import Foundation
import HealthKit

/// Bridges band sensor data into Apple Health and reads it back so the
/// app's rings and trends reflect the same combined totals Health shows
/// across every source (this app, Apple Watch, other apps).
///
/// Important: `appleExerciseTime`, `appleStandTime`, and `appleStandHour`
/// can only be *written* by Apple Watch — HealthKit rejects third-party
/// writes to those types. This app reads them (to show real Watch data
/// when available) but otherwise falls back to its own on-device
/// estimate computed by `ActivitySyncCoordinator` from band heart-rate
/// and movement data. Steps, distance, active energy, heart rate, and
/// blood oxygen are ordinary writable types and sync for real.
@MainActor
final class HealthKitManager: ObservableObject {
    static let isHealthDataAvailable = HKHealthStore.isHealthDataAvailable()

    @Published private(set) var isAuthorized = false
    @Published var todayActivity = DailyActivity()

    let store = HKHealthStore()

    private let writeTypes: Set<HKSampleType> = {
        let ids: [HKQuantityTypeIdentifier] = [.heartRate, .stepCount, .activeEnergyBurned, .distanceWalkingRunning, .oxygenSaturation]
        return Set(ids.compactMap { HKQuantityType.quantityType(forIdentifier: $0) })
    }()

    private let readTypes: Set<HKObjectType> = {
        let quantityIDs: [HKQuantityTypeIdentifier] = [.heartRate, .stepCount, .activeEnergyBurned, .distanceWalkingRunning, .oxygenSaturation, .appleExerciseTime]
        var set = Set<HKObjectType>(quantityIDs.compactMap { HKQuantityType.quantityType(forIdentifier: $0) })
        if let standType = HKCategoryType.categoryType(forIdentifier: .appleStandHour) {
            set.insert(standType)
        }
        set.insert(HKObjectType.activitySummaryType())
        return set
    }()

    func requestAuthorization() async {
        guard Self.isHealthDataAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            isAuthorized = true
            enableBackgroundDelivery()
            await refreshTodayActivity()
        } catch {
            isAuthorized = false
        }
    }

    private func enableBackgroundDelivery() {
        for type in readTypes.compactMap({ $0 as? HKSampleType }) {
            store.enableBackgroundDelivery(for: type, frequency: .immediate) { _, _ in }
        }
    }

    // MARK: - Writing band readings

    func write(reading: SensorReading) {
        guard isAuthorized else { return }
        switch reading.kind {
        case .heartRate:
            save(quantity: reading.value, unit: HKUnit.count().unitDivided(by: .minute()), type: .heartRate, at: reading.timestamp)
        case .spo2:
            save(quantity: reading.value / 100.0, unit: .percent(), type: .oxygenSaturation, at: reading.timestamp)
        case .calories:
            save(quantity: reading.value, unit: .kilocalorie(), type: .activeEnergyBurned, at: reading.timestamp)
        case .distance:
            save(quantity: reading.value, unit: .meter(), type: .distanceWalkingRunning, at: reading.timestamp)
        case .steps, .battery:
            break // steps are written as cumulative totals via writeStepCount; battery is device telemetry only
        }
    }

    func writeStepCount(_ steps: Int, start: Date, end: Date) {
        save(quantity: Double(steps), unit: .count(), type: .stepCount, start: start, end: end)
    }

    private func save(quantity value: Double, unit: HKUnit, type identifier: HKQuantityTypeIdentifier, at date: Date) {
        save(quantity: value, unit: unit, type: identifier, start: date, end: date)
    }

    private func save(quantity value: Double, unit: HKUnit, type identifier: HKQuantityTypeIdentifier, start: Date, end: Date) {
        guard isAuthorized, let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else { return }
        let quantity = HKQuantity(unit: unit, doubleValue: value)
        let sample = HKQuantitySample(type: quantityType, quantity: quantity, start: start, end: end)
        store.save(sample) { _, _ in }
    }

    // MARK: - Reading today's totals

    func refreshTodayActivity() async {
        guard isAuthorized else { return }
        async let energy = sumToday(.activeEnergyBurned, unit: .kilocalorie())
        async let exercise = sumToday(.appleExerciseTime, unit: .minute())
        async let steps = sumToday(.stepCount, unit: .count())
        async let distance = sumToday(.distanceWalkingRunning, unit: .meter())
        async let stand = standHoursToday()

        let (energyValue, exerciseValue, stepsValue, distanceValue, standValue) = await (energy, exercise, steps, distance, stand)
        todayActivity = DailyActivity(
            activeEnergy: energyValue,
            exerciseMinutes: exerciseValue,
            standHours: standValue,
            steps: Int(stepsValue),
            distanceMeters: distanceValue,
            latestHeartRate: todayActivity.latestHeartRate
        )
    }

    private func sumToday(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return 0 }
        return await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: Calendar.current.startOfDay(for: .now), end: .now)
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, _ in
                let value = statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    private func standHoursToday() async -> Int {
        guard let type = HKCategoryType.categoryType(forIdentifier: .appleStandHour) else { return 0 }
        return await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: Calendar.current.startOfDay(for: .now), end: .now)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let hours = (samples as? [HKCategorySample])?
                    .filter { $0.value == HKCategoryValueAppleStandHour.stood.rawValue }
                    .count ?? 0
                continuation.resume(returning: hours)
            }
            store.execute(query)
        }
    }

    // MARK: - Trends

    func fetchDailyHistory(for identifier: HKQuantityTypeIdentifier, unit: HKUnit, days: Int) async -> [DailyStat] {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return [] }
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: .now)
        let end = startOfToday.addingTimeInterval(86_400)
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: startOfToday) else { return [] }

        return await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
            var interval = DateComponents()
            interval.day = 1
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: startOfToday,
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, results, _ in
                var stats: [DailyStat] = []
                results?.enumerateStatistics(from: start, to: end) { statistics, _ in
                    let value = statistics.sumQuantity()?.doubleValue(for: unit) ?? 0
                    stats.append(DailyStat(date: statistics.startDate, value: value))
                }
                continuation.resume(returning: stats)
            }
            store.execute(query)
        }
    }
}
