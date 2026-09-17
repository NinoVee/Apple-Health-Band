import SwiftUI

struct RootView: View {
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "circle.circle") }
            SensorsView()
                .tabItem { Label("Sensors", systemImage: "waveform.path.ecg") }
            TrendsView()
                .tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }
            HealthChatView()
                .tabItem { Label("AI Insights", systemImage: "sparkles") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .preferredColorScheme(appearanceMode.colorScheme)
    }
}
