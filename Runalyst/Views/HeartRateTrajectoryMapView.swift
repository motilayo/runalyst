import SwiftUI
import Charts

/// Renders the Heart Rate Trajectory visualization for Aerobic Workouts
/// (Zone 2, Easy Runs, Long Runs, and Recovery Runs).
/// Highlighting Zone 2/3 thresholds, cardiac stability, and aerobic ceiling adherence.
struct HeartRateTrajectoryMapView: View {
    let phaseSegments: [PhaseSegment]
    let workingAvgHeartRate: Double
    var workoutDuration: Double?
    var workoutType: String?
    var zone1Ceiling: Double = 135.0
    var zone2Ceiling: Double = 144.0
    var percentZone4: Double = 0.0
    var hrCV: Double?
    var selectedModality: Binding<WorkoutTelemetryModality>?

    private static let neonPink = Color(red: 1.0, green: 0.18, blue: 0.55)

    private var isRecovery: Bool {
        workoutType == "Recovery Run"
    }

    private var effectiveThreshold: Double {
        isRecovery ? zone1Ceiling : zone2Ceiling
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
        let validHRs = normalizedSegments.map(\.avgHR).filter { $0 > 40 }
        let lowestHR = validHRs.min() ?? (workingAvgHeartRate > 0 ? workingAvgHeartRate - 15 : 100.0)
        let lowest = min(lowestHR, effectiveThreshold - 20)
        return max(60, floor((lowest - 10) / 5) * 5)
    }

    private var yMax: Double {
        let validHRs = normalizedSegments.map(\.avgHR).filter { $0 > 40 }
        let highestHR = validHRs.max() ?? (workingAvgHeartRate > 0 ? workingAvgHeartRate + 15 : 160.0)
        let highest = max(highestHR, effectiveThreshold + 10)
        return min(210, ceil((highest + 10) / 5) * 5)
    }

    struct HRPlotPoint: Identifiable {
        let id: String
        let minute: Double
        let heartRate: Double
        let kind: String
        let isAnchor: Bool
    }

    private var chartPoints: [HRPlotPoint] {
        var points: [HRPlotPoint] = []
        let fallbackHR = workingAvgHeartRate > 0 ? workingAvgHeartRate : effectiveThreshold

        for (idx, seg) in normalizedSegments.enumerated() {
            let hr = seg.avgHR > 0 ? seg.avgHR : fallbackHR
            let startMin = seg.startSeconds / 60.0
            let endMin = seg.endSeconds / 60.0
            let midMin = (seg.startSeconds + seg.endSeconds) / 120.0

            if normalizedSegments.count == 1 || (endMin - startMin) > 2.0 {
                // Continuous run or extended phase: render start, mid, and end anchors
                points.append(HRPlotPoint(id: "\(idx)-start", minute: startMin, heartRate: hr, kind: seg.kind, isAnchor: false))
                points.append(HRPlotPoint(id: "\(idx)-mid", minute: midMin, heartRate: hr, kind: seg.kind, isAnchor: true))
                points.append(HRPlotPoint(id: "\(idx)-end", minute: endMin, heartRate: hr, kind: seg.kind, isAnchor: false))
            } else {
                points.append(HRPlotPoint(id: "\(idx)-mid", minute: midMin, heartRate: hr, kind: seg.kind, isAnchor: true))
            }
        }

        // Defensive guarantee: Swift Charts requires at least 2 points to render AreaMark and LineMark
        if points.count == 1, let first = points.first {
            let endMin = max(maxMinutes, first.minute + 1.0)
            points = [
                HRPlotPoint(id: "start", minute: 0, heartRate: first.heartRate, kind: first.kind, isAnchor: false),
                HRPlotPoint(id: "mid", minute: first.minute, heartRate: first.heartRate, kind: first.kind, isAnchor: true),
                HRPlotPoint(id: "end", minute: endMin, heartRate: first.heartRate, kind: first.kind, isAnchor: false)
            ]
        }

        return points.sorted(by: { $0.minute < $1.minute })
    }

    private var cardiacStabilityText: String {
        if percentZone4 <= 0.04 && (hrCV ?? 0.05) <= 0.08 {
            return "Cardiac Stability: High"
        } else if percentZone4 <= 0.12 {
            return "Cardiac Stability: Moderate"
        } else {
            return "Cardiac Drift Detected"
        }
    }

