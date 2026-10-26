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

    /// Evaluates multi-day streaks, 48-hour volume compression, and day-over-day cardiac decoupling
    /// calibrated by the runner's experience level and active training goal.
    public static func evaluateStreakAndVolume(
        samples: [StreakRunSample],
        experienceLevel: String,
        trainingGoal: String,
        now: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> StreakAndVolumeSummary {
        // 1. Separate main runs (>= 20 min or non-primer) from short primers (< 20 min)
        let mainRuns = samples.filter { sample in
            guard sample.date <= now else { return false }
            let isShortPrimer = (sample.isPrimer || sample.durationSeconds < 1200) && sample.percentZone4 < 0.25
            return !isShortPrimer
        }.sorted { $0.date > $1.date }

        // 2. Trailing 28-day baseline (duration and frequency)
        let day28Cutoff = calendar.date(byAdding: .day, value: -28, to: now) ?? now.addingTimeInterval(-28 * 24 * 3600)
        let trailingRuns = mainRuns.filter { $0.date >= day28Cutoff }
        let totalTrailingDurationMins = trailingRuns.map { $0.durationSeconds / 60.0 }.reduce(0, +)
        let trailingWeeklyDurationMinutes = totalTrailingDurationMins > 0 ? (totalTrailingDurationMins / 4.0) : 150.0

        var uniqueTrailingDays = Set<DateComponents>()
        for run in trailingRuns {
            uniqueTrailingDays.insert(calendar.dateComponents([.year, .month, .day], from: run.date))
        }
        let trailingWeeklyActiveDays = !uniqueTrailingDays.isEmpty ? (Double(uniqueTrailingDays.count) / 4.0) : 3.5

        // 3. 48-Hour Volume (Includes all runs banked across trailing 2 calendar days leading into today)
        let startOfToday = calendar.startOfDay(for: now)
        let cutoff48h = calendar.date(byAdding: .day, value: -2, to: startOfToday) ?? now.addingTimeInterval(-48 * 3600)
        let runs48h = samples.filter { $0.date <= now && $0.date >= cutoff48h }
        let last48hDurationMinutes = runs48h.map { $0.durationSeconds / 60.0 }.reduce(0, +)
        let volumeRatio48h = trailingWeeklyDurationMinutes > 0 ? (last48hDurationMinutes / trailingWeeklyDurationMinutes) : 0.0

        // 4. Consecutive Run Days (Streak)
        var streak = 0
        var checkDate = now
        let todayComponents = calendar.dateComponents([.year, .month, .day], from: now)
        let hasRunToday = mainRuns.contains { calendar.dateComponents([.year, .month, .day], from: $0.date) == todayComponents }
        if !hasRunToday {
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: now) {
                let yesterdayComponents = calendar.dateComponents([.year, .month, .day], from: yesterday)
                let hasRunYesterday = mainRuns.contains { calendar.dateComponents([.year, .month, .day], from: $0.date) == yesterdayComponents }
                if hasRunYesterday {
                    checkDate = yesterday
                }
            }
        }

        while streak < 14 {
            guard let targetDay = calendar.date(byAdding: .day, value: -streak, to: checkDate) else { break }
            let targetComponents = calendar.dateComponents([.year, .month, .day], from: targetDay)
            let ranOnDay = mainRuns.contains { calendar.dateComponents([.year, .month, .day], from: $0.date) == targetComponents }
            if ranOnDay {
                streak += 1
            } else {
                break
            }
        }

        // 5. Back-to-Back HR Decoupling (Day-over-Day)
        var hrDecoupling = 0.0
        if streak >= 2, mainRuns.count >= 2 {
            let latest = mainRuns[0]
            let previous = mainRuns[1]
            if calendar.isDate(latest.date, inSameDayAs: checkDate),
               let prevExpected = calendar.date(byAdding: .day, value: -1, to: checkDate),
               calendar.isDate(previous.date, inSameDayAs: prevExpected) {
                let latestHR = latest.avgHeartRate
                let prevHR = previous.avgHeartRate
                if latestHR > 0 && prevHR > 0 {
                    hrDecoupling = latestHR - prevHR
                }
            }
        }

        // 6. Calibration Matrix (Experience & Goal)
        let exp = experienceLevel.lowercased()
        let baseMaxDays: Int
        let baseCompressionThreshold: Double

        if exp.contains("novice") || exp.contains("beginner") {
            baseMaxDays = 2
            baseCompressionThreshold = 0.50
        } else if exp.contains("advanced") || exp.contains("veteran") {
            baseMaxDays = 4
            baseCompressionThreshold = 0.68
        } else if exp.contains("competitive") || exp.contains("elite") {
            baseMaxDays = 5
            baseCompressionThreshold = 0.75
        } else {
            baseMaxDays = 3
            baseCompressionThreshold = 0.60
        }

        var maxDays = baseMaxDays
        var compressionThreshold = baseCompressionThreshold
        let goal = trainingGoal.lowercased()

        if goal.contains("injury") || goal.contains("recovery") {
            maxDays = 1
            compressionThreshold = 0.45
        } else if goal.contains("half") || goal.contains("marathon") {
            if !exp.contains("novice") {
                maxDays = min(5, baseMaxDays + 1)
            }
            compressionThreshold = min(0.85, baseCompressionThreshold + 0.05)
        }

        // 7. Decision
        var recommendRest = false
        var reason: String?

        if streak >= maxDays {
            recommendRest = true
            reason = "You've completed \(streak) consecutive days of running. A scheduled rest day allows muscle and tendon rebuilding before your next run toward \(trainingGoal)."
        } else if volumeRatio48h >= compressionThreshold && last48hDurationMinutes >= 60.0 {
            recommendRest = true
            let pct = Int(round(volumeRatio48h * 100))
            let mins48 = Int(round(last48hDurationMinutes))
            let weeklyMins = Int(round(trailingWeeklyDurationMinutes))
            reason = "48-Hour Volume Compression: You've banked \(mins48) min in the last 48 hours (\(pct)% of your \(weeklyMins) min/week average). A rest day allows deep recovery to prevent cumulative overload."
        } else if streak >= 2 && hrDecoupling >= 10.0 {
            recommendRest = true
            let shift = Int(round(hrDecoupling))
            reason = "Day-over-day cardiac drift (+\(shift) BPM) indicates autonomic fatigue after consecutive runs. Take a rest day to recover baseline cardiac cost."
        }

        return StreakAndVolumeSummary(
            consecutiveRunDays: streak,
            last48hDurationMinutes: last48hDurationMinutes,
            trailingWeeklyDurationMinutes: trailingWeeklyDurationMinutes,
            trailingWeeklyActiveDays: trailingWeeklyActiveDays,
            backToBackHRDecouplingBPM: hrDecoupling,
            volumeRatio48h: volumeRatio48h,
            maxConsecutiveDays: maxDays,
            volumeCompressionThreshold: compressionThreshold,
            shouldRecommendRestDay: recommendRest,
            restDayReason: reason
        )
    }
}

