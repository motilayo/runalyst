## Context

Runalyst currently renders active Watch workouts in `RunalystWatch/Views/PacingGaugeView.swift` (511 LOC) using a perimeter split-progress bezel (`splitProgressBezel` / `WatchBezelTrackShape`), a linear pace-band bar (`dynamicPaceGauge`), calibration progress (`isCalibrating`), adaptive micro-block pills (`activeBlockBadge`), and workout controls (`controlsRow`), while mirroring telemetry to `Runalyst/Views/WatchLiveCompanionBannerView.swift` (299 LOC) via `WatchLiveRunSnapshot` (`WatchCompanionStateCore.swift`, 343 LOC).

Cross-device audit findings addressed in this design:
- `PacingGaugeView` uses `useMetricSystem` dynamically, whereas `WatchLiveRunSnapshot.from(...)` currently defaults to non-parameterized pace strings; both must honor the runner's unit preference (`km` vs `mi`) while keeping the **400m track** universal.
- `WatchDesignTokens.swift` and `WatchLiveCompanionBannerView.swift` map `PacingAccentToken` differently (`calibratingBlue` and `recoverAmber` are collapsed on iPhone); a single canonical palette must drive Watch, iPhone, iPad, and `RunalystWidgets`.
- `WatchLiveCompanionBannerView.swift` has no `horizontalSizeClass` adaptation for iPad (`BLUEPRINT.md` Section 6).
- There is no `WidgetKit` / `ActivityKit` extension target in `Runalyst.xcodeproj`, and `Runalyst/Info.plist` lacks `NSSupportsLiveActivities`.

Constraints enforced by `CONSTITUTION.md` and `./assay.sh`:
- **Directory Air-Gap**: `RunalystCore/` allows only `Foundation` (no `SwiftUI`, `ActivityKit`, `WidgetKit`, `HealthKit`, `Date()`, or `Calendar.current`).
- **Reverse Air-Gap**: `RunalystWatch/Views/`, `Runalyst/Views/`, `Runalyst/Models/`, and `RunalystWidgets/` MUST contain zero domain thresholds, pace/lap arithmetic, or chart normalization math.

## Goals / Non-Goals

### Goals
- Compute deterministic 400m track lap kinematics, ghost target pacer position, `useMetricSystem` distance/pace parity, calibration guards, rolling 8-minute trajectory normalization, and 400m lap splits inside `RunalystCore/Sources/RunalystCore/LiveTrackCore.swift`.
- Replace `splitProgressBezel` in `RunalystWatch` with a swipeable pager defaulting to View 1 (`WatchTrackView`), with a left-swipe Controls page (`WatchControlsView`: Pause/Resume, End Run, Voice Cues) and Views 1–3 (`WatchTrackView`, `WatchMetricsView` preserving `dynamicPaceGauge`, `WatchTrajectoryChartView`).
- Introduce `RunalystWidgets` (`ActivityKit` + `WidgetKit`) and `LiveActivityManager` supporting Dynamic Island (Compact + Expanded with glowing dot) and the 3-view Lock Screen Live Activity (with runner avatar, ghost dot, `CycleLiveActivityViewIntent` switcher, and `ToggleWatchWorkoutPauseIntent` remote control).
- Upgrade `WatchLiveCompanionBannerView` to enforce identical 3-view parity (`1. Track -> 2. Metrics -> 3. Chart`), using a swipeable pager on iPhone (`.compact`) and a 3-column side-by-side layout on iPad (`.regular`).

### Non-Goals
- Standalone watchOS-only Live Activity initiation (iOS `ActivityKit` requires the paired iPhone app to start/update the Live Activity; watchOS Smart Stack mirrors the iPhone Live Activity automatically).
- GPS map polyline rendering (`MKMapView` / route tiles); the 400m track oval is standardized for indoor and outdoor parity.
- Full-history multi-hour charting in Live Activities (`ActivityKit` 4 KB payload cap requires `<= 24` downsampled points over 480s and `<= 4` recent lap splits).

## Architecture & Exact Data Types

### 1. `RunalystCore` (`LiveTrackCore.swift` + `WatchCompanionStateCore.swift`)