    private var cardiacStabilityColor: Color {
        if percentZone4 <= 0.04 && (hrCV ?? 0.05) <= 0.08 {
            return Color.green
        } else if percentZone4 <= 0.12 {
            return Color.orange
        } else {
            return Color.red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(isRecovery ? "Recovery Heart Rate Envelope" : "Heart Rate Trajectory")
                    .font(.headline)
                Text(isRecovery ? "Gentle active recovery cardiac envelope with minimal strain" : "Zone 2 aerobic threshold adherence & cardiac stability")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let selectedModality = selectedModality {
                Picker("Telemetry Mode", selection: selectedModality) {
                    Text("Heart Rate").tag(WorkoutTelemetryModality.heartRate)
                    Text("Cadence").tag(WorkoutTelemetryModality.cadence)
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedModality.wrappedValue) { _, _ in
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }

            if normalizedSegments.isEmpty {
                Text("Heart rate data will appear once workout telemetry is processed.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .frame(height: 120)
            } else {
                Chart {
                    // Shaded Aerobic Target Envelope
                    RectangleMark(
                        xStart: .value("Start", 0.0),
                        xEnd: .value("End", maxMinutes + 1.0),
                        yStart: .value("Min Y", yMin),
                        yEnd: .value("Threshold", effectiveThreshold)
                    )
                    .foregroundStyle(Self.neonPink.opacity(0.06))

                    // Soft gradient under the Heart Rate curve
                    ForEach(chartPoints) { pt in
                        AreaMark(
                            x: .value("Time", pt.minute),
                            yStart: .value("Floor", yMin),
                            yEnd: .value("Heart Rate", pt.heartRate)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Self.neonPink.opacity(0.32), Self.neonPink.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }

                    // Prominent Heart Rate trajectory line
                    ForEach(chartPoints) { pt in
                        LineMark(
                            x: .value("Time", pt.minute),
                            y: .value("Heart Rate", pt.heartRate)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Self.neonPink)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    }

                    // Midpoint & Peak BPM Point Marks
                    ForEach(chartPoints.filter(\.isAnchor)) { pt in
                        let midTime = pt.minute
                        let hr = pt.heartRate
                        let isAboveThreshold = hr > effectiveThreshold
                        let isNearRightEdge = midTime >= (maxMinutes - 1.2)
                        let isNearLeftEdge = midTime <= 0.8
                        let annotationAlignment: Alignment = isNearRightEdge ? .trailing : (isNearLeftEdge ? .leading : .center)

                        PointMark(
                            x: .value("Time", midTime),
                            y: .value("Heart Rate", hr)
                        )
                        .foregroundStyle(isAboveThreshold ? Color.orange : Self.neonPink)
                        .symbolSize(36)
                        .annotation(position: .top, alignment: annotationAlignment) {
                            Text("\(Int(round(hr)))")
                                .font(.system(size: 10, weight: .bold).monospacedDigit())
                                .foregroundColor(isAboveThreshold ? .orange : Self.neonPink)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color(UIColor.secondarySystemGroupedBackground))
                                .clipShape(Capsule())
                                .shadow(color: Color.black.opacity(0.12), radius: 2)
                        }
                    }

                    // Aerobic Ceiling / Zone Threshold Rule
                    RuleMark(y: .value("Aerobic Ceiling", effectiveThreshold))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .foregroundStyle(isRecovery ? Color.secondary.opacity(0.7) : Color.orange.opacity(0.85))
                }
                .chartScrollableAxes(.horizontal)
                .chartXVisibleDomain(length: min(maxMinutes + 1.0, 13.5))
                .chartXScale(domain: 0...(maxMinutes + 1.0))
                .chartYScale(domain: yMin...yMax)
                .frame(height: 220)

                // Contextual Legend & Stability Badge
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        legendItem(color: Self.neonPink, label: "Heart Rate")

                        HStack(spacing: 4) {
                            HStack(spacing: 2) {
                                Rectangle()
                                    .fill(isRecovery ? Color.secondary.opacity(0.7) : Color.orange.opacity(0.85))
                                    .frame(width: 4, height: 1.5)
                                Rectangle()
                                    .fill(isRecovery ? Color.secondary.opacity(0.7) : Color.orange.opacity(0.85))
                                    .frame(width: 4, height: 1.5)
                            }
                            Text(isRecovery ? "Zone 1 Ceiling (\(Int(effectiveThreshold)))" : "Zone 2 Ceiling (\(Int(effectiveThreshold)) BPM)")
                                .font(.caption2.weight(.medium))
                                .foregroundColor(.secondary)
                        }

                        // Cardiac Stability Pill
                        HStack(spacing: 4) {
                            Circle()
                                .fill(cardiacStabilityColor)
                                .frame(width: 6, height: 6)
                            Text(cardiacStabilityText)
                                .font(.caption2.weight(.medium))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 1)
                }
                .padding(.top, 4)
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
