## Why

Runalyst currently has two major experiential gaps between its deterministic backend and its user-facing UI:
1. **Runalyst Milestones vs. Apple Fitness Awards**: In `LifetimeMilestonesCard.swift`, milestone badges are rendered as a 1-row flat horizontal strip where tapping a badge triggers a generic `UIAlertController` (`"Status: Unlocked ✓"` / `[ OK ]`) with zero workout provenance, zero earned date or best-mark telemetry, zero repeat counts (`×12`), and zero progress tracking when locked. By contrast, Apple Fitness Awards render 3-column metallic medallions with earned metric subtitles, repeat-count pills, and a rich celebratory Award Detail Sheet linking directly to the qualifying workout.
2. **Headless Metronome vs. Real Interactive Cadence Beat Player**: `LiveCoachEngine.swift` and `LiveMetronomeCore.swift` exist only in unit tests and are not wired to any UI surface, while `WatchConnectivityManager.swift` and `LiveCoachDTOs.swift` are inert `WCSession` scaffolding. On `DrillInterstitialReadoutView`, the `🎯 153–159 SPM` badge is static text, leaving runners (especially on indoor treadmills where watchOS disables `CadenceRangeAlert`) with no way to hear or feel their prescribed cadence rhythm.

## What Changes

- **Rich Milestone Provenance & Medallion Geometry in `RunalystCore` (`LifetimeMilestonesCore.swift`)**:
  - Expand `MilestoneBadgeSpec` with deterministic award provenance computed purely from `[MilestoneRunSample]`:
    - `medallionShape: MilestoneMedallionShape` (`.circleRecord`, `.splitHorizonDistance`, `.hexagonStreak`)
    - `timesEarnedCount: Int` (number of qualifying workouts or volume/streak count)
    - `qualifyingRunID: UUID?`, `qualifyingDate: Date?`, and `qualifyingDistanceMeters: Double?` / `qualifyingDurationSeconds: Double?` / `qualifyingPaceSecondsPerKm: Double?` / `qualifyingCadenceSPM: Double?`
    - `progressFraction: Double` (`0.0...1.0`) and `earnedMetricSummary(useMetric: Bool) -> String` / `earnedNarrativeProse(useMetric: Bool, formattedDate: String?) -> String`
- **Pure Target Cadence Midpoint & Woodblock Envelope Math in `RunalystCore` (`LiveMetronomeCore.swift`)**:
  - Add `LiveMetronomeCore.midpointSPM(fromTargetString:)` (e.g. `"153-159 SPM"` -> `156`, `"170 SPM"` -> `170`) and percussive click envelope parameters so `LiveCoachEngine` produces a crisp, pleasant woodblock/click tone instead of a raw 880 Hz sine wave.
- **Apple Fitness-Style Metallic Medallion Grid & Award Detail Sheet (`LifetimeMilestonesCard.swift` + `MilestoneAwardDetailSheet.swift`)**:
  - Upgrade `LifetimeMilestonesCard.swift` from a 1-row flat strip + `Alert` to an Apple Fitness-inspired **3-column Metallic Medallion Grid** displaying multi-bezel metallic medallions, repeat-count pills (`×14`), badge titles, and earned metric subtitles (`5.4 km`, `174 SPM`, `1.42 EF`).
  - Create `MilestoneAwardDetailSheet.swift` presenting a full-bleed celebratory sheet with a large (`180x180pt`) metallic medallion, earned narrative with exact metric and date (or progress bar when locked), and the **Qualifying Workout Card** at the bottom.
- **Live Interactive Cadence Beat Player (`DrillInterstitialReadoutView.swift`) & Pruning Dead `WCSession` Code**:
  - Wire an interactive **Cadence Beat Preview / Live Metronome** bar and tappable `🎯 153–159 SPM` pill into `DrillInterstitialReadoutView.swift` powered by `LiveCoachEngine` + `LiveMetronomeCore` (playing rhythmic audio clicks mixed via `.mixWithOthers` + synced `UIImpactFeedbackGenerator(style: .light)` haptic pulses + visual pulse animation, auto-stopping `.onDisappear`).
  - Remove dead `WCSession` scaffolding (`Runalyst/LiveCoach/WatchConnectivityManager.swift` and `Runalyst/LiveCoach/LiveCoachDTOs.swift`) and update `LiveCoachDTOCodableTests.swift` accordingly.

## Capabilities

### New Capabilities
- `fitness-awards-and-live-metronome`: Covers `LifetimeMilestonesCore` provenance & medallion telemetry, Apple Fitness-style 3-column metallic medallion grid and `MilestoneAwardDetailSheet`, interactive `LiveCoachEngine` Cadence Beat Player in `DrillInterstitialReadoutView`, and removal of dead `WCSession` files.

### Modified Capabilities
<!-- None -->

## Impact

- **`RunalystCore`**:
  - `RunalystCore/Sources/RunalystCore/LifetimeMilestonesCore.swift` + unit tests in `RunalystCore/Tests/RunalystCoreTests/LifetimeMilestonesCoreTests.swift`.
  - `RunalystCore/Sources/RunalystCore/LiveMetronomeCore.swift` + `RunalystCore/Tests/RunalystCoreTests/LiveMetronomeCoreTests.swift`.
- **`Runalyst` (Foundry & Hollow Views)**:
  - `Runalyst/Views/LifetimeMilestonesCard.swift` + new `Runalyst/Views/Components/MilestoneAwardDetailSheet.swift`.
  - `Runalyst/Views/DrillInterstitialReadoutView.swift` + `Runalyst/LiveCoach/LiveCoachEngine.swift`.
  - Removed dead `Runalyst/LiveCoach/WatchConnectivityManager.swift` and `Runalyst/LiveCoach/LiveCoachDTOs.swift`.
