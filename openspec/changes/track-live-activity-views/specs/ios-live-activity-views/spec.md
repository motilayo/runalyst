## ADDED Requirements

### Requirement: Lock Screen & Dynamic Island Track Live Activities (`RunalystWidgets`)
The iOS app SHALL include a `RunalystWidgets` WidgetKit/ActivityKit extension (`NSSupportsLiveActivities = true` in `Runalyst/Info.plist`) managed by `LiveActivityManager` that starts, updates, handles stale disconnects, and terminates a `RunalystTrackActivityAttributes` Live Activity synchronized from `WatchCalibrationBridge.latestWatchSnapshot` using shared `LiveTrackCore.paletteRGB` colors.

#### Scenario: Live Activity starts automatically when Watch workout becomes active
- **WHEN** `WatchCalibrationBridge.latestWatchSnapshot` transitions to `isActiveWorkout == true` and no `RunalystTrackActivityAttributes` activity is running
- **THEN** `LiveActivityManager` requests a new `Activity<RunalystTrackActivityAttributes>` populated with the latest `WatchLiveRunSnapshot` and default `.track` `LiveActivityDisplayMode`.

#### Scenario: Interactive AppIntents cycle Lock Screen views and execute remote Pause/Resume
- **WHEN** the runner taps `CycleLiveActivityViewIntent` on the Lock Screen Live Activity
- **THEN** `displayMode` cycles `.track -> .metrics -> .chart -> .track` and updates the active Live Activity content immediately without opening the foreground app
- **AND** tapping `ToggleWatchWorkoutPauseIntent` sends `.pauseWorkout` or `.resumeWorkout` via `WatchCalibrationBridge` when Watch is reachable (or displays `"Watch Offline"` when unreachable).

#### Scenario: Dynamic Island uses glowing dot while Lock Screen uses runner avatar
- **WHEN** Dynamic Island renders in Compact or Expanded presentation
- **THEN** Compact Leading shows **Electric Blue** `filteredPaceFormatted` and Compact Trailing shows **Vibrant Green** `filteredCadenceFormatted`
- **AND** Expanded renders the 3D 400m track with the **glowing biometric dot** and ghost pacer dot (plus Pace / Cadence / HR readouts) for crisp legibility at compact scale
- **AND** Lock Screen View 1 renders the 3D 400m track with the **runner avatar**, ghost pacer dot, calibration/block status, and `trackSnapshot.accessibilitySummary`.

#### Scenario: Update throttling, stale disconnect cleanup, and completion dismissal
- **WHEN** incoming `WatchLiveRunSnapshot` updates arrive faster than every `2.0` seconds without a phase, lap, or `displayMode` transition
- **THEN** `LiveActivityManager` coalesces intermediate updates to respect `ActivityKit` budgets
- **AND** ends stale Live Activities cleanly if `snapshot.isStale(at:)` becomes `true`
- **AND** upon `.completed`, displays the debrief summary and schedules dismissal (`dismissalPolicy: .after(...)`).

---

### Requirement: Cross-Device Adaptive Companion Banner (iPhone Swipe vs. iPad 3-Column)
`WatchLiveCompanionBannerView.swift` SHALL render identical 3-view parity (`1. Track` with cadence-synced animated runner avatar + ghost pacer dot, `2. Metrics` with `dynamicPaceGauge`, `3. Rolling Chart`) using shared `LiveTrackCore.paletteRGB` colors and `useMetricSystem` units while adapting proportionally to `horizontalSizeClass` and preserving remote pause/resume/end controls.

#### Scenario: iPhone compact layout presents swipeable 3-page pager with cadence-synced avatar
- **WHEN** `horizontalSizeClass == .compact` and `WatchLiveCompanionBannerView` displays Page 1 (`Track`) with `phase.isActiveWorkout == true`
- **THEN** the runner avatar animates smoothly along `lapProgress` at `runnerStrideHz` when `runnerStrideHz > 0` and halts immediately when `phase == .paused` (`runnerStrideHz == 0.0`)
- **AND** during `isCalibrating == true`, omits the ghost pacer dot and renders the calibration progress bar.

#### Scenario: iPad regular layout displays Track, Metrics, and Chart side-by-side
- **WHEN** `horizontalSizeClass == .regular` (iPad) and an active Watch workout is mirrored
- **THEN** `WatchLiveCompanionBannerView` arranges the 3D 400m Track, Sweaty-Hands Metrics (with `dynamicPaceGauge`), and Rolling Trajectory Chart side-by-side in a multi-column layout rather than hiding Metrics and Chart inside a phone-style swipe pager.
