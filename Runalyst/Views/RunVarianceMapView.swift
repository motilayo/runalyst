import SwiftUI
import Charts

/// Renders the Workout Rhythm & Intervals breakdown in the Working Stats view.
/// Shows surges, steady running, and recovery segments alongside the cadence floor.
struct RunVarianceMapView: View {
    let phaseSegments: [PhaseSegment]
    let cadenceFloor: Double
    let averageCadence: Double
    var workoutDuration: Double?
    var isIntervalOrDrill: Bool = true
    var workoutType: String?

    private var isRecovery: Bool {
        workoutType == "Recovery Run"
    }

    private var normalizedSegments: [PhaseSegment] {
        guard let targetDuration = workoutDuration, targetDuration > 0,
              let maxEnd = phaseSegments.map(\.endSeconds).max(), maxEnd > 0 else {
            return phaseSegments
        }
        let scale = targetDuration / maxEnd
        if abs(scale - 1.0) < 0.05 {
            return phaseSegments
        }
        return phaseSegments.map { seg in
            PhaseSegment(
                startSeconds: seg.startSeconds * scale,
                endSeconds: seg.endSeconds * scale,
                kind: seg.kind,
                avgPace: seg.avgPace,
                avgCadence: seg.avgCadence,
                avgHR: seg.avgHR
            )
        }
    }

    private var maxMinutes: Double {
        let maxSec = workoutDuration ?? (normalizedSegments.map(\.endSeconds).max() ?? 1800.0)
        return max(1.0, ceil(maxSec / 60.0))
    }

    private var yMin: Double {
        let validCadences = normalizedSegments.map(\.avgCadence).filter { $0 > 60 }
        let lowestCad = validCadences.min() ?? cadenceFloor
        let lowest = min(lowestCad, cadenceFloor)
        return max(60, floor((lowest - 6) / 5) * 5)
    }

