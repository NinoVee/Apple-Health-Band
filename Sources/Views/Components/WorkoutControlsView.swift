import SwiftUI

/// Apple Fitness-style highlighter-green workout controls for the Today
/// tab: a grid of workout-type buttons when idle, or a live Start/Pause/
/// End card once `WorkoutSessionManager` has an active session.
struct WorkoutControlsView: View {
    @EnvironmentObject var workoutSession: WorkoutSessionManager

    var body: some View {
        if workoutSession.activeWorkout != nil {
            ActiveWorkoutCard()
        } else {
            WorkoutTypeGrid()
        }
    }
}

/// The highlighter-green accent used across Apple's own Fitness app for
/// its primary workout-start buttons.
enum WorkoutTheme {
    static let highlighterGreen = Color(red: 0.68, green: 1.0, blue: 0.18)
}

private struct WorkoutTypeGrid: View {
    @EnvironmentObject var workoutSession: WorkoutSessionManager
    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Start a Workout")
                .font(.headline)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(WorkoutType.allCases) { type in
                    Button {
                        workoutSession.start(type)
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: type.systemImage)
                                .font(.title2)
                            Text(type.label)
                                .font(.caption.bold())
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundStyle(.black)
                        .background(WorkoutTheme.highlighterGreen, in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                }
            }

            if let error = workoutSession.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }
}

private struct ActiveWorkoutCard: View {
    @EnvironmentObject var workoutSession: WorkoutSessionManager

    var body: some View {
        if let type = workoutSession.activeWorkout {
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: type.systemImage)
                        .font(.title2)
                        .foregroundStyle(WorkoutTheme.highlighterGreen)
                    Text(type.label)
                        .font(.title3.bold())
                    Spacer()
                    Text(formattedElapsed)
                        .font(.title3.monospacedDigit().bold())
                }

                HStack(spacing: 24) {
                    stat("Calories", value: "\(Int(workoutSession.activeEnergy))", unit: "kcal")
                    stat("Heart Rate", value: workoutSession.averageHeartRate.map { "\(Int($0))" } ?? "--", unit: "bpm")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 16) {
                    Button(workoutSession.isPaused ? "Resume" : "Pause") {
                        if workoutSession.isPaused {
                            workoutSession.resume()
                        } else {
                            workoutSession.pause()
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(WorkoutTheme.highlighterGreen)

                    Button("End Workout") {
                        workoutSession.end()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }

                if let error = workoutSession.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private var formattedElapsed: String {
        let total = Int(workoutSession.elapsedTime)
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    private func stat(_ title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.title2.bold())
            Text(unit).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
