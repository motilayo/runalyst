## MODIFIED Requirements

### Requirement: Live Watch Workout Mirroring on iPhone
Active Watch workouts and post-run debriefs SHALL be represented by pure `Codable` `WatchLiveRunSnapshot` payloads formatted consistently with `useMetricSystem` and streamed from Watch to iPhone—including optional `trackSnapshot: LiveTrackSnapshot?` and `trajectorySummary: LiveTrajectorySummary?` fields with backward-compatible V1 decoding—and exposed cleanly on `@Observable WatchCalibrationBridge` to drive `WatchLiveCompanionBannerView`, `LiveActivityManager`, and Lock Screen `AppIntent` remote controls.

#### Scenario: Watch publishes unit-aligned phase, 400m track state, and trajectory snapshots to iPhone
- **GIVEN** a workout starts, advances along the 400m track, transitions phases (`.calibrating`, `.running`, `.surge`, `.recover`, `.paused`), or finishes (`.completed`) in `WorkoutManager`
- **WHEN** `WatchContextStore.shared.publishLiveSnapshot(...)` is invoked
- **THEN** `WatchLiveRunSnapshot` formats pace and distance strings using the active `useMetricSystem` preference and attaches `trackSnapshot` on every broadcast plus `trajectorySummary` (`<= 24` points) on periodic/lap updates
- **AND** `WatchContextStore` updates `applicationContext` and transmits interactively via `sendMessage` when reachable (and `transferUserInfo` upon `.completed` with `WatchRunDebrief` attached)
- **AND** iPhone `WatchCalibrationBridge` updates `latestWatchSnapshot`, `latestCompletedDebrief`, and forwards updates to `LiveActivityManager` on `@MainActor`.

#### Scenario: Backward compatibility with V1 snapshots omitting track fields
- **GIVEN** an encoded V1 `WatchLiveRunSnapshot` payload that omits `trackSnapshot` and `trajectorySummary`
- **WHEN** decoded by either `Runalyst`, `RunalystWidgets`, or `RunalystWatch`
- **THEN** decoding succeeds with `trackSnapshot == nil` and `trajectorySummary == nil`, and views gracefully fall back to standard telemetry presentation without crashing.

#### Scenario: Watch finishes run and surfaces debrief on iPhone Dashboard
- **GIVEN** the runner taps End Run on Apple Watch producing a `WatchRunDebrief`
- **WHEN** iPhone receives the `.completed` `WatchLiveRunSnapshot`
- **THEN** `WatchLiveCompanionBannerView` on `DashboardView` displays the 3-bullet "Coach's Takeaway" (`Adaptations`, `Efficiency Score`, `Form Insight`) until dismissed and allows triggering HealthKit sync.
