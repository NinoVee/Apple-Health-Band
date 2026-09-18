import Foundation
import CoreBluetooth

/// Standard Bluetooth SIG GATT services this app scans for and subscribes
/// to out of the box. Many bands only implement a subset of these.
enum GattService {
    static let heartRate = CBUUID(string: "180D")
    static let battery = CBUUID(string: "180F")
    static let runningSpeedCadence = CBUUID(string: "1814")
    static let pulseOximeter = CBUUID(string: "1822")
    static let bodyComposition = CBUUID(string: "181B")
    static let healthThermometer = CBUUID(string: "1809")
    static let bloodPressure = CBUUID(string: "1810")

    static let standard: [CBUUID] = [
        heartRate, battery, runningSpeedCadence, pulseOximeter, bodyComposition, healthThermometer, bloodPressure
    ]
}

enum GattCharacteristic {
    static let heartRateMeasurement = CBUUID(string: "2A37")
    static let batteryLevel = CBUUID(string: "2A19")
    static let rscMeasurement = CBUUID(string: "2A53")
    static let pulseOximeterMeasurement = CBUUID(string: "2A5E")
    static let bodyCompositionMeasurement = CBUUID(string: "2A9C")
    static let temperatureMeasurement = CBUUID(string: "2A1C")
    static let bloodPressureMeasurement = CBUUID(string: "2A35")
}

/// Many bands expose steps, sleep, and SpO2 through vendor-specific
/// services instead of (or in addition to) the standard GATT profiles
/// above. To support your exact band, add its service/characteristic
/// UUIDs here and a matching `VendorSensorDecoder`, then include it in
/// `BandBluetoothManager`'s scan/discovery list.
///
/// The entries below are VWAR MG's actual services, found with the
/// LightBlue sniffer app — listed here so `discoverServices` can see
/// them at all (it only returns services matching the UUIDs it's
/// asked for), even though there's no decoder for them yet. Nothing
/// is known about VWAR's byte-level protocol on these — that's what
/// `SensorParsers`'s debug logging in `decode(characteristicUUID:data:)`
/// is for: watch Xcode's console while triggering a known action on
/// the band (or in its own "G Band" app) to see the real bytes.
enum VendorService {
    static let vwarMG: [CBUUID] = [
        CBUUID(string: "AE40"),
        CBUUID(string: "AE00"),
        CBUUID(string: "FEE7"),
        CBUUID(string: "F0020001-0451-4000-B000-000000000000"),
        CBUUID(string: "F0030001-0451-4000-B000-000000000000"),
        CBUUID(string: "F0080001-0451-4000-B000-000000000000")
    ]

    static let custom: [CBUUID] = vwarMG
}

protocol VendorSensorDecoder {
    var serviceUUID: CBUUID { get }
    var characteristicUUIDs: [CBUUID] { get }
    func decode(characteristic: CBUUID, data: Data) -> [SensorReading]
}
