import RunalystCore
import SwiftUI

// MARK: - Watch App Entry Point

@main
struct RunalystWatchApp: App {
    @State private var workoutManager = WorkoutManager.shared
    @State private var pacingViewModel: PacingViewModel

    init() {
        // Register default preference so voice cues default to ON
        UserDefaults.standard.register(defaults: ["watchVoiceCuesEnabled": true])

        // Activate WatchConnectivity store on launch
        _ = WatchContextStore.shared

        let preview = ProcessInfo.processInfo.environment["RUNALYST_PREVIEW_SCREEN"]
        let vm = PacingViewModel()
        if let preview {
            switch preview {
            case "START_PRESCRIBED_DRILL":
                let mockProfile = AthleteCalibrationProfile(maxHR: 185.0, restingHR: 52.0, powerToHRTopQuartile: 1.85, isFallback: false)
                var calendar = Calendar(identifier: .gregorian)
                calendar.locale = Locale(identifier: "en_US_POSIX")
                let today = AthleteCalibrationCore.formatDayString(date: Date(), calendar: calendar)
                let mockIntent = AthleteCalibrationCore.makeDrillIntent(
                    title: "Cadence Pyramids",
                    drillId: "cadencePyramids",
                    targetCadence: "165 SPM",
                    durationMinutes: 10,
                    day: today
                )
                let context = WatchPacingContext(profile: mockProfile, intent: mockIntent)
                if let data = try? JSONEncoder().encode(context) {
                    UserDefaults.standard.set(data, forKey: "cachedWatchPacingContext")
                    WatchContextStore.shared.reloadPersistedContext()
                }
            case "START":
                UserDefaults.standard.removeObject(forKey: "cachedWatchPacingContext")
                WatchContextStore.shared.reloadPersistedContext()
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
                    refractoryProgress: 0.0,
                    filteredCadenceSPM: 168,
                    filteredCadenceFormatted: "168 SPM",
                    isCalibrating: true,
                    elapsedTimeFormatted: "2:15",
                    paceGaugeNormalizedPosition: 0.5,
                    biometricStatusToken: .calibratingBlue,
                    biometricStatusLabel: "Calibrating"
                )
            case "GAUGE_FLOW", "GAUGE_ON_TARGET":
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
                    refractoryProgress: 0.0,
                    filteredCadenceSPM: 172,
                    filteredCadenceFormatted: "172 SPM",
                    isCalibrating: false,
                    elapsedTimeFormatted: "12:30",
                    paceGaugeNormalizedPosition: 0.52,
                    targetBandLowerNormalized: 0.42,
                    targetBandUpperNormalized: 0.58,
                    biometricStatusToken: .electricBlue,
                    biometricStatusLabel: "Locked In"
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
                    refractoryProgress: 0.18,
                    filteredCadenceSPM: 176,
                    filteredCadenceFormatted: "176 SPM",
                    isCalibrating: false,
                    elapsedTimeFormatted: "18:45",
                    paceGaugeNormalizedPosition: 0.65,
                    targetBandLowerNormalized: 0.42,
                    targetBandUpperNormalized: 0.58,
                    biometricStatusToken: .surgeTeal,
                    biometricStatusLabel: "Surge Zone"
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
                    refractoryProgress: 0.35,
                    filteredCadenceSPM: 164,
                    filteredCadenceFormatted: "164 SPM",
                    isCalibrating: false,
                    elapsedTimeFormatted: "24:10",
                    paceGaugeNormalizedPosition: 0.32,
                    targetBandLowerNormalized: 0.42,
                    targetBandUpperNormalized: 0.58,
                    biometricStatusToken: .recoverAmber,
                    biometricStatusLabel: "Protecting Zone"
                )
            case "SUMMARY_DEBRIEF":
                break
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
                if let previewScreen {
                    if previewScreen == "SUMMARY_DEBRIEF" {
                        RunSummaryView(
                            debrief: WatchRunDebrief(
                                adaptationsBullet: "2 surges (+10s/km peak), 1 recovery adjustment.",
                                efficiencyScoreBullet: "Held baseline efficiency for 28 minutes before cardiac drift.",
                                formInsightBullet: "Cadence stayed rock-solid at 172 spm across the run.",
                                elapsedFormatted: "32:45",
                                distanceFormatted: "6.20 km",
                                averagePaceFormatted: "5:17 /km",
                                averageHeartRateFormatted: "152 bpm",
                                averageCadenceFormatted: "172 SPM"
                            ),
                            onDone: {}
                        )
                    } else if previewScreen.starts(with: "GAUGE") {
                        PacingGaugeView()
                    } else {
                        StartRunView()
                    }
                } else {
                    StartRunView()
                }
            }
            .environment(workoutManager)
            .environment(pacingViewModel)
        }
    }
}
