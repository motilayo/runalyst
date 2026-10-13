import SwiftUI

/// Dedicated execution scorecard for unprescribed interval workouts.
/// Evaluates pacing repeatability across reps, cadence floor retention under fatigue,
/// and heart rate recovery drops between sets.
struct IntervalPerformanceCard: View {
    let runRecord: RunRecord
    var baselineCadence: Double?

    @State private var isExpanded: Bool = false

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

                VStack(alignment: .leading, spacing: 3) {
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

                    Text("\(evaluations.count) Work Reps • \(isIndoor ? "Treadmill Pacing" : "Road / Track")")
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
                    subtitle: isIndoor ? "±\(Int(Double(paceSpread) / 2.0))s spread • Belt" : "±\(Int(Double(paceSpread) / 2.0))s spread • Road"
                )

                metricTile(
                    label: "TURNOVER",
                    value: "\(avgCadence) SPM",
                    valueColor: avgCadence >= cadenceFloor ? Color(red: 0.0, green: 0.75, blue: 0.65) : .orange,
                    subtitle: isIndoor ? "Floor: \(cadenceFloor) SPM (Belt)" : "Floor: \(cadenceFloor) SPM"
                )

                metricTile(
                    label: "AVG HR DROP",
                    value: avgHRDrop.map { "-\($0) BPM" } ?? "--",
                    valueColor: (avgHRDrop ?? 0) >= (isIndoor ? 12 : 15) ? Color(red: 0.0, green: 0.75, blue: 0.65) : .secondary,
                    subtitle: hrDropSubtitle(avgHRDrop: avgHRDrop, isIndoor: isIndoor)
                )
            }

            // MARK: - Graded Reps Section
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
                        repRow(rep)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }

    // MARK: - Subviews

    @ViewBuilder
    private func repRow(_ rep: IntervalRepEvaluation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: Rep Number + Duration + Grade
            HStack {
                Text("Rep \(rep.repIndex)")
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)

                let durMin = Int(rep.durationSeconds) / 60
                let durSec = Int(rep.durationSeconds) % 60
                Text(durMin > 0 ? "\(durMin)m \(durSec)s" : "\(durSec)s")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(UIColor.tertiarySystemFill))
                    .clipShape(Capsule())

                Spacer()

                Text("Grade \(rep.letterGrade)")
                    .font(.caption2.bold())
                    .foregroundColor(gradeColor(for: rep.letterGrade))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(gradeColor(for: rep.letterGrade).opacity(0.12))
                    .clipShape(Capsule())
            }

            // Work Metrics Row
            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    Image(systemName: "bolt.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Text(rep.workPaceFormatted)
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                }

                Text("•")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.5))

                HStack(spacing: 3) {
                    Image(systemName: "shoeprints.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(rep.workCadence) SPM")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text("•")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.5))

                HStack(spacing: 3) {
                    Image(systemName: "heart.fill")
                        .font(.caption2)
                        .foregroundColor(.red.opacity(0.8))
                    Text("\(rep.workHeartRate) BPM")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Recovery Row (if present)
            if let recPace = rep.recoveryPaceFormatted {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text("Recovery: \(recPace)")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if let drop = rep.recoveryHeartRateDrop, drop > 0 {
                        Spacer()
                        HStack(spacing: 3) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 8))
                            Text("-\(drop) BPM drop")
                                .font(.caption2.bold())
                        }
                        .foregroundColor(Color(red: 0.0, green: 0.75, blue: 0.65))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(red: 0.0, green: 0.75, blue: 0.65).opacity(0.12))
                        .clipShape(Capsule())
                    }
                }
            }

            // Observation
            Text(rep.observation)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding(10)
        .background(Color(UIColor.tertiarySystemGroupedBackground))
        .cornerRadius(10)
    }

    private func metricTile(label: String, value: String, valueColor: Color, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .tracking(0.5)

            Text(value)
                .font(.subheadline.bold())
                .foregroundColor(valueColor)

            Text(subtitle)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(UIColor.tertiarySystemGroupedBackground))
        .cornerRadius(8)
    }

    // MARK: - Helpers

    private func hrDropSubtitle(avgHRDrop: Int?, isIndoor: Bool) -> String {
        guard let drop = avgHRDrop else { return isIndoor ? "Indoor Recovery" : "Recovery" }
        if isIndoor {
            return drop >= 18 ? "Strong (Static Air)" : (drop >= 12 ? "Solid (Heat Build)" : "Blunted by Heat")
        } else {
            return drop >= 20 ? "Strong Drop" : (drop >= 10 ? "Moderate" : "Recovery")
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
