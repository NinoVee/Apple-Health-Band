import XCTest
import CoreBluetooth
@testable import AppleHealthBand

final class SensorParserTests: XCTestCase {
    func testHeartRateUInt8Format() {
        let data = Data([0x00, 72]) // flags: uint8 format, value 72 bpm
        let reading = SensorParsers.heartRate(from: data)
        XCTAssertEqual(reading?.kind, .heartRate)
        XCTAssertEqual(reading?.value, 72)
    }

    func testHeartRateUInt16Format() {
        let data = Data([0x01, 0x88, 0x00]) // flags: uint16 format, value 136 little-endian
        let reading = SensorParsers.heartRate(from: data)
        XCTAssertEqual(reading?.value, 136)
    }

    func testBatteryLevel() {
        let data = Data([87])
        XCTAssertEqual(SensorParsers.batteryLevel(from: data)?.value, 87)
    }

    func testRSCCadence() {
        // flags: no stride length, no total distance; speed(2)=0; cadence=90
        let data = Data([0x00, 0x00, 0x00, 90])
        let readings = SensorParsers.rscCadenceAndDistance(from: data)
        XCTAssertEqual(readings.count, 1)
        XCTAssertEqual(readings.first?.kind, .steps)
        XCTAssertEqual(readings.first?.value, 90)
    }

    func testRSCCadenceWithDistance() {
        // flags: total distance present (bit 1); speed(2)=0; cadence=80;
        // total distance = 1000 (0x03E8, little-endian) -> 100.0 meters
        let data = Data([0x02, 0x00, 0x00, 80, 0xE8, 0x03, 0x00, 0x00])
        let readings = SensorParsers.rscCadenceAndDistance(from: data)
        XCTAssertEqual(readings.count, 2)
        XCTAssertEqual(readings.last?.kind, .distance)
        XCTAssertEqual(readings.last?.value, 100.0)
    }

    func testBodyCompositionFatFreeMassAndWeight() {
        // flags: fat-free mass present (bit 6, 0x0040) + weight present
        // (bit 10, 0x0400) = 0x0440, SI units; body fat 23.5% (raw 235);
        // fat-free mass 60.0kg (raw 12000 @ 0.005kg resolution);
        // weight 75.0kg (raw 15000 @ 0.005kg resolution).
        let data = Data([0x40, 0x04, 0xEB, 0x00, 0xE0, 0x2E, 0x98, 0x3A])
        let readings = SensorParsers.bodyComposition(from: data)

        XCTAssertEqual(readings.count, 3)
        XCTAssertEqual(readings[0].kind, .bodyFatPercentage)
        XCTAssertEqual(readings[0].value, 23.5, accuracy: 0.001)
        XCTAssertEqual(readings[1].kind, .leanBodyMass)
        XCTAssertEqual(readings[1].value, 60.0, accuracy: 0.001)
        XCTAssertEqual(readings[2].kind, .bodyMass)
        XCTAssertEqual(readings[2].value, 75.0, accuracy: 0.001)
    }

    func testBodyCompositionBodyFatOnly() {
        // flags: no optional fields; body fat 18.2% (raw 182)
        let data = Data([0x00, 0x00, 0xB6, 0x00])
        let readings = SensorParsers.bodyComposition(from: data)
        XCTAssertEqual(readings.count, 1)
        XCTAssertEqual(readings.first?.kind, .bodyFatPercentage)
        XCTAssertEqual(readings.first?.value, 18.2, accuracy: 0.001)
    }

    func testUnknownCharacteristicDecodesToEmpty() {
        let readings = SensorParsers.decode(characteristicUUID: CBUUID(string: "FFFF"), data: Data([1, 2, 3]))
        XCTAssertTrue(readings.isEmpty)
    }
}
