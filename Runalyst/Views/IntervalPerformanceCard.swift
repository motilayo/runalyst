import SwiftUI

/// Dedicated execution scorecard for unprescribed interval workouts.
/// Evaluates pacing repeatability across reps, cadence floor retention under fatigue,
/// and heart rate recovery drops between sets using User-Centered Design (UCD)
/// with progressive disclosure for effortless scanning.
struct IntervalPerformanceCard: View {
    let runRecord: RunRecord
    var baselineCadence: Double?

    @State private var isExpanded: Bool = false
    @State private var expandedRepIndices: Set<Int> = []

    var body: some View {
        let context = WorkoutAnalysisContext(
            runRecord: runRecord,
            runSignature: runRecord.signature,
            macroProfile: nil,
            recoveryTimeline: RecoveryTimeline(
                now: Date(),
                lastHard: nil,
                hardSessionsLast72h: 0,
                requiredHours: 48,
                state: .productive
            ),
            baselineStats: baselineCadence.map { (avgPace: runRecord.workingAvgPace, avgCadence: $0, avgHR: runRecord.workingAvgHeartRate) }
        )

        let evaluations = context.intervalEvaluations
        let overallGrade = context.overallGradeReport.grade
        let workSegments = context.workSegments
        let isIndoor = context.isIndoor
        let meanWorkPace = workSegments.isEmpty ? 0 : workSegments.reduce(0.0) { $0 + $1.avgPace } / Double(workSegments.count)
        let paceSpread = Int(context.workRepPaceSpreadSec)
        let avgCadence = workSegments.isEmpty ? 0 : Int(workSegments.reduce(0.0) { $0 + $1.avgCadence } / Double(workSegments.count))
        let cadenceFloor = context.runnerProfile.heightAdjustedCadenceFloor
        let validDrops = evaluations.compactMap(\.recoveryHeartRateDrop)
        let avgHRDrop: Int? = validDrops.isEmpty ? nil : Int((Double(validDrops.reduce(0, +)) / Double(validDrops.count)).rounded())

        VStack(spacing: 14) {
            // MARK: - Header
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                    .foregroundColor(.orange)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Interval Performance")
                            .font(.headline.weight(.semibold))
                            .foregroundColor(.primary)

                        HStack(spacing: 3) {
                            Image(systemName: isIndoor ? "figure.run.square.stack" : "figure.run")
                                .font(.system(size: 9, weight: .bold))
                            Text(isIndoor ? "Indoor" : "Outdoor")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .foregroundColor(isIndoor ? .purple : .blue)
                        .background((isIndoor ? Color.purple : Color.blue).opacity(0.12))
                        .clipShape(Capsule())
                    }

                    Text("\(evaluations.count) Work Reps • \(isIndoor ? "Treadmill Pacing" : "Outdoor Pacing")")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: gradeBadgeIcon(for: overallGrade))
                        .font(.caption2.bold())
                    Text("Grade \(overallGrade)")
                        .font(.caption.bold())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(gradeColor(for: overallGrade).opacity(0.12))
                .foregroundColor(gradeColor(for: overallGrade))
                .clipShape(Capsule())
            }

            // MARK: - Core Metric Stat Tiles (Pacing, Cadence Floor, HR Drop)
            HStack(spacing: 8) {
                metricTile(
                    label: "WORK PACE",
                    value: PaceFormatter.formatPace(secondsPerKilometer: meanWorkPace),
                    valueColor: paceSpread <= 15 ? .green : .orange,
                    subtitle: "±\(Int((Double(paceSpread) / 2.0).rounded()))s spread"
                )

                metricTile(
                    label: "TURNOVER",
                    value: "\(avgCadence) SPM",
                    valueColor: avgCadence >= cadenceFloor ? Color(red: 0.0, green: 0.75, blue: 0.65) : .orange,
                    subtitle: "Floor: \(cadenceFloor) SPM"
                )

                metricTile(
                    label: "AVG HR DROP",
                    value: avgHRDrop.map { "-\($0) BPM" } ?? "--",
                    valueColor: (avgHRDrop ?? 0) >= (isIndoor ? 12 : 15) ? Color(red: 0.0, green: 0.75, blue: 0.65) : .secondary,
                    subtitle: hrDropSubtitle(avgHRDrop: avgHRDrop, isIndoor: isIndoor)
                )
            }

