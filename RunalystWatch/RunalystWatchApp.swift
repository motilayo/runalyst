import RunalystCore
import SwiftUI

// MARK: - Watch App Entry Point

@main
struct RunalystWatchApp: App {
    @State private var workoutManager = WorkoutManager.shared
    @State private var pacingViewModel = PacingViewModel()

    init() {
        // Activate WatchConnectivity store on launch
        _ = WatchContextStore.shared
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                StartRunView()
            }
            .environment(workoutManager)
            .environment(pacingViewModel)
        }
    }
}
