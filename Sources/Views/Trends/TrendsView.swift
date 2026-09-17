import SwiftUI
import Charts
import HealthKit

struct TrendsView: View {
    @EnvironmentObject var healthKit: HealthKitManager
    @State private var range: TrendRange = .week
    @State private var steps: [DailyStat] = []
    @State private var energy: [DailyStat] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Picker("Range", selection: $range) {
                        ForEach(TrendRange.allCases) { range in
                            Text(range.label).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)

                    trendSection(title: "Steps", data: steps, color: .orange)
                    trendSection(title: "Active Energy", data: energy, color: .pink)
                }
                .padding()
            }
            .navigationTitle("Trends")
            .task { await loadHistory() }
            .refreshable { await loadHistory() }
            .onChange(of: range) { _, _ in
                Task { await loadHistory() }
            }
        }
    }

    private func trendSection(title: String, data: [DailyStat], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Chart(data) { stat in
                BarMark(
                    x: .value("Period", stat.date, unit: range.chartUnit),
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
        async let stepsHistory = healthKit.fetchHistory(
            for: .stepCount, unit: .count(), days: range.days, intervalComponents: range.intervalComponents
        )
        async let energyHistory = healthKit.fetchHistory(
            for: .activeEnergyBurned, unit: .kilocalorie(), days: range.days, intervalComponents: range.intervalComponents
        )
        steps = await stepsHistory
        energy = await energyHistory
    }
}
