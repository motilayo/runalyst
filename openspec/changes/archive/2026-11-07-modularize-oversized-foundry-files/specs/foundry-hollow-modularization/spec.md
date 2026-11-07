# Foundry Hollow Modularization Specification

## ADDED Requirements

### Requirement: Companion Extension Decomposition Under 500 LOC Without Code Golfing
The Foundry layer (`Runalyst/Models/` and `Runalyst/Views/`) SHALL decompose any view or modal adapter exceeding 500 lines of code into cohesive `<File>+<Section>.swift` companion extension files within the `Runalyst` target so that each resulting `.swift` file is `<= 500 LOC` while preserving 100% of existing edge-case logic, accessibility labels, and UI layout.

#### Scenario: Decomposed DrillReadout and HeartRateTrajectoryMapView files stay under 500 LOC
- **WHEN** `DrillReadout.swift` and `HeartRateTrajectoryMapView.swift` are split into companion extension files (`DrillReadout+Adaptive.swift` and `HeartRateTrajectoryMapView+Chart.swift`)
- **THEN** each resulting file SHALL have `<= 500` lines of code, compile cleanly in `Runalyst.xcodeproj`, and pass all `DrillReadoutTests` and `CrossSurfaceIdempotencyTests`.

#### Scenario: Decomposed DrillExecutionScorecard and RunDetailView files stay under 500 LOC
- **WHEN** `DrillExecutionScorecard.swift` and `RunDetailView.swift` are split into companion extension files (`DrillExecutionScorecard+Evaluation.swift`, `DrillExecutionScorecard+Subviews.swift`, `RunDetailView+Cards.swift`, `RunDetailView+PillsAndHelpers.swift`)
- **THEN** each resulting file SHALL have `<= 500` lines of code, pass `[Gate 1c] Reverse Air-Gap Audit` in `./assay.sh`, and pass `swiftlint --strict` with 0 violations.
