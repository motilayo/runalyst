import Foundation

/// Comprehensive runner profile capturing athletic maturity, active training goal,
/// height-calibrated biomechanical thresholds, and empirical 30-day training load.
struct RunnerProfile: Equatable, Sendable {
    let experienceLevel: String
    let trainingGoal: String
    let userHeightCm: Double
    let current30DayDistanceKm: Double
    let weeklyAverageKm: Double
    let runsPerWeek: Double
    let isAutoCalculated: Bool
    let calculatedExperienceLevel: String

    /// Standard experience level options available in profile settings.
    static let experienceLevelOptions = [
        "Novice / Beginner",
        "Intermediate / Enthusiast",
        "Advanced / Veteran",
        "Competitive / Elite"
    ]

    init(
        experienceLevel: String,
        trainingGoal: String,
        userHeightCm: Double,
        current30DayDistanceKm: Double,
        weeklyAverageKm: Double,
        runsPerWeek: Double,
        isAutoCalculated: Bool = false,
        calculatedExperienceLevel: String? = nil
    ) {
        self.experienceLevel = experienceLevel
        self.trainingGoal = trainingGoal
        self.userHeightCm = userHeightCm
        self.current30DayDistanceKm = current30DayDistanceKm
        self.weeklyAverageKm = weeklyAverageKm
        self.runsPerWeek = runsPerWeek
        self.isAutoCalculated = isAutoCalculated
        self.calculatedExperienceLevel = calculatedExperienceLevel ?? experienceLevel
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

    /// Deterministically calculates athletic experience level from SwiftData run history.
    /// Evaluates empirical 30-day volume, run frequency, lifetime workout counts, and endurance distance.
    static func calculateExperienceLevel(from runRecords: [RunRecord], now: Date = Date()) -> String {
        guard !runRecords.isEmpty else {
            return "Novice / Beginner"
        }

        let cal = Calendar.current
        let thirtyDaysAgo = cal.date(byAdding: .day, value: -30, to: now) ?? now.addingTimeInterval(-30 * 24 * 3600)
        let recentRuns = runRecords.filter { $0.date >= thirtyDaysAgo && $0.date <= now }

        let totalRunsCount = runRecords.count
        let totalDistanceMeters = recentRuns.reduce(0.0) { $0 + $1.totalDistanceMeters }
        let totalDistanceKm = totalDistanceMeters / 1000.0
        let weeks = 30.0 / 7.0
        let weeklyAvgKm = totalDistanceKm / weeks

        let uniqueDays = Set(recentRuns.map { cal.startOfDay(for: $0.date) })
        let runsPerWeek = Double(uniqueDays.count) / weeks

        let maxDistanceMeters = runRecords.map(\.totalDistanceMeters).max() ?? 0.0
        let longestRunKm = maxDistanceMeters / 1000.0

        let validPaces = runRecords.filter { $0.workingAvgPace > 0 && $0.totalDistanceMeters >= 1000.0 }.map(\.workingAvgPace)
        let fastestPaceSec = validPaces.min() ?? 360.0

        // 1. Competitive / Elite
        // High weekly volume (>= 60 km/wk with high frequency) OR strong volume (>= 45 km/wk) with elite speed (< 4:10/km / 250s) and long-distance base
        if (weeklyAvgKm >= 60.0 && runsPerWeek >= 4.5 && longestRunKm >= 18.0) ||
           (weeklyAvgKm >= 45.0 && fastestPaceSec <= 250.0 && longestRunKm >= 20.0) {
            return "Competitive / Elite"
        }

        // 2. Advanced / Veteran
        // Solid weekly volume (>= 32 km/wk / ~20 mi/wk) with >= 3.2 runs/wk, established history (>= 12 runs), and double-digit distance capacity (>= 12 km)
        if (weeklyAvgKm >= 32.0 && runsPerWeek >= 3.2 && totalRunsCount >= 12 && longestRunKm >= 12.0) ||
           (weeklyAvgKm >= 28.0 && longestRunKm >= 16.0 && totalRunsCount >= 15) {
            return "Advanced / Veteran"
        }

        // 3. Intermediate / Enthusiast
        // Habitual runner: at least 5 lifetime runs, weekly volume >= 10 km/wk, OR runs 2+ times/week with 5K+ endurance capacity
        if (totalRunsCount >= 5 && longestRunKm >= 4.5 && (weeklyAvgKm >= 10.0 || runsPerWeek >= 1.8)) ||
           (totalRunsCount >= 8 && longestRunKm >= 5.0) {
            return "Intermediate / Enthusiast"
        }

        // 4. Novice / Beginner
        // Cold start, low lifetime runs, sporadic frequency, or has not yet completed a 5K continuous run
        return "Novice / Beginner"
    }

    /// Factory method computing 30-day volume, load metrics, and auto-adjusted experience level.
    static func compute(
        from runRecords: [RunRecord],
        trainingGoal: String? = nil,
        experienceLevel: String? = nil,
        userHeightCm: Double? = nil,
        now: Date = Date()
    ) -> RunnerProfile {
        let defaults = UserDefaults.standard
        let goal = trainingGoal ?? defaults.string(forKey: "trainingGoal") ?? "Base Building"
        let storedLevel = defaults.string(forKey: "userExperienceLevel") ?? "Auto"
        let storedHeight = defaults.double(forKey: "userHeightCm")
        let height = userHeightCm ?? (storedHeight > 0 ? storedHeight : 175.0)

        let cal = Calendar.current
        let thirtyDaysAgo = cal.date(byAdding: .day, value: -30, to: now) ?? now.addingTimeInterval(-30 * 24 * 3600)
        let recentRuns = runRecords.filter { $0.date >= thirtyDaysAgo && $0.date <= now }

        let totalDistanceMeters = recentRuns.reduce(0.0) { $0 + $1.totalDistanceMeters }
        let totalDistanceKm = totalDistanceMeters / 1000.0
        let weeks = 30.0 / 7.0
        let weeklyAvgKm = totalDistanceKm / weeks
        let uniqueDays = Set(recentRuns.map { cal.startOfDay(for: $0.date) })
        let runsPerWeek = Double(uniqueDays.count) / weeks

        let calculatedLevel = calculateExperienceLevel(from: runRecords, now: now)

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

        return RunnerProfile(
            experienceLevel: resolvedLevel,
            trainingGoal: goal,
            userHeightCm: height,
            current30DayDistanceKm: totalDistanceKm,
            weeklyAverageKm: weeklyAvgKm,
            runsPerWeek: runsPerWeek,
            isAutoCalculated: isAuto,
            calculatedExperienceLevel: calculatedLevel
        )
    }

    /// Human-readable load summary string.
    var loadSummary: String {
        let kmText = String(format: "%.1f km/wk", weeklyAverageKm)
        let freqText = String(format: "%.1f runs/wk", runsPerWeek)
        return "\(kmText) across \(freqText)"
    }
}
