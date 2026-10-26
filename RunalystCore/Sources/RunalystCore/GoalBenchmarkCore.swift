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
            // Default: Base Building
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
}
