import Foundation

public enum GoalVolumeStatus: String, Sendable, Codable, Equatable {
    case building
    case onTrack = "on_track"
    case exceeding

    public var displayText: String {
        switch self {
        case .building: return "Building Base"
        case .onTrack: return "On Track"
        case .exceeding: return "Exceeding Target"
        }
    }
}

public struct GoalReadinessPresentationSpec: Sendable, Codable, Equatable {
    public let statusLabel: String
    public let statusTone: String
    public let progressRatio: Double
    public let progressTitle: String
    public let progressValueFormatted: String
    public let percentageFormatted: String
    public let weeklyVolumeTitle: String
    public let weeklyVolumeFormatted: String
    public let secondaryIcon: String
    public let secondaryTitle: String
    public let secondaryValueFormatted: String
    public let secondaryTone: String
    public let coachingRationale: String

    public init(
        statusLabel: String,
        statusTone: String,
        progressRatio: Double,
        progressTitle: String,
        progressValueFormatted: String,
        percentageFormatted: String,
        weeklyVolumeTitle: String = "30-DAY WEEKLY AVG",
        weeklyVolumeFormatted: String,
        secondaryIcon: String,
        secondaryTitle: String,
        secondaryValueFormatted: String,
        secondaryTone: String,
        coachingRationale: String
    ) {
        self.statusLabel = statusLabel
        self.statusTone = statusTone
        self.progressRatio = progressRatio
        self.progressTitle = progressTitle
        self.progressValueFormatted = progressValueFormatted
        self.percentageFormatted = percentageFormatted
        self.weeklyVolumeTitle = weeklyVolumeTitle
        self.weeklyVolumeFormatted = weeklyVolumeFormatted
        self.secondaryIcon = secondaryIcon
        self.secondaryTitle = secondaryTitle
        self.secondaryValueFormatted = secondaryValueFormatted
        self.secondaryTone = secondaryTone
        self.coachingRationale = coachingRationale
    }
}

public struct GoalBenchmark: Sendable, Codable, Equatable {
    public let goalName: String
    public let targetWeeklyKmMin: Double
    public let targetWeeklyKmMax: Double
    public let targetLongRunKmMin: Double
    public let targetLongRunKmMax: Double
    public let primaryStimulus: String
    public let targetCadenceBand: String
    public let targetAerobicSharePercent: Int

    public let currentWeeklyKm: Double
    public let currentLongRunKm: Double
    public let weeklyVolumeStatus: GoalVolumeStatus
    public let longRunStatus: GoalVolumeStatus
    public let volumeGapKm: Double
    public let coachingDirective: String

    public init(
        goalName: String,
        targetWeeklyKmMin: Double,
        targetWeeklyKmMax: Double,
        targetLongRunKmMin: Double,
        targetLongRunKmMax: Double,
        primaryStimulus: String,
        targetCadenceBand: String,
        targetAerobicSharePercent: Int,
        currentWeeklyKm: Double,
        currentLongRunKm: Double,
        weeklyVolumeStatus: GoalVolumeStatus,
        longRunStatus: GoalVolumeStatus,
        volumeGapKm: Double,
        coachingDirective: String
    ) {
        self.goalName = goalName
        self.targetWeeklyKmMin = targetWeeklyKmMin
        self.targetWeeklyKmMax = targetWeeklyKmMax
        self.targetLongRunKmMin = targetLongRunKmMin
        self.targetLongRunKmMax = targetLongRunKmMax
        self.primaryStimulus = primaryStimulus
        self.targetCadenceBand = targetCadenceBand
        self.targetAerobicSharePercent = targetAerobicSharePercent
        self.currentWeeklyKm = currentWeeklyKm
        self.currentLongRunKm = currentLongRunKm
        self.weeklyVolumeStatus = weeklyVolumeStatus
        self.longRunStatus = longRunStatus
        self.volumeGapKm = volumeGapKm
        self.coachingDirective = coachingDirective
    }
}

