# Tasks: Watch Running Companion Experience

## 1. RunalystCore: Cadence Baseline Locking & Drift Engine

- [x] 1.1 `[Senior | pro]` Add `currentTargetCadenceSPM: Int?`, `cadenceDriftDebounceDurationSeconds: TimeInterval = 12.0`, and `cadenceDriftCooldownSeconds: TimeInterval = 30.0` to `AdaptivePacingConfiguration` and `AdaptivePacingCore.swift`. Lock cadence baseline during calibration. Verify with `swift test --package-path RunalystCore`.
- [x] 1.2 `[Senior | pro]` Implement `evaluateCadenceDriftAlert()` in `AdaptivePacingCore+Triggers.swift` with continuous 12s debounce, 30s cooldown, and non-destructive emission of `PacingEvent.cadenceDrift`. Verify with `swift test --package-path RunalystCore`.
- [x] 1.3 `[Senior | pro]` Add `case cadenceDrift(currentCadenceSPM: Int, targetCadenceSPM: Int, deltaSPM: Int)` and `case splitMilestone(splitIndex: Int, splitPaceSecondsPerKm: Int)` to `PacingEvent` and map feedback specs in `AdaptivePacingCore+Presentation.swift`. Verify with `swift test --package-path RunalystCore`.
- [x] 1.4 `[Mid/Jnr | flash]` Add unit tests in `AdaptivePacingCoreTests.swift` verifying cadence baseline locking, 12s debounce triggering, and cooldown suppression. Verify with `swift test --package-path RunalystCore`.

## 2. WatchOS Foundry & Display Integration

- [x] 2.1 `[Mid/Jnr | flash]` Update `PacingDisplayState` in `AdaptivePacingCore+Presentation.swift` to expose `filteredCadenceSPM: Int?` and `filteredCadenceFormatted: String`. Update `PacingGaugeView.swift` in `RunalystWatch/Views/` to render live turnover in **Vibrant Green**. Verify with `swift build`.
- [x] 2.2 `[Mid/Jnr | flash]` Update `FeedbackDispatcher.swift` in `RunalystWatch/` to support `.cadenceDrift` (rhythmic `.retry` double-tap) and `.splitMilestone` (`.success` tap with formatted voice announcement). Verify with `swift build`.
- [x] 2.3 `[Mid/Jnr | flash]` Implement kilometer split detection in `TelemetryEngine.swift` (or `WorkoutManager.swift`) emitting `.splitMilestone` events upon crossing split boundaries. Verify with `swift build`.

## 3. Verification & Crucible Assay

- [x] 3.1 `[Mid/Jnr | flash]` Run `./assay.sh` across the workspace ensuring 0 SwiftLint violations, all unit tests passing, and all files adhering to the ~500 LOC modularity guideline.
- [x] 3.2 `[Staff/Lead | parent]` Verify multi-platform build and test suite with `xcodebuild -project Runalyst.xcodeproj -scheme Runalyst -destination "platform=iOS Simulator,name=iPhone 18 Pro" test`.
