## Context

- Runalyst today is iPhone-only. There is **no watchOS target**, no `WorkoutManager`, and no live `WCSession` (inert WCSession code was removed under `fitness-awards-and-live-metronome`). The Watch currently receives only `WorkoutKit` `CustomWorkout`s scheduled from the phone.
- `RunalystCore/Package.swift` declares `.iOS(.v17)` and `.macOS(.v14)`; Core tests use Swift Testing (`@Test`, `#expect`).
- Relevant existing Core: `TheMold.swift` (`TelemetryBucket`, `efficiencyFactor` = speed/HR), `FramboiseCore.swift` (maxHR default 190), `PhysiologicalDiagnosisCore.swift` (`CardiacBehaviorVerdict`), `SessionSynthesisCore.swift` (prescription, `AthleteSynthesisContext`), `TrainingZoneCore.swift` (`PaceRange`). `RunnerProfile` (Foundry) has `age` and `vo2Max` but no max/resting HR.
- The source specification was a draft containing a CoreML box, hardcoded thresholds (`gct > 260 && cadence < 165`, `HR < 155`), and `Date()` inside the engine. This design keeps its control-loop intent and replaces those parts with deterministic, relative, Sans-I/O equivalents.

## Goals / Non-Goals

**Goals:**
- A pure, replayable `AdaptivePacingCore` state machine in RunalystCore, fully covered by golden synthetic-session tests.
- A thin standalone watchOS app that hosts the core during a run and delivers haptic, audio, and visual nudges.
- Profile and intent handoff from iPhone so watch thresholds are personal, with safe behavior when absent.

**Non-Goals:**
- CoreML or any learned model on the wrist.
- Post-run transfer of the pacing event log or Glass-Box modal of watch decisions on iPhone (follow-up change).
- Shock attenuation profiling from the IMU; IMU is only used for indoor cadence cross-check.
- Adaptive pacing inside structured interval workouts (WorkoutKit owns those).
- Changes to iPhone views.

## Decisions

### D1. Directory and module layout
```
RunalystCore/Sources/RunalystCore/
  PacingSignalCore.swift            KalmanFilter1D, TelemetryTick, TelemetryRingBuffer, RollingWindowStats
  PacingIndicatorsCore.swift        EfficiencyDriftTracker, BiomechanicalDegradationIndex
  AdaptivePacingCore.swift          AdaptivePacingCore, PacingState, PacingEvent, PacingDisplayState
  AdaptivePacingCore+Triggers.swift RECOVER / SURGE evaluation, damping math
  AthleteCalibrationCore.swift      AthleteCalibrationProfile, PacingSessionIntent, WatchPacingContext, mapping
RunalystWatch/                      (new watchOS app target)
  RunalystWatchApp.swift, WorkoutManager.swift, MotionStreamService.swift,
  TelemetryEngine.swift, FeedbackDispatcher.swift, WatchContextStore.swift,
  Views/PacingGaugeView.swift, Views/StartRunView.swift
Runalyst/Services/WatchCalibrationBridge.swift
```
*Alternative considered:* a separate `RunalystPacingCore` package. Rejected — it duplicates the Air-Gap and assay tooling; adding `.watchOS(.v10)` to the existing package is enough because Core is Foundation-only.

