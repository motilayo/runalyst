## 1. Core Signal Conditioning (RunalystCore)

- [ ] 1.1 [Senior | pro] Add `.watchOS(.v10)` to `RunalystCore/Package.swift` platforms; confirm `swift build` and `swift test` still pass. Verify: `cd RunalystCore && swift test`.
- [ ] 1.2 [Senior | pro] Implement `TelemetryTick`, `KalmanFilter1D` (seed-on-first, predict-only on invalid/missing, valid ranges), `TelemetryRingBuffer` (capacity 900, O(1) append), and `RollingWindowStats` (30 s / 180 s, 80% coverage gate) in `RunalystCore/Sources/RunalystCore/PacingSignalCore.swift` per design D2 and spec `adaptive-pacing-core` (Kalman, Ring Buffer requirements). Verify: `./assay.sh`.
- [ ] 1.3 [Mid/Jnr | flash] Write Swift Testing suite `RunalystCore/Tests/RunalystCoreTests/PacingSignalCoreTests.swift` covering scenarios: seeding without ramp, artifact rejection (215 BPM spike), dropout handling, window coverage gate, constant memory at 7,200 ticks. Verify: `cd RunalystCore && swift test --filter PacingSignalCoreTests`.

## 2. Core Indicators (RunalystCore)

- [ ] 2.1 [Senior | pro] Implement `EfficiencyDriftTracker` (power/HR preferred, speed/HR fallback (outdoor only; indoor without power -> nil), EF_0 lock 300...600 s, source-consistency rule, 1.5% grade guard) and `BiomechanicalDegradationIndex` (GCT_0 / Cadence_0 lock, BDI formula, `gctDeltaFraction`, `cadenceDropSPM`, `formBreakdown`) in `RunalystCore/Sources/RunalystCore/PacingIndicatorsCore.swift` per spec `adaptive-pacing-core` (EF Drift, BDI requirements). Verify: `./assay.sh`.
- [ ] 2.2 [Mid/Jnr | flash] Write `RunalystCore/Tests/RunalystCoreTests/PacingIndicatorsCoreTests.swift` covering: cardiac drift -0.067, hill climb without power yields nil, power-source mismatch yields nil, indoor without power yields nil, form breakdown (240->260 ms, 168->163 SPM), relative baseline (275 ms @ 158 SPM stays false). Verify: `swift test --filter PacingIndicatorsCoreTests`.

## 3. Adaptive Pacing State Machine (RunalystCore)

- [ ] 3.1 [Senior | pro] Implement `AdaptivePacingConfiguration.standard`, `PacingState`, `PacingReason`, `PacingEvent`, `PaceDeviation`, `PacingDisplayState`, and `PacingLocation`, `AdaptivePacingCore.init(profile:intent:location:configuration:)`, `AdaptivePacingCore.ingest(_:)` (calibrating 600 s with 60 s extensions to 900 s and monitor-only fallback, 10 s evaluation cadence, back-on-target band) in `RunalystCore/Sources/RunalystCore/AdaptivePacingCore.swift` per design D2/D3. Verify: `./assay.sh`.
- [ ] 3.2 [Senior | pro] Implement RECOVER (EF, 30 s HR ceiling persistence, 2-evaluation form breakdown, 3/5/8% magnitudes), SURGE (all conditions + intent + distress + fallback gate, 2%), 90 s refractory, 10 s/km step cap, and 12% cumulative truncation in `RunalystCore/Sources/RunalystCore/AdaptivePacingCore+Triggers.swift` per design D5 and spec (Recover, Surge, Hysteresis requirements). Verify: `./assay.sh`.
- [ ] 3.3 [Senior | pro] Build a deterministic synthetic session generator `RunalystCore/Tests/RunalystCoreTests/PacingSessionFixtures.swift` (steady easy run, progressive heat drift, outdoor hill climb with and without power, HR ceiling 35 s vs 25 s, form collapse at minute 40, sensor dropout, 2-hour long run) with optional `TelemetryNoiseInjector`-style seeded noise (+/- 1.5 BPM HR, +/- 1.2 SPM cadence, +/- 0.08 m/s speed).
- [ ] 3.4 [Mid/Jnr | flash] Write `RunalystCore/Tests/RunalystCoreTests/AdaptivePacingCoreTests.swift` using 3.3 fixtures covering every `#### Scenario` under Calibrating, Recover, Surge, Hysteresis, Back-On-Target, and Sans-I/O determinism (replay equality) in `specs/adaptive-pacing-core/spec.md`. Verify: `swift test --filter AdaptivePacingCoreTests`.
- [ ] 3.5 [Mid/Jnr | flash] Add crucible timing test (7,200 ticks, median ingest < 0.1 ms) to `AdaptivePacingCoreTests.swift` and register it with the `./assay.sh` crucible gate if the script enumerates crucible tests explicitly. Verify: `./assay.sh`.

## 4. Athlete Calibration & Intent Mapping (RunalystCore)

