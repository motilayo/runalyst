import Foundation
import HealthKit
import Observation
import RunalystCore
import WatchConnectivity

/// Hollow adapter bridging athlete calibration profiles and training intents to Apple Watch via WatchConnectivity.
///
/// Strictly obeys the Hollow Foundry doctrine: performs zero physiological math or threshold comparisons.
/// All calibration and intent derivation is performed exclusively by `RunalystCore`.
typealias WatchConnectivityManager = WatchCalibrationBridge

@MainActor
@Observable
final class WatchCalibrationBridge: NSObject, WCSessionDelegate {
    static let shared = WatchCalibrationBridge()

    public private(set) var isWatchPaired: Bool = false
    public private(set) var isWatchAppInstalled: Bool = false
    public private(set) var isWatchReachable: Bool = false
    public private(set) var latestWatchSnapshot: WatchLiveRunSnapshot?
    public private(set) var latestCompletedDebrief: WatchRunDebrief?

    @ObservationIgnored private var pendingContext: WatchPacingContext?
    @ObservationIgnored public private(set) var lastPublishedContext: WatchPacingContext?
    @ObservationIgnored private var snapshotStalenessTask: Task<Void, Never>?

    override private init() {
        super.init()
        activateSession()
    }

    private func activateSession() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        refreshSessionState(session)
    }

    private func refreshSessionState(_ session: WCSession) {
        guard WCSession.isSupported() else { return }
        self.isWatchPaired = session.isPaired
        self.isWatchAppInstalled = session.isWatchAppInstalled
        self.isWatchReachable = session.isReachable
    }

    private var defaultMetricPreference: Bool {
        UserDefaults.standard.object(forKey: "useMetricSystem") as? Bool ?? (Locale.current.measurementSystem == .metric)
    }

    private var defaultVoiceCuesPreference: Bool {
        UserDefaults.standard.object(forKey: "watchVoiceCuesEnabled") as? Bool ?? true
    }

    // MARK: - Publishing API

    /// Publishes a pre-built `WatchPacingContext` to the paired Apple Watch.
    func publish(context: WatchPacingContext) {
        let resolvedContext: WatchPacingContext
        if context.useMetricSystem == nil || context.watchVoiceCuesEnabled == nil {
            resolvedContext = WatchPacingContext(
                schemaVersion: context.schemaVersion,
                profile: context.profile,
                intent: context.intent,
                isIndoorPreferred: context.isIndoorPreferred,
                useMetricSystem: context.useMetricSystem ?? defaultMetricPreference,
                watchVoiceCuesEnabled: context.watchVoiceCuesEnabled ?? defaultVoiceCuesPreference
            )
        } else {
            resolvedContext = context
        }

        let previousContext = self.lastPublishedContext
        self.lastPublishedContext = resolvedContext

        guard WCSession.isSupported() else { return }
        let session = WCSession.default

        refreshSessionState(session)

        guard session.activationState == .activated else {
            self.pendingContext = resolvedContext
            if session.activationState == .notActivated {
                session.activate()
            }
            return
        }

        // Silent exit if watch is not paired or watch app not installed
        guard session.isPaired, session.isWatchAppInstalled else { return }

        // Skip redundant transfers if unchanged, unless watch is reachable
        if let last = previousContext, last == resolvedContext, !isWatchReachable {
            return
        }

        do {
            let data = try JSONEncoder().encode(resolvedContext)
            try session.updateApplicationContext(["pacingContext": data])
            if isWatchReachable {
                session.sendMessage(["pacingContext": data], replyHandler: nil, errorHandler: nil)
            }
            self.pendingContext = nil
        } catch {
            // Silently handle transport failure with zero user disruption
        }
    }

    /// Sends updated pacing context to Apple Watch, ensuring `isIndoorPreferred`, `useMetricSystem`, and `watchVoiceCuesEnabled` are synchronized immediately.
    func sendPacingContext(isIndoorPreferred: Bool? = nil) {
        let indoorPref = isIndoorPreferred ?? UserDefaults.standard.bool(forKey: "preferredWorkoutIsIndoor")
        let metricPref = defaultMetricPreference
        let voicePref = defaultVoiceCuesPreference

        if let current = lastPublishedContext {
            let updated = WatchPacingContext(
                schemaVersion: current.schemaVersion,
                profile: current.profile,
                intent: current.intent,
                isIndoorPreferred: indoorPref,
                useMetricSystem: metricPref,
                watchVoiceCuesEnabled: voicePref
            )
            publish(context: updated)
        } else {
            let profile = AthleteCalibrationProfile(maxHR: 190.0, isFallback: true)
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = Locale(identifier: "en_US_POSIX")
            let dayString = AthleteCalibrationCore.formatDayString(date: Date(), calendar: calendar)
            let intent = PacingSessionIntent(
                intent: .steady,
                validForDay: dayString
            )
            let context = WatchPacingContext(
                schemaVersion: WatchPacingContext.currentSchemaVersion,
                profile: profile,
                intent: intent,
                isIndoorPreferred: indoorPref,
                useMetricSystem: metricPref,
                watchVoiceCuesEnabled: voicePref
            )
            publish(context: context)
        }
    }

    /// Derives athlete calibration profile and session intent via `AthleteCalibrationCore` and publishes to Apple Watch.
    func publishContext(
        runs: [RunRecord],
        restingHRSamples: [Double] = [],
        age: Int? = nil,
        spec: PlannedSessionSpec? = nil,
        subjectiveDistress: Bool = false,
        now: Date = Date(),
        targetPaceSecondsPerKm: Int? = nil,
        isIndoorPreferred: Bool? = nil
    ) {
        let buckets = runs.map { run in
            TelemetryBucket(
                timestamp: run.date,
                durationSeconds: run.duration,
                distanceMeters: run.totalDistanceMeters,
                paceSecondsPerKm: run.workingAvgPace > 0 ? run.workingAvgPace : run.rawAvgPace,
                cadenceSPM: run.workingAvgCadence > 0 ? run.workingAvgCadence : run.rawAvgCadence,
                heartRateBPM: run.workingAvgHeartRate > 0 ? run.workingAvgHeartRate : run.rawAvgHeartRate,
                groundContactTimeMs: nil,
                verticalOscillationCm: run.workingAvgVerticalOscillation ?? run.rawAvgVerticalOscillation,
                strideLengthMeters: run.workingAvgStrideLength ?? run.rawAvgStrideLength,
                elevationGainMeters: nil,
                powerWatts: nil
            )
        }

        let profile = AthleteCalibrationCore.makeProfile(
            buckets: buckets,
            restingHRSamples: restingHRSamples,
            age: age,
            windowEnd: now
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let dayString = AthleteCalibrationCore.formatDayString(date: now, calendar: calendar)

        let intent = AthleteCalibrationCore.makeIntent(
            spec: spec,
            subjectiveDistress: subjectiveDistress,
            day: dayString,
            targetPaceSecondsPerKm: targetPaceSecondsPerKm
        )

        let indoorPref = isIndoorPreferred ?? UserDefaults.standard.bool(forKey: "preferredWorkoutIsIndoor")
        let context = WatchPacingContext(
            schemaVersion: WatchPacingContext.currentSchemaVersion,
            profile: profile,
            intent: intent,
            isIndoorPreferred: indoorPref,
            useMetricSystem: defaultMetricPreference,
            watchVoiceCuesEnabled: defaultVoiceCuesPreference
        )

        publish(context: context)
    }

    /// Publishes a structured drill intent directly to Apple Watch for execution in RunalystWatch.
    func publishDrillIntent(
        dto: DrillPrescriptionDTO,
        subjectiveDistress: Bool = false,
        now: Date = Date(),
        isIndoorPreferred: Bool? = nil
    ) {
        let profile = lastPublishedContext?.profile ?? AthleteCalibrationProfile(maxHR: 190.0, isFallback: true)
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let dayString = AthleteCalibrationCore.formatDayString(date: now, calendar: calendar)

        let intent = AthleteCalibrationCore.makeDrillIntent(
            title: dto.title,
            drillId: dto.preRunDrillId,
            targetCadence: dto.targetCadence,
            durationMinutes: dto.durationMinutes,
            day: dayString,
            subjectiveDistress: subjectiveDistress
        )

        let indoorPref = isIndoorPreferred ?? dto.isIndoor ?? UserDefaults.standard.bool(forKey: "preferredWorkoutIsIndoor")
        let context = WatchPacingContext(
            schemaVersion: WatchPacingContext.currentSchemaVersion,
            profile: profile,
            intent: intent,
            isIndoorPreferred: indoorPref,
            useMetricSystem: defaultMetricPreference,
            watchVoiceCuesEnabled: defaultVoiceCuesPreference
        )

        publish(context: context)
    }

    // MARK: - Watch Workout Handoff

    /// Launches the active companion workout on Apple Watch via HealthKit handoff.
    func launchWatchWorkout(isIndoor: Bool? = nil) async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let indoorPref = isIndoor ?? UserDefaults.standard.bool(forKey: "preferredWorkoutIsIndoor")
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = indoorPref ? .indoor : .outdoor

        if let existing = lastPublishedContext {
            let updated = WatchPacingContext(
                schemaVersion: existing.schemaVersion,
                profile: existing.profile,
                intent: existing.intent,
                isIndoorPreferred: indoorPref,
                useMetricSystem: existing.useMetricSystem,
                watchVoiceCuesEnabled: existing.watchVoiceCuesEnabled
            )
            publish(context: updated)
        } else {
            sendPacingContext(isIndoorPreferred: indoorPref)
        }

        await withCheckedContinuation { continuation in
            HKHealthStore().startWatchApp(with: configuration) { _, _ in
                continuation.resume()
            }
        }
    }

    // MARK: - Remote Control Commands & Snapshot Reception

    /// Sends a remote control command (pause, resume, end) to the active workout on Apple Watch.
    func sendRemoteCommand(_ command: WatchRemoteCommand) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        refreshSessionState(session)
        guard session.activationState == .activated, isWatchReachable else { return }
        session.sendMessage(["remoteCommand": command.rawValue], replyHandler: nil, errorHandler: nil)
    }

    /// Dismisses the completed workout debrief banner.
    func dismissCompletedDebrief() {
        self.latestCompletedDebrief = nil
        if self.latestWatchSnapshot?.phase == .completed {
            self.latestWatchSnapshot = nil
        }
        self.snapshotStalenessTask?.cancel()
        self.snapshotStalenessTask = nil
    }

    /// Refreshes snapshot staleness and clears `latestWatchSnapshot` if stale.
    @discardableResult
    func refreshStalenessIfNeeded(now: Date = Date()) -> Bool {
        if let snapshot = latestWatchSnapshot, snapshot.isStale(at: now.timeIntervalSince1970) {
            latestWatchSnapshot = nil
            snapshotStalenessTask?.cancel()
            snapshotStalenessTask = nil
            return true
        }
        return false
    }

    private func scheduleStalenessTimer(for snapshot: WatchLiveRunSnapshot) {
        snapshotStalenessTask?.cancel()
        snapshotStalenessTask = nil

        guard snapshot.phase != .completed && !snapshot.isPaused else {
            return
        }

        snapshotStalenessTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 46_000_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.refreshStalenessIfNeeded()
        }
    }

    /// Processes an incoming raw `WatchLiveRunSnapshot` JSON payload from Apple Watch.
    func handleReceivedLiveSnapshotData(_ data: Data) {
        guard let snapshot = try? JSONDecoder().decode(WatchLiveRunSnapshot.self, from: data) else {
            return
        }
        guard snapshot.isSupportedSchema else { return }
        if snapshot.isStale(at: Date().timeIntervalSince1970) {
            return
        }
        if let existing = latestWatchSnapshot, snapshot.updatedAtEpochSeconds < existing.updatedAtEpochSeconds {
            return
        }
        self.latestWatchSnapshot = snapshot
        if snapshot.phase == .completed, let debrief = snapshot.completedDebrief {
            self.latestCompletedDebrief = debrief
        }
        scheduleStalenessTimer(for: snapshot)
    }

    // MARK: - WCSessionDelegate

    private func publishPendingContext() {
        guard let pending = self.pendingContext else { return }
        publish(context: pending)
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        guard activationState == .activated else { return }
        Task { @MainActor in
            self.refreshSessionState(WCSession.default)
            self.publishPendingContext()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.refreshSessionState(WCSession.default)
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.refreshSessionState(WCSession.default)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        let snapshotData = applicationContext["watchLiveSnapshot"] as? Data
        Task { @MainActor in
            if let snapshotData {
                self.handleReceivedLiveSnapshotData(snapshotData)
            }
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
        let snapshotData = userInfo["watchLiveSnapshot"] as? Data
        Task { @MainActor in
            if let snapshotData {
                self.handleReceivedLiveSnapshotData(snapshotData)
            }
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        let snapshotData = message["watchLiveSnapshot"] as? Data
        let remoteCommandString = message["remoteCommand"] as? String
        Task { @MainActor in
            if let snapshotData {
                self.handleReceivedLiveSnapshotData(snapshotData)
            }
            if remoteCommandString == WatchRemoteCommand.requestContextSync.rawValue {
                if let existing = self.lastPublishedContext {
                    self.publish(context: existing)
                } else {
                    self.sendPacingContext()
                }
            }
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        let snapshotData = message["watchLiveSnapshot"] as? Data
        let remoteCommandString = message["remoteCommand"] as? String
        let voiceCueText = message["voiceCueText"] as? String
        let voiceCueLanguage = message["voiceCueLanguage"] as? String
        let replyBox = UncheckedReplyBox(send: replyHandler)

        Task { @MainActor in
            if let snapshotData {
                self.handleReceivedLiveSnapshotData(snapshotData)
            }

            if let text = voiceCueText {
                let spoken = CompanionVoiceRelay.shared.speakIfHeadphonesConnected(text: text, language: voiceCueLanguage)
                replyBox.send(["spoken": spoken])
                return
            }

            if remoteCommandString == WatchRemoteCommand.requestContextSync.rawValue {
                if let existing = self.lastPublishedContext {
                    self.publish(context: existing)
                } else {
                    self.sendPacingContext()
                }
                var reply: [String: Any] = ["status": "ok"]
                if let ctx = self.lastPublishedContext,
                   let data = try? JSONEncoder().encode(ctx) {
                    reply["pacingContext"] = data
                }
                replyBox.send(reply)
                return
            }

            replyBox.send([:])
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Reactivate for multi-watch switching
        WCSession.default.activate()
    }
}

private struct UncheckedReplyBox: @unchecked Sendable {
    let send: ([String: Any]) -> Void
}
