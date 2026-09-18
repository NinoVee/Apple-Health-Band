import SwiftUI

@main
struct HealthBandApp: App {
    @StateObject private var bluetooth: BandBluetoothManager
    @StateObject private var healthKit: HealthKitManager
    @StateObject private var goalsStore = GoalsStore()
    @StateObject private var scaleLogStore = ScaleLogStore()
    @StateObject private var coordinator: ActivitySyncCoordinator
    @StateObject private var workoutSession: WorkoutSessionManager

    init() {
        let bluetooth = BandBluetoothManager()
        let healthKit = HealthKitManager()
        let coordinator = ActivitySyncCoordinator(bluetooth: bluetooth, healthKit: healthKit)
        let workoutSession = WorkoutSessionManager(store: healthKit.store, bluetooth: bluetooth)
        coordinator.workoutSession = workoutSession

        _bluetooth = StateObject(wrappedValue: bluetooth)
        _healthKit = StateObject(wrappedValue: healthKit)
        _coordinator = StateObject(wrappedValue: coordinator)
        _workoutSession = StateObject(wrappedValue: workoutSession)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(bluetooth)
                .environmentObject(healthKit)
                .environmentObject(goalsStore)
                .environmentObject(scaleLogStore)
                .environmentObject(coordinator)
                .environmentObject(workoutSession)
                .task {
                    await healthKit.requestAuthorization()
                }
        }
    }
}
