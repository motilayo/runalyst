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
    @ObservationIgnored private var latestRecentWalkMeters48h: Double?

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
        guard WCSession.isSupported() else { return }
        let session = WCSession.default

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

        refreshSessionState(session)
        self.lastPublishedContext = resolvedContext

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
        if let last = lastPublishedContext, last == resolvedContext, !isWatchReachable {
            return
        }

        do {
            let data = try JSONEncoder().encode(resolvedContext)
            try session.updateApplicationContext(["pacingContext": data])
            if isWatchReachable {
                session.sendMessage(["pacingContext": data], replyHandler: nil, errorHandler: nil)
            }
            self.lastPublishedContext = resolvedContext
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
        isIndoorPreferred: Bool? = nil,
        readinessHint: WatchReadinessHint? = nil
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

        let userHeight: Double = {
            let stored = UserDefaults.standard.double(forKey: "userHeightCm")
            return stored > 0 ? stored : 175.0
        }()

        let resolvedReadinessHint: WatchReadinessHint = {
            if let hint = readinessHint {
                if hint.recentWalkMeters48h == nil, let cachedWalk = latestRecentWalkMeters48h {
                    return WatchReadinessHint(
                        daysSinceLastRun: hint.daysSinceLastRun,
                        recentWalkMeters48h: cachedWalk,
                        hadRecentCadenceFade: hint.hadRecentCadenceFade,
                        hadRecentBounce: hint.hadRecentBounce,
                        calibratedCadenceFloorSPM: hint.calibratedCadenceFloorSPM,
                        isClearedForQuality: hint.isClearedForQuality
                    )
                }
                return hint
            }
            return SessionSynthesisEngine.buildWatchReadinessHint(
                runRecords: runs,
                userHeightCm: userHeight,
                recentWalkMeters48h: latestRecentWalkMeters48h,
                subjectiveDistress: subjectiveDistress,
                now: now
            )
        }()

        let intent = AthleteCalibrationCore.makeIntent(
            spec: spec,
            subjectiveDistress: subjectiveDistress,
            day: dayString,
            targetPaceSecondsPerKm: targetPaceSecondsPerKm,
            readinessHint: resolvedReadinessHint
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

        // When async context allows, query 48h walking distance read-only from HealthKitManager and update
        if resolvedReadinessHint.recentWalkMeters48h == nil {
            Task { @MainActor [weak self] in
                guard let self else { return }
                let walkMeters = await HealthKitManager.shared.fetchRecentWalkingDistanceMeters(windowHours: 48)
                guard walkMeters > 0 else { return }
                self.latestRecentWalkMeters48h = walkMeters
                self.updateRecentWalkingMeters(walkMeters)
            }
        }
    }

    /// Asynchronously derives athlete calibration and session intent, fetching 48-hour walking load before publishing to Apple Watch.
    func publishContextWithWalkingLoad(
        runs: [RunRecord],
        restingHRSamples: [Double] = [],
        age: Int? = nil,
        spec: PlannedSessionSpec? = nil,
        subjectiveDistress: Bool = false,
        now: Date = Date(),
        targetPaceSecondsPerKm: Int? = nil,
        isIndoorPreferred: Bool? = nil,
        readinessHint: WatchReadinessHint? = nil
    ) async {
        let walkMeters: Double? = if let existing = readinessHint?.recentWalkMeters48h {
            existing
        } else {
            await {
                let meters = await HealthKitManager.shared.fetchRecentWalkingDistanceMeters(windowHours: 48)
                return meters > 0 ? meters : nil
            }()
        }
        if let walkMeters {
            self.latestRecentWalkMeters48h = walkMeters
        }
        let userHeight: Double = {
            let stored = UserDefaults.standard.double(forKey: "userHeightCm")
            return stored > 0 ? stored : 175.0
        }()
        let hintToPublish = readinessHint.map { hint in
            WatchReadinessHint(
                daysSinceLastRun: hint.daysSinceLastRun,
                recentWalkMeters48h: walkMeters ?? hint.recentWalkMeters48h,
                hadRecentCadenceFade: hint.hadRecentCadenceFade,
                hadRecentBounce: hint.hadRecentBounce,
                calibratedCadenceFloorSPM: hint.calibratedCadenceFloorSPM,
                isClearedForQuality: hint.isClearedForQuality
            )
        } ?? SessionSynthesisEngine.buildWatchReadinessHint(
            runRecords: runs,
            userHeightCm: userHeight,
            recentWalkMeters48h: walkMeters,
            subjectiveDistress: subjectiveDistress,
            now: now
        )
        publishContext(
            runs: runs,
            restingHRSamples: restingHRSamples,
            age: age,
            spec: spec,
            subjectiveDistress: subjectiveDistress,
            now: now,
            targetPaceSecondsPerKm: targetPaceSecondsPerKm,
            isIndoorPreferred: isIndoorPreferred,
            readinessHint: hintToPublish
        )
    }

    /// Updates the published context with fresh walking load when received asynchronously.
    func updateRecentWalkingMeters(_ meters: Double) {
        guard let current = lastPublishedContext else { return }
        let currentHint = current.intent.readinessHint
        guard currentHint?.recentWalkMeters48h != meters else { return }
        let updatedHint = WatchReadinessHint(
            daysSinceLastRun: currentHint?.daysSinceLastRun,
            recentWalkMeters48h: meters,
            hadRecentCadenceFade: currentHint?.hadRecentCadenceFade ?? false,
            hadRecentBounce: currentHint?.hadRecentBounce ?? false,
            calibratedCadenceFloorSPM: currentHint?.calibratedCadenceFloorSPM,
            isClearedForQuality: currentHint?.isClearedForQuality ?? true
        )
        let updatedIntent = PacingSessionIntent(
            targetPaceSecondsPerKm: current.intent.targetPaceSecondsPerKm,
            intent: current.intent.intent,
            subjectiveDistress: current.intent.subjectiveDistress,
            validForDay: current.intent.validForDay,
            prescribedDrillTitle: current.intent.prescribedDrillTitle,
            prescribedDrillId: current.intent.prescribedDrillId,
            targetCadenceSPM: current.intent.targetCadenceSPM,
            prescribedDurationMinutes: current.intent.prescribedDurationMinutes,
            readinessHint: updatedHint
        )
        let updatedContext = WatchPacingContext(
            schemaVersion: current.schemaVersion,
            profile: current.profile,
            intent: updatedIntent,
            isIndoorPreferred: current.isIndoorPreferred,
            useMetricSystem: current.useMetricSystem,
            watchVoiceCuesEnabled: current.watchVoiceCuesEnabled
        )
        publish(context: updatedContext)
    }

    /// Publishes a structured drill intent directly to Apple Watch for execution in RunalystWatch.
    func publishDrillIntent(
        dto: DrillPrescriptionDTO,
        subjectiveDistress: Bool = false,
        now: Date = Date(),
        isIndoorPreferred: Bool? = nil,
        readinessHint: WatchReadinessHint? = nil
    ) {
        let profile = lastPublishedContext?.profile ?? AthleteCalibrationProfile(maxHR: 190.0, isFallback: true)
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let dayString = AthleteCalibrationCore.formatDayString(date: now, calendar: calendar)

        let effectiveHint = readinessHint ?? lastPublishedContext?.intent.readinessHint
        let intent = AthleteCalibrationCore.makeDrillIntent(
            title: dto.title,
            drillId: dto.preRunDrillId,
            targetCadence: dto.targetCadence,
            durationMinutes: dto.durationMinutes,
            day: dayString,
            subjectiveDistress: subjectiveDistress,
            readinessHint: effectiveHint
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

        sendPacingContext(isIndoorPreferred: indoorPref)

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
    }

    /// Processes an incoming raw `WatchLiveRunSnapshot` JSON payload from Apple Watch.
    func handleReceivedLiveSnapshotData(_ data: Data) {
        guard let snapshot = try? JSONDecoder().decode(WatchLiveRunSnapshot.self, from: data) else {
            return
        }
        guard snapshot.isSupportedSchema else { return }
        if let existing = latestWatchSnapshot, snapshot.updatedAtEpochSeconds < existing.updatedAtEpochSeconds {
            return
        }
        self.latestWatchSnapshot = snapshot
        if snapshot.phase == .completed, let debrief = snapshot.completedDebrief {
            self.latestCompletedDebrief = debrief
        }
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
                self.sendPacingContext()
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
                self.sendPacingContext()
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
