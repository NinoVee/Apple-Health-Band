import XCTest
import CoreBluetooth
@testable import AppleHealthBand

final class SensorParserTests: XCTestCase {
    func testHeartRateUInt8Format() {
        let data = Data([0x00, 72]) // flags: uint8 format, value 72 bpm
        let readings = SensorParsers.heartRate(from: data)
        XCTAssertEqual(readings.count, 1)
        XCTAssertEqual(readings.first?.kind, .heartRate)
        XCTAssertEqual(readings.first?.value, 72)
    }

    func testHeartRateUInt16Format() {
        let data = Data([0x01, 0x88, 0x00]) // flags: uint16 format, value 136 little-endian
        let readings = SensorParsers.heartRate(from: data)
        XCTAssertEqual(readings.first?.value, 136)
    }

    func testHeartRateWithRRIntervals() {
        // flags: uint8 format, RR-interval present (bit 4, 0x10); hr=70;
        // RR#1 raw 1024 (1/1024s units) -> 1000.0ms; RR#2 raw 960 -> 937.5ms
        let data = Data([0x10, 70, 0x00, 0x04, 0xC0, 0x03])
        let readings = SensorParsers.heartRate(from: data)

        XCTAssertEqual(readings.count, 3)
        XCTAssertEqual(readings[0].kind, .heartRate)
        XCTAssertEqual(readings[0].value, 70)
        XCTAssertEqual(readings[1].kind, .rrInterval)
        XCTAssertEqual(readings[1].value, 1000.0, accuracy: 0.001)
        XCTAssertEqual(readings[2].kind, .rrInterval)
        XCTAssertEqual(readings[2].value, 937.5, accuracy: 0.001)
    }

    func testBodyTemperatureCelsius() {
        // flags: Celsius, no optional fields; mantissa 365, exponent -1 -> 36.5°C
        let data = Data([0x00, 0x6D, 0x01, 0x00, 0xFF])
        let reading = SensorParsers.bodyTemperature(from: data)
        XCTAssertEqual(reading?.kind, .bodyTemperature)
        XCTAssertEqual(reading?.value, 36.5, accuracy: 0.001)
    }

    func testBodyTemperatureFahrenheitConvertsToCelsius() {
        // flags: Fahrenheit (bit 0); mantissa 986, exponent -1 -> 98.6°F -> 37.0°C
        let data = Data([0x01, 0xDA, 0x03, 0x00, 0xFF])
        let reading = SensorParsers.bodyTemperature(from: data)
        XCTAssertEqual(reading?.value, 37.0, accuracy: 0.01)
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

    func testBloodPressureWithPulseRate() {
        // flags: mmHg, no time stamp, pulse rate present (bit 2, 0x04);
        // systolic 120 (SFLOAT mantissa 120, exponent 0), diastolic 80,
        // MAP 93 (parsed but unused), pulse rate 65.
        let data = Data([0x04, 0x78, 0x00, 0x50, 0x00, 0x5D, 0x00, 0x41, 0x00])
        let readings = SensorParsers.bloodPressure(from: data)

        XCTAssertEqual(readings.count, 3)
        XCTAssertEqual(readings[0].kind, .bloodPressureSystolic)
        XCTAssertEqual(readings[0].value, 120.0, accuracy: 0.001)
        XCTAssertEqual(readings[1].kind, .bloodPressureDiastolic)
        XCTAssertEqual(readings[1].value, 80.0, accuracy: 0.001)
        XCTAssertEqual(readings[2].kind, .heartRate)
        XCTAssertEqual(readings[2].value, 65.0, accuracy: 0.001)
    }

    func testBloodPressureKPaConvertsToMmHg() {
        // flags: kPa units (bit 0), no optional fields;
        // systolic 16 kPa, diastolic 11 kPa, MAP 13 kPa (unused)
        let data = Data([0x01, 0x10, 0x00, 0x0B, 0x00, 0x0D, 0x00])
        let readings = SensorParsers.bloodPressure(from: data)

        XCTAssertEqual(readings.count, 2)
        XCTAssertEqual(readings[0].value, 16.0 * 7.500617, accuracy: 0.01)
        XCTAssertEqual(readings[1].value, 11.0 * 7.500617, accuracy: 0.01)
    }

    func testUnknownCharacteristicDecodesToEmpty() {
        let readings = SensorParsers.decode(characteristicUUID: CBUUID(string: "FFFF"), data: Data([1, 2, 3]))
        XCTAssertTrue(readings.isEmpty)
    }
}
