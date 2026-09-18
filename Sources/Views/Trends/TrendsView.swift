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
    @State private var calories: [DailyStat] = []
    @State private var heartRate: [DailyStat] = []
    @State private var bloodOxygen: [DailyStat] = []
    @State private var systolic: [DailyStat] = []
    @State private var diastolic: [DailyStat] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Picker("Range", selection: $range) {
                    ForEach(TrendRange.allCases) { range in
                        Text(range.label).tag(range)
                    }
                }
                .pickerStyle(.segmented)

                barSection(title: "Steps", data: steps, color: .orange)
                barSection(title: "Calories Burned", data: calories, color: .pink)
                lineSection(title: "Heart Rate", data: heartRate, color: .red)
                lineSection(title: "Blood Oxygen", data: bloodOxygen, color: .cyan)
                bloodPressureSection
            }
            .padding()
        }
        .task { await loadHistory() }
        .refreshable { await loadHistory() }
        .onChange(of: range) { _, _ in
            Task { await loadHistory() }
        }
    }

    private func barSection(title: String, data: [DailyStat], color: Color) -> some View {
        card(title: title) {
            Chart(data) { stat in
                BarMark(
                    x: .value("Period", stat.date, unit: range.chartUnit),
                    y: .value("Value", stat.value)
                )
                .foregroundStyle(color.gradient)
            }
            .frame(height: 160)
        }
    }

    private func lineSection(title: String, data: [DailyStat], color: Color) -> some View {
        card(title: title) {
            if data.allSatisfy({ $0.value == 0 }) {
                emptyState(title)
            } else {
                Chart(data) { stat in
                    LineMark(
                        x: .value("Period", stat.date, unit: range.chartUnit),
                        y: .value(title, stat.value)
                    )
                    .foregroundStyle(color)
                    .interpolationMethod(.catmullRom)
                }
                .frame(height: 160)
            }
        }
    }

    private var bloodPressureSection: some View {
        card(title: "Blood Pressure") {
            if systolic.allSatisfy({ $0.value == 0 }) {
                emptyState("Blood Pressure")
            } else {
                Chart {
                    ForEach(systolic) { stat in
                        LineMark(
                            x: .value("Period", stat.date, unit: range.chartUnit),
                            y: .value("Systolic", stat.value),
                            series: .value("Series", "Systolic")
                        )
                        .foregroundStyle(.red)
                    }
                    ForEach(diastolic) { stat in
                        LineMark(
                            x: .value("Period", stat.date, unit: range.chartUnit),
                            y: .value("Diastolic", stat.value),
                            series: .value("Series", "Diastolic")
                        )
                        .foregroundStyle(.blue)
                    }
                }
                .frame(height: 160)

                HStack(spacing: 16) {
                    Label("Systolic", systemImage: "circle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                    Label("Diastolic", systemImage: "circle.fill")
                        .foregroundStyle(.blue)
                        .font(.caption)
                }
            }
        }
    }

    private func emptyState(_ title: String) -> some View {
        Text("No \(title.lowercased()) data for this range.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(height: 160)
    }

    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
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
        async let heartRateHistory = healthKit.fetchHistory(
            for: .heartRate, unit: HKUnit.count().unitDivided(by: .minute()), days: range.days,
            intervalComponents: range.intervalComponents, aggregation: .average
        )
        async let spo2History = healthKit.fetchHistory(
            for: .oxygenSaturation, unit: .percent(), days: range.days,
            intervalComponents: range.intervalComponents, aggregation: .average
        )
        async let systolicHistory = healthKit.fetchHistory(
            for: .bloodPressureSystolic, unit: .millimeterOfMercury(), days: range.days,
            intervalComponents: range.intervalComponents, aggregation: .average
        )
        async let diastolicHistory = healthKit.fetchHistory(
            for: .bloodPressureDiastolic, unit: .millimeterOfMercury(), days: range.days,
            intervalComponents: range.intervalComponents, aggregation: .average
        )

        steps = await stepsHistory
        calories = await energyHistory
        heartRate = await heartRateHistory
        // HKUnit.percent() reports a 0-1 fraction; scale to 0-100 for display.
        bloodOxygen = (await spo2History).map { DailyStat(date: $0.date, value: $0.value * 100) }
        systolic = await systolicHistory
        diastolic = await diastolicHistory
    }
}
