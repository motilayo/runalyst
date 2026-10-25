import Foundation

// MARK: - Tool Projection Domain Shapes (Pure Data, Zero Prose)

/// Pure structured telemetry inspection payload for `inspectWorkout`.
public struct WorkoutInspectionTelemetry: Sendable, Codable, Equatable {
    public let workingDistanceMeters: Double
    public let workingDurationSeconds: Double
    public let workingAvgPaceSecondsPerKm: Double
    public let workingAvgCadenceSPM: Double
    public let workingAvgHeartRateBPM: Double
    public let rawTotalDistanceMeters: Double
    public let rawTotalDurationSeconds: Double
    public let deadStopsCount: Int
    public let paceCV: Double
    public let paceSlope: Double
    public let efficiencyFactor: Double?
    public let isIndoor: Bool
    public let needsInclineReview: Bool
    public let detectedClassification: String

    public init(
        workingDistanceMeters: Double,
        workingDurationSeconds: Double,
        workingAvgPaceSecondsPerKm: Double,
        workingAvgCadenceSPM: Double,
        workingAvgHeartRateBPM: Double,
        rawTotalDistanceMeters: Double,
        rawTotalDurationSeconds: Double,
        deadStopsCount: Int,
        paceCV: Double,
        paceSlope: Double,
        efficiencyFactor: Double?,
        isIndoor: Bool,
        needsInclineReview: Bool,
        detectedClassification: String
    ) {
        self.workingDistanceMeters = workingDistanceMeters
        self.workingDurationSeconds = workingDurationSeconds
        self.workingAvgPaceSecondsPerKm = workingAvgPaceSecondsPerKm
        self.workingAvgCadenceSPM = workingAvgCadenceSPM
        self.workingAvgHeartRateBPM = workingAvgHeartRateBPM
        self.rawTotalDistanceMeters = rawTotalDistanceMeters
        self.rawTotalDurationSeconds = rawTotalDurationSeconds
        self.deadStopsCount = deadStopsCount
        self.paceCV = paceCV
        self.paceSlope = paceSlope
        self.efficiencyFactor = efficiencyFactor
        self.isIndoor = isIndoor
        self.needsInclineReview = needsInclineReview
        self.detectedClassification = detectedClassification
    }
}

/// A discrete scheduled calendar day projection for `getTrainingSchedule`.
public struct ScheduledDayProjection: Sendable, Codable, Equatable {
    public let date: Date
    public let plannedTitle: String
    public let plannedMinutesMin: Int
    public let plannedMinutesMax: Int
    public let isRestDay: Bool
    public let completedMinutes: Double
    public let isCompleted: Bool

    public init(
        date: Date,
        plannedTitle: String,
        plannedMinutesMin: Int,
        plannedMinutesMax: Int,
        isRestDay: Bool,
        completedMinutes: Double,
        isCompleted: Bool
    ) {
        self.date = date
        self.plannedTitle = plannedTitle
        self.plannedMinutesMin = plannedMinutesMin
        self.plannedMinutesMax = plannedMinutesMax
        self.isRestDay = isRestDay
        self.completedMinutes = completedMinutes
        self.isCompleted = isCompleted
    }
}

/// Pure structured biological readiness and workload facts for `getReadinessAndWorkload`.
public struct ReadinessWorkloadProjection: Sendable, Codable, Equatable {
    public let readinessState: String
    public let acwr: Double?
    public let acwrZone: ACWRZone?
    public let streakDays: Int
    public let streakLimit: Int
    public let last48hMinutes: Double
    public let trailingWeeklyMinutes: Double
    public let volumeRatio48h: Double
    public let hrDecouplingBPM: Double
    public let todayCompletedMinutes: Double
    public let todayTargetMinutes: Int
    public let secondRunAdvisable: Bool
    public let limitingFactors: [String]
    public let cadenceFloorSPM: Int
    public let safetyOverrideDirective: RunDirective?

