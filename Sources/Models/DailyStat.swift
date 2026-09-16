import Foundation

/// One day's cumulative value for a Trends chart (see `TrendsView`).
struct DailyStat: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}
