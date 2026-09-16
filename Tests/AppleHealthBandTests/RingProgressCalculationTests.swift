import XCTest
@testable import AppleHealthBand

final class RingProgressCalculationTests: XCTestCase {
    func testMoveProgressCappedAt150Percent() {
        var activity = DailyActivity()
        activity.activeEnergy = 1000
        XCTAssertEqual(activity.moveProgress(goal: 500), 1.5)
    }

    func testMoveProgressPartial() {
        var activity = DailyActivity()
        activity.activeEnergy = 250
        XCTAssertEqual(activity.moveProgress(goal: 500), 0.5)
    }

    func testMoveProgressZeroGoalIsZero() {
        let activity = DailyActivity()
        XCTAssertEqual(activity.moveProgress(goal: 0), 0)
    }

    func testGoalsDefaultMatchesAppleDefaults() {
        XCTAssertEqual(ActivityGoals.default.moveCalories, 500)
        XCTAssertEqual(ActivityGoals.default.exerciseMinutes, 30)
        XCTAssertEqual(ActivityGoals.default.standHours, 12)
    }
}
