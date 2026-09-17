import Foundation

/// A manually-logged smart-scale reading. Stored in metric internally
/// (kg/cm) regardless of what unit the entry form was filled in with.
///
/// `weightKg`, `heightCm`, `bmi`, `bodyFatPercentage`,
/// `fatFreeBodyWeightKg`, and `basalMetabolicRateKcal` sync to Apple
/// Health (see `HealthKitManager.writeScaleEntry`). `muscleMassKg`,
/// `boneMassKg`, `visceralFatRating`, and `subcutaneousFatPercentage`
/// have no matching HealthKit type, so they only live in this app's own
/// log (`ScaleLogStore`).
struct ScaleEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var date: Date = .now
    var weightKg: Double?
    var heightCm: Double?
    var bmi: Double?
    var bodyFatPercentage: Double?
    var fatFreeBodyWeightKg: Double?
    var muscleMassKg: Double?
    var boneMassKg: Double?
    var visceralFatRating: Double?
    var subcutaneousFatPercentage: Double?
    var basalMetabolicRateKcal: Double?

    /// A convenience the entry form offers but never forces — the
    /// scale's own displayed BMI may use a slightly different formula.
    static func computedBMI(weightKg: Double, heightCm: Double) -> Double? {
        guard heightCm > 0 else { return nil }
        let heightMeters = heightCm / 100.0
        return weightKg / (heightMeters * heightMeters)
    }
}
