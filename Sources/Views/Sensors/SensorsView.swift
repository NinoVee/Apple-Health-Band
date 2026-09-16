import SwiftUI

struct SensorsView: View {
    @EnvironmentObject var bluetooth: BandBluetoothManager
    @EnvironmentObject var healthKit: HealthKitManager
    @State private var showingScan = false
    @State private var ecgHistory: [HealthKitManager.ECGSummary] = []

    var body: some View {
        NavigationStack {
            List {
                Section("Device") {
                    DeviceStatusCard()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    Button(bluetooth.connectedDevice == nil ? "Find a band" : "Change band") {
                        showingScan = true
                    }
                    if bluetooth.connectedDevice != nil {
                        Button("Disconnect", role: .destructive) {
                            bluetooth.disconnect()
                        }
                    }
                }

                if let heartRate = bluetooth.latestReadings[.heartRate] {
                    Section("Heart Rate") {
                        Text("\(Int(heartRate.value)) bpm").font(.largeTitle.bold())
                        HeartRateGraphView(readings: bluetooth.heartRateHistory)
                    }
                }

                Section("Live readings") {
                    ForEach(SensorKind.allCases, id: \.self) { kind in
                        if let reading = bluetooth.latestReadings[kind] {
                            HStack {
                                Label(title(for: kind), systemImage: icon(for: kind))
                                Spacer()
                                Text("\(formatted(reading.value)) \(reading.unit)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if bluetooth.latestReadings.isEmpty {
                        Text("No sensor data yet. Connect a band to see live readings here.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    ECGHistoryView(ecgs: ecgHistory)
                } header: {
                    Text("ECG")
                } footer: {
                    Text("This band can't record new ECGs — Apple restricts that to reviewed medical accessories. These are recordings already in Health, e.g. from an Apple Watch.")
                }
            }
            .navigationTitle("Sensors")
            .sheet(isPresented: $showingScan) {
                DeviceScanView()
            }
            .task {
                ecgHistory = await healthKit.fetchRecentECGs()
            }
        }
    }

    private func title(for kind: SensorKind) -> String {
        switch kind {
        case .heartRate: return "Heart Rate"
        case .steps: return "Cadence"
        case .spo2: return "Blood Oxygen"
        case .battery: return "Battery"
        case .calories: return "Active Energy"
        case .distance: return "Distance"
        case .bodyFatPercentage: return "Body Fat"
        case .bodyMass: return "Weight"
        case .leanBodyMass: return "Lean Mass"
        }
    }

    private func icon(for kind: SensorKind) -> String {
        switch kind {
        case .heartRate: return "heart.fill"
        case .steps: return "figure.walk"
        case .spo2: return "lungs.fill"
        case .battery: return "battery.100"
        case .calories: return "flame.fill"
        case .distance: return "location.fill"
        case .bodyFatPercentage: return "percent"
        case .bodyMass: return "scalemass.fill"
        case .leanBodyMass: return "figure.arms.open"
        }
    }

    private func formatted(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value)
    }
}
