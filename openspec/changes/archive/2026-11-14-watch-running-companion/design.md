# Design: Watch Running Companion Experience

## Context

Runners on watchOS currently receive pace alerts, but lack proactive cadence coaching and split awareness during open runs. Cadence is the runner's first line of defense against overstriding, heavy heel-striking, and biomechanical fatigue. 

This design extends `RunalystCore` with cadence baseline locking, continuous cadence drop detection, split milestone tracking, and surfaces turnover on the watch interface.

## Technical Design

### 1. Cadence Baseline Locking & Tracking (`RunalystCore`)
* In `AdaptivePacingCore`:
  * Add `currentTargetCadenceSPM: Int?`.
  * During `handleCalibration`, lock `currentTargetCadenceSPM = intent.targetCadenceSPM ?? max(150, Int(cadenceStats.mean.rounded()))`.
  * In `evaluateCadenceDriftAlert()`:
    * Track `cadenceDriftContinuousSeconds: Double = 0.0`.
    * Track `cadenceDriftCooldownRemainingSeconds: Int = 0`.
    * Compare 30s short-window filtered cadence against `currentTargetCadenceSPM`.
    * If `filteredCadence < targetCadence - 6` (or < 150 SPM absolute floor):
      * Increment `cadenceDriftContinuousSeconds += 1.0`.
      * If `cadenceDriftContinuousSeconds >= 12.0` and `cooldown == 0`:
        * Emit `PacingEvent.cadenceDrift(currentCadenceSPM:current, targetCadenceSPM:target, deltaSPM:delta)`.
        * Reset accumulator and set `cooldown = 30`.
    * If cadence recovers to within 5 SPM of target, reset accumulator to 0.

### 2. Distance Split Milestone Engine (`RunalystCore` / `RunalystWatch`)
* In `TelemetryEngine`:
  * Track cumulative distance from `HKLiveWorkoutBuilder`.
  * Track `lastCompletedKilometer: Int = 0`.
  * When `currentKm > lastCompletedKilometer`:
    * Calculate split pace for the completed kilometer.
    * Emit `PacingEvent.splitMilestone(splitIndex: currentKm, splitPaceSecondsPerKm: splitPace)`.

### 3. Feedback Specification Mapping (`RunalystWatch`)
* In `PacingEventFeedbackSpec`:
  * `.cadenceDrift`:
    * Haptic: `.retry` (distinct double-tap).
    * Voice cue: `"Cadence dropping. Quicken your steps."`
    * Accent: `.vibrantGreen`.
  * `.splitMilestone(index, pace)`:
    * Haptic: `.success`.
    * Voice cue: `"Kilometer \(index). \(formattedPace) pace."`
    * Accent: `.electricBlue`.

### 4. Live Cadence on Watch Gauge (`RunalystWatch`)
* In `PacingDisplayState`:
  * Ensure `filteredCadenceSPM: Int?` and `filteredCadenceFormatted: String` are exposed.
* In `PacingGaugeView`:
  * Display turnover in **Vibrant Green** alongside pace (**Electric Blue**) and heart rate (**Neon Pink**).
