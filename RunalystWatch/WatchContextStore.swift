import Foundation
import Observation
import RunalystCore
import WatchConnectivity

// MARK: - Watch Context Store

/// Manages cached athlete calibration context received from iPhone via WatchConnectivity.
@Observable
public final class WatchContextStore: NSObject, WCSessionDelegate, @unchecked Sendable {
    public static let shared = WatchContextStore()

    private let userDefaultsKey = "cachedWatchPacingContext"
    public private(set) var cachedContext: WatchPacingContext?

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
        do {
            let data = try JSONEncoder().encode(context)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
            self.cachedContext = context
        } catch {
            // Encoding failed
        }
    }

    // MARK: - Session Resolution

    /// Resolves the workout session configuration given today's date and the runner's choice.
    public func resolveSession(
        selectedPace: Int? = nil,
        fallbackAge: Int? = nil
    ) -> WatchResolvedSessionConfig {
        let currentDay = todayDayString()
        return AthleteCalibrationCore.resolveWatchSession(
            cachedContext: cachedContext,
            currentDayString: currentDay,
            selectedTargetPaceSecondsPerKm: selectedPace,
            fallbackAge: fallbackAge
        )
    }

    private func todayDayString() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return AthleteCalibrationCore.formatDayString(date: Date(), calendar: calendar)
    }

    // MARK: - WCSessionDelegate

    public func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        if let contextData = session.receivedApplicationContext["pacingContext"] as? Data {
            processContextData(contextData)
        }
    }

    public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let contextData = applicationContext["pacingContext"] as? Data {
            processContextData(contextData)
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
                Task { @MainActor in
                    self.persistContext(context)
                }
            }
        } catch {
            // Ignore malformed or unsupported payload
        }
    }
}
