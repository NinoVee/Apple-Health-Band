import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var healthKit: HealthKitManager
    @EnvironmentObject var bluetooth: BandBluetoothManager
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Appearance", selection: $appearanceMode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Apple Health") {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(healthKit.isAuthorized ? "Connected" : "Not connected")
                            .foregroundStyle(healthKit.isAuthorized ? .green : .secondary)
                    }
                    Button("Request Health access") {
                        Task { await healthKit.requestAuthorization() }
                    }
                }
                Section("Paired band") {
                    if let device = bluetooth.connectedDevice {
                        Text(device.name)
                        Button("Forget this band", role: .destructive) {
                            bluetooth.disconnect()
                        }
                    } else {
                        Text("No band paired").foregroundStyle(.secondary)
                    }
                }
                Section("About") {
                    LabeledContent("Version", value: Bundle.main.appVersionString)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
