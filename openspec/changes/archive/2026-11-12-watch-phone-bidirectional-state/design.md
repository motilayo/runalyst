# Design: Bidirectional Watch-Phone Companion State Awareness

## 1. RunalystCore Contracts

### 1.1 `WatchPacingContext` Extensions (`WatchTargetPaceOption.swift`)
Add backward-compatible optional fields to `WatchPacingContext`:
- `public let useMetricSystem: Bool?`
- `public let watchVoiceCuesEnabled: Bool?`
Keep initializer default arguments `useMetricSystem: Bool? = nil, watchVoiceCuesEnabled: Bool? = nil` so all existing call sites and tests compile untouched.

### 1.2 `WatchCompanionStateCore.swift` (NEW Pure Core File)
```swift
public enum WatchCompanionPhase: String, Sendable, Codable, Equatable {
    case idle, calibrating, running, surge, recover, paused, completed

    public var isActiveWorkout: Bool {
        switch self {
        case .calibrating, .running, .surge, .recover, .paused: return true
        case .idle, .completed: return false
        }
    }
}

public enum WatchRemoteCommand: String, Sendable, Codable, Equatable {
    case pauseWorkout, resumeWorkout, endWorkout, toggleVoiceCues, requestContextSync
}

public struct WatchLiveRunSnapshot: Sendable, Codable, Equatable {
    public static let currentSchemaVersion: Int = 1
    public let schemaVersion: Int
    public let phase: WatchCompanionPhase
    public let location: PacingLocation
    public let runIntent: WatchRunIntent
    public let prescribedDrillTitle: String?
    public let stateTitle: String
    public let biometricStatusLabel: String
    public let biometricStatusToken: PacingAccentToken
    public let filteredPaceFormatted: String
    public let targetPaceFormatted: String
    public let filteredHeartRateFormatted: String
    public let filteredCadenceFormatted: String
    public let elapsedTimeFormatted: String
    public let deviationTitle: String
    public let paceGaugeNormalizedPosition: Double
    public let targetBandLowerNormalized: Double
    public let targetBandUpperNormalized: Double
    public let calibrationProgress: Double?
    public let completedDebrief: WatchRunDebrief?
    public let updatedAtEpochSeconds: TimeInterval

    // Pre-computed hollow UI helpers:
    public var isActiveWorkout: Bool { phase.isActiveWorkout }
    public var headerTitle: String { ... }
    public var intentAndLocationSubtitle: String { ... }
}
```
Also provide static factory helper on `WatchLiveRunSnapshot.from(displayState:location:runIntent:prescribedDrillTitle:isPaused:isCompleted:completedDebrief:updatedAtEpochSeconds:)`.

## 2. WatchOS Side (`RunalystWatch/`)
- **`WatchContextStore.swift`** (`@MainActor @Observable`):
  - Applies synced `context.useMetricSystem` & `context.watchVoiceCuesEnabled` to `UserDefaults.standard`.
  - Adds `requestLatestContextIfNeeded()` sending `["remoteCommand": WatchRemoteCommand.requestContextSync.rawValue]`.
  - Adds `publishLiveSnapshot(_ snapshot: WatchLiveRunSnapshot, forceImmediate: Bool = false)`:
    - Encodes JSON (`watchLiveSnapshot`), updates `applicationContext["watchLiveSnapshot"]` cleanly (preserving any prior keys isn't needed since Watch->Phone `applicationContext` is dedicated to Watch state!), throttled to >= 2.0s unless `forceImmediate == true` (phase transitions, pause, resume, complete).
    - If `WCSession.default.isReachable`: also sends `["watchLiveSnapshot": data]` via `sendMessage`.
    - When `snapshot.phase == .completed`: ALSO calls `WCSession.default.transferUserInfo(["watchLiveSnapshot": data])` for guaranteed offline/pocket delivery!
  - Implements `session(_:didReceiveMessage:)` & `session(_:didReceiveMessage:replyHandler:)` handling both `"pacingContext"` data AND `"remoteCommand"` strings (`WorkoutManager.shared.handleRemoteCommand(...)`).
- **`WorkoutManager.swift` & Views**:
  - Track `activeLocation`, `activeIntent`, `activePrescribedTitle`, push live snapshots on start, paused/resumed, tick updates (passing `snapshot` to `WatchContextStore.shared`), and completion (`completedDebrief`).
  - `StartRunView.onAppear` calls `WatchContextStore.shared.requestLatestContextIfNeeded()`.
  - `PacingGaugeView` voice button syncs updated `watchVoiceCuesEnabled` back if toggled.

## 3. iOS Side (`Runalyst/`)
- **`WatchCalibrationBridge.swift`** (`@MainActor @Observable`):
  - Exposes `isWatchPaired`, `isWatchAppInstalled`, `isWatchReachable`, `latestWatchSnapshot`, `latestCompletedDebrief`.
  - Includes `useMetricSystem` and `watchVoiceCuesEnabled` read from `UserDefaults.standard` in every `WatchPacingContext` published.
  - Receives `"watchLiveSnapshot"` via `didReceiveApplicationContext`, `didReceiveUserInfo`, and `didReceiveMessage`, updating `latestWatchSnapshot` and `latestCompletedDebrief` (ignoring stale timestamps older than current `updatedAtEpochSeconds`).
  - Handles `"remoteCommand": "requestContextSync"` inside `didReceiveMessage` by calling `sendPacingContext()` / replying with latest encoded `"pacingContext"`!
  - Exposes `sendRemoteCommand(_ command: WatchRemoteCommand)` and `dismissCompletedDebrief()`.
- **`SettingsView.swift`**:
  - `.onChange(of: useMetricSystem)` calls `WatchCalibrationBridge.shared.sendPacingContext(...)`.
- **`WatchLiveCompanionBannerView.swift` & `DashboardView.swift`**:
  - Hollow banner card rendered cleanly inside `DashboardView` above main metrics whenever `watchBridge.latestWatchSnapshot?.isActiveWorkout == true` (live metrics, mini Dynamic Pace Gauge, Pause/Resume/End buttons) OR when `watchBridge.latestCompletedDebrief != nil` (Coach's Takeaway 3-bullet card + Dismiss / Sync button).
