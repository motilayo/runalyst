# Design: Modularize Oversized Foundry Views and Modals

## Context
Four Foundry files (`DrillReadout.swift`, `HeartRateTrajectoryMapView.swift`, `DrillExecutionScorecard.swift`, and `RunDetailView.swift`) exceed 500 lines of code (`687`, `637`, `1,012`, and `1,256` LOC respectively). Per Constitutional Rule 2, we never compress or golf code to fit 500 lines; instead, we extract cohesive `extension` blocks into `<Module>+<Role>.swift` companion files and promote cross-file `private` properties/methods to `internal` (default Swift module visibility).

## Decisions
1. **Promote Cross-Extension Members from `private` to `internal`**:
   - Swift `@State`, `@Environment`, and `@AppStorage` properties accessed by extension files in the same module (`Runalyst`) must use `internal` (default) access rather than `private`.
2. **Exact File Splits & LOC Targets**:
   - `Runalyst/Models/DrillReadout.swift` (`<= 450 LOC`) + `Runalyst/Models/DrillReadout+Adaptive.swift` (`<= 300 LOC`)
   - `Runalyst/Views/HeartRateTrajectoryMapView.swift` (`<= 360 LOC`) + `Runalyst/Views/HeartRateTrajectoryMapView+Chart.swift` (`<= 320 LOC`)
   - `Runalyst/Views/DrillExecutionScorecard.swift` (`<= 420 LOC`) + `Runalyst/Views/DrillExecutionScorecard+Evaluation.swift` (`<= 420 LOC`) + `Runalyst/Views/DrillExecutionScorecard+Subviews.swift` (`<= 280 LOC`)
   - `Runalyst/Views/RunDetailView.swift` (`<= 450 LOC`) + `Runalyst/Views/RunDetailView+Cards.swift` (`<= 450 LOC`) + `Runalyst/Views/RunDetailView+PillsAndHelpers.swift` (`<= 420 LOC`)
3. **Xcode Project Registration (`Runalyst.xcodeproj/project.pbxproj`)**:
   - Register all 6 new `.swift` files in `PBXBuildFile`, `PBXFileReference`, the `Models` / `Views` `PBXGroup`, and `PBXSourcesBuildPhase` so `xcodebuild build` and `xcodebuild test` compile all companion files.
