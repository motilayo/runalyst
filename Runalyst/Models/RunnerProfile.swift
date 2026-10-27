import Foundation
import RunalystCore

/// Comprehensive runner profile capturing athletic maturity, active training goal,
/// height-calibrated biomechanical thresholds, empirical 30-day training load,
/// and objective goal readiness benchmarks.
struct RunnerProfile: Equatable, Sendable {
    let name: String
    let age: Int?
    let vo2Max: Double?
    let experienceLevel: String
    let trainingGoal: String
    let userHeightCm: Double
    let current30DayDistanceKm: Double
    let weeklyAverageKm: Double
    let runsPerWeek: Double
    let isAutoCalculated: Bool
    let calculatedExperienceLevel: String
    let longestRunKm: Double
    let fastestPaceSec: Double
    let goalBenchmark: GoalBenchmark

    /// Standard experience level options available in profile settings.
    static let experienceLevelOptions = [
        "Novice / Beginner",
        "Intermediate / Enthusiast",
        "Advanced / Veteran",
        "Competitive / Elite"
    ]

    init(
        name: String = "Runner",
        age: Int? = nil,
        vo2Max: Double? = nil,
        experienceLevel: String,
        trainingGoal: String,
        userHeightCm: Double,
        current30DayDistanceKm: Double,
        weeklyAverageKm: Double,
        runsPerWeek: Double,
        isAutoCalculated: Bool = false,
        calculatedExperienceLevel: String? = nil,
        longestRunKm: Double = 0.0,
        fastestPaceSec: Double = 0.0,
        goalBenchmark: GoalBenchmark? = nil
    ) {
        self.name = name
        self.age = age
        self.vo2Max = vo2Max
        self.experienceLevel = experienceLevel
        self.trainingGoal = trainingGoal
        self.userHeightCm = userHeightCm
        self.current30DayDistanceKm = current30DayDistanceKm
        self.weeklyAverageKm = weeklyAverageKm
        self.runsPerWeek = runsPerWeek
        self.isAutoCalculated = isAutoCalculated
        self.calculatedExperienceLevel = calculatedExperienceLevel ?? experienceLevel
        self.longestRunKm = longestRunKm
        self.fastestPaceSec = fastestPaceSec
        self.goalBenchmark = goalBenchmark ?? GoalBenchmarkCore.evaluate(
            goal: trainingGoal,
            currentWeeklyKm: weeklyAverageKm,
            longestRunKm: longestRunKm,
            userHeightCm: userHeightCm,
            experienceLevel: experienceLevel
        )
    }

    /// Height scale relative to the standard reference height of 175 cm (5'9").
    var heightScaleFactor: Double {
        let clamped = max(130.0, min(220.0, userHeightCm))
        return clamped / 175.0
    }

    /// Height-calibrated baseline cadence floor (e.g. 150 SPM at 175 cm, ~142 SPM at 193 cm, ~156 SPM at 155 cm).
    var heightAdjustedCadenceFloor: Int {
        Int((150.0 / heightScaleFactor).rounded())
    }

    /// Height-calibrated high turnover threshold (e.g. 165 SPM at 175 cm, ~156 SPM at 193 cm, ~172 SPM at 155 cm).
    var heightAdjustedHighCadenceThreshold: Int {
        Int((165.0 / heightScaleFactor).rounded())
    }

    /// Height-calibrated maximum normal vertical oscillation (e.g. 9.5 cm at 175 cm).
    var heightAdjustedMaxOscillationCM: Double {
        9.5 * heightScaleFactor
    }

    /// Deterministically calculates athletic experience level from SwiftData run history via RunalystCore.
    static func calculateExperienceLevel(from runRecords: [RunRecord], now: Date = Date()) -> String {
        let activeRuns = runRecords.filter { !$0.isDeleted }
        guard !activeRuns.isEmpty else {
            return "Novice / Beginner"
        }

        let summary = MacroVolumeCore.evaluateVolumeSummary(
            allRuns: activeRuns.map { $0.toVolumeRunSample() },
            timeRange: "30 Days",
            now: now,
            calendar: Calendar.current
        )
        let longestRunKm = (activeRuns.map(\.totalDistanceMeters).max() ?? 0.0) / 1000.0
        let validPaces = activeRuns.filter { $0.workingAvgPace > 0 && $0.totalDistanceMeters >= 1000.0 }.map(\.workingAvgPace)
        let fastestPaceSec = validPaces.min() ?? 360.0

        return GoalBenchmarkCore.calculateExperienceLevel(
            totalRunsCount: activeRuns.count,
            weeklyAvgKm: summary.weeklyAverageKm,
            runsPerWeek: summary.runsPerWeek,
            longestRunKm: longestRunKm,
            fastestPaceSec: fastestPaceSec
        )
    }

