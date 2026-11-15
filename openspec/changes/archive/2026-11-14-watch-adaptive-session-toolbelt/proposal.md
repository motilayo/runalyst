## Why

The Apple Watch running companion (`RunalystWatch`) currently receives a flat daily `PacingSessionIntent` and runs reactive, `30s`-cooldown alerts (`surge`, `recover`, `cadenceDrift`, `paceDrift`) with spoken voice cues, while the redundant `Just Run` pace-picker concept fails to convey runner intent and `Adaptive Base` overwrites iPhone-prescribed `.tempo` / readiness context back to `.steady`. Furthermore, `LiveMetronomeCore` sits unused on `RunalystWatch`, and live `.indoor` treadmill sessions trust noisy wrist-accelerometer speed identically to outdoor GPS.

Upgrading the existing `RunalystCore` engines (`AthleteCalibrationCore`, `AdaptivePacingCore`, `LiveMetronomeCore`, and `PacingSignalCore`) rather than building a separate engine turns `Adaptive Base`, `Push / Performance`, and `Recovery` into truly intelligent, on-the-fly session shapers that:
1. Respect pre-run readiness and recent limiters (including days since last run and non-running walking load).
2. Adapt dynamically on the Watch display without vocalizing block shifts (`PacingGaugeView`).
3. Nudge turnover and effort via gradual, short-burst (`15–20s`) tactile feedback with `4–5 min` quiet checkpoint budgets and anticipatory phase-boundary cues.
4. Anchor indoor treadmill sessions on Heart Rate, `50 Hz` IMU Cadence, and Power so wrist-speed noise never triggers false drift alerts.

## What Changes

- **Intent & Readiness Handoff Upgrade (`AthleteCalibrationCore`, `WatchTargetPaceOption`, `WatchCalibrationBridge`, `SessionSynthesisEngine`)**:
  - Preserve iPhone's daily readiness & limiter context inside `WatchPacingContext` (`daysSinceLastRun`, `recentNonRunningWalkMeters`, `recentCadenceLag`, `readinessSignal`) so Watch sessions know when legs are fresh vs. stiff/fatigued.
  - Prevent `WatchResolvedSessionConfig.applying(runIntent: .adaptiveBase)` from silently erasing iPhone's daily session intent (only `.recovery` strictly overrides downward per the Protection Mandate, and `.pushPerformance` explicitly opts into ceiling exploration).
  - Retire the dead/redundant `Just Run` target-pace wheel concept in `StartRunView` / `WatchTargetPaceOption` so the 3 Watch intents (`Adaptive Base`, `Push / Performance`, `Recovery`) are the single unambiguous control surface, and update `RunalystWatchAppDelegate.handle(_:)` so iPhone-to-Watch handoffs do not drop `targetPaceSecondsPerKm` via `requiresTargetPacePicker`.
  - Guard `BanisterReadinessCore` / `ReadinessEvaluator` against false-positive `.deload` classification when a `2–4` day rest/walk gap causes an earlier run to roll outside the strict `7`-day acute window despite healthy prior-week mileage.
- **Visual-Only On-the-Fly Session Blocks & Debrief (`AdaptivePacingCore`, `WatchCompanionStateCore`, `WatchRunDebriefCore`, `PacingGaugeView`)**:
  - Add timed micro-block orchestration (`AdaptiveBlockKind`: e.g., `cadenceReset`, `thresholdSurge`, `cooldownFloor`, `effortEase`) with mid-block physiological/behavioral backoffs inside `AdaptivePacingCore` (companion file `AdaptivePacingCore+SessionBlocks.swift`).
  - Surface active block state, countdown, and stepped target visually in `PacingDisplayState` and `PacingGaugeView`'s top capsule / target strip (`voiceCueText: nil` across drift, form, surge, recover, and adaptive block transitions so treadmill runs stay quiet), and summarize executed/backed-off blocks inside `WatchRunDebriefCore`.
- **Gradual Short-Burst Tactile Entrainer (`LiveMetronomeCore`, `AdaptivePacingCore+Triggers`, `FeedbackDispatcher`)**:
  - Upgrade `LiveMetronomeCore` with bidirectional ramp math (`SteppedMetronomeRamp`) that meets the runner's current cadence and steps gradually (`+2` to `+4 SPM` per rung) during a `15–20s` burst, stopping immediately once locked for `5s` or backing off cleanly after `20s` until the next `4–5 min` checkpoint or anticipatory phase transition (e.g., `Cadence Pyramids` work rep or `Tempo Surges` cooldown floor).
  - Enforce distinct tactile semantics: crisp rhythmic `.click` ticks strictly for **cadence/turnover** (never lowering BPM to slow down, avoiding overstriding), and spaced `.descendingDoublePulse` / `.ascendingDoublePulse` cues (`3–4s` spacing during a short correction window) strictly for **pace/effort** down- or up-regulation.
  - Wire a dedicated, duty-cycled haptic pulse scheduler into `RunalystWatch/FeedbackDispatcher.swift` decoupled from the `1.5s` discrete alert cooldown.
