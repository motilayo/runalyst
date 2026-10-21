import Foundation

// MARK: - Banister Workload Domain Types

/// A pure, framework-agnostic record of a training session's mechanical and cardiovascular load.
public struct WorkloadSession: Sendable, Codable, Equatable {
    public let date: Date
    public let durationMinutes: Double
    public let distanceMeters: Double
    public let percentZone4: Double
    public let isHardSession: Bool
    public let tags: Set<String>

    /// Session load proxy (TRIMP-style): working minutes, with Zone 4/5 minutes weighted 3x.
    public var trainingLoad: Double {
        let minutes = max(0.0, durationMinutes)
        let z4 = min(1.0, max(0.0, percentZone4))
        return minutes * (1.0 + 2.0 * z4)
    }

    public init(
        date: Date,
        durationMinutes: Double,
        distanceMeters: Double,
        percentZone4: Double,
        isHardSession: Bool = false,
        tags: Set<String> = []
    ) {
        self.date = date
        self.durationMinutes = durationMinutes
        self.distanceMeters = distanceMeters
        self.percentZone4 = percentZone4
        self.isHardSession = isHardSession
        self.tags = tags
    }
}

/// Acute:Chronic Workload Ratio (ACWR) safety and adaptation zones.
public enum ACWRZone: String, Sendable, Codable, Equatable, CaseIterable {
    /// ACWR < 0.8: Under-training or recovery phase; risk of fitness decay.
    case low
    /// 0.8 <= ACWR <= 1.3: Optimal sweet spot; progressive overload without excessive injury risk.
    case optimal
    /// 1.3 < ACWR <= 1.4: Elevated training load; monitor biomechanics and turnover closely.
    case elevated
    /// ACWR > 1.4: High injury risk spike; triggers mandatory safety recovery override.
    case spike

    public var isOverloadSpike: Bool {
        self == .spike
    }
}

/// The synthesized readiness, workload, and deterministic safety directive report.
public struct BanisterReadinessReport: Sendable, Codable, Equatable {
    public let acuteLoad: Double
    public let chronicWeeklyLoad: Double
    public let acwr: Double?
    public let zone: ACWRZone?
    public let isSafetyOverridden: Bool
    public let overrideReason: String?
    public let effectiveDirective: RunDirective

    public init(
        acuteLoad: Double,
        chronicWeeklyLoad: Double,
        acwr: Double?,
        zone: ACWRZone?,
        isSafetyOverridden: Bool,
        overrideReason: String?,
        effectiveDirective: RunDirective
    ) {
        self.acuteLoad = acuteLoad
        self.chronicWeeklyLoad = chronicWeeklyLoad
        self.acwr = acwr
        self.zone = zone
        self.isSafetyOverridden = isSafetyOverridden
        self.overrideReason = overrideReason
        self.effectiveDirective = effectiveDirective
    }
}

// MARK: - Banister Readiness Core

/// Pure sports science engine for Acute:Chronic Workload Ratio (ACWR) evaluation
/// and the Deterministic Safety Gate.
public enum BanisterReadinessCore {

    public static let acuteWindowDays = 7
    public static let chronicWindowDays = 28
    public static let acwrSpikeThreshold = 1.4
    public static let minimumHistorySpanDays = 14
    public static let minimumChronicRuns = 4

    /// Classifies an ACWR value into its physiological risk zone.
    public static func classifyZone(acwr: Double) -> ACWRZone {
        if acwr < 0.8 {
            return .low
        } else if acwr <= 1.3 {
            return .optimal
        } else if acwr <= 1.4 {
            return .elevated
        } else {
            return .spike
        }
    }

    /// Evaluates Acute:Chronic Workload Ratio from a sequence of sessions.
    /// Employs a coupled 7-day acute and 28-day chronic window.
    public static func calculateACWR(
        sessions: [WorkloadSession],
        now: Date
    ) -> (acuteLoad: Double, chronicWeeklyLoad: Double, acwr: Double?, zone: ACWRZone?) {
        let dayInterval: TimeInterval = 24 * 3600
        let acuteCutoff = now.addingTimeInterval(-Double(acuteWindowDays) * dayInterval)
        let chronicCutoff = now.addingTimeInterval(-Double(chronicWindowDays) * dayInterval)

        let window = sessions
            .filter { $0.date <= now && $0.date >= chronicCutoff }
            .sorted { $0.date > $1.date }

        guard !window.isEmpty else {
            return (0.0, 0.0, nil, nil)
        }

        let acuteSessions = window.filter { $0.date >= acuteCutoff }
        let acuteLoad = acuteSessions.map(\.trainingLoad).reduce(0.0, +)
        let chronicWeeklyLoad = window.map(\.trainingLoad).reduce(0.0, +) / (Double(chronicWindowDays) / 7.0)

        let oldestDate = window.last?.date ?? now
        let historySpanDays = now.timeIntervalSince(oldestDate) / dayInterval
        let hasChronicHistory = historySpanDays >= Double(minimumHistorySpanDays)
            && window.count >= minimumChronicRuns
            && chronicWeeklyLoad > 0.0

        guard hasChronicHistory else {
            return (acuteLoad, chronicWeeklyLoad, nil, nil)
        }

        let acwrValue = acuteLoad / chronicWeeklyLoad
        let zone = classifyZone(acwr: acwrValue)
        return (acuteLoad, chronicWeeklyLoad, acwrValue, zone)
    }

