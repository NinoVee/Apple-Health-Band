import Foundation
import Combine
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
/// and movement data. Steps, distance, active energy, heart rate, blood
/// oxygen, body temperature, heart rate variability (SDNN, computed from
/// the band's RR intervals), blood pressure, height, BMI, basal energy
/// burned, and body composition (weight/fat %/lean mass) are ordinary
/// writable types and sync for real.
///
/// Muscle mass, bone mass, visceral fat, and subcutaneous fat have no
/// matching HealthKit quantity type at all — not a permissions issue,
/// there's simply no such type to write to. `ScaleLogStore` keeps those
/// in this app's own local log instead of pretending to sync them.
///
/// ECG is a similar Watch-style restriction, but stricter: writing a new
/// ECG *recording* requires a dedicated entitlement Apple only grants to
/// reviewed medical-device accessories, via application outside Xcode —
/// there's no capability toggle for it. So this app only *reads* ECGs
/// that already exist in Health (see `fetchRecentECGs`), e.g. ones an
/// Apple Watch recorded; it never attempts to write one from band data.
@MainActor
final class HealthKitManager: ObservableObject {
    static let isHealthDataAvailable = HKHealthStore.isHealthDataAvailable()

    @Published private(set) var isAuthorized = false
    @Published var todayActivity = DailyActivity()

    let store = HKHealthStore()

    private let writeTypes: Set<HKSampleType> = {
        let ids: [HKQuantityTypeIdentifier] = [
            .heartRate, .stepCount, .activeEnergyBurned, .distanceWalkingRunning, .oxygenSaturation,
            .bodyFatPercentage, .bodyMass, .leanBodyMass, .bodyTemperature, .heartRateVariabilitySDNN,
            .height, .bodyMassIndex, .basalEnergyBurned, .bloodPressureSystolic, .bloodPressureDiastolic
        ]
        return Set(ids.compactMap { HKQuantityType.quantityType(forIdentifier: $0) })
    }()

