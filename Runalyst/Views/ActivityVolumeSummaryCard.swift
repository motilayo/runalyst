import SwiftUI

/// Displays aggregate running volume, moving time, and visual workout distribution
/// for the selected time range (7 Days or 30 Days).
struct ActivityVolumeSummaryCard: View {
    let runs: [RunRecord]
    let timeRange: String
    let useMetricSystem: Bool
    var activeGoal: String = "Base Building"

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US_POSIX")
        cal.firstWeekday = 1
        return cal
    }

    private var totalDistanceMeters: Double {
        runs.map(\.totalDistanceMeters).reduce(0, +)
    }

    private var totalDurationSeconds: TimeInterval {
        runs.map(\.duration).reduce(0, +)
    }

    private var formattedTotalDistance: (value: String, unit: String) {
        let converted = useMetricSystem ? (totalDistanceMeters / 1000.0) : (totalDistanceMeters / 1609.344)
        let unit = useMetricSystem ? "km" : "mi"
        return (String(format: "%.1f", converted), unit)
    }

    private var formattedTotalDuration: String {
        let totalSeconds = Int(totalDurationSeconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    private var activeDaysCount: Int {
        Set(runs.map { calendar.startOfDay(for: $0.date) }).count
    }

    // MARK: - 7-Day Day-by-Day Volume
    private struct DayVolume: Identifiable {
        let id = UUID()
        let date: Date
        let dayLetter: String
        let dayNumber: String
        let distanceMeters: Double
        let isToday: Bool
        let hasRun: Bool
    }

    private var trailing7Days: [DayVolume] {
        let today = calendar.startOfDay(for: Date())
        let letterFormatter = DateFormatter()
        letterFormatter.dateFormat = "EEEEE"
        letterFormatter.locale = Locale(identifier: "en_US_POSIX")

        let numberFormatter = DateFormatter()
        numberFormatter.dateFormat = "d"
        numberFormatter.locale = Locale(identifier: "en_US_POSIX")

        let dayOffsets: [Int] = [6, 5, 4, 3, 2, 1, 0]
        return dayOffsets.map { daysAgo in
            guard let dayDate = calendar.date(byAdding: .day, value: -daysAgo, to: today) else {
                return DayVolume(date: today, dayLetter: "", dayNumber: "", distanceMeters: 0, isToday: false, hasRun: false)
            }
            let dayRuns = runs.filter { calendar.isDate($0.date, inSameDayAs: dayDate) }
            let dayDistance = dayRuns.map(\.totalDistanceMeters).reduce(0, +)

            return DayVolume(
                date: dayDate,
                dayLetter: letterFormatter.string(from: dayDate),
                dayNumber: numberFormatter.string(from: dayDate),
                distanceMeters: dayDistance,
                isToday: daysAgo == 0,
                hasRun: !dayRuns.isEmpty
            )
        }
    }

    // MARK: - 30-Day 4-Week Volume
    private struct WeekVolume: Identifiable {
        let id = UUID()
        let label: String
        let distanceMeters: Double
        let runCount: Int
    }

    private var trailing4Weeks: [WeekVolume] {
        let tc = TrainingCalendar(calendar: calendar, now: Date())
        let currentWeek = tc.weekInterval(containing: Date())
        let currentSunday = currentWeek.start

        let weekOffsets: [(label: String, weeksAgo: Int)] = [
            ("3W Ago", 3),
            ("2W Ago", 2),
            ("Last Wk", 1),
            ("This Wk", 0)
        ]

        return weekOffsets.map { item in
            guard let startDate = calendar.date(byAdding: .day, value: -(item.weeksAgo * 7), to: currentSunday),
                  let nextSunday = calendar.date(byAdding: .day, value: 7, to: startDate) else {
                return WeekVolume(label: item.label, distanceMeters: 0, runCount: 0)
            }
            let weekRuns = runs.filter { $0.date >= startDate && $0.date < nextSunday }
            let dist = weekRuns.map(\.totalDistanceMeters).reduce(0, +)
            return WeekVolume(
                label: item.label,
                distanceMeters: dist,
                runCount: weekRuns.count
            )
        }
    }

    private var classificationMix: [(name: String, count: Int, color: Color)] {
        var counts: [String: Int] = [:]
        for run in runs {
            let name = run.detectedTypeRaw.isEmpty ? run.normalizedClassification : run.detectedTypeRaw
            counts[name, default: 0] += 1
        }
        let order = ["Easy Run", "Steady Effort", "Tempo Run", "Intervals", "Progression Run", "Long Run"]
        return order.compactMap { key in
            guard let count = counts[key], count > 0 else { return nil }
            return (name: key, count: count, color: colorForClassification(key))
        }
    }

    private func colorForClassification(_ name: String) -> Color {
        switch name {
        case "Easy Run", "Recovery Run": return Color.green
        case "Steady Effort": return Color.blue
        case "Tempo Run": return Color.orange
        case "Intervals", "Cadence Pyramids": return Color.purple
        case "Long Run": return Color.teal
        default: return Color.secondary
        }
    }

    // MARK: - Body View
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header Row: Title & Active Goal Badge
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Image(systemName: "figure.run")
                        .foregroundColor(.blue)
                        .font(.subheadline.bold())
                    Text("TRAINING VOLUME • \(timeRange.uppercased())")
                        .font(.caption.bold())
                        .foregroundColor(.blue)
                }

                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("\(runs.count) \(runs.count == 1 ? "run" : "runs")")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.12))
                .clipShape(Capsule())
            }

            // Primary Big Stat Row: Total Distance & Duration & Active Days
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                // Distance Block
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formattedTotalDistance.value)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundColor(.primary)
                    Text(formattedTotalDistance.unit)
                        .font(.subheadline.bold())
                        .foregroundColor(.secondary)
                }
                .fixedSize(horizontal: true, vertical: false)

                Divider()
                    .frame(height: 28)

                // Time Block
                VStack(alignment: .leading, spacing: 2) {
                    Text("TIME")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                    Text(formattedTotalDuration)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.primary)
                }

                Divider()
                    .frame(height: 28)

                // Active Days Block
                VStack(alignment: .leading, spacing: 2) {
                    Text("ACTIVE")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                    Text("\(activeDaysCount) \(activeDaysCount == 1 ? "day" : "days")")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.primary)
                }

                Spacer()
            }

            Divider()
                .background(Color(UIColor.separator).opacity(0.3))

            // Visual Rhythm / Distribution Section
            if timeRange == "7 Days" {
                weeklyDailyRhythmView
            } else {
                monthlyProgressionView
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: 16, padding: 16, accentColor: .blue)
    }

    // MARK: - 7-Day Visual Day Bar Strip
    @ViewBuilder
    private var weeklyDailyRhythmView: some View {
        let maxDist = max(1000.0, trailing7Days.map(\.distanceMeters).max() ?? 1000.0)

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Daily Rhythm")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                Spacer()
            }

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(trailing7Days) { day in
                    VStack(spacing: 6) {
                        // Distance readout above bar
                        if day.distanceMeters > 0 {
                            let converted = useMetricSystem ? (day.distanceMeters / 1000.0) : (day.distanceMeters / 1609.344)
                            Text(String(format: "%.1f", converted))
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(.primary)
                        } else {
                            Text("—")
                                .font(.system(size: 10, weight: .regular))
                                .foregroundColor(.secondary.opacity(0.5))
                        }

                        // Bar Capsule
                        ZStack(alignment: .bottom) {
                            Capsule()
                                .fill(Color(UIColor.secondarySystemFill))
                                .frame(width: 24, height: 48)

                            if day.distanceMeters > 0 {
                                let ratio = max(0.2, min(1.0, day.distanceMeters / maxDist))
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.blue, Color(red: 0.0, green: 0.8, blue: 0.65)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .frame(width: 24, height: 48 * ratio)
                            }
                        }

                        // Day Letter & Number
                        VStack(spacing: 1) {
                            Text(day.dayLetter)
                                .font(.caption.bold())
                                .foregroundColor(day.isToday ? .blue : .primary)

                            Text(day.dayNumber)
                                .font(.system(size: 10, weight: .regular))
                                .monospacedDigit()
                                .foregroundColor(day.isToday ? .blue : .secondary)
                        }
                        .padding(.vertical, 2)
                        .padding(.horizontal, 4)
                        .background(day.isToday ? Color.blue.opacity(0.12) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - 30-Day 4-Week Progression View
    @ViewBuilder
    private var monthlyProgressionView: some View {
        let maxWeekDist = max(1000.0, trailing4Weeks.map(\.distanceMeters).max() ?? 1000.0)

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("4-Week Mileage Progression")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                Spacer()
            }

            // 4-Week Horizontal Bar Rows
            VStack(spacing: 6) {
                ForEach(trailing4Weeks) { week in
                    HStack(spacing: 8) {
                        Text(week.label)
                            .font(.caption2.bold())
                            .foregroundColor(.secondary)
                            .frame(width: 52, alignment: .leading)

                        // Progress Bar
                        GeometryReader { geo in
                            let ratio = max(0.04, min(1.0, week.distanceMeters / maxWeekDist))
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color(UIColor.secondarySystemFill))
                                    .frame(height: 10)

                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.blue, Color(red: 0.0, green: 0.8, blue: 0.65)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: geo.size.width * ratio, height: 10)
                            }
                        }
                        .frame(height: 10)

                        // Distance Text
                        let converted = useMetricSystem ? (week.distanceMeters / 1000.0) : (week.distanceMeters / 1609.344)
                        HStack(spacing: 2) {
                            Text(String(format: "%.1f", converted))
                                .font(.caption.bold())
                                .monospacedDigit()
                                .foregroundColor(.primary)
                            Text(useMetricSystem ? "km" : "mi")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .frame(width: 60, alignment: .trailing)
                    }
                }
            }

            // Workout Classification Mix Pills
            if !classificationMix.isEmpty {
                Divider()
                    .background(Color(UIColor.separator).opacity(0.3))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(classificationMix, id: \.name) { mix in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(mix.color)
                                    .frame(width: 6, height: 6)
                                Text("\(mix.name): \(mix.count)")
                                    .font(.caption2.bold())
                                    .foregroundColor(.primary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(mix.color.opacity(0.12))
                            .clipShape(Capsule())
                        }
                    }
                }
            }
        }
    }
}