- **Live Indoor Treadmill Reliability (`PacingSignalCore`, `AdaptivePacingCore`, `WorkoutManager`)**:
  - Apply indoor wrist-speed outlier clamping (`25%` window) and heavier Kalman measurement damping (`R`) when `location == .indoor`.
  - Anchor indoor calibration and adaptive block triggers on Heart Rate, `50 Hz` IMU Cadence, and Power (when available), suppressing false `"too fast / too slow"` pace-drift bursts caused by outdoor-vs-treadmill calibration offsets or brief console/water-bottle arm-swing drops.

## Capabilities

### New Capabilities
- `watch-adaptive-session-blocks`: On-the-fly visual-only micro-block selection and timing inside `AdaptivePacingCore` driven by pre-run readiness/limiters and live min 0–5 calibration telemetry.
- `watch-gradual-tactile-entrainer`: Short-burst (`15–20s`), gradual stepped `.click` metronome entrainment for cadence/cooldown floors and distinct slow directional pulses for effort/pace regulation with `4–5 min` quiet checkpoint budgets and anticipatory phase-boundary triggers.
- `watch-treadmill-live-reliability`: Live `.indoor` treadmill guardrails anchoring Watch blocks on HR, IMU cadence, and power while damping and outlier-clamping raw wrist speed.

### Modified Capabilities
- `watch-zero-friction-companion`: Update Watch intent resolution so `Adaptive Base` preserves iPhone's synthesized readiness context rather than flattening `.tempo` to `.steady`, retire the unused `Just Run` target-pace picker flow, shift adaptive block notifications from vocalized speech to visual-only `PacingGaugeView` capsule states, and replace `30s` pace/cadence nagging cooldowns with `4–5 min` short-burst checkpoints.

## Impact & Air-Gap Assessment

- **Architectural Boundaries Touched**:
  - **RunalystCore (Sans-I/O Core)**: `LiveMetronomeCore.swift` (`154` LOC), `AdaptivePacingCore.swift` (`559` LOC -> unchanged or trimmed via new companion `AdaptivePacingCore+SessionBlocks.swift`), `AdaptivePacingCore+Triggers.swift` (`373` LOC), `AdaptivePacingCore+Presentation.swift` (`533` LOC -> keep additions minimal or extract `AdaptivePacingCore+FeedbackSpec.swift`), `AthleteCalibrationCore.swift` (`427` LOC), `WatchTargetPaceOption.swift` (`204` LOC), `PacingSignalCore.swift` (`432` LOC), `WatchCompanionStateCore.swift` (`306` LOC). Zero Apple UI/HealthKit/SwiftData imports; zero `Date()` wall-clock calls.
  - **Runalyst Foundry (iOS Adapters)**: `WatchCalibrationBridge.swift` (`407` LOC), `SessionSynthesisEngine.swift` (`1610` LOC — thin wiring to pass readiness/walk-load metadata), `HealthKitManager.swift` (optional non-running walk distance query for readiness context without polluting `RunRecord`).
  - **RunalystWatch (Hollow Views & Services)**: `FeedbackDispatcher.swift` (`203` LOC), `TelemetryEngine.swift` (`275` LOC), `WatchContextStore.swift` (`262` LOC), `StartRunView.swift` (`224` LOC), `PacingGaugeView.swift` (`478` LOC — strictly hollow bindings to `PacingDisplayState`).
- **500-LOC Soft Modularity Guideline**: Files already near or above `500` LOC (`AdaptivePacingCore.swift`, `AdaptivePacingCore+Presentation.swift`, `PacingGaugeView.swift`) will not be bloated; new block-state logic will live in `AdaptivePacingCore+SessionBlocks.swift` and `PacingGaugeView` will only bind to pre-computed display properties.
- **Verification**: All changes must pass `./assay.sh` (Directory Air-Gap check, `swiftlint --strict`, Grounded Voice audit, and `swift test` in `RunalystCore`) plus Xcode build/test on iOS & watchOS schemes.