    public init(
        readinessState: String,
        acwr: Double?,
        acwrZone: ACWRZone?,
        streakDays: Int,
        streakLimit: Int,
        last48hMinutes: Double,
        trailingWeeklyMinutes: Double,
        volumeRatio48h: Double,
        hrDecouplingBPM: Double,
        todayCompletedMinutes: Double,
        todayTargetMinutes: Int,
        secondRunAdvisable: Bool,
        limitingFactors: [String],
        cadenceFloorSPM: Int,
        safetyOverrideDirective: RunDirective? = nil
    ) {
        self.readinessState = readinessState
        self.acwr = acwr
        self.acwrZone = acwrZone
        self.streakDays = streakDays
        self.streakLimit = streakLimit
        self.last48hMinutes = last48hMinutes
        self.trailingWeeklyMinutes = trailingWeeklyMinutes
        self.volumeRatio48h = volumeRatio48h
        self.hrDecouplingBPM = hrDecouplingBPM
        self.todayCompletedMinutes = todayCompletedMinutes
        self.todayTargetMinutes = todayTargetMinutes
        self.secondRunAdvisable = secondRunAdvisable
        self.limitingFactors = limitingFactors
        self.cadenceFloorSPM = cadenceFloorSPM
        self.safetyOverrideDirective = safetyOverrideDirective
    }
}

/// Mathematical comparison between two historical workouts for `queryWorkoutHistory`.
public struct WorkoutHistoryComparison: Sendable, Codable, Equatable {
    public let paceDeltaSecondsPerKm: Double
    public let cadenceDeltaSPM: Double
    public let heartRateDeltaBPM: Double
    public let distanceDeltaMeters: Double
    public let durationDeltaSeconds: Double
    public let efficiencyRatio: Double?
    public let daysBetweenRuns: Int

    public init(
        paceDeltaSecondsPerKm: Double,
        cadenceDeltaSPM: Double,
        heartRateDeltaBPM: Double,
        distanceDeltaMeters: Double,
        durationDeltaSeconds: Double,
        efficiencyRatio: Double?,
        daysBetweenRuns: Int
    ) {
        self.paceDeltaSecondsPerKm = paceDeltaSecondsPerKm
        self.cadenceDeltaSPM = cadenceDeltaSPM
        self.heartRateDeltaBPM = heartRateDeltaBPM
        self.distanceDeltaMeters = distanceDeltaMeters
        self.durationDeltaSeconds = durationDeltaSeconds
        self.efficiencyRatio = efficiencyRatio
        self.daysBetweenRuns = daysBetweenRuns
    }
}

/// Structured outcome of a coach action evaluation for `executeCoachAction`.
public struct CoachActionOutcome: Sendable, Codable, Equatable {
    public let action: String
    public let statusCode: String
    public let effectiveDirective: RunDirective?
    public let isSafetyOverridden: Bool
    public let payload: String?

    public init(
        action: String,
        statusCode: String,
        effectiveDirective: RunDirective? = nil,
        isSafetyOverridden: Bool = false,
        payload: String? = nil
    ) {
        self.action = action
        self.statusCode = statusCode
        self.effectiveDirective = effectiveDirective
        self.isSafetyOverridden = isSafetyOverridden
        self.payload = payload
    }
}

// MARK: - Orthogonal Tools Core

/// Pure sports science computation engine fulfilling the data contracts for AI model tool calling.
/// Emits raw domain values, status enums, and mathematical diffs with zero conversational prose.
public enum OrthogonalToolsCore {

    /// Projects a `WorkingStats` domain ingot into the pure data payload for `inspectWorkout`.
    public static func inspectWorkout(stats: WorkingStats) -> WorkoutInspectionTelemetry {
        WorkoutInspectionTelemetry(
            workingDistanceMeters: stats.workingDistanceMeters,
            workingDurationSeconds: stats.workingDurationSeconds,
            workingAvgPaceSecondsPerKm: stats.workingAvgPaceSecondsPerKm,
            workingAvgCadenceSPM: stats.workingAvgCadenceSPM,
            workingAvgHeartRateBPM: stats.workingAvgHeartRateBPM,
            rawTotalDistanceMeters: stats.rawTotalDistanceMeters,
            rawTotalDurationSeconds: stats.rawTotalDurationSeconds,
            deadStopsCount: stats.deadStopsCount,
            paceCV: stats.paceCV,
            paceSlope: stats.paceSlope,
            efficiencyFactor: stats.efficiencyFactor,
            isIndoor: stats.isIndoor,
            needsInclineReview: stats.needsInclineReview,
            detectedClassification: stats.detectedClassification
        )
    }

