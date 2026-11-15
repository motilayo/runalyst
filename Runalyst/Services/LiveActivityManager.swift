import ActivityKit
import CoreFoundation
import Foundation
import Observation
import RunalystCore
import UIKit
import UserNotifications

/// Manager orchestrating ActivityKit Live Activities and Dynamic Island presentations
/// synchronized from Apple Watch companion run telemetry.
@MainActor
@Observable
final class LiveActivityManager {
    public static let shared = LiveActivityManager()

    public private(set) var activeActivity: Activity<RunalystTrackActivityAttributes>?
    public private(set) var latestSnapshot: WatchLiveRunSnapshot?
    public private(set) var isWatchReachable: Bool = false

    public var currentDisplayMode: LiveActivityDisplayMode {
        get {
            let raw = RunalystAppGroup.userDefaults.string(forKey: RunalystLiveActivityBridge.displayModeKey)
                ?? UserDefaults.standard.string(forKey: RunalystLiveActivityBridge.displayModeKey)
            return raw.flatMap(LiveActivityDisplayMode.init(rawValue:)) ?? .track
        }
        set {
            RunalystAppGroup.userDefaults.set(newValue.rawValue, forKey: RunalystLiveActivityBridge.displayModeKey)
            UserDefaults.standard.set(newValue.rawValue, forKey: RunalystLiveActivityBridge.displayModeKey)
        }
    }

    @ObservationIgnored private var lastUpdateTime: TimeInterval = 0
    @ObservationIgnored private var lastUpdatedPhase: WatchCompanionPhase?
    @ObservationIgnored private var lastUpdatedLapNumber: Int?
    @ObservationIgnored private var lastUpdatedDisplayMode: LiveActivityDisplayMode?
    @ObservationIgnored private var lastUpdatedIsWatchReachable: Bool?
    @ObservationIgnored private var pendingCoalescedTask: Task<Void, Never>?
    @ObservationIgnored private var hasPostedStartNotificationForCurrentRun = false
    private static let startNotificationID = "runalyst.liveActivity.startPrompt"

    private init() {
        self.activeActivity = Activity<RunalystTrackActivityAttributes>.activities.first(where: {
            $0.activityState == .active || $0.activityState == .stale
        })
        registerLocalObservers()
        registerDarwinNotification()
    }

    // MARK: - Observer Registration

    private func registerLocalObservers() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("RunalystLiveActivityDisplayModeDidChange"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let modeRaw = notification.object as? String
            Task { @MainActor [weak self] in
                self?.handleDisplayModeDidChange(modeRaw)
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("RunalystRemoteCommandPendingNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handlePendingRemoteCommand()
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.activeActivity == nil {
                    self.activeActivity = Activity<RunalystTrackActivityAttributes>.activities.first(where: {
                        $0.activityState == .active || $0.activityState == .stale
                    })
                }
                if self.activeActivity == nil,
                   let snapshot = self.latestSnapshot,
                   snapshot.isActiveWorkout && !snapshot.isStale(at: Date().timeIntervalSince1970) {
                    self.startNewLiveActivity(with: snapshot, isWatchReachable: self.isWatchReachable)
                }
            }
        }
    }

    private func registerDarwinNotification() {
        let ptr = Unmanaged.passUnretained(self).toOpaque()
        let notifyCenter = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(
            notifyCenter,
            ptr,
            { _, _, _, _, _ in
                Task { @MainActor in
                    LiveActivityManager.shared.handlePendingRemoteCommand()
                }
            },
            RunalystLiveActivityBridge.darwinNotificationRemoteCommand as CFString,
            nil,
            .deliverImmediately
        )
    }

    // MARK: - Telemetry & Reachability Ingestion

    /// Updates or starts Live Activity based on latest snapshot from Apple Watch.
    func handleSnapshotUpdate(_ snapshot: WatchLiveRunSnapshot?, isWatchReachable: Bool) {
        self.isWatchReachable = isWatchReachable

        guard let snapshot else {
            cleanUpStaleActivity()
            return
        }

        if snapshot.isStale(at: Date().timeIntervalSince1970) {
            cleanUpStaleActivity()
            return
        }

        if snapshot.phase == .completed {
            completeLiveActivity(with: snapshot, isWatchReachable: isWatchReachable)
            return
        }

        guard snapshot.isActiveWorkout else {
            if snapshot.phase == .idle {
                cleanUpStaleActivity()
            }
            return
        }

        self.latestSnapshot = snapshot

        let existing = activeActivity ?? Activity<RunalystTrackActivityAttributes>.activities.first(where: {
            $0.activityState == .active || $0.activityState == .stale
        })

        if let existing {
            self.activeActivity = existing
            evaluateThrottledUpdate(snapshot: snapshot, isWatchReachable: isWatchReachable)
        } else {
            startNewLiveActivity(with: snapshot, isWatchReachable: isWatchReachable)
        }
    }

