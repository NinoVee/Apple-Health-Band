import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "circle.circle") }
            SensorsView()
                .tabItem { Label("Sensors", systemImage: "waveform.path.ecg") }
            TrendsView()
                .tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }
            GoalsView()
                .tabItem { Label("Goals", systemImage: "target") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