    /// Evaluates biological readiness, ACWR, and volume constraints for `getReadinessAndWorkload`.
    public static func getReadinessAndWorkload(
        sessions: [WorkloadSession],
        now: Date,
        todayCompletedMinutes: Double,
        todayTargetMinutes: Int,
        cadenceFloorSPM: Int = 150,
        streakDays: Int = 0,
        streakLimit: Int = 6,
        userDistress: SubjectiveDistressSignal? = nil,
        paceDeltaVsBaseline: Double? = nil,
        hrDeltaVsBaseline: Double? = nil
    ) -> ReadinessWorkloadProjection {
        let readinessReport = BanisterReadinessCore.evaluateSafetyGate(
            sessions: sessions,
            now: now,
            paceDeltaVsBaseline: paceDeltaVsBaseline,
            hrDeltaVsBaseline: hrDeltaVsBaseline,
            subjectiveDistress: userDistress
        )

        let dayInterval: TimeInterval = 24 * 3600
        let cal = Calendar(identifier: .gregorian)
        let startOfToday = cal.startOfDay(for: now)
        let cutoff48h = cal.date(byAdding: .day, value: -2, to: startOfToday) ?? now.addingTimeInterval(-48 * 3600)
        let last48hSessions = sessions.filter { $0.date >= cutoff48h && $0.date <= now }
        let last48hMins = last48hSessions.map(\.durationMinutes).reduce(0.0, +)

        let cutoff28d = now.addingTimeInterval(-28 * dayInterval)
        let pastSessions = sessions.filter { $0.date >= cutoff28d && $0.date <= now }
        let trailingWeeklyMins = pastSessions.map(\.durationMinutes).reduce(0.0, +) / 4.0

        let volumeRatio48h = trailingWeeklyMins > 0 ? (last48hMins / trailingWeeklyMins) : 0.0

        var limitingFactors: [String] = []
        if readinessReport.isSafetyOverridden {
            limitingFactors.append("safety_override_triggered")
        }
        if streakDays >= streakLimit {
            limitingFactors.append("streak_limit_reached")
        }
        if volumeRatio48h >= 0.50 {
            limitingFactors.append("48h_volume_compression")
        }
        if todayTargetMinutes > 0 && (todayCompletedMinutes / Double(todayTargetMinutes)) >= 0.80 {
            limitingFactors.append("daily_volume_satisfied")
        }

        let isOverridden = readinessReport.isSafetyOverridden
        let secondRunAdvisable: Bool
        if isOverridden || streakDays >= streakLimit || volumeRatio48h >= 0.50 || todayCompletedMinutes <= 0.0 {
            secondRunAdvisable = false
        } else if todayCompletedMinutes <= 20.0 && todayTargetMinutes > 20 {
            secondRunAdvisable = true
        } else {
            secondRunAdvisable = false
        }

        let readinessStateStr: String
        if isOverridden {
            readinessStateStr = "distress"
        } else if let zone = readinessReport.zone {
            switch zone {
            case .low: readinessStateStr = "low"
            case .optimal: readinessStateStr = "productive"
            case .elevated: readinessStateStr = "elevated"
            case .spike: readinessStateStr = "acuteFatigue"
            }
        } else {
            readinessStateStr = "calibrating"
        }

        let hrDecoupling = (hrDeltaVsBaseline ?? 0.0)

        return ReadinessWorkloadProjection(
            readinessState: readinessStateStr,
            acwr: readinessReport.acwr,
            acwrZone: readinessReport.zone,
            streakDays: streakDays,
            streakLimit: streakLimit,
            last48hMinutes: last48hMins,
            trailingWeeklyMinutes: trailingWeeklyMins,
            volumeRatio48h: volumeRatio48h,
            hrDecouplingBPM: hrDecoupling,
            todayCompletedMinutes: todayCompletedMinutes,
            todayTargetMinutes: todayTargetMinutes,
            secondRunAdvisable: secondRunAdvisable,
            limitingFactors: limitingFactors,
            cadenceFloorSPM: cadenceFloorSPM,
            safetyOverrideDirective: isOverridden ? readinessReport.effectiveDirective : nil
        )
    }