// MARK: - Streak and Volume Domain Types

public struct StreakRunSample: Sendable, Equatable, Codable {
    public let date: Date
    public let durationSeconds: Double
    public let percentZone4: Double
    public let avgHeartRate: Double
    public let isPrimer: Bool

    public init(
        date: Date,
        durationSeconds: Double,
        percentZone4: Double,
        avgHeartRate: Double = 0.0,
        isPrimer: Bool = false
    ) {
        self.date = date
        self.durationSeconds = durationSeconds
        self.percentZone4 = percentZone4
        self.avgHeartRate = avgHeartRate
        self.isPrimer = isPrimer
    }
}

public struct StreakAndVolumeSummary: Sendable, Equatable, Codable {
    public let consecutiveRunDays: Int
    public let last48hDurationMinutes: Double
    public let trailingWeeklyDurationMinutes: Double
    public let trailingWeeklyActiveDays: Double
    public let backToBackHRDecouplingBPM: Double
    public let volumeRatio48h: Double
    public let maxConsecutiveDays: Int
    public let volumeCompressionThreshold: Double
    public let shouldRecommendRestDay: Bool
    public let restDayReason: String?

    public init(
        consecutiveRunDays: Int,
        last48hDurationMinutes: Double,
        trailingWeeklyDurationMinutes: Double,
        trailingWeeklyActiveDays: Double,
        backToBackHRDecouplingBPM: Double,
        volumeRatio48h: Double,
        maxConsecutiveDays: Int,
        volumeCompressionThreshold: Double,
        shouldRecommendRestDay: Bool,
        restDayReason: String?
    ) {
        self.consecutiveRunDays = consecutiveRunDays
        self.last48hDurationMinutes = last48hDurationMinutes
        self.trailingWeeklyDurationMinutes = trailingWeeklyDurationMinutes
        self.trailingWeeklyActiveDays = trailingWeeklyActiveDays
        self.backToBackHRDecouplingBPM = backToBackHRDecouplingBPM
        self.volumeRatio48h = volumeRatio48h
        self.maxConsecutiveDays = maxConsecutiveDays
        self.volumeCompressionThreshold = volumeCompressionThreshold
        self.shouldRecommendRestDay = shouldRecommendRestDay
        self.restDayReason = restDayReason
    }
}
