import SwiftUI
import UIKit
import SwiftData
import WorkoutKit
import RunalystCore

struct RunDetailView: View {
    @Bindable var runRecord: RunRecord
    @AppStorage("useMetricSystem") var useMetricSystem: Bool = Locale.current.measurementSystem == .metric
    @Environment(\.modelContext) var modelContext
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Query var existingRuns: [RunRecord]

    @State var isForceAnalyzing: Bool = false
    @State var showingBiomechanicsExplainer = false
    @State var showingClassificationExplainer = false
    @State var showingDrillExplainer = false
    @State var isGeneratingInsight = false
    @State var showingEnvironmentInfo = false

    @ViewBuilder
    var workoutRhythmTimeline: some View {
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

                    // Compact horizontal tags strip: hide redundant classification pill when a specific drill is linked
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            environmentPill
                            if prescribedDrillName == nil {
                                classificationPill
                            }
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
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Run Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.regularMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
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
}