    /// Evaluates chronological or performance telemetry deltas between two workouts for `queryWorkoutHistory`.
    public static func compareWorkouts(
        current: WorkingStats,
        currentDate: Date,
        prior: WorkingStats,
        priorDate: Date
    ) -> WorkoutHistoryComparison {
        let paceDiff = current.workingAvgPaceSecondsPerKm - prior.workingAvgPaceSecondsPerKm
        let cadDiff = current.workingAvgCadenceSPM - prior.workingAvgCadenceSPM
        let hrDiff = current.workingAvgHeartRateBPM - prior.workingAvgHeartRateBPM
        let distDiff = current.workingDistanceMeters - prior.workingDistanceMeters
        let durDiff = current.workingDurationSeconds - prior.workingDurationSeconds

        let effRatio: Double? = {
            guard let curEff = current.efficiencyFactor, let priorEff = prior.efficiencyFactor, priorEff > 0 else {
                return nil
            }
            return curEff / priorEff
        }()

        let days = max(0, Int(round(abs(currentDate.timeIntervalSince(priorDate)) / (24 * 3600))))

        return WorkoutHistoryComparison(
            paceDeltaSecondsPerKm: paceDiff,
            cadenceDeltaSPM: cadDiff,
            heartRateDeltaBPM: hrDiff,
            distanceDeltaMeters: distDiff,
            durationDeltaSeconds: durDiff,
            efficiencyRatio: effRatio,
            daysBetweenRuns: days
        )
    }

    /// Evaluates scheduled timeline days within a continuous date interval for `getTrainingSchedule`.
    public static func projectSchedule(
        from: Date,
        to: Date,
        plannedSessions: [(date: Date, title: String, minMinutes: Int, maxMinutes: Int, isRest: Bool)],
        completedSessions: [(date: Date, durationMinutes: Double)]
    ) -> [ScheduledDayProjection] {
        let dayInterval: TimeInterval = 24 * 3600
        var projections: [ScheduledDayProjection] = []

        var cursor = from
        while cursor <= to {
            let nextDay = cursor.addingTimeInterval(dayInterval)

            let matchedPlan = plannedSessions.first { $0.date >= cursor && $0.date < nextDay }
            let completed = completedSessions
                .filter { $0.date >= cursor && $0.date < nextDay }
                .map(\.durationMinutes)
                .reduce(0.0, +)

            let title = matchedPlan?.title ?? (completed > 0 ? "Logged Workout" : "Rest Day")
            let minMin = matchedPlan?.minMinutes ?? 0
            let maxMin = matchedPlan?.maxMinutes ?? 0
            let isRest = matchedPlan?.isRest ?? (completed == 0)
            let isCompleted = completed > 0

            projections.append(ScheduledDayProjection(
                date: cursor,
                plannedTitle: title,
                plannedMinutesMin: minMin,
                plannedMinutesMax: maxMin,
                isRestDay: isRest,
                completedMinutes: completed,
                isCompleted: isCompleted
            ))

            cursor = nextDay
        }

        return projections
    }

    /// Evaluates a coach action request against safety gates for `executeCoachAction`.
    public static func executeCoachAction(
        action: String,
        requestedDirective: RunDirective?,
        safetyReport: BanisterReadinessReport,
        payload: String? = nil
    ) -> CoachActionOutcome {
        if safetyReport.isSafetyOverridden {
            return CoachActionOutcome(
                action: action,
                statusCode: "overridden_by_safety",
                effectiveDirective: safetyReport.effectiveDirective,
                isSafetyOverridden: true,
                payload: payload
            )
        }

        return CoachActionOutcome(
            action: action,
            statusCode: "action_executed",
            effectiveDirective: requestedDirective,
            isSafetyOverridden: false,
            payload: payload
        )
    }
}
