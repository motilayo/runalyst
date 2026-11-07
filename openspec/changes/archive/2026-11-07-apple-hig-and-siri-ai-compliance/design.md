## Context

Apple's November 3, 2026 Developer Preview announcement (*"Siri AI is now open to all developers"*, `gdk2umrf`) and the 9 accompanying Apple Human Interface Guidelines (Siri, Machine Learning, Generative AI, HealthKit, Workouts, Playing Audio, Playing Haptics, Charting Data, and Designing for watchOS) define the gold-standard integration patterns for Apple-native sports science apps.

Our codebase audit identified four concrete areas to complete Runalyst's alignment while strictly upholding both the Forward and Reverse Air-Gap:
1. **`LiveCoachEngine.swift` Leaked Domain Math & Missing Audio Mixing**: `Runalyst/LiveCoach/LiveCoachEngine.swift` currently computes prescription regex parsing (`(\d+)x(\d+)m`), cadence alert bounds (`max(0, targetSPM - 5)...(targetSPM + 5)`), metronome beat intervals (`60.0 / Double(targetSPM)`), and haptic duty-cycle thresholds (`intervalElapsedSeconds <= 20.0 || currentSPM < (targetSPM - 2)`) directly in the Foundry layer, and starts `AVAudioEngine` without setting `AVAudioSession` `.mixWithOthers`.
2. **Siri AI & Spotlight Semantic Index (`AppIntents` + `IndexedEntity`)**: `Runalyst` has no `AppIntents` or `AppShortcutsProvider` integration, preventing Siri AI from querying daily readiness, surfacing today's prescribed session, logging subjective fatigue overrides, or indexing `RunRecord` workouts in Spotlight's Semantic Index.
3. **Swift Charts Audio Graphs (`AXChartDescriptorRepresentable`)**: `HeartRateTrajectoryMapView+Chart.swift`, `RunVarianceMapView.swift`, and `ProgressionChartView.swift` use Swift Charts without `.accessibilityChartDescriptor(...)` Audio Graph support.
4. **Generative AI & HealthKit HIG Badges**: `AIDisclaimerFooter.swift` and `PermissionsSyncSectionView.swift` need the persistent *"Analyzed on-device"* badge (`docs/BLUEPRINT.md` Section 2) and explicit Apple Health attribution required by the HealthKit HIG.

## Goals / Non-Goals

**Goals:**
- Extract all cadence prescription parsing, beat interval math, and haptic duty-cycle thresholds into `RunalystCore/Sources/RunalystCore/LiveMetronomeCore.swift` (`[Senior | pro]`) with comprehensive unit tests.
- Upgrade `Runalyst/LiveCoach/LiveCoachEngine.swift` (`[Mid/Jnr | flash]`) to delegate math to `LiveMetronomeCore` and configure `AVAudioSession` with `.mixWithOthers` so background music/podcasts are never interrupted.
- Implement `Runalyst/Intents/RunalystShortcuts.swift` (`[Mid/Jnr | flash]`) providing `CheckReadinessIntent`, `GetPrescribedWorkoutIntent`, `ReportSubjectiveDistressIntent`, `RunRecordAppEntity` (`AppEntity`, `IndexedEntity` via `CoreSpotlight`), `RunalystAppShortcuts` (`AppShortcutsProvider`), and Siri Snippet Views.
- Implement `Runalyst/Views/Components/ChartAudioGraphDescriptors.swift` (`[Mid/Jnr | flash]`) conforming heart rate trajectory, run variance, and progression chart series to `AXChartDescriptorRepresentable` and wire `.accessibilityChartDescriptor(...)` into all 3 chart views.
- Upgrade `AIDisclaimerFooter.swift` and `PermissionsSyncSectionView.swift` (`[Mid/Jnr | flash]`) with the persistent *"Analyzed on-device"* privacy pill and Apple Health attribution badge.

