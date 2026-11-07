# workout-prescription-veracity Specification

## Purpose
TBD - created by archiving change fix-interval-ingestion-and-workout-veracity. Update Purpose after archive.
## Requirements
### Requirement: Unified Primer Duration Math Across Card, Phase Bar, and Preview Modal
The duration displayed on the `Total: X Min` header pill, the `DrillPrimerCardView` duration badge/tile, the bottom phase summary bar, and the `DrillInterstitialReadoutView` preview sheet SHALL all derive from the exact sum of the workout's warmup, interval work/recovery, and cooldown phase durations, with sub-minute cooldowns formatted accurately (`1.5m` or `1m 30s`) rather than truncated via integer division.

#### Scenario: Short Cadence Pyramids Primer Duration Alignment
- **WHEN** a `Cadence Pyramids` pre-run primer is configured with a `1m` (`60s`) warm-up, `2 x (20s work / 30s walk)` (`100s`), and a cooldown block
- **THEN** the card badge, `DURATION` tile, `Total: X Min` pill, bottom phase bar, and `Preview` modal header SHALL report identical total duration and exact cooldown duration (never showing `7 min` on the card, `1m out` on the bar, and `4m 10s` in the modal)

### Requirement: Accurate Main Run Subtitles, Pace Bands, Cadence Targets, and Readout Prose
`PrescribedSessionCardView`, `SessionSynthesisEngine`, and `DrillReadout` SHALL display session-appropriate subtitles, work-interval pace bands, cadence targets, and structural breakdown prose for threshold/tempo main runs.

#### Scenario: 10K Threshold Surges Main Run Card and Modal
- **WHEN** the prescribed Main Run is `10K Threshold Surges` (`35 min`: `4m` warm-up, `4 x (3m work / 3m walk)`, `7m` cool-down)
- **THEN** `PrescribedSessionCardView` SHALL display a threshold-specific subtitle (never `"Aerobic consistency & conversational pacing"`), a threshold work pace band (faster than easy pace, never walk-diluted `7:15-7:30/km`), and the target cadence range (`155-161 SPM`), while `DrillReadout` SHALL label the modal `"Tempo Main Run • 35 min"` (never `"Tempo Pre-Run"`) and state `"finishing with a 7-minute cool-down"` (never `"2-minute cool-down"`)

### Requirement: Non-Truncated Environment Picker and Tab Bar Clearance
The `Run Environment` segmented control in `DrillInterstitialReadoutView` and `DrillsLibraryView` SHALL display its indoor option without ellipsis truncation, and `WorkoutsView` SHALL include sufficient bottom safe-area padding so the floating tab bar does not cover workout cards.

#### Scenario: Indoor Treadmill Segmented Control Rendering
- **WHEN** the user views the `Run Environment` segmented picker on iPhone portrait width
- **THEN** the indoor segment label SHALL render cleanly without truncating to `"Indoor (Trea..."`

