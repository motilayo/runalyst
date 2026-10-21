import SwiftUI
import Charts

/// Renders the Heart Rate Trajectory visualization for Aerobic Workouts
/// (Zone 2, Easy Runs, Long Runs, and Recovery Runs).
/// Highlighting Zone 2/3 thresholds, cardiac stability, and aerobic ceiling adherence
/// following Apple Health's clean visual language.
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

    @State private var selectedMinute: Double?

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

    private var peakPoint: HRPlotPoint? {
        chartPoints.max(by: { $0.heartRate < $1.heartRate })
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

    private var scrubbedPoint: HRPlotPoint? {
        guard let minute = selectedMinute else { return nil }
        return chartPoints.min(by: { abs($0.minute - minute) < abs($1.minute - minute) })
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
                        xEnd: .value("End", maxMinutes),
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
                                colors: [Self.neonPink.opacity(0.28), Self.neonPink.opacity(0.02)],
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

                    // De-cluttered subtle dots along the curve (Apple Health Style)
                    ForEach(chartPoints.filter(\.isAnchor)) { pt in
                        PointMark(
                            x: .value("Time", pt.minute),
                            y: .value("Heart Rate", pt.heartRate)
                        )
                        .foregroundStyle(Self.neonPink)
                        .symbolSize(18)
                    }

                    // Single clean Peak Heart Rate callout (prevents overlapping badge noise)
                    if let peak = peakPoint, selectedMinute == nil {
                        let isNearRight = peak.minute >= (maxMinutes - 4.0)
                        let isNearLeft = peak.minute <= 4.0
                        let peakAlignment: Alignment = isNearRight ? .trailing : (isNearLeft ? .leading : .center)

                        PointMark(
                            x: .value("Time", peak.minute),
                            y: .value("Heart Rate", peak.heartRate)
                        )
                        .foregroundStyle(peak.heartRate > effectiveThreshold ? Color.orange : Self.neonPink)
                        .symbolSize(40)
                        .annotation(position: .top, alignment: peakAlignment) {
                            Text("\(Int(round(peak.heartRate))) Peak")
                                .font(.system(size: 10, weight: .bold).monospacedDigit())
                                .foregroundColor(peak.heartRate > effectiveThreshold ? .orange : Self.neonPink)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(UIColor.secondarySystemGroupedBackground))
                                .clipShape(Capsule())
                                .shadow(color: Color.black.opacity(0.12), radius: 2)
                        }
                    }

                    // Interactive Scrub Indicator
                    if let scrub = scrubbedPoint {
                        RuleMark(x: .value("Scrubbed Time", scrub.minute))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                            .foregroundStyle(Color.secondary.opacity(0.8))
                            .annotation(position: .top, alignment: .center) {
                                VStack(spacing: 2) {
                                    Text("\(Int(round(scrub.heartRate))) BPM")
                                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                                        .foregroundColor(Self.neonPink)
                                    Text("\(Int(scrub.minute))m")
                                        .font(.system(size: 9).monospacedDigit())
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color(UIColor.secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .shadow(color: Color.black.opacity(0.15), radius: 3)
                            }
                    }

                    // Aerobic Ceiling / Zone Threshold Rule with Apple Health-Style Inline Label
                    RuleMark(y: .value("Aerobic Ceiling", effectiveThreshold))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .foregroundStyle(isRecovery ? Color.secondary.opacity(0.7) : Color.orange.opacity(0.85))
                        .annotation(position: .top, alignment: .leading) {
                            Text(isRecovery ? "\(Int(effectiveThreshold)) BPM Zone 1 Ceiling" : "\(Int(effectiveThreshold)) BPM Zone 2 Ceiling")
                                .font(.system(size: 9.5, weight: .bold).monospacedDigit())
                                .foregroundColor(isRecovery ? Color.secondary : Color.orange)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1.5)
                                .background(Color(UIColor.secondarySystemGroupedBackground).opacity(0.92))
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }
                }
                .chartXSelection(value: $selectedMinute)
                .chartXScale(domain: 0...maxMinutes)
                .chartYScale(domain: yMin...yMax)
                .frame(height: 200)

                // Clean Adaptive Legend & Cardiac Stability Row (Zero Truncation)
                HStack(alignment: .center, spacing: 8) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Self.neonPink)
                            .frame(width: 8, height: 8)
                        Text("Heart Rate")
                            .font(.caption2.weight(.medium))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 5) {
                        Circle()
                            .fill(cardiacStabilityColor)
                            .frame(width: 6, height: 6)
                        Text(cardiacStabilityText)
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(cardiacStabilityColor)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(cardiacStabilityColor.opacity(0.12))
                    .clipShape(Capsule())
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
}
