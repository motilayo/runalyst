## 1. Reference Core: Milestone Provenance & Cadence Midpoint Math (`RunalystCore`)

- [x] 1.1 [Senior | pro] Expand `RunalystCore/Sources/RunalystCore/LifetimeMilestonesCore.swift` with `MilestoneMedallionShape` (`.circleRecord`, `.splitHorizonDistance`, `.hexagonStreak`), qualifying run provenance (`qualifyingRunID`, `qualifyingDate`, `qualifyingDistanceMeters`, `qualifyingDurationSeconds`, `qualifyingCadenceSPM`), `timesEarnedCount`, `progressFraction`, `earnedMetricSubtitle(useMetric:)`, and `earnedNarrativeProse(useMetric:formattedDate:)`.
- [x] 1.2 [Senior | pro] Add `LiveMetronomeCore.midpointSPM(fromTargetString:)` to `RunalystCore/Sources/RunalystCore/LiveMetronomeCore.swift` and add unit tests in `LiveMetronomeCoreTests.swift` and `LifetimeMilestonesCoreTests.swift`.

## 2. Apple Fitness-Style Medallion Grid & Award Detail Sheet (`Runalyst/Views`)

- [x] 2.1 [Mid/Jnr | flash] Create `Runalyst/Views/Components/MilestoneAwardDetailSheet.swift` (and register in `project.pbxproj`) rendering the Apple Fitness-inspired metallic medallion (`circleRecord`, `splitHorizonDistance`, `hexagonStreak`), repeat count pill, earned narrative with exact metric and date (or progress bar when locked), and the Qualifying Workout Card at the bottom.
- [x] 2.2 [Mid/Jnr | flash] Upgrade `Runalyst/Views/LifetimeMilestonesCard.swift` to replace the 1-row flat circle strip and `.alert` with a 3-column Apple Fitness-style metallic medallion grid (with earned metric subtitles and repeat-count pills) presenting `MilestoneAwardDetailSheet` via `.sheet(item: $selectedBadge)`.

## 3. Live Interactive Cadence Beat Player & Dead Code Pruning (`Runalyst/LiveCoach` & `DrillInterstitialReadoutView`)

- [x] 3.1 [Mid/Jnr | flash] Upgrade `Runalyst/LiveCoach/LiveCoachEngine.swift` to synthesize a crisp percussive woodblock click (exponential decay envelope) with synchronized `.light` haptic ticks on iOS, wire an interactive **Cadence Beat Player** into `Runalyst/Views/DrillInterstitialReadoutView.swift` (tappable header SPM pill + interactive beat preview bar that auto-stops `.onDisappear`), and remove dead `WatchConnectivityManager.swift` and `LiveCoachDTOs.swift` from disk, `project.pbxproj`, and `LiveCoachDTOCodableTests.swift`.

## 4. Verification & Assay Gatekeeper

- [x] 4.1 [Scout | flash_lite] Verify all requirements and scenarios in `openspec/changes/fitness-awards-and-live-metronome/specs/fitness-awards-and-live-metronome/spec.md` against the implemented files and line numbers.
- [x] 4.2 [Staff/Lead | parent] Execute `./assay.sh`, run `xcodebuild test`, visually validate the new Awards Grid, Award Detail Sheet, and Cadence Beat Player on the iOS Simulator, archive the OpenSpec change, and open a Pull Request.
