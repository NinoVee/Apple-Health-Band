import SwiftUI

struct GoalsView: View {
    @EnvironmentObject var goalsStore: GoalsStore

    var body: some View {
        NavigationStack {
            Form {
                Section("Move") {
                    Stepper(value: $goalsStore.goals.moveCalories, in: 100...2000, step: 50) {
                        Text("\(Int(goalsStore.goals.moveCalories)) kcal")
                    }
                }
                Section("Exercise") {
                    Stepper(value: $goalsStore.goals.exerciseMinutes, in: 5...180, step: 5) {
                        Text("\(Int(goalsStore.goals.exerciseMinutes)) min")
                    }
                }
                Section("Stand") {
                    Stepper(value: $goalsStore.goals.standHours, in: 1...24, step: 1) {
                        Text("\(Int(goalsStore.goals.standHours)) hrs")
                    }
                }
                Section {
                    Button("Reset to Apple defaults", role: .destructive) {
                        goalsStore.goals = .default
                    }
                }
            }
            .navigationTitle("Goals")
        }
    }
}
