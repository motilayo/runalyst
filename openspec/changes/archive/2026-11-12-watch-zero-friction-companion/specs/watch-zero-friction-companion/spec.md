# Specification: Watch Zero-Friction Adaptive Running Companion

## ADDED Requirements

### Requirement: Zero-Friction Watch Start Screen & Run Intent
The watchOS start experience SHALL let the runner select **Outdoor** or **Indoor** and choose a single high-level run intent (**Adaptive Base**, **Push / Performance**, or **Recovery**) defaulting to **Adaptive Base**, without requiring target pace, interval, or timer programming.

#### Scenario: Adaptive Base default launch
- **GIVEN** the runner opens Runalyst on Apple Watch with no overriding scheduled interval prescription
- **WHEN** `StartRunView` appears
- **THEN** location defaults to the synced preference (**Outdoor** or **Indoor**), intent defaults to **Adaptive Base** ("Balanced aerobic run"), manual target-pace wheel selection is omitted for zero-friction start, and tapping **Start Run** initiates live calibration with `targetPaceSecondsPerKm: nil` and `watchVoiceCuesEnabled` defaulting to `true`.

#### Scenario: Intent policies in Core
- **GIVEN** `AdaptivePacingConfiguration.forWatchCompanion(intent:)` is initialized
- **WHEN** `intent` is `.recovery`
- **THEN** upward `.surge` transitions MUST be strictly suppressed and HR ceiling protection triggers earlier (threshold fraction <= 0.80 maxHR)
- **WHEN** `intent` is `.pushPerformance`
- **THEN** upward `.surge` evaluations use a permissive ceiling (e.g., HR < 0.88 maxHR, top 40% efficiency quantile) while still honoring the 90s refractory cooldown and aerobic safety caps
- **WHEN** `intent` is `.adaptiveBase`
- **THEN** upward `.surge` and downward `.recover` protection use balanced aerobic thresholds (e.g., surge HR < 0.82 maxHR, recovery ceiling 0.92 maxHR).

---

### Requirement: 5-Minute Calibration Phase & Blue Edge Aura
The adaptive engine SHALL calibrate quietly for minutes 0 through 5 (300 seconds) while rendering a calm blue edge aura and announcing calibration start and lock-in over ducked audio.

#### Scenario: Calibration start audio cue
- **GIVEN** a watch companion session begins in `.calibrating`
- **WHEN** the first telemetry tick is ingested
- **THEN** `AdaptivePacingCore` emits `.calibrationStarted` exactly once with `voiceCueText: "Find a comfortable rhythm. Reading your baseline."`, `haptic: .none`, and `accentToken: .calibratingBlue`
- **AND** during elapsed seconds [0, 300), zero pace drift, cadence drift, form check, surge, or recover nagging events SHALL be emitted.

#### Scenario: Calibration lock-in at 5 minutes
- **GIVEN** sufficient sensor coverage over the calibration baseline window
- **WHEN** elapsed time reaches 300 seconds (5:00)
- **THEN** `AdaptivePacingCore` locks the baseline pace and cadence floor, transitions to `.tracking`, and emits `.calibrationComplete` with `.success` haptic and voice cue `"Baseline locked. Target pace: <pace> per <kilometer/mile>. Let's roll."`
- **AND** `PacingDisplayState.accentToken` transitions to steady neutral `.electricBlue`.

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
Biomechanical breakdown SHALL trigger a non-destructive Form Check before any pace dial-back; sustained cardiac or efficiency drift triggers a Recovery adjustment with warm amber visuals and descending double-tap haptic.

#### Scenario: Non-destructive Form Check nudge
- **GIVEN** the runner is post-calibration (`state != .calibrating`) and either Biomechanical Degradation Index triggers (GCT delta > +7% AND cadence drop > 4.0 SPM) or sustained cadence drift occurs below target cadence floor
- **WHEN** cooldown allows
- **THEN** `AdaptivePacingCore` emits `.formCheck` (or updated `.cadenceDrift`) with `haptic: .threeQuickLightTaps` and voice cue `"Form check. Quick, light steps—bring your cadence up."`
- **AND** `currentTargetPaceSecondsPerKm` MUST NOT be slowed down solely by the first Form Check.

#### Scenario: Recovery adjustment on cardiac drift
- **GIVEN** efficiency drift (`deltaEF <= recoverEfficiencyDriftThreshold`) or sustained HR ceiling persists after form check / in tracking
- **WHEN** a `.recover` trigger fires (refractory == 0)
- **THEN** `AdaptivePacingCore` dials target pace slower (capped by step limit and cumulative 12% ceiling), emits `.recover` with `haptic: .descendingDoublePulse`, `accentToken: .recoverAmber`, and voice cue `"Cardiac drift detected. Dialing target back to <pace> to protect your aerobic zone."`.

---

### Requirement: Cool-Down & Instant 3-Bullet Wrist Debrief
Ending a run on Apple Watch SHALL transition directly to an on-wrist `RunSummaryView` presenting a pure-Core 3-bullet "Coach's Takeaway" (`Adaptations`, `Efficiency Score`, `Form Insight`).

#### Scenario: End Run generates wrist Coach's Takeaway
- **GIVEN** a completed run session on Apple Watch with recorded surges, recovery adjustments, cardiac drift onset time, and cadence stability history
- **WHEN** the runner taps End Run and `WorkoutManager.endWorkout()` completes
- **THEN** `AdaptivePacingCore.buildRunDebrief(elapsedSeconds:totalDistanceMeters:useMetricSystem:)` returns a `WatchRunDebrief` containing non-empty `adaptationsBullet`, `efficiencyScoreBullet`, and `formInsightBullet` formatted in metric or imperial units
- **AND** `PacingGaugeView` presents `RunSummaryView(debrief:)` on the wrist until the runner taps Done.
