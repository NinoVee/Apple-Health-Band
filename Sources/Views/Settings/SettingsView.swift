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
                Section {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(healthKit.isAuthorized ? "Connected" : "Not connected")
                            .foregroundStyle(healthKit.isAuthorized ? .green : .secondary)
                    }
                    Button("Request Health access") {
                        Task { await healthKit.requestAuthorization() }
                    }
                    if let error = healthKit.authorizationError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Apple Health")
                } footer: {
                    if healthKit.authorizationError != nil {
                        Text("If this mentions HealthKit not being available/entitled, check Xcode's Signing & Capabilities tab for a HealthKit row, and confirm you're signed in with a paid Apple Developer account — a free personal-team account cannot use HealthKit at all, on device or in Simulator.")
                    }
                }
                Section("Paired devices") {
                    if bluetooth.connectedDevices.isEmpty {
                        Text("No devices paired").foregroundStyle(.secondary)
                    } else {
                        ForEach(bluetooth.connectedDevices) { device in
                            HStack {
                                Text(device.name)
                                Spacer()
                                Button("Forget", role: .destructive) {
                                    bluetooth.disconnect(device)
                                }
                                .font(.caption)
                            }
                        }
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
