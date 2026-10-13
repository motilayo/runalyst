import Foundation

/// Deterministic recovery clock: calculates when the runner can absorb another hard training session.
struct RecoveryTimeline: Equatable, Sendable {
    let now: Date
    let lastHard: ReadinessRunSnapshot?
    let hardSessionsLast72h: Int
    let requiredHours: Double
    let state: ReadinessState

    static func build(runs: [ReadinessRunSnapshot], readiness: ReadinessAssessment, now: Date) -> RecoveryTimeline {
        let hard = runs
            .filter { $0.date <= now && $0.isHardSession }
            .sorted { $0.date > $1.date }
        let recentCount = hard.filter { now.timeIntervalSince($0.date) <= 72 * 3600 }.count
        var required: Double = 48
        if let last = hard.first, last.percentZone4 >= 0.6 { required = 72 }
        if recentCount >= 2 { required = 72 }
        if readiness.state == .acuteFatigue { required = max(required, 72) }
        return RecoveryTimeline(
            now: now,
            lastHard: hard.first,
            hardSessionsLast72h: recentCount,
            requiredHours: required,
            state: readiness.state
        )
    }

    var hoursSinceLastHard: Double? {
        lastHard.map { now.timeIntervalSince($0.date) / 3600 }
    }

    var earliestHardDate: Date? {
        guard let lastHard else {
            return state == .acuteFatigue ? now.addingTimeInterval(24 * 3600) : nil
        }
        let byRecovery = lastHard.date.addingTimeInterval(requiredHours * 3600)
        if state == .acuteFatigue && byRecovery <= now {
            return now.addingTimeInterval(24 * 3600)
        }
        return byRecovery
    }

    var readyForHard: Bool {
        guard let earliest = earliestHardDate else { return true }
        return earliest <= now
    }

    func isCleared(for timeframe: String) -> Bool {
        guard let earliest = earliestHardDate else { return true }
        let lower = timeframe.lowercased()
        if lower == "today" {
            return readyForHard
        }
        let cal = Calendar.current
        let targetDate: Date? = {
            if lower == "tomorrow" {
                return cal.date(byAdding: .day, value: 1, to: now)
            }
            let days = ["sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7]
            guard let targetWeekday = days.first(where: { lower.contains($0.key) })?.value else { return nil }
            let currentWeekday = cal.component(.weekday, from: now)
            var diff = targetWeekday - currentWeekday
            if diff <= 0 { diff += 7 }
            return cal.date(byAdding: .day, value: diff, to: now)
        }()
        guard let targetDate else { return readyForHard }
        return cal.startOfDay(for: targetDate) >= cal.startOfDay(for: earliest)
    }

    var easyCap: ClosedRange<Int>? {
        guard !readyForHard else { return nil }
        guard let hours = hoursSinceLastHard else { return 20...30 }
        return hours < 24 ? 20...30 : 30...40
    }

    var earliestHardPhrase: String {
        guard let date = earliestHardDate else { return "now" }
        return Self.futurePhrase(for: date, relativeTo: now)
    }

    static func weekday(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    private static func partOfDay(_ date: Date, calendar: Calendar) -> String {
        let hour = calendar.component(.hour, from: date)
        if hour < 12 { return "morning" }
        if hour < 17 { return "afternoon" }
        return "evening"
    }

    static func futurePhrase(for date: Date, relativeTo now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "later today" }
        let part = partOfDay(date, calendar: calendar)
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "tomorrow \(part)"
        }
        return "\(weekday(date)) \(part)"
    }

    static func pastPhrase(for date: Date, relativeTo now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "earlier today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "yesterday"
        }
        if now.timeIntervalSince(date) < 6 * 24 * 3600 {
            return "on \(weekday(date))"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        return "on \(formatter.string(from: date))"
    }

    static func durationPhrase(hours: Double) -> String {
        if hours < 1 { return "under an hour" }
        if hours < 36 { return "\(Int(hours.rounded())) hours" }
        return "\(Int((hours / 24).rounded())) days"
    }
}
