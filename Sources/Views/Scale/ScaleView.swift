import SwiftUI
import Charts

/// Content for the Scale section of the Trends tab. The "+" toolbar
/// button and its sheet live in `TrendsView` (the shared nav container),
/// so this is just the list/chart content.
struct ScaleLogView: View {
    @EnvironmentObject var store: ScaleLogStore

    var body: some View {
        List {
            if store.entries.contains(where: { $0.weightKg != nil }) {
                Section("Weight trend") {
                    Chart(store.entries.reversed()) { entry in
                        if let weight = entry.weightKg {
                            LineMark(
                                x: .value("Date", entry.date),
                                y: .value("Weight", weight)
                            )
                            .foregroundStyle(.blue)
                            .interpolationMethod(.catmullRom)
                        }
                    }
                    .frame(height: 160)
                }
            }

            Section("History") {
                if store.entries.isEmpty {
                    Text("No scale readings logged yet. Tap + to add one.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.entries) { entry in
                        ScaleEntryRow(entry: entry)
                    }
                    .onDelete(perform: store.delete)
                }
            }
        }
    }
}

private struct ScaleEntryRow: View {
    let entry: ScaleEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                .font(.subheadline.bold())
            HStack(spacing: 12) {
                if let weight = entry.weightKg {
                    Text("\(String(format: "%.1f", weight)) kg")
                }
                if let bmi = entry.bmi {
                    Text("BMI \(String(format: "%.1f", bmi))")
                }
                if let fat = entry.bodyFatPercentage {
                    Text("Fat \(String(format: "%.1f", fat))%")
                }
                if let muscle = entry.muscleMassKg {
                    Text("Muscle \(String(format: "%.1f", muscle)) kg")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
