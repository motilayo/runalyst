import SwiftUI
import RunalystCore

struct MilestoneBadge: Identifiable {
    let spec: MilestoneBadgeSpec
    let accentColor: Color

    var id: String { spec.id }
    var title: String { spec.title }
    var iconName: String { spec.iconName }
    var description: String { spec.description }
    var isUnlocked: Bool { spec.isUnlocked }
}

struct LifetimeMilestonesCard: View {
    var allRuns: [RunRecord]
    @AppStorage("useMetricSystem") private var useMetricSystem: Bool = Locale.current.measurementSystem == .metric
    @State private var selectedBadge: MilestoneBadge?
    @State private var navigatedRun: RunRecord?

    private var recordsSummary: PersonalRecordsSummaryCore {
        let valid = allRuns.filter { !$0.isDeleted }.map { $0.toMilestoneRunSample() }
        return LifetimeMilestonesCore.evaluate(samples: valid)
    }

    private var totalDistanceMeters: Double {
        recordsSummary.totalDistanceMeters
    }

    private var totalDurationSeconds: TimeInterval {
        recordsSummary.totalDurationSeconds
    }

    private var formattedTotalDistance: String {
        let distance = useMetricSystem ? (totalDistanceMeters / 1000.0) : (totalDistanceMeters / 1609.344)
        let unit = useMetricSystem ? "km" : "mi"
        return String(format: "%.1f %@", distance, unit)
    }

    private var formattedTotalTime: String {
        let hours = Int(totalDurationSeconds) / 3600
        let minutes = (Int(totalDurationSeconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    private var longestRunFormatted: String {
        guard recordsSummary.longestRunMeters > 0 else { return "—" }
        let distance = useMetricSystem ? (recordsSummary.longestRunMeters / 1000.0) : (recordsSummary.longestRunMeters / 1609.344)
        let unit = useMetricSystem ? "km" : "mi"
        return String(format: "%.1f %@", distance, unit)
    }

    private var fastestPaceFormatted: String {
        guard let minPace = recordsSummary.fastestPaceSecondsPerKm else { return "—" }
        return PaceFormatter.formatPace(secondsPerKilometer: minPace)
    }

    private var highestCadenceFormatted: String {
        guard let maxCadence = recordsSummary.peakCadenceSPM else { return "—" }
        return "\(Int(maxCadence)) SPM"
    }

    private var peakEfficiencyFactorFormatted: String {
        guard let maxEF = recordsSummary.peakEfficiencyFactor else { return "—" }
        return String(format: "%.2f", maxEF)
    }

    private var milestoneBadges: [MilestoneBadge] {
        recordsSummary.badges.map { spec in
            MilestoneBadge(
                spec: spec,
                accentColor: color(for: spec.accentColorName)
            )
        }
    }

    private func color(for colorName: String) -> Color {
        switch colorName {
        case "blue": return .blue
        case "orange": return .orange
        case "yellow": return .yellow
        case "purple": return .purple
        case "cyan": return .cyan
        case "indigo": return .indigo
        case "teal": return .teal
        case "pink": return .pink
        case "green": return .green
        default: return .blue
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "trophy.fill")
                    .foregroundColor(.yellow)
                    .font(.headline)
                Text("Lifetime Volume & Milestones")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                Text("\(allRuns.count) Total Runs")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
            }

            // Hero Volume Stats Grid
            HStack(spacing: 12) {
                // Total Distance
                VStack(alignment: .leading, spacing: 4) {
                    Text("TOTAL DISTANCE")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                    Text(formattedTotalDistance)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(UIColor.tertiarySystemFill))
                .cornerRadius(12)

                // Total Time
                VStack(alignment: .leading, spacing: 4) {
                    Text("TIME ON FEET")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                    Text(formattedTotalTime)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(UIColor.tertiarySystemFill))
                .cornerRadius(12)
            }

            // Personal Records 2x2 Grid (Eliminates Cramping and Tiny Icons)
            VStack(alignment: .leading, spacing: 8) {
                Text("PERSONAL RECORDS")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    // Longest Run
                    personalRecordCell(
                        icon: "road.lanes",
                        iconColor: .indigo,
                        title: "Longest Run",
                        value: longestRunFormatted,
                        subtitle: "Single effort"
                    )

                    // Fastest Pace
                    personalRecordCell(
                        icon: "speedometer",
                        iconColor: Color(red: 0.0, green: 0.55, blue: 1.0),
                        title: "Best Pace",
                        value: fastestPaceFormatted,
                        subtitle: useMetricSystem ? "Min / km" : "Min / mi"
                    )

                    // Peak Cadence
                    personalRecordCell(
                        icon: "metronome.fill",
                        iconColor: Color(red: 0.18, green: 0.82, blue: 0.35),
                        title: "Peak Cadence",
                        value: highestCadenceFormatted,
                        subtitle: "Turnover rhythm"
                    )

                    // Peak Efficiency Factor
                    personalRecordCell(
                        icon: "bolt.heart.fill",
                        iconColor: Color(red: 1.0, green: 0.22, blue: 0.55),
                        title: "Aerobic EF",
                        value: peakEfficiencyFactorFormatted,
                        subtitle: "Speed ÷ HR"
                    )
                }
            }

            // Milestone Badges 3-Column Medallion Grid
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("MILESTONE BADGES")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                    Spacer()
                    let unlockedCount = milestoneBadges.filter(\.isUnlocked).count
                    Text("\(unlockedCount) of \(milestoneBadges.count) Unlocked")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 16) {
                    ForEach(milestoneBadges) { badge in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            selectedBadge = badge
                        } label: {
                            VStack(spacing: 8) {
                                MetallicMedallionView(spec: badge.spec, accentColor: badge.accentColor, size: 74)

                                Text(badge.spec.title)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(badge.spec.isUnlocked ? .primary : .secondary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)

                                Text(badge.spec.earnedMetricSubtitle(useMetric: useMetricSystem))
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundColor(badge.spec.isUnlocked ? badge.accentColor : .secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .liquidGlass(cornerRadius: 16, padding: 16, accentColor: .yellow)
        .padding(.horizontal)
        .sheet(item: $selectedBadge) { badge in
            let qualifyingRun = allRuns.first(where: { $0.id == badge.spec.qualifyingRunID })
            MilestoneAwardDetailSheet(
                spec: badge.spec,
                accentColor: badge.accentColor,
                qualifyingRun: qualifyingRun,
                useMetricSystem: useMetricSystem,
                onSelectWorkout: { run in
                    selectedBadge = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                        navigatedRun = run
                    }
                }
            )
        }
        .navigationDestination(item: $navigatedRun) { run in
            RunDetailView(runRecord: run)
        }
    }

    private func personalRecordCell(
        icon: String,
        iconColor: Color,
        title: String,
        value: String,
        subtitle: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.12))
                        .frame(width: 24, height: 24)
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(iconColor)
                }

                Text(title.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(UIColor.tertiarySystemFill))
        .cornerRadius(12)
    }
}
