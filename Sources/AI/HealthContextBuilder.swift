import Foundation

/// Builds the plain-text Health summary sent alongside each chat request
/// — never raw HealthKit samples, just the same aggregate numbers already
/// shown on the Today/Sensors tabs. Kept as a separate, inspectable step
/// so it's obvious exactly what leaves the device.
@MainActor
enum HealthContextBuilder {
    static func summary(
        healthKit: HealthKitManager,
        bluetooth: BandBluetoothManager,
        coordinator: ActivitySyncCoordinator
    ) -> String {
        let activity = healthKit.todayActivity
        var lines: [String] = ["Today's activity, from Apple Health (combines this band with any other source, e.g. Apple Watch):"]

        lines.append("- Active energy: \(Int(activity.activeEnergy)) kcal")
        lines.append("- Exercise minutes: \(Int(max(activity.exerciseMinutes, coordinator.estimatedExerciseMinutes)))")
        lines.append("- Stand hours: \(max(activity.standHours, coordinator.estimatedStandHours))")
        lines.append("- Steps: \(activity.steps)")
        lines.append("- Distance: \(String(format: "%.2f", activity.distanceMeters / 1000)) km")

        if let heartRate = activity.latestHeartRate {
            lines.append("- Latest heart rate: \(Int(heartRate)) bpm")
        }
        if let hrv = coordinator.latestHRV {
            lines.append("- Heart rate variability (SDNN): \(Int(hrv)) ms")
        }
        if let spo2 = bluetooth.latestReadings[.spo2] {
            lines.append("- Blood oxygen (SpO2): \(Int(spo2.value))%")
        }
        if let temperature = bluetooth.latestReadings[.bodyTemperature] {
            lines.append("- Body temperature: \(String(format: "%.1f", temperature.value))°C")
        }
        if let fat = bluetooth.latestReadings[.bodyFatPercentage] {
            lines.append("- Body fat: \(String(format: "%.1f", fat.value))%")
        }
        if let weight = bluetooth.latestReadings[.bodyMass] {
            lines.append("- Weight: \(String(format: "%.1f", weight.value)) kg")
        }
        if let leanMass = bluetooth.latestReadings[.leanBodyMass] {
            lines.append("- Lean body mass: \(String(format: "%.1f", leanMass.value)) kg")
        }

        return lines.joined(separator: "\n")
    }
}
