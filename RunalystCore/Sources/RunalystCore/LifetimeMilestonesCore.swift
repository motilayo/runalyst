import Foundation

// MARK: - Lifetime Milestones Domain Types

public struct MilestoneRunSample: Sendable, Codable, Equatable {
    public let id: UUID
    public let date: Date
    public let totalDistanceMeters: Double
    public let durationSeconds: Double
    public let workingAvgPace: Double
    public let workingAvgCadence: Double
    public let efficiencyFactor: Double?

    public init(
        id: UUID,
        date: Date,
        totalDistanceMeters: Double,
        durationSeconds: Double,
        workingAvgPace: Double = 0.0,
        workingAvgCadence: Double = 0.0,
        efficiencyFactor: Double? = nil
    ) {
        self.id = id
        self.date = date
        self.totalDistanceMeters = totalDistanceMeters
        self.durationSeconds = durationSeconds
        self.workingAvgPace = workingAvgPace
        self.workingAvgCadence = workingAvgCadence
        self.efficiencyFactor = efficiencyFactor
    }
}

public enum MilestoneBadgeIdentifier: String, Sendable, Codable, CaseIterable {
    case firstRun = "first_run"
    case fiveK = "five_k"
    case tenK = "ten_k"
    case halfMarathon = "half_marathon"
    case centuryVolume = "century_volume"
    case fiveHundredK = "five_hundred_k"
    // swiftlint:disable:next inclusive_language
    case rhythmMaster = "rhythm_master"
    case aerobicEngine = "aerobic_engine"
    case consistency = "consistency"
}

public enum MilestoneMedallionShape: String, Sendable, Codable, Equatable {
    case circleRecord
    case splitHorizonDistance
    case hexagonStreak
}

public struct MilestoneBadgeSpec: Sendable, Codable, Equatable, Identifiable {
    public var id: String { identifier.rawValue }
    public let identifier: MilestoneBadgeIdentifier
    public let title: String
    public let iconName: String
    public let description: String
    public let isUnlocked: Bool
    public let accentColorName: String
    public let medallionShape: MilestoneMedallionShape
    public let timesEarnedCount: Int
    public let progressFraction: Double
    public let qualifyingRunID: UUID?
    public let qualifyingDate: Date?
    public let qualifyingDistanceMeters: Double?
    public let qualifyingDurationSeconds: Double?
    public let qualifyingCadenceSPM: Double?
    public let qualifyingEfficiencyFactor: Double?

    public init(
        identifier: MilestoneBadgeIdentifier,
        title: String,
        iconName: String,
        description: String,
        isUnlocked: Bool,
        accentColorName: String,
        medallionShape: MilestoneMedallionShape = .circleRecord,
        timesEarnedCount: Int = 0,
        progressFraction: Double = 0.0,
        qualifyingRunID: UUID? = nil,
        qualifyingDate: Date? = nil,
        qualifyingDistanceMeters: Double? = nil,
        qualifyingDurationSeconds: Double? = nil,
        qualifyingCadenceSPM: Double? = nil,
        qualifyingEfficiencyFactor: Double? = nil
    ) {
        self.identifier = identifier
        self.title = title
        self.iconName = iconName
        self.description = description
        self.isUnlocked = isUnlocked
        self.accentColorName = accentColorName
        self.medallionShape = medallionShape
        self.timesEarnedCount = timesEarnedCount
        self.progressFraction = min(1.0, max(0.0, progressFraction))
        self.qualifyingRunID = qualifyingRunID
        self.qualifyingDate = qualifyingDate
        self.qualifyingDistanceMeters = qualifyingDistanceMeters
        self.qualifyingDurationSeconds = qualifyingDurationSeconds
        self.qualifyingCadenceSPM = qualifyingCadenceSPM
        self.qualifyingEfficiencyFactor = qualifyingEfficiencyFactor
    }
}

public struct PersonalRecordsSummaryCore: Sendable, Codable, Equatable {
    public let totalDistanceMeters: Double
    public let totalDurationSeconds: Double
    public let totalRunsCount: Int
    public let longestRunMeters: Double
    public let fastestPaceSecondsPerKm: Double?
    public let peakCadenceSPM: Double?
    public let peakEfficiencyFactor: Double?
    public let badges: [MilestoneBadgeSpec]

    public var unlockedBadgesCount: Int {
        badges.filter(\.isUnlocked).count
    }