- [ ] 4.1 [Senior | pro] Implement `AthleteCalibrationProfile`, `PacingIntentKind`, `PacingSessionIntent`, `WatchPacingContext` (schemaVersion 1), `AthleteCalibrationCore.makeProfile(buckets:restingHRSamples:age:windowEnd:)` (60 s sustained peak over 180 days, Tanaka fallback, 190 fallback, median resting HR, p75 power/HR), and `AthleteCalibrationCore.intent(for:subjectiveDistress:day:)` mapping a `SessionSynthesisCore` prescription to `PacingSessionIntent` in `RunalystCore/Sources/RunalystCore/AthleteCalibrationCore.swift`. Use explicit `windowEnd`, never `Date()`. Verify: `./assay.sh`.
- [ ] 4.2 [Mid/Jnr | flash] Write `RunalystCore/Tests/RunalystCoreTests/AthleteCalibrationCoreTests.swift` covering observed max HR 187, age fallback 180, empty-everything 190, recovery prescription -> `recovery`, interval prescription -> `intervals`, Codable round-trip, unknown `schemaVersion` detection helper. Verify: `swift test --filter AthleteCalibrationCoreTests`.

## 5. watchOS Target Scaffold (Foundry)

- [ ] 5.1 [Mid/Jnr | flash] Add `RunalystWatch` watchOS app target (deployment target watchOS 26) to `Runalyst.xcodeproj` (companion to `Runalyst`, links local `RunalystCore` package), with HealthKit entitlement, `WKBackgroundModes: workout-processing`, `NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription`, `NSMotionUsageDescription`. Add `RunalystWatch/` to SwiftLint and reverse Air-Gap scope in `./assay.sh` / `.swiftlint.yml`. Verify: `xcodebuild -scheme RunalystWatch -destination 'generic/platform=watchOS Simulator' build`.

## 6. watchOS Runtime Adapters (Foundry)

- [ ] 6.1 [Mid/Jnr | flash] Implement `RunalystWatch/WorkoutManager.swift` (`HKWorkoutSession` + `HKLiveWorkoutBuilder`, outdoor/indoor, start/pause/resume/end, authorization for the six quantity types, save on end) per spec `watch-adaptive-pacing-runtime` (Session Lifecycle).
- [ ] 6.2 [Mid/Jnr | flash] Implement `RunalystWatch/MotionStreamService.swift` (`CMPedometer` always; 50 Hz `CMMotionManager` only when `.indoor` and not paused; `CMAltimeter` relative altitude for grade input) exposing `AsyncStream`s. No thresholds or step-detection math beyond passing raw values; IMU step frequency extraction, if non-trivial, must be requested as a Core addition.
- [ ] 6.3 [Senior | pro] Implement `RunalystWatch/TelemetryEngine.swift` as `actor`: per-metric latest-value cache, 5 s staleness to `nil`, one `TelemetryTick` per whole elapsed second from `builder.elapsedTime` (pause excluded), owns `AdaptivePacingCore`, publishes to `@MainActor @Observable PacingViewModel`. Swift 6 strict concurrency clean. Per design D6.
- [ ] 6.4 [Mid/Jnr | flash] Implement `RunalystWatch/FeedbackDispatcher.swift`: `switch` over `PacingEvent` -> haptic / localized cue / accent token per spec table; 1.5 s haptic serialization; `AVAudioSession` `.playback` + `.duckOthers`, deactivate after cue; voice toggle via `@AppStorage("watchVoiceCuesEnabled")` default false.
- [ ] 6.5 [Mid/Jnr | flash] Implement `RunalystWatch/WatchContextStore.swift` (`WCSessionDelegate`, decode `WatchPacingContext`, reject higher `schemaVersion`, persist JSON in `UserDefaults`, resolve active context vs fallback per spec `watch-calibration-handoff`). Day-matching uses a Core helper, not inline date math.

## 7. watchOS Hollow Views (Foundry)

- [ ] 7.1 [Mid/Jnr | flash] Implement `RunalystWatch/Views/StartRunView.swift` (indoor/outdoor picker, target pace picker shown only when context resolution requires it, defaulting to "Just Run", 44x44pt controls) and `RunalystWatch/Views/PacingGaugeView.swift` (pure black background, binds only to `PacingDisplayState`, `SF Pro Rounded` + `.monospacedDigit()`, accent tokens Electric Blue / Neon Pink / Vibrant Green, calibration progress, refractory countdown). Zero arithmetic or thresholds.

## 8. iPhone Calibration Bridge (Foundry)

- [ ] 8.1 [Mid/Jnr | flash] Implement `Runalyst/Services/WatchCalibrationBridge.swift` (activate `WCSession`, guard `isPaired && isWatchAppInstalled`, encode `WatchPacingContext`, `updateApplicationContext`). Wire one call after `syncData()` completes in `ContentView.swift` and where today's prescription is resolved, passing values produced by `AthleteCalibrationCore`. Verify: `xcodebuild test` (iOS scheme) passes.

## 9. Verification

- [ ] 9.1 [Mid/Jnr | flash] Run `./assay.sh` (all gates), `swiftlint --strict` (0 violations, including `RunalystWatch/`), iOS `xcodebuild test`, and the watch build; audit `git diff` on `Runalyst/Views/`, `Runalyst/Models/`, and `RunalystWatch/` for leaked thresholds (`0.94`, `0.82`, `0.06`, `0.12`, `90`, `600`) or `.reduce` math. Report under 25 lines.
- [ ] 9.2 [Staff/Lead | parent] Manual on-device validation: one outdoor 60-minute run on Series 10 / Ultra 2 recording battery drop (< 12%), event log sanity, ducking behavior; one indoor treadmill run confirming IMU active and no false drift alerts. Record results in this change before `/opsx-verify`.
