## MODIFIED Requirements

### Requirement: Zero-Friction Watch Start Screen & Run Intent
The watchOS start experience SHALL let the runner select **Outdoor** or **Indoor** and choose a single high-level run intent (**Adaptive Base**, **Push / Performance**, or **Recovery**) defaulting to **Adaptive Base**, without presenting redundant manual pace wheels or `"Just Run"` ambiguity.

#### Scenario: Adaptive Base preserves iPhone readiness intent
- **WHEN** `StartRunView` launches with a fresh same-day `WatchPacingContext` synthesized from iPhone (e.g., `.tempo` for a cleared 10K threshold session) and the runner leaves **Adaptive Base** selected
- **THEN** `WatchResolvedSessionConfig.applying(runIntent: .adaptiveBase)` MUST preserve `cachedContext.intent.intent` and `WatchReadinessHint` instead of overwriting `.tempo` to `.steady`
- **AND** `StartRunView` MUST NOT render a `"Just Run"` or manual `WatchTargetPaceOption` wheel picker.

#### Scenario: iPhone "Start on Watch" handoff preserves target pace
- **WHEN** iPhone launches the Watch companion via `launchWatchWorkout` and `RunalystWatchAppDelegate.handle(_:)` resolves the session
- **THEN** it MUST pass `resolved.intent.targetPaceSecondsPerKm` directly to `WorkoutManager.startWorkout(...)` without gating on the retired `requiresTargetPacePicker` flag.

#### Scenario: Intent policies in Core
- **WHEN** `intent` is `.recovery`
- **THEN** `applying(runIntent: .recovery)` MUST force `.recovery`, suppress all upward `.surge` and `.thresholdSurge` blocks, and enforce the conservative HR ceiling (`<= 0.80` maxHR)
- **WHEN** `intent` is `.pushPerformance`
- **THEN** `applying(runIntent: .pushPerformance)` sets `.tempo` (unless `subjectiveDistress == true`, which retains `.recovery`) and enables permissive surge ceilings (`HR < 0.88` maxHR) while honoring aerobic safety caps.

---

### Requirement: 5-Minute Calibration Phase & Blue Edge Aura
The adaptive engine SHALL calibrate quietly for minutes 0 through 5 (300 seconds) while rendering a calm blue edge aura and observing early-run HR, pace, and cadence readiness without vocalized block announcements.

#### Scenario: Calibration start and silent lock-in
- **WHEN** a watch companion session begins in `.calibrating`
- **THEN** `AdaptivePacingCore` emits `.calibrationStarted` with `accentToken: .calibratingBlue` and suppresses drift nagging during elapsed seconds `[0, 300)`
- **WHEN** elapsed time reaches `300` seconds (5:00) with sufficient sensor coverage
- **THEN** `AdaptivePacingCore` locks the baseline pace and cadence floor (capped by `calibratedCadenceFloorSPM` or `>= 150 SPM`), transitions to `.tracking`, and evaluates whether an initial adaptive block (`cadenceReset` or `thresholdSurge`) should immediately open visually on `PacingGaugeView`.

---

### Requirement: Two-Step Form Check & Cardiac Drift Recovery Protection
Biomechanical degradation and sustained cardiac/efficiency drift SHALL trigger visual display updates and short-burst tactile interventions on a `4–5 minute` checkpoint budget rather than continuous `30-second` nagging.

#### Scenario: Quiet checkpoint budget replaces 30s nagging
- **WHEN** a `cadenceDrift` or `paceDrift` correction burst completes or backs off without lock-in after `20.0` seconds
- **THEN** `AdaptivePacingCore` MUST suppress repeat `cadenceDrift` and `paceDrift` alerts for at least `240` seconds (`4` minutes), unless an explicit phase transition occurs
- **AND** `PacingEventFeedbackSpec` for `.paceDrift`, `.cadenceDrift`, `.formCheck`, `.surge`, `.recover`, and `.adaptiveBlockChanged` MUST set `voiceCueText: nil` so Watch runs rely on visual display updates and tactile cues without vocalized coaching chatter.