public enum GoalBenchmarkCore {
    public static func calculateExperienceLevel(
        totalRunsCount: Int,
        weeklyAvgKm: Double,
        runsPerWeek: Double,
        longestRunKm: Double,
        fastestPaceSec: Double
    ) -> String {
        guard totalRunsCount > 0 else {
            return "Novice / Beginner"
        }

        if (weeklyAvgKm >= 60.0 && runsPerWeek >= 4.5 && longestRunKm >= 18.0) ||
           (weeklyAvgKm >= 45.0 && fastestPaceSec <= 250.0 && longestRunKm >= 20.0) {
            return "Competitive / Elite"
        }

        if (weeklyAvgKm >= 32.0 && runsPerWeek >= 3.2 && totalRunsCount >= 12 && longestRunKm >= 12.0) ||
           (weeklyAvgKm >= 28.0 && longestRunKm >= 16.0 && totalRunsCount >= 15) {
            return "Advanced / Veteran"
        }

        if (totalRunsCount >= 5 && longestRunKm >= 4.5 && (weeklyAvgKm >= 10.0 || runsPerWeek >= 1.8)) ||
           (totalRunsCount >= 8 && longestRunKm >= 5.0) {
            return "Intermediate / Enthusiast"
        }

        return "Novice / Beginner"
    }

    public static func evaluate(
        goal: String,
        currentWeeklyKm: Double,
        longestRunKm: Double,
        userHeightCm: Double = 175.0,
        experienceLevel: String = "Intermediate / Enthusiast"
    ) -> GoalBenchmark {
        let normalizedGoal = goal.lowercased()
        let heightScale = max(130.0, min(220.0, userHeightCm)) / 175.0
        let baseCadence = Int((150.0 / heightScale).rounded())

        let targetWeeklyMin: Double
        let targetWeeklyMax: Double
        let targetLongMin: Double
        let targetLongMax: Double
        let stimulus: String
        let cadenceBand: String
        let aerobicShare: Int

        if normalizedGoal.contains("5k") {
            targetWeeklyMin = 15.0
            targetWeeklyMax = 28.0
            targetLongMin = 7.0
            targetLongMax = 10.0
            stimulus = "Neuromuscular turnover and VO2 max threshold intervals"
            cadenceBand = "\(baseCadence + 5)–\(baseCadence + 15) SPM"
            aerobicShare = 75
        } else if normalizedGoal.contains("10k") {
            targetWeeklyMin = 25.0
            targetWeeklyMax = 42.0
            targetLongMin = 10.0
            targetLongMax = 15.0
            stimulus = "Lactate threshold tempo runs and steady aerobic volume"
            cadenceBand = "\(baseCadence + 3)–\(baseCadence + 12) SPM"
            aerobicShare = 80
        } else if normalizedGoal.contains("half") {
            targetWeeklyMin = 35.0
            targetWeeklyMax = 55.0
            targetLongMin = 15.0
            targetLongMax = 20.0
            stimulus = "Progressive long runs, tempo stamina, and aerobic resilience"
            cadenceBand = "\(baseCadence)–\(baseCadence + 10) SPM"
            aerobicShare = 80
        } else if normalizedGoal.contains("marathon") {
            targetWeeklyMin = 45.0
            targetWeeklyMax = 75.0
            targetLongMin = 22.0
            targetLongMax = 32.0
            stimulus = "Long weekend endurance builds, fat oxidation, and cumulative fatigue adaptation"
            cadenceBand = "\(baseCadence)–\(baseCadence + 8) SPM"
            aerobicShare = 85
        } else if normalizedGoal.contains("injury") || normalizedGoal.contains("recovery") {
            targetWeeklyMin = 5.0
            targetWeeklyMax = 15.0
            targetLongMin = 3.0
            targetLongMax = 6.0
            stimulus = "Low-impact aerobic flushing, high turnover to protect joints, and soft surface running"
            cadenceBand = "\(baseCadence + 5)–\(baseCadence + 10) SPM"
            aerobicShare = 95
        } else if normalizedGoal.contains("fun") {
            targetWeeklyMin = 10.0
            targetWeeklyMax = 25.0
            targetLongMin = 5.0
            targetLongMax = 8.0
            stimulus = "Conversational running, consistency, and aerobic health"
            cadenceBand = "\(baseCadence)–\(baseCadence + 8) SPM"
            aerobicShare = 90
        } else {
            targetWeeklyMin = 15.0
            targetWeeklyMax = 30.0
            targetLongMin = 8.0
            targetLongMax = 12.0
            stimulus = "Zone 2 aerobic foundation, mitochondrial density, and musculoskeletal conditioning"
            cadenceBand = "\(baseCadence)–\(baseCadence + 10) SPM"
            aerobicShare = 85
        }

        let volumeStatus: GoalVolumeStatus
        let volumeGap: Double
        if currentWeeklyKm < targetWeeklyMin {
            volumeStatus = .building
            volumeGap = max(0.0, targetWeeklyMin - currentWeeklyKm)
        } else if currentWeeklyKm > targetWeeklyMax {
            volumeStatus = .exceeding
            volumeGap = 0.0
        } else {
            volumeStatus = .onTrack
            volumeGap = 0.0
        }

        let longStatus: GoalVolumeStatus
        if longestRunKm < targetLongMin {
            longStatus = .building
        } else if longestRunKm > targetLongMax {
            longStatus = .exceeding
        } else {
            longStatus = .onTrack
        }

        let directive: String
        switch volumeStatus {
        case .building:
            directive = "Currently building towards the \(goal) foundation. Progress weekly volume gradually (+10% weekly max) and prioritize steady Zone 2."
        case .onTrack:
            directive = "Weekly volume is on track for \(goal). Focus on \(stimulus.lowercased()) and maintaining consistent rhythm."
        case .exceeding:
            directive = "Training volume exceeds the \(goal) baseline. Primed for pacing progression or considering an advanced training tier."
        }

        return GoalBenchmark(
            goalName: goal,
            targetWeeklyKmMin: targetWeeklyMin,
            targetWeeklyKmMax: targetWeeklyMax,
            targetLongRunKmMin: targetLongMin,
            targetLongRunKmMax: targetLongMax,
            primaryStimulus: stimulus,
            targetCadenceBand: cadenceBand,
            targetAerobicSharePercent: aerobicShare,
            currentWeeklyKm: currentWeeklyKm,
            currentLongRunKm: longestRunKm,
            weeklyVolumeStatus: volumeStatus,
            longRunStatus: longStatus,
            volumeGapKm: volumeGap,
            coachingDirective: directive
        )
    }

