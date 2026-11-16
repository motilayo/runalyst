import ActivityKit
import AppIntents
import CoreFoundation
import Foundation
import RunalystCore
import SwiftUI

// MARK: - Activity Attributes

/// ActivityKit attributes definition driving Lock Screen Live Activities and Dynamic Island presentations.
public struct RunalystTrackActivityAttributes: ActivityAttributes, Sendable {

    /// Dynamic content payload synchronized from active Apple Watch workout telemetry.
    public struct ContentState: Codable, Hashable, Sendable {
        /// Latest serializable snapshot emitted by Apple Watch companion runtime.
        public var snapshot: WatchLiveRunSnapshot
        /// Active display presentation mode (Track -> Metrics -> Chart).
        public var displayMode: LiveActivityDisplayMode
        /// Whether iPhone-to-Watch WCSession reachability is currently operational.
        public var isWatchReachable: Bool

        public init(
            snapshot: WatchLiveRunSnapshot,
            displayMode: LiveActivityDisplayMode = .track,
            isWatchReachable: Bool = true
        ) {
            self.snapshot = snapshot
            self.displayMode = displayMode
            self.isWatchReachable = isWatchReachable
        }

        public static func == (lhs: ContentState, rhs: ContentState) -> Bool {
            lhs.snapshot == rhs.snapshot &&
            lhs.displayMode == rhs.displayMode &&
            lhs.isWatchReachable == rhs.isWatchReachable
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(snapshot.updatedAtEpochSeconds)
            hasher.combine(snapshot.phase.rawValue)
            hasher.combine(snapshot.elapsedTimeFormatted)
            hasher.combine(snapshot.filteredPaceFormatted)
            hasher.combine(snapshot.filteredHeartRateFormatted)
            hasher.combine(snapshot.filteredCadenceFormatted)
            hasher.combine(snapshot.deviationTitle)
            hasher.combine(displayMode.rawValue)
            hasher.combine(isWatchReachable)
        }
    }

    /// Fixed immutable attributes for this workout session.
    public var workoutId: String
    public var athleteIntent: String

    public init(workoutId: String = UUID().uuidString, athleteIntent: String = "Pacing") {
        self.workoutId = workoutId
        self.athleteIntent = athleteIntent
    }
}

// MARK: - Shared Bridge & Storage Constants

/// Cross-target storage constants and Darwin IPC notifications between App Extension and Host App.
public enum RunalystAppGroup {
    public static let suiteName: String = "group.com.runalyzer.Runalyzer"

    public static var userDefaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }
}

public enum RunalystLiveActivityBridge {
    public static let darwinNotificationRemoteCommand: String = "com.runalyzer.Runalyzer.remoteCommandPending"
    public static let displayModeKey: String = "runalyst_live_activity_display_mode"
    public static let pendingCommandKey: String = "pendingWatchRemoteCommand"
    public static let pendingCommandTimestampKey: String = "pendingWatchRemoteCommandTimestamp"

    /// Posts an immediate Darwin notification across sandbox process boundaries.
    public static func postDarwinNotification(_ name: String) {
        let cfName = name as CFString
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(cfName),
            nil,
            nil,
            true
        )
    }
}

// MARK: - Cycle Live Activity View Intent

/// Interactive AppIntent cycling presentation modes (1. Track -> 2. Metrics -> 3. Chart).
public struct CycleLiveActivityViewIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Cycle Live Activity View"
    public static let description = IntentDescription("Cycles presentation across Track, Metrics, and Trajectory Chart.")
    public static let isDiscoverable: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult {
        let storedModeRaw = RunalystAppGroup.userDefaults.string(forKey: RunalystLiveActivityBridge.displayModeKey)
            ?? UserDefaults.standard.string(forKey: RunalystLiveActivityBridge.displayModeKey)
        let currentMode = storedModeRaw.flatMap(LiveActivityDisplayMode.init(rawValue:)) ?? .track
        let nextMode = currentMode.nextMode

        RunalystAppGroup.userDefaults.set(nextMode.rawValue, forKey: RunalystLiveActivityBridge.displayModeKey)
        UserDefaults.standard.set(nextMode.rawValue, forKey: RunalystLiveActivityBridge.displayModeKey)

        for activity in Activity<RunalystTrackActivityAttributes>.activities {
            var updatedState = activity.content.state
            updatedState.displayMode = nextMode
            let updatedContent = ActivityContent(
                state: updatedState,
                staleDate: activity.content.staleDate,
                relevanceScore: activity.content.relevanceScore
            )
            await activity.update(updatedContent)
        }

        NotificationCenter.default.post(
            name: NSNotification.Name("RunalystLiveActivityDisplayModeDidChange"),
            object: nextMode.rawValue
        )

        return .result()
    }
}

// MARK: - Toggle Watch Workout Pause Intent

/// Interactive AppIntent toggling remote Pause / Resume commands to Apple Watch.
public struct ToggleWatchWorkoutPauseIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Toggle Watch Workout Pause"
    public static let description = IntentDescription("Toggles pause or resume for the active watch workout.")
    public static let isDiscoverable: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult {
        var isCurrentlyPaused = false
        if let activity = Activity<RunalystTrackActivityAttributes>.activities.first {
            isCurrentlyPaused = activity.content.state.snapshot.phase == .paused
        }

        let command: WatchRemoteCommand = isCurrentlyPaused ? .resumeWorkout : .pauseWorkout
        RunalystAppGroup.userDefaults.set(command.rawValue, forKey: RunalystLiveActivityBridge.pendingCommandKey)
        RunalystAppGroup.userDefaults.set(Date().timeIntervalSince1970, forKey: RunalystLiveActivityBridge.pendingCommandTimestampKey)
        UserDefaults.standard.set(command.rawValue, forKey: RunalystLiveActivityBridge.pendingCommandKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: RunalystLiveActivityBridge.pendingCommandTimestampKey)

        RunalystLiveActivityBridge.postDarwinNotification(RunalystLiveActivityBridge.darwinNotificationRemoteCommand)
        NotificationCenter.default.post(
            name: NSNotification.Name("RunalystRemoteCommandPendingNotification"),
            object: nil,
            userInfo: ["command": command.rawValue]
        )

        return .result()
    }
}

// MARK: - Shared Color Extension

extension Color {
    /// Canonical biometric color initialized directly from `LiveTrackCore.paletteRGB(for:)`.
    public init(token: PacingAccentToken) {
        let rgb = LiveTrackCore.paletteRGB(for: token)
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}
