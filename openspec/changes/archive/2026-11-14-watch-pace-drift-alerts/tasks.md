# Tasks: Watch Real-Time Pace Drift Alerts and Environment Preference Synchronization

## 1. RunalystCore: Real-Time Pace Drift Alert Engine

- [x] 1.1 `[Senior | pro]` Extend `AdaptivePacingConfiguration` with `paceDriftDebounceDurationSeconds` (default 12.0s) and `paceDriftCooldownSeconds` (default 30.0s), and add `case paceDrift(deviation: PaceDeviation, deltaSecondsPerKm: Int)` with its `feedbackSpec` to `PacingEvent` in `RunalystCore/Sources/RunalystCore/AdaptivePacingCore.swift`. Verify with `swift test --package-path RunalystCore`.
- [x] 1.2 `[Senior | pro]` Implement `evaluatePaceDriftAlert()` in `RunalystCore/Sources/RunalystCore/AdaptivePacingCore+Triggers.swift` with continuous deviation accumulation (12s debounce) and refractory cooldown (30s quiet period) during tracking state without mutating `currentTargetPaceSecondsPerKm`. Verify with `swift test --package-path RunalystCore`.
- [x] 1.3 `[Mid/Jnr | flash]` Add comprehensive unit tests in `RunalystCore/Tests/RunalystCoreTests/AdaptivePacingCoreTests.swift` covering 12s debounce threshold, return-to-target reset, and 30s cooldown refractory suppression. Verify with `swift test --package-path RunalystCore`.

## 2. WatchOS Foundry & Preference Synchronization

- [x] 2.1 `[Senior | pro]` Extend `WatchPacingContext` in `RunalystCore/Sources/RunalystCore/WatchTargetPaceOption.swift` with `isIndoorPreferred: Bool?`, and expose `preferredLocation: PacingLocation` in `RunalystWatch/WatchContextStore.swift`. Verify with `swift test --package-path RunalystCore`.
- [x] 2.2 `[Mid/Jnr | flash]` Update `WatchConnectivityManager.swift` in `Runalyst/Managers/` to pass `@AppStorage("preferredWorkoutIsIndoor")` into the application context payload. Verify with `swift build`.
- [x] 2.3 `[Mid/Jnr | flash]` Update `RunalystWatch/FeedbackDispatcher.swift` to handle `.paceDrift` events, playing directional haptic cues (`.directionUp` / `.directionDown`) and grounded voice prompts. Verify with `swift build`.
- [x] 2.4 `[Mid/Jnr | flash]` Update `RunalystWatch/Views/StartRunView.swift` to initialize `selectedLocation` using `WatchContextStore.shared.preferredLocation`. Verify with `swift build`.

## 3. Verification & Crucible Assay

- [x] 3.1 `[Mid/Jnr | flash]` Run `./assay.sh` across the workspace ensuring 0 SwiftLint violations, all unit tests passing, and all files adhering to the ~500 LOC modularity guideline.
- [x] 3.2 `[Staff/Lead | parent]` Review diff for air-gap compliance and verify companion watch simulator build with `xcodebuild -workspace Runalyst.xcworkspace -scheme Runalyst test -destination "platform=iOS Simulator,name=iPhone 16 Pro"`.
