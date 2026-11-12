# watch-phone-bidirectional-state Specification

## Purpose
TBD - created by archiving change watch-phone-bidirectional-state. Update Purpose after archive.
## Requirements
### Requirement: Preference Synchronization (Phone <-> Watch)
`WatchPacingContext` SHALL synchronize `useMetricSystem` and `watchVoiceCuesEnabled` alongside `isIndoorPreferred`, `profile`, and `intent` from iPhone to Apple Watch, and Watch SHALL pull fresh context on start screen appearance.

#### Scenario: Unit preference change syncs immediately to Watch
- **GIVEN** the runner toggles `Unit System` (`useMetricSystem`) in iOS `SettingsView`
- **WHEN** `WatchCalibrationBridge.shared.sendPacingContext(...)` runs
- **THEN** the encoded `WatchPacingContext` carries the updated `useMetricSystem` flag
- **AND** `WatchContextStore` persists `useMetricSystem` to Watch `UserDefaults.standard` upon receipt in `didReceiveApplicationContext` or `didReceiveMessage`.

#### Scenario: Watch pulls latest context on StartRunView appear
- **GIVEN** `WCSession.default.isReachable` is `true` when `StartRunView` appears
- **WHEN** `WatchContextStore.shared.requestLatestContextIfNeeded()` executes
- **THEN** Watch sends `WatchRemoteCommand.requestContextSync` to iPhone
- **AND** iPhone responds/pushes the current `WatchPacingContext`.

---

### Requirement: Live Watch Workout Mirroring on iPhone
Active Watch workouts and post-run debriefs SHALL be represented by pure `Codable` `WatchLiveRunSnapshot` payloads streamed from Watch to iPhone and exposed cleanly on `@Observable WatchCalibrationBridge`.

#### Scenario: Watch publishes phase and metric snapshots to iPhone
- **GIVEN** a workout starts, transitions phases (`.calibrating`, `.running`, `.surge`, `.recover`, `.paused`), or finishes (`.completed`) in `WorkoutManager`
- **WHEN** `WatchContextStore.shared.publishLiveSnapshot(...)` is invoked
- **THEN** `WatchContextStore` updates `applicationContext` and transmits interactively via `sendMessage` when reachable (and `transferUserInfo` upon `.completed` with `WatchRunDebrief` attached)
- **AND** iPhone `WatchCalibrationBridge` updates `latestWatchSnapshot` and `latestCompletedDebrief` reactively on `@MainActor`.

#### Scenario: Watch finishes run and surfaces debrief on iPhone Dashboard
- **GIVEN** the runner taps End Run on Apple Watch producing a `WatchRunDebrief`
- **WHEN** iPhone receives the `.completed` `WatchLiveRunSnapshot`
- **THEN** `WatchLiveCompanionBannerView` on `DashboardView` displays the 3-bullet "Coach's Takeaway" (`Adaptations`, `Efficiency Score`, `Form Insight`) until dismissed and allows triggering HealthKit sync.

---

### Requirement: Remote Companion Controls (Phone -> Watch)
During an active mirrored Watch workout, the runner SHALL be able to pause, resume, or end the Watch workout directly from `WatchLiveCompanionBannerView` on iPhone.

#### Scenario: iPhone remote pause/resume/end executes on Watch
- **GIVEN** `WatchCalibrationBridge.shared.isWatchReachable` is `true` and `latestWatchSnapshot?.isActiveWorkout == true`
- **WHEN** `sendRemoteCommand(.pauseWorkout | .resumeWorkout | .endWorkout)` is triggered on iPhone
- **THEN** `WatchContextStore` receives the command via `WCSession` and executes `pauseWorkout()`, `resumeWorkout()`, or `endWorkout()` on `WorkoutManager.shared`.

