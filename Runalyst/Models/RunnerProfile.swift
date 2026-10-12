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

    /// Standard experience level options available in profile settings.
    static let experienceLevelOptions = [
        "Novice / Beginner",
        "Intermediate / Enthusiast",
        "Advanced / Veteran",
        "Competitive / Elite"
    ]

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

    /// Factory method computing 30-day volume and load metrics from historical run records.
    static func compute(
        from runRecords: [RunRecord],
        trainingGoal: String? = nil,
        experienceLevel: String? = nil,
        userHeightCm: Double? = nil,
        now: Date = Date()
    ) -> RunnerProfile {
        let defaults = UserDefaults.standard
        let goal = trainingGoal ?? defaults.string(forKey: "trainingGoal") ?? "Base Building"
        let level = experienceLevel ?? defaults.string(forKey: "userExperienceLevel") ?? "Intermediate / Enthusiast"
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

        return RunnerProfile(
            experienceLevel: level,
            trainingGoal: goal,
            userHeightCm: height,
            current30DayDistanceKm: totalDistanceKm,
            weeklyAverageKm: weeklyAvgKm,
            runsPerWeek: runsPerWeek
        )
    }

    /// Human-readable load summary string.
    var loadSummary: String {
        let kmText = String(format: "%.1f km/wk", weeklyAverageKm)
        let freqText = String(format: "%.1f runs/wk", runsPerWeek)
        return "\(kmText) across \(freqText)"
    }
}