    /// Handles changes in iPhone-to-Watch WCSession reachability.
    func handleReachabilityUpdate(_ isReachable: Bool) {
        let changed = self.isWatchReachable != isReachable
        self.isWatchReachable = isReachable
        if changed, let snapshot = self.latestSnapshot, snapshot.isActiveWorkout {
            evaluateThrottledUpdate(snapshot: snapshot, isWatchReachable: isReachable, forceImmediate: true)
        }
    }

    // MARK: - Remote Commands & Display Mode Synchronization

    /// Handles display mode toggle notifications from interactive AppIntents.
    func handleDisplayModeDidChange(_ newModeRaw: String? = nil) {
        let modeRaw = newModeRaw
            ?? RunalystAppGroup.userDefaults.string(forKey: RunalystLiveActivityBridge.displayModeKey)
            ?? UserDefaults.standard.string(forKey: RunalystLiveActivityBridge.displayModeKey)
        if let modeRaw, let mode = LiveActivityDisplayMode(rawValue: modeRaw) {
            if self.lastUpdatedDisplayMode != mode {
                self.currentDisplayMode = mode
                if let snapshot = self.latestSnapshot, snapshot.isActiveWorkout {
                    evaluateThrottledUpdate(snapshot: snapshot, isWatchReachable: self.isWatchReachable, forceImmediate: true)
                }
            }
        }
    }

    /// Forwards pending remote commands (Pause/Resume) to Apple Watch via WatchCalibrationBridge when reachable.
    func handlePendingRemoteCommand() {
        let commandRaw = RunalystAppGroup.userDefaults.string(forKey: RunalystLiveActivityBridge.pendingCommandKey)
            ?? UserDefaults.standard.string(forKey: RunalystLiveActivityBridge.pendingCommandKey)
        guard let commandRaw, let command = WatchRemoteCommand(rawValue: commandRaw) else {
            return
        }
        RunalystAppGroup.userDefaults.removeObject(forKey: RunalystLiveActivityBridge.pendingCommandKey)
        UserDefaults.standard.removeObject(forKey: RunalystLiveActivityBridge.pendingCommandKey)

        if WatchCalibrationBridge.shared.isWatchReachable {
            WatchCalibrationBridge.shared.sendRemoteCommand(command)
        }
    }

    // MARK: - Lifecycle Management

    private func startNewLiveActivity(with snapshot: WatchLiveRunSnapshot, isWatchReachable: Bool) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        if UIApplication.shared.applicationState != .active {
            postOneTapStartNotificationIfNeeded(for: snapshot)
            return
        }

        let mode = currentDisplayMode
        let attributes = RunalystTrackActivityAttributes(
            workoutId: UUID().uuidString,
            athleteIntent: snapshot.prescribedDrillTitle ?? snapshot.runIntent.title
        )
        let contentState = RunalystTrackActivityAttributes.ContentState(
            snapshot: snapshot,
            displayMode: mode,
            isWatchReachable: isWatchReachable
        )
        let content = ActivityContent(
            state: contentState,
            staleDate: Date().addingTimeInterval(60)
        )

