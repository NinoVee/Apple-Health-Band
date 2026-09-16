import Foundation
import Combine

/// Turns raw band readings into Apple Health writes, and derives a local
/// estimate of exercise minutes / stand hours (metrics HealthKit reserves
/// for Apple Watch to write) so the rings still move when the paired band
/// is the only source of activity data.
///
/// Heuristics used, deliberately simple and documented rather than hidden:
/// - Exercise minutes accrue while heart rate is at/above
///   `exerciseHeartRateThreshold`.
/// - A stand "hour" is credited for any clock hour that saw an elevated
///   heart rate or a cadence reading (i.e. the wearer was up and moving).
/// - Step count is cadence (steps/min) integrated over the time since the
///   previous cadence sample.
@MainActor
final class ActivitySyncCoordinator: ObservableObject {
    @Published private(set) var estimatedExerciseMinutes: Double = 0
    @Published private(set) var estimatedStandHours: Int = 0

    let exerciseHeartRateThreshold: Double = 100
    let spo2WriteInterval: TimeInterval = 5 * 60

    private let bluetooth: BandBluetoothManager
    private let healthKit: HealthKitManager
    private var cancellables = Set<AnyCancellable>()

    private var lastCadenceTimestamp: Date?
    private var lastExerciseCreditTimestamp: Date?
    private var standHoursCredited = Set<Int>()
    private var lastSpo2WriteTime: Date?
    private var currentDay = Calendar.current.startOfDay(for: .now)

    init(bluetooth: BandBluetoothManager, healthKit: HealthKitManager) {
        self.bluetooth = bluetooth
        self.healthKit = healthKit
        bluetooth.readingPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] reading in self?.handle(reading) }
            .store(in: &cancellables)
    }

    private func handle(_ reading: SensorReading) {
        resetIfNewDay()
        switch reading.kind {
        case .heartRate:
            healthKit.write(reading: reading)
            healthKit.todayActivity.latestHeartRate = reading.value
            creditExerciseAndStand(for: reading)
        case .spo2:
            let due = lastSpo2WriteTime.map { Date().timeIntervalSince($0) > spo2WriteInterval } ?? true
            if due {
                lastSpo2WriteTime = Date()
                healthKit.write(reading: reading)
            }
        case .steps:
            creditStepsFromCadence(reading)
        case .distance:
            healthKit.write(reading: reading)
        case .calories, .battery:
            break
        }
        Task { await healthKit.refreshTodayActivity() }
    }

    private func creditExerciseAndStand(for reading: SensorReading) {
        let now = reading.timestamp
        if reading.value >= exerciseHeartRateThreshold {
            if let last = lastExerciseCreditTimestamp {
                let delta = now.timeIntervalSince(last) / 60.0
                if delta > 0, delta < 5 {
                    estimatedExerciseMinutes += delta
                }
            }
            creditStandHour(at: now)
        }
        lastExerciseCreditTimestamp = now
    }

    private func creditStepsFromCadence(_ reading: SensorReading) {
        let now = reading.timestamp
        defer { lastCadenceTimestamp = now }
        guard let last = lastCadenceTimestamp else { return }
        let minutesElapsed = now.timeIntervalSince(last) / 60.0
        guard minutesElapsed > 0, minutesElapsed < 5 else { return } // ignore gaps after a disconnect
        let steps = Int((reading.value * minutesElapsed).rounded())
        guard steps > 0 else { return }

        healthKit.writeStepCount(steps, start: last, end: now)
        let estimatedKcal = Double(steps) * 0.04 // rough steps-to-kcal estimate
        healthKit.write(reading: SensorReading(kind: .calories, value: estimatedKcal, unit: "kcal", timestamp: now))
        creditStandHour(at: now)
    }

    private func creditStandHour(at date: Date) {
        standHoursCredited.insert(Calendar.current.component(.hour, from: date))
        estimatedStandHours = standHoursCredited.count
    }

    private func resetIfNewDay() {
        let today = Calendar.current.startOfDay(for: .now)
        guard today != currentDay else { return }
        currentDay = today
        estimatedExerciseMinutes = 0
        estimatedStandHours = 0
        standHoursCredited.removeAll()
    }
}
