import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var healthKit: HealthKitManager
    @EnvironmentObject var bluetooth: BandBluetoothManager
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @AppStorage("aiInsightsEnabled") private var aiInsightsEnabled = false
    @AppStorage("aiProvider") private var aiProvider: AIProvider = .claude
    @AppStorage("aiRelayURL") private var aiRelayURL = ""
    @AppStorage("aiSharedSecret") private var aiSharedSecret = ""

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
                GoalsSections()
                Section {
                    Toggle("Enable AI Insights", isOn: $aiInsightsEnabled)
                    if aiInsightsEnabled {
                        Picker("Provider", selection: $aiProvider) {
                            ForEach(AIProvider.allCases) { provider in
                                Text(provider.label).tag(provider)
                            }
                        }
                        TextField("Relay URL (e.g. https://your-app.vercel.app/api/chat)", text: $aiRelayURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        SecureField("Shared Secret", text: $aiSharedSecret)
                    }
                } header: {
                    Text("AI Insights")
                } footer: {
                    Text("Off by default. When enabled, sending a message in the AI Insights tab sends a text summary of your recent Health data — not raw records — to your own relay server (see Server/ in the repo), which forwards it to \(aiProvider.label). Nothing is sent automatically. \(aiProvider.label) is a third-party AI service, not a medical professional.")
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
