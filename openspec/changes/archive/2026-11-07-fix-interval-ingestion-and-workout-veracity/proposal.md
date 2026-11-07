## Why

Structured interval workouts scheduled by Runalyst (such as a 35-minute `10K Threshold Surges` session with `4 x 3m` work surges and `4 x 3m` walk recoveries) are currently corrupted during ingestion: `FramboiseCore` strips the prescribed walking recoveries as "dead stops" (shrinking a `4.55 km`, `35:00` workout into `3.28 km`, `20:30`), causing the run to be misclassified as an `Easy Run` and falsely failed (`Not Met`) against a `Zone 2 Easy Base` scorecard while its 4 HR peaks (`167-175 BPM`) are flattened into a single `157 BPM` curve. Simultaneously, the `Workouts` tab and `Run Details` views exhibit multiple mathematical and diagnostic contradictions—including a 3-way Primer duration mismatch (`7 min` card badge vs `3m 40s` phase bar vs `4m 10s` preview modal), Easy Run subtitles/pace bands rendered on `10K Threshold Surges` cards, `"Tempo Pre-Run"` and `"2-minute cool-down"` copy on a 35-minute Main Run with a `7m` cool-down, and `"safely above your 154 SPM floor"` when cadence is exactly `154 SPM`.

## What Changes

- **Preserve Prescribed Walk Recoveries & Classify Interval Workouts Accurately (`RunalystCore`)**:
  - Update `FramboiseCore` / `FramboiseEngine` and `IntervalSegmenterCore` / `RunClassifierCore` / `DrillPatternCore` so structured interval sessions containing alternating work surges (`>= 3` cycles of work/recovery) retain their full session distance and moving duration (`4.55 km`, `35:00`) for workout-level ledger truth while isolating work-phase metrics for interval execution grading, and accurately classify/link 35-minute `Tempo Surges` / `10K Threshold Surges` workouts instead of defaulting to `Easy Run`.
- **Preserve True Interval Peaks & Unify HR Zone Math (`HeartRateTrajectoryMapView` & `DrillExecutionScorecard`)**:
  - Preserve local maxima/minima during bucket rendering in `HeartRateTrajectoryMapView` so 4-rep threshold surge oscillations (`167-175 BPM` peaks, `134-138 BPM` recovery troughs) are never flattened into a single `157 BPM` curve, and align zone ceiling/spike calculations across the scorecard and trajectory chart.
- **Eliminate Self-Contradictory Diagnostics in `RunDetailView`**:
  - Fix the `cad == floor` boundary in `RunDetailView` (`"matched your X SPM mechanical floor"` instead of `"safely above"` when equal), and synchronize the `"What the Numbers Mean"` headline and `Cardiovascular Control` prose with the actual `DrillExecutionScorecard` execution verdict so a `Not Met` run never displays `"Strong Rhythm Found"` or praises `"steady aerobic conditioning"`.
- **Unify Primer & Main Run Durations, Subtitles, Pace Bands & UI Layout (`Workouts` & `DrillReadout`)**:
  - Compute `DrillPrimerCardView` and `Total: X Min` header durations directly from the sum of the generated `PreRunDrill` phase blocks (or format half-minute cooldowns accurately as `1.5m out` / `1m 30s` instead of truncating `90s` to `1m`), ensuring the card badge, phase bar, and preview sheet always agree.
  - Bind dynamic workout-specific subtitles, threshold pace bands, and cadence targets (`155-161 SPM`) to `PrescribedSessionCardView` and `SessionSynthesisEngine` for `10K Threshold Surges` (replacing the hardcoded `"Aerobic consistency & conversational pacing"` and walk-diluted `7:15-7:30/km` belt pace).
  - Fix `DrillReadout` so 35-minute Main Runs display `"Tempo Main Run • 35 min"` (not `"Tempo Pre-Run"`) and dynamically reflect the actual `7-minute cool-down` (not hardcoded `"2-minute cool-down"`).
  - Prevent `"Indoor (Treadmill)"` picker truncation in `DrillInterstitialReadoutView` / `DrillsLibraryView` and ensure adequate bottom safe-area inset on `WorkoutsView` so the floating tab bar does not obscure cards.

## Capabilities

### New Capabilities
- `interval-ingestion-and-classification`: Preserving walk recovery intervals, detecting multi-surge interval workouts (`10K Threshold Surges`), and maintaining ledger-true distance/duration alongside work-interval execution grading.
- `run-detail-diagnostic-coherence`: Consistent HR trajectory peak/zone rendering and non-contradictory diagnostic copy across `DrillExecutionScorecard`, `HeartRateTrajectoryMapView`, and `RunDetailView`.
- `workout-prescription-veracity`: Unified duration math, dynamic subtitles, pace/cadence bands, and readout descriptions across `PreRunDrill`, `DrillPrimerCardView`, `PrescribedSessionCardView`, and `DrillInterstitialReadoutView`.

### Modified Capabilities
<!-- No pre-existing specs in openspec/specs/ yet -->

## Impact

- **Architectural Boundary**:
  - `RunalystCore/` (Sans-I/O Core): `FramboiseCore.swift` (currently 488/500 LOC — must be split or kept strictly <= 500 LOC), `IntervalSegmenterCore.swift` (493/500 LOC — must be split or kept <= 500 LOC), `RunClassifierCore.swift` (222/500 LOC), `DrillPatternCore.swift` (488/500 LOC), `SessionSynthesisCore.swift` (485/500 LOC).
  - `Runalyst/` (Foundry & Hollow Views): `PreRunDrill.swift`, `DrillReadout.swift`, `SessionSynthesisEngine.swift`, `RunDetailView.swift`, `DrillExecutionScorecard.swift`, `HeartRateTrajectoryMapView.swift`, `DrillPrimerCardView.swift`, `PrescribedSessionCardView.swift`, `DrillInterstitialReadoutView.swift`.
- **Air-Gap & Mass Limit Compliance**: Several `RunalystCore` files (`FramboiseCore.swift` at 488 LOC, `IntervalSegmenterCore.swift` at 493 LOC, `DrillPatternCore.swift` at 488 LOC, `SessionSynthesisCore.swift` at 485 LOC) are near the 500-LOC ceiling and will be modularized or kept strictly <= 500 LOC under `./assay.sh`.
