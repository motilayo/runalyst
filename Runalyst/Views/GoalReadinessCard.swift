import SwiftUI
import SwiftData
import RunalystCore

/// Apple Health-style Goal Readiness & Progress Card for the Analysis tab.
/// Connects the runner's chosen training goal in User Profile to empirical SwiftData telemetry.
struct GoalReadinessCard: View {
    var allRuns: [RunRecord]
    var onEditGoal: (() -> Void)?

    @AppStorage("trainingGoal") private var trainingGoal: String = "Base Building"
    @AppStorage("useMetricSystem") private var useMetricSystem: Bool = Locale.current.measurementSystem == .metric

    var body: some View {
        let spec = computeGoalSpec()

        VStack(alignment: .leading, spacing: 14) {
            // Header: Category label + Edit in Profile button
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(Color.purple.opacity(0.14))
                            .frame(width: 24, height: 24)
                        Image(systemName: "target")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.purple)
                    }

                    Text("CURRENT GOAL")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.purple)
                }

                Spacer()

                if let onEditGoal {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onEditGoal()
                    } label: {
                        HStack(spacing: 4) {
                            Text("Edit")
                                .font(.caption.weight(.semibold))
                            Image(systemName: "pencil")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.10))
                        .clipShape(Capsule())
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Edit Training Goal")
                    .accessibilityHint("Opens User Profile to change your target running goal")
                }
            }

            // Goal Title & Readiness Status Badge
            HStack(alignment: .firstTextBaseline) {
                Text(trainingGoal)
                    .font(.title3.weight(.bold))
                    .foregroundColor(.primary)

                Spacer()

                HStack(spacing: 5) {
                    Circle()
                        .fill(spec.statusColor)
                        .frame(width: 6, height: 6)
                    Text(spec.statusLabel)
                        .font(.caption.bold())
                        .foregroundColor(spec.statusColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(spec.statusColor.opacity(0.12))
                .clipShape(Capsule())
            }

            // Progress Bar & Labels
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(spec.progressTitle)
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)

                    Spacer()

                    HStack(spacing: 4) {
                        Text(spec.progressValueFormatted)
                            .font(.caption.bold())
                            .monospacedDigit()
                            .foregroundColor(.primary)

                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Text(spec.percentageFormatted)
                            .font(.caption.bold())
                            .monospacedDigit()
                            .foregroundColor(.accentColor)
                    }
                }

                // Progress Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(UIColor.tertiarySystemGroupedBackground))
                            .frame(height: 8)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue, Color.purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(8, geo.size.width * CGFloat(min(1.0, max(0.0, spec.progressRatio)))), height: 8)
                    }
                }
                .frame(height: 8)
            }

            // 2-Column Telemetry Cells (Weekly Volume & Complementary Stat)
            HStack(spacing: 10) {
                telemetryCell(
                    icon: "calendar",
                    title: spec.weeklyVolumeTitle,
                    value: spec.weeklyVolumeFormatted,
                    color: .blue
                )

                telemetryCell(
                    icon: spec.secondaryIcon,
                    title: spec.secondaryTitle,
                    value: spec.secondaryValueFormatted,
                    color: spec.secondaryColor
                )
            }

            // Contextual Coaching Rationale
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.purple)
                    .padding(.top, 2)

                Text(spec.coachingRationale)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.purple.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .liquidGlass(cornerRadius: 16, padding: 16, accentColor: .purple)
        .padding(.horizontal)
    }

    // MARK: - Subview Helpers

    private func telemetryCell(icon: String, title: String, value: String, color: Color) -> some View {
        MiniStatTile(
            title: title,
            value: value,
            unit: nil,
            icon: icon,
            accentColor: color
        )
    }

    // MARK: - Hollow Adapter to RunalystCore

    private func computeGoalSpec() -> GoalSpecData {
        Self.evaluateGoalSpec(
            allRuns: allRuns,
            trainingGoal: trainingGoal,
            useMetricSystem: useMetricSystem,
            now: Date()
        )
    }

    static func evaluateGoalSpec(
        allRuns: [RunRecord],
        trainingGoal: String,
        useMetricSystem: Bool,
        now: Date = Date()
    ) -> GoalSpecData {
        let activeRuns = allRuns.filter { !$0.isDeleted }
        let profile = RunnerProfile.compute(from: activeRuns, trainingGoal: trainingGoal, now: now)
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now.addingTimeInterval(-30 * 24 * 3600)
        let recentRuns = activeRuns.filter { $0.date >= thirtyDaysAgo && $0.date <= now }

        let validCadenceRuns = recentRuns.filter { $0.workingAvgCadence > 0 }
        let recentAvgCadence = validCadenceRuns.isEmpty
            ? 0
            : Int(validCadenceRuns.map(\.workingAvgCadence).reduce(0, +) / Double(validCadenceRuns.count))

        let easyRunsCount = recentRuns.filter { $0.normalizedClassification == "Easy Run" || $0.workingAvgHeartRate < 145 }.count
        let recentEasyRatio = recentRuns.isEmpty ? 1.0 : Double(easyRunsCount) / Double(recentRuns.count)

        let coreSpec = GoalBenchmarkCore.evaluateReadinessSpec(
            benchmark: profile.goalBenchmark,
            runsPerWeek: profile.runsPerWeek,
            hasAnyRuns: !activeRuns.isEmpty,
            recentEasyRunRatio: recentEasyRatio,
            recentAvgCadence: recentAvgCadence,
            useMetricSystem: useMetricSystem
        )

        return GoalSpecData(
            statusLabel: coreSpec.statusLabel,
            statusColor: mapToneToColor(coreSpec.statusTone),
            progressRatio: coreSpec.progressRatio,
            progressTitle: coreSpec.progressTitle,
            progressValueFormatted: coreSpec.progressValueFormatted,
            percentageFormatted: coreSpec.percentageFormatted,
            weeklyVolumeTitle: coreSpec.weeklyVolumeTitle,
            weeklyVolumeFormatted: coreSpec.weeklyVolumeFormatted,
            secondaryIcon: coreSpec.secondaryIcon,
            secondaryTitle: coreSpec.secondaryTitle,
            secondaryValueFormatted: coreSpec.secondaryValueFormatted,
            secondaryColor: mapToneToColor(coreSpec.secondaryTone),
            coachingRationale: coreSpec.coachingRationale
        )
    }

    private static func mapToneToColor(_ tone: String) -> Color {
        switch tone {
        case "blue": return .blue
        case "green": return .green
        case "purple": return .purple
        case "orange": return .orange
        case "red": return .red
        case "teal": return Color(red: 0.0, green: 0.8, blue: 0.65)
        default: return .secondary
        }
    }
}

// MARK: - Goal Spec Presentation Model

struct GoalSpecData {
    let statusLabel: String
    let statusColor: Color
    let progressRatio: Double
    let progressTitle: String
    let progressValueFormatted: String
    let percentageFormatted: String
    var weeklyVolumeTitle: String = "30-DAY WEEKLY AVG"
    let weeklyVolumeFormatted: String
    let secondaryIcon: String
    let secondaryTitle: String
    let secondaryValueFormatted: String
    let secondaryColor: Color
    let coachingRationale: String
}
