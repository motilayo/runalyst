## Context

1. **Awards Comparison (`LifetimeMilestonesCard.swift` vs Apple Fitness)**:
   - Currently, `LifetimeMilestonesCard` displays a 1-row horizontal scroll of flat circles and uses `.alert(item: $selectedBadge)` showing only `"Logged a single run of at least 5 km.\n\nStatus: Unlocked ✓"`.
   - Apple Fitness renders a 3-column grid of brushed metallic medallions (with circular, split-horizon chevron, and hexagonal shapes, plus repeat-count pills like `42` and earned values like `9.64 km` underneath), and tapping any award opens a celebratory detail view with a large metallic medallion, specific earned prose with the exact date and metric, and a **Workout** card at the bottom showing the qualifying workout.
2. **Cadence Metronome (`LiveCoachEngine.swift` & `DrillInterstitialReadoutView.swift`)**:
   - `LiveCoachEngine` and `LiveMetronomeCore` were headless and unwired from the UI, while `WatchConnectivityManager.swift` and `LiveCoachDTOs.swift` were unused `WCSession` stubs.
   - Wiring `LiveCoachEngine` into `DrillInterstitialReadoutView` turns the static `🎯 153-159 SPM` target into an interactive **Cadence Beat Preview & Treadmill Metronome** with a crisp woodblock/click tone, synchronized `.light` haptic ticks, and a visual pulse animation.

## Goals / Non-Goals

**Goals:**
- Expand `LifetimeMilestonesCore.swift` (`[Senior | pro]`) so `MilestoneBadgeSpec` carries `medallionShape`, `timesEarnedCount`, `progressFraction`, `qualifyingRunID`, `qualifyingDate`, `qualifyingDistanceMeters`, `qualifyingDurationSeconds`, `qualifyingCadenceSPM`, `earnedMetricSubtitle(useMetric:)`, and `earnedNarrativeProse(useMetric:formattedDate:)`.
- Add `LiveMetronomeCore.midpointSPM(fromTargetString:)` (`[Senior | pro]`) to parse `"153-159 SPM"` -> `156`.
- Upgrade `LifetimeMilestonesCard.swift` and create `Runalyst/Views/Components/MilestoneAwardDetailSheet.swift` (`[Mid/Jnr | flash]`) to render the 3-column Apple Fitness-style metallic medallion grid and celebratory Award Detail Sheet with the qualifying workout card.
- Wire an interactive Cadence Beat Player into `DrillInterstitialReadoutView.swift` using `LiveCoachEngine` (`[Mid/Jnr | flash]`), upgrade `LiveCoachEngine.generateBeep` to a crisp percussive woodblock click with exponential decay, and prune the unused `WatchConnectivityManager.swift` and `LiveCoachDTOs.swift` files.

**Non-Goals:**
- Adding a standalone watchOS target (Apple Watch workouts continue to execute via native `WorkoutKit`).

## Decisions

### 1. Core-First Handshake for Award Provenance (`LifetimeMilestonesCore.swift`)
- **Decision**: Compute all badge provenance deterministically in `LifetimeMilestonesCore.evaluate(samples:)`:
  - `public enum MilestoneMedallionShape: String, Sendable, Codable, Equatable { case circleRecord, splitHorizonDistance, hexagonStreak }`
  - `MilestoneBadgeSpec` gains:
    - `public let medallionShape: MilestoneMedallionShape`
    - `public let timesEarnedCount: Int`
    - `public let progressFraction: Double`
    - `public let qualifyingRunID: UUID?`
    - `public let qualifyingDate: Date?`
    - `public let qualifyingDistanceMeters: Double?`
    - `public let qualifyingDurationSeconds: Double?`
    - `public let qualifyingCadenceSPM: Double?`
    - `public func earnedMetricSubtitle(useMetric: Bool) -> String`
    - `public func earnedNarrativeProse(useMetric: Bool, formattedDate: String?) -> String`
- **Rationale**: Zero domain math or threshold formatting leaks into `LifetimeMilestonesCard` or `MilestoneAwardDetailSheet`.

### 2. Core-First Handshake for Cadence Beat Midpoint (`LiveMetronomeCore.swift`)
- **Decision**: Add `LiveMetronomeCore.midpointSPM(fromTargetString target: String?) -> Int?` in `RunalystCore` which extracts integer numbers in `100...240` from strings like `"153-159 SPM"` or `"160–166 SPM (Adapted)"` and returns their rounded average (`156`, `163`).

### 3. Pruning Inert `WCSession` Files
- **Decision**: Remove `Runalyst/LiveCoach/WatchConnectivityManager.swift` and `Runalyst/LiveCoach/LiveCoachDTOs.swift` from disk and `Runalyst.xcodeproj/project.pbxproj`, and update `RunalystTests/Models/LiveCoachDTOCodableTests.swift` to test `DrillPrescriptionDTO` and `LiveCoachEngine.shouldTriggerHaptic`.

## Risks / Trade-offs

- **[Risk] Metronome timer continuing after sheet dismissal** → **Mitigation**: Call `metronomeController.stop()` in `.onDisappear` on `DrillInterstitialReadoutView` so audio/haptic timers always terminate cleanly when the user closes the modal.
