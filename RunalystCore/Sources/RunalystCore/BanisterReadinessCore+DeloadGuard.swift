import Foundation

// MARK: - Banister Readiness Deload Guard

extension BanisterReadinessCore {

    /// Pure deterministic helper that evaluates whether a strict 7-day acute mileage drop
    /// (>= 25% below trailing weekly average) is an actual deload vs. a 2-4 day rest/walk gap
    /// following a healthy prior week / 10-day window.
    ///
    /// - Parameters:
    ///   - sessions: Historical workload sessions up to `now`.
    ///   - trailingWeeklyMeters: Trailing weekly volume baseline (e.g. 21-day average weekly meters).
    ///   - now: The reference timestamp for evaluation.
    ///   - calendar: Calendar used for date arithmetic (defaults to Gregorian).
    ///   - dropThreshold: Drop fraction threshold required to consider a deload (defaults to 0.25).
    /// - Returns: `true` if the drop is an actual deload; `false` if the drop is less than threshold
    ///   or is suppressed due to healthy prior-week / 10-day volume during a 2-4 day rest gap.
    public static func isTrueDeloadVolumeDrop(
        sessions: [WorkloadSession],
        trailingWeeklyMeters: Double,
        now: Date,
        calendar: Calendar = Calendar(identifier: .gregorian),
        dropThreshold: Double = 0.25
    ) -> Bool {
        guard trailingWeeklyMeters > 0.0 else {
            return false
        }

        let validSessions = sessions.filter { $0.date <= now }
        let dayInterval: TimeInterval = 24 * 3600

        // 1. Strict 7-day acute mileage drop
        let acuteCutoff = now.addingTimeInterval(-7.0 * dayInterval)
        let acuteMeters = validSessions
            .filter { $0.date >= acuteCutoff }
            .map(\.distanceMeters)
            .reduce(0.0, +)

        let acuteDrop = 1.0 - (acuteMeters / trailingWeeklyMeters)
        guard acuteDrop >= dropThreshold else {
            return false
        }

        // 2. Identify latest session and days elapsed since last run
        let pastSessions = validSessions.sorted { $0.date > $1.date }
        guard let latestSession = pastSessions.first else {
            return false
        }

        let startOfNow = calendar.startOfDay(for: now)
        let startOfLatest = calendar.startOfDay(for: latestSession.date)
        let calendarDays = calendar.dateComponents([.day], from: startOfLatest, to: startOfNow).day ?? 0
        let timeDays = Int(now.timeIntervalSince(latestSession.date) / dayInterval)
        let daysSinceLastRun = max(0, max(calendarDays, timeDays))

        // 3. Rest-gap resilience check (2-4+ day rest/walk gap following healthy load)
        if daysSinceLastRun >= 2 {
            // Normalized trailing 10-day weekly volume: (10-day meters / 10.0) * 7.0
            let cutoff10d = calendar.date(byAdding: .day, value: -10, to: now) ?? now.addingTimeInterval(-10.0 * dayInterval)
            let meters10d = validSessions
                .filter { $0.date >= cutoff10d }
                .map(\.distanceMeters)
                .reduce(0.0, +)
            let normalized10DayWeeklyRate = (meters10d / 10.0) * 7.0

            // Most recent completed calendar week volume (Monday-to-Sunday athletic standard)
            let targetWeekday = 2 // Monday (ISO 8601 athletic training standard)
            let currentWeekday = calendar.component(.weekday, from: startOfNow)
            let daysToSubtract = (currentWeekday - targetWeekday + 7) % 7
            let currentWeekStart = calendar.date(byAdding: .day, value: -daysToSubtract, to: startOfNow) ?? startOfNow
            let completedWeekStart = calendar.date(byAdding: .day, value: -7, to: currentWeekStart) ?? currentWeekStart.addingTimeInterval(-7.0 * dayInterval)
            let completedWeekEnd = currentWeekStart
            let completedWeekMeters = validSessions
                .filter { $0.date >= completedWeekStart && $0.date < completedWeekEnd }
                .map(\.distanceMeters)
                .reduce(0.0, +)

            // Prior 7-day block before the rest gap
            let priorBlockStart = latestSession.date.addingTimeInterval(-7.0 * dayInterval)
            let priorBlockMeters = validSessions
                .filter { $0.date >= priorBlockStart && $0.date <= latestSession.date }
                .map(\.distanceMeters)
                .reduce(0.0, +)

            let priorWeekMeters = max(completedWeekMeters, priorBlockMeters)
            let healthyThreshold = 0.80 * trailingWeeklyMeters

            // If normalized 10-day or prior calendar week was >= 80% of chronic baseline,
            // suppress false-positive deload (preserves productive readiness).
            if normalized10DayWeeklyRate >= healthyThreshold || priorWeekMeters >= healthyThreshold {
                return false
            }
        }

        return true
    }
}
