## ADDED Requirements

### Requirement: Deterministic Milestone Provenance, Repeat Counts, and Medallion Geometry in RunalystCore
`LifetimeMilestonesCore.evaluate(samples:)` SHALL compute for every `MilestoneBadgeSpec` its geometric medallion shape (`MilestoneMedallionShape`), repeat count (`timesEarnedCount`), progress fraction (`progressFraction` in `0.0...1.0`), qualifying run metadata (`qualifyingRunID`, `qualifyingDate`, `qualifyingDistanceMeters`, `qualifyingDurationSeconds`, `qualifyingCadenceSPM`), and pre-computed earned metric summary and narrative prose methods (`earnedMetricSubtitle(useMetric:)`, `earnedNarrativeProse(useMetric:formattedDate:)`).

#### Scenario: Evaluating 5K Milestone with multiple qualifying runs
- **WHEN** `LifetimeMilestonesCore.evaluate(samples:)` is given 3 runs of `5200m`, `6400m`, and `3100m`
- **THEN** the `.fiveK` badge SHALL have `isUnlocked == true`, `timesEarnedCount == 2`, `qualifyingRunID` matching the `6400m` best-distance run, `progressFraction == 1.0`, and `medallionShape == .splitHorizonDistance`

#### Scenario: Evaluating locked 100K Century Volume badge progress
- **WHEN** `LifetimeMilestonesCore.evaluate(samples:)` is given runs totaling `64_500m` (`64.5 km`)
- **THEN** the `.centuryVolume` badge SHALL have `isUnlocked == false`, `progressFraction == 0.645`, and `earnedMetricSubtitle(useMetric: true)` returning `"64.5 / 100 km"`

### Requirement: Target Cadence String Midpoint Extraction in LiveMetronomeCore
`LiveMetronomeCore.midpointSPM(fromTargetString:)` SHALL deterministically parse cadence range strings (e.g., `"153-159 SPM"`, `"160–166 SPM (Adapted)"`, `"170 SPM"`) and return the integer midpoint SPM (`156`, `163`, `170`) or `nil` when no valid cadence integers exist.

#### Scenario: Parsing en-dash and hyphen cadence ranges
- **WHEN** `LiveMetronomeCore.midpointSPM(fromTargetString: "153–159 SPM")` is called
- **THEN** it SHALL return `156`

### Requirement: Apple Fitness-Style 3-Column Metallic Medallion Grid and Award Detail Sheet
`LifetimeMilestonesCard` SHALL render milestone badges in a 3-column metallic medallion grid displaying each badge's geometric medallion, repeat-count badge (`×N` when `timesEarnedCount > 1`), title, and earned metric subtitle, and tapping any badge SHALL present `MilestoneAwardDetailSheet` (replacing the legacy `.alert`) showing a hero metallic medallion, earned narrative with date/metric provenance (or progress bar when locked), and the qualifying workout summary card.

#### Scenario: Tapping an unlocked milestone badge in LifetimeMilestonesCard
- **WHEN** the user taps an unlocked badge such as `5K Milestone`
- **THEN** `MilestoneAwardDetailSheet` SHALL present the hero metallic medallion, the earned narrative with the qualifying date and distance, and the qualifying workout card

### Requirement: Interactive Cadence Beat Player in DrillInterstitialReadoutView and Removal of Inert WCSession Code
`DrillInterstitialReadoutView` SHALL provide an interactive Cadence Beat Player (triggered from the header cadence pill or a dedicated beat preview control) that plays rhythmic audio clicks mixed via `.mixWithOthers` and synchronized `.light` haptic ticks at `LiveMetronomeCore.midpointSPM(fromTargetString:)` via `LiveCoachEngine`, automatically stopping when the view disappears; and inert `WCSession` files (`WatchConnectivityManager.swift` and `LiveCoachDTOs.swift`) SHALL be removed from the project.

#### Scenario: Toggling the live cadence beat preview on a drill readout sheet
- **WHEN** the runner taps the Cadence Beat Preview button on `DrillInterstitialReadoutView` for a `153-159 SPM` drill
- **THEN** `LiveCoachEngine` SHALL start the metronome at `156 SPM` with synchronized haptic pulses and stop cleanly when toggled off or when the sheet is dismissed
