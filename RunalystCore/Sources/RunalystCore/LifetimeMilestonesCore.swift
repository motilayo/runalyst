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
    case rhythmMaster = "rhythm_master"
    case aerobicEngine = "aerobic_engine"
    case consistency = "consistency"
}

public struct MilestoneBadgeSpec: Sendable, Codable, Equatable, Identifiable {
    public var id: String { identifier.rawValue }
    public let identifier: MilestoneBadgeIdentifier
    public let title: String
    public let iconName: String
    public let description: String
    public let isUnlocked: Bool
    public let accentColorName: String

    public init(
        identifier: MilestoneBadgeIdentifier,
        title: String,
        iconName: String,
        description: String,
        isUnlocked: Bool,
        accentColorName: String
    ) {
        self.identifier = identifier
        self.title = title
        self.iconName = iconName
        self.description = description
        self.isUnlocked = isUnlocked
        self.accentColorName = accentColorName
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

        let badges: [MilestoneBadgeSpec] = [
            MilestoneBadgeSpec(
                identifier: .firstRun,
                title: "First Steps",
                iconName: "figure.run.circle.fill",
                description: "Recorded your first run in Runalyst.",
                isUnlocked: count >= 1,
                accentColorName: "blue"
            ),
            MilestoneBadgeSpec(
                identifier: .fiveK,
                title: "5K Milestone",
                iconName: "flame.fill",
                description: "Logged a single run of at least 5 km.",
                isUnlocked: maxRunKm >= 5.0,
                accentColorName: "orange"
            ),
            MilestoneBadgeSpec(
                identifier: .tenK,
                title: "10K Club",
                iconName: "trophy.fill",
                description: "Logged a single run of at least 10 km.",
                isUnlocked: maxRunKm >= 10.0,
                accentColorName: "yellow"
            ),
            MilestoneBadgeSpec(
                identifier: .halfMarathon,
                title: "Half Marathon",
                iconName: "medal.fill",
                description: "Completed a 21.1 km endurance effort.",
                isUnlocked: maxRunKm >= 21.1,
                accentColorName: "purple"
            ),
            MilestoneBadgeSpec(
                identifier: .centuryVolume,
                title: "100K Century",
                iconName: "sparkles",
                description: "Accumulated 100 km of total lifetime running volume.",
                isUnlocked: totalKm >= 100.0,
                accentColorName: "cyan"
            ),
            MilestoneBadgeSpec(
                identifier: .fiveHundredK,
                title: "500K Titan",
                iconName: "crown.fill",
                description: "Accumulated 500 km of total lifetime running volume.",
                isUnlocked: totalKm >= 500.0,
                accentColorName: "indigo"
            ),
            MilestoneBadgeSpec(
                identifier: .rhythmMaster,
                title: "Rhythm Master",
                iconName: "metronome.fill",
                description: "Maintained optimal turnover of 170+ SPM.",
                isUnlocked: (peakCadence ?? 0.0) >= 170.0,
                accentColorName: "teal"
            ),
            MilestoneBadgeSpec(
                identifier: .aerobicEngine,
                title: "Aerobic Engine",
                iconName: "bolt.heart.fill",
                description: "Achieved an Efficiency Factor exceeding 1.35 m/beat.",
                isUnlocked: (peakEF ?? 0.0) >= 1.35,
                accentColorName: "pink"
            ),
            MilestoneBadgeSpec(
                identifier: .consistency,
                title: "Consistent Runner",
                iconName: "calendar.badge.checkmark",
                description: "Logged 10 or more structured running workouts.",
                isUnlocked: count >= 10,
                accentColorName: "green"
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
