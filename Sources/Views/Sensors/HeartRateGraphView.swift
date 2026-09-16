import SwiftUI
import Charts

struct HeartRateGraphView: View {
    let readings: [SensorReading]

    var body: some View {
        Chart(readings) { reading in
            LineMark(
                x: .value("Time", reading.timestamp),
                y: .value("BPM", reading.value)
            )
            .foregroundStyle(.pink)
            .interpolationMethod(.catmullRom)
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .frame(height: 140)
    }
}
