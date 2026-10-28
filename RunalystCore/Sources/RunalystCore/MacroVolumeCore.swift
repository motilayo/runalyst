import Foundation

public struct VolumeRunSample: Sendable, Codable, Equatable {
    public let id: UUID
    public let date: Date
    public let totalDistanceMeters: Double
    public let durationSeconds: Double
    public let workingAvgPace: Double
    public let workingAvgHeartRate: Int
    public let workingAvgCadence: Double
    public let classification: String

    public init(
        id: UUID,
        date: Date,
        totalDistanceMeters: Double,
        durationSeconds: Double,
        workingAvgPace: Double = 0,
        workingAvgHeartRate: Int = 0,
        workingAvgCadence: Double = 0,
        classification: String = "Easy Run"
    ) {
        self.id = id
        self.date = date
        self.totalDistanceMeters = totalDistanceMeters
        self.durationSeconds = durationSeconds
        self.workingAvgPace = workingAvgPace
        self.workingAvgHeartRate = workingAvgHeartRate
        self.workingAvgCadence = workingAvgCadence
        self.classification = classification
    }
}

public struct DayVolumeBucket: Sendable, Codable, Equatable, Identifiable {
    public let id: String
    public let date: Date
    public let dayLetter: String
    public let dayNumber: String
    public let distanceMeters: Double
    public let isToday: Bool
    public let hasRun: Bool

    public init(
        id: String,
        date: Date,
        dayLetter: String,
        dayNumber: String,
        distanceMeters: Double,
        isToday: Bool,
        hasRun: Bool
    ) {
        self.id = id
        self.date = date
        self.dayLetter = dayLetter
        self.dayNumber = dayNumber
        self.distanceMeters = distanceMeters
        self.isToday = isToday
        self.hasRun = hasRun
    }
}

public struct WeekVolumeBucket: Sendable, Codable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let distanceMeters: Double
    public let runCount: Int

    public init(id: String, label: String, distanceMeters: Double, runCount: Int) {
        self.id = id
        self.label = label
        self.distanceMeters = distanceMeters
        self.runCount = runCount
    }
}

public struct ClassificationCount: Sendable, Codable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let count: Int

    public init(name: String, count: Int) {
        self.name = name
        self.count = count
    }
}

public struct MacroVolumeSummary: Sendable, Codable, Equatable {
    public let totalDistanceMeters: Double
    public let totalDurationSeconds: Double
    public let runCount: Int
    public let activeDaysCount: Int
    public let weeklyAverageKm: Double
    public let runsPerWeek: Double
    public let trailing7Days: [DayVolumeBucket]
    public let trailing4Weeks: [WeekVolumeBucket]
    public let classificationMix: [ClassificationCount]
    public let baselineCadence: Int?
    public let previousBaselineCadence: Int?
    public let baselinePace: Double?
    public let previousBaselinePace: Double?
    public let baselineHeartRate: Int?
    public let workoutDensityTier: String

    public init(
        totalDistanceMeters: Double,
        totalDurationSeconds: Double,
        runCount: Int,
        activeDaysCount: Int,
        weeklyAverageKm: Double,
        runsPerWeek: Double,
        trailing7Days: [DayVolumeBucket],
        trailing4Weeks: [WeekVolumeBucket],
        classificationMix: [ClassificationCount],
        baselineCadence: Int?,
        previousBaselineCadence: Int?,
        baselinePace: Double?,
        previousBaselinePace: Double?,
        baselineHeartRate: Int?,
        workoutDensityTier: String
    ) {
        self.totalDistanceMeters = totalDistanceMeters
        self.totalDurationSeconds = totalDurationSeconds
        self.runCount = runCount
        self.activeDaysCount = activeDaysCount
        self.weeklyAverageKm = weeklyAverageKm
        self.runsPerWeek = runsPerWeek
        self.trailing7Days = trailing7Days
        self.trailing4Weeks = trailing4Weeks
        self.classificationMix = classificationMix
        self.baselineCadence = baselineCadence
        self.previousBaselineCadence = previousBaselineCadence
        self.baselinePace = baselinePace
        self.previousBaselinePace = previousBaselinePace
        self.baselineHeartRate = baselineHeartRate
        self.workoutDensityTier = workoutDensityTier
    }
}

