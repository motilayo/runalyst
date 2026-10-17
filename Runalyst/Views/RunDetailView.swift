import SwiftUI
import UIKit
import SwiftData
import WorkoutKit

struct RunDetailView: View {
    @Bindable var runRecord: RunRecord
    @AppStorage("useMetricSystem") private var useMetricSystem: Bool = Locale.current.measurementSystem == .metric
    @Environment(\.modelContext) private var modelContext
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query private var existingRuns: [RunRecord]

    @State private var showRawMetrics: Bool = false
    @State private var isForceAnalyzing: Bool = false
    @State private var showingToggleInfo = false
    @State private var showingClassificationExplainer = false
    @State private var showingDrillExplainer = false
    @State private var isGeneratingInsight = false
    @State private var showingReadinessMathModal = false
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

    private var baselineRuns: [RunRecord] {
        guard let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: runRecord.date) else { return [] }
        return existingRuns.filter {
            $0.date < runRecord.date &&
            $0.date >= thirtyDaysAgo
        }
    }

    private var baselinePace: Double? {
        let runs = baselineRuns.filter { $0.workingAvgPace > 0 }
        guard !runs.isEmpty else { return nil }
        let totalDuration = runs.map(\.duration).reduce(0, +)
        guard totalDuration > 0 else {
            return runs.map(\.workingAvgPace).reduce(0, +) / Double(runs.count)
        }
        return runs.map { $0.workingAvgPace * $0.duration }.reduce(0, +) / totalDuration
    }

    private var baselineHR: Double? {
        let runs = baselineRuns.filter { $0.workingAvgHeartRate > 0 }
        guard !runs.isEmpty else { return nil }
        let totalDuration = runs.map(\.duration).reduce(0, +)
        guard totalDuration > 0 else {
            return Double(runs.map(\.workingAvgHeartRate).reduce(0, +)) / Double(runs.count)
        }
        return runs.map { Double($0.workingAvgHeartRate) * $0.duration }.reduce(0, +) / totalDuration
    }

    private var baselineCadence: Double? {
        let runs = baselineRuns.filter { $0.workingAvgCadence > 0 }
        guard !runs.isEmpty else { return nil }
        let totalDuration = runs.map(\.duration).reduce(0, +)
        guard totalDuration > 0 else {
            return Double(runs.map(\.workingAvgCadence).reduce(0, +)) / Double(runs.count)
        }
        return runs.map { Double($0.workingAvgCadence) * $0.duration }.reduce(0, +) / totalDuration
    }

    private var baselineOscillation: Double? {
        let runs = baselineRuns.compactMap { run -> (val: Double, dur: Double)? in
            guard let osc = run.workingAvgVerticalOscillation ?? run.rawAvgVerticalOscillation, osc > 0 else { return nil }
            return (osc, run.duration)
        }
        guard !runs.isEmpty else { return nil }
        let totalDuration = runs.map(\.dur).reduce(0, +)
        guard totalDuration > 0 else {
            return runs.map(\.val).reduce(0, +) / Double(runs.count)
        }
        return runs.map { $0.val * $0.dur }.reduce(0, +) / totalDuration
    }

    private var baselineStrideLength: Double? {
        let runs = baselineRuns.compactMap { run -> (val: Double, dur: Double)? in
            guard let stride = run.workingAvgStrideLength ?? run.rawAvgStrideLength, stride > 0 else { return nil }
            return (stride, run.duration)
        }
        guard !runs.isEmpty else { return nil }
        let totalDuration = runs.map(\.dur).reduce(0, +)
        guard totalDuration > 0 else {
            return runs.map(\.val).reduce(0, +) / Double(runs.count)
        }
        return runs.map { $0.val * $0.dur }.reduce(0, +) / totalDuration
    }

    private var baselineVerticalRatio: Double? {
        let runs = baselineRuns.compactMap { run -> (val: Double, dur: Double)? in
            guard let vr = run.verticalRatio, vr > 0 else { return nil }
            return (vr, run.duration)
        }
        guard !runs.isEmpty else { return nil }
        let totalDuration = runs.map(\.dur).reduce(0, +)
        guard totalDuration > 0 else {
            return runs.map(\.val).reduce(0, +) / Double(runs.count)
        }
        return runs.map { $0.val * $0.dur }.reduce(0, +) / totalDuration
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
        // A run is only a prescribed drill if it has a confirmed authentic drill name
        if runRecord.framboiseTags.contains("prescribedDrill") && prescribedDrillName == nil {
            runRecord.framboiseTags.removeAll { tag in
                tag == "prescribedDrill" || tag.hasPrefix("drill:")
            }
            try? modelContext.save()
        }
    }

    var deterministicRunAnalysisSummary: String? {
        guard runRecord.workingAvgCadence > 0 || runRecord.workingAvgHeartRate > 0 else { return nil }
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
            baselineStats: baselineCadence.map { (avgPace: runRecord.workingAvgPace, avgCadence: $0, avgHR: runRecord.workingAvgHeartRate) }
        )
        let grade = context.overallGradeReport.grade
        let floor = context.runnerProfile.heightAdjustedCadenceFloor
        let cad = context.workingCadence

        var components: [String] = []

        // 1. Cadence & Biomechanics
        let isRecovery = runRecord.detectedTypeRaw == "Recovery Run" || (runRecord.percentZone4 <= 0.02 && runRecord.workingAvgHeartRate > 0 && runRecord.workingAvgHeartRate <= 135)
        let effectiveFloor = isRecovery ? max(138, floor - 10) : floor
        if cad > 0 {
            if isRecovery {
                components.append("Turnover averaged \(cad) SPM with relaxed, low-impact stride mechanics, ideal for active recovery and flushing fatigue.")
            } else if cad >= effectiveFloor {
                components.append("Turnover averaged \(cad) SPM, safely above your \(floor) SPM mechanical floor. This cadence helps keep foot strikes underneath your hips and cushions joint impact\(isIndoor ? " on the treadmill belt" : "").")
            } else {
                components.append("Turnover averaged \(cad) SPM, dipping below your \(floor) SPM mechanical floor. Increasing step rate will shorten your stride and cushion joint landing\(isIndoor ? " on the moving belt" : "").")
            }
        }

        // 2. Cardiovascular Effort & Decoupling
        if context.workingHR > 0 {
            if isIndoor {
                components.append("Running indoors without convective airflow accelerates thermal buildup; your \(context.workingHR) BPM average reflects steady aerobic conditioning under indoor heat accumulation.")
            } else if context.hasCardiacDrift {
                components.append("Heart rate climbed +\(context.cardiacDriftMagnitudeBPM) BPM over the duration, reflecting cardiovascular drift and internal fatigue as the session progressed.")
            } else {
                components.append("Heart rate averaged \(context.workingHR) BPM with stable cardiovascular coupling, demonstrating controlled aerobic efficiency throughout.")
            }
        }

        // 3. Modality Execution & Grade
        if runRecord.evaluationModality == .intervals && hasIntervalWorkReps {
            let workSegments = runRecord.signature?.phaseSegments.filter { $0.kind == "work" && $0.avgPace > 0 } ?? []
            if !workSegments.isEmpty {
                let meanWorkPace = workSegments.reduce(0.0) { $0 + $1.avgPace } / Double(workSegments.count)
                let paceStr = PaceFormatter.formatPace(secondsPerKilometer: meanWorkPace)
                let avgWorkCad = Int(workSegments.reduce(0.0) { $0 + $1.avgCadence } / Double(workSegments.count))
                components.append("Active work reps hit \(paceStr) at \(avgWorkCad) SPM, earning a Grade \(grade) for pacing control.")
            }
        } else if !components.isEmpty {
            components.append("Overall execution earned a Grade \(grade).")
        }

        return components.joined(separator: " ")
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
                VStack(alignment: .leading, spacing: 8) {
                    if let insight = runRecord.insight, !insight.headline.isEmpty {
                        Text(insight.headline)
                            .font(.headline)
                            .foregroundColor(.primary)
                    }

                    if let groundedSummary = deterministicRunAnalysisSummary {
                        Text(groundedSummary)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
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
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(UIColor.separator).opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
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
    private var drillControl: some View {
        DrillLinkControlView(
            runRecord: runRecord,
            prescribedDrillName: prescribedDrillName,
            baselineCadence: baselineCadence
        )
    }

    @ViewBuilder
    private var workoutRhythmTimeline: some View {
        if !showRawMetrics, let segments = runRecord.signature?.phaseSegments, !segments.isEmpty {
            let isIntervalOrDrill: Bool = {
                if effectiveScorecardDrillId != nil { return true }
                if runRecord.evaluationModality == .intervals { return true }
                let type = runRecord.detectedTypeRaw
                return type == "Intervals" || type == "Fartlek" || type == "Pyramids" || type == "Hill Repeats"
            }()
            let isRecovery = runRecord.detectedTypeRaw == "Recovery Run" || (runRecord.percentZone4 <= 0.02 && runRecord.workingAvgHeartRate > 0 && runRecord.workingAvgHeartRate <= 135)
            let effectiveFloor = isRecovery ? min(runRecord.signature?.cadenceFloor ?? 150.0, 142.0) : (runRecord.signature?.cadenceFloor ?? 150.0)

            RunVarianceMapView(
                phaseSegments: segments,
                cadenceFloor: effectiveFloor,
                averageCadence: runRecord.workingAvgCadence,
                workoutDuration: runRecord.duration,
                isIntervalOrDrill: isIntervalOrDrill,
                workoutType: runRecord.detectedTypeRaw
            )
            .id("workoutRhythmChart")
        }
    }

    @ViewBuilder
    private var performanceAndAnalysisSection: some View {
        let isRecovery = runRecord.detectedTypeRaw == "Recovery Run" || (runRecord.percentZone4 <= 0.02 && runRecord.workingAvgHeartRate > 0 && runRecord.workingAvgHeartRate <= 135 && runRecord.duration >= 600)
        let resolvedDrillId: PreRunDrillId? = {
            if let drillId = effectiveScorecardDrillId { return drillId }
            if isRecovery { return .aerobicFlush }
            return nil
        }()

        if let drillId = resolvedDrillId {
            let scorecard = DrillExecutionScorecard(
                runRecord: runRecord,
                drillId: drillId,
                baselineCadence: baselineCadence,
                baselineOscillation: baselineOscillation,
                customTitle: isRecovery && prescribedDrillName == nil ? "Recovery Performance" : "Drill Performance"
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
            let scorecard = IntervalPerformanceCard(
                runRecord: runRecord,
                baselineCadence: baselineCadence
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
                // Formatted run date header
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(formattedRunDate)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.secondary)

                        Text(formattedRunTimeRange)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    let isIndoor = runRecord.isIndoor ?? false
                    HStack(spacing: 4) {
                        Image(systemName: isIndoor ? "figure.run.square.stack" : "figure.run")
                            .font(.caption2.bold())
                        Text(isIndoor ? "Indoor" : "Outdoor")
                            .font(.caption2.bold())
                        Image(systemName: "info.circle")
                            .font(.caption2)
                            .opacity(0.7)
                    }
                    .foregroundColor(isIndoor ? .purple : .blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .frame(minHeight: 44)
                    .background(isIndoor ? Color.purple.opacity(0.12) : Color.blue.opacity(0.12))
                    .clipShape(Capsule())
                    .contentShape(Rectangle())
                    .onTapGesture { showingEnvironmentInfo = true }
                    .accessibilityAddTraits(.isButton)
                    .alert(isIndoor ? "Indoor Session" : "Outdoor Session", isPresented: $showingEnvironmentInfo) {
                        Button("OK", role: .cancel) {}
                    } message: {
                        Text(environmentInfoMessage)
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
                if runRecord.needsInclineReview != true && (runRecord.detectedTypeRaw == "Mixed Effort (Review)" || (runRecord.classificationConfidence ?? 1.0) < 0.75) {
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
                                return probs.filter { $0.key != "Mixed Effort (Review)" }
                                    .sorted { $0.value > $1.value }
                                    .prefix(3)
                                    .map { (key: $0.key, value: $0.value) }
                            } else {
                                return [("Intervals", 0.45), ("Hill Repeats", 0.35), ("Tempo Run", 0.20)]
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

                // MARK: Run Classification & Drill
                VStack(alignment: .leading, spacing: 10) {
                    // Row 1: Classification
                    HStack {
                        HStack(spacing: 5) {
                            Text("Classification:")
                                .font(.subheadline.bold())
                                .foregroundColor(.primary)

                            Image(systemName: "info.circle")
                                .font(.caption)
                                .foregroundColor(.secondary.opacity(0.8))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showingClassificationExplainer = true
                        }

                        Spacer()

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
                        } label: {
                            HStack(spacing: 5) {
                                Text(runRecord.detectedTypeRaw.isEmpty ? runRecord.normalizedClassification : runRecord.detectedTypeRaw)
                                    .font(.subheadline.bold())
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2.bold())
                            }
                            .foregroundColor(runRecord.detectedTypeRaw == "Mixed Effort (Review)" ? .orange : Color(red: 0.05, green: 0.45, blue: 0.5))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                (runRecord.detectedTypeRaw == "Mixed Effort (Review)" ? Color.orange : Color(red: 0.05, green: 0.45, blue: 0.5))
                                    .opacity(0.12)
                            )
                            .clipShape(Capsule())
                        }
                    }

                    // Row 2: Drill
                    HStack {
                        HStack(spacing: 5) {
                            Text("Drill:")
                                .font(.subheadline.bold())
                                .foregroundColor(.primary)

                            Image(systemName: "info.circle")
                                .font(.caption)
                                .foregroundColor(.secondary.opacity(0.8))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showingDrillExplainer = true
                        }

                        Spacer()

                        drillControl
                    }
                }
                .padding(.horizontal)
                .sheet(isPresented: $showingClassificationExplainer) {
                    RunClassificationExplainerSheet()
                }
                .alert("Drill Tracking", isPresented: $showingDrillExplainer) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text("Link this workout to a drill (like Cadence Pyramids, Strides, or Zone 2 Run) to track your form adherence against coaching targets in Drill Performance.")
                }

                // MARK: Scorecard & AI Run Analysis
                performanceAndAnalysisSection

                // MARK: Data Toggle
                HStack(spacing: 8) {
                    Picker("Metrics Type", selection: $showRawMetrics) {
                        Text("Working Stats").tag(false)
                        Text("Workout Stats").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: showRawMetrics) { _, _ in
                        UISelectionFeedbackGenerator().selectionChanged()
                    }

                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showingToggleInfo = true
                    }) {
                        Image(systemName: "info.circle")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                }
                .padding(.horizontal)
                .sheet(isPresented: $showingToggleInfo) {
                    let explainer = MetricDetailExplainer.explainer(for: showRawMetrics ? "Workout Stats" : "Working Stats", isWorkoutStats: showRawMetrics)
                    MetricExplainerSheet(
                        explainer: explainer,
                        mode: showRawMetrics ? "Workout Stats" : "Working Stats"
                    )
                }

                // MARK: Metrics Grid
                let columns: [GridItem] = {
                    if horizontalSizeClass == .regular {
                        return [
                            GridItem(.flexible(), spacing: 16),
                            GridItem(.flexible(), spacing: 16),
                            GridItem(.flexible(), spacing: 16),
                            GridItem(.flexible(), spacing: 16)
                        ]
                    } else if verticalSizeClass == .regular {
                        return [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
                    } else {
                        return [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
                    }
                }()

                LazyVGrid(columns: columns, spacing: 16) {
                    let activeDistanceMeters = showRawMetrics ? runRecord.totalDistanceMeters : runRecord.effectiveWorkingDistanceMeters
                    let distanceConverted = useMetricSystem ? (activeDistanceMeters / 1000.0) : (activeDistanceMeters / 1609.344)
                    let distanceUnit = useMetricSystem ? "km" : "mi"
                    StatBox(title: "Distance", value: String(format: "%.2f", distanceConverted), unit: distanceUnit, isWorkoutStats: showRawMetrics)

                    let activeDuration = showRawMetrics ? runRecord.duration : runRecord.effectiveWorkingDurationSeconds
                    let minutes = Int(activeDuration) / 60
                    let seconds = Int(activeDuration) % 60
                    StatBox(title: showRawMetrics ? "Total Time" : "Moving Time", value: String(format: "%d:%02d", minutes, seconds), unit: "min", isWorkoutStats: showRawMetrics)

                    let currentPace: Double = {
                        if showRawMetrics {
                            let totalKm = runRecord.totalDistanceMeters / 1000.0
                            return totalKm > 0 ? (runRecord.duration / totalKm) : runRecord.rawAvgPace
                        } else {
                            let workingKm = runRecord.effectiveWorkingDistanceMeters / 1000.0
                            return workingKm > 0 ? (runRecord.effectiveWorkingDurationSeconds / workingKm) : runRecord.workingAvgPace
                        }
                    }()
                    let currentHR = showRawMetrics ? runRecord.rawAvgHeartRate : runRecord.workingAvgHeartRate
                    let currentCadence = showRawMetrics ? runRecord.rawAvgCadence : runRecord.workingAvgCadence

                    let paceValue = PaceFormatter.formatPace(secondsPerKilometer: currentPace)
                    let paceCurrent = currentPace > 0 ? currentPace : nil
                    let paceBaseline = (showRawMetrics || currentPace <= 0) ? nil : baselinePace
                    StatBox(title: "Avg Pace", value: paceValue, unit: "", currentValue: paceCurrent, baselineValue: paceBaseline, polarity: .lowerIsBetter, isWorkoutStats: showRawMetrics)

                    let hrValue = currentHR > 0 ? "\(Int(round(currentHR)))" : "--"
                    let hrUnit = currentHR > 0 ? "BPM" : ""
                    let hrCurrent = currentHR > 0 ? currentHR : nil
                    let hrBaseline = (showRawMetrics || currentHR <= 0) ? nil : baselineHR
                    StatBox(title: "Avg HR", value: hrValue, unit: hrUnit, currentValue: hrCurrent, baselineValue: hrBaseline, polarity: .lowerIsBetter, isWorkoutStats: showRawMetrics)

                    let cadValue = currentCadence > 0 ? "\(Int(currentCadence))" : "--"
                    let cadUnit = currentCadence > 0 ? "SPM" : ""
                    let cadCurrent = currentCadence > 0 ? currentCadence : nil
                    let cadBaseline = (showRawMetrics || currentCadence <= 0) ? nil : baselineCadence
                    StatBox(title: "Avg Cadence", value: cadValue, unit: cadUnit, currentValue: cadCurrent, baselineValue: cadBaseline, polarity: .higherIsBetter, isWorkoutStats: showRawMetrics)

                    let currentStride = showRawMetrics ? (runRecord.rawAvgStrideLength ?? runRecord.workingAvgStrideLength) : (runRecord.workingAvgStrideLength ?? runRecord.rawAvgStrideLength)
                    let currentStrideConverted: Double? = {
                        guard let stride = currentStride, stride > 0 else { return nil }
                        return useMetricSystem ? stride : (stride * 3.28084)
                    }()
                    let baselineStrideConverted: Double? = {
                        guard let base = baselineStrideLength, base > 0 else { return nil }
                        return useMetricSystem ? base : (base * 3.28084)
                    }()
                    if currentStride != nil {
                        StatBox(
                            title: "Avg Stride",
                            value: currentStrideConverted.map { String(format: "%.2f", $0) } ?? "--",
                            unit: currentStride != nil ? (useMetricSystem ? "m" : "ft") : "",
                            currentValue: currentStrideConverted,
                            baselineValue: showRawMetrics ? nil : baselineStrideConverted,
                            polarity: .higherIsBetter,
                            isWorkoutStats: showRawMetrics
                        )
                    }

                    let currentOscillation = showRawMetrics ? (runRecord.rawAvgVerticalOscillation ?? runRecord.workingAvgVerticalOscillation) : (runRecord.workingAvgVerticalOscillation ?? runRecord.rawAvgVerticalOscillation)
                    if currentOscillation != nil {
                        StatBox(
                            title: "Bounce",
                            value: currentOscillation.map { String(format: "%.1f", $0) } ?? "--",
                            unit: currentOscillation != nil ? "cm" : "",
                            currentValue: currentOscillation,
                            baselineValue: showRawMetrics ? nil : baselineOscillation,
                            polarity: .lowerIsBetter,
                            isWorkoutStats: showRawMetrics
                        )
                    }

                    let currentVR = runRecord.verticalRatio
                    if currentVR != nil {
                        StatBox(
                            title: "Bounce Ratio",
                            value: currentVR.map { String(format: "%.1f", $0) } ?? "--",
                            unit: currentVR != nil ? "%" : "",
                            currentValue: currentVR,
                            baselineValue: showRawMetrics ? nil : baselineVerticalRatio,
                            polarity: .lowerIsBetter,
                            isWorkoutStats: showRawMetrics
                        )
                    }
                }
                .padding(.horizontal)
                .id("metricsGrid")

                // MARK: Drills Section (Only on runs <= 7 days old)
                let isOlderThan7Days = (Calendar.current.dateComponents([.day], from: runRecord.date, to: Date()).day ?? 0) > 7
                let hasBiometrics = runRecord.workingAvgCadence > 0 || runRecord.workingAvgHeartRate > 0

                if !isOlderThan7Days {
                    if let insight = runRecord.insight {
                        if let drills = insight.drillRecommendations, !drills.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Recommended Drills")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    NavigationLink(destination: DrillsLibraryView()) {
                                        HStack(spacing: 2) {
                                            Text("All Drills")
                                            Image(systemName: "chevron.right")
                                        }
                                        .font(.caption.bold())
                                        .foregroundColor(.accentColor)
                                    }
                                }
                                .padding(.horizontal)

                                DrillDeckView(drills: drills)
                            }
                            .padding(.top, 12)
                        }
                    } else if hasBiometrics {
                        AnimatedLoadingView(
                            text: "Generating Coaching Insight...",
                            isHorizontal: false,
                            imageSize: 60,
                            textFont: .subheadline,
                            textColor: .secondary,
                            iconColor: .purple,
                            spacing: 20
                        )
                        .multilineTextAlignment(.center)
                        .frame(minHeight: 1)
                        .padding(32)
                    }
                }
            }
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
                                let intervalSummary = DrillIntervalEvaluator.evaluate(
                                    workout: workout,
                                    buckets: buckets,
                                    drillId: drillId,
                                    baselineCadence: thirtyDayCadence,
                                    workoutDuration: runRecord.duration,
                                    oscDelta: oscDelta
                                )
                                runRecord.framboiseTags.removeAll {
                                    $0.hasPrefix("drillIntervals:") ||
                                    $0.hasPrefix("drillWorkCadence:") ||
                                    $0.hasPrefix("drillRecCadence:") ||
                                    $0.hasPrefix("drillReps:")
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
                Button {
                    showingAnalystChat = true
                } label: {
                    Label("Ask Coach", systemImage: "bubble.left.and.text.bubble.right.fill")
                        .foregroundColor(.purple)
                }
            }
        }
        .sheet(isPresented: $showingAnalystChat) {
            AnalystChatView(runRecord: runRecord)
        }
        .sheet(isPresented: $showingReadinessMathModal) {
            ReadinessMathModal()
        }
        .onAppear {
            normalizeDrillClassification()
        }
        .task {
            let previewScroll = ProcessInfo.processInfo.environment["RUNALYST_PREVIEW_SCROLL"]
            if previewScroll == "CHART" {
                try? await Task.sleep(nanoseconds: 600_000_000)
                withAnimation(.easeInOut(duration: 0.5)) {
                    scrollProxy.scrollTo("workoutRhythmChart", anchor: .top)
                }
            } else if previewScroll == "BOTTOM" {
                try? await Task.sleep(nanoseconds: 600_000_000)
                withAnimation(.easeInOut(duration: 0.5)) {
                    scrollProxy.scrollTo("aiAnalysisCard", anchor: .top)
                }
            } else if ProcessInfo.processInfo.environment["RUNALYST_PREVIEW_SCREEN"] == "AUTO_TOUR" {
                Task {
                    try? await Task.sleep(nanoseconds: 3_500_000_000)
                    withAnimation(.easeInOut(duration: 2.2)) {
                        scrollProxy.scrollTo("metricsGrid", anchor: .top)
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
        try? modelContext.save()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
