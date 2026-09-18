import Foundation
import HealthKit
import Combine

/// Drives a live `HKWorkoutSession` from BLE sensor data. `HKWorkoutSession`
/// was watchOS-only before iOS 26, when Apple added iOS support
/// specifically so third-party accessories — like this band, not just an
/// Apple Watch — can record a real workout to Health. Ending a session
/// here produces an actual `HKWorkout` (duration, calories, average
/// heart rate) that shows up in the Fitness/Health apps like any other
/// recorded workout, not just a pile of disconnected samples.
///
/// "Calibration" per exercise happens two ways: `WorkoutType.healthKitActivityType`
/// tells HealthKit which activity this is, so *Health's own* calorie/zone
/// algorithms calibrate to it (the same bpm means a different calorie
/// burn for running vs. yoga); and starting a workout sets
/// `BandBluetoothManager`'s non-notify re-poll cadence to
/// `WorkoutType.scanningInterval`. Neither of those makes a physical
/// sensor sample faster — that's the connected device's firmware, not
/// something this app controls.
@MainActor
final class WorkoutSessionManager: NSObject, ObservableObject {
    @Published private(set) var activeWorkout: WorkoutType?
    @Published private(set) var isPaused = false
    @Published private(set) var elapsedTime: TimeInterval = 0
    @Published private(set) var activeEnergy: Double = 0
    @Published private(set) var averageHeartRate: Double?
    @Published var errorMessage: String?

    private let store: HKHealthStore
    private let bluetooth: BandBluetoothManager
    private var cancellables = Set<AnyCancellable>()

    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var startDate: Date?
    private var pauseStartedAt: Date?
    private var pausedAccumulated: TimeInterval = 0
    private var displayTimer: Timer?

    init(store: HKHealthStore, bluetooth: BandBluetoothManager) {
        self.store = store
        self.bluetooth = bluetooth
        super.init()
        bluetooth.readingPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] reading in self?.feed(reading) }
            .store(in: &cancellables)
    }

    func start(_ type: WorkoutType) {
        guard HKHealthStore.isHealthDataAvailable() else {
            errorMessage = "Health data isn't available on this device."
            return
        }
        guard activeWorkout == nil else { return }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = type.healthKitActivityType
        configuration.locationType = .unknown

        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self

            self.session = session
            self.builder = builder
            activeWorkout = type
            isPaused = false
            elapsedTime = 0
            activeEnergy = 0
            averageHeartRate = nil
            pausedAccumulated = 0
            pauseStartedAt = nil
            errorMessage = nil

            let now = Date()
            startDate = now
            session.startActivity(with: now)

            Task { @MainActor in
                do {
                    _ = try await builder.beginCollection(at: now)
                } catch {
                    self.errorMessage = error.localizedDescription
                }
            }

            bluetooth.setScanningInterval(type.scanningInterval)
            startDisplayTimer()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func pause() {
        session?.pause()
    }

    func resume() {
        session?.resume()
    }

    func end() {
        session?.end()
    }

    private func feed(_ reading: SensorReading) {
        guard let builder, activeWorkout != nil else { return }
        let identifier: HKQuantityTypeIdentifier
        let unit: HKUnit
        switch reading.kind {
        case .heartRate:
            identifier = .heartRate
            unit = HKUnit.count().unitDivided(by: .minute())
        case .calories:
            identifier = .activeEnergyBurned
            unit = .kilocalorie()
        case .distance:
            identifier = .distanceWalkingRunning
            unit = .meter()
        default:
            return
        }
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else { return }
        let quantity = HKQuantity(unit: unit, doubleValue: reading.value)
        let sample = HKQuantitySample(type: quantityType, quantity: quantity, start: reading.timestamp, end: reading.timestamp)
        builder.add([sample]) { _, _ in }
    }

    private func startDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard let startDate, !isPaused else { return }
        elapsedTime = Date().timeIntervalSince(startDate) - pausedAccumulated
    }

    private func cleanUpAfterEnd() {
        displayTimer?.invalidate()
        displayTimer = nil
        bluetooth.setScanningInterval(nil)
        session = nil
        builder = nil
        startDate = nil
        pauseStartedAt = nil
        pausedAccumulated = 0
        activeWorkout = nil
        isPaused = false
    }
}

extension WorkoutSessionManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            switch toState {
            case .paused:
                isPaused = true
                pauseStartedAt = date
            case .running:
                if let pauseStartedAt {
                    pausedAccumulated += date.timeIntervalSince(pauseStartedAt)
                    self.pauseStartedAt = nil
                }
                isPaused = false
            case .ended:
                guard let builder else { return }
                do {
                    _ = try await builder.endCollection(at: date)
                    _ = try await builder.finishWorkout()
                } catch {
                    errorMessage = error.localizedDescription
                }
                cleanUpAfterEnd()
            default:
                break
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            errorMessage = error.localizedDescription
            cleanUpAfterEnd()
        }
    }
}

extension WorkoutSessionManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Task { @MainActor in
            for type in collectedTypes {
                guard let quantityType = type as? HKQuantityType else { continue }
                guard let statistics = workoutBuilder.statistics(for: quantityType) else { continue }
                if quantityType == HKQuantityType.quantityType(forIdentifier: .heartRate) {
                    averageHeartRate = statistics.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                } else if quantityType == HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
                    activeEnergy = statistics.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                }
            }
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
