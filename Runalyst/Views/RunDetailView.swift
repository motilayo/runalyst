import SwiftUI
import UIKit
import SwiftData
import WorkoutKit
import RunalystCore

struct RunDetailView: View {
    @Bindable var runRecord: RunRecord
    @AppStorage("useMetricSystem") private var useMetricSystem: Bool = Locale.current.measurementSystem == .metric
    @Environment(\.modelContext) private var modelContext
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query private var existingRuns: [RunRecord]

    @State private var isForceAnalyzing: Bool = false
    @State private var showingBiomechanicsExplainer = false
    @State private var showingClassificationExplainer = false
    @State private var showingDrillExplainer = false
    @State private var isGeneratingInsight = false
    @State private var showingAnalystChat = false
    @State private var showingEnvironmentInfo = false

    private var environmentInfoMessage: String {
        guard runRecord.isIndoor == true else {
            return String(localized: "Recorded outdoors with GPS. Pace, distance, and route come directly from your Apple Watch.")
        }
        switch runRecord.dataSourceRaw?.lowercased() {
        case "gymkit":
            return String(localized: "Recorded on a GymKit-connected treadmill. Speed and distance were synced directly from the machine.")
        case "footpod":
            return String(localized: "Recorded on a treadmill with a Bluetooth footpod providing distance and cadence.")
        default:
            return String(localized: "Recorded on a treadmill using your Apple Watch wrist sensors. Since the belt sets your speed, coaching focuses on heart rate and cadence rhythm.")
        }
    }

    private var baselineStats: SessionSynthesisEngine.WeightedBaselineStats? {
        SessionSynthesisEngine.computeWeightedBaselineStats(from: existingRuns, priorTo: runRecord.date)
    }

    private var baselinePace: Double? {
        baselineStats?.avgPace
    }

    private var baselineHR: Double? {
        baselineStats?.avgHR
    }

    private var baselineCadence: Double? {
        baselineStats?.avgCadence
    }

    private var baselineOscillation: Double? {
        baselineStats?.avgOscillation
    }

    private var baselineStrideLength: Double? {
        baselineStats?.avgStrideLength
    }

    private var baselineVerticalRatio: Double? {
        baselineStats?.avgVerticalRatio
    }

