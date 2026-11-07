# microcycle-coherent-session-synthesis Specification

## Purpose
TBD - created by archiving change overhaul-session-synthesis-microcycle. Update Purpose after archive.
## Requirements
### Requirement: Steady-State Cardiac Drift Filtering Without False-Positive Ping-Pong
The system SHALL only infer split-based cardiac drift (`inferredCardiacDrift`) on continuous aerobic/steady workouts (never on structured interval or tempo surge workouts where HR intentionally oscillates across surges) and SHALL require a meaningful steady-pace heart rate rise (`>= 12 BPM` across steady mid-to-late splits after warmup) before flagging acute cardiac drift, using the actual measured `hrRise` rather than inflating minor rises (`5 BPM`) to a hardcoded `18 BPM`.

#### Scenario: Structured Interval Workout Does Not Trigger False Cardiac Drift Penalty
- **WHEN** a runner completes a structured interval or threshold surge session (`runType == "Intervals"` or `"Tempo"`, or containing `>= 3` work/recovery surge cycles) where heart rate rises from warmup (`106 BPM`) to later surges (`167 BPM`)
- **THEN** `SessionSynthesisEngine` MUST NOT flag false-positive aerobic cardiac drift on that session or force an automatic `Zone 1 Active Recovery Flush` penalty the next day unless explicit fatigue tags, subjective distress, or high workload (`ACWR >= 1.35`) are present

#### Scenario: Normal 5-8 BPM Aerobic Warmup-to-Steady Rise
- **WHEN** a runner completes a continuous aerobic run where split heart rate rises by `5-8 BPM` from the first kilometer (cardiac warmup lag) to the final kilometer at steady pace without explicit `"Cardiac Drift"` tags
- **THEN** the engine SHALL NOT inflate `driftBPM` to `18 BPM` or lock the runner into a 2-day ping-pong loop between `Zone 1 Active Recovery Flush` and `10K Threshold Surges`

### Requirement: Multi-Stimulus Microcycle Variety and Horizon Alignment
When readiness is productive and no recent quality stimulus was completed in the last 48 hours, `SessionSynthesisEngine` and `SessionHorizonCore` SHALL rotate quality and aerobic sessions across the training week (supporting `Tempo Progression`, `Long Aerobic Endurance`, and `Easy Aerobic Base` in addition to `10K Threshold Surges` / `5K Rhythm Intervals`) and align `plannedSession(on:)` day offsets accurately when today's workout is completed.

#### Scenario: Completed Quality Session Followed by Productive Aerobic Base Progression
- **WHEN** a runner with a `10K Race` goal has already completed a quality interval/threshold session within the last 48 hours and readiness is normal (not acutely fatigued)
- **THEN** the engine SHALL prescribe a varied aerobic or progression session (`Easy Aerobic Base` or `Tempo Progression` / `Long Aerobic Endurance` on weekend long-run days) rather than repeating `10K Threshold Surges` back-to-back or forcing `Zone 1 Active Recovery Flush`

#### Scenario: Tomorrow Horizon Offset Consistency After Completing Today's Run
- **WHEN** the runner completes today's workout (`.completedToday`) and inspects future days via `plannedSession(on:)`
- **THEN** `plannedSession(on:)` SHALL map calendar day offsets deterministically without off-by-one shifts caused by `startsAfterTomorrow`

### Requirement: Dynamic Heart Rate Ceilings and Experience-Scaled Quality Durations
The system SHALL compute heart rate ceiling strings (`maxHeartRate`) dynamically from the runner's `TrainingZoneCore` boundaries (`zone1Ceiling`, `zone2Ceiling`, `zone3Ceiling`, `zone4Ceiling`) and scale quality/aerobic session durations by runner experience level while preserving default baseline expectations (`35 MIN` for Intermediate `10K` quality, `30 MIN` for Intermediate `5K` quality).

#### Scenario: Dynamic Zone Ceilings on Prescribed Sessions
- **WHEN** `SessionSynthesisEngine` or `SessionHorizonCore` generates a recovery, aerobic base, tempo, or threshold session
- **THEN** `maxHeartRate` SHALL reflect the athlete's calculated zone ceiling (e.g., `< \(zones.zone1Ceiling) BPM` for Zone 1 recovery, `< \(zones.zone2Ceiling + 4) BPM` for Zone 2 aerobic, `< \(zones.zone4Ceiling) BPM` for threshold surges) rather than disconnected static string literals

