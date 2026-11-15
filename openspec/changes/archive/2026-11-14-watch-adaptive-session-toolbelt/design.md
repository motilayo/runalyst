## Context

Runalyst separates deterministic sports science (`RunalystCore`) from iOS/watchOS infrastructure (`Runalyst` and `RunalystWatch`). Today, four related gaps prevent the Watch companion from behaving as a truly adaptive, low-distraction coaching instrument:

1. **Intent & Readiness Drop-off**: `SessionSynthesisEngine` and `BanisterReadinessCore` already compute training readiness, recovery clocks, and biomechanical limiters (`detectRecentLimiters`), yet `WatchPacingContext` / `PacingSessionIntent` omits days-since-last-run, non-running walk load, and limiter flags. Worse, `WatchResolvedSessionConfig.applying(runIntent: .adaptiveBase)` in `WatchTargetPaceOption.swift` overwrites iPhone's `.tempo` intent back to `.steady` and forces `requiresTargetPacePicker = false` (leaving the `"Just Run"` wheel dead code).
2. **Flat In-Run State Machine**: `AdaptivePacingCore` (`559` LOC) only supports binary `surge` / `recover` pace steps and `30s` naggy drift alerts, with no timed visual micro-block orchestration (e.g., opening a `Cadence Reset` block if legs start stiff after 4 days off running, then opening a `Threshold Block` once warm and HR is green, or guarding a `Cooldown Floor` after tempo surges).
3. **Unused & Unidirectional Metronome**: `LiveMetronomeCore` (`154` LOC) already implements `beatIntervalSeconds(forTargetSPM:)` and duty-cycling, but is only wired on iPhone (`LiveCoachEngine`) and has no bidirectional ramp or watchOS haptic ticker in `FeedbackDispatcher` (`203` LOC).
4. **Live Treadmill Blind Spot**: Post-run `TreadmillKinematicsCore` smooths wrist pace and clamps `25%` outliers, and `EfficiencyDriftTracker` skips `.speed` fallback indoors, yet live `AdaptivePacingCore` uses identical `KalmanFilter1D.standardSpeed` (`Q = 0.02, R = 0.25`) and `max(5 s/km, 2%)` pace-drift alerts for `.indoor` and `.outdoor`.

## Goals / Non-Goals

- **Goals**:
  - Upgrade existing `RunalystCore` engines (`AthleteCalibrationCore`, `AdaptivePacingCore`, `LiveMetronomeCore`, `PacingSignalCore`) rather than building a separate engine ("1 more tool in the toolbelt").
  - Preserve iPhone's daily readiness & limiter context across `WatchPacingContext`, including days since last run and recent non-running walking volume (`HealthKitManager`), while keeping `StartRunView` strictly 3-intent (`Adaptive Base`, `Push / Performance`, `Recovery`) with no `"Just Run"` wheel.
  - Render adaptive micro-block transitions (`Cadence Reset`, `Threshold Block`, `Cooldown Floor`) visually on `PacingGaugeView` without vocalizing them (`voiceCueText: nil`).
  - Deliver short-burst (`15–20s`), gradual stepped `.click` metronome entrainment for cadence/cooldown floors and distinct spaced `.descendingDoublePulse` / `.ascendingDoublePulse` cues (`3–4s` spacing) for effort/pace regulation, backed by `4–5 min` quiet checkpoint budgets and anticipatory phase-boundary triggers.
  - Stabilize `.indoor` treadmill runs by anchoring blocks on HR, `50 Hz` IMU cadence, and Power while damping/outlier-clamping wrist speed and suppressing false outdoor-target pace-drift alerts.
- **Non-Goals**:
  - Reintroducing manual target-pace pickers or workout builders on Apple Watch (`StartRunView`).
  - Persisting walking workouts as `RunRecord` entities in SwiftData (walks remain lightweight readiness context only).
  - Running continuous 40-minute wrist metronome haptics (battery and sensory habituation hazard).

## Decisions

