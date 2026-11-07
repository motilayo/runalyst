import SwiftUI
import UIKit
import SwiftData
import WorkoutKit
import RunalystCore

extension RunDetailView {
    @ViewBuilder
    var aiRunAnalysisCard: some View {
        let hasBiometrics = runRecord.workingAvgCadence > 0 || runRecord.workingAvgHeartRate > 0

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(hasBiometrics ? .purple : .secondary)
                Text(hasBiometrics ? "What the Numbers Mean" : "Sensor Data Limited")
                    .font(.subheadline.bold())
                    .foregroundColor(hasBiometrics ? .purple : .secondary)
            }

            if !hasBiometrics {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Biometric Analysis Unavailable")
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                    Text("This workout was recorded without an Apple Watch and has no cadence or heart rate sensor data. Runalyst requires continuous biometric telemetry to analyze form, cadence rhythm, and cardiac strain without hallucinating.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineSpacing(2)
                }
                .padding(.vertical, 2)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    let analysisHeadline = takeawaySummary.headline

                    Text(analysisHeadline)
                        .font(.headline)
                        .foregroundColor(.primary)

                    if !deterministicRunAnalysisTakeaways.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(deterministicRunAnalysisTakeaways) { item in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: item.icon)
                                        .font(.subheadline.bold())
                                        .foregroundColor(item.iconColor)
                                        .frame(width: 20, height: 20)
                                        .padding(.top, 2)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .font(.caption.bold())
                                            .foregroundColor(.primary)
                                        Text(item.detail)
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                            .lineSpacing(2)
                                    }
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(UIColor.tertiarySystemGroupedBackground).opacity(0.7))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                    } else if let insight = runRecord.insight, !insight.longitudinalObservation.isEmpty {
                        Text(insight.longitudinalObservation)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                    } else if isGeneratingInsight {
                        AnimatedLoadingView(
                            text: "Generating AI insight...",
                            isHorizontal: true,
                            imageSize: 14,
                            textFont: .body,
                            spacing: 8
                        )
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                    }
                }
            }

            if hasBiometrics {
                AIDisclaimerFooter()
            }
        }
        .frame(minHeight: 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: 16, padding: 16, accentColor: .purple)
        .id("aiAnalysisCard")
        .task {
            if !hasBiometrics, let oldInsight = runRecord.insight {
                modelContext.delete(oldInsight)
                runRecord.insight = nil
                try? modelContext.save()
            } else if hasBiometrics && runRecord.insight == nil {
                isGeneratingInsight = true
                if #available(iOS 26.0, *) {
                    await CoachingEngine.shared.requestAnalysis(for: runRecord)
                    isGeneratingInsight = false
                } else {
                    isGeneratingInsight = false
                }
            }
        }
    }

    @ViewBuilder
    var heroMetricsCard: some View {
        let activeDistanceMeters = runRecord.effectiveWorkingDistanceMeters > 0 ? runRecord.effectiveWorkingDistanceMeters : runRecord.totalDistanceMeters
        let distanceConverted = useMetricSystem ? (activeDistanceMeters / 1000.0) : (activeDistanceMeters / 1609.344)
        let distanceUnit = useMetricSystem ? "km" : "mi"

        let activeDuration = runRecord.effectiveWorkingDurationSeconds > 0 ? runRecord.effectiveWorkingDurationSeconds : runRecord.duration
        let hours = Int(activeDuration) / 3600
        let minutes = (Int(activeDuration) % 3600) / 60
        let seconds = Int(activeDuration) % 60
        let timeString = hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds) : String(format: "%d:%02d", minutes, seconds)

        let currentPace = runRecord.effectiveWorkingAvgPace
        let paceValue = PaceFormatter.formatPaceValue(secondsPerKilometer: currentPace)
        let paceUnit = PaceFormatter.paceUnit()

        let hrVal = runRecord.workingAvgHeartRate > 0 ? Int(round(runRecord.workingAvgHeartRate)) : Int(round(runRecord.rawAvgHeartRate))
        let cadVal = runRecord.workingAvgCadence > 0 ? Int(round(runRecord.workingAvgCadence)) : Int(round(runRecord.rawAvgCadence))

        VStack(spacing: 12) {
            // Row 1: The Big 3 (Distance, Time, Pace)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("DISTANCE")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(String(format: "%.2f", distanceConverted))
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.primary)
                        Text(distanceUnit)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text("MOVING TIME")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                    Text(timeString)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text("AVG PACE")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(paceValue)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(RunalystColor.pace)
                        Text(paceUnit)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Row 2: Secondary biometrics
            if hrVal > 0 || cadVal > 0 {
                Divider()
                    .opacity(0.6)

                HStack(spacing: 18) {
                    if hrVal > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: RunalystIcon.heartRate)
                                .font(.system(size: 12))
                                .foregroundColor(RunalystColor.heartRate)
                            Text("AVG HR")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(.secondary)
                            Text("\(hrVal)")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(.primary)
                            Text("BPM")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                    }

                    if cadVal > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: RunalystIcon.cadence)
                                .font(.system(size: 12))
                                .foregroundColor(RunalystColor.cadence)
                            Text("CADENCE")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(.secondary)
                            Text("\(cadVal)")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(.primary)
                            Text("SPM")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()
                }
            }
        }
        .liquidGlass(cornerRadius: 16, padding: 16, accentColor: RunalystColor.pace)
        .padding(.horizontal)
    }

    @ViewBuilder
    var secondaryBiomechanicsCard: some View {
        if hasBiomechanicsData {
            let currentOsc = runRecord.workingAvgVerticalOscillation ?? runRecord.rawAvgVerticalOscillation
            let currentStride = runRecord.workingAvgStrideLength ?? runRecord.rawAvgStrideLength
            let currentStrideConverted: Double? = {
                guard let stride = currentStride, stride > 0 else { return nil }
                return useMetricSystem ? stride : (stride * 3.28084)
            }()
            let currentVR = runRecord.verticalRatio
            let currentEF = runRecord.efficiencyFactor

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: RunalystIcon.verticalOscillation)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(RunalystColor.pace)
                        Text("STRIDE & RUNNING ECONOMY")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showingBiomechanicsExplainer = true
                    } label: {
                        Image(systemName: RunalystIcon.glassBoxInfo)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Learn more about running dynamics and biomechanics")
                }

                let columns = horizontalSizeClass == .regular
                    ? [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
                    : [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

                LazyVGrid(columns: columns, spacing: 10) {
                    if let osc = currentOsc {
                        MiniStatTile(
                            title: "Bounce",
                            value: String(format: "%.1f", osc),
                            unit: "cm",
                            icon: RunalystIcon.verticalOscillation,
                            accentColor: Color.orange
                        )
                    }

                    if let stride = currentStrideConverted {
                        MiniStatTile(
                            title: "Stride Length",
                            value: String(format: "%.2f", stride),
                            unit: useMetricSystem ? "m" : "ft",
                            icon: RunalystIcon.strideLength,
                            accentColor: Color.indigo
                        )
                    }

                    if let vr = currentVR {
                        MiniStatTile(
                            title: "Bounce Ratio",
                            value: String(format: "%.1f", vr),
                            unit: "%",
                            icon: "percent",
                            accentColor: Color.teal
                        )
                    }

                    if let ef = currentEF {
                        MiniStatTile(
                            title: "Economy",
                            value: String(format: "%.2f", ef),
                            unit: "m/b",
                            icon: RunalystIcon.efficiencyFactor,
                            accentColor: RunalystColor.coach
                        )
                    }
                }
            }
            .liquidGlass(cornerRadius: 16, padding: 14, accentColor: RunalystColor.pace)
            .padding(.horizontal)
            .id("secondaryBiomechanicsCard")
        }
    }

    @ViewBuilder
    var performanceAndAnalysisSection: some View {
        let isRecovery = runRecord.detectedTypeRaw == "Recovery Run" || (runRecord.percentZone4 <= 0.02 && runRecord.workingAvgHeartRate > 0 && runRecord.workingAvgHeartRate <= 135 && runRecord.duration >= 600)

        if let drillId = resolvedSessionDrillId {
            let isLinkedTechniqueDrill = (prescribedDrillName != nil)

            let title: String = {
                if isLinkedTechniqueDrill {
                    return drillId.title
                }
                if isRecovery {
                    return "Zone 1 Recovery Run"
                } else if runRecord.detectedTypeRaw == "Steady Effort" {
                    return "Zone 2 Steady Base"
                } else if runRecord.detectedTypeRaw == "Easy Run" {
                    return "Zone 2 Easy Base"
                } else {
                    return runRecord.detectedTypeRaw
                }
            }()

            let subtitle: String? = {
                if isLinkedTechniqueDrill {
                    let adherence = DrillExecutionScorecard.evaluateDrillAdherence(
                        runRecord: runRecord,
                        drillId: drillId,
                        baselineCadence: baselineCadence
                    )
                    if adherence.totalCount > 0 {
                        return "Pre-Run Primer • \(adherence.metCount) of \(adherence.totalCount) on Target"
                    } else {
                        return "Pre-Run Primer • Target Met"
                    }
                } else {
                    let hr = Int(round(runRecord.workingAvgHeartRate))
                    if isRecovery || (hr > 0 && hr <= 135) {
                        return "Aerobic Base • Zero Cardiac Strain"
                    } else if hr > 0 && hr <= 144 {
                        return "Aerobic Base • Steady Aerobic Control"
                    } else {
                        return "Aerobic Base • Elevated Cardiac Strain"
                    }
                }
            }()

            let scorecard = DrillExecutionScorecard(
                runRecord: runRecord,
                drillId: drillId,
                baselineCadence: baselineCadence,
                baselineOscillation: baselineOscillation,
                customTitle: title,
                customSubtitle: subtitle
            )
            if horizontalSizeClass == .regular {
                HStack(alignment: .top, spacing: 16) {
                    scorecard
                    aiRunAnalysisCard
                }
                .padding(.horizontal)

                workoutRhythmTimeline
                    .padding(.horizontal)
            } else {
                scorecard
                    .padding(.horizontal)

                workoutRhythmTimeline
                    .padding(.horizontal)

                aiRunAnalysisCard
                    .padding(.horizontal)
            }
        } else if runRecord.evaluationModality == .intervals && hasIntervalWorkReps {
            let rawType = runRecord.detectedTypeRaw.isEmpty ? "Intervals" : runRecord.detectedTypeRaw
            let title = rawType
            let scorecard = IntervalPerformanceCard(
                runRecord: runRecord,
                baselineCadence: baselineCadence,
                customTitle: title
            )
            if horizontalSizeClass == .regular {
                HStack(alignment: .top, spacing: 16) {
                    scorecard
                    aiRunAnalysisCard
                }
                .padding(.horizontal)

                workoutRhythmTimeline
                    .padding(.horizontal)
            } else {
                scorecard
                    .padding(.horizontal)

                workoutRhythmTimeline
                    .padding(.horizontal)

                aiRunAnalysisCard
                    .padding(.horizontal)
            }
        } else {
            workoutRhythmTimeline
                .padding(.horizontal)

            aiRunAnalysisCard
                .padding(.horizontal)
        }
    }
}
