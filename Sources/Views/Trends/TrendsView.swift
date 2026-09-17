import SwiftUI
import Charts
import HealthKit

/// Hosts both trend-style tabs — Activity (Health history) and Scale
/// (manual log) — behind one segmented control, so the tab bar doesn't
/// need a separate entry for each.
struct TrendsView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case activity
        case scale

        var id: String { rawValue }
        var label: String {
            switch self {
            case .activity: return "Activity"
            case .scale: return "Scale"
            }
        }
    }

    @EnvironmentObject var healthKit: HealthKitManager
    @EnvironmentObject var scaleLog: ScaleLogStore
    @State private var section: Section = .activity
    @State private var showingScaleForm = false

    var body: some View {
        NavigationStack {
            Group {
                switch section {
                case .activity:
                    ActivityTrendsView()
                case .scale:
                    ScaleLogView()
                }
            }
            .navigationTitle("Trends")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Section", selection: $section) {
                        ForEach(Section.allCases) { section in
                            Text(section.label).tag(section)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
                if section == .scale {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingScaleForm = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingScaleForm) {
                ScaleEntryFormView { entry in
                    scaleLog.add(entry)
                    healthKit.writeScaleEntry(entry)
                }
            }
        }
    }
}

private struct ActivityTrendsView: View {
    @EnvironmentObject var healthKit: HealthKitManager
    @State private var range: TrendRange = .week
    @State private var steps: [DailyStat] = []
    @State private var energy: [DailyStat] = []

    var body: some View {
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
        .task { await loadHistory() }
        .refreshable { await loadHistory() }
        .onChange(of: range) { _, _ in
            Task { await loadHistory() }
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
