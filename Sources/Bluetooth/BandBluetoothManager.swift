import Foundation
import CoreBluetooth
import Combine

/// Scans for, connects to, and streams sensor data from a Bluetooth LE
/// smart band. Publishes decoded readings via `readingPublisher` for
/// `ActivitySyncCoordinator` to relay into Apple Health, and keeps the
/// latest value per sensor plus a short heart-rate history for the UI.
@MainActor
final class BandBluetoothManager: NSObject, ObservableObject {
    enum ConnectionState: Equatable {
        case disconnected
        case scanning
        case connecting
        case connected
        case failed(String)
    }

    @Published private(set) var isBluetoothReady = false
    @Published private(set) var discoveredDevices: [BandDevice] = []
    @Published private(set) var connectedDevice: BandDevice?
    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var latestReadings: [SensorKind: SensorReading] = [:]
    @Published private(set) var heartRateHistory: [SensorReading] = []

    let readingPublisher = PassthroughSubject<SensorReading, Never>()

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?

    private var pairedPeripheralID: UUID? {
        get { UserDefaults.standard.string(forKey: "pairedPeripheralID").flatMap(UUID.init) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: "pairedPeripheralID") }
    }

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func startScanning() {
        guard isBluetoothReady else { return }
        discoveredDevices.removeAll()
        connectionState = .scanning
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScanning() {
        central.stopScan()
        if connectionState == .scanning { connectionState = .disconnected }
    }

    func connect(to device: BandDevice) {
        stopScanning()
        connectionState = .connecting
        peripheral = device.peripheral
        peripheral?.delegate = self
        central.connect(device.peripheral, options: nil)
    }

    func disconnect() {
        pairedPeripheralID = nil
        guard let peripheral else { return }
        central.cancelPeripheralConnection(peripheral)
    }

    private func attemptReconnect() {
        guard let id = pairedPeripheralID else { return }
        guard let match = central.retrievePeripherals(withIdentifiers: [id]).first else { return }
        peripheral = match
        match.delegate = self
        connectionState = .connecting
        central.connect(match, options: nil)
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
                attemptReconnect()
            } else {
                connectionState = .disconnected
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "Unknown band"
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
        let name = peripheral.name ?? "Band"
        Task { @MainActor in
            pairedPeripheralID = identifier
            connectedDevice = discoveredDevices.first(where: { $0.id == identifier })
                ?? BandDevice(id: identifier, name: name, rssi: 0, peripheral: peripheral)
            connectionState = .connected
            peripheral.discoverServices(GattService.standard + VendorService.custom)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let message = error?.localizedDescription ?? "Connection failed"
        Task { @MainActor in
            connectionState = .failed(message)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            connectedDevice = nil
            connectionState = .disconnected
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
