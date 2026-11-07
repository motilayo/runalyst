# interval-ingestion-and-classification Specification

## Purpose
TBD - created by archiving change fix-interval-ingestion-and-workout-veracity. Update Purpose after archive.
## Requirements
### Requirement: Structured Interval Walk Recovery Preservation
The system SHALL preserve intentional walking recovery intervals and warm-up/cool-down phases in workout-level distance and duration totals when a run contains structured alternating work and recovery cycles (`>= 3` work surges separated by recovery intervals), rather than stripping walking recoveries as dead stops.

#### Scenario: 35-Minute 10K Threshold Surges with Walk Recoveries
- **WHEN** a runner completes a 35-minute (`2100s`), `4.55 km` workout containing a 4-minute warm-up, `4 x (3-minute work surge at 5:22-5:29/km and 158-160 SPM paired with 3-minute walk recovery at 10:24-11:59/km and 114-124 SPM)`, and a 7-minute cool-down
- **THEN** the workout summary SHALL preserve the full `4.55 km` distance and `35:00` moving duration for ledger truth while exposing work-interval metrics (`158-160 SPM` work cadence, `5:22-5:29/km` work pace) for interval execution evaluation

#### Scenario: Unstructured Run with Traffic Stop
- **WHEN** a runner completes a continuous aerobic run containing an isolated stationary stop (`speed <= 0.5 m/s` or isolated walking break with `< 3` work/recovery cycles)
- **THEN** `FramboiseCore` SHALL continue to trim the isolated dead-stop bucket from working pace and cadence calculations

### Requirement: Multi-Surge Interval Classification and Workout Linking
The system SHALL classify workouts exhibiting `>= 3` alternating work/recovery surge cycles (where work pace exceeds recovery pace by `>= 45 s/km` and work cadence is `>= 145 SPM`) as `"Interval"` or `"Tempo"` and link matching 35-minute `4 x 3m` sessions to `Tempo Surges` (`10K Threshold Surges`), rather than defaulting to `"Easy Run"`.

#### Scenario: 4x3m Threshold Surges Classification
- **WHEN** an ingested 35-minute indoor or outdoor run contains 4 work surges of ~3 minutes (`180s`) at `5:20-5:35/km` (`155-161 SPM`) separated by 3-minute walking recoveries (`10:00-12:00/km`, `110-125 SPM`)
- **THEN** `RunClassifierCore` and `IntervalSegmenterCore` SHALL classify the run as an interval/tempo session (never `"Easy Run"`) and evaluate execution against the interval/tempo target rather than the `Zone 2 Easy Base` ceiling

