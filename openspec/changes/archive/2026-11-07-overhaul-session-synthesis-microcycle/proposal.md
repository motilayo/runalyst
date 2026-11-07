## Why

Real-world multi-week testing of `SessionSynthesisEngine` reveals five structural defects that make daily workout prescriptions feel repetitive, disconnected from the upcoming weekly schedule, and physiologically contradictory:
1. **Today vs. Upcoming Schedule Split-Brain & 2-Day Ping-Pong Loop**: `SessionSynthesisEngine.synthesizePreRunPrescription` ignores the calendar weekday microcycle in `SessionHorizonCore.templateSpecForWeekday`, prescribing only a single quality workout (`10K Threshold Surges` for 10K goals) whenever readiness is productive—even on scheduled Easy Base, Tempo Progression, Long Run, or Rest days. Combined with a hypersensitive split cardiac drift check (`driftBPM = max(18, hrRise)` whenever HR rises `>= 5 BPM`), runners get locked into an endless 2-day ping-pong oscillation between `10K Threshold Surges` and `20m Zone 1 Active Recovery Flush`.
2. **Redundant & Contradictory Primer Coupling**: Every non-rest workout unconditionally forces a separate `Pre-Run Primer` (even before a `20m Zone 1 Active Recovery Flush` or before a `35m 10K Threshold Surges` workout that already contains its own `4m` warmup, `4 x 3m` surges, and `7m` cooldown).
3. **Static Durations & Hardcoded HR String Literals**: Quality and recovery durations (`20m`, `30m`, `35m`) ignore runner experience and 4-week progressive overload, while HR caps (`"< 135 BPM"`, `"< 150 BPM"`, `"< 165 BPM"`) use hardcoded literals instead of dynamic `TrainingZoneCore` boundaries.
4. **Amnesia of Execution Verdicts & Subjective Overrides**: Synthesis ignores whether the last workout's execution was `Met` vs `Not Met` and ignores user `TrainingCorrection` feedback, while `synthesizeTomorrowPrescription` has an off-by-one `day-1` vs `startsAfterTomorrow` offset mismatch.
5. **Foundry Domain Leakage**: `SessionSynthesisEngine.swift` (`1,472 LOC`) contains pure domain heuristics (cardiac drift decoupling, weekly stimulus counting, and microcycle progression) that belong in `RunalystCore`.

## What Changes

- **Calendar-Coherent Microcycle Synthesis (`SessionHorizonCore` & `SessionSynthesisEngine`)**:
  - Unify Today's workout synthesis with `SessionHorizonCore` weekday templates so scheduled `Easy Aerobic Base`, `Tempo Progression`, `10K Threshold Surges`, `Hill Surges`, `Long Aerobic Endurance`, and `Rest & Mobility` days are honored when that weekday arrives, with biological readiness/fatigue acting as an intelligent intensity/volume modifier rather than erasing the weekly cycle.
  - Fix the `startsAfterTomorrow` microcycle day-ID offset in `plannedSession(on:)` so Tomorrow and the 5-day Upcoming Schedule align deterministically.
- **True Steady-State Cardiac Decoupling & Execution Feedback Loop**:
  - Replace the false-positive `max(18, hrRise)` split check (`>= 5 BPM` rise) with steady-state aerobic decoupling that excludes warmup/cooldown and interval workouts (requiring `>= 10 BPM` steady-pace HR drift or `ACWR >= 1.35` before triggering a recovery downshift).
  - Incorporate previous workout execution adherence and `TrainingCorrection` overrides so failed threshold sessions (`Not Met`) step down gracefully to `Easy Aerobic Base` or adjusted cadence targets rather than ping-ponging between extremes.
- **Physiologically Grounded Primer Pairing**:
  - Attach `Pre-Run Primer` drills to **continuous aerobic/steady runs** where neuromuscular form priming is beneficial, and allow standalone execution (or optional/omitted primer) for `Zone 1 Active Recovery Flush` and already-structured multi-interval workouts when appropriate, while preserving test compatibility.
- **Dynamic HR Zone Ceilings & Experience-Scaled Progressive Durations**:
  - Compute session HR caps dynamically from `TrainingZoneCore` (`zone1Ceiling`, `zone2Ceiling`, `zone3Ceiling`, `zone4Ceiling`) and scale workout durations by runner experience and rolling 4-week volume.

## Capabilities

### New Capabilities
- `microcycle-coherent-session-synthesis`: Unified weekday microcycle progression, true steady-state cardiac drift detection, execution verdict feedback, dynamic HR zone caps, and experience-scaled workout synthesis across `SessionHorizonCore`, `SessionSynthesisCore`, and `SessionSynthesisEngine`.

### Modified Capabilities
<!-- None -->

## Impact

- **Architectural Boundary**:
  - `RunalystCore/`: `SessionHorizonCore.swift` (currently `255 / 500 LOC`), `SessionSynthesisCore.swift` (currently `485 / 500 LOC` — new pure helpers will be placed in `SessionHorizonCore.swift` or a companion `SessionSynthesisCore+Progression.swift` so every file stays strictly `<= 500 LOC`).
  - `Runalyst/`: `SessionSynthesisEngine.swift`, `PrescribedSessionCardView.swift`, `WorkoutsView.swift`.
  - `RunalystTests/`: `SessionSynthesisEngineTests.swift`.