```swift
public enum LiveActivityDisplayMode: String, Sendable, Codable, Equatable, CaseIterable {
    case track
    case metrics
    case chart

    public var nextMode: LiveActivityDisplayMode
    public var title: String
}

public struct BiometricPaletteRGB: Sendable, Codable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double
}

public struct LiveTrackSnapshot: Sendable, Codable, Equatable {
    public let lapNumber: Int                  // 1-indexed (floor(distance / 400) + 1)
    public let lapDistanceMeters: Int          // 0...399
    public let lapProgress: Double             // 0.0..<1.0 along 400m oval
    public let ghostProgress: Double?          // 0.0..<1.0 for targetPaceSecondsPerKm (nil during calibration/no target)
    public let ghostDeltaMeters: Int?          // signed meters ahead (+) or behind (-) target
    public let ghostDeltaLabel: String         // e.g., "+12m ahead", "-8m behind", "On Pacer", or "Calibrating"
    public let lapHeaderLabel: String          // e.g., "Lap 6 • 240/400m"
    public let totalDistanceFormatted: String  // respects useMetricSystem (e.g., "2.24 km" or "1.39 mi")
    public let lapElapsedFormatted: String     // e.g., "1:24"
    public let runnerStrideHz: Double         // cadenceSPM / 60.0 clamped [1.5, 4.0], 0.0 when paused/idle
    public let statusToken: PacingAccentToken
    public let accessibilitySummary: String    // pre-formatted combined VoiceOver label
}

public struct LiveTrajectoryPoint: Sendable, Codable, Equatable {
    public let elapsedSeconds: Int
    public let paceNormalizedY: Double         // 0.0 (slow/bottom) ... 1.0 (fast/top)
    public let hrNormalizedY: Double?          // 0.0 (low/bottom) ... 1.0 (high/top)
}

public struct TrackLapSplit: Sendable, Codable, Equatable {
    public let lapNumber: Int
    public let splitSeconds: Int
    public let splitFormatted: String          // e.g., "2:05"
    public let onTarget: Bool
}

public struct LiveTrajectorySummary: Sendable, Codable, Equatable {
    public let points: [LiveTrajectoryPoint]   // max 24 downsampled points over last 480s
    public let corridorLowerY: Double          // 0.0...1.0 pre-normalized target band floor
    public let corridorUpperY: Double          // 0.0...1.0 pre-normalized target band ceiling
    public let recentLapSplits: [TrackLapSplit]// up to last 4 completed 400m laps
    public let windowLabel: String             // e.g., "Last 8 min"
}
```

Pure helpers in `RunalystCore`:
- `LiveTrackCore.trackOvalPoint(progress: Double) -> (x: Double, y: Double)` in normalized `[0.0, 1.0]` coordinates (start/finish at top-center `progress = 0.0 -> (0.5, 0.08)` moving clockwise).
- `LiveTrackCore.paletteRGB(for token: PacingAccentToken) -> BiometricPaletteRGB` providing the single source of truth for `.electricBlue`, `.surgeBlue`, `.calibratingBlue`, `.surgeTeal`, `.vibrantGreen`, `.recoverAmber`, `.recoverOrange`, `.neonPink`, and `.neutral` across Watch, iPhone, iPad, and `RunalystWidgets`.
- `LiveTrackAccumulator` (`Sendable`, `Equatable`) prunes samples to 480s, tracks `completedLapSplits`, records calibration state cleanly (`ghostProgress = nil` while `displayState.isCalibrating == true`), and emits `LiveTrackSnapshot` + `LiveTrajectorySummary`.

`WatchLiveRunSnapshot` (in `WatchCompanionStateCore.swift`) updates `from(displayState:..., useMetricSystem: Bool = true, trackSnapshot: LiveTrackSnapshot? = nil, trajectorySummary: LiveTrajectorySummary? = nil, ...)` so `filteredPaceFormatted` and `targetPaceFormatted` respect `useMetricSystem`, while keeping `currentSchemaVersion = 1` and optional fields (`= nil` defaults) for seamless V1 `Codable` compatibility.

### 2. Cross-Device Surface Parity Matrix

| Surface | Track Marker | Ghost Dot | Views / Navigation | Controls | Calibration & Blocks |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Apple Watch** (`RunalystWatch`) | Glowing Dot | Yes (post-cal) | Swipe `TabView`: `Controls` (left) \| **`Track` (default)** \| `Metrics` \| `Chart` | `WatchControlsView` (Pause/Resume, End, Voice) | Calibration progress bar on Track; `activeBlockBadge` & `dynamicPaceGauge` on Track/Metrics |
| **Dynamic Island** (`RunalystWidgets`) | Glowing Dot (Expanded) | Yes (Expanded) | Compact: Pace (Blue) + Cadence (Green); Expanded: 3D Track + 3 metrics | Tap opens app | Status dot + state label reflects `calibratingBlue` / `activeBlockBadge` |
| **Lock Screen Live Activity** (`RunalystWidgets`) | Runner Avatar | Yes | 3 Views: `1. Track` -> `2. Metrics` -> `3. Chart` via `CycleLiveActivityViewIntent` | `ToggleWatchWorkoutPauseIntent` button (when Watch reachable) | Calibration bar / `activeBlockBadge` header + `dynamicPaceGauge` on Metrics |
| **iPhone App** (`WatchLiveCompanionBannerView`) | Animated Runner Avatar | Yes | `.compact`: Swipe `TabView` (`Track` \| `Metrics` \| `Chart`) | Remote Pause/Resume/End bar | Calibration progress bar, `activeBlockBadge`, `dynamicPaceGauge` |
| **iPad App** (`WatchLiveCompanionBannerView`) | Animated Runner Avatar | Yes | `.regular`: All 3 views (`Track`, `Metrics`, `Chart`) rendered side-by-side | Remote Pause/Resume/End bar | Calibration progress bar, `activeBlockBadge`, `dynamicPaceGauge` |

