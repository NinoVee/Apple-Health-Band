import XCTest
@testable import AppleHealthBand

final class ScaleEntryTests: XCTestCase {
    func testComputedBMI() {
        // 70 kg at 175 cm -> BMI 22.86
        let bmi = ScaleEntry.computedBMI(weightKg: 70, heightCm: 175)
        XCTAssertEqual(bmi ?? 0, 22.857, accuracy: 0.01)
    }

    func testComputedBMIZeroHeightIsNil() {
        XCTAssertNil(ScaleEntry.computedBMI(weightKg: 70, heightCm: 0))
    }
}