### D2. Core public API (exact signatures)
```swift
public struct TelemetryTick: Sendable, Equatable {
    public let elapsedSeconds: TimeInterval
    public let heartRateBPM: Double?
    public let speedMetersPerSecond: Double?
    public let powerWatts: Double?
    public let cadenceSPM: Double?
    public let imuCadenceSPM: Double?
    public let groundContactTimeMs: Double?
    public let verticalOscillationCm: Double?
    public let strideLengthMeters: Double?
    public let gradeFraction: Double?          // nil when unknown
}

public struct KalmanFilter1D: Sendable {
    public init(processNoise: Double, measurementNoise: Double, validRange: ClosedRange<Double>)
    public mutating func step(_ measurement: Double?) -> (estimate: Double?, isValid: Bool)
}

public struct AthleteCalibrationProfile: Sendable, Codable, Equatable {
    public let maxHR: Double
    public let restingHR: Double?
    public let powerToHRTopQuartile: Double?
    public let isFallback: Bool
}

public enum PacingLocation: String, Sendable, Codable { case outdoor, indoor }

public enum PacingIntentKind: String, Sendable, Codable {
    case recovery, easyAerobic, steady, tempo, progression, intervals
}

public struct PacingSessionIntent: Sendable, Codable, Equatable {
    public let targetPaceSecondsPerKm: Int?
    public let intent: PacingIntentKind
    public let subjectiveDistress: Bool
    public let validForDay: String               // "yyyy-MM-dd", en_US_POSIX
}

public struct WatchPacingContext: Sendable, Codable, Equatable {
    public let schemaVersion: Int                // 1
    public let profile: AthleteCalibrationProfile
    public let intent: PacingSessionIntent
}

public enum PacingState: Sendable, Equatable {
    case calibrating(progress: Double)
    case tracking
    case surge, recover                          // transient, held during refractory
}

public enum PacingReason: String, Sendable { case efficiencyDrift, heartRateCeiling, formBreakdown, compound, reservesAvailable }

public enum PacingEvent: Sendable, Equatable {
    case calibrationComplete(originalTargetSecondsPerKm: Int, adjustmentsEnabled: Bool)
    case surge(deltaSecondsPerKm: Int, newTargetSecondsPerKm: Int)
    case recover(deltaSecondsPerKm: Int, newTargetSecondsPerKm: Int, reason: PacingReason)
    case backOnTarget
}

public enum PaceDeviation: Sendable { case onTarget, tooFast, tooSlow, unknown }

public struct PacingDisplayState: Sendable, Equatable {
    public let state: PacingState
    public let targetPaceSecondsPerKm: Int?
    public let filteredPaceSecondsPerKm: Int?
    public let filteredHeartRateBPM: Int?
    public let deviation: PaceDeviation
    public let refractorySecondsRemaining: Int
    public let lastReason: PacingReason?
    public let adjustmentsEnabled: Bool
}

public struct AdaptivePacingCore: Sendable {
    public init(profile: AthleteCalibrationProfile, intent: PacingSessionIntent, location: PacingLocation, configuration: AdaptivePacingConfiguration = .standard)
    public mutating func ingest(_ tick: TelemetryTick) -> (events: [PacingEvent], display: PacingDisplayState)
}
```
`AdaptivePacingConfiguration.standard` holds every threshold from the spec (300/600/900 s calibration, 10 s evaluation, 90 s refractory, 10 s/km step, 12% cumulative, 0.82 / 0.94 HR fractions, -0.06 / -0.01 ΔEF, 7% GCT, 4 SPM, 2.0 SPM σ, 2/3/5/8% magnitudes, 1.5% grade guard, 80% coverage). Tests construct custom configurations; production uses `.standard`.

*Alternative considered:* an `actor` in Core. Rejected — a `mutating` struct is deterministic, trivially testable, and the Foundry `actor TelemetryEngine` already provides isolation.

### D3. Calibration window is 600 s, not 300 s
The draft says CALIBRATING lasts 300 s yet derives `EF_0` from 300...600 s — contradictory. We discard 0...300 s (VO2 and stroke-volume kinetics) and lock baselines over 300...600 s, so adjustments start at 600 s. The original target pace is the intent's `targetPaceSecondsPerKm` when present, else the 300...600 s mean filtered pace (`Pace_0`).
*Alternative:* lock at 300 s from a 120...300 s window. Rejected — HR is still rising in that window, which would bias `EF_0` high and produce false drift.

### D4. Power-based EF with speed fallback and grade guard
Raw speed/HR collapses on hills and would fire "cardiac drift" on every climb. Apple Watch running power already accounts for grade, so EF uses power/HR when power coverage is at least 80%. Speed/HR is the fallback, suspended when |grade| > 1.5%. Grade is supplied by the Foundry from `CMAltimeter` relative altitude over pedometer distance; if unavailable, `gradeFraction` is `nil` and speed-based ΔEF stays active On `.indoor` sessions speed-based EF is disabled entirely (see D9).
*Alternative:* Grade-Adjusted Pace model in Core. Deferred — more math with less accuracy than the watch's own power estimate.

