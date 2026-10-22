import SwiftUI

/// A minimalist, horizontally scrolling timeline UI representing the structured phases of a pre-run workout.
/// Translates complex WorkoutKit phase data into plain English and visual geometry using native SwiftUI shapes.
struct WorkoutPhaseTimelineView: View {
    let phases: [WorkoutPhase]
    var showHeader: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showHeader {
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.caption2.bold())
                            .foregroundColor(.secondary)
                        Text("Breakdown")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(totalDurationString)
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary.opacity(0.85))
                }
            } else {
                HStack(spacing: 8) {
                    if phases.contains(where: { $0.kind == .warmup }) {
                        HStack(spacing: 3) {
                            Circle().fill(WorkoutPhase.Kind.warmup.color).frame(width: 6, height: 6)
                            Text("Warm-up").font(.system(size: 9)).foregroundColor(.secondary)
                        }
                    }
                    if phases.contains(where: { $0.kind == .work }) {
                        HStack(spacing: 3) {
                            Circle().fill(WorkoutPhase.Kind.work.color).frame(width: 6, height: 6)
                            Text("Work").font(.system(size: 9)).foregroundColor(.secondary)
                        }
                    }
                    if phases.contains(where: { $0.kind == .steady }) {
                        HStack(spacing: 3) {
                            Circle().fill(WorkoutPhase.Kind.steady.color).frame(width: 6, height: 6)
                            Text("Steady").font(.system(size: 9)).foregroundColor(.secondary)
                        }
                    }
                    if phases.contains(where: { if case .recovery = $0.kind { return true } else { return false } }) {
                        HStack(spacing: 3) {
                            Circle().fill(WorkoutPhase.Kind.recovery(isWalk: false).color).frame(width: 6, height: 6)
                            Text(recoveryLegendTitle).font(.system(size: 9)).foregroundColor(.secondary)
                        }
                    }
                    if phases.contains(where: { $0.kind == .cooldown }) {
                        HStack(spacing: 3) {
                            Circle().fill(WorkoutPhase.Kind.cooldown.color).frame(width: 6, height: 6)
                            Text("Cool-down").font(.system(size: 9)).foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Text(totalDurationString)
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary.opacity(0.85))
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(phases) { phase in
                        VStack(spacing: 4) {
                            // Visual phase block / spike
                            RoundedRectangle(cornerRadius: 4)
                                .fill(blockColor(for: phase.kind))
                                .frame(width: blockWidth(for: phase), height: blockHeight(for: phase.kind))

                            // Plain English phase title
                            Text(phase.name)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.primary.opacity(0.85))
                                .lineLimit(1)

                            // Duration badge
                            Text(phase.formattedDuration)
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
            }
        }
        .padding(10)
        .background(Color(UIColor.tertiarySystemFill).opacity(0.6))
        .cornerRadius(12)
    }

    private var totalDurationString: String {
        let totalSec = phases.reduce(0) { $0 + $1.durationSeconds }
        let mins = totalSec / 60
        let secs = totalSec % 60
        if secs == 0 {
            return "\(mins) min total"
        } else {
            return "\(mins)m \(secs)s total"
        }
    }

    private var recoveryLegendTitle: String {
        let hasJog = phases.contains(where: {
            if case .recovery(let isWalk) = $0.kind { return !isWalk }
            return false
        })
        let hasWalk = phases.contains(where: {
            if case .recovery(let isWalk) = $0.kind { return isWalk }
            return false
        })
        if hasJog && !hasWalk {
            return "Jog / Rest"
        } else if hasWalk && !hasJog {
            return "Walk / Rest"
        } else {
            return "Recovery"
        }
    }

    private func blockColor(for kind: WorkoutPhase.Kind) -> Color {
        kind.color
    }

    private func blockHeight(for kind: WorkoutPhase.Kind) -> CGFloat {
        switch kind {
        case .work:
            return 38 // Tall spike
        case .warmup, .cooldown:
            return 22 // Mid-height block
        case .recovery:
            return 14 // Flat block
        case .steady:
            return 26
        }
    }

    private func blockWidth(for phase: WorkoutPhase) -> CGFloat {
        let sec = CGFloat(phase.durationSeconds)
        switch phase.kind {
        case .warmup:
            // Long block scaling with warm-up length (e.g. 1m -> 54pt, 5m -> 88pt)
            return min(95, max(54, 45 + sec * 0.15))
        case .cooldown:
            return min(80, max(46, 40 + sec * 0.15))
        case .steady:
            return 110
        case .work:
            // Narrow spikes (height = effort, width = duration): 15s -> 25pt, 20s -> 27pt, 30s -> 31pt
            return min(55, max(24, 20 + sec * 0.35))
        case .recovery:
            // Flat recovery blocks: 30s -> 37pt, 60s (1 min walk) -> 52pt
            return min(75, max(32, 22 + sec * 0.50))
        }
    }
}
