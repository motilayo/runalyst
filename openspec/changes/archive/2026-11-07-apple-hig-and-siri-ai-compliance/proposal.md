## Why

Apple's November 3, 2026 announcement (*"Siri AI is now open to all developers"*, `gdk2umrf`) alongside Apple's Human Interface Guidelines across Siri, Generative AI, Machine Learning, HealthKit, Workouts, Playing Audio, Playing Haptics, Charting Data, and Designing for watchOS establish concrete platform contracts for modern fitness intelligence apps. While Runalyst's deterministic `RunalystCore` math and Hollow View architecture already satisfy core "Thick Client, Thin AI" mandates, a comprehensive audit revealed key gaps: zero `AppIntents` / `AppShortcutsProvider` / Spotlight `IndexedEntity` integration for Siri AI, missing `AXChartDescriptorRepresentable` Audio Graphs on Swift Charts, missing `AVAudioSession` `.mixWithOthers` / `.duckOthers` configuration and leaked cadence/haptic duty-cycle math inside `LiveCoachEngine.swift`, and missing persistent *"Analyzed on-device"* privacy and Apple Health attribution badges required by the Generative AI and HealthKit HIGs.

## What Changes

- **Pure Live Metronome & Haptic Duty-Cycle Engine (`RunalystCore`)**:
  - Extract cadence interval prescription parsing (`(\d+)x(\d+)m`), target SPM band bounds (`targetSPM +/- 5`), corrective haptic drift logic (`currentSPM < targetSPM`), and duty-cycled haptic burst triggers (`intervalElapsedSeconds <= 20.0 || currentSPM < targetSPM - 2`) out of `Runalyst/LiveCoach/LiveCoachEngine.swift` into a pure, deterministic `LiveMetronomeCore` module in `RunalystCore`.
- **Siri AI, App Intents & Spotlight Semantic Index (`Runalyst/Intents/`)**:
  - Introduce `RunalystAppShortcuts` (`AppShortcutsProvider`), `CheckReadinessIntent`, `GetPrescribedWorkoutIntent`, and `ReportSubjectiveDistressIntent` bridging Siri AI and Shortcuts directly to `SessionSynthesisEngine` and `BanisterReadinessCore` with glanceable SwiftUI Siri Snippet Views.
  - Introduce `RunRecordAppEntity` conforming to `AppEntity` and `IndexedEntity` so Spotlight's Semantic Index and Siri AI can surface historical workouts naturally.
- **HIG Audio & Haptic Compliance (`Runalyst/LiveCoach/LiveCoachEngine.swift`)**:
  - Configure `AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])` before starting `AVAudioEngine` so metronome ticks never interrupt a runner's background music or podcasts, while delegating all cadence/haptic math to `LiveMetronomeCore`.
- **HIG Charting Data & Audio Graphs (`Runalyst/Views/*Chart*`)**:
  - Implement `AXChartDescriptorRepresentable` (`accessibilityChartDescriptor`) for `HeartRateTrajectoryMapView`, `RunVarianceMapView`, and `ProgressionChartView` so VoiceOver and Audio Graphs synthesize pitch-mapped heart rate, pace, and cadence trends.
- **HIG Generative AI, Machine Learning & HealthKit Attribution (`Runalyst/Views/Components/`)**:
  - Upgrade `AIDisclaimerFooter` and coaching surfaces with the persistent *"Analyzed on-device"* Apple Intelligence privacy badge and Apple Health data attribution required by `docs/BLUEPRINT.md` and the Apple HealthKit / Generative AI HIGs.

## Capabilities

### New Capabilities
- `siri-ai-and-hig-compliance`: Covers pure `LiveMetronomeCore` extraction in `RunalystCore`, Siri AI `AppIntents` + `IndexedEntity` Spotlight semantic indexing, `AVAudioSession` background audio mixing, `AXChartDescriptorRepresentable` Audio Graphs across Swift Charts, and Generative AI / HealthKit HIG attribution badges.

### Modified Capabilities
<!-- No existing spec requirements are broken; this is an additive capability and architectural purification. -->

## Impact

- **`RunalystCore` (Sans-I/O Reference Core)**:
  - New `RunalystCore/Sources/RunalystCore/LiveMetronomeCore.swift` (zero I/O, zero Apple frameworks beyond `Foundation`) + unit tests in `RunalystCore/Tests/RunalystCoreTests/LiveMetronomeCoreTests.swift`.
- **`Runalyst` (The Foundry — Adapters & Intents)**:
  - Refactored `Runalyst/LiveCoach/LiveCoachEngine.swift` to delegate math to `LiveMetronomeCore` and configure `AVAudioSession` `.mixWithOthers`.
  - New `Runalyst/Intents/RunalystShortcuts.swift` (`AppShortcutsProvider`, `AppIntent` conformances, `IndexedEntity`, and Siri Snippet Views).
- **`Runalyst` (Hollow Views & Accessibility)**:
  - New `Runalyst/Views/Components/ChartAudioGraphDescriptors.swift` implementing `AXChartDescriptorRepresentable` for `HeartRateTrajectoryMapView+Chart.swift`, `RunVarianceMapView.swift`, and `ProgressionChartView.swift`.
  - Updated `Runalyst/Views/Components/AIDisclaimerFooter.swift` and `Runalyst/Views/PermissionsSyncSectionView.swift` with on-device privacy and Apple Health attribution badges.
- **Air-Gap & Modularity Assessment**:
  - Enforces both the Forward Air-Gap (`RunalystCore` imports only `Foundation`) and Reverse Air-Gap (`LiveCoachEngine` and Views hold zero domain math). All new and modified files stay cleanly below the ~500 LOC modularity guideline.