            // MARK: - Graded Reps Section (Progressive Disclosure)
            if !evaluations.isEmpty {
                Divider()

                HStack {
                    Text("SETS (\(evaluations.count))")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)

                    Spacer()

                    if evaluations.count > 3 {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                isExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(isExpanded ? "Show Less" : "Show All (\(evaluations.count))")
                                    .font(.caption.bold())
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption2.bold())
                            }
                            .foregroundColor(.orange)
                        }
                    }
                }

                let displayedReps = isExpanded ? evaluations : Array(evaluations.prefix(3))
                VStack(spacing: 8) {
                    ForEach(displayedReps) { rep in
                        repRow(rep, cadenceFloor: cadenceFloor)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }

    // MARK: - Rep Row with Progressive Disclosure

    @ViewBuilder
    private func repRow(_ rep: IntervalRepEvaluation, cadenceFloor: Int) -> some View {
        let isRepExpanded = expandedRepIndices.contains(rep.repIndex)
        let isFastest = rep.observation.starts(with: "Fastest")

        VStack(alignment: .leading, spacing: 0) {
            // Tappable Primary Row (Scannable Bird's-Eye View)
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    if isRepExpanded {
                        expandedRepIndices.remove(rep.repIndex)
                    } else {
                        expandedRepIndices.insert(rep.repIndex)
                    }
                }
            } label: {
                VStack(spacing: 6) {
                    // Line 1: Identity & Duration & Pace & Grade
                    HStack(alignment: .center, spacing: 6) {
                        Text("Rep \(rep.repIndex)")
                            .font(.subheadline.bold())
                            .foregroundColor(.primary)

                        let durMin = Int(rep.durationSeconds) / 60
                        let durSec = Int(rep.durationSeconds) % 60
                        Text(durMin > 0 ? "\(durMin)m \(durSec)s" : "\(durSec)s")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(UIColor.tertiarySystemFill))
                            .clipShape(Capsule())

                        if isFastest {
                            Text("Fastest")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.orange)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color.orange.opacity(0.12))
                                .clipShape(Capsule())
                        }

                        Spacer()

                        Text(rep.workPaceFormatted)
                            .font(.subheadline.bold())
                            .monospacedDigit()
                            .foregroundColor(.primary)

                        Text(rep.letterGrade)
                            .font(.caption2.bold())
                            .foregroundColor(gradeColor(for: rep.letterGrade))
                            .frame(minWidth: 22)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(gradeColor(for: rep.letterGrade).opacity(0.12))
                            .clipShape(Capsule())

                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.6))
                            .rotationEffect(.degrees(isRepExpanded ? 90 : 0))
                    }

                    // Line 2: Biometrics & Recovery Summary
                    HStack(alignment: .center, spacing: 6) {
                        HStack(spacing: 4) {
                            Text("\(rep.workCadence) SPM")
                                .font(.caption)
                                .foregroundColor(rep.workCadence < cadenceFloor ? .orange : .secondary)

                            Text("·")
                                .font(.caption.bold())
                                .foregroundColor(.secondary.opacity(0.4))

                            Text("\(rep.workHeartRate) BPM")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if let recPace = rep.recoveryPaceFormatted {
                            HStack(spacing: 4) {
                                Text("Rec \(recPace)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)

                                if let drop = rep.recoveryHeartRateDrop, drop > 0 {
                                    HStack(spacing: 2) {
                                        Image(systemName: "arrow.down")
                                            .font(.system(size: 8, weight: .bold))
                                        Text("\(drop) BPM")
                                            .font(.system(size: 10, weight: .semibold))
                                    }
                                    .foregroundColor(Color(red: 0.0, green: 0.75, blue: 0.65))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(Color(red: 0.0, green: 0.75, blue: 0.65).opacity(0.12))
                                    .clipShape(Capsule())
                                }
                            }
                        } else if let drop = rep.recoveryHeartRateDrop, drop > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 8, weight: .bold))
                                Text("\(drop) BPM drop")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundColor(Color(red: 0.0, green: 0.75, blue: 0.65))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color(red: 0.0, green: 0.75, blue: 0.65).opacity(0.12))
                            .clipShape(Capsule())
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded Deep-Dive (Progressive Disclosure)
            if isRepExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                        .padding(.vertical, 4)

                    // Telemetry Breakdown Badges
                    HStack(spacing: 8) {
                        telemetryPill(
                            label: "Pacing",
                            value: paceDeltaString(rep.paceDeltaVsAverageWorkSec),
                            color: abs(rep.paceDeltaVsAverageWorkSec) <= 5 ? .green : .orange
                        )

                        let cadenceDelta = rep.workCadence - cadenceFloor
                        telemetryPill(
                            label: "Cadence",
                            value: cadenceDelta >= 0 ? "+\(cadenceDelta) vs floor" : "\(cadenceDelta) vs floor",
                            color: cadenceDelta >= 0 ? Color(red: 0.0, green: 0.75, blue: 0.65) : .orange
                        )

                        if let drop = rep.recoveryHeartRateDrop {
                            telemetryPill(
                                label: "HR Drop",
                                value: "-\(drop) BPM",
                                color: drop >= 10 ? Color(red: 0.0, green: 0.75, blue: 0.65) : .secondary
                            )
                        }
                    }

                    // Coach's Observation
                    if !rep.observation.isEmpty {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10))
                                .foregroundColor(.orange)
                                .padding(.top, 1)

                            Text(rep.observation)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(UIColor.secondarySystemGroupedBackground).opacity(0.7))
                        .cornerRadius(6)
                    }
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(10)
        .background(Color(UIColor.tertiarySystemGroupedBackground))
        .cornerRadius(10)
    }

    // MARK: - Metric Tile

    private func metricTile(label: String, value: String, valueColor: Color, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .tracking(0.5)

            Text(value)
                .font(.subheadline.bold())
                .foregroundColor(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(subtitle)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(UIColor.tertiarySystemGroupedBackground))
        .cornerRadius(8)
    }

    private func telemetryPill(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(6)
    }

    private func paceDeltaString(_ delta: Int) -> String {
        if delta == 0 {
            return "±0s vs mean"
        } else if delta > 0 {
            return "+\(delta)s vs mean"
        } else {
            return "\(delta)s vs mean"
        }
    }

    // MARK: - Helpers

    private func hrDropSubtitle(avgHRDrop: Int?, isIndoor: Bool) -> String {
        guard let drop = avgHRDrop else { return "Recovery" }
        if isIndoor {
            return drop >= 18 ? "Strong Drop" : (drop >= 12 ? "Solid Drop" : "Heat-blunted")
        } else {
            return drop >= 20 ? "Strong Drop" : (drop >= 10 ? "Moderate Drop" : "Gradual Drop")
        }
    }

    private func gradeColor(for grade: String) -> Color {
        if grade.starts(with: "A") {
            return Color(red: 0.0, green: 0.75, blue: 0.65)
        } else if grade.starts(with: "B") {
            return .orange
        } else {
            return .red
        }
    }

    private func gradeBadgeIcon(for grade: String) -> String {
        if grade.starts(with: "A") {
            return "checkmark.seal.fill"
        } else if grade.starts(with: "B") {
            return "checkmark"
        } else {
            return "info.circle"
        }
    }
}
