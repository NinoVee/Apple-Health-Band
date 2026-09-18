import SwiftUI

struct SensorsView: View {
    @EnvironmentObject var bluetooth: BandBluetoothManager
    @EnvironmentObject var healthKit: HealthKitManager
    @EnvironmentObject var coordinator: ActivitySyncCoordinator
    @State private var showingScan = false
    @State private var ecgHistory: [HealthKitManager.ECGSummary] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DeviceStatusCard()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    ForEach(bluetooth.connectedDevices) { device in
                        HStack {
                            Text(device.name)
                            Spacer()
                            Button("Disconnect", role: .destructive) {
                                bluetooth.disconnect(device)
                            }
                            .font(.caption)
                        }
                    }
                    Button("Add a device") {
                        showingScan = true
                    }
                } header: {
                    Text("Devices")
                } footer: {
                    Text("Pair a band, a scale, and a blood pressure cuff at the same time — each syncs whatever it reports (heart rate, weight, blood pressure, etc.) into the same Health data. If your device came with its own companion app that already syncs to Apple Health (common for many bands), you don't need to connect it here too — leave it paired with its own app instead (most BLE devices only hold one connection at a time) and this app will pick up everything it writes to Health automatically, same as Steps and Distance already do. Connecting a device here is for ones without their own Health sync.")
                }

                if let heartRate = bluetooth.latestReadings[.heartRate] {
                    Section("Heart Rate") {
                        Text("\(Int(heartRate.value)) bpm").font(.largeTitle.bold())
                        HeartRateGraphView(readings: bluetooth.heartRateHistory)
                        if let hrv = coordinator.latestHRV {
                            HStack {
                                Text("HRV (SDNN)")
                                Spacer()
                                Text("\(Int(hrv)) ms").foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let spo2 = bluetooth.latestReadings[.spo2] {
                    Section("Blood Oxygen") {
                        Text("\(Int(spo2.value))%").font(.largeTitle.bold())
                        let status = spo2Status(spo2.value)
                        Text(status.label)
                            .font(.caption)
                            .foregroundStyle(status.color)
                    }
                }

                if let systolic = bluetooth.latestReadings[.bloodPressureSystolic],
                   let diastolic = bluetooth.latestReadings[.bloodPressureDiastolic] {
                    Section("Blood Pressure") {
                        Text("\(Int(systolic.value))/\(Int(diastolic.value)) mmHg").font(.largeTitle.bold())
                        let status = bloodPressureStatus(systolic: systolic.value, diastolic: diastolic.value)
                        Text(status.label)
                            .font(.caption)
                            .foregroundStyle(status.color)
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
        case .bodyTemperature: return "Body Temperature"
        case .rrInterval: return "RR Interval"
        case .heartRateVariability: return "Heart Rate Variability"
        case .bloodPressureSystolic: return "Systolic"
        case .bloodPressureDiastolic: return "Diastolic"
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
        case .bodyTemperature: return "thermometer"
        case .rrInterval: return "waveform"
        case .heartRateVariability: return "waveform.path.ecg.rectangle"
        case .bloodPressureSystolic, .bloodPressureDiastolic: return "heart.text.square.fill"
        }
    }

    private func formatted(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value)
    }

    /// Typical clinical SpO2 reference ranges — not a diagnosis, just a
    /// label to make the raw percentage easier to read at a glance.
    private func spo2Status(_ value: Double) -> (label: String, color: Color) {
        switch value {
        case 95...: return ("Normal", .green)
        case 90..<95: return ("Low", .orange)
        default: return ("Critical — seek medical attention", .red)
        }
    }

    /// Simplified AHA blood pressure categories — not a diagnosis, just a
    /// label to make the raw numbers easier to read at a glance.
    private func bloodPressureStatus(systolic: Double, diastolic: Double) -> (label: String, color: Color) {
        switch (systolic, diastolic) {
        case (180..., _), (_, 120...):
            return ("Hypertensive Crisis — seek medical attention", .red)
        case (140..., _), (_, 90...):
            return ("High (Stage 2)", .red)
        case (130..<140, _), (_, 80..<90):
            return ("High (Stage 1)", .orange)
        case (120..<130, ..<80):
            return ("Elevated", .yellow)
        default:
            return ("Normal", .green)
        }
    }
}
