## 1. Reference Core: Pure Live Metronome & Haptic Duty-Cycle Engine (`RunalystCore`)

- [x] 1.1 [Senior | pro] Create `RunalystCore/Sources/RunalystCore/LiveMetronomeCore.swift` implementing `ParsedIntervalPrescription` and `LiveMetronomeCore` (`parsePrescription`, `beatIntervalSeconds`, `shouldTriggerCorrectiveHaptic`, `shouldTriggerDutyCycledHaptic`) with zero Apple UI/audio imports and zero wall-clock time.
- [x] 1.2 [Senior | pro] Create `RunalystCore/Tests/RunalystCoreTests/LiveMetronomeCoreTests.swift` verifying prescription regex parsing, cadence alert bounds (`max(0, targetSPM - 5)...(targetSPM + 5)`), beat interval calculation, corrective drift triggers, and 20-second duty-cycled haptic burst rules.

## 2. Foundry Audio, Haptics & Siri AI App Intents (`Runalyst`)

- [x] 2.1 [Mid/Jnr | flash] Refactor `Runalyst/LiveCoach/LiveCoachEngine.swift` to delegate prescription parsing, beat intervals, and haptic threshold evaluations to `LiveMetronomeCore`, and configure `AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])` in `setupAudioIfNeeded()` per Apple's Playing Audio HIG.
- [x] 2.2 [Mid/Jnr | flash] Create `Runalyst/Intents/RunalystShortcuts.swift` implementing `RunRecordAppEntity` (`AppEntity`, `IndexedEntity` for Spotlight Semantic Index), `CheckReadinessIntent`, `GetPrescribedWorkoutIntent`, `ReportSubjectiveDistressIntent`, `RunalystAppShortcuts` (`AppShortcutsProvider`), and glanceable SwiftUI Siri Snippet Views, and register the file in `Runalyst.xcodeproj/project.pbxproj`.

## 3. Swift Charts Audio Graphs & Generative AI / HealthKit HIG Attribution (`Runalyst/Views`)

- [x] 3.1 [Mid/Jnr | flash] Create `Runalyst/Views/Components/ChartAudioGraphDescriptors.swift` implementing `AXChartDescriptorRepresentable` (`HRWaveAudioGraphDescriptor`, `RunVarianceAudioGraphDescriptor`, `ProgressionAudioGraphDescriptor`), wire `.accessibilityChartDescriptor(...)` into `HeartRateTrajectoryMapView+Chart.swift`, `RunVarianceMapView.swift`, and `ProgressionChartView.swift`, and register the file in `Runalyst.xcodeproj/project.pbxproj`.
- [x] 3.2 [Mid/Jnr | flash] Upgrade `Runalyst/Views/Components/AIDisclaimerFooter.swift` and `Runalyst/Views/PermissionsSyncSectionView.swift` to render the persistent *"Analyzed on-device"* privacy badge and **Apple Health** attribution pill per `docs/BLUEPRINT.md`, the Generative AI HIG, and the HealthKit HIG.

## 4. Verification & Assay Gatekeeper

- [x] 4.1 [Scout | flash_lite] Audit all `### Requirement:` and `#### Scenario:` blocks in `openspec/changes/apple-hig-and-siri-ai-compliance/specs/siri-ai-and-hig-compliance/spec.md` against the implemented files and line numbers.
- [x] 4.2 [Staff/Lead | parent] Execute `./assay.sh` and `xcodebuild test` on the iOS Simulator, archive the OpenSpec change, and open a Pull Request.