### 1. Intent Preservation & Readiness Handoff (`AthleteCalibrationCore` + `WatchTargetPaceOption`)
- **Decision**: Extend `PacingSessionIntent` (and `WatchPacingContext` schema v2, backward-compatible via optional properties with defaults) with a lightweight `WatchReadinessHint` struct:
  ```swift
  public struct WatchReadinessHint: Sendable, Codable, Equatable {
      public let daysSinceLastRun: Int?
      public let recentWalkMeters48h: Double?
      public let hadRecentCadenceFade: Bool
      public let hadRecentBounce: Bool
      public let calibratedCadenceFloorSPM: Int?
      public let isClearedForQuality: Bool
  }
  ```
- **Intent Resolution Rule (`WatchResolvedSessionConfig.applying(runIntent:)`)**:
  - `.recovery` always forces `intent = .recovery` and suppresses upward surges/blocks (Protection Mandate).
  - `.pushPerformance` forces `intent = .tempo` (unless `subjectiveDistress == true`, which preserves `.recovery`).
  - `.adaptiveBase` **preserves** iPhone's synthesized `intent` (`cachedContext.intent.intent`, e.g., `.tempo` on a fresh 10K quality day or `.easyAerobic` during consolidation) instead of wiping it to `.steady`, falling back to `.steady` only when context is stale or missing.
  - Remove `requiresTargetPacePicker` presentation from `StartRunView` and update `RunalystWatchAppDelegate.handle(_:)` in `RunalystWatchApp.swift` to pass `resolved.intent.targetPaceSecondsPerKm` directly rather than gating on `requiresTargetPacePicker`. Mark `WatchTargetPaceOption` legacy-deprecated so `Adaptive Base` owns open-ended adaptive runs.
- **Alternative Considered**: Adding a 4th `"Follow Plan"` button on Watch. Rejected to preserve the 3-choice zero-friction Watch start screen.

### 2. Visual-Only Adaptive Micro-Blocks (`AdaptivePacingCore+SessionBlocks.swift`)
- **Decision**: Keep `AdaptivePacingCore.swift` (`559` LOC) compact by placing micro-block orchestration in a companion file `AdaptivePacingCore+SessionBlocks.swift`.
- **Types**:
  ```swift
  public enum AdaptiveBlockKind: String, Sendable, Codable, Equatable {
      case none
      case cadenceReset      // timed 3-min turnover pickup when opening cadence < floor/baseline
      case thresholdSurge    // timed 4-min quality block when fresh & HR/EF green
      case cooldownFloor     // post-surge or recovery cadence floor guard
      case effortEase        // down-regulation window when HR ceiling or EF drift triggers
  }

  public struct AdaptiveBlockState: Sendable, Equatable {
      public let kind: AdaptiveBlockKind
      public let remainingSeconds: Int
      public let blockTargetCadenceSPM: Int?
      public let blockTargetPaceSecondsPerKm: Int?
      public let displayBadgeText: String   // e.g. "CADENCE 158->162 • 2:45"
  }
  ```