public struct DashboardTrajectorySynthesis: Sendable, Equatable {
    public let verdict: TrajectoryVerdict
    public let volumeStatus: GoalVolumeStatus
    public let canonicalHeadline: String
    public let badgeLabel: String
    public let badgeTone: String
    public let directiveCode: String
    public let directiveContext: String
    public let efficiencyContext: String
    public let verticalOscillationContext: String
    public let fallbackBody: String

    public init(
        verdict: TrajectoryVerdict,
        volumeStatus: GoalVolumeStatus,
        canonicalHeadline: String,
        badgeLabel: String,
        badgeTone: String,
        directiveCode: String,
        directiveContext: String,
        efficiencyContext: String,
        verticalOscillationContext: String,
        fallbackBody: String
    ) {
        self.verdict = verdict
        self.volumeStatus = volumeStatus
        self.canonicalHeadline = canonicalHeadline
        self.badgeLabel = badgeLabel
        self.badgeTone = badgeTone
        self.directiveCode = directiveCode
        self.directiveContext = directiveContext
        self.efficiencyContext = efficiencyContext
        self.verticalOscillationContext = verticalOscillationContext
        self.fallbackBody = fallbackBody
    }

    public func reconcileHeadline(_ candidateHeadline: String) -> String {
        let trimmed = candidateHeadline.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return canonicalHeadline }
        let lower = trimmed.lowercased()
        if directiveCode == "TRAJECTORY_BUILDING_BASE" {
            if lower.contains("on track") || lower.contains("race ready") || lower.contains("ready for speed") || lower.contains("stabilizing") {
                return canonicalHeadline
            }
        } else if directiveCode == "TRAJECTORY_EASE_UP" {
            if lower.contains("on track") || lower.contains("race ready") || lower.contains("ready for speed") {
                return canonicalHeadline
            }
        }
        return trimmed
    }
}

public enum MacroVolumeCore {
    public static func evaluateVolumeSummary(
        allRuns: [VolumeRunSample],
        timeRange: String,
        isTrajectoryEaseUp: Bool = false,
        now: Date,
        calendar: Calendar
    ) -> MacroVolumeSummary {
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now.addingTimeInterval(-7 * 86400)
        let fourteenDaysAgo = calendar.date(byAdding: .day, value: -14, to: now) ?? now.addingTimeInterval(-14 * 86400)
        let twentyOneDaysAgo = calendar.date(byAdding: .day, value: -21, to: now) ?? now.addingTimeInterval(-21 * 86400)
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) ?? now.addingTimeInterval(-30 * 86400)
        let sixtyDaysAgo = calendar.date(byAdding: .day, value: -60, to: now) ?? now.addingTimeInterval(-60 * 86400)

        let runs30d = allRuns.filter { $0.date >= thirtyDaysAgo && $0.date <= now }
        let runs7d = allRuns.filter { $0.date >= sevenDaysAgo && $0.date <= now }

        let activeWindowRuns: [VolumeRunSample]
        let previousWindowRuns: [VolumeRunSample]
        switch timeRange {
        case "7 Days":
            activeWindowRuns = runs7d
            previousWindowRuns = allRuns.filter { $0.date >= fourteenDaysAgo && $0.date < sevenDaysAgo }
        case "30 Days":
            activeWindowRuns = runs30d
            previousWindowRuns = allRuns.filter { $0.date >= sixtyDaysAgo && $0.date < thirtyDaysAgo }
        default:
            activeWindowRuns = allRuns
            previousWindowRuns = []
        }

        let totalDistanceMeters = activeWindowRuns.reduce(0.0) { $0 + $1.totalDistanceMeters }
        let totalDurationSeconds = activeWindowRuns.reduce(0.0) { $0 + $1.durationSeconds }
        let uniqueActiveDays = Set(activeWindowRuns.map { calendar.startOfDay(for: $0.date) })
        let activeDaysCount = uniqueActiveDays.count

        let total30dDistanceKm = runs30d.reduce(0.0) { $0 + $1.totalDistanceMeters } / 1000.0
        let weeksIn30d = 30.0 / 7.0
        let weeklyAvgKm = total30dDistanceKm / weeksIn30d
        let unique30dDays = Set(runs30d.map { calendar.startOfDay(for: $0.date) })
        let runsPerWeek = Double(unique30dDays.count) / weeksIn30d

