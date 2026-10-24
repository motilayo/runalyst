import SwiftUI
import SwiftData

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
                    title: "4-WEEK AVG VOLUME",
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

    // MARK: - Deterministic Mathematical Evaluation

    private func computeGoalSpec() -> GoalSpecData {
        let cal = Calendar.current
        let now = Date()
        let thirtyDaysAgo = cal.date(byAdding: .day, value: -30, to: now) ?? now.addingTimeInterval(-30 * 24 * 3600)
        let recentRuns = allRuns.filter { $0.date >= thirtyDaysAgo && $0.date <= now }

        let totalMeters30Days = recentRuns.reduce(0.0) { $0 + $1.totalDistanceMeters }
        let weeklyAvgKm = (totalMeters30Days / 1000.0) / (30.0 / 7.0)
        let weeklyAvgDistanceFormatted = formatDistance(km: weeklyAvgKm) + "/wk"

        let longestRecentRunMeters = recentRuns.map(\.totalDistanceMeters).max()
            ?? allRuns.map(\.totalDistanceMeters).max()
            ?? 0.0
        let longestRecentRunKm = longestRecentRunMeters / 1000.0

        let uniqueDays = Set(recentRuns.map { cal.startOfDay(for: $0.date) })
        let runsPerWeek = Double(uniqueDays.count) / (30.0 / 7.0)

        guard !allRuns.isEmpty else {
            return GoalSpecData(
                statusLabel: "Needs Data",
                statusColor: .secondary,
                progressRatio: 0.0,
                progressTitle: "Initial Evaluation",
                progressValueFormatted: formatDistance(km: 0.0),
                percentageFormatted: "0%",
                weeklyVolumeFormatted: "0.0 " + (useMetricSystem ? "km" : "mi") + "/wk",
                secondaryIcon: "figure.run",
                secondaryTitle: "LONGEST RUN",
                secondaryValueFormatted: "—",
                secondaryColor: .purple,
                coachingRationale: "Complete your first recorded run to activate goal tracking and progress insights."
            )
        }

        switch trainingGoal {
        case "5K Race":
            let targetKm = 5.0
            let ratio = min(1.0, longestRecentRunKm / targetKm)
            let percentInt = Int((ratio * 100).rounded())
            let status = ratio >= 0.90 ? ("Race Ready", Color.green) : (ratio >= 0.60 ? ("On Track", Color.green) : ("Building Base", Color.blue))
            let note = ratio >= 0.90
                ? "Your longest run covers the 5K distance. Focus on cadence pyramids and tempo surges to sharpen your race pace."
                : "Aerobic stamina is developing. Progress your weekly longest run toward 5 km with comfortable, conversational pacing."
            return GoalSpecData(
                statusLabel: status.0,
                statusColor: status.1,
                progressRatio: ratio,
                progressTitle: "Longest Prep Run",
                progressValueFormatted: "\(formatDistance(km: longestRecentRunKm)) / \(formatDistance(km: targetKm))",
                percentageFormatted: "\(percentInt)%",
                weeklyVolumeFormatted: weeklyAvgDistanceFormatted,
                secondaryIcon: "stopwatch.fill",
                secondaryTitle: "LONGEST RUN",
                secondaryValueFormatted: formatDistance(km: longestRecentRunKm),
                secondaryColor: .purple,
                coachingRationale: note
            )

        case "10K Race":
            let targetKm = 10.0
            let ratio = min(1.0, longestRecentRunKm / targetKm)
            let percentInt = Int((ratio * 100).rounded())
            let status = ratio >= 0.90 ? ("Race Ready", Color.green) : (ratio >= 0.60 ? ("On Track", Color.green) : ("Building Base", Color.blue))
            let note = ratio >= 0.90
                ? "You have established strong 10K endurance. Maintain smooth turnover rhythm and consolidate threshold efficiency."
                : "Building endurance capability. Gradually increase your long run toward 10 km while keeping heart rate strictly controlled."
            return GoalSpecData(
                statusLabel: status.0,
                statusColor: status.1,
                progressRatio: ratio,
                progressTitle: "Longest Prep Run",
                progressValueFormatted: "\(formatDistance(km: longestRecentRunKm)) / \(formatDistance(km: targetKm))",
                percentageFormatted: "\(percentInt)%",
                weeklyVolumeFormatted: weeklyAvgDistanceFormatted,
                secondaryIcon: "stopwatch.fill",
                secondaryTitle: "LONGEST RUN",
                secondaryValueFormatted: formatDistance(km: longestRecentRunKm),
                secondaryColor: .purple,
                coachingRationale: note
            )

        case "Half Marathon":
            let targetKm = 21.097
            let simulationTargetKm = 18.0
            let ratio = min(1.0, longestRecentRunKm / simulationTargetKm)
            let percentInt = Int((min(1.0, longestRecentRunKm / targetKm) * 100).rounded())
            let status = longestRecentRunKm >= 16.0 ? ("Race Ready", Color.green) : (longestRecentRunKm >= 10.0 ? ("On Track", Color.green) : ("Building Base", Color.blue))
            let note = longestRecentRunKm >= 16.0
                ? "Long-distance foundation is primed for 21.1 km. Prioritize active recovery flushes and maintain a stable cadence floor."
                : "Solid aerobic progression. Build your long prep run progressively toward 16–18 km to lock in half-marathon readiness."
            return GoalSpecData(
                statusLabel: status.0,
                statusColor: status.1,
                progressRatio: ratio,
                progressTitle: "Longest Prep Run",
                progressValueFormatted: "\(formatDistance(km: longestRecentRunKm)) / \(formatDistance(km: targetKm))",
                percentageFormatted: "\(percentInt)%",
                weeklyVolumeFormatted: weeklyAvgDistanceFormatted,
                secondaryIcon: "figure.run",
                secondaryTitle: "LONGEST RUN",
                secondaryValueFormatted: formatDistance(km: longestRecentRunKm),
                secondaryColor: .purple,
                coachingRationale: note
            )

        case "Marathon":
            let targetKm = 42.195
            let simulationPeakKm = 32.0
            let ratio = min(1.0, longestRecentRunKm / simulationPeakKm)
            let percentInt = Int((min(1.0, longestRecentRunKm / targetKm) * 100).rounded())
            let status = longestRecentRunKm >= 28.0 ? ("Race Ready", Color.green) : (longestRecentRunKm >= 18.0 ? ("On Track", Color.green) : ("Building Base", Color.blue))
            let note = longestRecentRunKm >= 28.0
                ? "Excellent peak endurance capacity. Emphasize low-impact aerobic recovery and protect joint health leading into the race."
                : "Progressive marathon preparation underway. Continue extending weekly volume and long aerobic runs with conversational pacing."
            return GoalSpecData(
                statusLabel: status.0,
                statusColor: status.1,
                progressRatio: ratio,
                progressTitle: "Longest Prep Run",
                progressValueFormatted: "\(formatDistance(km: longestRecentRunKm)) / \(formatDistance(km: targetKm))",
                percentageFormatted: "\(percentInt)%",
                weeklyVolumeFormatted: weeklyAvgDistanceFormatted,
                secondaryIcon: "figure.run",
                secondaryTitle: "LONGEST RUN",
                secondaryValueFormatted: formatDistance(km: longestRecentRunKm),
                secondaryColor: .purple,
                coachingRationale: note
            )

        case "Injury Recovery":
            let validCadenceRuns = recentRuns.filter { $0.workingAvgCadence > 0 }
            let avgCadence = validCadenceRuns.isEmpty ? 0 : Int(validCadenceRuns.map(\.workingAvgCadence).reduce(0, +) / Double(validCadenceRuns.count))
            let targetRatio = 0.85
            let easyRunsCount = recentRuns.filter { $0.normalizedClassification == "Easy Run" || $0.workingAvgHeartRate < 145 }.count
            let easyRatio = recentRuns.isEmpty ? 1.0 : Double(easyRunsCount) / Double(recentRuns.count)
            let progressRatio = min(1.0, easyRatio / targetRatio)
            let percentInt = Int((easyRatio * 100).rounded())
            let status = easyRatio >= 0.75 ? ("Protected", Color.green) : ("Caution", Color.orange)
            let cadenceText = avgCadence > 0 ? "\(avgCadence) SPM" : "—"
            return GoalSpecData(
                statusLabel: status.0,
                statusColor: status.1,
                progressRatio: progressRatio,
                progressTitle: "Aerobic Control Adherence",
                progressValueFormatted: "\(percentInt)% Easy Volume",
                percentageFormatted: "\(Int((progressRatio * 100).rounded()))%",
                weeklyVolumeFormatted: weeklyAvgDistanceFormatted,
                secondaryIcon: "metronome.fill",
                secondaryTitle: "AVG CADENCE",
                secondaryValueFormatted: cadenceText,
                secondaryColor: Color(red: 0.0, green: 0.8, blue: 0.65),
                coachingRationale: "Low aerobic strain and controlled cadence protect joints while allowing biological tissues to adapt safely."
            )

        case "Just for Fun":
            let targetWeeklyRuns = 3.0
            let ratio = min(1.0, runsPerWeek / targetWeeklyRuns)
            let percentInt = Int((ratio * 100).rounded())
            let status = ratio >= 0.8 ? ("Active", Color.green) : ("Building", Color.blue)
            let frequencyText = String(format: "%.1f runs/wk", runsPerWeek)
            return GoalSpecData(
                statusLabel: status.0,
                statusColor: status.1,
                progressRatio: ratio,
                progressTitle: "Weekly Consistency",
                progressValueFormatted: frequencyText,
                percentageFormatted: "\(percentInt)%",
                weeklyVolumeFormatted: weeklyAvgDistanceFormatted,
                secondaryIcon: "flame.fill",
                secondaryTitle: "FREQUENCY",
                secondaryValueFormatted: frequencyText,
                secondaryColor: .orange,
                coachingRationale: "Enjoying the rhythm of running. Consistent relaxed outings build lasting vitality and mental clarity."
            )

        default: // "Base Building"
            let targetWeeklyKm = 30.0
            let ratio = min(1.0, weeklyAvgKm / targetWeeklyKm)
            let percentInt = Int((ratio * 100).rounded())
            let status = ratio >= 0.85 ? ("Solid Base", Color.green) : (ratio >= 0.50 ? ("On Track", Color.green) : ("Building", Color.blue))
            let note = ratio >= 0.85
                ? "Aerobic engine is solidly established. You have built a durable foundation for structured quality workouts or race blocks."
                : "Steadily expanding weekly volume. Keep runs primarily in Zone 2 to stimulate mitochondrial density without fatigue."
            return GoalSpecData(
                statusLabel: status.0,
                statusColor: status.1,
                progressRatio: ratio,
                progressTitle: "Weekly Aerobic Base",
                progressValueFormatted: "\(formatDistance(km: weeklyAvgKm)) / \(formatDistance(km: targetWeeklyKm))",
                percentageFormatted: "\(percentInt)%",
                weeklyVolumeFormatted: weeklyAvgDistanceFormatted,
                secondaryIcon: "figure.run",
                secondaryTitle: "LONGEST RUN",
                secondaryValueFormatted: formatDistance(km: longestRecentRunKm),
                secondaryColor: .purple,
                coachingRationale: note
            )
        }
    }

    private func formatDistance(km: Double) -> String {
        if useMetricSystem {
            return String(format: "%.1f km", km)
        } else {
            let mi = km * 0.621371
            return String(format: "%.1f mi", mi)
        }
    }
}

// MARK: - Goal Spec Presentation Model

private struct GoalSpecData {
    let statusLabel: String
    let statusColor: Color
    let progressRatio: Double
    let progressTitle: String
    let progressValueFormatted: String
    let percentageFormatted: String
    let weeklyVolumeFormatted: String
    let secondaryIcon: String
    let secondaryTitle: String
    let secondaryValueFormatted: String
    let secondaryColor: Color
    let coachingRationale: String
}
