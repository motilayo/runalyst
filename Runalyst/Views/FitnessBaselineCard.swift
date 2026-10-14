import SwiftUI

struct FitnessBaselineCard: View {
    var globalVO2Max: Double?
    var baselineVO2Max: Double?
    var baselineCadence: Int?
    var previousBaselineCadence: Int?
    var baselinePace: Double?
    var previousBaselinePace: Double?
    var workoutDensityTier: String
    var timeRangeRunsCount: Int
    var timeRangeName: String

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var activeExplainer: MetricExplainerInfo?

    @ViewBuilder
    private var quadrantVO2Max: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .foregroundColor(.red)
                    .font(.caption)
                Text("VO2 MAX")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                Image(systemName: "info.circle")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
            }

            if let vo2Val = globalVO2Max {
                Text(String(format: "%.1f", vo2Val))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.primary)

                if let base = baselineVO2Max {
                    let diff = vo2Val - base
                    if abs(diff) > 0.05 {
                        let isPositive = diff >= 0
                        HStack(spacing: 3) {
                            Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 10, weight: .bold))
                            Text(String(format: "%@%.1f", isPositive ? "+" : "", diff))
                                .font(.caption2.bold())
                        }
                        .foregroundColor(isPositive ? .green : .red)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background((isPositive ? Color.green : Color.red).opacity(0.12))
                        .clipShape(Capsule())
                    }
                }
            } else {
                Text("—")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            activeExplainer = MetricExplainerInfo(
                explainer: MetricDetailExplainer.explainer(for: "VO2 Max", isWorkoutStats: false),
                mode: "Working Stats"
            )
        }
    }

    @ViewBuilder
    private var quadrantCadence: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "figure.run")
                    .foregroundColor(.blue)
                    .font(.caption)
                Text("AVG CADENCE")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                Image(systemName: "info.circle")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
            }

            if let cadenceVal = baselineCadence, cadenceVal > 0 {
                Text("\(cadenceVal) SPM")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.primary)

                if let prevCadence = previousBaselineCadence {
                    let diff = cadenceVal - prevCadence
                    if diff != 0 {
                        let isPositive = diff > 0
                        HStack(spacing: 3) {
                            Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 10, weight: .bold))
                            Text(String(format: "%@%d SPM", isPositive ? "+" : "", diff))
                                .font(.caption2.bold())
                        }
                        .foregroundColor(isPositive ? .green : .orange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background((isPositive ? Color.green : Color.orange).opacity(0.12))
                        .clipShape(Capsule())
                    }
                }
            } else {
                Text("—")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            activeExplainer = MetricExplainerInfo(
                explainer: MetricDetailExplainer.explainer(for: "Average Cadence", isWorkoutStats: false),
                mode: "Working Stats"
            )
        }
    }

    @ViewBuilder
    private var quadrantPace: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "speedometer")
                    .foregroundColor(.teal)
                    .font(.caption)
                Text("AVG PACE")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                Image(systemName: "info.circle")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
            }

            if let paceVal = baselinePace, paceVal > 0 {
                let displayPace = PaceFormatter.formatPace(secondsPerKilometer: paceVal)
                Text(displayPace)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.primary)

                if let prevPace = previousBaselinePace {
                    let diffSecs = Int(round(paceVal - prevPace))
                    if diffSecs != 0 {
                        let isFaster = diffSecs < 0
                        HStack(spacing: 3) {
                            Image(systemName: isFaster ? "arrow.down.right" : "arrow.up.right")
                                .font(.system(size: 10, weight: .bold))
                            Text(String(format: "%@%ds", diffSecs > 0 ? "+" : "", diffSecs))
                                .font(.caption2.bold())
                        }
                        .foregroundColor(isFaster ? .green : .orange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background((isFaster ? Color.green : Color.orange).opacity(0.12))
                        .clipShape(Capsule())
                    }
                }
            } else {
                Text("—")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            activeExplainer = MetricExplainerInfo(
                explainer: MetricDetailExplainer.explainer(for: "Average Pace", isWorkoutStats: false),
                mode: "Working Stats"
            )
        }
    }

    @ViewBuilder
    private var quadrantDensity: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .foregroundColor(.yellow)
                    .font(.caption)
                Text("WORKOUT DENSITY")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                Image(systemName: "info.circle")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
            }

            let density = workoutDensityTier
            Text(density)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(density == "Optimal" ? .green : (density == "Moderate" ? .yellow : (density == "High" ? .orange : (density == "Low" ? .orange : .secondary))))

            Text(timeRangeRunsCount == 0 ? "No runs in \(timeRangeName.lowercased())" : "\(timeRangeRunsCount) runs in \(timeRangeName.lowercased())")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            activeExplainer = MetricExplainerInfo(
                explainer: MetricDetailExplainer.explainer(for: "Workout Density", isWorkoutStats: false),
                mode: "Working Stats"
            )
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            if horizontalSizeClass == .regular {
                HStack(alignment: .top, spacing: 20) {
                    quadrantVO2Max
                    Divider()
                        .background(Color(UIColor.separator).opacity(0.3))
                        .frame(height: 70)
                    quadrantCadence
                    Divider()
                        .background(Color(UIColor.separator).opacity(0.3))
                        .frame(height: 70)
                    quadrantPace
                    Divider()
                        .background(Color(UIColor.separator).opacity(0.3))
                        .frame(height: 70)
                    quadrantDensity
                }
            } else {
                HStack(alignment: .top) {
                    quadrantVO2Max
                    quadrantCadence
                }

                Divider()
                    .background(Color(UIColor.separator).opacity(0.3))

                HStack(alignment: .top) {
                    quadrantPace
                    quadrantDensity
                }
            }
        }
        .padding(18)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(UIColor.separator).opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        .padding(.horizontal)
        .sheet(item: $activeExplainer) { info in
            MetricExplainerSheet(info: info)
        }
    }
}
