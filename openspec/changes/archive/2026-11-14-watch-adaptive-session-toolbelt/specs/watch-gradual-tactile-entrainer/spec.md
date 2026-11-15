## ADDED Requirements

### Requirement: Distinct Tactile Semantics for Cadence vs. Effort
`LiveMetronomeCore` and `FeedbackDispatcher` SHALL use distinct haptic waveforms so runners never confuse cadence/turnover cues with pace/effort braking cues.

#### Scenario: Never lower metronome BPM to slow pace down
- **WHEN** the runner is overcooking (`HR` above ceiling or pace too fast) and needs to reduce speed or effort
- **THEN** `LiveMetronomeCore` MUST emit `.effortDown` (`.descendingDoublePulse` spaced every `3.5s`) rather than lowering metronome BPM below current cadence
- **AND** rhythmic `.click` metronome ticks MUST ONLY be used to lift laggy cadence upward or protect a minimum cadence floor (e.g., during cooldowns or `Cadence Pyramids` work bouts).

---

### Requirement: Gradual Stepped Cadence Ramp
When cadence lags target (`currentSPM < goalSPM - 2`), `LiveMetronomeCore` SHALL compute a stepped target BPM starting near the runner's actual cadence and walking upward gradually instead of jumping directly to the final goal.

#### Scenario: Gradual ramp from 154 SPM to 160 SPM
- **WHEN** a runner at `154 SPM` enters a cadence nudge targeting `160 SPM`
- **THEN** `SteppedMetronomeRamp` MUST initialize `steppedTargetSPM` at `min(160, 154 + 3) = 157 SPM`
- **AND** only advance `steppedTargetSPM` by `+3 SPM` (to `160 SPM`) after the runner maintains `157 +/- 2 SPM` for `10.0` continuous seconds.

---

### Requirement: Short-Burst Duty-Cycling, Early Silence & Checkpoint Budget
Tactile feedback SHALL operate strictly in short bursts (`<= 20.0s`), stop immediately when the runner locks in, and back off cleanly for `4–5 minutes` if ignored—except on anticipatory phase transitions.

#### Scenario: Early lock-in silences haptics immediately
- **WHEN** an active `cadenceMetronome` or `effortDown` burst is running and the runner enters the target zone (`+/- 2 SPM` or `.onTarget` / HR below ceiling) for `5.0` continuous seconds
- **THEN** `LiveMetronomeCore` terminates the active burst immediately (`activeTactileCue = nil`) and starts the `240`–`300` second checkpoint cooldown.

#### Scenario: 20-second timeout graceful back-off
- **WHEN** a burst runs for `20.0` seconds without the runner locking into the target zone
- **THEN** `LiveMetronomeCore` MUST silence the haptic ticker automatically and wait at least `240` seconds (`4` minutes) before the next periodic checkpoint nudge.

#### Scenario: Anticipatory phase-boundary pre-arming
- **WHEN** an active workout transitions into a known structured phase (e.g., `Cadence Pyramids` work rep or `Tempo Surges` cooldown floor)
- **THEN** `AdaptivePacingCore` MUST bypass the periodic checkpoint cooldown and arm a fresh `<= 20.0s` lock-in burst at the boundary.