    private var yMax: Double {
        let validCadences = normalizedSegments.map(\.avgCadence).filter { $0 > 60 }
        let highestCad = validCadences.max() ?? (averageCadence + 15)
        return min(220, ceil((highestCad + 8) / 5) * 5)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(isIntervalOrDrill ? "Workout Rhythm & Intervals" : "Cadence Rhythm")
                    .font(.headline)
                Text(isIntervalOrDrill ? "Cadence surges, steady running, and recoveries across your run" : (isRecovery ? "Gentle active recovery cadence trajectory with low mechanical strain" : "Continuous cadence trajectory across your session"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if normalizedSegments.isEmpty {
                Text("Interval breakdown will appear once run data is processed.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .frame(height: 120)
            } else {
                Chart {
                    // Background phase blocks (only for intervals/drills)
                    if isIntervalOrDrill {
                        ForEach(normalizedSegments) { seg in
                            RectangleMark(
                                xStart: .value("Start", seg.startSeconds / 60.0),
                                xEnd: .value("End", seg.endSeconds / 60.0),
                                yStart: .value("Min Y", yMin),
                                yEnd: .value("Max Y", yMax)
                            )
                            .foregroundStyle(phaseColor(seg.kind).opacity(seg.kind == "work" ? 0.22 : 0.12))
                        }
                    }

                    // Soft gradient under the cadence line
                    ForEach(normalizedSegments) { seg in
                        AreaMark(
                            x: .value("Time", (seg.startSeconds + seg.endSeconds) / 120.0),
                            yStart: .value("Floor", yMin),
                            yEnd: .value("Cadence", seg.avgCadence > 0 ? seg.avgCadence : averageCadence)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.purple.opacity(0.30), Color.purple.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }

                    // Prominent Cadence trajectory connecting line
                    ForEach(normalizedSegments) { seg in
                        LineMark(
                            x: .value("Time", (seg.startSeconds + seg.endSeconds) / 120.0),
                            y: .value("Cadence", seg.avgCadence > 0 ? seg.avgCadence : averageCadence)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color.purple)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    }

                    // Prominent Peak and Trough Point Marks
                    ForEach(normalizedSegments) { seg in
                        let midTime = (seg.startSeconds + seg.endSeconds) / 120.0
                        let cad = seg.avgCadence > 0 ? seg.avgCadence : averageCadence
                        let isNearRightEdge = midTime >= (maxMinutes - 1.2)
                        let isNearLeftEdge = midTime <= 0.8
                        let annotationAlignment: Alignment = isNearRightEdge ? .trailing : (isNearLeftEdge ? .leading : .center)

                        PointMark(
                            x: .value("Time", midTime),
                            y: .value("Cadence", cad)
                        )
                        .foregroundStyle(isIntervalOrDrill ? phaseColor(seg.kind) : Color.purple)
                        .symbolSize(isIntervalOrDrill ? (seg.kind == "work" ? 76 : (seg.kind == "recovery" ? 60 : 44)) : 36)
                        .annotation(position: .top, alignment: annotationAlignment) {
                            if isIntervalOrDrill {
                                if seg.kind == "work" {
                                    Text("\(Int(cad))")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.purple)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color(UIColor.secondarySystemGroupedBackground))
                                        .clipShape(Capsule())
                                        .shadow(color: Color.black.opacity(0.12), radius: 2)
                                } else if seg.kind == "recovery" {
                                    Text("\(Int(cad))")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.teal)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color(UIColor.secondarySystemGroupedBackground))
                                        .clipShape(Capsule())
                                        .shadow(color: Color.black.opacity(0.12), radius: 2)
                                }
                            }
                        }
                    }

                    // Cadence Floor Rule (context-aware: muted for recovery runs, alert for intervals)
                    RuleMark(y: .value("Cadence Floor", cadenceFloor))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .foregroundStyle(isRecovery ? Color.secondary.opacity(0.6) : Color.red.opacity(0.80))
                }
                .chartScrollableAxes(.horizontal)
                .chartXVisibleDomain(length: min(maxMinutes + 1.0, 13.5))
                .chartXScale(domain: 0...(maxMinutes + 1.0))
                .chartYScale(domain: yMin...yMax)
                .frame(height: 220)

                // Legend
                if isIntervalOrDrill {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            legendItem(color: .purple, label: "Fast / Surge")
                            legendItem(color: .teal, label: "Recovery")
                            legendItem(color: .blue, label: "Steady")
                            legendItem(color: .gray, label: "Walking")
                            HStack(spacing: 4) {
                                HStack(spacing: 2) {
                                    Rectangle()
                                        .fill(Color.red.opacity(0.85))
                                        .frame(width: 4, height: 1.5)
                                    Rectangle()
                                        .fill(Color.red.opacity(0.85))
                                        .frame(width: 4, height: 1.5)
                                }
                                Text("Floor: \(Int(cadenceFloor))")
                                    .font(.caption2.weight(.medium))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, 1)
                    }
                    .padding(.top, 4)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            legendItem(color: .purple, label: "Cadence")
                            HStack(spacing: 4) {
                                HStack(spacing: 2) {
                                    Rectangle()
                                        .fill(isRecovery ? Color.secondary.opacity(0.7) : Color.red.opacity(0.85))
                                        .frame(width: 4, height: 1.5)
                                    Rectangle()
                                        .fill(isRecovery ? Color.secondary.opacity(0.7) : Color.red.opacity(0.85))
                                        .frame(width: 4, height: 1.5)
                                }
                                Text(isRecovery ? "Recovery Baseline (\(Int(cadenceFloor)))" : "Floor: \(Int(cadenceFloor)) SPM")
                                    .font(.caption2.weight(.medium))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, 1)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(UIColor.separator).opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
    }

    private func phaseColor(_ kind: String) -> Color {
        switch kind {
        case "work": return .purple
        case "recovery": return .teal
        case "steady": return .blue
        case "walking": return .gray
        default: return .secondary
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundColor(.secondary)
        }
    }
}
