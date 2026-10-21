import Foundation
import SwiftData

/// Represents Gregorian calendar operations time-locked to Sunday-to-Saturday weeks.
public struct TrainingCalendar: Sendable {
    public let calendar: Calendar
    public let now: Date

    public init(calendar: Calendar = Calendar(identifier: .gregorian), now: Date = Date()) {
        var cal = calendar
        cal.firstWeekday = 1 // Sunday
        cal.locale = Locale(identifier: "en_US_POSIX")
        if cal.timeZone != TimeZone.current && calendar == Calendar(identifier: .gregorian) {
            cal.timeZone = TimeZone.current
        }
        self.calendar = cal
        self.now = now
    }

    public static let isoDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    public static let weekdayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        df.dateFormat = "EEEE"
        return df
    }()

    public static let shortWeekdayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        df.dateFormat = "EEE"
        return df
    }()

    public func formatISO(_ date: Date) -> String {
        Self.isoDateFormatter.string(from: date)
    }

    public func parseISO(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased() == "today" {
            return calendar.startOfDay(for: now)
        }
        if trimmed.lowercased() == "tomorrow" {
            let today = calendar.startOfDay(for: now)
            return calendar.date(byAdding: .day, value: 1, to: today)
        }
        if trimmed.lowercased() == "yesterday" {
            let today = calendar.startOfDay(for: now)
            return calendar.date(byAdding: .day, value: -1, to: today)
        }
        return Self.isoDateFormatter.date(from: trimmed)
    }

    /// Start of day for `date` under the calendar.
    public func startOfDay(for date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    /// Date offset utility.
    public func date(byAdding component: Calendar.Component, value: Int, to date: Date) -> Date? {
        calendar.date(byAdding: component, value: value, to: date)
    }

    /// Computes the start (Sunday) and end (Saturday) of the week containing `date`.
    public func weekInterval(containing date: Date) -> (start: Date, end: Date) {
        let target = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: target) // 1 = Sun, 7 = Sat
        let daysFromSunday = weekday - 1
        let sunday = calendar.date(byAdding: .day, value: -daysFromSunday, to: target) ?? target
        let saturday = calendar.date(byAdding: .day, value: 6, to: sunday) ?? target
        return (sunday, saturday)
    }

    /// Next week's Sunday to Saturday interval.
    public func nextWeekInterval(relativeTo date: Date? = nil) -> (start: Date, end: Date) {
        let currentWeek = weekInterval(containing: date ?? now)
        let nextSunday = calendar.date(byAdding: .day, value: 1, to: currentWeek.end) ?? currentWeek.end
        let nextSaturday = calendar.date(byAdding: .day, value: 6, to: nextSunday) ?? nextSunday
        return (nextSunday, nextSaturday)
    }

    /// Generates pure dates between `from` and `to` inclusive.
    public func dates(from startDate: Date, to endDate: Date) -> [Date] {
        let start = calendar.startOfDay(for: min(startDate, endDate))
        let end = calendar.startOfDay(for: max(startDate, endDate))
        var dates: [Date] = []
        var current = start
        while current <= end {
            dates.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return dates
    }

    /// Compact context block anchor string: "Today: Tue 2026-10-20. This week: 2026-10-18..2026-10-24. Next week: 2026-10-25..2026-10-31."
    public func anchor(now: Date? = nil, useMetric: Bool) -> String {
        let refDate = now ?? self.now
        let todayStr = Self.isoDateFormatter.string(from: refDate)
        let dayName = Self.shortWeekdayFormatter.string(from: refDate)
        let currentWeek = weekInterval(containing: refDate)
        let nextWeek = nextWeekInterval(relativeTo: refDate)

        let thisWeekStr = "\(formatISO(currentWeek.start))..\(formatISO(currentWeek.end))"
        let nextWeekStr = "\(formatISO(nextWeek.start))..\(formatISO(nextWeek.end))"
        let unitStr = useMetric ? "metric" : "imperial"

        return "Today: \(dayName) \(todayStr). This week: \(thisWeekStr). Next week: \(nextWeekStr). Units: \(unitStr)."
    }
    public func anchor(useMetric: Bool) -> String {
        anchor(now: nil, useMetric: useMetric)
    }
}

/// Context required to deterministically synthesize planned workouts and summarize completed runs.
struct ScheduleEvaluationContext {
    let runRecords: [RunRecord]
    let activeGoal: String
    let profile: RunnerProfile
    let useMetric: Bool
}