    public static func evaluateReadinessSpec(
        benchmark: GoalBenchmark,
        runsPerWeek: Double,
        hasAnyRuns: Bool,
        recentEasyRunRatio: Double = 1.0,
        recentAvgCadence: Int = 0,
        useMetricSystem: Bool = true
    ) -> GoalReadinessPresentationSpec {
        let weeklyAvgKm = benchmark.currentWeeklyKm
        let longestRecentRunKm = benchmark.currentLongRunKm
        let weeklyAvgDistanceFormatted = formatDistance(km: weeklyAvgKm, useMetricSystem: useMetricSystem) + "/wk"

        guard hasAnyRuns else {
            return GoalReadinessPresentationSpec(
                statusLabel: "Needs Data",
                statusTone: "secondary",
                progressRatio: 0.0,
                progressTitle: "Initial Evaluation",
                progressValueFormatted: formatDistance(km: 0.0, useMetricSystem: useMetricSystem),
                percentageFormatted: "0%",
                weeklyVolumeFormatted: "0.0 " + (useMetricSystem ? "km" : "mi") + "/wk",
                secondaryIcon: "figure.run",
                secondaryTitle: "LONGEST RUN",
                secondaryValueFormatted: "—",
                secondaryTone: "purple",
                coachingRationale: "Complete your first recorded run to activate goal tracking and progress insights."
            )
        }

        switch benchmark.goalName {
        case "5K Race":
            return evaluateRaceSpec(
                benchmark: benchmark,
                targetKm: 5.0,
                simulationTargetKm: 5.0,
                readyLongRunThresholdKm: 4.5,
                onTrackLongRunThresholdKm: 3.0,
                useMetricSystem: useMetricSystem,
                weeklyAvgDistanceFormatted: weeklyAvgDistanceFormatted,
                secondaryIcon: "stopwatch.fill"
            )
        case "10K Race":
            return evaluateRaceSpec(
                benchmark: benchmark,
                targetKm: 10.0,
                simulationTargetKm: 10.0,
                readyLongRunThresholdKm: 9.0,
                onTrackLongRunThresholdKm: 6.0,
                useMetricSystem: useMetricSystem,
                weeklyAvgDistanceFormatted: weeklyAvgDistanceFormatted,
                secondaryIcon: "stopwatch.fill"
            )
        case "Half Marathon":
            return evaluateRaceSpec(
                benchmark: benchmark,
                targetKm: 21.097,
                simulationTargetKm: 18.0,
                readyLongRunThresholdKm: 16.0,
                onTrackLongRunThresholdKm: 10.0,
                useMetricSystem: useMetricSystem,
                weeklyAvgDistanceFormatted: weeklyAvgDistanceFormatted,
                secondaryIcon: "figure.run"
            )
        case "Marathon":
            return evaluateRaceSpec(
                benchmark: benchmark,
                targetKm: 42.195,
                simulationTargetKm: 32.0,
                readyLongRunThresholdKm: 28.0,
                onTrackLongRunThresholdKm: 18.0,
                useMetricSystem: useMetricSystem,
                weeklyAvgDistanceFormatted: weeklyAvgDistanceFormatted,
                secondaryIcon: "figure.run"
            )
        case "Injury Recovery":
            let targetRatio = 0.85
            let progressRatio = min(1.0, recentEasyRunRatio / targetRatio)
            let percentInt = Int((recentEasyRunRatio * 100).rounded())
            let status = recentEasyRunRatio >= 0.75 ? ("Protected", "green") : ("Caution", "orange")
            let cadenceText = recentAvgCadence > 0 ? "\(recentAvgCadence) SPM" : "—"
            return GoalReadinessPresentationSpec(
                statusLabel: status.0,
                statusTone: status.1,
                progressRatio: progressRatio,
                progressTitle: "Aerobic Control Adherence",
                progressValueFormatted: "\(percentInt)% Easy Volume",
                percentageFormatted: "\(Int((progressRatio * 100).rounded()))%",
                weeklyVolumeFormatted: weeklyAvgDistanceFormatted,
                secondaryIcon: "metronome.fill",
                secondaryTitle: "AVG CADENCE",
                secondaryValueFormatted: cadenceText,
                secondaryTone: "teal",
                coachingRationale: "Low aerobic strain and controlled cadence protect joints while allowing biological tissues to adapt safely."
            )
        case "Just for Fun":
            let targetWeeklyRuns = 3.0
            let ratio = min(1.0, runsPerWeek / targetWeeklyRuns)
            let percentInt = Int((ratio * 100).rounded())
            let status = ratio >= 0.8 ? ("Active", "green") : ("Building", "blue")
            let frequencyText = String(format: "%.1f runs/wk", runsPerWeek)
            return GoalReadinessPresentationSpec(
                statusLabel: status.0,
                statusTone: status.1,
                progressRatio: ratio,
                progressTitle: "Weekly Consistency",
                progressValueFormatted: frequencyText,
                percentageFormatted: "\(percentInt)%",
                weeklyVolumeFormatted: weeklyAvgDistanceFormatted,
                secondaryIcon: "flame.fill",
                secondaryTitle: "FREQUENCY",
                secondaryValueFormatted: frequencyText,
                secondaryTone: "orange",
                coachingRationale: "Enjoying the rhythm of running. Consistent relaxed outings build lasting vitality and mental clarity."
            )
        default:
            let targetWeeklyKm = benchmark.targetWeeklyKmMax
            let ratio = min(1.0, weeklyAvgKm / targetWeeklyKm)
            let percentInt = Int((ratio * 100).rounded())
            let status: (String, String)
            let note: String
            switch benchmark.weeklyVolumeStatus {
            case .exceeding:
                status = ("Exceeding Target", "purple")
                note = "Weekly aerobic volume (\(weeklyAvgDistanceFormatted)) exceeds the baseline band. High endurance capacity established."
            case .onTrack:
                status = ("Solid Base", "green")
                note = "Aerobic engine is solidly established. You have built a durable foundation for structured quality workouts or race blocks."
            case .building:
                status = ("Building Base", "blue")
                note = "Steadily expanding weekly volume toward \(Int(benchmark.targetWeeklyKmMin)) km/wk. Keep runs primarily in Zone 2 to stimulate mitochondrial density without fatigue."
            }
            return GoalReadinessPresentationSpec(
                statusLabel: status.0,
                statusTone: status.1,
                progressRatio: ratio,
                progressTitle: "Weekly Aerobic Base",
                progressValueFormatted: "\(formatDistance(km: weeklyAvgKm, useMetricSystem: useMetricSystem)) / \(formatDistance(km: targetWeeklyKm, useMetricSystem: useMetricSystem))",
                percentageFormatted: "\(percentInt)%",
                weeklyVolumeFormatted: weeklyAvgDistanceFormatted,
                secondaryIcon: "figure.run",
                secondaryTitle: "LONGEST RUN",
                secondaryValueFormatted: formatDistance(km: longestRecentRunKm, useMetricSystem: useMetricSystem),
                secondaryTone: "purple",
                coachingRationale: note
            )
        }
    }

