import Foundation

/// Today's activity totals, as read back from Apple Health (see
/// `HealthKitManager.refreshTodayActivity`). Progress values are capped at
/// 150% so an over-achieved ring renders like Apple's own Activity rings.
struct DailyActivity: Equatable {
    var activeEnergy: Double = 0
    var exerciseMinutes: Double = 0
    var standHours: Int = 0
    var steps: Int = 0
    var distanceMeters: Double = 0
    var latestHeartRate: Double?

    func moveProgress(goal: Double) -> Double {
        Self.progress(activeEnergy, goal: goal)
    }

    static func progress(_ value: Double, goal: Double) -> Double {
        guard goal > 0 else { return 0 }
        return min(value / goal, 1.5)
    }
}
