# Tasks: Watch Zero-Friction Adaptive Running Companion

## 1. RunalystCore: Intent Profiles, 5-Min Calibration, Two-Step Catch & Debrief

- [x] 1.1 `[Senior | pro]` Add `WatchRunIntent` (`adaptiveBase`, `pushPerformance`, `recovery`) and update `WatchResolvedSessionConfig` (`requiresTargetPacePicker = false` when `!hasPrescribedDrill`) in `RunalystCore/Sources/RunalystCore/WatchTargetPaceOption.swift`. Add `AdaptivePacingConfiguration.forWatchCompanion(intent:)` with 5-minute (300s = 120s warmup + 180s baseline) calibration and 90s refractory cooldown in `RunalystCore/Sources/RunalystCore/AdaptivePacingCore.swift`. Verify with `swift test --package-path RunalystCore`.
- [x] 1.2 `[Senior | pro]` Implement `calibrationStarted` (first tick), `surgeLockedIn` (single tap when surge target enters `.onTarget`), two-step non-destructive `formCheck` (GCT/cadence degradation prior to pace drop) vs `.recover` (cardiac drift dial-back), and run debrief accumulators (`surgeCount`, `peakSurgeDeltaSecondsPerKm`, `recoveryAdjustmentCount`, `firstDriftElapsedSeconds`, `solidCadenceUntilDistanceMeters`, rolling averages) across `RunalystCore/Sources/RunalystCore/AdaptivePacingCore.swift` and `AdaptivePacingCore+Triggers.swift`. Verify with `swift test --package-path RunalystCore`.
- [x] 1.3 `[Senior | pro]` Extend `PacingHapticSemantic` (`.ascendingDoublePulse`, `.threeQuickLightTaps`, `.descendingDoublePulse`, `.subtleConfirmation`), `PacingAccentToken` (`.calibratingBlue`, `.surgeTeal`, `.recoverAmber`), unit-aware `feedbackSpec(useMetricSystem:)`, and pre-computed `PacingDisplayState` properties (`isCalibrating`, `elapsedTimeFormatted`, `paceGaugeNormalizedPosition`, `targetBandLowerNormalized`, `targetBandUpperNormalized`, `biometricStatusToken`, `biometricStatusLabel`) in `RunalystCore/Sources/RunalystCore/AdaptivePacingCore+Presentation.swift`. Verify with `swift test --package-path RunalystCore`.
- [x] 1.4 `[Senior | pro]` Create `RunalystCore/Sources/RunalystCore/WatchRunDebriefCore.swift` implementing `WatchRunDebrief` and `AdaptivePacingCore.buildRunDebrief(elapsedSeconds:totalDistanceMeters:useMetricSystem:)` generating grounded 3-bullet "Coach's Takeaway" strings (`adaptationsBullet`, `efficiencyScoreBullet`, `formInsightBullet`). Verify with `swift test --package-path RunalystCore`.

## 2. Core Unit Tests

- [x] 2.1 `[Mid/Jnr | flash]` Add unit tests in `RunalystCore/Tests/RunalystCoreTests/AdaptivePacingCore+WatchCompanionTests.swift` covering `WatchRunIntent` policies (including `recovery` surge lockout and `pushPerformance` headroom), 5-minute (`300s`) calibration start/lock-in audio scripts, `.surge` -> `.surgeLockedIn` confirmation, two-step `.formCheck` vs `.recover` escalation, and `WatchRunDebrief` 3-bullet outputs in both metric and imperial units. Verify with `swift test --package-path RunalystCore`.

## 3. RunalystWatch Foundry: Audio, Multi-Pulse Haptics, Telemetry & Debrief Capture

- [x] 3.1 `[Mid/Jnr | flash]` Update `RunalystWatch/FeedbackDispatcher.swift` and `RunalystWatch/RunalystWatchApp.swift` so `watchVoiceCuesEnabled` defaults to `true`, `useMetricSystem` parameterizes spoken cues, and multi-pulse watchOS haptics (`.ascendingDoublePulse`, `.threeQuickLightTaps`, `.descendingDoublePulse`, `.subtleConfirmation`) execute cleanly via `WKInterfaceDevice.current()`.
- [x] 3.2 `[Mid/Jnr | flash]` Update `RunalystWatch/TelemetryEngine.swift`, `RunalystWatch/PacingViewModel.swift`, and `RunalystWatch/WorkoutManager.swift` to accept `WatchRunIntent`, configure `AdaptivePacingConfiguration.forWatchCompanion(intent:)`, pass `useMetricSystem`, and expose `completedDebrief: WatchRunDebrief?` on `endWorkout()`.

## 4. RunalystWatch Hollow Views & Xcode Target Wiring

- [x] 4.1 `[Mid/Jnr | flash]` Update `RunalystWatch/Views/StartRunView.swift` to present clean **Outdoor** / **Indoor** toggle + **WatchRunIntent** picker (`Adaptive Base`, `Push / Performance`, `Recovery`) with zero manual pace/interval setup required, keeping optional Prescribed Drill hero card if present.
- [x] 4.2 `[Mid/Jnr | flash]` Update `RunalystWatch/Views/PacingGaugeView.swift` to render calm pulsing **blue edge aura** during Calibration, **steady neutral blue** when locked, **teal/green** glow on Surge/Efficiency, warm **amber** accent on Recovery/Cardiac Drift, central **Dynamic Pace Gauge** track with sweet-spot band & live position marker, large pace & HR + compact cadence, and navigate on End Run to `RunSummaryView(debrief:)`.
- [x] 4.3 `[Mid/Jnr | flash]` Create `RunalystWatch/Views/RunSummaryView.swift` rendering the 3-bullet wrist **Coach's Takeaway** (`Adaptations`, `Efficiency Score`, `Form Insight`) + run summary strip + Done button, add `summary` preview support to `RunalystWatch/RunalystWatchApp.swift`, and register `RunSummaryView.swift` in `Runalyst.xcodeproj/project.pbxproj`.

## 5. Assay, Multi-Platform Build Verification & Visual Check

- [x] 5.1 `[Mid/Jnr | flash]` Run `./assay.sh` ensuring 0 SwiftLint violations, Air-Gap & Reverse Air-Gap compliance, and all Core unit tests passing.
- [x] 5.2 `[Mid/Jnr | flash]` Run `xcodebuild test -project Runalyst.xcodeproj -scheme Runalyst -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:RunalystTests` and `xcodebuild build -project Runalyst.xcodeproj -scheme RunalystWatch -destination "generic/platform=watchOS Simulator"` verifying both iOS and watchOS targets build cleanly without errors or warnings.
- [x] 5.3 `[Scout | flash_lite]` Verify every requirement and scenario in `openspec/changes/watch-zero-friction-companion/specs/watch-zero-friction-companion/spec.md` matches the final implementation line-by-line, and confirm no domain math leaked into `RunalystWatch/Views/`.
