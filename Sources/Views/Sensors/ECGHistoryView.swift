import SwiftUI

/// Lists ECG recordings already in Apple Health (read-only). This app
/// cannot record new ECGs from the band — see `HealthKitManager`'s doc
/// comment for why that's an Apple-side restriction, not a missing
/// feature here.
struct ECGHistoryView: View {
    let ecgs: [HealthKitManager.ECGSummary]

    var body: some View {
        if ecgs.isEmpty {
            Text("No ECG recordings in Health yet.")
                .foregroundStyle(.secondary)
        } else {
            ForEach(ecgs) { ecg in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ecg.classification)
                            .font(.subheadline.bold())
                        Text(ecg.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let heartRate = ecg.averageHeartRate {
                        Text("\(Int(heartRate)) bpm")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
