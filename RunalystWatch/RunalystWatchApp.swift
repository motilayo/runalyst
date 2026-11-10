import RunalystCore
import SwiftUI

// MARK: - Watch App Entry Point

@main
struct RunalystWatchApp: App {
    @State private var workoutManager = WorkoutManager.shared
    @State private var pacingViewModel: PacingViewModel

    init() {
        // Activate WatchConnectivity store on launch
        _ = WatchContextStore.shared

        let preview = ProcessInfo.processInfo.environment["RUNALYST_PREVIEW_SCREEN"]
        let vm = PacingViewModel()
        if let preview {
            switch preview {
            case "GAUGE_ON_TARGET":
                vm.displayState = PacingDisplayState(
                    state: .tracking,
                    targetPaceSecondsPerKm: 300,
                    filteredPaceSecondsPerKm: 298,
                    filteredHeartRateBPM: 148,
                    deviation: .onTarget,
                    refractorySecondsRemaining: 0,
                    lastReason: nil,
                    adjustmentsEnabled: true,
                    targetPaceFormatted: "5:00 /km",
                    filteredPaceFormatted: "4:58 /km",
                    filteredHeartRateFormatted: "148 bpm",
                    deviationTitle: "ON TARGET",
                    calibrationProgress: 1.0,
                    calibrationProgressFormatted: "100%",
                    refractoryProgress: 0.0
                )
            case "GAUGE_SURGE":
                vm.displayState = PacingDisplayState(
                    state: .surge,
                    targetPaceSecondsPerKm: 295,
                    filteredPaceSecondsPerKm: 292,
                    filteredHeartRateBPM: 145,
                    deviation: .onTarget,
                    refractorySecondsRemaining: 74,
                    lastReason: .reservesAvailable,
                    adjustmentsEnabled: true,
                    targetPaceFormatted: "4:55 /km",
                    filteredPaceFormatted: "4:52 /km",
                    filteredHeartRateFormatted: "145 bpm",
                    deviationTitle: "SURGE (+5 s/km)",
                    calibrationProgress: 1.0,
                    calibrationProgressFormatted: "100%",
                    refractoryProgress: 0.18
                )
            case "GAUGE_RECOVER":
                vm.displayState = PacingDisplayState(
                    state: .recover,
                    targetPaceSecondsPerKm: 310,
                    filteredPaceSecondsPerKm: 308,
                    filteredHeartRateBPM: 168,
                    deviation: .tooFast,
                    refractorySecondsRemaining: 58,
                    lastReason: .efficiencyDrift,
                    adjustmentsEnabled: true,
                    targetPaceFormatted: "5:10 /km",
                    filteredPaceFormatted: "5:08 /km",
                    filteredHeartRateFormatted: "168 bpm",
                    deviationTitle: "CARDIAC DRIFT (-10 s/km)",
                    calibrationProgress: 1.0,
                    calibrationProgressFormatted: "100%",
                    refractoryProgress: 0.35
                )
            case "GAUGE_CALIBRATING":
                vm.displayState = PacingDisplayState(
                    state: .calibrating(progress: 0.45),
                    targetPaceSecondsPerKm: 300,
                    filteredPaceSecondsPerKm: 302,
                    filteredHeartRateBPM: 138,
                    deviation: .onTarget,
                    refractorySecondsRemaining: 0,
                    lastReason: nil,
                    adjustmentsEnabled: true,
                    targetPaceFormatted: "5:00 /km",
                    filteredPaceFormatted: "5:02 /km",
                    filteredHeartRateFormatted: "138 bpm",
                    deviationTitle: "CALIBRATING (45%)",
                    calibrationProgress: 0.45,
                    calibrationProgressFormatted: "45%",
                    refractoryProgress: 0.0
                )
            default:
                break
            }
        }
        _pacingViewModel = State(initialValue: vm)
    }

    private var previewScreen: String? {
        ProcessInfo.processInfo.environment["RUNALYST_PREVIEW_SCREEN"]
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                if let previewScreen, previewScreen.starts(with: "GAUGE") {
                    PacingGaugeView()
                } else {
                    StartRunView()
                }
            }
            .environment(workoutManager)
            .environment(pacingViewModel)
        }
    }
}
