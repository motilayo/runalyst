## Context

When a runner executes a structured interval session scheduled via Runalyst's `WorkoutKit` bridge—such as the 35-minute `10K Threshold Surges` (`4m` warmup + `4 x (3m work / 3m walk recovery)` + `7m` cooldown, totaling `4.55 km` and `35:00` in Apple Fitness)—four layers of the system currently conflict:

1. **Core Telemetry Filtering (`FramboiseCore.swift` — 488/500 LOC, `FramboiseEngine.swift` — 344 LOC)**:
   - `FramboiseCore.filterRunningSamples(buckets:)` strips any bucket where `speed <= 1.65 m/s` or `cadence < 125 SPM` as a non-running dead stop.
   - In a `4 x (3m work / 3m walk)` workout, the runner's 4 walk recoveries (`114-124 SPM`, `10:24-11:59/km`) and slow warmup (`118 SPM`) total `14m 30s` and `1.27 km`. Trimming those buckets reduces `workingDistance` from `4.55 km` to `3.28 km` and `workingDuration` from `35:00` (`2100s`) to `20:30` (`1230s`), violating Constitutional Invariant 1 (*Zero Lies in the Ledger*).
2. **Interval Segmentation, Classification & Drill Matching (`IntervalSegmenterCore.swift` — 493/500 LOC, `RunClassifierCore.swift` — 222 LOC, `DrillPatternCore.swift` — 488/500 LOC, `RunRecord.swift` — 557 LOC)**:
   - Once walking recoveries are stripped or diluted, `RunClassifierCore` fails to classify the workout as `"Interval"` or `"Tempo"`, falling back to `"Easy Run"`.
   - Autonomous drill pattern recognition in `RunRecord.prescribedDrillName` is capped at `<= 1320s` (`22 min`), so a 35-minute (`2100s`) `Tempo Surges` / `10K Threshold Surges` Main Run is never linked and instead gets graded against the `Zone 2 Easy Base` (`144 BPM` ceiling) scorecard, resulting in a false `Not Met` failure.
3. **Run Detail Trajectory & Diagnostic Copy (`HeartRateTrajectoryMapView.swift` — 542 LOC, `DrillExecutionScorecard.swift` — 989 LOC, `RunDetailView.swift` — 1278 LOC)**:
   - `HeartRateTrajectoryMapView` plots smoothed/downsampled split points anchored to `effectiveWorkingHR`, flattening 4 distinct interval peaks (`154-175 BPM`) and recovery troughs (`134-138 BPM`) into a single `157 Peak` curve (`Zone 3`) while `DrillExecutionScorecard` simultaneously displays `Zone 4 Spike: 38%`.
   - `RunDetailView` (lines 223-265) unconditionally outputs `"safely above your \(floor) SPM mechanical floor"` when `cad == floor` (`154 == 154`), and renders `"Strong Rhythm Found"` and `"steady aerobic conditioning"` even when the execution verdict is `Not Met`.
4. **Workout Cards & Readout Modals (`PreRunDrill.swift` — 312 LOC, `DrillReadout.swift` — 776 LOC, `DrillPrimerCardView.swift` — 399 LOC, `PrescribedSessionCardView.swift` — 431 LOC, `DrillInterstitialReadoutView.swift` — 425 LOC, `SessionSynthesisEngine.swift` — 1427 LOC)**:
   - `DrillPrimerCardView` shows `7 min` from a static enum/duration property while its bottom bar truncates `90s` (`1.5m`) cooldown to `1m out` (`3m 40s` sum) and `DrillInterstitialReadoutView` sums the actual blocks (`4m 10s`).
   - `PrescribedSessionCardView` hardcodes `"Aerobic consistency & conversational pacing"` onto `10K Threshold Surges`, and `SessionSynthesisEngine` supplies an easy/walk-diluted belt pace (`7:15-7:30/km`) and `>= 155 SPM` instead of threshold work targets (`155-161 SPM`).
   - `DrillReadout` hardcodes `"Tempo Pre-Run • \(duration.rawValue) min"` and `"finishing with a 2-minute cool-down"` for the 35-minute Main Run (`7m` actual cooldown).

## Goals / Non-Goals

**Goals:**
- Preserve full session distance (`4.55 km`) and moving duration (`35:00`) when a workout contains structured alternating work/recovery cycles (`>= 3` work surges separated by walking recoveries), while still computing work-phase cadence and pace for interval evaluation.
- Classify `4 x 3m` work/walk surge workouts accurately as `"Interval"` / `"Tempo"` and recognize 35-minute `Tempo Surges` (`10K Threshold Surges`) workouts so they are evaluated against their threshold/cadence targets rather than `Zone 2 Easy Base`.
- Render true bucket-level HR oscillations and true Peak HR in `HeartRateTrajectoryMapView`, and eliminate contradictory copy in `RunDetailView`.
- Unify primer and main-run durations, subtitles, pace/cadence bands, cooldown prose, and segmented picker labels across `WorkoutsView`, `DrillPrimerCardView`, `PrescribedSessionCardView`, `DrillReadout`, and `DrillInterstitialReadoutView`.
- Keep all `RunalystCore` files strictly `<= 500 LOC` and pass all 5 `./assay.sh` gates.

**Non-Goals:**
- Altering SwiftData persistent schema (`RunalystSchemaV1`)—all fixes operate on existing `BucketData`, `WorkoutPhase`, `RunRecord` computed properties, and pure `RunalystCore` engines.