    private var formattedRunDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE, MMM d, yyyy"
        return formatter.string(from: runRecord.date)
    }

    private var formattedRunTimeRange: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        let startStr = formatter.string(from: runRecord.date)
        if runRecord.duration > 0 {
            let endDate = runRecord.date.addingTimeInterval(runRecord.duration)
            let endStr = formatter.string(from: endDate)
            return "\(startStr) – \(endStr)"
        }
        return startStr
    }

    private let classificationOptions = [
        "Steady Effort", "Easy Run", "Tempo Run", "Intervals", "Pyramids",
        "Progression Run", "Recovery Run", "Hill Repeats",
        "Long Run", "Fartlek", "Urban Traffic", "Mixed Effort (Review)"
    ]

    private var prescribedDrillName: String? {
        guard !runRecord.isDeleted, runRecord.modelContext != nil else { return nil }
        return runRecord.prescribedDrillName
    }

    private var drillPillText: String {
        if let name = prescribedDrillName {
            return "Drill: \(name)"
        }
        return "Prescribed Drill"
    }

    private var effectiveScorecardDrillId: PreRunDrillId? {
        guard let drillName = prescribedDrillName else { return nil }
        return PreRunDrillId.allCases.first(where: { $0.title == drillName || $0.rawValue == drillName })
    }

    private var hasIntervalWorkReps: Bool {
        runRecord.signature?.phaseSegments.contains(where: { $0.kind == "work" && $0.avgPace > 0 }) ?? false
    }

    private func normalizeDrillClassification() {
        guard !runRecord.isDeleted, runRecord.modelContext != nil else { return }
        // Clean up any invalid drill tags on runs that are not genuine drills
        cleanUpInvalidDrillTagsIfNeeded()

        // Only normalize if detectedTypeRaw is an ACTUAL drill title (e.g. "Rhythm Intervals"), never a standard classification like "Intervals"
        guard let canonicalDrill = PreRunDrillId.canonicalDrillTitle(for: runRecord.detectedTypeRaw),
              let parentClass = PreRunDrillId.correspondingClassification(for: runRecord.detectedTypeRaw) else {
            return
        }

        if !runRecord.framboiseTags.contains("prescribedDrill") {
            runRecord.framboiseTags.append("prescribedDrill")
        }
        let drillTag = "drill:\(canonicalDrill)"
        if !runRecord.framboiseTags.contains(drillTag) {
            runRecord.framboiseTags.append(drillTag)
        }
        if runRecord.detectedTypeRaw != parentClass {
            runRecord.detectedTypeRaw = parentClass
            try? modelContext.save()
        }
    }

    private func cleanUpInvalidDrillTagsIfNeeded() {
        guard !runRecord.isDeleted, runRecord.modelContext != nil else { return }
        let allIds = Set(PreRunDrillId.allCases.map(\.rawValue))
        let allTitles = Set(PreRunDrillId.allCases.map(\.title))
        let hasAnyDrillTag = runRecord.framboiseTags.contains {
            $0 == "prescribedDrill" || $0.hasPrefix("drill:") || allIds.contains($0) || allTitles.contains($0)
        }
        // A run is only a prescribed drill if it has a confirmed authentic drill name
        if hasAnyDrillTag && prescribedDrillName == nil {
            runRecord.framboiseTags.removeAll { tag in
                tag == "prescribedDrill" ||
                tag.hasPrefix("drill:") ||
                tag.hasPrefix("drillIntervals:") ||
                tag.hasPrefix("drillWorkCadence:") ||
                tag.hasPrefix("drillRecCadence:") ||
                tag.hasPrefix("drillReps:") ||
                tag.hasPrefix("drillRepDetails:") ||
                allIds.contains(tag) ||
                allTitles.contains(tag)
            }
            if let sigClass = runRecord.signature?.classification.trimmingCharacters(in: .whitespacesAndNewlines),
               !sigClass.isEmpty,
               runRecord.detectedTypeRaw != sigClass {
                runRecord.detectedTypeRaw = sigClass
            }
            try? modelContext.save()
        }
    }

    struct RunAnalysisTakeawayItem: Identifiable {
        var id: String { title }
        let icon: String
        let iconColor: Color
        let title: String
        let detail: String
    }

    private var resolvedSessionDrillId: PreRunDrillId? {
        if let drillId = effectiveScorecardDrillId { return drillId }
        let isRec = runRecord.detectedTypeRaw == "Recovery Run" || (runRecord.percentZone4 <= 0.02 && runRecord.workingAvgHeartRate > 0 && runRecord.workingAvgHeartRate <= 135 && runRecord.duration >= 600)
        let isEasyOrSteady = runRecord.detectedTypeRaw == "Easy Run" || runRecord.detectedTypeRaw == "Steady Effort" || runRecord.detectedTypeRaw == "Zone 2" || runRecord.detectedTypeRaw == "Long Run"
        if isRec { return .aerobicFlush }
        if isEasyOrSteady { return .zone2Run }
        return nil
    }

    var deterministicRunAnalysisTakeaways: [RunAnalysisTakeawayItem] {
        guard runRecord.workingAvgCadence > 0 || runRecord.workingAvgHeartRate > 0 else { return [] }
        let isIndoor = runRecord.isIndoor ?? false

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
            baselineStats: baselineStats.map { (avgPace: $0.avgPace, avgCadence: $0.avgCadence, avgHR: $0.avgHR) }
        )
        let floor = context.runnerProfile.heightAdjustedCadenceFloor
        let cad = context.workingCadence

        var items: [RunAnalysisTakeawayItem] = []

        // 1. Cadence & Biomechanics
        let isRecovery = runRecord.detectedTypeRaw == "Recovery Run" || (runRecord.percentZone4 <= 0.02 && runRecord.workingAvgHeartRate > 0 && runRecord.workingAvgHeartRate <= 135)
        let effectiveFloor = isRecovery ? max(138, floor - 10) : floor
        if let drillId = effectiveScorecardDrillId, prescribedDrillName != nil {
            let adherence = DrillExecutionScorecard.evaluateDrillAdherence(
                runRecord: runRecord,
                drillId: drillId,
                baselineCadence: baselineCadence
            )
            let metCount = adherence.metCount
            let totalCount = adherence.totalCount
            let targetCadence = adherence.targetCadence
            let cadDetail: String
            if totalCount > 0 && metCount == totalCount {
                cadDetail = "Target turnover of \(targetCadence) SPM was held flawlessly across all \(totalCount) work intervals, reinforcing efficient running economy."
            } else if totalCount > 0 && metCount > 0 {
                cadDetail = "Target turnover reached \(targetCadence) SPM on \(metCount) of \(totalCount) work intervals, building consistent neuromuscular turnover."
            } else {
                cadDetail = "Turnover averaged \(cad) SPM against your \(targetCadence) SPM drill target."
            }
            items.append(RunAnalysisTakeawayItem(
                icon: "metronome.fill",
                iconColor: Color.green,
                title: "Drill Turnover",
                detail: cadDetail
            ))
        } else if cad > 0 {
            let cadDetail: String
            if isRecovery {
                cadDetail = "Turnover averaged \(cad) SPM with relaxed, low-impact stride mechanics, ideal for active recovery and flushing muscular fatigue."
            } else if cad >= effectiveFloor {
                cadDetail = "Turnover averaged \(cad) SPM, safely above your \(floor) SPM mechanical floor. This cadence helps keep foot strikes underneath your hips and cushions joint landing\(isIndoor ? " on the treadmill belt" : "")."
            } else {
                cadDetail = "Turnover averaged \(cad) SPM, dipping below your \(floor) SPM mechanical floor. Increasing step rate will shorten your stride and cushion joint landing\(isIndoor ? " on the moving belt" : "")."
            }
            items.append(RunAnalysisTakeawayItem(
                icon: "figure.run",
                iconColor: cad >= effectiveFloor ? Color.green : Color.orange,
                title: "Cadence & Form",
                detail: cadDetail
            ))
        }

        // 2. Cardiovascular Effort & Decoupling
        if context.workingHR > 0 {
            let hrDetail: String
            let hrColor: Color
            if isIndoor {
                hrDetail = "Running indoors without convective airflow accelerates thermal buildup; your \(context.workingHR) BPM average reflects steady aerobic conditioning under indoor heat accumulation."
                hrColor = Color(red: 1.0, green: 0.18, blue: 0.55)
            } else if context.hasCardiacDrift {
                hrDetail = "Heart rate climbed +\(context.cardiacDriftMagnitudeBPM) BPM over the duration, reflecting cardiovascular drift and internal fatigue as the session progressed."
                hrColor = Color.orange
            } else {
                hrDetail = "Heart rate averaged \(context.workingHR) BPM with stable cardiovascular coupling, demonstrating controlled aerobic efficiency throughout."
                hrColor = Color(red: 1.0, green: 0.18, blue: 0.55)
            }
            items.append(RunAnalysisTakeawayItem(
                icon: "heart.fill",
                iconColor: hrColor,
                title: "Cardiovascular Control",
                detail: hrDetail
            ))
        }

        // 3. Modality Execution & Harmonized Status
        let resolvedDrill = resolvedSessionDrillId

        if let drill = resolvedDrill {
            let adherence = DrillExecutionScorecard.calculateAdherence(
                runRecord: runRecord,
                drillId: drill,
                baselineCadence: baselineCadence,
                baselineOscillation: baselineOscillation
            )
            let statusText = adherence.tier.badgeText(for: drill)
            let execDetail: String
            if adherence.tier == .exceeded || adherence.tier == .met {
                execDetail = "Execution Status: \(statusText) — aerobic target and cadence stability were maintained throughout the session."
            } else {
                execDetail = "Execution Status: \(statusText) — telemetry showed cardiac drift or cadence drop beyond target boundaries."
            }
            items.append(RunAnalysisTakeawayItem(
                icon: "checkmark.seal.fill",
                iconColor: adherence.tier.tintColor,
                title: "Execution Verdict",
                detail: execDetail
            ))
        } else if runRecord.evaluationModality == .intervals && hasIntervalWorkReps {
            let workSegments = runRecord.signature?.phaseSegments.filter { $0.kind == "work" && $0.avgPace > 0 } ?? []
            if !workSegments.isEmpty {
                let meanWorkPace = workSegments.reduce(0.0) { $0 + $1.avgPace } / Double(workSegments.count)
                let paceStr = PaceFormatter.formatPace(secondsPerKilometer: meanWorkPace)
                let avgWorkCad = Int(workSegments.reduce(0.0) { $0 + $1.avgCadence } / Double(workSegments.count))
                items.append(RunAnalysisTakeawayItem(
                    icon: "flag.checkered",
                    iconColor: Color.purple,
                    title: "Interval Execution",
                    detail: "Active work reps hit \(paceStr) at \(avgWorkCad) SPM with consistent pacing repeatability."
                ))
            }
        }

        return items
    }

    var deterministicRunAnalysisSummary: String? {
        let details = deterministicRunAnalysisTakeaways.map(\.detail)
        guard !details.isEmpty else { return nil }
        return details.joined(separator: " ")
    }

    @ViewBuilder
    private var aiRunAnalysisCard: some View {
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
                    let analysisHeadline: String = {
                        if let drillName = prescribedDrillName {
                            return "\(drillName) Technique Analysis"
                        }
                        if let insight = runRecord.insight, !insight.headline.isEmpty {
                            return insight.headline
                        }
                        return "\(runRecord.detectedTypeRaw) Biomechanical Analysis"
                    }()

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

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showingAnalystChat = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.subheadline.bold())
                        Text("Ask AI Coach about this run")
                            .font(.subheadline.bold())
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2.bold())
                    }
                    .foregroundColor(.purple)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(minHeight: 44)
                    .background(Color.purple.opacity(0.12))
                    .cornerRadius(12)
                    .contentShape(Rectangle())
                }
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
    private var environmentPill: some View {
        let isIndoor = runRecord.isIndoor ?? false
        Button {
            showingEnvironmentInfo = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isIndoor ? RunalystIcon.indoor : RunalystIcon.outdoor)
                    .font(.caption2.bold())
                Text(isIndoor ? "Indoor" : "Outdoor")
                    .font(.caption.bold())
            }
            .foregroundColor(isIndoor ? RunalystColor.indoor : RunalystColor.outdoor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background((isIndoor ? RunalystColor.indoor : RunalystColor.outdoor).opacity(0.12))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke((isIndoor ? RunalystColor.indoor : RunalystColor.outdoor).opacity(0.3), lineWidth: 1)
            )
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Workout Environment: \(isIndoor ? "Indoor" : "Outdoor")")
        .accessibilityHint("Double tap to change workout environment")
        .alert(isIndoor ? "Indoor Session" : "Outdoor Session", isPresented: $showingEnvironmentInfo) {
            Button(isIndoor ? "Switch to Outdoor" : "Switch to Indoor (Treadmill)") {
                let newIndoor = !isIndoor
                runRecord.isIndoor = newIndoor
                runRecord.framboiseTags.removeAll { $0 == "userSetIndoor" || $0 == "userSetOutdoor" }
                runRecord.framboiseTags.append(newIndoor ? "userSetIndoor" : "userSetOutdoor")
                UserDefaults.standard.set(newIndoor, forKey: "preferredWorkoutIsIndoor")
                try? modelContext.save()
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(environmentInfoMessage)
        }
    }

    @ViewBuilder
    private var classificationPill: some View {
        Menu {
            ForEach(classificationOptions, id: \.self) { option in
                Button {
                    let old = runRecord.detectedTypeRaw
                    runRecord.detectedTypeRaw = option
                    updateClassification(to: option, from: old)
                } label: {
                    if option == runRecord.detectedTypeRaw {
                        Label(option, systemImage: "checkmark")
                    } else {
                        Text(option)
                    }
                }
            }

            Divider()

            Button {
                showingClassificationExplainer = true
            } label: {
                Label("About Classifications...", systemImage: "info.circle")
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "figure.run")
                    .font(.caption2.bold())
                Text(runRecord.detectedTypeRaw.isEmpty ? runRecord.normalizedClassification : runRecord.detectedTypeRaw)
                    .font(.caption.bold())
                Image(systemName: "chevron.down")
                    .font(.caption2.bold())
                    .opacity(0.7)
            }
            .foregroundColor(runRecord.detectedTypeRaw == "Mixed Effort (Review)" ? .orange : Color(red: 0.05, green: 0.45, blue: 0.5))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                (runRecord.detectedTypeRaw == "Mixed Effort (Review)" ? Color.orange : Color(red: 0.05, green: 0.45, blue: 0.5))
                    .opacity(0.12)
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        (runRecord.detectedTypeRaw == "Mixed Effort (Review)" ? Color.orange : Color(red: 0.05, green: 0.45, blue: 0.5))
                            .opacity(0.3),
                        lineWidth: 1
                    )
            )
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Workout Classification: \(runRecord.detectedTypeRaw.isEmpty ? runRecord.normalizedClassification : runRecord.detectedTypeRaw)")
        .accessibilityHint("Double tap to reclassify workout")
    }

    @ViewBuilder
    private var heroMetricsCard: some View {
        let activeDistanceMeters = runRecord.effectiveWorkingDistanceMeters > 0 ? runRecord.effectiveWorkingDistanceMeters : runRecord.totalDistanceMeters
        let distanceConverted = useMetricSystem ? (activeDistanceMeters / 1000.0) : (activeDistanceMeters / 1609.344)
        let distanceUnit = useMetricSystem ? "km" : "mi"

        let activeDuration = runRecord.effectiveWorkingDurationSeconds > 0 ? runRecord.effectiveWorkingDurationSeconds : runRecord.duration
        let minutes = Int(activeDuration) / 60
        let seconds = Int(activeDuration) % 60
        let timeString = String(format: "%d:%02d", minutes, seconds)

        let workingKm = activeDistanceMeters / 1000.0
        let currentPace = (workingKm > 0 && activeDuration > 0) ? (activeDuration / workingKm) : runRecord.workingAvgPace
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
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(timeString)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.primary)
                        Text("min")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                    }
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
    private var drillControl: some View {
        DrillLinkControlView(
            runRecord: runRecord,
            prescribedDrillName: prescribedDrillName,
            baselineCadence: baselineCadence
        )
    }

    @ViewBuilder
    private var workoutRhythmTimeline: some View {
        if let segments = runRecord.signature?.phaseSegments, !segments.isEmpty {
            let isIntervalOrDrill: Bool = {
                let type = runRecord.detectedTypeRaw
                let isContinuous = type == "Recovery Run" || type == "Easy Run" || type == "Steady Effort" || type == "Long Run"
                if let drillId = effectiveScorecardDrillId {
                    return !drillId.isAerobicContinuous
                }
                if isContinuous {
                    return false
                }
                if runRecord.evaluationModality == .intervals {
                    return true
                }
                return type == "Intervals" || type == "Fartlek" || type == "Pyramids" || type == "Hill Repeats"
            }()
            let heightFloor = runRecord.signature?.cadenceFloor ?? Double(SessionSynthesisCore.heightAdjustedCadenceFloor(heightCm: UserDefaults.standard.double(forKey: "userHeight") > 0 ? UserDefaults.standard.double(forKey: "userHeight") : 175.0))
            let isRecovery = runRecord.detectedTypeRaw == "Recovery Run" || (runRecord.percentZone4 <= 0.02 && runRecord.workingAvgHeartRate > 0 && runRecord.workingAvgHeartRate <= 135)
            let effectiveFloor = isRecovery ? max(138.0, heightFloor - 10.0) : heightFloor

            AdaptiveWorkoutTelemetryCard(
                runRecord: runRecord,
                phaseSegments: segments,
                cadenceFloor: effectiveFloor,
                averageCadence: runRecord.workingAvgCadence,
                workoutDuration: runRecord.duration,
                isIntervalOrDrill: isIntervalOrDrill,
                workoutType: runRecord.detectedTypeRaw
            )
            .id("workoutRhythmChart-\(runRecord.detectedTypeRaw)")
        }
    }

    private var hasBiomechanicsData: Bool {
        (runRecord.workingAvgVerticalOscillation ?? runRecord.rawAvgVerticalOscillation) != nil ||
        (runRecord.workingAvgStrideLength ?? runRecord.rawAvgStrideLength) != nil ||
        runRecord.verticalRatio != nil ||
        runRecord.efficiencyFactor != nil
    }

    @ViewBuilder
    private var secondaryBiomechanicsCard: some View {
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
    private var performanceAndAnalysisSection: some View {
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

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(spacing: 20) {
                // Header: Formatted run date & time + compact horizontal tags
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(formattedRunDate)
                            .font(.headline.weight(.bold))
                            .foregroundColor(.primary)

                        Text(formattedRunTimeRange)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.secondary)
                    }

                    // Compact horizontal tags strip: [ 🏠 Indoor ] [ 🏃 Easy Run ▾ ] [ ＋ Add Drill ]
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            environmentPill
                            classificationPill
                            drillControl
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 4)

                // Incline / Hill Confirmation Banner
                if runRecord.needsInclineReview == true {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(Color.orange.opacity(0.15))
                                    .frame(width: 28, height: 28)
                                Image(systemName: "mountain.2.fill")
                                    .font(.caption.bold())
                                    .foregroundColor(.orange)
                            }
                            Text("Incline Telemetry Detected")
                                .font(.subheadline.bold())
                                .foregroundColor(.primary)
                        }

                        Text("Cardiovascular strain spiked significantly while pace was flat. Were you running incline intervals on the treadmill?")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 10) {
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    runRecord.detectedTypeRaw = "Hill Repeats"
                                    runRecord.needsInclineReview = false
                                    if !runRecord.framboiseTags.contains("userConfirmedIncline") {
                                        runRecord.framboiseTags.append("userConfirmedIncline")
                                    }
                                    let correction = TrainingCorrection(
                                        runRecordID: runRecord.id,
                                        originalLabel: "Steady Effort",
                                        correctedLabel: "Hill Repeats",
                                        featureVector: [runRecord.workingAvgPace, runRecord.paceCV, runRecord.paceSlope, runRecord.percentZone4, runRecord.duration / 60.0]
                                    )
                                    modelContext.insert(correction)
                                    try? modelContext.save()
                                }
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "checkmark")
                                        .font(.caption2.bold())
                                    Text("Yes, Incline Intervals")
                                        .font(.caption.bold())
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.orange)
                                .clipShape(Capsule())
                            }

                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    runRecord.needsInclineReview = false
                                    if !runRecord.framboiseTags.contains("userRejectedIncline") {
                                        runRecord.framboiseTags.append("userRejectedIncline")
                                    }
                                    try? modelContext.save()
                                }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "xmark")
                                        .font(.caption2.bold())
                                    Text("No, Flat Belt")
                                        .font(.caption.bold())
                                }
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color(UIColor.tertiarySystemFill))
                                .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(16)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.orange.opacity(0.25), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
                    .padding(.horizontal)
                }

                // Mixed Effort Review Banner (Only displayed if not already prompting incline)
                if runRecord.needsInclineReview != true && runRecord.needsClassificationReview {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            ZStack {
                                Circle()
                                    .fill(Color.orange.opacity(0.15))
                                    .frame(width: 28, height: 28)
                                Image(systemName: "sparkles")
                                    .font(.caption.bold())
                                    .foregroundColor(.orange)
                            }
                            Text("Classification Needs Review")
                                .font(.subheadline.bold())
                            Spacer()
                            if let conf = runRecord.classificationConfidence {
                                Text("\(Int(round(conf * 100)))% confidence")
                                    .font(.caption2.bold())
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(UIColor.tertiarySystemFill))
                                    .clipShape(Capsule())
                            }
                        }

                        Text("Telemetry showed competing patterns across pace, heart rate, and cadence. Confirm your run style:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        let candidates: [(key: String, value: Double)] = {
                            if let probs = runRecord.classificationProbabilities, !probs.isEmpty {
                                var filtered = probs.filter { $0.key != "Mixed Effort (Review)" }
                                if runRecord.isIndoor == true {
                                    filtered = filtered.filter { $0.key != "Urban Traffic" && $0.key != "Hill Repeats" }
                                }
                                var sorted = filtered.sorted { $0.value > $1.value }
                                let currentType = runRecord.detectedTypeRaw
                                if currentType != "Mixed Effort (Review)" && !sorted.prefix(3).contains(where: { $0.key == currentType }) {
                                    sorted.insert((key: currentType, value: probs[currentType] ?? 0.50), at: 0)
                                }
                                return Array(sorted.prefix(3)).map { (key: $0.key, value: $0.value) }
                            } else {
                                let defaultOptions = (runRecord.isIndoor == true) ?
                                    [("Intervals", 0.45), ("Fartlek", 0.35), ("Steady Effort", 0.20)] :
                                    [("Intervals", 0.45), ("Hill Repeats", 0.35), ("Tempo Run", 0.20)]
                                return defaultOptions
                            }
                        }()

                        HStack(spacing: 8) {
                            ForEach(candidates, id: \.key) { label, prob in
                                Button {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                        updateClassification(to: label)
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(label)
                                            .font(.caption.bold())
                                        Text("\(Int(round(prob * 100)))%")
                                            .font(.caption2)
                                            .opacity(0.8)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(runRecord.detectedTypeRaw == label ? Color.accentColor : Color(UIColor.tertiarySystemFill))
                                    .foregroundColor(runRecord.detectedTypeRaw == label ? .white : .primary)
                                    .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
                    .padding(.horizontal)
                }

                // MARK: - Core Run Metrics First
                heroMetricsCard
                .id("heroMetricsCard")

                // MARK: Scorecard & AI Run Analysis
                performanceAndAnalysisSection
                    .id("performanceSection-\(runRecord.detectedTypeRaw)")

                // MARK: - Secondary Biomechanics
                secondaryBiomechanicsCard
            }
            .frame(maxWidth: horizontalSizeClass == .regular ? 880 : .infinity)
            .frame(maxWidth: .infinity)
            .padding(.vertical)

            .task(id: runRecord.id) {
                guard !runRecord.isDeleted, runRecord.modelContext != nil else { return }

                if runRecord.isIndoor == nil {
                    runRecord.isIndoor = (runRecord.dataSourceRaw == "gymkit") ? true : false
                    try? modelContext.save()
                }
                if runRecord.detectedTypeRaw.isEmpty {
                    runRecord.detectedTypeRaw = runRecord.normalizedClassification
                    try? modelContext.save()
                }

                // Auto-resolve or reconcile drill recognition against authentic HealthKit workout metadata / scheduled intent
                // ONLY if the run has NO drill assigned yet and user hasn't manually linked or unlinked one
                if prescribedDrillName == nil && !runRecord.framboiseTags.contains("userLinkedDrill") && !runRecord.framboiseTags.contains("userUnlinkedDrill") {
                    if let workout = try? await HealthKitManager.shared.fetchWorkout(with: runRecord.hkWorkoutID) {
                        let buckets = (try? await HealthKitManager.shared.fetchBucketedSamples(for: workout)) ?? []
                        let baseline = runRecord.computeHistoricalBaselineCadence().map(Int.init)
                        let matched = WorkoutBridge.matchDrill(
                            workout: workout,
                            durationSeconds: runRecord.duration,
                            buckets: buckets,
                            baselineCadence: baseline
                        )
                        if let matched = matched {
                            let canonical = PreRunDrillId.canonicalDrillTitle(for: matched.drillTitle) ?? matched.drillTitle
                            let drillTag = "drill:\(canonical)"
                            if !runRecord.framboiseTags.contains(drillTag) {
                                runRecord.framboiseTags.removeAll { $0.hasPrefix("drill:") || PreRunDrillId.allCases.map(\.rawValue).contains($0) }
                                if !runRecord.framboiseTags.contains("prescribedDrill") {
                                    runRecord.framboiseTags.append("prescribedDrill")
                                }
                                if let preRunId = matched.preRunDrillId {
                                    runRecord.framboiseTags.append(preRunId)
                                }
                                runRecord.framboiseTags.append(drillTag)
                            }
                            if let parentClass = PreRunDrillId.correspondingClassification(for: canonical),
                               runRecord.detectedTypeRaw != parentClass {
                                runRecord.detectedTypeRaw = parentClass
                            }

                            if let drillId = PreRunDrillId(rawValue: matched.preRunDrillId ?? "")
                                ?? PreRunDrillId.allCases.first(where: { $0.title == matched.drillTitle }) {
                                let thirtyDayCadence = baseline ?? Int(runRecord.workingAvgCadence > 0 ? runRecord.workingAvgCadence : 155)
                                let oscDelta = (runRecord.workingAvgVerticalOscillation ?? 9.5) - 9.5
                                let targetOverride = runRecord.effectivePrescribedTargetCadence(drillId: drillId, baselineCadence: thirtyDayCadence)
                                    ?? matched.targetCadence
                                let intervalSummary = DrillIntervalEvaluator.evaluate(
                                    workout: workout,
                                    buckets: buckets,
                                    drillId: drillId,
                                    baselineCadence: thirtyDayCadence,
                                    workoutDuration: runRecord.duration,
                                    oscDelta: oscDelta,
                                    targetCadenceOverride: targetOverride
                                )
                                runRecord.framboiseTags.removeAll {
                                    $0.hasPrefix("drillIntervals:") ||
                                    $0.hasPrefix("drillWorkCadence:") ||
                                    $0.hasPrefix("drillRecCadence:") ||
                                    $0.hasPrefix("drillReps:") ||
                                    $0.hasPrefix("drillRepDetails:")
                                }
                                for tag in intervalSummary.framboiseTags where !runRecord.framboiseTags.contains(tag) {
                                    runRecord.framboiseTags.append(tag)
                                }
                            }

                            try? modelContext.save()
                        }
                    }
                }

                if runRecord.insight == nil {
                    if #available(iOS 26.0, *) {
                        await CoachingEngine.shared.requestAnalysis(for: runRecord)
                    }
                }
            }
        }
        .refreshable {
            isGeneratingInsight = true
            defer { isGeneratingInsight = false }

            do {
                try await HealthKitManager.shared.refreshWorkoutMetrics(for: runRecord, in: modelContext)
            } catch {
                print("Single run HealthKit refresh failed: \(error.localizedDescription)")
            }

            if #available(iOS 26.0, *) {
                await CoachingEngine.shared.requestAnalysis(for: runRecord, force: true)
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 80)
        }
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Run Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.regularMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                CoachPillButton {
                    showingAnalystChat = true
                }
            }
        }
        .sheet(isPresented: $showingBiomechanicsExplainer) {
            GlassBoxExplainerSheet(
                title: "Stride & Running Economy",
                categoryBadge: "Biomechanics",
                whatSummary: "Running economy reflects how efficiently your body converts oxygen and energy into forward propulsion. Optimal stride mechanics direct force horizontally through hip extension rather than wasting energy bouncing upward.",
                whyItMatters: "High vertical oscillation (> 10 cm) and long ground contact times cause heavy joint braking forces. Lower bounce and a vertical ratio under 8% preserve elastic recoil, saving glycogen for the final miles.",
                howItWorks: "Runalyst calculates Efficiency Factor as meters traveled per heartbeat (Speed / Heart Rate). Vertical Ratio measures vertical bounce divided by stride length. Pause-trimmed Working Stats filter sensor noise at stoplights.",
                formula: "Efficiency Factor = Speed (m/min) / HR (BPM) • Vertical Ratio = Bounce (cm) / Stride (m)",
                targetRange: "Bounce: 6.0–9.0 cm • Stride: 1.0–1.4 m • Ratio: < 8.0%"
            )
        }
        .sheet(isPresented: $showingAnalystChat) {
            AnalystChatView(runRecord: runRecord)
        }
        .sheet(isPresented: $showingClassificationExplainer) {
            GlassBoxExplainerSheet(
                title: "Workout Classification",
                categoryBadge: "CoreML & Biometrics",
                whatSummary: "Runalyst analyzes your continuous minute-by-minute running data using on-device machine learning paired with physiological cardiac rules to identify what your body actually experienced.",
                whyItMatters: "Strict cardiac guardrails ensure that high-intensity or elevated heart rate sessions are never classified as easy or recovery, even if your pace was slow on hills or in the heat.",
                howItWorks: "Evaluates multi-signal telemetry across pace coefficient of variation (CV), pace slope regression, duration, and Zone 4 heart rate percentage with sub-20s pause trimming.",
                formula: "Pace CV = σ ÷ μ • Pace Slope = Linear Regression over Time",
                targetRange: "Easy: Zone 1–2 • Steady: CV < 6% • Tempo: Zone 3–4 • Intervals: Work Surges"
            )
        }
        .onAppear {
            normalizeDrillClassification()
        }
        .task {
            let previewScroll = UserDefaults.standard.string(forKey: "RUNALYST_PREVIEW_SCROLL") ?? ProcessInfo.processInfo.environment["RUNALYST_PREVIEW_SCROLL"]
            if previewScroll == "CHART" {
                try? await Task.sleep(nanoseconds: 600_000_000)
                withAnimation(.easeInOut(duration: 0.5)) {
                    scrollProxy.scrollTo("workoutRhythmChart", anchor: .top)
                }
            } else if previewScroll == "BOTTOM" {
                try? await Task.sleep(nanoseconds: 600_000_000)
                withAnimation(.easeInOut(duration: 0.5)) {
                    scrollProxy.scrollTo("secondaryBiomechanicsCard", anchor: .top)
                }
            } else if ProcessInfo.processInfo.environment["RUNALYST_PREVIEW_SCREEN"] == "AUTO_TOUR" {
                Task {
                    try? await Task.sleep(nanoseconds: 3_500_000_000)
                    withAnimation(.easeInOut(duration: 2.2)) {
                        scrollProxy.scrollTo("secondaryBiomechanicsCard", anchor: .top)
                    }
                }
            }
        }
        }
    }

    private func updateClassification(to newType: String, from oldType: String? = nil) {
        let previous = oldType ?? runRecord.detectedTypeRaw
        guard newType != previous else { return }
        let correction = TrainingCorrection(
            runRecordID: runRecord.id,
            originalLabel: previous,
            correctedLabel: newType,
            featureVector: [runRecord.workingAvgPace, runRecord.paceCV, runRecord.paceSlope, runRecord.percentZone4, runRecord.duration / 60.0]
        )
        modelContext.insert(correction)
        runRecord.detectedTypeRaw = newType
        runRecord.classificationProvenance = .userConfirmed
        runRecord.classificationConfidence = 1.0
        if !runRecord.framboiseTags.contains("userConfirmedClassification") {
            runRecord.framboiseTags.append("userConfirmedClassification")
        }
        try? modelContext.save()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
