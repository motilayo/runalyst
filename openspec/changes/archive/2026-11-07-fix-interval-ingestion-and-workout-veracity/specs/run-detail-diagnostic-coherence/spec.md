## ADDED Requirements

### Requirement: True Heart Rate Trajectory Peak and Oscillation Rendering
The `HeartRateTrajectoryMapView` SHALL render actual bucket telemetry (or extrema-preserving bucket series) across the full workout timeline so that multi-interval heart rate peaks and recovery troughs are visible and the displayed Peak HR badge matches the true peak heart rate of the workout.

#### Scenario: 4x3m Interval Heart Rate Oscillations
- **WHEN** a 35-minute interval workout contains 4 work surges reaching `154-175 BPM` separated by recovery drops to `134-138 BPM`
- **THEN** `HeartRateTrajectoryMapView` SHALL plot the 4 distinct heart rate oscillations across the 35-minute timeline and report the true peak heart rate rather than flattening the curve to an interpolated split average (`157 Peak`)

#### Scenario: Zone Spike Banner and Chart Zone Consistency
- **WHEN** `DrillExecutionScorecard` and `HeartRateTrajectoryMapView` evaluate heart rate zone distribution for the same `RunRecord`
- **THEN** both components SHALL use the same zone boundary thresholds so that a `Zone 4 Spike` percentage never contradicts the Peak HR zone classification shown on the trajectory chart

### Requirement: Non-Contradictory Run Detail Diagnostic Copy
The `"What the Numbers Mean"` section in `RunDetailView` SHALL generate headline and metric bullets that are mathematically accurate at boundary values (`cadence == floor`) and strictly consistent with the `DrillExecutionScorecard` execution verdict (`Met` vs `Not Met`).

#### Scenario: Cadence Exactly Equals Mechanical Floor
- **WHEN** a run's working cadence (`154 SPM`) equals the runner's mechanical cadence floor (`154 SPM`)
- **THEN** the `Cadence & Form` diagnostic bullet SHALL state that turnover matched/met the `154 SPM` mechanical floor, and MUST NOT state `"safely above your 154 SPM mechanical floor"`

#### Scenario: Execution Status Not Met Due to Cardiac Strain
- **WHEN** the execution verdict for a run is `Not Met` due to heart rate exceeding the target zone ceiling
- **THEN** `RunDetailView` MUST NOT display the positive headline `"Strong Rhythm Found"` or claim that average heart rate `"reflects steady aerobic conditioning"`, and the `Execution Verdict` bullet SHALL specify the actual failure dimension (cardiac drift vs cadence drop) rather than a generic `"cardiac drift or cadence drop"` string
