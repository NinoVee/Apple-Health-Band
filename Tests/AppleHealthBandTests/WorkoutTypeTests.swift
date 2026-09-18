import XCTest
@testable import AppleHealthBand

final class WorkoutTypeTests: XCTestCase {
    func testAllCasesHaveDistinctHealthKitActivityTypes() {
        let activityTypes = WorkoutType.allCases.map(\.healthKitActivityType)
        XCTAssertEqual(Set(activityTypes).count, WorkoutType.allCases.count)
    }

    func testYogaThresholdIsLowerThanBoxing() {
        XCTAssertLessThan(WorkoutType.yoga.exerciseHeartRateThreshold, WorkoutType.boxing.exerciseHeartRateThreshold)
    }

    func testScanningIntervalsAreAllPositive() {
        for type in WorkoutType.allCases {
            XCTAssertGreaterThan(type.scanningInterval, 0)
        }
    }
}
