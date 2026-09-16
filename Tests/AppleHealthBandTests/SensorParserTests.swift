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

    func testUnknownCharacteristicDecodesToEmpty() {
        let readings = SensorParsers.decode(characteristicUUID: CBUUID(string: "FFFF"), data: Data([1, 2, 3]))
        XCTAssertTrue(readings.isEmpty)
    }
}
