# Tasks: Bidirectional Watch-Phone Companion State Awareness

## 1. RunalystCore: Shared Bidirectional State Contracts

- [x] 1.1 `[Senior | pro]` Extend `WatchPacingContext` in `RunalystCore/Sources/RunalystCore/WatchTargetPaceOption.swift` with optional `useMetricSystem: Bool? = nil` and `watchVoiceCuesEnabled: Bool? = nil`. Create `RunalystCore/Sources/RunalystCore/WatchCompanionStateCore.swift` defining `WatchCompanionPhase`, `WatchRemoteCommand`, and `WatchLiveRunSnapshot` (including `WatchLiveRunSnapshot.from(...)` and pre-computed display helpers). Verify with `swift test --package-path RunalystCore`.

## 2. Core Unit Tests

- [x] 2.1 `[Mid/Jnr | flash]` Add unit tests in `RunalystCore/Tests/RunalystCoreTests/WatchCompanionStateTests.swift` verifying `WatchPacingContext` JSON backward compatibility + unit/voice preference fields, `WatchLiveRunSnapshot.from(...)` across all phases (`.calibrating`, `.running`, `.surge`, `.recover`, `.paused`, `.completed`), `Codable` round-trips, and pre-computed header/subtitle strings. Verify with `swift test --package-path RunalystCore`.

## 3. WatchOS Side: Preference Application, Live Snapshot Streaming & Remote Commands

- [x] 3.1 `[Mid/Jnr | flash]` Update `RunalystWatch/WatchContextStore.swift`, `RunalystWatch/WorkoutManager.swift`, `RunalystWatch/Views/StartRunView.swift`, and `RunalystWatch/Views/PacingGaugeView.swift` to: (a) apply `useMetricSystem` & `watchVoiceCuesEnabled` from received `WatchPacingContext` into `UserDefaults.standard`; (b) request fresh context on `StartRunView.onAppear` & session activation; (c) stream `WatchLiveRunSnapshot` via `WatchContextStore.shared.publishLiveSnapshot(...)` across start, ticks, pause, resume, and end (with `transferUserInfo` + debrief on completion); (d) handle incoming `WatchRemoteCommand` messages on `WorkoutManager.shared`.

## 4. iOS Side: Observable Companion Bridge, Settings Sync & Hollow Dashboard Card

- [x] 4.1 `[Mid/Jnr | flash]` Update `Runalyst/Services/WatchCalibrationBridge.swift` and `Runalyst/Views/SettingsView.swift` to: (a) make `WatchCalibrationBridge` `@Observable` exposing `isWatchPaired`, `isWatchAppInstalled`, `isWatchReachable`, `latestWatchSnapshot`, and `latestCompletedDebrief`; (b) attach `useMetricSystem` & `watchVoiceCuesEnabled` when building `WatchPacingContext` and trigger `sendPacingContext()` on `useMetricSystem` changes; (c) handle incoming `watchLiveSnapshot` (via `didReceiveApplicationContext`, `didReceiveUserInfo`, `didReceiveMessage`) and `requestContextSync`; (d) implement `sendRemoteCommand(_:)` and `dismissCompletedDebrief()`.
- [x] 4.2 `[Mid/Jnr | flash]` Create `Runalyst/Views/WatchLiveCompanionBannerView.swift` (hollow renderer over `WatchLiveRunSnapshot` and `WatchRunDebrief` with active live gauge + Pause/Resume/End buttons and post-run Coach's Takeaway debrief card), register it in `Runalyst.xcodeproj/project.pbxproj` (`WCB10005`/`WCB10006`), and wire it cleanly into `Runalyst/Views/DashboardView.swift`.

## 5. Verification

- [x] 5.1 `[Mid/Jnr | flash]` Run `./assay.sh`, `xcodebuild build -project Runalyst.xcodeproj -scheme RunalystWatch -destination "platform=watchOS Simulator,name=Apple Watch Series 12 (46mm)"`, and `xcodebuild test -project Runalyst.xcodeproj -scheme Runalyst -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:RunalystTests`.
