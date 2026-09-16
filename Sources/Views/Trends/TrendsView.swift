import SwiftUI
import Charts
import HealthKit

struct TrendsView: View {
    @EnvironmentObject var healthKit: HealthKitManager
    @State private var steps: [DailyStat] = []
    @State private var energy: [DailyStat] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    trendSection(title: "Steps (7 days)", data: steps, color: .orange)
                    trendSection(title: "Active Energy (7 days)", data: energy, color: .pink)
                }
                .padding()
            }
            .navigationTitle("Trends")
            .task { await loadHistory() }
            .refreshable { await loadHistory() }
        }
    }

    private func trendSection(title: String, data: [DailyStat], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Chart(data) { stat in
                BarMark(
                    x: .value("Day", stat.date, unit: .day),
                    y: .value("Value", stat.value)
                )
                .foregroundStyle(color.gradient)
            }
            .frame(height: 160)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func loadHistory() async {
        async let stepsHistory = healthKit.fetchDailyHistory(for: .stepCount, unit: .count(), days: 7)
        async let energyHistory = healthKit.fetchDailyHistory(for: .activeEnergyBurned, unit: .kilocalorie(), days: 7)
        steps = await stepsHistory
        energy = await energyHistory
    }
}
