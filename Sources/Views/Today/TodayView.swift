import SwiftUI

struct TodayView: View {
    @EnvironmentObject var healthKit: HealthKitManager
    @EnvironmentObject var coordinator: ActivitySyncCoordinator
    @EnvironmentObject var goalsStore: GoalsStore

    private var exerciseMinutes: Double {
        max(healthKit.todayActivity.exerciseMinutes, coordinator.estimatedExerciseMinutes)
    }

    private var standHours: Int {
        max(healthKit.todayActivity.standHours, coordinator.estimatedStandHours)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    ActivityRingsView(
                        moveProgress: healthKit.todayActivity.moveProgress(goal: goalsStore.goals.moveCalories),
                        exerciseProgress: DailyActivity.progress(exerciseMinutes, goal: goalsStore.goals.exerciseMinutes),
                        standProgress: DailyActivity.progress(Double(standHours), goal: goalsStore.goals.standHours)
                    )
                    .padding(.top, 12)

                    HStack(spacing: 16) {
                        StatCardView(
                            title: "Move",
                            value: "\(Int(healthKit.todayActivity.activeEnergy))",
                            unit: "kcal",
                            color: RingColors.move.first ?? .pink
                        )
                        StatCardView(
                            title: "Exercise",
                            value: "\(Int(exerciseMinutes))",
                            unit: "min",
                            color: RingColors.exercise.first ?? .green
                        )
                        StatCardView(
                            title: "Stand",
                            value: "\(standHours)",
                            unit: "hrs",
                            color: RingColors.stand.first ?? .cyan
                        )
                    }

                    HStack(spacing: 16) {
                        StatCardView(title: "Steps", value: "\(healthKit.todayActivity.steps)", unit: "steps", color: .orange)
                        StatCardView(
                            title: "Distance",
                            value: String(format: "%.2f", healthKit.todayActivity.distanceMeters / 1000),
                            unit: "km",
                            color: .purple
                        )
                        StatCardView(
                            title: "Heart Rate",
                            value: healthKit.todayActivity.latestHeartRate.map { "\(Int($0))" } ?? "--",
                            unit: "bpm",
                            color: .pink
                        )
                    }

                    WorkoutControlsView()

                    DeviceStatusCard()
                }
                .padding()
            }
            .navigationTitle("Today")
            .task {
                await healthKit.refreshTodayActivity()
            }
        }
    }
}