## Decisions

### Decision 1: Interval-Aware Working Stats & Classification in `RunalystCore` (Senior Tier — `pro`)
- **Approach**:
  - Because `FramboiseCore.swift` (488 LOC), `IntervalSegmenterCore.swift` (493 LOC), and `DrillPatternCore.swift` (488 LOC) are right at the 500-LOC mass ceiling, we will extract or refactor compact helper functions so no file exceeds 500 LOC.
  - In `FramboiseCore`: detect structured multi-surge interval patterns (`>= 3` distinct running surges `>= 60s` with `cadence >= 145 SPM` and `speed >= 2.2 m/s` separated by intentional walking recovery windows `30s-240s` with `speed >= 0.8 m/s`). When a structured interval pattern is present, preserve intentional walk recovery and warmup/cooldown buckets in `workingDistance` and `workingDuration` (so `4.55 km` and `35:00` remain ledger-true) while still trimming true stationary stops (`speed < 0.5 m/s`).
  - In `RunClassifierCore` / `IntervalSegmenterCore` / `DrillPatternCore`: ensure workouts with `>= 3` alternating work/walk cycles (`paceDiff >= 45 s/km`) classify as `"Interval"` (or match `"Tempo Surges"` for 30-40 min `4 x 3m` structures) and extend `RunRecord.prescribedDrillName` pattern recognition to support structured 35-minute `Tempo Surges` main runs when `"userUnlinkedDrill"` is not set.
- **Alternatives Considered**:
  - *Never trimming walking in any run*: Rejected because casual continuous runs with a long crosswalk/coffee walk break would have their aerobic working pace artificially slowed. Limiting walk-recovery preservation to runs with `>= 3` structured work/walk cycles protects both interval workouts and continuous runs.

### Decision 2: Extrema-Preserving HR Trajectory & Verdict-Synchronized Diagnostics (Mid/Jnr Tier — `flash`)
- **Approach**:
  - In `HeartRateTrajectoryMapView.swift`: plot raw/extrema-preserving `BucketData` heart rate samples across the full workout duration (`0m` to `35m`) and compute `Peak` from the actual bucket maximum (`max(buckets.map(\.heartRate))`) rather than smoothed split midpoints, so all 4 interval HR waves and the true peak (`167-175 BPM`) render faithfully.
  - In `RunDetailView.swift`:
    - Fix the cadence comparison (`lines 234-243`): use `"exceeded your \(floor) SPM mechanical floor"` only when `cad > floor`, `"matched your \(floor) SPM mechanical floor"` when `cad == floor`, and `"fell below your \(floor) SPM mechanical floor"` when `cad < floor`.
    - Pass or evaluate the execution status (`Met` vs `Not Met` and whether failure was HR ceiling vs cadence floor) before constructing the `"What the Numbers Mean"` headline (`"Elevated Cardiac Strain"` / `"Target Ceiling Exceeded"` instead of `"Strong Rhythm Found"` when `Not Met`) and `Cardiovascular Control` / `Execution Verdict` bullets.

### Decision 3: Single Source of Truth for Workout Durations, Subtitles & Readout Copy (Mid/Jnr Tier — `flash`)
- **Approach**:
  - In `PreRunDrill.swift`, `DrillPrimerCardView.swift`, and `DrillReadout.swift`:
    - Ensure the primer's phase durations (`warmupSeconds + reps * (workSeconds + recoverySeconds) + cooldownSeconds`) sum exactly to the displayed Primer duration (`lockedDurationMinutes` or dynamic total), and format non-integer minute cooldowns (`90s`) as `1.5m out` (or adjust cooldown to match the exact minute target so card badge, phase bar, and preview modal show the exact same duration).
    - In `DrillReadout.swift`: distinguish pre-run primers (`<= 15 min`, `"Tempo Pre-Run"`) from main runs (`>= 20 min`, `"Tempo Main Run • \(duration.rawValue) min"`), and compute the cooldown duration in `breakdownText` dynamically from the actual cooldown phase (`"finishing with a 7-minute cool-down"` instead of hardcoded `"2-minute cool-down"`).
    - In `PrescribedSessionCardView.swift` & `SessionSynthesisEngine.swift`: replace the hardcoded `"Aerobic consistency & conversational pacing"` subtitle with session-specific subtitles (e.g., `"Lactate threshold surges & mechanical turnover"` for `10K Threshold Surges`), bind the work-interval pace band and cadence target (`155-161 SPM`), shorten `"Indoor (Treadmill)"` in compact segmented pickers (or apply `.lineLimit(1).minimumScaleFactor(0.85)`) so it never truncates to `"Indoor (Trea..."`, and ensure bottom safe-area clearance on `WorkoutsView`.

## Risks / Trade-offs

- **[Risk] `FramboiseCore.swift` (488 LOC), `IntervalSegmenterCore.swift` (493 LOC), and `DrillPatternCore.swift` (488 LOC) exceeding the 500-LOC Assay gate** -> **Mitigation**: Extract cohesive helper logic or streamline existing verbose comments/helpers within `RunalystCore` so every `.swift` file remains strictly `<= 500 LOC`, verified by `./assay.sh`.
- **[Risk] Existing unit tests in `FramboiseEngineTests` or `GoldenTelemetryFixtures` expecting dead-stop trimming on single stops** -> **Mitigation**: Require `>= 3` alternating work/walk surge cycles before preserving walk recovery intervals, keeping single/double mid-run stops trimmed as before.