### D5. Conservative trigger ordering
RECOVER is evaluated before SURGE and is never intent-gated (Protection Mandate). SURGE needs every condition plus a non-fallback profile and a progressive intent. Missing data never satisfies a SURGE condition; missing data never triggers a RECOVER either (it just suspends that trigger). Form breakdown needs two consecutive evaluations (20 s) to avoid single-window GCT noise.

### D6. Hollow watch Foundry
`TelemetryEngine` aligns samples: it caches the latest value and timestamp per metric, and on every whole second of `builder.elapsedTime` (driven by a 1 s `AsyncTimerSequence` checked against elapsed time, with pause excluded) emits one `TelemetryTick`. It owns one `AdaptivePacingCore` and publishes `(events, display)` to a `@MainActor @Observable` `PacingViewModel`. `FeedbackDispatcher` is a pure `switch` over `PacingEvent` -> `(WKHapticType, LocalizedStringResource?, AccentToken)`.

### D7. WatchConnectivity via application context
`updateApplicationContext` delivers the latest state only and survives the watch app not running, which is exactly the "last known profile" semantic. Watch persists it to `UserDefaults` (JSON). `transferUserInfo` (queued history) and `sendMessage` (requires reachability) are not needed.

### D8. Engineering tiers
- **Senior | pro:** D2 Core types, Kalman, ring buffer, indicators, state machine, calibration derivation, golden session tests (all in RunalystCore); `TelemetryEngine` actor concurrency.
- **Mid/Jnr | flash:** Xcode target scaffold, `WorkoutManager`, `MotionStreamService`, `FeedbackDispatcher`, `WatchContextStore`, views, `WatchCalibrationBridge`, entitlements and plist keys, fixture builders.

## Risks / Trade-offs

- [Optical HR lag (10–20 s) makes the loop sluggish] → 30 s ceiling persistence, 90 s refractory, and 10 s/km step cap keep the loop slower than the sensor lag; it nudges, never chases.
- [Indoor treadmill incline is invisible; speed-based EF drops on an incline] → indoor sessions use power-based EF only; without power, EF triggers are disabled for the session (D10).
- [Heat-driven drift is real fatigue, not noise] → intended: RECOVER on heat drift is correct behavior per the Protection Mandate.
- [Voice cues fight with music / Siri] → `.duckOthers` + deactivate after each cue; haptic-only toggle.
- [New watch target increases CI build time and code signing surface] → watch target added to the scheme but Core tests remain the assay crucible; watch build verified with `xcodebuild -scheme RunalystWatch -destination 'generic/platform=watchOS' build`.
- [maxHR fallback 208 - 0.7 × age can be off by +/- 10 BPM] → fallback profile disables SURGE entirely; RECOVER at 0.94 × a possibly-low maxHR errs toward safety.
- [Battery budget unverifiable in CI] → manual on-device measurement task with recorded result.

## Migration Plan

Additive only: no SwiftData schema changes, no changes to existing Core behavior. Rollback = remove the watch target from the scheme and stop calling `WatchCalibrationBridge`; Core additions are inert if unused. Ship behind the watch app's own install — iPhone-only users are unaffected.

## Resolved Decisions (formerly Open Questions)

- **D9. Platform floors:** Package declares `.watchOS(.v10)` (Foundation-only Core, matching the package's iOS 17 floor). The `RunalystWatch` app target deploys at watchOS 26 to match the iOS 26 app.
- **D10. Indoor without power:** speed-based EF is disabled indoors (ΔEF is `nil` for the session). A guessed stricter threshold would still false-alarm on unannounced incline; HR ceiling and form breakdown keep the Protection Mandate intact.
- **D11. No phone intent:** the watch offers a target pace picker whose default is "Just Run" (`targetPaceSecondsPerKm == nil`), so the core adapts around `Pace_0` from the 300...600 s window.
- **D12. Voice cues default off:** haptics on by default; voice cues opt-in via `watchVoiceCuesEnabled` (default false).