    /// The Deterministic Safety Gate:
    /// When fatigue, an ACWR spike (> 1.4), cardiac decoupling, or subjective distress is active,
    /// Swift strictly strips any stated race goals and injects a mandatory EasyAerobicRecovery directive.
    public static func evaluateSafetyGate(
        sessions: [WorkloadSession],
        now: Date,
        paceDeltaVsBaseline: Double? = nil,
        hrDeltaVsBaseline: Double? = nil,
        subjectiveDistress: SubjectiveDistressSignal? = nil,
        userStatedDirective: RunDirective = .steadyAerobicMaintenance(targetSPM: 160)
    ) -> BanisterReadinessReport {
        let (acuteLoad, chronicWeeklyLoad, acwr, zone) = calculateACWR(sessions: sessions, now: now)

        // Safety Trigger 1: User subjective distress override
        if let distress = subjectiveDistress, distress.requiresSafetyOverride {
            let reason = "Subjective biological override active (\(distress.rawValue)). Safety overrides race goal."
            let directive = RunDirective.easyAerobicRecovery(pacingBand: .zone1Recovery, maxDurationMinutes: 30.0)
            return BanisterReadinessReport(
                acuteLoad: acuteLoad,
                chronicWeeklyLoad: chronicWeeklyLoad,
                acwr: acwr,
                zone: zone,
                isSafetyOverridden: true,
                overrideReason: reason,
                effectiveDirective: directive
            )
        }

        // Safety Trigger 2: ACWR overload spike (> 1.4)
        if let ratio = acwr, ratio > acwrSpikeThreshold {
            let reason = "ACWR workload spike detected (\(String(format: "%.2f", ratio)) > \(acwrSpikeThreshold)). Mandatory aerobic recovery required."
            let directive = RunDirective.easyAerobicRecovery(pacingBand: .zone1Recovery, maxDurationMinutes: 35.0)
            return BanisterReadinessReport(
                acuteLoad: acuteLoad,
                chronicWeeklyLoad: chronicWeeklyLoad,
                acwr: acwr,
                zone: zone,
                isSafetyOverridden: true,
                overrideReason: reason,
                effectiveDirective: directive
            )
        }

        // Safety Trigger 3: Physiological cardiac fatigue decoupling (slower pace with higher heart rate)
        if let paceDiff = paceDeltaVsBaseline, let hrDelta = hrDeltaVsBaseline, paceDiff < 0 && hrDelta > 0 {
            let reason = "Physiological cardiac strain decoupling: slower pace accompanied by elevated heart rate. Safety overrides race goal."
            let directive = RunDirective.easyAerobicRecovery(pacingBand: .zone1Recovery, maxDurationMinutes: 30.0)
            return BanisterReadinessReport(
                acuteLoad: acuteLoad,
                chronicWeeklyLoad: chronicWeeklyLoad,
                acwr: acwr,
                zone: zone,
                isSafetyOverridden: true,
                overrideReason: reason,
                effectiveDirective: directive
            )
        }

        // Safety Trigger 4: Consecutive hard days within 72 hours
        let dayInterval: TimeInterval = 24 * 3600
        let triggerCutoff = now.addingTimeInterval(-72 * 3600)
        let acuteCutoff = now.addingTimeInterval(-Double(acuteWindowDays) * dayInterval)
        let recentHard = sessions
            .filter { $0.date >= acuteCutoff && $0.date <= now && $0.isHardSession }
            .sorted { $0.date > $1.date }

        if hasConsecutiveHardSessions(recentHard: recentHard, triggerCutoff: triggerCutoff) {
            let reason = "Consecutive hard training sessions recorded within 72 hours. Mandatory recovery prescribed."
            let directive = RunDirective.easyAerobicRecovery(pacingBand: .zone1Recovery, maxDurationMinutes: 30.0)
            return BanisterReadinessReport(
                acuteLoad: acuteLoad,
                chronicWeeklyLoad: chronicWeeklyLoad,
                acwr: acwr,
                zone: zone,
                isSafetyOverridden: true,
                overrideReason: reason,
                effectiveDirective: directive
            )
        }

        // No safety override: runner is cleared for prescribed workout directive
        return BanisterReadinessReport(
            acuteLoad: acuteLoad,
            chronicWeeklyLoad: chronicWeeklyLoad,
            acwr: acwr,
            zone: zone,
            isSafetyOverridden: false,
            overrideReason: nil,
            effectiveDirective: userStatedDirective
        )
    }

    private static func hasConsecutiveHardSessions(recentHard: [WorkloadSession], triggerCutoff: Date) -> Bool {
        guard recentHard.count >= 2 else { return false }
        for index in 0..<(recentHard.count - 1) {
            let later = recentHard[index]
            let earlier = recentHard[index + 1]
            guard later.date >= triggerCutoff else { continue }
            let diffSeconds = later.date.timeIntervalSince(earlier.date)
            // Sessions separated by between 12 and 36 hours count as consecutive calendar days
            if diffSeconds >= 12 * 3600 && diffSeconds <= 36 * 3600 {
                return true
            }
        }
        return false
    }
}
