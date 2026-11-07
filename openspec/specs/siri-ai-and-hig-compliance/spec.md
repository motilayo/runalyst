# siri-ai-and-hig-compliance Specification

## Purpose
TBD - created by archiving change apple-hig-and-siri-ai-compliance. Update Purpose after archive.
## Requirements
### Requirement: Pure Live Metronome and Haptic Duty-Cycle Engine in RunalystCore
The `RunalystCore` package SHALL provide a pure, deterministic `LiveMetronomeCore` engine that computes cadence interval prescription parsing, target SPM bounds, metronome beat intervals, and duty-cycled haptic trigger evaluations without importing any Apple UI/audio frameworks or wall-clock APIs.

#### Scenario: Parsing prescription strings and computing target cadence bounds
- **WHEN** `LiveMetronomeCore.parsePrescription("4x400m intervals", targetSPM: 170)` is called
- **THEN** it SHALL return `iterations == 4`, `distanceMeters == 400.0`, and `cadenceRange == 165.0...175.0` (`max(0, targetSPM - 5)...(targetSPM + 5)`)

#### Scenario: Evaluating duty-cycled haptic burst and drift triggers
- **WHEN** `LiveMetronomeCore.shouldTriggerHaptic(isEnabled: true, currentSPM: 169, targetSPM: 170, intervalElapsedSeconds: 15.0)` is evaluated during the initial 20-second lock-in window
- **THEN** it SHALL return `true`
- **WHEN** `intervalElapsedSeconds > 20.0` and `currentSPM >= targetSPM - 2`
- **THEN** it SHALL return `false` to prevent continuous haptic actuator fatigue per Apple's Playing Haptics HIG

### Requirement: Background-Friendly Audio Session Mixing in LiveCoachEngine
The `LiveCoachEngine` SHALL configure `AVAudioSession` with `.playback` and `.mixWithOthers` before starting `AVAudioEngine` so metronome cues never interrupt the runner's background music or podcast playback, while delegating all cadence and haptic threshold calculations to `LiveMetronomeCore`.

#### Scenario: Starting the metronome alongside background audio
- **WHEN** `LiveCoachEngine` initializes audio output outside unit test runners
- **THEN** it SHALL configure `AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])` and delegate interval timing (`60.0 / Double(targetSPM)`) and haptic evaluations to `LiveMetronomeCore`

### Requirement: Siri AI App Intents, Shortcuts Provider, and Spotlight Semantic Indexing
The `Runalyst` application SHALL expose Siri AI and Shortcuts capabilities via `AppIntents` (`CheckReadinessIntent`, `GetPrescribedWorkoutIntent`, `ReportSubjectiveDistressIntent`, `RunalystAppShortcuts`) and Spotlight Semantic Indexing (`RunRecordAppEntity: AppEntity, IndexedEntity`) backed by deterministic `RunalystCore` primitives and glanceable Siri Snippet Views.

#### Scenario: Querying daily readiness and workout prescription via Siri AI
- **WHEN** a runner invokes `CheckReadinessIntent` or `GetPrescribedWorkoutIntent` through Siri AI or Shortcuts
- **THEN** the intent SHALL evaluate deterministic readiness and session state from the local SwiftData store (or default productive baseline when empty) and return a spoken dialog paired with a high-contrast SwiftUI Snippet View

#### Scenario: Reporting subjective fatigue override via Siri AI
- **WHEN** a runner invokes `ReportSubjectiveDistressIntent`
- **THEN** the intent SHALL persist the subjective fatigue override in `UserDefaults.standard` for today and return a safety-first recovery directive

### Requirement: Swift Charts Audio Graphs Accessibility Descriptors
All primary Swift Charts in `Runalyst` (`HeartRateTrajectoryMapView`, `RunVarianceMapView`, and `ProgressionChartView`) SHALL attach an `AXChartDescriptorRepresentable` via `.accessibilityChartDescriptor(...)` per Apple's Charting Data HIG so VoiceOver users can play pitch-mapped Audio Graphs.

#### Scenario: VoiceOver Audio Graph generation for heart rate, variance, and progression charts
- **WHEN** VoiceOver inspects `HeartRateTrajectoryMapView`, `RunVarianceMapView`, or `ProgressionChartView`
- **THEN** `.accessibilityChartDescriptor` SHALL provide a valid `AXChartDescriptor` with labeled axes (`AXNumericDataAxisDescriptor` / `AXCategoricalDataAxisDescriptor`) and `AXDataSeriesDescriptor` points

### Requirement: Generative AI On-Device Privacy and Apple Health Attribution Badges
The coaching and permissions surfaces SHALL display a persistent *"Analyzed on-device"* privacy indicator and explicit **Apple Health** data attribution per `docs/BLUEPRINT.md`, the Generative AI HIG, and the HealthKit HIG.

#### Scenario: Rendering on-device AI and Apple Health attribution on coaching footers
- **WHEN** `AIDisclaimerFooter` and `PermissionsSyncSectionView` are rendered
- **THEN** they SHALL display the on-device Apple Intelligence processing guarantee (*"Analyzed on-device"*) and Apple Health attribution badge

