## Why

Runalyst prescribes locked pace and duration bands on iPhone, but once the runner starts moving there is no closed loop: a runner whose heart rate drifts 7% on a hot day, or whose form collapses at minute 40, gets the same target they started with. The Blueprint names the Apple Watch as the "Wrist-First Extension" that handles execution, not analysis — this change gives it a deterministic, on-wrist adaptive pacing engine that nudges the target up or down from filtered physiology, without a phone, a network, or an LLM in the loop.

## What Changes

- **Pure Adaptive Pacing Engine (`RunalystCore` — Sans-I/O Core)**:
  - New 1 Hz signal conditioning primitives: `KalmanFilter1D` (scalar random-walk with dropout-aware predict-only steps) and `TelemetryRingBuffer` (fixed-capacity flat buffer, 30 s short and 180 s long rolling windows).
  - New derived indicators: Efficiency Factor drift (`ΔEF`, power-per-beat preferred, speed-per-beat fallback with a grade guard) and Biomechanical Degradation Index (`BDI`, ground contact time vs cadence relative to the runner's own calibration window).
  - New finite state machine `AdaptivePacingCore` (`calibrating -> tracking -> surge | recover -> tracking`) with a 10 s evaluation cadence, 90 s refractory cooldown, `+/- 10 s/km` step cap, and `+/- 12%` cumulative session cap. All thresholds are relative to an `AthleteCalibrationProfile` (max HR, resting HR, top-quartile power-to-HR) — no hardcoded `165 SPM` / `155 BPM` constants.
  - Protection Mandate gate: `SURGE` is locked out when the session intent is `recovery` / `easyAerobic` or when the runner has reported subjective distress.
  - New `AthleteCalibrationCore` that derives the profile (max HR, resting HR, power-to-HR quartiles) from historical `TelemetryBucket` data on iPhone.
  - `Package.swift` adds `.watchOS(.v10)` (the watch app target itself deploys at watchOS 26, matching the iOS 26 app) so the same Foundation-only package compiles for the watch.
- **New watchOS Foundry (`RunalystWatch` target)**:
  - `WorkoutManager` (`HKWorkoutSession` + `HKLiveWorkoutBuilder`, outdoor / indoor), `MotionStreamService` (`CMPedometer` always; 50 Hz `CMMotionManager` only for indoor treadmill cadence verification), `TelemetryEngine` (`actor` shell that aligns samples to 1 Hz ticks and forwards them to `AdaptivePacingCore`), and `FeedbackDispatcher` (`WKInterfaceDevice` haptics + ducked `AVAudioSession` voice cues).
  - Hollow SwiftUI pacing gauge on a pure black background, bound only to `AdaptivePacingCore` output.
- **iPhone -> Watch Calibration Handoff (`Runalyst` Foundry)**:
  - Phone computes `AthleteCalibrationProfile` + today's `PacingSessionIntent` (target pace, intent) via RunalystCore and pushes them with `WCSession.updateApplicationContext`. Watch runs standalone with the last received context; with no context it runs in a conservative fallback (SURGE disabled).
- **Explicit non-goals for this change**: no CoreML (the diagram's "CoreML" box is replaced by the deterministic state machine), no post-run pacing-event log transfer, no shock attenuation profiling.

## Capabilities

### New Capabilities
- `adaptive-pacing-core`: Pure, deterministic 1 Hz signal conditioning (Kalman, ring buffer, rolling windows), EF drift and BDI indicators, athlete calibration derivation, and the hysteresis-damped CALIBRATING / TRACKING / SURGE / RECOVER state machine in RunalystCore.
- `watch-adaptive-pacing-runtime`: Standalone watchOS workout runtime (HealthKit session, CoreMotion streams, 1 Hz tick alignment, haptic + audio + UI feedback delivery) acting as a hollow adapter over `adaptive-pacing-core`.
- `watch-calibration-handoff`: iPhone-to-watch delivery of `AthleteCalibrationProfile` and today's `PacingSessionIntent` via WatchConnectivity, with deterministic watch-side fallback when no context exists.

### Modified Capabilities
<!-- None. `fitness-awards-and-live-metronome` removed *inert* WCSession code; this change introduces a new, purpose-built WCSession channel under its own capability without altering that requirement's behavior for the metronome. -->

## Impact & Air-Gap Assessment

- **`RunalystCore` (Sans-I/O Reference Core)** — new files, all `import Foundation` only, zero `Date()` (time enters as `elapsedSeconds: TimeInterval`), zero force-unwraps:
  - `PacingSignalCore.swift` (~220 LOC): `KalmanFilter1D`, `TelemetryTick`, `TelemetryRingBuffer`, `RollingWindowStats`.
  - `PacingIndicatorsCore.swift` (~200 LOC): `EfficiencyDriftTracker`, `BiomechanicalDegradationIndex`.
  - `AdaptivePacingCore.swift` (~420 LOC) + `AdaptivePacingCore+Triggers.swift` (~200 LOC): state machine, triggers, damping.
  - `AthleteCalibrationCore.swift` (~200 LOC): profile derivation.
  - `Package.swift`: adds `.watchOS(.v10)` platform. Existing files untouched.
- **`Runalyst` (iOS Foundry)**: new `Runalyst/Services/WatchCalibrationBridge.swift` (~150 LOC) — hollow `WCSession` adapter. One call site added where today's prescription is already resolved.
- **`RunalystWatch` (new watchOS Foundry target)**: ~6 files, each well under 500 LOC. New `.xcodeproj` target, entitlements (HealthKit, `workout-processing` background mode), and `NSHealthShareUsageDescription` / `NSMotionUsageDescription`.
- **Hollow Views**: watch views bind only to `PacingDisplayState` emitted by RunalystCore; no thresholds or arithmetic in views.
- **Dependencies**: no third-party additions. Frameworks: HealthKit, CoreMotion, WatchKit, AVFoundation, WatchConnectivity (Foundry only).
- **Verification**: `./assay.sh` gates (Air-Gap, determinism, reverse Air-Gap, `swiftlint --strict`, LOC advisory, Grounded Voice, crucible) apply to all new Core files; the watch target is added to the lint scope.