        do {
            let activity = try Activity<RunalystTrackActivityAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            self.activeActivity = activity
            self.lastUpdateTime = Date().timeIntervalSince1970
            self.lastUpdatedPhase = snapshot.phase
            self.lastUpdatedLapNumber = snapshot.trackSnapshot?.lapNumber
            self.lastUpdatedDisplayMode = mode
            self.lastUpdatedIsWatchReachable = isWatchReachable
            self.hasPostedStartNotificationForCurrentRun = true
            clearStartNotification()
        } catch {
            postOneTapStartNotificationIfNeeded(for: snapshot)
        }
    }

    private func evaluateThrottledUpdate(
        snapshot: WatchLiveRunSnapshot,
        isWatchReachable: Bool,
        forceImmediate: Bool = false
    ) {
        let now = Date().timeIntervalSince1970
        let mode = currentDisplayMode
        let phaseChanged = lastUpdatedPhase != snapshot.phase
        let lapChanged = lastUpdatedLapNumber != snapshot.trackSnapshot?.lapNumber
        let modeChanged = lastUpdatedDisplayMode != mode
        let reachabilityChanged = lastUpdatedIsWatchReachable != isWatchReachable
        let timeSinceLast = now - lastUpdateTime
        let timeExpired = timeSinceLast >= 2.0

        if forceImmediate || phaseChanged || lapChanged || modeChanged || reachabilityChanged || timeExpired {
            pendingCoalescedTask?.cancel()
            pendingCoalescedTask = nil
            pushUpdate(snapshot: snapshot, displayMode: mode, isWatchReachable: isWatchReachable)
        } else {
            scheduleCoalescedUpdate(delay: max(0.0, 2.0 - timeSinceLast))
        }
    }

    private func scheduleCoalescedUpdate(delay: TimeInterval) {
        guard pendingCoalescedTask == nil else { return }
        pendingCoalescedTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            self.pendingCoalescedTask = nil
            if let snapshot = self.latestSnapshot, snapshot.isActiveWorkout {
                self.pushUpdate(
                    snapshot: snapshot,
                    displayMode: self.currentDisplayMode,
                    isWatchReachable: self.isWatchReachable
                )
            }
        }
    }

    private func pushUpdate(
        snapshot: WatchLiveRunSnapshot,
        displayMode: LiveActivityDisplayMode,
        isWatchReachable: Bool
    ) {
        self.lastUpdateTime = Date().timeIntervalSince1970
        self.lastUpdatedPhase = snapshot.phase
        self.lastUpdatedLapNumber = snapshot.trackSnapshot?.lapNumber
        self.lastUpdatedDisplayMode = displayMode
        self.lastUpdatedIsWatchReachable = isWatchReachable

        let contentState = RunalystTrackActivityAttributes.ContentState(
            snapshot: snapshot,
            displayMode: displayMode,
            isWatchReachable: isWatchReachable
        )
        let content = ActivityContent(
            state: contentState,
            staleDate: Date().addingTimeInterval(60)
        )

        Task {
            for activity in Activity<RunalystTrackActivityAttributes>.activities {
                await activity.update(content)
            }
        }
    }

    private func completeLiveActivity(with snapshot: WatchLiveRunSnapshot, isWatchReachable: Bool) {
        pendingCoalescedTask?.cancel()
        pendingCoalescedTask = nil
        self.latestSnapshot = snapshot
        self.hasPostedStartNotificationForCurrentRun = false
        clearStartNotification()

        let mode = currentDisplayMode
        let contentState = RunalystTrackActivityAttributes.ContentState(
            snapshot: snapshot,
            displayMode: mode,
            isWatchReachable: isWatchReachable
        )
        let finalContent = ActivityContent(
            state: contentState,
            staleDate: nil
        )

        Task {
            for activity in Activity<RunalystTrackActivityAttributes>.activities {
                await activity.end(
                    finalContent,
                    dismissalPolicy: .after(Date().addingTimeInterval(20))
                )
            }
            self.activeActivity = nil
        }
    }

    /// Ends stale Live Activities immediately when Watch disconnects or telemetry is outdated.
    func cleanUpStaleActivity() {
        pendingCoalescedTask?.cancel()
        pendingCoalescedTask = nil
        self.latestSnapshot = nil
        self.hasPostedStartNotificationForCurrentRun = false
        clearStartNotification()

        Task {
            for activity in Activity<RunalystTrackActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            self.activeActivity = nil
        }
    }

    // MARK: - Local Notification Fallback

    private func postOneTapStartNotificationIfNeeded(for snapshot: WatchLiveRunSnapshot) {
        guard !hasPostedStartNotificationForCurrentRun else { return }
        hasPostedStartNotificationForCurrentRun = true

        Task {
            let center = UNUserNotificationCenter.current()
            var settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
                settings = await center.notificationSettings()
            }
            guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
                || settings.authorizationStatus == .ephemeral else {
                return
            }

            let content = UNMutableNotificationContent()
            content.title = "Run Started on Apple Watch"
            content.body = "Tap to show live pacing & 400m track on your Lock Screen."
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: Self.startNotificationID,
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }

    private func clearStartNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.startNotificationID])
        center.removeDeliveredNotifications(withIdentifiers: [Self.startNotificationID])
    }
}
