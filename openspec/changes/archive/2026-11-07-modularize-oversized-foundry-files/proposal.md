# Proposal: Modularize Oversized Foundry Views and Modals Under 500 LOC

## Why
While all 27 domain modules in `RunalystCore` strictly obey the `<= 500 LOC` ceiling and both the Forward and Reverse Air-Gaps (`[Gate 1]` through `[Gate 1c]` in `./assay.sh`), four key Foundry files modified during recent interval and synthesis work remain over 500 lines of code:
- `Runalyst/Views/RunDetailView.swift` (`1,256 LOC`)
- `Runalyst/Views/DrillExecutionScorecard.swift` (`1,012 LOC`)
- `Runalyst/Models/DrillReadout.swift` (`687 LOC`)
- `Runalyst/Views/HeartRateTrajectoryMapView.swift` (`637 LOC`)

Decomposing these four files into clean, cohesive `<File>+Subviews.swift` / `<File>+Templates.swift` companion extensions (without code-golfing or altering runtime behavior) brings the Foundry into full `<= 500 LOC` structural parity with `RunalystCore`.

## What Changes
- **Decompose `DrillReadout.swift` (`687 LOC`)** into:
  - `Runalyst/Models/DrillReadout.swift` (`<= 450 LOC`): Core `DrillReadout` struct, factory `readout(for:...)`, and `ActiveDrillReadoutItem`.
  - `Runalyst/Models/DrillReadout+Adaptive.swift` (`<= 350 LOC`): Readiness modulation and `ActiveDrillReadoutItem` adaptive/prescription builders.
- **Decompose `HeartRateTrajectoryMapView.swift` (`637 LOC`)** into:
  - `Runalyst/Views/HeartRateTrajectoryMapView.swift` (`<= 380 LOC`): Main view state, `HRPlotPoint` mapping, and `AerobicStrainEvaluation` bindings.
  - `Runalyst/Views/HeartRateTrajectoryMapView+Chart.swift` (`<= 350 LOC`): Swift Charts rendering layers, scrub overlay, and legend components.
- **Decompose `DrillExecutionScorecard.swift` (`1,012 LOC`)** into:
  - `Runalyst/Views/DrillExecutionScorecard.swift` (`<= 450 LOC`): Core scorecard container, header, and metric tile layout.
  - `Runalyst/Views/DrillExecutionScorecard+Evaluation.swift` (`<= 450 LOC`): Adherence calculation adapter (`calculateAdherence`) and interval/cadence evaluation helpers.
  - `Runalyst/Views/DrillExecutionScorecard+Subviews.swift` (`<= 300 LOC`): Reusable subview components, rep breakdown rows, and explainer sheets.
- **Decompose `RunDetailView.swift` (`1,256 LOC`)** into:
  - `Runalyst/Views/RunDetailView.swift` (`<= 450 LOC`): Main view declaration, state properties, `body`, and lifecycle handlers.
  - `Runalyst/Views/RunDetailView+Cards.swift` (`<= 450 LOC`): `aiRunAnalysisCard`, `heroMetricsCard`, `secondaryBiomechanicsCard`, and `workoutRhythmTimeline`.
  - `Runalyst/Views/RunDetailView+PillsAndHelpers.swift` (`<= 450 LOC`): `environmentPill`, `classificationPill`, drill normalization helpers, and classification update logic.
- **Register all new companion files in `Runalyst.xcodeproj/project.pbxproj`**.

## Impact & Air-Gap Assessment
- **Architectural Boundary**: Touches only `Runalyst/` (The Foundry — Models & Hollow Views) and `Runalyst.xcodeproj/project.pbxproj`. Zero changes to `RunalystCore/`.
- **Air-Gap & Mass Compliance**: Every resulting file in this change set is strictly `<= 500 LOC`, passes `./assay.sh` (including `[Gate 1c] Reverse Air-Gap Audit`), and passes `swiftlint --strict` with zero violations.
