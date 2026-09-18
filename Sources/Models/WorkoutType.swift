import Foundation
import HealthKit

enum WorkoutType: String, CaseIterable, Identifiable {
    case running
    case weightTraining
    case swimming
    case cycling
    case yoga
    case boxing
    case basketball
    case tennis

    var id: String { rawValue }

    var label: String {
        switch self {
        case .running: return "Running"
        case .weightTraining: return "Weight Training"
        case .swimming: return "Swimming"
        case .cycling: return "Cycling"
        case .yoga: return "Yoga"
        case .boxing: return "Boxing"
        case .basketball: return "Basketball"
        case .tennis: return "Tennis"
        }
    }

    var systemImage: String {
        switch self {
        case .running: return "figure.run"
        case .weightTraining: return "dumbbell.fill"
        case .swimming: return "figure.pool.swim"
        case .cycling: return "figure.outdoor.cycle"
        case .yoga: return "figure.yoga"
        case .boxing: return "figure.boxing"
        case .basketball: return "figure.basketball"
        case .tennis: return "figure.tennis"
        }
    }

    /// Apple's own calorie/zone algorithms are calibrated per activity
    /// type — the same heart rate produces a different calorie estimate
    /// for running vs. yoga. Picking the right type here is what actually
    /// "calibrates" a finished workout in Health, not anything this app
    /// computes itself.
    var healthKitActivityType: HKWorkoutActivityType {
        switch self {
        case .running: return .running
        case .weightTraining: return .traditionalStrengthTraining
        case .swimming: return .swimming
        case .cycling: return .cycling
        case .yoga: return .yoga
        case .boxing: return .boxing
        case .basketball: return .basketball
        case .tennis: return .tennis
        }
    }

    /// The heart rate above which `ActivitySyncCoordinator` credits
    /// exercise minutes while this workout is active — a fixed "100 bpm"
    /// threshold doesn't mean the same thing for yoga as it does for
    /// boxing, so this overrides the coordinator's default per activity.
    var exerciseHeartRateThreshold: Double {
        switch self {
        case .yoga: return 90
        case .weightTraining: return 100
        case .basketball, .tennis: return 110
        case .running, .cycling, .swimming: return 120
        case .boxing: return 130
        }
    }

    /// How often the app re-polls read-only (non-notify) BLE
    /// characteristics while this workout is active — the one thing this
    /// app can actually control about "scanning frequency." A device's
    /// notify-based sensors (heart rate, etc.) push on their own firmware
    /// schedule; the app can't make the physical sensor itself sample
    /// faster, only how often it re-checks characteristics that don't
    /// push updates on their own. See `BandBluetoothManager.setScanningInterval`.
    var scanningInterval: TimeInterval {
        switch self {
        case .yoga: return 10
        case .weightTraining: return 5
        case .basketball, .tennis, .swimming: return 3
        case .cycling: return 3
        case .running, .boxing: return 2
        }
    }
}