    public init(
        totalDistanceMeters: Double,
        totalDurationSeconds: Double,
        totalRunsCount: Int,
        longestRunMeters: Double,
        fastestPaceSecondsPerKm: Double?,
        peakCadenceSPM: Double?,
        peakEfficiencyFactor: Double?,
        badges: [MilestoneBadgeSpec]
    ) {
        self.totalDistanceMeters = totalDistanceMeters
        self.totalDurationSeconds = totalDurationSeconds
        self.totalRunsCount = totalRunsCount
        self.longestRunMeters = longestRunMeters
        self.fastestPaceSecondsPerKm = fastestPaceSecondsPerKm
        self.peakCadenceSPM = peakCadenceSPM
        self.peakEfficiencyFactor = peakEfficiencyFactor
        self.badges = badges
    }
}

// MARK: - Core Lifetime Milestones Evaluator

public enum LifetimeMilestonesCore {

    public static func evaluate(samples: [MilestoneRunSample]) -> PersonalRecordsSummaryCore {
        let totalDistance = samples.map(\.totalDistanceMeters).reduce(0.0, +)
        let totalDuration = samples.map(\.durationSeconds).reduce(0.0, +)
        let count = samples.count

        let longestMeters = samples.map(\.totalDistanceMeters).max() ?? 0.0

        let validPaces = samples
            .filter { $0.workingAvgPace > 0.0 && $0.totalDistanceMeters >= 1000.0 }
            .map(\.workingAvgPace)
        let fastestPace = validPaces.min()

        let validCadences = samples.map(\.workingAvgCadence).filter { $0 > 0.0 }
        let peakCadence = validCadences.max()

        let validEFs = samples.compactMap(\.efficiencyFactor).filter { $0 > 0.0 }
        let peakEF = validEFs.max()

        let totalKm = totalDistance / 1000.0
        let maxRunKm = longestMeters / 1000.0

        let earliestRun = samples.min(by: { $0.date < $1.date })
        let mostRecentRun = samples.max(by: { $0.date < $1.date })
        let longestRun = samples.max(by: { $0.totalDistanceMeters < $1.totalDistanceMeters })

        // 5K Qualifying
        let qualifyingFiveKRuns = samples.filter { $0.totalDistanceMeters >= 5000.0 }
        let bestFiveKRun = qualifyingFiveKRuns.max(by: { $0.totalDistanceMeters < $1.totalDistanceMeters }) ?? longestRun
        let isFiveKUnlocked = maxRunKm >= 5.0

        // 10K Qualifying
        let qualifyingTenKRuns = samples.filter { $0.totalDistanceMeters >= 10_000.0 }
        let bestTenKRun = qualifyingTenKRuns.max(by: { $0.totalDistanceMeters < $1.totalDistanceMeters }) ?? longestRun
        let isTenKUnlocked = maxRunKm >= 10.0

        // Half Marathon Qualifying
        let qualifyingHalfMarathonRuns = samples.filter { $0.totalDistanceMeters >= 21_097.5 }
        let bestHalfMarathonRun = qualifyingHalfMarathonRuns.max(by: { $0.totalDistanceMeters < $1.totalDistanceMeters }) ?? longestRun
        let isHalfMarathonUnlocked = maxRunKm >= 21.1 || longestMeters >= 21_097.5

        // Rhythm Master Qualifying
        let qualifyingCadenceRuns = samples.filter { $0.workingAvgCadence >= 170.0 }
        let bestCadenceRun = qualifyingCadenceRuns.max(by: { $0.workingAvgCadence < $1.workingAvgCadence })
            ?? samples.max(by: { $0.workingAvgCadence < $1.workingAvgCadence })
        let isRhythmUnlocked = (peakCadence ?? 0.0) >= 170.0

        // Aerobic Engine Qualifying
        let qualifyingEFRuns = samples.filter { ($0.efficiencyFactor ?? 0.0) >= 1.35 }
        let bestEFRun = qualifyingEFRuns.max(by: { ($0.efficiencyFactor ?? 0.0) < ($1.efficiencyFactor ?? 0.0) })
            ?? samples.filter { ($0.efficiencyFactor ?? 0.0) > 0.0 }.max(by: { ($0.efficiencyFactor ?? 0.0) < ($1.efficiencyFactor ?? 0.0) })
        let isAerobicEngineUnlocked = (peakEF ?? 0.0) >= 1.35

        let isCenturyUnlocked = totalKm >= 100.0
        let isFiveHundredKUnlocked = totalKm >= 500.0
        let isConsistencyUnlocked = count >= 10

        let badges: [MilestoneBadgeSpec] = [
            MilestoneBadgeSpec(
                identifier: .firstRun,
                title: "First Steps",
                iconName: "figure.run.circle.fill",
                description: "Recorded your first run in Runalyst.",
                isUnlocked: count >= 1,
                accentColorName: "blue",
                medallionShape: .circleRecord,
                timesEarnedCount: count >= 1 ? 1 : 0,
                progressFraction: count >= 1 ? 1.0 : 0.0,
                qualifyingRunID: earliestRun?.id,
                qualifyingDate: earliestRun?.date,
                qualifyingDistanceMeters: earliestRun?.totalDistanceMeters,
                qualifyingDurationSeconds: earliestRun?.durationSeconds,
                qualifyingCadenceSPM: earliestRun?.workingAvgCadence
            ),
            MilestoneBadgeSpec(
                identifier: .fiveK,
                title: "5K Milestone",
                iconName: "flame.fill",
                description: "Logged a single run of at least 5 km.",
                isUnlocked: isFiveKUnlocked,
                accentColorName: "orange",
                medallionShape: .splitHorizonDistance,
                timesEarnedCount: qualifyingFiveKRuns.count,
                progressFraction: min(1.0, max(0.0, maxRunKm / 5.0)),
                qualifyingRunID: isFiveKUnlocked ? bestFiveKRun?.id : nil,
                qualifyingDate: isFiveKUnlocked ? bestFiveKRun?.date : nil,
                qualifyingDistanceMeters: isFiveKUnlocked ? bestFiveKRun?.totalDistanceMeters : longestMeters,
                qualifyingDurationSeconds: isFiveKUnlocked ? bestFiveKRun?.durationSeconds : nil,
                qualifyingCadenceSPM: isFiveKUnlocked ? bestFiveKRun?.workingAvgCadence : nil
            ),
            MilestoneBadgeSpec(
                identifier: .tenK,
                title: "10K Club",
                iconName: "trophy.fill",
                description: "Logged a single run of at least 10 km.",
                isUnlocked: isTenKUnlocked,
                accentColorName: "yellow",
                medallionShape: .splitHorizonDistance,
                timesEarnedCount: qualifyingTenKRuns.count,
                progressFraction: min(1.0, max(0.0, maxRunKm / 10.0)),
                qualifyingRunID: isTenKUnlocked ? bestTenKRun?.id : nil,
                qualifyingDate: isTenKUnlocked ? bestTenKRun?.date : nil,
                qualifyingDistanceMeters: isTenKUnlocked ? bestTenKRun?.totalDistanceMeters : longestMeters,
                qualifyingDurationSeconds: isTenKUnlocked ? bestTenKRun?.durationSeconds : nil,
                qualifyingCadenceSPM: isTenKUnlocked ? bestTenKRun?.workingAvgCadence : nil
            ),
            MilestoneBadgeSpec(
                identifier: .halfMarathon,
                title: "Half Marathon",
                iconName: "medal.fill",
                description: "Completed a 21.1 km endurance effort.",
                isUnlocked: isHalfMarathonUnlocked,
                accentColorName: "purple",
                medallionShape: .splitHorizonDistance,
                timesEarnedCount: qualifyingHalfMarathonRuns.count,
                progressFraction: min(1.0, max(0.0, maxRunKm / 21.1)),
                qualifyingRunID: isHalfMarathonUnlocked ? bestHalfMarathonRun?.id : nil,
                qualifyingDate: isHalfMarathonUnlocked ? bestHalfMarathonRun?.date : nil,
                qualifyingDistanceMeters: isHalfMarathonUnlocked ? bestHalfMarathonRun?.totalDistanceMeters : longestMeters,
                qualifyingDurationSeconds: isHalfMarathonUnlocked ? bestHalfMarathonRun?.durationSeconds : nil,
                qualifyingCadenceSPM: isHalfMarathonUnlocked ? bestHalfMarathonRun?.workingAvgCadence : nil
            ),
            MilestoneBadgeSpec(
                identifier: .centuryVolume,
                title: "100K Century",
                iconName: "sparkles",
                description: "Accumulated 100 km of total lifetime running volume.",
                isUnlocked: isCenturyUnlocked,
                accentColorName: "cyan",
                medallionShape: .splitHorizonDistance,
                timesEarnedCount: Int(totalKm / 100.0),
                progressFraction: min(1.0, max(0.0, totalKm / 100.0)),
                qualifyingRunID: isCenturyUnlocked ? mostRecentRun?.id : nil,
                qualifyingDate: isCenturyUnlocked ? mostRecentRun?.date : nil,
                qualifyingDistanceMeters: totalDistance,
                qualifyingDurationSeconds: isCenturyUnlocked ? mostRecentRun?.durationSeconds : nil,
                qualifyingCadenceSPM: isCenturyUnlocked ? mostRecentRun?.workingAvgCadence : nil
            ),
            MilestoneBadgeSpec(
                identifier: .fiveHundredK,
                title: "500K Titan",
                iconName: "crown.fill",
                description: "Accumulated 500 km of total lifetime running volume.",
                isUnlocked: isFiveHundredKUnlocked,
                accentColorName: "indigo",
                medallionShape: .splitHorizonDistance,
                timesEarnedCount: Int(totalKm / 500.0),
                progressFraction: min(1.0, max(0.0, totalKm / 500.0)),
                qualifyingRunID: isFiveHundredKUnlocked ? mostRecentRun?.id : nil,
                qualifyingDate: isFiveHundredKUnlocked ? mostRecentRun?.date : nil,
                qualifyingDistanceMeters: totalDistance,
                qualifyingDurationSeconds: isFiveHundredKUnlocked ? mostRecentRun?.durationSeconds : nil,
                qualifyingCadenceSPM: isFiveHundredKUnlocked ? mostRecentRun?.workingAvgCadence : nil
            ),
            MilestoneBadgeSpec(
                identifier: .rhythmMaster,
                title: "Rhythm Master",
                iconName: "metronome.fill",
                description: "Maintained optimal turnover of 170+ SPM.",
                isUnlocked: isRhythmUnlocked,
                accentColorName: "teal",
                medallionShape: .circleRecord,
                timesEarnedCount: qualifyingCadenceRuns.count,
                progressFraction: min(1.0, max(0.0, (peakCadence ?? 0.0) / 170.0)),
                qualifyingRunID: isRhythmUnlocked ? bestCadenceRun?.id : nil,
                qualifyingDate: isRhythmUnlocked ? bestCadenceRun?.date : nil,
                qualifyingDistanceMeters: isRhythmUnlocked ? bestCadenceRun?.totalDistanceMeters : nil,
                qualifyingDurationSeconds: isRhythmUnlocked ? bestCadenceRun?.durationSeconds : nil,
                qualifyingCadenceSPM: peakCadence
            ),
            MilestoneBadgeSpec(
                identifier: .aerobicEngine,
                title: "Aerobic Engine",
                iconName: "bolt.heart.fill",
                description: "Achieved an Efficiency Factor exceeding 1.35 m/beat.",
                isUnlocked: isAerobicEngineUnlocked,
                accentColorName: "pink",
                medallionShape: .circleRecord,
                timesEarnedCount: qualifyingEFRuns.count,
                progressFraction: min(1.0, max(0.0, (peakEF ?? 0.0) / 1.35)),
                qualifyingRunID: isAerobicEngineUnlocked ? bestEFRun?.id : nil,
                qualifyingDate: isAerobicEngineUnlocked ? bestEFRun?.date : nil,
                qualifyingDistanceMeters: isAerobicEngineUnlocked ? bestEFRun?.totalDistanceMeters : nil,
                qualifyingDurationSeconds: isAerobicEngineUnlocked ? bestEFRun?.durationSeconds : nil,
                qualifyingCadenceSPM: isAerobicEngineUnlocked ? bestEFRun?.workingAvgCadence : nil,
                qualifyingEfficiencyFactor: peakEF
            ),
            MilestoneBadgeSpec(
                identifier: .consistency,
                title: "Consistent Runner",
                iconName: "calendar.badge.checkmark",
                description: "Logged 10 or more structured running workouts.",
                isUnlocked: isConsistencyUnlocked,
                accentColorName: "green",
                medallionShape: .hexagonStreak,
                timesEarnedCount: count / 10,
                progressFraction: min(1.0, Double(count) / 10.0),
                qualifyingRunID: isConsistencyUnlocked ? mostRecentRun?.id : nil,
                qualifyingDate: isConsistencyUnlocked ? mostRecentRun?.date : nil,
                qualifyingDistanceMeters: isConsistencyUnlocked ? mostRecentRun?.totalDistanceMeters : nil,
                qualifyingDurationSeconds: isConsistencyUnlocked ? mostRecentRun?.durationSeconds : nil,
                qualifyingCadenceSPM: isConsistencyUnlocked ? mostRecentRun?.workingAvgCadence : nil
            )
        ]

        return PersonalRecordsSummaryCore(
            totalDistanceMeters: totalDistance,
            totalDurationSeconds: totalDuration,
            totalRunsCount: count,
            longestRunMeters: longestMeters,
            fastestPaceSecondsPerKm: fastestPace,
            peakCadenceSPM: peakCadence,
            peakEfficiencyFactor: peakEF,
            badges: badges
        )
    }
}
