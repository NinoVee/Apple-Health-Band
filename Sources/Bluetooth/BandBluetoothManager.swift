import Foundation
import CoreBluetooth
import Combine

/// Scans for, connects to, and streams sensor data from any number of
/// simultaneous Bluetooth LE health accessories — a wrist band, a
/// smart scale, a blood pressure cuff, whatever implements the standard
/// GATT profiles in `GattProfiles.swift`. CoreBluetooth itself has no
/// problem holding several peripheral connections at once, so this is a
/// small fleet manager rather than a single-device wrapper: each
/// peripheral gets its own connection state, but all of them publish
/// into the same `latestReadings`/`readingPublisher`, since the sensor
/// kinds a band, scale, and cuff report don't normally overlap (the one
/// exception, heart rate, just reflects whichever device reported most
/// recently — the same "latest reading wins" rule already used
/// everywhere else in the app).
@MainActor
final class BandBluetoothManager: NSObject, ObservableObject {
    enum ConnectionState: Equatable {
        case connecting
        case connected
        case disconnected
        case failed(String)
    }

    @Published private(set) var isBluetoothReady = false
    @Published private(set) var isScanning = false
    @Published private(set) var discoveredDevices: [BandDevice] = []
    @Published private(set) var connectedDevices: [BandDevice] = []
    @Published private(set) var connectionStates: [UUID: ConnectionState] = [:]
    @Published private(set) var latestReadings: [SensorKind: SensorReading] = [:]
    @Published private(set) var heartRateHistory: [SensorReading] = []

    let readingPublisher = PassthroughSubject<SensorReading, Never>()

    private var central: CBCentralManager!
    private var peripheralsByID: [UUID: CBPeripheral] = [:]

    private var pairedPeripheralIDs: Set<UUID> {
        get {
            let strings = UserDefaults.standard.stringArray(forKey: "pairedPeripheralIDs") ?? []
            return Set(strings.compactMap(UUID.init))
        }
        set {
            UserDefaults.standard.set(newValue.map(\.uuidString), forKey: "pairedPeripheralIDs")
        }
    }

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func startScanning() {
        guard isBluetoothReady else { return }
        discoveredDevices.removeAll()
        isScanning = true
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScanning() {
        central.stopScan()
        isScanning = false
    }

    /// Connects an additional device without disturbing any devices
    /// already connected — call this once per accessory (band, scale,
    /// cuff, ...) you want reporting into the app at the same time.
    func connect(to device: BandDevice) {
        stopScanning()
        peripheralsByID[device.id] = device.peripheral
        device.peripheral.delegate = self
        connectionStates[device.id] = .connecting
        central.connect(device.peripheral, options: nil)
    }

    func disconnect(_ device: BandDevice) {
        pairedPeripheralIDs.remove(device.id)
        guard let peripheral = peripheralsByID[device.id] else { return }
        central.cancelPeripheralConnection(peripheral)
    }

    func connectionState(for device: BandDevice) -> ConnectionState {
        connectionStates[device.id] ?? .disconnected
    }

    private func attemptReconnectAll() {
        let ids = Array(pairedPeripheralIDs)
        guard !ids.isEmpty else { return }
        for peripheral in central.retrievePeripherals(withIdentifiers: ids) {
            peripheralsByID[peripheral.identifier] = peripheral
            peripheral.delegate = self
            connectionStates[peripheral.identifier] = .connecting
            central.connect(peripheral, options: nil)
        }
    }

    fileprivate func record(_ reading: SensorReading) {
        latestReadings[reading.kind] = reading
        if reading.kind == .heartRate {
            heartRateHistory.append(reading)
            if heartRateHistory.count > 60 {
                heartRateHistory.removeFirst(heartRateHistory.count - 60)
            }
        }
        readingPublisher.send(reading)
    }
}

extension BandBluetoothManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        Task { @MainActor in
            isBluetoothReady = state == .poweredOn
            if isBluetoothReady {
                attemptReconnectAll()
            } else {
                connectedDevices.removeAll()
                connectionStates = connectionStates.mapValues { _ in .disconnected }
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "Unknown device"
        let device = BandDevice(id: peripheral.identifier, name: name, rssi: RSSI.intValue, peripheral: peripheral)
        Task { @MainActor in
            if let index = discoveredDevices.firstIndex(where: { $0.id == device.id }) {
                discoveredDevices[index] = device
            } else {
                discoveredDevices.append(device)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let identifier = peripheral.identifier
        let name = peripheral.name ?? "Device"
        Task { @MainActor in
            pairedPeripheralIDs.insert(identifier)
            let device = discoveredDevices.first(where: { $0.id == identifier })
                ?? BandDevice(id: identifier, name: name, rssi: 0, peripheral: peripheral)
            if let index = connectedDevices.firstIndex(where: { $0.id == identifier }) {
                connectedDevices[index] = device
            } else {
                connectedDevices.append(device)
            }
            connectionStates[identifier] = .connected
            peripheral.discoverServices(GattService.standard + VendorService.custom)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let identifier = peripheral.identifier
        let message = error?.localizedDescription ?? "Connection failed"
        Task { @MainActor in
            connectionStates[identifier] = .failed(message)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let identifier = peripheral.identifier
        Task { @MainActor in
            connectedDevices.removeAll { $0.id == identifier }
            connectionStates[identifier] = .disconnected
        }
    }
}

extension BandBluetoothManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            if characteristic.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: characteristic)
            } else if characteristic.properties.contains(.read) {
                peripheral.readValue(for: characteristic)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        let uuid = characteristic.uuid
        let readings = SensorParsers.decode(characteristicUUID: uuid, data: data)
        guard !readings.isEmpty else { return }
        Task { @MainActor in
            for reading in readings {
                record(reading)
            }
        }
    }
}
