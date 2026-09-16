import Foundation
import Combine

struct ActivityGoals: Codable, Equatable {
    var moveCalories: Double
    var exerciseMinutes: Double
    var standHours: Double

    static let `default` = ActivityGoals(moveCalories: 500, exerciseMinutes: 30, standHours: 12)
}

@MainActor
final class GoalsStore: ObservableObject {
    @Published var goals: ActivityGoals {
        didSet { persist() }
    }

    private let defaultsKey = "activityGoals"

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(ActivityGoals.self, from: data) {
            goals = decoded
        } else {
            goals = .default
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(goals) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