        // 7-Day Daily Rhythm Buckets (strictly partitions runs7d so sum(days) == runs7d total)
        let todayStart = calendar.startOfDay(for: now)
        let letterFormatter = DateFormatter()
        letterFormatter.calendar = calendar
        letterFormatter.dateFormat = "EEEEE"
        letterFormatter.locale = Locale(identifier: "en_US_POSIX")

        let numberFormatter = DateFormatter()
        numberFormatter.calendar = calendar
        numberFormatter.dateFormat = "d"
        numberFormatter.locale = Locale(identifier: "en_US_POSIX")

        let dayOffsets = [6, 5, 4, 3, 2, 1, 0]
        let trailing7Days: [DayVolumeBucket] = dayOffsets.map { daysAgo in
            let dayDate = calendar.date(byAdding: .day, value: -daysAgo, to: todayStart) ?? todayStart
            let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayDate) ?? dayDate.addingTimeInterval(86400)
            let dayRuns: [VolumeRunSample]
            if daysAgo == 6 {
                dayRuns = runs7d.filter { $0.date < nextDayStart }
            } else if daysAgo == 0 {
                dayRuns = runs7d.filter { $0.date >= dayDate }
            } else {
                dayRuns = runs7d.filter { $0.date >= dayDate && $0.date < nextDayStart }
            }
            let dist = dayRuns.reduce(0.0) { $0 + $1.totalDistanceMeters }
            return DayVolumeBucket(
                id: "day-\(daysAgo)",
                date: dayDate,
                dayLetter: letterFormatter.string(from: dayDate),
                dayNumber: numberFormatter.string(from: dayDate),
                distanceMeters: dist,
                isToday: daysAgo == 0,
                hasRun: !dayRuns.isEmpty
            )
        }

        // 30-Day 4-Week Progression Buckets (discrete calendar weeks from TemporalSnapshotCore)
        let snapshot = TemporalSnapshotCore.evaluateSnapshot(runs: allRuns, now: now, calendar: calendar)
        let trailing4Weeks: [WeekVolumeBucket] = [
            WeekVolumeBucket(
                id: "w3",
                label: "3W Ago",
                distanceMeters: snapshot.threeWeeksAgo.totalDistanceMeters,
                runCount: snapshot.threeWeeksAgo.workoutCount
            ),
            WeekVolumeBucket(
                id: "w2",
                label: "2W Ago",
                distanceMeters: snapshot.twoWeeksAgo.totalDistanceMeters,
                runCount: snapshot.twoWeeksAgo.workoutCount
            ),
            WeekVolumeBucket(
                id: "w1",
                label: "Last Wk",
                distanceMeters: snapshot.lastWeek.totalDistanceMeters,
                runCount: snapshot.lastWeek.workoutCount
            ),
            WeekVolumeBucket(
                id: "w0",
                label: "This Wk",
                distanceMeters: snapshot.thisWeek.totalDistanceMeters,
                runCount: snapshot.thisWeek.workoutCount
            )
        ]

        // Classification Mix
        var counts: [String: Int] = [:]
        for run in activeWindowRuns {
            counts[run.classification, default: 0] += 1
        }
        let order = ["Easy Run", "Steady Effort", "Tempo Run", "Intervals", "Progression Run", "Long Run"]
        let classificationMix: [ClassificationCount] = order.compactMap { key in
            guard let count = counts[key], count > 0 else { return nil }
            return ClassificationCount(name: key, count: count)
        }

        // Duration-Weighted Baselines
        let baselineCadence = computeWeightedCadence(from: activeWindowRuns)
        let previousBaselineCadence = previousWindowRuns.isEmpty ? nil : computeWeightedCadence(from: previousWindowRuns)
        let baselinePace = computeWeightedPace(from: activeWindowRuns)
        let previousBaselinePace = previousWindowRuns.isEmpty ? nil : computeWeightedPace(from: previousWindowRuns)
        let baselineHeartRate = computeWeightedHeartRate(from: activeWindowRuns)

        // Workout Density Tier
        let workoutDensityTier: String = {
            if activeDaysCount == 0 { return "—" }
            if timeRange == "7 Days" {
                if activeDaysCount <= 2 { return "Low" }
                if activeDaysCount <= 3 { return "Moderate" }
                if activeDaysCount <= 5 { return "Optimal" }
                return "High"
            } else {
                if isTrajectoryEaseUp && activeDaysCount >= 14 { return "High" }
                if activeDaysCount <= 6 { return "Low" }
                if activeDaysCount <= 12 { return "Moderate" }
                if activeDaysCount <= 18 { return "Optimal" }
                return "High"
            }
        }()

        return MacroVolumeSummary(
            totalDistanceMeters: totalDistanceMeters,
            totalDurationSeconds: totalDurationSeconds,
            runCount: activeWindowRuns.count,
            activeDaysCount: activeDaysCount,
            weeklyAverageKm: weeklyAvgKm,
            runsPerWeek: runsPerWeek,
            trailing7Days: trailing7Days,
            trailing4Weeks: trailing4Weeks,
            classificationMix: classificationMix,
            baselineCadence: baselineCadence,
            previousBaselineCadence: previousBaselineCadence,
            baselinePace: baselinePace,
            previousBaselinePace: previousBaselinePace,
            baselineHeartRate: baselineHeartRate,
            workoutDensityTier: workoutDensityTier
        )
    }

    public static func evaluateDashboardTrajectory(
        assessment: TrajectoryAssessment,
        benchmark: GoalBenchmark,
        trainingGoal: String,
        paceContext: String
    ) -> DashboardTrajectorySynthesis {
        let volumeStatus = benchmark.weeklyVolumeStatus
        let weeklyAvgKm = benchmark.currentWeeklyKm
        let canonicalHeadline: String
        let badgeLabel: String
        let badgeTone: String
        let directiveCode: String
        let directiveContext: String
        let efficiencyContext: String
        let fallbackBody: String

        if assessment.verdict == .easeUp {
            canonicalHeadline = "Active Recovery Needed"
            badgeLabel = "Cumulative Strain"
            badgeTone = "red"
            directiveCode = "TRAJECTORY_EASE_UP"
            directiveContext = "TRAJECTORY_EASE_UP: Over the past 30 days, training data indicates cumulative overworking and declining efficiency (aerobic cost is climbing). For their stated goal of \(trainingGoal), tell the runner clearly that they are overworking and need to ease up on volume or intensity so their body can absorb the training and avoid declining instead of improving."
            efficiencyContext = "Efficiency Factor declined over the past month. Cardiac drift and physiological strain accumulating."
            fallbackBody = "Your recent training load shows accumulating fatigue and rising cardiac effort. Ease back on intensity this week so your body can absorb the work and rebound stronger."
        } else if volumeStatus == .building {
            canonicalHeadline = "Building Aerobic Base"
            badgeLabel = "Building Base"
            badgeTone = "blue"
            directiveCode = "TRAJECTORY_BUILDING_BASE"
            let efNote = assessment.efDelta > 0
                ? "Aerobic efficiency is improving (+\(String(format: "%.2f", assessment.efDelta)) m/beat), while weekly volume is building toward the target band."
                : "Aerobic base is in the building phase."
            directiveContext = "TRAJECTORY_BUILDING_BASE: The runner is actively building their aerobic foundation for the \(trainingGoal) goal. Currently averaging \(String(format: "%.1f", weeklyAvgKm)) km/wk, which is \(String(format: "%.1f", benchmark.volumeGapKm)) km below the \(Int(benchmark.targetWeeklyKmMin)) km/wk target minimum. Tell the runner clearly that they are in the 'Building Base' phase: their consistency is building momentum, and steady easy miles will help close the volume gap."
            efficiencyContext = "\(efNote) Volume gap: \(String(format: "%.1f", benchmark.volumeGapKm)) km."
            fallbackBody = "You are building a steady aerobic foundation toward your goal, though weekly mileage is still below the target band. Keep prioritizing relaxed, consistent Zone 2 sessions to safely expand your weekly volume."
        } else if volumeStatus == .exceeding {
            canonicalHeadline = "High Volume Capacity"
            badgeLabel = "Exceeding Target"
            badgeTone = "purple"
            directiveCode = "TRAJECTORY_EXCEEDING"
            directiveContext = "TRAJECTORY_EXCEEDING: The runner is averaging \(String(format: "%.1f", weeklyAvgKm)) km/wk, exceeding the target maximum (\(Int(benchmark.targetWeeklyKmMax)) km/wk) for their \(trainingGoal) goal. Commend their high capacity and advise smart recovery to avoid overtraining."
            efficiencyContext = "Weekly volume is high (\(String(format: "%.1f", weeklyAvgKm)) km/wk)."
            fallbackBody = "Your weekly volume exceeds the baseline target for your goal, demonstrating strong endurance capacity. Protect your recovery days to keep your legs fresh and resilient."
        } else {
            canonicalHeadline = "On Track For Goal"
            badgeLabel = "Aerobic Base Expanding"
            badgeTone = "green"
            directiveCode = "TRAJECTORY_ON_TRACK"
            let hrDeltaText = assessment.hrDelta < 0 ? "\(Int(abs(assessment.hrDelta))) BPM lower" : "stable"
            let vrDeltaText = assessment.avgRecentVR > 0 ? ", Vertical Ratio: \(String(format: "%.1f", assessment.avgRecentVR))%" : ""
            directiveContext = "TRAJECTORY_ON_TRACK: Over the past 30 days, aerobic efficiency, cardiac response, and running economy have clearly improved (Efficiency Factor increased by \(String(format: "%.2f", assessment.efDelta)), heart rate at \(paceContext) is \(hrDeltaText)\(vrDeltaText)) and weekly volume is on track for their \(trainingGoal) goal. Tell the runner clearly that they are solidly on track for their \(trainingGoal) goal and their consistency is paying off."
            efficiencyContext = "Efficiency Factor rose by +\(String(format: "%.2f", assessment.efDelta)) m/beat. Aerobic capacity expanding."
            fallbackBody = "You are solidly on track for your goal, with both weekly volume and aerobic efficiency moving in the right direction. Stay consistent with your rhythm and controlled effort."
        }

        let verticalOscillationContext: String
        if assessment.avgRecentVR > 0 {
            verticalOscillationContext = "Vertical Oscillation: \(String(format: "%.1f", assessment.avgRecentOsc)) cm (VR: \(String(format: "%.1f", assessment.avgRecentVR))%)"
        } else {
            verticalOscillationContext = assessment.avgRecentOsc > 0
                ? "Vertical Oscillation: \(String(format: "%.1f", assessment.avgRecentOsc)) cm"
                : "Vertical form steady"
        }

        return DashboardTrajectorySynthesis(
            verdict: assessment.verdict,
            volumeStatus: volumeStatus,
            canonicalHeadline: canonicalHeadline,
            badgeLabel: badgeLabel,
            badgeTone: badgeTone,
            directiveCode: directiveCode,
            directiveContext: directiveContext,
            efficiencyContext: efficiencyContext,
            verticalOscillationContext: verticalOscillationContext,
            fallbackBody: fallbackBody
        )
    }

    private static func computeWeightedCadence(from runs: [VolumeRunSample]) -> Int? {
        let valid = runs.filter { $0.workingAvgCadence > 0 }
        guard !valid.isEmpty else { return nil }
        let totalDuration = valid.reduce(0.0) { $0 + $1.durationSeconds }
        guard totalDuration > 0 else {
            return Int(valid.reduce(0.0) { $0 + $1.workingAvgCadence }) / valid.count
        }
        return Int(valid.reduce(0.0) { $0 + ($1.workingAvgCadence * $1.durationSeconds) } / totalDuration)
    }

    private static func computeWeightedPace(from runs: [VolumeRunSample]) -> Double? {
        let valid = runs.filter { $0.workingAvgPace > 0 }
        guard !valid.isEmpty else { return nil }
        let totalDuration = valid.reduce(0.0) { $0 + $1.durationSeconds }
        guard totalDuration > 0 else {
            return valid.reduce(0.0) { $0 + $1.workingAvgPace } / Double(valid.count)
        }
        return valid.reduce(0.0) { $0 + ($1.workingAvgPace * $1.durationSeconds) } / totalDuration
    }

    private static func computeWeightedHeartRate(from runs: [VolumeRunSample]) -> Int? {
        let valid = runs.filter { $0.workingAvgHeartRate > 0 }
        guard !valid.isEmpty else { return nil }
        let totalDuration = valid.reduce(0.0) { $0 + $1.durationSeconds }
        guard totalDuration > 0 else {
            return valid.reduce(0) { $0 + $1.workingAvgHeartRate } / valid.count
        }
        return Int(valid.reduce(0.0) { $0 + (Double($1.workingAvgHeartRate) * $1.durationSeconds) } / totalDuration)
    }
}