extension TrainingCalendar {
    /// Evaluates the complete schedule over `[from...to]` mapping to clean, discoverable `ScheduleDay` objects.
    @MainActor
    func evaluateSchedule(
        from startDate: Date,
        to endDate: Date,
        context: ScheduleEvaluationContext
    ) -> [ScheduleDay] {
        let allDates = dates(from: startDate, to: endDate)
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today

        let activeRuns = context.runRecords.filter { !$0.isDeleted }

        return allDates.map { date in
            let dateStart = calendar.startOfDay(for: date)
            let isoDate = formatISO(dateStart)
            let weekday = Self.weekdayFormatter.string(from: dateStart)

            // 1. Relative timing
            let relative: ScheduleDay.RelativeDay
            if dateStart == today {
                relative = .today
            } else if dateStart == tomorrow {
                relative = .tomorrow
            } else if dateStart < today {
                relative = .past
            } else {
                relative = .future
            }

            // 2. Completed workouts on this calendar date
            let runsOnDay = activeRuns.filter { calendar.isDate($0.date, inSameDayAs: dateStart) }
                .sorted { $0.date < $1.date }

            let completedSummaries: [CompletedWorkoutSummary] = runsOnDay.map { run in
                let durMins = (run.duration / 60.0).rounded(toPlaces: 1)
                let distKm = (run.totalDistanceMeters > 0 ? (run.totalDistanceMeters / 1000.0) : (run.effectiveWorkingDistanceMeters / 1000.0)).rounded(toPlaces: 2)
                let unit = context.useMetric ? "km" : "mi"
                let distFinal = context.useMetric ? distKm : (distKm * 0.621371).rounded(toPlaces: 2)
                let isPrimer = run.framboiseTags.contains("prescribedDrill") || run.prescribedDrillName != nil || (run.duration <= 1200 && run.percentZone4 < 0.25)
                let targetMet = isPrimer ? true : nil
                let grade: String? = nil
                let hr = run.workingAvgHeartRate > 0 ? Int(run.workingAvgHeartRate) : (run.rawAvgHeartRate > 0 ? Int(run.rawAvgHeartRate) : nil)
                let cad = run.workingAvgCadence > 0 ? Int(run.workingAvgCadence) : (run.rawAvgCadence > 0 ? Int(run.rawAvgCadence) : nil)

                return CompletedWorkoutSummary(
                    type: run.normalizedClassification,
                    minutes: durMins,
                    distance: distFinal,
                    unit: unit,
                    grade: grade,
                    targetMet: targetMet,
                    avgHeartRate: hr,
                    avgCadence: cad
                )
            }

            // 3. Planned session for this date
            let planned = SessionSynthesisEngine.plannedSession(
                on: dateStart,
                runRecords: context.runRecords,
                activeGoal: context.activeGoal,
                profile: context.profile,
                useMetric: context.useMetric,
                now: now,
                calendar: calendar
            )

            // 4. Completion status
            let completion: ScheduleDay.CompletionStatus
            if !runsOnDay.isEmpty {
                let hasMainRun = runsOnDay.contains { run in
                    let isPrimer = run.framboiseTags.contains("prescribedDrill") || run.prescribedDrillName != nil || (run.duration <= 1200 && run.percentZone4 < 0.25)
                    return !isPrimer && run.duration >= 1200
                }
                completion = hasMainRun ? .completed : .partial
            } else if dateStart > today {
                completion = .upcoming
            } else if planned.kind == .rest {
                completion = .completed
            } else if dateStart < today {
                completion = .missed
            } else {
                completion = .pending
            }

            return ScheduleDay(
                date: isoDate,
                weekday: weekday,
                relative: relative,
                completion: completion,
                completed: completedSummaries,
                planned: planned
            )
        }
    }

    /// Formats a token-dense plain-text summary of the evaluated schedule for on-device LLM consumption.
    public static func formatCompactScheduleSummary(days: [ScheduleDay]) -> String {
        guard !days.isEmpty else { return "No schedule days planned." }
        var lines: [String] = ["SCHEDULE TIMELINE:"]
        for day in days {
            let relativePrefix: String
            switch day.relative {
            case .today:
                relativePrefix = "Today (\(day.weekday))"
            case .tomorrow:
                relativePrefix = "Tomorrow (\(day.weekday))"
            case .past, .future:
                relativePrefix = "\(day.weekday) (\(day.date))"
            }

            var parts: [String] = []

            // Completed workouts on this calendar day
            if !day.completed.isEmpty {
                let completedStr = day.completed.map { summary in
                    "\(summary.distance) \(summary.unit) \(summary.type) (COMPLETED)"
                }.joined(separator: ", ")
                parts.append(completedStr)
            }

            // Planned status for this calendar day
            if day.planned.kind == .rest {
                if day.completed.isEmpty {
                    parts.append("Rest & Recovery")
                }
            } else {
                var plannedDesc = "\(day.planned.title) (\(day.planned.minutesLow)-\(day.planned.minutesHigh) min"
                if day.planned.minutesLow == day.planned.minutesHigh {
                    plannedDesc = "\(day.planned.title) (\(day.planned.minutesLow) min"
                }
                if let pace = day.planned.paceBand {
                    plannedDesc += " @ \(pace)"
                }
                plannedDesc += ")"
                if let primer = day.planned.primerTitle {
                    plannedDesc += ", Primer: \(primer)"
                }
                if day.completion == .missed {
                    parts.append("Missed: \(plannedDesc)")
                } else if day.completed.isEmpty {
                    parts.append("Planned: \(plannedDesc)")
                } else {
                    parts.append("Target: \(plannedDesc)")
                }
            }

            let line = "• \(relativePrefix): " + parts.joined(separator: " | ")
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
