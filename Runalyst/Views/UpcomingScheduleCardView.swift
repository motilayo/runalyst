import SwiftUI

/// Reusable upcoming weekly training schedule card shared across WorkoutsView and AnalystChatView.
/// Provides high-scannability color-coded workout categories, distinct SF symbols, and clean telemetry badges.
struct UpcomingScheduleCardView: View {
    let microcycle: [MicrocycleDay]

    enum ScheduleCategory {
        case rest
        case longRun
        case speedTempo
        case steadyAerobic
        case easyRecovery

        var icon: String {
            switch self {
            case .rest: return "bed.double.fill"
            case .longRun: return "figure.run"
            case .speedTempo: return "bolt.fill"
            case .steadyAerobic: return "figure.run"
            case .easyRecovery: return "leaf.fill"
            }
        }

        var color: Color {
            switch self {
            case .rest: return Color(UIColor.secondaryLabel)
            case .longRun: return Color(red: 0.35, green: 0.45, blue: 0.95) // Deep Indigo / Royal Blue
            case .speedTempo: return Color(red: 1.0, green: 0.55, blue: 0.0) // Vibrant Amber
            case .steadyAerobic: return Color(red: 0.0, green: 0.55, blue: 1.0) // Electric Blue
            case .easyRecovery: return Color(red: 0.0, green: 0.78, blue: 0.55) // Emerald / Mint Green
            }
        }

        nonisolated static func category(for day: MicrocycleDay) -> ScheduleCategory {
            if day.isRestDay || day.iconName == "bed.double.fill" || day.sessionTitle.localizedCaseInsensitiveContains("rest") {
                return .rest
            }
            let lower = day.sessionTitle.lowercased()
            if lower.contains("long") || day.iconName.contains("curvepath") {
                return .longRun
            }
            if lower.contains("interval") || lower.contains("surge") || lower.contains("stride")
                || lower.contains("tempo") || lower.contains("pyramid") || lower.contains("hill")
                || lower.contains("threshold") || day.iconName == "bolt.fill" || day.iconName == "flag.fill" {
                return .speedTempo
            }
            if lower.contains("recovery") || lower.contains("flush") || lower.contains("easy")
                || lower.contains("zone 1") || lower.contains("aerobic consistency") || day.iconName == "leaf.fill" {
                return .easyRecovery
            }
            return .steadyAerobic
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("UPCOMING SCHEDULE")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(microcycle.enumerated()), id: \.element.id) { index, day in
                    let category = ScheduleCategory.category(for: day)
                    let parsed = Self.parseSessionSchedule(day.sessionTitle)

                    HStack(spacing: 10) {
                        // Category Icon Badge in Tinted Container
                        ZStack {
                            Circle()
                                .fill(category.color.opacity(0.12))
                                .frame(width: 28, height: 28)

                            Image(systemName: category.icon)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(category.color)
                        }

                        // Day of Week
                        Text(day.dayLabel)
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(category == .rest ? .secondary : .primary)
                            .frame(width: day.dayLabel.count > 4 ? nil : 36, alignment: .leading)
                            .lineLimit(1)

                        // Clean Workout Title
                        Text(parsed.name)
                            .font(.subheadline.weight(category == .rest ? .regular : .semibold))
                            .foregroundColor(category == .rest ? .secondary : .primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        Spacer(minLength: 6)

                        // Telemetry Badge (Distance / Duration)
                        if let detail = parsed.detail, detail != "0 min" && !day.isRestDay {
                            Text(detail)
                                .font(.system(size: 11, weight: .bold))
                                .monospacedDigit()
                                .foregroundColor(category.color)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(category.color.opacity(0.10))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(minHeight: 44)

                    if index < microcycle.count - 1 {
                        Divider()
                            .padding(.leading, 52)
                    }
                }
            }
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(UIColor.separator).opacity(0.15), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        }
        .padding(.top, 4)
    }

    /// Robust parsing extracting workout display name and trailing or parenthesized telemetry detail.
    nonisolated public static func parseSessionSchedule(_ rawTitle: String) -> (name: String, detail: String?) {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Explicit bullet separator: "Easy Run • 8 km"
        if title.contains(" • ") {
            let parts = title.components(separatedBy: " • ")
            return (parts[0], parts.count > 1 ? parts[1] : nil)
        }

        // 2. Parenthesized detail: "Aerobic Consistency Run (8 km)" or "Zone 2 Steady (45m)"
        if let openParen = title.range(of: " ("), title.hasSuffix(")") {
            let name = String(title[..<openParen.lowerBound])
            let detail = String(title[openParen.upperBound...].dropLast())
            return (name, detail)
        }

        // 3. Leading distance: "6 km Easy Aerobic Run" or "4.5 mi Easy Run"
        let leadingRegex = try? NSRegularExpression(
            pattern: #"^(\d+(?:\.\d+)?\s*(?:km|mi))\s+(.+)$"#,
            options: .caseInsensitive
        )
        if let match = leadingRegex?.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) {
            if let distRange = Range(match.range(at: 1), in: title),
               let nameRange = Range(match.range(at: 2), in: title) {
                let detail = String(title[distRange])
                let name = String(title[nameRange])
                return (name, detail)
            }
        }

        // 4. Trailing distance or duration: "Long Run 14 km", "Long Run 8.5 mi", "Zone 2 Steady 45m"
        let trailingRegex = try? NSRegularExpression(
            pattern: #"^(.+?)\s+(\d+(?:\.\d+)?\s*(?:km|mi|min|m))$"#,
            options: .caseInsensitive
        )
        if let match = trailingRegex?.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) {
            if let nameRange = Range(match.range(at: 1), in: title),
               let detailRange = Range(match.range(at: 2), in: title) {
                let name = String(title[nameRange])
                let detail = String(title[detailRange])
                return (name, detail)
            }
        }

        return (title, nil)
    }
}