### 3. `RunalystWatch` 4-Page Pager (`Controls` + Views 1–3)
- Refactor `PacingGaugeView.swift` into a container hosting a `TabView(selection: $selectedPage)` initialized to `.track` (Page 1), with `.controls` to the left (Apple Watch Workout convention), `.metrics` to the right, and `.chart` after Metrics.
- Remove `splitProgressBezel` from `PacingGaugeView.swift`.
- `WatchMetricsView` keeps `dynamicPaceGauge` (target band slider) and `refractoryCountdownFormatted` alongside the 2x2 monospaced grid so no existing tactical pacing feedback is lost.

### 4. `Runalyst` iOS Foundry & `RunalystWidgets` Extension
- **Shared Core & Palette**: Link `RunalystCore` to both `Runalyst` and `RunalystWidgets`. Add a small SwiftUI `Color(token: PacingAccentToken)` bridge reading `LiveTrackCore.paletteRGB(for:)` used identically in `RunalystWatch`, `Runalyst`, and `RunalystWidgets`.
- **ActivityAttributes & AppIntents**: `RunalystTrackActivityAttributes` + `CycleLiveActivityViewIntent` + `ToggleWatchWorkoutPauseIntent` (routes `.pauseWorkout` / `.resumeWorkout` through `WatchCalibrationBridge.shared.sendRemoteCommand(...)` using shared App Group or active app intent bridge).
- **LiveActivityManager** (`@MainActor` in `Runalyst/Services/LiveActivityManager.swift`): Observes `WatchCalibrationBridge.latestWatchSnapshot`. Starts `Activity.request(...)` on `isActiveWorkout`, coalesces updates (`>= 2.0s` unless `phase`, `lapNumber`, or `displayMode` changes), ends stale activities if `snapshot.isStale(at:)` triggers, and schedules debrief dismissal (`.after(Date().addingTimeInterval(20))`) on `.completed`.

## Decisions & Alternatives

1. **Decision: Dedicated left-swipe `WatchControlsView` page on Watch instead of cramming buttons under the 400m track**
   - *Rationale*: Keeps the 400m 3D track clean and legible at glance speed ("Sweaty Hands" signal-to-noise), matching Apple's native Workout app ergonomics.
   - *Alternative Considered*: Keeping `controlsRow` pinned below `WatchTrackView` on all pages. Rejected because it compresses the 3D track oval on 40mm/41mm Watches.

2. **Decision: Glowing Dot on Watch & Dynamic Island; Runner Avatar on iPhone App & Lock Screen**
   - *Rationale*: Preserves crisp readability at small Watch/Dynamic Island scales while delivering rich cadence-synced character animation on iPhone/iPad.

3. **Decision: Side-by-side 3-column layout on iPad `.regular` size class**
   - *Rationale*: Enforces `BLUEPRINT.md` Section 6 ("iPad is not a giant iPhone") so Track, Metrics, and Trajectory Chart operate as a unified live coaching workstation on large screens.

## Risks / Trade-offs

- **[Risk] `ActivityKit` Lock Screen update throttling prevents 60fps avatar striding** → **Mitigation**: Animate smoothly inside `WatchTrackView` and `WatchLiveCompanionBannerView` (`TimelineView`), while coalescing Lock Screen `Activity.update` calls to `>= 2.0s` or lap/phase changes.
- **[Risk] Lock Screen remote Pause/Resume requires iPhone-to-Watch `WCSession` reachability** → **Mitigation**: Disable or dim the Lock Screen Pause/Resume `AppIntent` control when `isWatchReachable == false`, showing `"Watch Offline"` rather than silently failing.
- **[Risk] `PacingGaugeView.swift` currently at 511 LOC** → **Mitigation**: Extracting `WatchControlsView`, `WatchTrackView`, `WatchMetricsView`, and `WatchTrajectoryChartView` reduces `PacingGaugeView.swift` below 250 LOC.

## Migration Plan

1. Implement `LiveTrackCore.swift` and update `WatchCompanionStateCore.swift` (`useMetricSystem` + optional track/trajectory fields) + Crucible tests.
2. Refactor `RunalystWatch` (`TelemetryEngine`, `WorkoutManager`, `WatchDesignTokens`, `PacingGaugeView` + 4 modular subviews).
3. Add `RunalystWidgets` target, `RunalystTrackActivityAttributes`, `AppIntents`, `LiveActivityManager`, shared `PacingAccentToken` palette, and iPhone/iPad adaptive `WatchLiveCompanionBannerView`.
4. Verify via `./assay.sh` and multi-platform `xcodebuild` builds/tests.