**Non-Goals:**
- Adding a separate watchOS Xcode target or WidgetKit extension target in this change (to keep `project.pbxproj` target topologies focused and deterministic in CI).
- Modifying any existing `DrillScheduleCore` or `IntervalSegmenterCore` biomechanics math.

## Decisions

### 1. Core-First Handshake: `LiveMetronomeCore` in `RunalystCore`
- **Decision**: Create `RunalystCore/Sources/RunalystCore/LiveMetronomeCore.swift` containing:
  - `public struct ParsedIntervalPrescription: Sendable, Equatable` (`iterations: Int`, `distanceMeters: Double`, `cadenceLowerBound: Double`, `cadenceUpperBound: Double`)
  - `public enum LiveMetronomeCore` with static pure functions:
    - `parsePrescription(_ prescription: String, targetSPM: Int) -> ParsedIntervalPrescription?`
    - `beatIntervalSeconds(forTargetSPM targetSPM: Int) -> TimeInterval?`
    - `shouldTriggerCorrectiveHaptic(currentSPM: Int, targetSPM: Int) -> Bool`
    - `shouldTriggerDutyCycledHaptic(isEnabled: Bool, currentSPM: Int, targetSPM: Int, intervalElapsedSeconds: TimeInterval) -> Bool`
- **Rationale**: Satisfies the Reverse Air-Gap by moving all cadence/haptic domain thresholds into `RunalystCore` where they are testable in milliseconds via `swift test`.

### 2. Siri AI Integration via `AppIntents` and `IndexedEntity`
- **Decision**: Create `Runalyst/Intents/RunalystShortcuts.swift` importing `AppIntents`, `CoreSpotlight`, `SwiftData`, and `SwiftUI`.
  - `RunRecordAppEntity: AppEntity, IndexedEntity` exposes workout date, classification, distance, working pace, and cadence to Siri AI and the Spotlight Semantic Index (`attributeSet: CSSearchableItemAttributeSet`).
  - `CheckReadinessIntent: AppIntent` & `GetPrescribedWorkoutIntent: AppIntent` read the latest workouts via `ModelContainer` on `@MainActor`, evaluate `BanisterReadinessCore` / `DrillScheduleCore`, and return ` some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetView`.
  - `ReportSubjectiveDistressIntent: AppIntent` records a subjective fatigue override so the runner can tell Siri *"I'm feeling exhausted today"* hands-free.
  - `RunalystAppShortcuts: AppShortcutsProvider` registers natural phrases for Siri AI discovery.

### 3. Audio Graphs via `AXChartDescriptorRepresentable`
- **Decision**: Create `Runalyst/Views/Components/ChartAudioGraphDescriptors.swift` with 3 lightweight value types (`HRWaveAudioGraphDescriptor`, `RunVarianceAudioGraphDescriptor`, `ProgressionAudioGraphDescriptor`) conforming to `AXChartDescriptorRepresentable` and attach them via `.accessibilityChartDescriptor(...)` on `HeartRateTrajectoryMapView+Chart.swift`, `RunVarianceMapView.swift`, and `ProgressionChartView.swift`.
- **Rationale**: Keeps the chart view files concise while giving VoiceOver users full pitch-mapped Audio Graph navigation per Apple's Charting Data HIG.

## Risks / Trade-offs

- **[Risk] `AVAudioSession` activation in unit tests on Simulator** → **Mitigation**: Guard `AVAudioSession.sharedInstance().setCategory(...)` inside `setupAudioIfNeeded()` behind the existing `guard !isRunningInTest else { return }` check so headless XCTest runs never contend for Simulator audio hardware.
- **[Risk] Xcode project registration for new Foundry files** → **Mitigation**: Register `RunalystShortcuts.swift` and `ChartAudioGraphDescriptors.swift` in `Runalyst.xcodeproj/project.pbxproj` (`PBXBuildFile`, `PBXFileReference`, `PBXGroup`, `PBXSourcesBuildPhase`) and verify with both `./assay.sh` and `xcodebuild test`.
