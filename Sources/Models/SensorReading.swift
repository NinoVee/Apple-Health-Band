import Foundation

enum SensorKind: String, CaseIterable, Hashable {
    case heartRate
    case steps
    case spo2
    case battery
    case calories
    case distance
    case bodyFatPercentage
    case bodyMass
    case leanBodyMass
    case bodyTemperature
    case rrInterval
    case heartRateVariability
    case bloodPressureSystolic
    case bloodPressureDiastolic
}

struct SensorReading: Identifiable, Equatable {
    let id = UUID()
    let kind: SensorKind
    let value: Double
    let unit: String
    let timestamp: Date
}
