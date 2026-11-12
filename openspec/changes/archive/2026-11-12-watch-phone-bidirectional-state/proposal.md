# Proposal: Bidirectional Watch-Phone Companion State Awareness

## Why

Currently, communication between `Runalyst` (iPhone) and `RunalystWatch` (Apple Watch) is nearly one-way and disconnected:
1. iPhone pushes calibration context sporadically (`publishContext` / `sendPacingContext(isIndoorPreferred:)`), without syncing unit system (`useMetricSystem`) or voice feedback settings (`watchVoiceCuesEnabled`), and Watch never requests fresh context on launch.
2. When you start, pause, resume, surge, or finish a run on Apple Watch, the iPhone app has zero visibility into active Watch state, live pacing telemetry, or the completed 3-bullet "Coach's Takeaway" debrief, and cannot remotely pause, resume, or end the Watch workout.

## What Changes

- **`RunalystCore/` (Sans-I/O Core)**:
  - `WatchTargetPaceOption.swift`: Extend `WatchPacingContext` with backward-compatible `useMetricSystem: Bool?` and `watchVoiceCuesEnabled: Bool?`.
  - `WatchCompanionStateCore.swift` (NEW): Define `WatchCompanionPhase`, `WatchLiveRunSnapshot` (lightweight `Codable` live telemetry + UI labels/tokens), and `WatchRemoteCommand` (`.pauseWorkout`, `.resumeWorkout`, `.endWorkout`, `.toggleVoiceCues`, `.requestContextSync`), plus `PacingDisplayState.makeLiveSnapshot(...)` factory.
- **`RunalystWatch/` (Foundry)**:
  - `WatchContextStore.swift`: Convert to `@MainActor @Observable`, sync `useMetricSystem` & `watchVoiceCuesEnabled` into `UserDefaults.standard`, pull latest context from iPhone on launch/appear (`requestContextSync`), publish throttled/event-driven `WatchLiveRunSnapshot` updates to iPhone (via `updateApplicationContext`, `sendMessage`, and `transferUserInfo` for completed debriefs), and handle incoming `WatchRemoteCommand` messages.
  - `WorkoutManager.swift` & `Views/StartRunView.swift` / `Views/PacingGaugeView.swift`: Stream live workout state changes back through `WatchContextStore` and request fresh context on `StartRunView.onAppear`.
- **`Runalyst/` (iOS Bridge & Hollow Banner)**:
  - `WatchCalibrationBridge.swift`: Become `@MainActor @Observable` tracking `isWatchPaired`, `isWatchAppInstalled`, `isWatchReachable`, `latestWatchSnapshot`, and `latestCompletedDebrief`; sync `useMetricSystem` & `watchVoiceCuesEnabled` on every context publish; implement full `WCSessionDelegate` receive handlers (`didReceiveApplicationContext`, `didReceiveUserInfo`, `didReceiveMessage`); add `sendRemoteCommand(_:)` and `dismissCompletedDebrief()`.
  - `SettingsView.swift`: Sync `useMetricSystem` changes immediately to Watch via `WatchCalibrationBridge.shared.sendPacingContext(...)`.
  - `WatchLiveCompanionBannerView.swift` (NEW Hollow View) & `DashboardView.swift`: Surface a live mirrored Watch run card on Dashboard (status badge, dynamic pace gauge, Pace/HR/Cadence/Target, Pause/Resume/End buttons) and a post-run Coach's Takeaway debrief card when a Watch run finishes.

## Impact & Air-Gap Assessment

- **Air-Gap Compliance**: Zero Apple frameworks (`WatchConnectivity`, `SwiftUI`, `HealthKit`, `SwiftData`) or wall-clock `Date()` calls inside `RunalystCore/`.
- **Reverse Air-Gap Compliance**: `WatchLiveCompanionBannerView` binds strictly to `WatchLiveRunSnapshot` and `WatchRunDebrief` with zero inline domain math.
- **Modularity**: Each new or modified file stays cleanly concise (`<= 500 LOC`).
