import SwiftUI

/// The Move/Exercise/Stand goal editors, as `Form` sections rather than
/// their own screen — embedded directly in `SettingsView`.
struct GoalsSections: View {
    @EnvironmentObject var goalsStore: GoalsStore

    var body: some View {
        Group {
            Section("Move Goal") {
                Stepper(value: $goalsStore.goals.moveCalories, in: 100...2000, step: 50) {
                    Text("\(Int(goalsStore.goals.moveCalories)) kcal")
                }
            }
            Section("Exercise Goal") {
                Stepper(value: $goalsStore.goals.exerciseMinutes, in: 5...180, step: 5) {
                    Text("\(Int(goalsStore.goals.exerciseMinutes)) min")
                }
            }
            Section("Stand Goal") {
                Stepper(value: $goalsStore.goals.standHours, in: 1...24, step: 1) {
                    Text("\(Int(goalsStore.goals.standHours)) hrs")
                }
            }
            Section {
                Button("Reset goals to Apple defaults", role: .destructive) {
                    goalsStore.goals = .default
                }
            }
        }
    }
}
