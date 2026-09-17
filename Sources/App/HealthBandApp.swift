import SwiftUI

@main
struct HealthBandApp: App {
    @StateObject private var bluetooth: BandBluetoothManager
    @StateObject private var healthKit: HealthKitManager
    @StateObject private var goalsStore = GoalsStore()
    @StateObject private var scaleLogStore = ScaleLogStore()
    @StateObject private var coordinator: ActivitySyncCoordinator

    init() {
        let bluetooth = BandBluetoothManager()
        let healthKit = HealthKitManager()
        _bluetooth = StateObject(wrappedValue: bluetooth)
        _healthKit = StateObject(wrappedValue: healthKit)
        _coordinator = StateObject(wrappedValue: ActivitySyncCoordinator(bluetooth: bluetooth, healthKit: healthKit))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(bluetooth)
                .environmentObject(healthKit)
                .environmentObject(goalsStore)
                .environmentObject(scaleLogStore)
                .environmentObject(coordinator)
                .task {
                    await healthKit.requestAuthorization()
                }
        }
    }
}