    private let readTypes: Set<HKObjectType> = {
        let quantityIDs: [HKQuantityTypeIdentifier] = [
            .heartRate, .stepCount, .activeEnergyBurned, .distanceWalkingRunning, .oxygenSaturation, .appleExerciseTime,
            .bodyFatPercentage, .bodyMass, .leanBodyMass, .bodyTemperature, .heartRateVariabilitySDNN,
            .height, .bodyMassIndex, .basalEnergyBurned, .bloodPressureSystolic, .bloodPressureDiastolic
        ]
        var set = Set<HKObjectType>(quantityIDs.compactMap { HKQuantityType.quantityType(forIdentifier: $0) })
        if let standType = HKCategoryType.categoryType(forIdentifier: .appleStandHour) {
            set.insert(standType)
        }
        set.insert(HKObjectType.activitySummaryType())
        set.insert(HKObjectType.electrocardiogramType()) // read-only — see class doc comment
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
        case .bodyFatPercentage:
            save(quantity: reading.value / 100.0, unit: .percent(), type: .bodyFatPercentage, at: reading.timestamp)
        case .bodyMass:
            save(quantity: reading.value, unit: .gramUnit(with: .kilo), type: .bodyMass, at: reading.timestamp)
        case .leanBodyMass:
            save(quantity: reading.value, unit: .gramUnit(with: .kilo), type: .leanBodyMass, at: reading.timestamp)
        case .bodyTemperature:
            save(quantity: reading.value, unit: .degreeCelsius(), type: .bodyTemperature, at: reading.timestamp)
        case .heartRateVariability:
            save(quantity: reading.value, unit: .secondUnit(with: .milli), type: .heartRateVariabilitySDNN, at: reading.timestamp)
        case .steps, .battery, .rrInterval, .bloodPressureSystolic, .bloodPressureDiastolic:
            break // steps are cumulative totals via writeStepCount; battery is telemetry; rrInterval feeds HRV;
                  // blood pressure is written as a paired correlation via writeBloodPressure, not individually
        }
    }

    /// Writes systolic + diastolic together as an `HKCorrelation`, which
    /// is how Health expects blood pressure stored (so it displays as a
    /// linked "120/80" reading, not two unrelated numbers).
    func writeBloodPressure(systolicMmHg: Double, diastolicMmHg: Double, at date: Date) {
        guard isAuthorized,
              let systolicType = HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic),
              let diastolicType = HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic),
              let correlationType = HKCorrelationType.correlationType(forIdentifier: .bloodPressure)
        else { return }

        let unit = HKUnit.millimeterOfMercury()
        let systolicSample = HKQuantitySample(
            type: systolicType, quantity: HKQuantity(unit: unit, doubleValue: systolicMmHg), start: date, end: date
        )
        let diastolicSample = HKQuantitySample(
            type: diastolicType, quantity: HKQuantity(unit: unit, doubleValue: diastolicMmHg), start: date, end: date
        )
        let correlation = HKCorrelation(type: correlationType, start: date, end: date, objects: [systolicSample, diastolicSample])
        store.save(correlation) { _, _ in }
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

    func fetchHistory(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        days: Int,
        intervalComponents: DateComponents
    ) async -> [DailyStat] {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return [] }
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: .now)
        let end = startOfToday.addingTimeInterval(86_400)
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: startOfToday) else { return [] }

        return await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: startOfToday,
                intervalComponents: intervalComponents
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

    // MARK: - Scale log

    /// Writes the subset of a `ScaleEntry` that has a matching HealthKit
    /// type. Muscle mass, bone mass, visceral fat, and subcutaneous fat
    /// have none, so they're skipped here — see the class doc comment.
    func writeScaleEntry(_ entry: ScaleEntry) {
        guard isAuthorized else { return }
        if let weightKg = entry.weightKg {
            save(quantity: weightKg, unit: .gramUnit(with: .kilo), type: .bodyMass, at: entry.date)
        }
        if let heightCm = entry.heightCm {
            save(quantity: heightCm / 100.0, unit: .meter(), type: .height, at: entry.date)
        }
        if let bmi = entry.bmi {
            save(quantity: bmi, unit: .count(), type: .bodyMassIndex, at: entry.date)
        }
        if let bodyFatPercentage = entry.bodyFatPercentage {
            save(quantity: bodyFatPercentage / 100.0, unit: .percent(), type: .bodyFatPercentage, at: entry.date)
        }
        if let fatFreeBodyWeightKg = entry.fatFreeBodyWeightKg {
            save(quantity: fatFreeBodyWeightKg, unit: .gramUnit(with: .kilo), type: .leanBodyMass, at: entry.date)
        }
        if let basalMetabolicRateKcal = entry.basalMetabolicRateKcal {
            save(quantity: basalMetabolicRateKcal, unit: .kilocalorie(), type: .basalEnergyBurned, at: entry.date)
        }
    }

    // MARK: - ECG (read-only)

    struct ECGSummary: Identifiable {
        let id = UUID()
        let date: Date
        let classification: String
        let averageHeartRate: Double?
    }

    /// Reads ECG recordings already in Health (e.g. from an Apple Watch).
    /// This app cannot write new ones — see the class doc comment.
    func fetchRecentECGs(limit: Int = 5) async -> [ECGSummary] {
        guard isAuthorized else { return [] }
        let type = HKObjectType.electrocardiogramType()
        return await withCheckedContinuation { continuation in
            let sort = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: limit, sortDescriptors: sort) { _, samples, _ in
                let bpmUnit = HKUnit.count().unitDivided(by: .minute())
                let summaries = (samples as? [HKElectrocardiogram])?.map { sample in
                    ECGSummary(
                        date: sample.endDate,
                        classification: Self.description(for: sample.classification),
                        averageHeartRate: sample.averageHeartRate?.doubleValue(for: bpmUnit)
                    )
                } ?? []
                continuation.resume(returning: summaries)
            }
            store.execute(query)
        }
    }

    /// Pure, stateless mapping — `nonisolated` so it can be called from
    /// HealthKit's background query-completion callback in `fetchRecentECGs`
    /// without needing a hop to the main actor.
    nonisolated private static func description(for classification: HKElectrocardiogram.Classification) -> String {
        switch classification {
        case .sinusRhythm: return "Sinus Rhythm"
        case .atrialFibrillation: return "Atrial Fibrillation"
        case .inconclusiveLowHeartRate: return "Inconclusive — Low Heart Rate"
        case .inconclusiveHighHeartRate: return "Inconclusive — High Heart Rate"
        case .inconclusivePoorReading: return "Inconclusive — Poor Reading"
        case .inconclusiveOther: return "Inconclusive"
        case .unrecognized: return "Unrecognized"
        case .notSet: return "Not Set"
        @unknown default: return "Unknown"
        }
    }
}