- **Visual-Only Rule & Silent Drift/Block Policy**: Block transitions emit `.adaptiveBlockChanged(AdaptiveBlockState)` whose `PacingEventFeedbackSpec` sets `voiceCueText: nil` and `accentToken` (`.vibrantGreen` / `.surgeTeal` / `.recoverAmber`), surfaced via new pre-computed fields on `PacingDisplayState` (`activeBlockBadge: String?`, `activeBlockRemainingFormatted: String?`, `tactileNudgeStatusLabel: String?`). `PacingEventFeedbackSpec` in `AdaptivePacingCore+Presentation.swift` also sets `voiceCueText: nil` for `.paceDrift`, `.cadenceDrift`, `.formCheck`, `.surge`, and `.recover` so treadmill runs stay visually and tactually driven without voice chatter. `PacingGaugeView` binds strictly to these strings with zero arithmetic.
- **Post-Run Debrief Block Accumulators (`WatchRunDebriefCore`)**: Track `cadenceResetCount`, `thresholdBlockCount`, `effortEaseCount`, and `blockBackoffCount` on `AdaptivePacingCore` so `buildRunDebrief` surfaces executed and backed-off blocks in `adaptationsBullet` alongside surges/recovery adjustments.
- **Block-Level Backoffs (`AdaptiveBlockBackoffTracker`)**:
  - *Physiological Abort*: If HR breaches block ceiling, `deltaEF <= recoverEfficiencyDriftThreshold`, or `2` consecutive `BDI` form breakdowns occur mid-block, abort immediately into `.effortEase` and set a `480s` (`8 min`) upward-block lockout.
  - *Behavioral Non-Adoption (`60s`)*: If the runner stays on steady baseline effort/cadence for `60.0s` after a block opens without moving toward the block target, dissolve silently back to `kind: .none` and double the next proposal cooldown (`300s -> 600s`).
  - *Session Cap (`Max 2`)*: After `2` aborts or non-adoptions in one workout, disable further adaptive block proposals for the rest of the run (preserving safety-only `.effortEase`).
- **Alternative Considered**: Using spoken AVSpeechSynthesizer prompts for every block change. Rejected per user direction ("put it on the display, no need to vocalize it").

### 3. Bidirectional Short-Burst Tactile Entrainer (`LiveMetronomeCore` + `FeedbackDispatcher`)
- **Decision**: Upgrade `LiveMetronomeCore.swift` (`154` LOC) with a pure deterministic `TactileEntrainerState` state machine:
  - **Two Unmistakable Tactile Languages**:
    1. *Cadence / Turnover* (`cadenceMetronome`): Crisp `.click` beats at `beatIntervalSeconds(forTargetSPM: steppedBPM)`. **Never** lowers BPM below the runner's current cadence to slow down (preventing overstriding). Instead, when current cadence lags goal (`current < goal - 2`), `steppedBPM` starts at `min(goal, current + 3)` and advances `+3 SPM` once the runner stays within `+/- 2 SPM` for `10s`.
    2. *Effort / Pace Regulation* (`effortDown` / `effortUp`): Spaced `.descendingDoublePulse` (for slowing down / HR ceiling / overcooking) or `.ascendingDoublePulse` (for picking up into a surge or work phase) every `3.5s`—never a slow footstrike metronome.
  - **Short-Burst + Quiet Checkpoint Budget**:
    - Active burst duration: maximum `20.0s` (`burstMaxDurationSeconds = 20.0`).
    - Early exit (Rewarding Silence): If the runner locks into the target band (`+/- 2 SPM` for cadence, or `.onTarget` / HR below ceiling for effort) for `5.0s` continuously, the burst terminates immediately.
    - Graceful back-off: If `20.0s` elapses without lock-in, the entrainer goes **silent** and enters a `240–300s` (`4–5 min`) checkpoint cooldown before re-evaluating—unless an **anticipatory phase transition** (e.g., `Cadence Pyramids` work rep start or `Tempo Surges` cooldown start) pre-arms a fresh lock-in burst.
- **Watch Ticker (`FeedbackDispatcher.swift`)**: Add a dedicated `Task`-based metronome/pulse loop driven by `PacingDisplayState.activeTactileCue` (`mode`, `targetBPM`, `pulseIntervalSeconds`), completely decoupled from the `1.5s` discrete alert `minHapticInterval` and automatically cancelled when `activeTactileCue == nil` or workout pauses/ends.
- **Alternative Considered**: Continuous 40-minute haptic ticks. Rejected due to watchOS Taptic Engine battery drain and sensory habituation.

