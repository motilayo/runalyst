import Foundation
import RunalystCore
import WatchConnectivity

/// Hollow adapter bridging athlete calibration profiles and training intents to Apple Watch via WatchConnectivity.
///
/// Strictly obeys the Hollow Foundry doctrine: performs zero physiological math or threshold comparisons.
/// All calibration and intent derivation is performed exclusively by `RunalystCore`.
@MainActor
final class WatchCalibrationBridge: NSObject, WCSessionDelegate {
    static let shared = WatchCalibrationBridge()

    private var pendingContext: WatchPacingContext?
    private var lastPublishedContext: WatchPacingContext?

    override private init() {
        super.init()
        activateSession()
    }

    private func activateSession() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    // MARK: - Publishing API

    /// Publishes a pre-built `WatchPacingContext` to the paired Apple Watch.
    func publish(context: WatchPacingContext) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default

        guard session.activationState == .activated else {
            self.pendingContext = context
            if session.activationState == .notActivated {
                session.activate()
            }
            return
        }

        // Silent exit if watch is not paired or watch app not installed
        guard session.isPaired, session.isWatchAppInstalled else { return }

        // Skip redundant transfers if unchanged
        if let last = lastPublishedContext, last == context {
            return
        }

        do {
            let data = try JSONEncoder().encode(context)
            try session.updateApplicationContext(["pacingContext": data])
            self.lastPublishedContext = context
            self.pendingContext = nil
        } catch {
            // Silently handle transport failure with zero user disruption
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
        targetPaceSecondsPerKm: Int? = nil
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

        let context = WatchPacingContext(
            schemaVersion: WatchPacingContext.currentSchemaVersion,
            profile: profile,
            intent: intent
        )

        publish(context: context)
    }

    /// Publishes a structured drill intent directly to Apple Watch for execution in RunalystWatch.
    func publishDrillIntent(
        dto: DrillPrescriptionDTO,
        subjectiveDistress: Bool = false,
        now: Date = Date()
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

        let context = WatchPacingContext(
            schemaVersion: WatchPacingContext.currentSchemaVersion,
            profile: profile,
            intent: intent
        )

        publish(context: context)
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
            self.publishPendingContext()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Reactivate for multi-watch switching
        WCSession.default.activate()
    }
}