    private static func evaluateRaceSpec(
        benchmark: GoalBenchmark,
        targetKm: Double,
        simulationTargetKm: Double,
        readyLongRunThresholdKm: Double,
        onTrackLongRunThresholdKm: Double,
        useMetricSystem: Bool,
        weeklyAvgDistanceFormatted: String,
        secondaryIcon: String
    ) -> GoalReadinessPresentationSpec {
        let longestRecentRunKm = benchmark.currentLongRunKm
        let ratio = min(1.0, longestRecentRunKm / simulationTargetKm)
        let percentInt = Int((min(1.0, longestRecentRunKm / targetKm) * 100).rounded())
        let status: (String, String)
        let note: String

        if benchmark.weeklyVolumeStatus == .building {
            status = ("Building Base", "blue")
            if longestRecentRunKm >= readyLongRunThresholdKm {
                note = "Strong single-run endurance (\(formatDistance(km: longestRecentRunKm, useMetricSystem: useMetricSystem))), but weekly volume (\(weeklyAvgDistanceFormatted)) is still building toward the \(Int(benchmark.targetWeeklyKmMin)) km/wk foundation to sustain \(benchmark.goalName) stamina."
            } else {
                note = "Building endurance capability. Gradually increase your weekly volume toward \(Int(benchmark.targetWeeklyKmMin)) km/wk while keeping heart rate strictly controlled."
            }
        } else if longestRecentRunKm >= readyLongRunThresholdKm {
            status = ("Race Ready", "green")
            note = "You have established strong \(benchmark.goalName) endurance and consistent volume. Maintain smooth turnover rhythm and consolidate threshold efficiency."
        } else if longestRecentRunKm >= onTrackLongRunThresholdKm {
            status = ("On Track", "green")
            note = "Endurance progression is on track. Gradually increase your long run toward \(formatDistance(km: simulationTargetKm, useMetricSystem: useMetricSystem)) while keeping heart rate strictly controlled."
        } else {
            status = ("Building Base", "blue")
            note = "Building endurance capability. Gradually increase your long run toward \(formatDistance(km: simulationTargetKm, useMetricSystem: useMetricSystem)) while keeping heart rate strictly controlled."
        }

        return GoalReadinessPresentationSpec(
            statusLabel: status.0,
            statusTone: status.1,
            progressRatio: ratio,
            progressTitle: "Longest Prep Run",
            progressValueFormatted: "\(formatDistance(km: longestRecentRunKm, useMetricSystem: useMetricSystem)) / \(formatDistance(km: targetKm, useMetricSystem: useMetricSystem))",
            percentageFormatted: "\(percentInt)%",
            weeklyVolumeFormatted: weeklyAvgDistanceFormatted,
            secondaryIcon: secondaryIcon,
            secondaryTitle: "LONGEST RUN",
            secondaryValueFormatted: formatDistance(km: longestRecentRunKm, useMetricSystem: useMetricSystem),
            secondaryTone: "purple",
            coachingRationale: note
        )
    }

    public static func formatDistance(km: Double, useMetricSystem: Bool) -> String {
        if useMetricSystem {
            return String(format: "%.1f km", km)
        } else {
            let mi = km * 0.621371
            return String(format: "%.1f mi", mi)
        }
    }
}
