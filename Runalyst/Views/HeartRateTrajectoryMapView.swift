import SwiftUI
import Charts
import RunalystCore

/// Renders the Heart Rate Trajectory visualization for Aerobic Workouts
/// (Zone 2, Easy Runs, Long Runs, and Recovery Runs).
/// Highlights Zone 2/3 thresholds, cardiac stability, and aerobic ceiling adherence
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
    var splits: [RunSplit] = []
    var rawAvgHeartRate: Double = 0.0
    var selectedModality: Binding<WorkoutTelemetryModality>?
    var buckets: [BucketData] = []

    @State var selectedMinute: Double?

    static let neonPink = Color(red: 1.0, green: 0.18, blue: 0.55)

    var isRecovery: Bool {
        workoutType == "Recovery Run"
    }

    var aerobicStrain: AerobicStrainEvaluation {
        AerobicStrainEvaluation.evaluate(
            workingAvgHeartRate: workingAvgHeartRate,
            percentZone4: percentZone4,
            zone2Ceiling: isRecovery ? zone1Ceiling : zone2Ceiling,
            isRecoveryPrescription: isRecovery,
            hrCV: hrCV
        )
    }

    var effectiveThreshold: Double {
        aerobicStrain.effectiveCeilingBPM
    }

    var effectiveWorkingHR: Double {
        if workingAvgHeartRate > 0 {
            return workingAvgHeartRate
        }
        if rawAvgHeartRate > 0 {
            return rawAvgHeartRate
        }
        return effectiveThreshold
    }

    var normalizedSegments: [PhaseSegment] {
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

    var maxMinutes: Double {
        let maxSec = workoutDuration ?? (normalizedSegments.map(\.endSeconds).max() ?? 1800.0)
        return max(1.0, ceil(maxSec / 60.0))
    }

    var isZone4Strain: Bool {
        aerobicStrain.isZone4Overreach
    }

    var isElevatedStrain: Bool {
        aerobicStrain.isElevatedStrain
    }

    var cardiacStabilityText: String {
        aerobicStrain.cardiacStabilityText
    }

    var cardiacStabilityColor: Color {
        if aerobicStrain.isSevereStrainColor {
            return Color.red
        } else if aerobicStrain.stabilitySeverity == "optimal" {
            return Color.green
        } else {
            return Color.orange
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(isRecovery ? "Recovery Heart Rate Envelope" : "Heart Rate Trajectory")
                        .font(.headline)
                    Text(
                        isRecovery
                            ? "Gentle active recovery cardiac envelope with minimal strain"
                            : "Zone 2 aerobic threshold adherence & cardiac stability"
                    )
                    .font(.caption)
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
                .padding(.vertical, 4)
                .background(cardiacStabilityColor.opacity(0.12))
                .clipShape(Capsule())
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

            if chartPoints.isEmpty {
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
                        let peakColor: Color = {
                            if peak.heartRate > (zone2Ceiling + 12.0) || isZone4Strain {
                                return Color.red
                            } else if peak.heartRate > effectiveThreshold {
                                return Color.orange
                            }
                            return Self.neonPink
                        }()

                        PointMark(
                            x: .value("Time", peak.minute),
                            y: .value("Heart Rate", peak.heartRate)
                        )
                        .foregroundStyle(peakColor)
                        .symbolSize(40)
                        .annotation(position: .top, alignment: peakAlignment) {
                            Text("\(Int(round(peak.heartRate))) Peak")
                                .font(.system(size: 10, weight: .bold).monospacedDigit())
                                .foregroundColor(peakColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(UIColor.secondarySystemGroupedBackground))
                                .clipShape(Capsule())
                                .shadow(color: Color.black.opacity(0.12), radius: 2)
                        }
                    }

                    // Interactive Touch Scrubber
                    if let minute = selectedMinute {
                        let hr = interpolatedHR(at: minute)
                        let zoneText = zoneLabel(for: hr)
                        let zoneCol = zoneColor(for: hr)
                        let minInt = Int(minute)
                        let secInt = Int((minute - Double(minInt)) * 60)

                        RuleMark(x: .value("Scrubbed Time", minute))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                            .foregroundStyle(Color.secondary.opacity(0.8))
                            .annotation(position: .top, alignment: .center) {
                                VStack(spacing: 3) {
                                    HStack(spacing: 4) {
                                        Text("\(Int(round(hr))) BPM")
                                            .font(.system(size: 11, weight: .bold).monospacedDigit())
                                            .foregroundColor(Self.neonPink)
                                        Text("•")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text(zoneText)
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundColor(zoneCol)
                                    }
                                    Text(String(format: "%d:%02d min", minInt, secInt))
                                        .font(.system(size: 9).monospacedDigit())
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(UIColor.secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .shadow(color: Color.black.opacity(0.18), radius: 4, x: 0, y: 2)
                            }

                        PointMark(
                            x: .value("Time", minute),
                            y: .value("Heart Rate", hr)
                        )
                        .foregroundStyle(Self.neonPink)
                        .symbolSize(48)
                    }

                    // Aerobic Ceiling / Zone Threshold Rule with Apple Health-Style Inline Label
                    RuleMark(y: .value("Aerobic Ceiling", effectiveThreshold))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .foregroundStyle(isRecovery ? Color.secondary.opacity(0.7) : Color.orange.opacity(0.85))
                        .annotation(position: .top, alignment: .leading) {
                            Text(
                                isRecovery
                                    ? "\(Int(effectiveThreshold)) BPM Zone 1 Ceiling"
                                    : "\(Int(effectiveThreshold)) BPM Zone 2 Ceiling"
                            )
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
                .chartXAxis {
                    AxisMarks(values: xAxisTicks) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                            .foregroundStyle(Color.secondary.opacity(0.2))
                        AxisTick()
                        AxisValueLabel {
                            if let minVal = value.as(Double.self) {
                                Text("\(Int(round(minVal)))m")
                                    .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .frame(height: 200)

                // Clean Adaptive Legend (Bottom Edge Clean)
                HStack(alignment: .center, spacing: 12) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Self.neonPink)
                            .frame(width: 8, height: 8)
                        Text("Heart Rate")
                            .font(.caption2.weight(.medium))
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 5) {
                        Rectangle()
                            .fill(isRecovery ? Color.secondary.opacity(0.7) : Color.orange.opacity(0.85))
                            .frame(width: 10, height: 2)
                        Text(isRecovery ? "Zone 1 Ceiling (\(Int(effectiveThreshold)) BPM)" : "Zone 2 Ceiling (\(Int(effectiveThreshold)) BPM)")
                            .font(.caption2.weight(.medium))
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: 16, padding: 16, accentColor: Self.neonPink)
    }
}
