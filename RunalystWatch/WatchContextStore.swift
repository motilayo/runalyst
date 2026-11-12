import Foundation
import Observation
import RunalystCore
import WatchConnectivity

// MARK: - Watch Context Store

/// Manages cached athlete calibration context received from iPhone via WatchConnectivity.
@MainActor
@Observable
public final class WatchContextStore: NSObject, WCSessionDelegate {
    public static let shared = WatchContextStore()

    private let userDefaultsKey = "cachedWatchPacingContext"
    public private(set) var cachedContext: WatchPacingContext?
    private var lastBroadcastUptime: TimeInterval = 0

    /// Synchronized preferred pacing location from iOS app context, defaulting to outdoor if unspecified.
    public var preferredLocation: PacingLocation {
        if cachedContext?.isIndoorPreferred == true {
            return .indoor
        } else {
            return .outdoor
        }
    }

    override private init() {
        super.init()
        reloadPersistedContext()
        activateSession()
    }

    private func activateSession() {
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }

    // MARK: - Persistence

    public func reloadPersistedContext() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            self.cachedContext = nil
            return
        }
        do {
            let context = try JSONDecoder().decode(WatchPacingContext.self, from: data)
            if context.isSupportedSchema {
                self.cachedContext = context
            }
        } catch {
            // Invalid data format; discard safely
        }
    }

    private func persistContext(_ context: WatchPacingContext) {
        guard context.isSupportedSchema else { return }
        if let useMetric = context.useMetricSystem {
            UserDefaults.standard.set(useMetric, forKey: "useMetricSystem")
        }
        if let voice = context.watchVoiceCuesEnabled {
            UserDefaults.standard.set(voice, forKey: "watchVoiceCuesEnabled")
        }
        do {
            let data = try JSONEncoder().encode(context)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
            self.cachedContext = context
        } catch {
            // Encoding failed
        }
    }

    // MARK: - Session Resolution

    /// Resolves the workout session configuration given today's date, running intent, and optional pace override.
    public func resolveSession(
        runIntent: WatchRunIntent = .adaptiveBase,
        selectedPace: Int? = nil,
        fallbackAge: Int? = nil
    ) -> WatchResolvedSessionConfig {
        let currentDay = todayDayString()
        return AthleteCalibrationCore.resolveWatchSession(
            cachedContext: cachedContext,
            currentDayString: currentDay,
            selectedTargetPaceSecondsPerKm: selectedPace,
            fallbackAge: fallbackAge
        ).applying(runIntent: runIntent)
    }

    private func todayDayString() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return AthleteCalibrationCore.formatDayString(date: Date(), calendar: calendar)
    }

    // MARK: - Remote Context & Live Snapshot Streaming

    /// Proactively requests the freshest pacing context and calibration profile from iPhone if reachable.
    public func requestLatestContextIfNeeded() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated && session.isReachable else { return }

        session.sendMessage(
            ["remoteCommand": WatchRemoteCommand.requestContextSync.rawValue],
            replyHandler: { reply in
                guard let data = reply["pacingContext"] as? Data else { return }
                Task { @MainActor in
                    self.processContextData(data)
                }
            },
            errorHandler: nil
        )
    }

    /// Publishes a live run snapshot to the paired iPhone via WatchConnectivity.
    public func publishLiveSnapshot(_ snapshot: WatchLiveRunSnapshot, forceImmediate: Bool = false) {
        let now = ProcessInfo.processInfo.systemUptime
        if !forceImmediate && (now - lastBroadcastUptime) < 2.0 {
            return
        }
        lastBroadcastUptime = now

        do {
            let data = try JSONEncoder().encode(snapshot)
            guard WCSession.isSupported() else { return }
            let session = WCSession.default
            guard session.activationState == .activated else { return }

            try? session.updateApplicationContext(["watchLiveSnapshot": data])

            if session.isReachable {
                session.sendMessage(["watchLiveSnapshot": data], replyHandler: nil, errorHandler: nil)
            }

            if snapshot.phase == .completed {
                _ = session.transferUserInfo(["watchLiveSnapshot": data])
            }
        } catch {
            // Encoding failed safely
        }
    }

    private func processContextData(_ data: Data) {
        // Explicitly reject unsupported schemaVersion > 1, preserving existing cached context
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let version = json["schemaVersion"] as? Int,
           version > WatchPacingContext.currentSchemaVersion {
            return
        }

        do {
            let context = try JSONDecoder().decode(WatchPacingContext.self, from: data)
            if context.isSupportedSchema {
                self.persistContext(context)
            }
        } catch {
            // Ignore malformed or unsupported payload
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchContextStore {
    nonisolated public func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        let contextData = session.receivedApplicationContext["pacingContext"] as? Data
        let isReachable = session.isReachable
        let isActivated = (activationState == .activated)
        Task { @MainActor in
            if let contextData {
                self.processContextData(contextData)
            }
            if isActivated && isReachable {
                self.requestLatestContextIfNeeded()
            }
        }
    }

    nonisolated public func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        let contextData = applicationContext["pacingContext"] as? Data
        if let contextData {
            Task { @MainActor in
                self.processContextData(contextData)
            }
        }
    }

    nonisolated public func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
        let contextData = userInfo["pacingContext"] as? Data
        if let contextData {
            Task { @MainActor in
                self.processContextData(contextData)
            }
        }
    }

    nonisolated public func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        let contextData = message["pacingContext"] as? Data
        let remoteCommand = message["remoteCommand"] as? String
        Task { @MainActor in
            if let contextData {
                self.processContextData(contextData)
            }
            if let remoteCommand {
                WorkoutManager.shared.handleRemoteCommand(remoteCommand)
            }
        }
    }

    nonisolated public func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        let contextData = message["pacingContext"] as? Data
        let remoteCommand = message["remoteCommand"] as? String
        replyHandler(["status": "acknowledged"])
        Task { @MainActor in
            if let contextData {
                self.processContextData(contextData)
            }
            if let remoteCommand {
                WorkoutManager.shared.handleRemoteCommand(remoteCommand)
            }
        }
    }

    nonisolated public func sessionReachabilityDidChange(_ session: WCSession) {
        let isReachable = session.isReachable
        let isActivated = (session.activationState == .activated)
        Task { @MainActor in
            if isActivated && isReachable {
                self.requestLatestContextIfNeeded()
            }
        }
    }
}