### 4. Live Indoor Treadmill Reliability (`PacingSignalCore` + `AdaptivePacingCore`)
- **Decision**: Parameterize `AdaptivePacingCore` initialization when `location == .indoor`:
  - **Heavier Speed Damping & Outlier Clamp**: Configure `kalmanSpeed` indoors with higher measurement noise (`Q = 0.01, R = 0.64`) and reject/clamp single-tick jumps exceeding `+/- 25%` of the trailing `30s` median speed (matching `TreadmillKinematicsCore.applyWristPaceSmoothing`) before feeding `TelemetryRingBuffer`.
  - **HR + IMU Cadence + Power Priority Indoors**:
    - When `location == .indoor`, `evaluatePaceDriftAlert` suppresses absolute `"too fast / too slow"` nudges against an iPhone-injected outdoor `targetPaceSecondsPerKm` whenever HR and `50 Hz` IMU cadence are already within the session's healthy target envelope.
    - During calibration (`0–5 min`) indoors, lock `originalTargetPaceSecondsPerKm` from the Watch's observed treadmill wrist baseline (or treat pace targets relatively as `%` delta from calibration baseline) so a 5–10% wrist-to-belt calibration offset never triggers false nag bursts.
- **Core-First Handshake & Engineering Org Split**:
  - **Senior (`pro`)**: `RunalystCore` pure types and math (`AthleteCalibrationCore`, `LiveMetronomeCore`, `PacingSignalCore`, `AdaptivePacingCore+SessionBlocks.swift`, `AdaptivePacingCore+Triggers.swift`, `AdaptivePacingCore+Presentation.swift`).
  - **Mid/Jnr (`flash`)**: Foundry & Watch adapters (`HealthKitManager` 48h walk-meters query, `WatchCalibrationBridge`, `SessionSynthesisEngine`, `WatchContextStore`, `FeedbackDispatcher`, `TelemetryEngine`), Hollow Views (`StartRunView`, `PacingGaugeView`), and comprehensive `RunalystCoreTests` / `RunalystTests`.

### 5. Rest-Gap Resilient Deload Guard (`BanisterReadinessCore` + `ReadinessModifier`)
- **Decision**: Add a pure helper `BanisterReadinessCore.isTrueDeloadVolumeDrop(...)` checking whether a strict `7`-day acute slice drop (`>= 25%`) is merely a `2–4` day rest/walk gap following healthy prior-week load: if normalized `10`-day volume (or prior calendar-week volume) remains `>= 80%` of the trailing `21`-day weekly average and `daysSinceLastRun >= 2`, suppress `.deload` and return `.productive`.
- **Rationale**: Prevents rested runners returning on Monday after `2–4` days off (or active walking days) from being falsely downgraded to a `30m` Zone 2 maintenance session.

## Risks / Trade-offs

- **[Risk] watchOS background timer jitter during wrist-down Always-On Display** -> Mitigation: Keep bursts short (`<= 20s`) while the runner is actively glancing/checking in, and anchor step timing against `ContinuousClock` / wall monotonic timestamps rather than accumulating drift.
- **[Risk] `WatchPacingContext` schema mismatch if Watch app updates independently of iPhone** -> Mitigation: Add new fields (`readinessHint`) as `Optional` properties on `PacingSessionIntent` / `WatchPacingContext` keeping `currentSchemaVersion = 1` wire-compatible, or decode gracefully with defaults.
- **[Risk] File size growth above 500-LOC guideline in `AdaptivePacingCore.swift` (`559`) and `PacingGaugeView.swift` (`478`)** -> Mitigation: Isolate block state machine in `AdaptivePacingCore+SessionBlocks.swift` and keep `PacingGaugeView` strictly bound to `PacingDisplayState` properties.

## Migration Plan

1. Land `RunalystCore` extensions with additive optional fields (zero breaking SwiftData migrations) and exhaustive unit tests (including simulated 4-day-off Monday treadmill & `Cadence Pyramids` fixtures).
2. Wire iOS `SessionSynthesisEngine` + `WatchCalibrationBridge` + `HealthKitManager` 48h walk distance helper.
3. Wire `RunalystWatch` (`StartRunView`, `FeedbackDispatcher`, `PacingGaugeView`) and verify `./assay.sh` + Xcode iOS/watchOS build & test suites pass.
