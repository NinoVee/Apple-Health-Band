import SwiftUI
import UIKit

struct RootView: View {
    private enum Tab: Hashable {
        case today, sensors, trends, insights, settings
    }

    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @State private var selectedTab: Tab = .today

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "circle.circle") }
                .tag(Tab.today)
            SensorsView()
                .tabItem { Label("Sensors", systemImage: "waveform.path.ecg") }
                .tag(Tab.sensors)
            TrendsView()
                .tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }
                .tag(Tab.trends)
            HealthChatView()
                .tabItem { Label("AI Insights", systemImage: "sparkles") }
                .tag(Tab.insights)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .preferredColorScheme(appearanceMode.colorScheme)
        // TabView doesn't resign the keyboard when the selected tab changes
        // (a tab's onDisappear doesn't fire on tab switches — it's just
        // hidden, not torn down), so a focused TextField like the one in
        // AI Insights stays first responder and its keyboard visually
        // sticks on top of whichever tab you switch to, swallowing every
        // touch until the app is force-quit. Forcing resignFirstResponder
        // on every tab change is the standard app-wide fix.
        .onChange(of: selectedTab) { _, _ in
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
}
