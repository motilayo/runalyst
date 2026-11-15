# watch-zero-friction-companion Specification

## Purpose
TBD - created by archiving change watch-zero-friction-companion. Update Purpose after archive.
## Requirements
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

### Requirement: In-Flow Dynamic Pace Gauge & Biometric Status Ring
During tracking, `PacingGaugeView` SHALL display a clean hierarchy with a central Dynamic Pace Gauge normalized to the live target window, large `.monospacedDigit()` pace and heart rate, compact cadence readout, and a Biometric Status Ring (Green/Teal, Blue, Amber) readable at a 0.5-second glance, staying silent while in the sweet spot.

#### Scenario: Pre-computed normalized gauge geometry
- **GIVEN** an active locked target pace and filtered pace
- **WHEN** `PacingDisplayState` is produced by `RunalystCore`
- **THEN** `PacingDisplayState` provides `paceGaugeNormalizedPosition` in [0.0, 1.0] (with 0.5 centered on target pace), `targetBandLowerNormalized` and `targetBandUpperNormalized` bounding the sweet spot, `biometricStatusToken`, `biometricStatusLabel`, and `elapsedTimeFormatted`
- **AND** `PacingGaugeView` performs zero pace-band arithmetic.

---

### Requirement: Surge Nudge, Lock-In Confirmation Tap & 90s Cooldown
When high efficiency reserves trigger a surge, the Watch SHALL play two ascending haptic pulses, announce the new target pace over ducked audio, glow teal/green, confirm lock-in with a single subtle tap when the runner settles into the new zone, and respect at least a 90-second cooldown before the next target shift.

#### Scenario: Surge trigger and zone lock-in confirmation
- **GIVEN** the runner enters `.surge` cleanly with target shifted faster (e.g., to 5:05/km)
- **WHEN** `.surge` is emitted
- **THEN** `feedbackSpec` uses `haptic: .ascendingDoublePulse`, `accentToken: .surgeTeal`, and voice cue `"Efficiency is high—you've got reserves. Nudging target pace to <pace>."`
- **AND** `AdaptivePacingCore` enters `refractorySecondsRemaining = 90` and records `awaitingSurgeLockInTargetSecondsPerKm = newTarget`
- **WHEN** subsequent ticks confirm filtered pace enters `.onTarget` within the new target window
- **THEN** `AdaptivePacingCore` emits `.surgeLockedIn` once with `haptic: .subtleConfirmation` and `voiceCueText: nil`.

---

### Requirement: Two-Step Form Check & Cardiac Drift Recovery Protection
Biomechanical degradation and sustained cardiac/efficiency drift SHALL trigger visual display updates and short-burst tactile interventions on a `4–5 minute` checkpoint budget rather than continuous `30-second` nagging.

#### Scenario: Quiet checkpoint budget replaces 30s nagging
- **WHEN** a `cadenceDrift` or `paceDrift` correction burst completes or backs off without lock-in after `20.0` seconds
- **THEN** `AdaptivePacingCore` MUST suppress repeat `cadenceDrift` and `paceDrift` alerts for at least `240` seconds (`4` minutes), unless an explicit phase transition occurs
- **AND** `PacingEventFeedbackSpec` for `.paceDrift`, `.cadenceDrift`, `.formCheck`, `.surge`, `.recover`, and `.adaptiveBlockChanged` MUST set `voiceCueText: nil` so Watch runs rely on visual display updates and tactile cues without vocalized coaching chatter.

#### Scenario: Non-destructive Form Check nudge
- **GIVEN** the runner is post-calibration (`state != .calibrating`) and either Biomechanical Degradation Index triggers (GCT delta > +7% AND cadence drop > 4.0 SPM) or sustained cadence drift occurs below target cadence floor
- **WHEN** cooldown allows
- **THEN** `AdaptivePacingCore` emits `.formCheck` (or updated `.cadenceDrift`) with `haptic: .threeQuickLightTaps` and visual/tactile cueing (`voiceCueText: nil`)
- **AND** `currentTargetPaceSecondsPerKm` MUST NOT be slowed down solely by the first Form Check.

#### Scenario: Recovery adjustment on cardiac drift
- **GIVEN** efficiency drift (`deltaEF <= recoverEfficiencyDriftThreshold`) or sustained HR ceiling persists after form check / in tracking
- **WHEN** a `.recover` trigger fires (refractory == 0)
- **THEN** `AdaptivePacingCore` dials target pace slower (capped by step limit and cumulative 12% ceiling), emits `.recover` with `haptic: .descendingDoublePulse`, `accentToken: .recoverAmber`, and visual/tactile alert (`voiceCueText: nil`).

---

### Requirement: Cool-Down & Instant 3-Bullet Wrist Debrief
Ending a run on Apple Watch SHALL transition directly to an on-wrist `RunSummaryView` presenting a pure-Core 3-bullet "Coach's Takeaway" (`Adaptations`, `Efficiency Score`, `Form Insight`).

#### Scenario: End Run generates wrist Coach's Takeaway
- **GIVEN** a completed run session on Apple Watch with recorded surges, recovery adjustments, cardiac drift onset time, and cadence stability history
- **WHEN** the runner taps End Run and `WorkoutManager.endWorkout()` completes
- **THEN** `AdaptivePacingCore.buildRunDebrief(elapsedSeconds:totalDistanceMeters:useMetricSystem:)` returns a `WatchRunDebrief` containing non-empty `adaptationsBullet`, `efficiencyScoreBullet`, and `formInsightBullet` formatted in metric or imperial units
- **AND** `PacingGaugeView` presents `RunSummaryView(debrief:)` on the wrist until the runner taps Done.

