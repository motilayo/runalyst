## Why

Currently, active Watch runs render a screen-edge split-progress bezel (`splitProgressBezel` / `WatchBezelTrackShape`) and linear gauge in `PacingGaugeView.swift` (511 LOC), while iOS lacks native Lock Screen and Dynamic Island `ActivityKit` Live Activities and `WatchLiveCompanionBannerView.swift` lacks `horizontalSizeClass` iPad adaptation and unit-consistent snapshot formatting. Replacing the screen-perimeter bezel with a 3D-tilted 400-meter track visualization and unifying live telemetry into a consistent 3-view architecture (Track, Metrics, Trajectory Chart) across Apple Watch, iPhone, Lock Screen, Dynamic Island, and iPad gives runners instant spatial pacing intuition everywhere.

## What Changes

* **Pure Track, Unit Parity & Trajectory Math (`RunalystCore` — Sans-I/O Core)**:
  * Introduce `LiveTrackCore` (`LiveTrackSnapshot`, `LiveTrajectoryPoint`, `TrackLapSplit`, `LiveTrajectorySummary`, `LiveActivityDisplayMode`, `BiometricPaletteRGB`, and pure `LiveTrackCalculator`) computing 400m lap number, lap distance (`0..<400m`), normalized track progress (`0.0..<1.0`), ghost target pacer progress, lead/lag delta in meters, cadence-driven runner stride phase (`0.0` when paused), parametric `trackOvalPoint(progress:)`, and an 8-minute downsampled rolling trajectory buffer plus 400m lap split history.
  * Extend `WatchLiveRunSnapshot` in `WatchCompanionStateCore.swift` with `useMetricSystem`-aware pace/distance formatting and optional `trackSnapshot: LiveTrackSnapshot?` + `trajectorySummary: LiveTrajectorySummary?` (backward-compatible V1 `Codable` decoding).
* **4-Page Watch Workout Pager (`RunalystWatch` — Hollow Views & Telemetry)**:
  * Refactor `PacingGaugeView.swift` to remove `splitProgressBezel` and host a swipeable `TabView` defaulted to the Track page, with a left-swipe Controls page (`WatchControlsView`: Pause/Resume, End Run confirmation, Voice Cues toggle) and the 3 telemetry views:
    1. `WatchTrackView`: Perspective-tilted 3D 400m oval with glowing biometric-status dot, ghost pacer dot (omitted cleanly during `isCalibrating` baseline mode), `activeBlockBadge` / calibration progress bar, and VoiceOver track summary.
    2. `WatchMetricsView`: High-contrast "Sweaty Hands" 2x2 monospaced grid (Electric Blue Pace, Vibrant Green Cadence, Neon Pink Heart Rate, Lap/Elapsed) plus `dynamicPaceGauge` sweet-spot band indicator and `refractoryCountdownFormatted`.
    3. `WatchTrajectoryChartView`: Compact rolling 8-minute pace-vs-target-corridor and heart-rate drift sparkline with recent 400m lap split chips.
  * Update `TelemetryEngine.swift` and `WorkoutManager.swift` to feed cumulative distance and periodic trajectory samples into `LiveTrackCalculator` using synced `useMetricSystem`.
* **iOS Live Activities, Lock Screen Actions & Cross-Device Parity (`Runalyst` Foundry + `RunalystWidgets` Extension)**:
  * Add a `RunalystWidgets` WidgetKit / ActivityKit extension target linked to `RunalystCore` and set `NSSupportsLiveActivities = true` in `Runalyst/Info.plist`.
  * Define `RunalystTrackActivityAttributes`, `CycleLiveActivityViewIntent` (Track -> Metrics -> Chart), and `ToggleWatchWorkoutPauseIntent` / remote command `AppIntent` controls + `LiveActivityManager` synced from `WatchCalibrationBridge.latestWatchSnapshot` (with staleness cleanup).
  * Enforce marker & layout consistency: **Watch** and **Dynamic Island** render the glowing **dot**, **iPhone App** and **Lock Screen Live Activity** render the **runner avatar** (both with the **ghost pacer dot**), shared `PacingAccentToken` colors match across all targets, and `WatchLiveCompanionBannerView.swift` adapts to iPad (`horizontalSizeClass == .regular`) by displaying Track, Metrics, and Chart side-by-side.

## Capabilities

### New Capabilities
- `live-track-kinematics`: Pure `RunalystCore` 400m stadium track progress, ghost target pacer math, calibration guards, cadence-linked stride phase, `useMetricSystem` formatting parity, shared biometric palette values, rolling 8-minute trajectory sampling, and 400m lap split accumulation.
- `watch-3d-track-pager`: Swipeable Apple Watch workout pager (`WatchControlsView` + 3D 400m `WatchTrackView` with glowing dot, `WatchMetricsView` with `dynamicPaceGauge`, and `WatchTrajectoryChartView`) replacing `splitProgressBezel`.
- `ios-live-activity-views`: `ActivityKit` Lock Screen and Dynamic Island Live Activities (`RunalystWidgets`) with `AppIntent` view switching + remote Pause/Resume, plus adaptive iPhone (3-page swipe) and iPad (`.regular` 3-column) companion views with animated runner avatar.

### Modified Capabilities
- `watch-phone-bidirectional-state`: Extend `WatchLiveRunSnapshot` streamed from Apple Watch to iPhone with `useMetricSystem`-aligned formatting, optional 400m track state, compact rolling trajectory samples, and Lock Screen `AppIntent` remote command routing.

## Impact & Air-Gap Assessment

* **RunalystCore (`RunalystCore/Sources/RunalystCore/`)**: New `LiveTrackCore.swift` (<= 500 LOC) and additive optional fields / `useMetricSystem` support on `WatchCompanionStateCore.swift` (currently 343 LOC). Zero Apple infrastructure imports (`HealthKit`, `SwiftData`, `SwiftUI`, `ActivityKit`, `WidgetKit`) and zero `Date()` / `Calendar.current` calls.
* **Runalyst Foundry & Widget Extension (`Runalyst/`, `RunalystWidgets/`, `Runalyst.xcodeproj`)**: `LiveActivityManager`, `RunalystTrackActivityAttributes`, `AppIntents`, shared `PacingAccentToken` color helper, `WatchCalibrationBridge` hook, and `WatchLiveCompanionBannerView.swift` (currently 299 LOC, kept <= 500 LOC via focused subviews). Zero inline domain thresholds or normalization math outside `RunalystCore`.
* **RunalystWatch (`RunalystWatch/`)**: Splits `PacingGaugeView.swift` (currently 511 LOC) into modular hollow subviews (`WatchControlsView`, `WatchTrackView`, `WatchMetricsView`, `WatchTrajectoryChartView`), bringing every touched file well below 500 LOC.
* **Verification**: Verified via `./assay.sh` (Air-Gap, Determinism, Reverse Air-Gap, SwiftLint `--strict`, <= 500 LOC mass check, Grounded Voice, and `swift test --package-path RunalystCore`) plus multi-destination `xcodebuild` builds/tests for `Runalyst`, `RunalystWidgets`, and `RunalystWatch`.