    /// Factory method computing 30-day volume, load metrics, and auto-adjusted experience level via RunalystCore.
    static func compute(
        from runRecords: [RunRecord],
        trainingGoal: String? = nil,
        experienceLevel: String? = nil,
        userHeightCm: Double? = nil,
        runnerName: String? = nil,
        runnerAge: Int? = nil,
        vo2Max: Double? = nil,
        now: Date = Date()
    ) -> RunnerProfile {
        let defaults = UserDefaults.standard
        let storedName = defaults.string(forKey: "runnerName")
        let name = runnerName ?? (storedName.flatMap { $0.isEmpty ? nil : $0 } ?? "Runner")
        let storedAge = defaults.integer(forKey: "runnerAge")
        let age = runnerAge ?? (storedAge > 0 ? storedAge : nil)
        let storedVO2 = defaults.double(forKey: "cachedVO2Max")
        let resolvedVO2 = vo2Max ?? (storedVO2 > 0 ? storedVO2 : nil)

        let goal = trainingGoal ?? defaults.string(forKey: "trainingGoal") ?? "Base Building"
        let storedLevel = defaults.string(forKey: "userExperienceLevel") ?? "Auto"
        let storedHeight = defaults.double(forKey: "userHeightCm")
        let height = userHeightCm ?? (storedHeight > 0 ? storedHeight : 175.0)

        let activeRuns = runRecords.filter { !$0.isDeleted }
        let summary = MacroVolumeCore.evaluateVolumeSummary(
            allRuns: activeRuns.map { $0.toVolumeRunSample() },
            timeRange: "30 Days",
            now: now,
            calendar: Calendar.current
        )
        let totalDistanceKm = summary.totalDistanceMeters / 1000.0
        let weeklyAvgKm = summary.weeklyAverageKm
        let runsPerWeek = summary.runsPerWeek

        let maxDistanceMeters = activeRuns.map(\.totalDistanceMeters).max() ?? 0.0
        let longestRunKm = maxDistanceMeters / 1000.0

        let validPaces = activeRuns.filter { $0.workingAvgPace > 0 && $0.totalDistanceMeters >= 1000.0 }.map(\.workingAvgPace)
        let fastestPaceSec = validPaces.min() ?? 360.0

        let calculatedLevel = GoalBenchmarkCore.calculateExperienceLevel(
            totalRunsCount: activeRuns.count,
            weeklyAvgKm: weeklyAvgKm,
            runsPerWeek: runsPerWeek,
            longestRunKm: longestRunKm,
            fastestPaceSec: fastestPaceSec
        )

        let resolvedLevel: String
        let isAuto: Bool
        if let explicit = experienceLevel, explicit != "Auto" {
            resolvedLevel = explicit
            isAuto = false
        } else if storedLevel != "Auto", experienceLevelOptions.contains(storedLevel) {
            resolvedLevel = storedLevel
            isAuto = false
        } else {
            resolvedLevel = calculatedLevel
            isAuto = true
        }

        let benchmark = GoalBenchmarkCore.evaluate(
            goal: goal,
            currentWeeklyKm: weeklyAvgKm,
            longestRunKm: longestRunKm,
            userHeightCm: height,
            experienceLevel: resolvedLevel
        )

        return RunnerProfile(
            name: name,
            age: age,
            vo2Max: resolvedVO2,
            experienceLevel: resolvedLevel,
            trainingGoal: goal,
            userHeightCm: height,
            current30DayDistanceKm: totalDistanceKm,
            weeklyAverageKm: weeklyAvgKm,
            runsPerWeek: runsPerWeek,
            isAutoCalculated: isAuto,
            calculatedExperienceLevel: calculatedLevel,
            longestRunKm: longestRunKm,
            fastestPaceSec: fastestPaceSec,
            goalBenchmark: benchmark
        )
    }

    /// Human-readable load summary string.
    var loadSummary: String {
        let kmText = String(format: "%.1f km/wk", weeklyAverageKm)
        let freqText = String(format: "%.1f runs/wk", runsPerWeek)
        return "\(kmText) across \(freqText)"
    }
}
