import Foundation

enum TrendRange: String, CaseIterable, Identifiable {
    case week
    case month
    case year

    var id: String { rawValue }

    var label: String {
        switch self {
        case .week: return "Week"
        case .month: return "Month"
        case .year: return "Year"
        }
    }

    /// How many days back the query window covers.
    var days: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        case .year: return 365
        }
    }

    /// Bucket size for `HKStatisticsCollectionQuery` — daily bars for
    /// Week/Month, monthly bars for Year (otherwise 365 daily bars would
    /// be unreadable).
    var intervalComponents: DateComponents {
        switch self {
        case .week, .month:
            var components = DateComponents()
            components.day = 1
            return components
        case .year:
            var components = DateComponents()
            components.month = 1
            return components
        }
    }

    /// Matches `intervalComponents` for Swift Charts' date-axis binning.
    var chartUnit: Calendar.Component {
        switch self {
        case .week, .month: return .day
        case .year: return .month
        }
    }
}
