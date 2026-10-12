import SwiftUI
import SwiftData
import HealthKit
import OSLog

private let logger = Logger(subsystem: "com.runalyzer.Runalyzer", category: "Sync")

/// The root view of the application that manages the onboarding state and primary HealthKit synchronization loop.
///
/// `ContentView` determines whether to show `OnboardingView` or `DashboardView`. It also handles fetching new
/// running workouts from HealthKit, persisting them to SwiftData, and lazily invoking the background AI analysis.
struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @StateObject private var healthKitManager = HealthKitManager.shared

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RunRecord.date, order: .reverse) private var existingRuns: [RunRecord]

    @State private var isSyncing = false
    @State private var syncProgress: (current: Int, total: Int)?
    @State private var syncStatusMessage: String?
    @State private var syncError: String?
    @State private var showError = false

    private var previewScreen: String? {
        ProcessInfo.processInfo.environment["RUNALYST_PREVIEW_SCREEN"]
    }

    @ViewBuilder
    private var drillReadoutPreview: some View {
        let template = DrillTemplate.template(for: .cadencePyramids)
        let baseCadence = 165
        let targetCadence: String? = template.calculateTargetCadence(baseCadence)
        let drill = PreRunDrill(
            id: .cadencePyramids,
            previousCadence: baseCadence,
            targetCadence: targetCadence,
            duration: .tenMinutes,
            hapticMode: .on
        )
        let readout = DrillReadout.readout(
            for: .cadencePyramids,
            customTitle: template.title,
            targetCadence: targetCadence,
            previousCadence: baseCadence,
            customDuration: .tenMinutes
        )
        let plan = drill.buildWorkoutPlan()
        let dto = DrillPrescriptionDTO(
            title: template.title,
            preRunDrillId: PreRunDrillId.cadencePyramids.rawValue,
            purpose: template.defaultPurpose,
            targetCadence: targetCadence,
            previousCadence: baseCadence,
            durationMinutes: DrillDuration.tenMinutes.rawValue,
            hapticMode: HapticFeedbackMode.on.rawValue
        )

        DrillInterstitialReadoutView(
            readout: readout,
            workoutPlan: plan,
            prescriptionDTO: dto,
            onCommitToWatch: nil
        )
    }

    var body: some View {
        Group {
            if let previewScreen {
                switch previewScreen {
                case "RUN_DETAIL":
                    if let run = existingRuns.first {
                        NavigationStack {
                            RunDetailView(runRecord: run)
                        }
                    } else {
                        DashboardView(onSync: nil)
                    }
                case "DRILL_CARD":
                    if let run = existingRuns.first, let drills = run.insight?.drillRecommendations, !drills.isEmpty {
                        NavigationStack {
                            ScrollView {
                                DrillDeckView(drills: drills)
                                    .padding(.top, 20)
                            }
                            .navigationTitle("Recommended Drill")
                        }
                        .onAppear {
                            if MacroProfile.load() == nil {
                                let profile = MacroProfile(
                                    acwr: 1.02,
                                    acuteLoad: 310,
                                    chronicWeeklyLoad: 304,
                                    baselinePace: 330,
                                    baselineHR: 148,
                                    baselineCadence: 168,
                                    baselineEfficiencyFactor: 1.45,
                                    updatedAt: Date()
                                )
                                profile.save()
                            }
                        }
                    } else {
                        DashboardView(onSync: nil)
                    }
                case "DRILLS":
                    NavigationStack {
                        DrillsLibraryView()
                    }
                case "DRILL_READOUT":
                    drillReadoutPreview
                case "BIOMECHANICS":
                    NavigationStack {
                        OverstrideBiomechanicsSheet()
                    }
                case "SETTINGS":
                    NavigationStack {
                        SettingsView(onForceSync: nil)
                    }
                case "PROGRESSION":
                    NavigationStack {
                        ScrollView {
                            ProgressionChartView(allRuns: existingRuns, defaultHorizon: .allTime)
                                .padding()
                        }
                        .navigationTitle("Cadence Progression")
                    }
                case "ANALYST", "ANALYST_ACTIVE", "ANALYST_READ", "ANALYST_EFFORT", "ANALYST_IMPROVE", "ANALYST_MULTI", "ANALYST_ARM_DRIVE", "ANALYST_DEGRADATION", "ANALYST_WEAKNESS", "ANALYST_SPLIT_GRADE":
                    if let run = existingRuns.first {
                        AnalystChatView(runRecord: run)
                    } else {
                        DashboardView(onSync: nil)
                    }
                case "READINESS":
                    ReadinessMathModal(acuteLoad: 168.5, chronicWeeklyLoad: 165.2, acwr: 1.02)
                case "DETAIL":
                    if let run = existingRuns.first {
                        NavigationStack {
                            RunDetailView(runRecord: run)
                        }
                    } else {
                        DashboardView(onSync: nil)
                    }
                case "DRILL_EXPLAINER":
                    let readiness = ReadinessEvaluator.assess(runRecords: existingRuns)
                    let dto = DrillPrescriptionDTO(
                        title: "Cadence Pyramids",
                        preRunDrillId: PreRunDrillId.cadencePyramids.rawValue,
                        purpose: "This pattern sharpens your cadence control and supports your aerobic foundation.",
                        targetCadence: "160-166 SPM",
                        previousCadence: 156,
                        durationMinutes: 10
                    )
                    let item = ActiveDrillReadoutItem.adaptive(
                        dto: dto,
                        readiness: readiness,
                        customCoachingTip: "Focus on steady, measured movement and release tension through your shoulders."
                    )
                    DrillInterstitialReadoutView(
                        readout: item.readout,
                        workoutPlan: item.plan,
                        prescriptionDTO: item.dto
                    )
                case "DRILL_EXPLAINER_ADAPTED":
                    let assessment = ReadinessAssessment(
                        state: .acuteFatigue,
                        triggers: [.consecutiveHardDays],
                        acuteLoad: 168.0,
                        chronicWeeklyLoad: 145.0,
                        acwr: 1.16,
                        mileageDropFraction: nil
                    )
                    let dto = DrillPrescriptionDTO(
                        title: "Cadence Pyramids",
                        preRunDrillId: PreRunDrillId.cadencePyramids.rawValue,
                        purpose: "This pattern sharpens your cadence control and supports your aerobic foundation.",
                        targetCadence: "160-166 SPM",
                        previousCadence: 156,
                        durationMinutes: 10
                    )
                    let item = ActiveDrillReadoutItem.adaptive(
                        dto: dto,
                        readiness: assessment,
                        customCoachingTip: "Focus on steady, measured movement and release tension through your shoulders."
                    )
                    DrillInterstitialReadoutView(
                        readout: item.readout,
                        workoutPlan: item.plan,
                        prescriptionDTO: item.dto
                    )
                case "VARIANCE_MAP":
                    let sampleSegments: [PhaseSegment] = [
                        PhaseSegment(startSeconds: 0, endSeconds: 300, kind: "steady", avgPace: 330, avgCadence: 160, avgHR: 138),
                        PhaseSegment(startSeconds: 300, endSeconds: 600, kind: "work", avgPace: 270, avgCadence: 174, avgHR: 168),
                        PhaseSegment(startSeconds: 600, endSeconds: 780, kind: "recovery", avgPace: 360, avgCadence: 154, avgHR: 142),
                        PhaseSegment(startSeconds: 780, endSeconds: 1080, kind: "work", avgPace: 265, avgCadence: 176, avgHR: 172),
                        PhaseSegment(startSeconds: 1080, endSeconds: 1260, kind: "recovery", avgPace: 365, avgCadence: 152, avgHR: 145),
                        PhaseSegment(startSeconds: 1260, endSeconds: 1560, kind: "work", avgPace: 260, avgCadence: 178, avgHR: 175),
                        PhaseSegment(startSeconds: 1560, endSeconds: 1800, kind: "steady", avgPace: 340, avgCadence: 158, avgHR: 140)
                    ]
                    let run = existingRuns.first
                    let segments = run?.signature?.phaseSegments ?? sampleSegments
                    NavigationStack {
                        ScrollView {
                            RunVarianceMapView(
                                phaseSegments: segments.isEmpty ? sampleSegments : segments,
                                cadenceFloor: run?.signature?.cadenceFloor ?? 152.0,
                                averageCadence: run?.workingAvgCadence ?? 164.0,
                                workoutDuration: run?.duration ?? 1800.0
                            )
                            .padding()
                        }
                        .navigationTitle("Workout Rhythm")
                    }
                case "AUTO_TOUR":
                    AppStoreTourView(existingRuns: existingRuns)
                case "DASHBOARD":
                    DashboardView(onSync: nil)
                default:
                    DashboardView(onSync: nil)
                }
            } else if hasCompletedOnboarding {
                DashboardView(onSync: { force in
                    await syncData(force: force)
                })
                .task {
                    guard NSClassFromString("XCTestCase") == nil else { return }
                    Task {
                        await syncData()
                    }

                    healthKitManager.onWorkoutsUpdated = {
                        Task {
                            await syncData()
                        }
                    }
                    healthKitManager.startObservingWorkouts()
                }
                .alert("Sync Error", isPresented: $showError) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(syncError ?? "An unknown error occurred while syncing.")
                }
                .safeAreaInset(edge: VerticalEdge.bottom, spacing: 80) {
                    if isSyncing {
                        if let progress = syncProgress, progress.total > 5 {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Image(systemName: "figure.run")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.accentColor)
                                        .symbolEffect(.bounce.up, options: .repeating)

                                    Text(syncStatusMessage ?? "Calibrating History")
                                        .font(.caption.bold())
                                        .foregroundColor(.primary)

                                    Spacer(minLength: 4)

                                    Text("\(progress.current)/\(progress.total)")
                                        .font(.caption.bold())
                                        .monospacedDigit()
                                        .foregroundColor(.secondary)
                                }

                                ProgressView(value: Double(progress.current), total: Double(max(1, progress.total)))
                                    .tint(.accentColor)

                                Text("Keep Runalyst open to complete baseline calibration")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(.regularMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        } else {
                            AnimatedLoadingView(
                                text: syncStatusMessage ?? "Syncing Health Data & AI...",
                                isHorizontal: true,
                                imageSize: 16,
                                textFont: .caption,
                                spacing: 8
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(.regularMaterial)
                            .clipShape(Capsule())
                            .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
                            .padding(.bottom, 20)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isSyncing)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: syncProgress?.current)
            } else {
                OnboardingView(
                    isSyncing: isSyncing,
                    syncProgress: syncProgress,
                    syncStatusMessage: syncStatusMessage,
                    onStartSync: {
                        Task {
                            await syncData()
                        }
                    },
                    onComplete: {
                        hasCompletedOnboarding = true
                    }
                )
            }
        }
        .task {
            if ProcessInfo.processInfo.environment["RUNALYST_FORCE_SEED"] == "true" {
                logger.info("Force-seeding 38 mock runs (clearing previous)...")
                for run in existingRuns {
                    modelContext.delete(run)
                }
                try? modelContext.save()
                HealthKitSeeder.shared.seedDirectToSwiftData(context: modelContext)
            } else if existingRuns.count < 30 && previewScreen != nil {
                logger.info("Auto-seeding 38 mock runs for preview/video recording...")
                HealthKitSeeder.shared.seedDirectToSwiftData(context: modelContext)
            }
        }
    }

    @MainActor
    private func syncData(force: Bool = false) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer {
            isSyncing = false
            syncProgress = nil
            syncStatusMessage = nil
            UIApplication.shared.isIdleTimerDisabled = false
        }

        do {
            if force {
                // Clear the local workout table completely
                let allRuns = try modelContext.fetch(FetchDescriptor<RunRecord>())
                for run in allRuns {
                    modelContext.delete(run)
                }
                try modelContext.save()
            }

            // 1. Fetch recent workouts from HealthKit
            syncStatusMessage = "Connecting to Apple Health..."
            let workouts = try await healthKitManager.fetchRunningWorkouts(filter: .allTime)

            // 2. Cross-reference with SwiftData to find new workouts
            let currentExistingRuns = try modelContext.fetch(FetchDescriptor<RunRecord>())
            let existingWorkoutIDs = Set(currentExistingRuns.map(\.hkWorkoutID))
            let newWorkouts = workouts.filter { workout in
                !existingWorkoutIDs.contains(workout.uuid)
            }

            // Check for post-workout distance calibration mutations on existing indoor runs
            let workoutDict = Dictionary(uniqueKeysWithValues: workouts.map { ($0.uuid, $0) })
            var didResolveLegacy = false
            for existingRun in currentExistingRuns {
                if existingRun.isIndoor == nil {
                    existingRun.isIndoor = (existingRun.dataSourceRaw == "gymkit") ? true : false
                    didResolveLegacy = true
                }
                if existingRun.detectedTypeRaw.isEmpty {
                    existingRun.detectedTypeRaw = "Steady Effort"
                    didResolveLegacy = true
                }
            }
            if didResolveLegacy {
                try? modelContext.save()
            }

            for existingRun in currentExistingRuns where (existingRun.isIndoor == true) {
                if let authenticWorkout = workoutDict[existingRun.hkWorkoutID] {
                    let hkDistance = authenticWorkout.totalDistance?.doubleValue(for: .meter()) ?? 0
                    if abs(hkDistance - existingRun.totalDistanceMeters) > 5.0 || abs(authenticWorkout.duration - existingRun.duration) > 2.0 {
                        logger.info("Detected post-workout treadmill calibration mutation on \(existingRun.date). Recalculating sliding windows.")
                        try? await healthKitManager.refreshWorkoutMetrics(for: existingRun, in: modelContext)
                    }
                }
            }

            let engine = FramboiseEngine()

            var priorRunData: [HealthKitManager.RunBaselineData] = currentExistingRuns
                .filter { !$0.isDeleted && $0.modelContext != nil }
                .map {
                    HealthKitManager.RunBaselineData(
                        date: $0.date,
                        pace: $0.workingAvgPace > 0 ? $0.workingAvgPace : $0.rawAvgPace,
                        hr: $0.workingAvgHeartRate > 0 ? $0.workingAvgHeartRate : $0.rawAvgHeartRate,
                        cadence: $0.workingAvgCadence > 0 ? $0.workingAvgCadence : $0.rawAvgCadence,
                        duration: $0.duration,
                        isPrescribedDrill: $0.framboiseTags.contains("prescribedDrill")
                    )
                }

            // 3. Extract and insert new runs incrementally (newest first)
            let sortedNewWorkouts = newWorkouts.sorted { $0.startDate > $1.startDate }
            if !sortedNewWorkouts.isEmpty {
                logger.info("Found \(sortedNewWorkouts.count) new workouts to sync.")
                if sortedNewWorkouts.count > 5 {
                    UIApplication.shared.isIdleTimerDisabled = true
                }
                syncStatusMessage = "Calibrating Running History"
                syncProgress = (0, sortedNewWorkouts.count)

                for (index, workout) in sortedNewWorkouts.enumerated() {
                    if let dto = try? await healthKitManager.extractRunRecord(from: workout, engine: engine, priorRuns: priorRunData) {
                        let newRun = RunRecord(
                            hkWorkoutID: dto.hkWorkoutID,
                            date: dto.date,
                            totalDistanceMeters: dto.totalDistanceMeters,
                            duration: dto.duration,
                            rawAvgPace: dto.rawAvgPace,
                            rawAvgHeartRate: dto.rawAvgHeartRate,
                            rawAvgCadence: dto.rawAvgCadence,
                            workingAvgPace: dto.workingAvgPace,
                            workingAvgCadence: dto.workingAvgCadence,
                            workingAvgHeartRate: dto.workingAvgHeartRate,
                            workingAvgVerticalOscillation: dto.workingAvgVerticalOscillation,
                            rawAvgVerticalOscillation: dto.rawAvgVerticalOscillation,
                            rawAvgStrideLength: dto.rawAvgStrideLength,
                            workingAvgStrideLength: dto.workingAvgStrideLength,
                            workingDistanceMeters: dto.workingDistanceMeters,
                            workingDurationSeconds: dto.workingDurationSeconds,
                            isIndoor: dto.isIndoor ?? false,
                            paceCV: dto.paceCV,
                            paceSlope: dto.paceSlope,
                            percentZone4: dto.percentZone4,
                            detectedTypeRaw: dto.detectedTypeRaw.isEmpty ? "Steady Effort" : dto.detectedTypeRaw,
                            framboiseTags: dto.framboiseTags,
                            dataSourceRaw: dto.dataSourceRaw,
                            classificationConfidence: dto.classificationConfidence,
                            classificationProbabilitiesData: dto.classificationProbabilitiesData,
                            hrCV: dto.hrCV,
                            cadenceSlope: dto.cadenceSlope,
                            needsInclineReview: dto.needsInclineReview,
                            runSignatureData: dto.runSignatureData
                        )
                        modelContext.insert(newRun)

                        if dto.framboiseTags.contains("prescribedDrill") {
                            // 1. Auto-complete matching uncompleted DrillRecommendations
                            let openDrillsDescriptor = FetchDescriptor<DrillRecommendation>(
                                predicate: #Predicate<DrillRecommendation> { drill in
                                    !drill.isCompleted
                                }
                            )
                            if let openDrills = try? modelContext.fetch(openDrillsDescriptor) {
                                for drill in openDrills {
                                    let matchesId = drill.preRunDrillId.map { dto.framboiseTags.contains($0) } ?? false
                                    let matchesTag = dto.framboiseTags.contains("drill:\(drill.drillTitle)")
                                    let matchesTitle = drill.drillTitle.localizedCaseInsensitiveCompare(dto.detectedTypeRaw) == .orderedSame
                                    if matchesTitle || matchesId || matchesTag {
                                        drill.isCompleted = true
                                        logger.info("Auto-completed prescribed drill recommendation: \(drill.drillTitle)")
                                    }
                                }
                            }

                            // 2. Generate ground-truth TrainingCorrection for CoreML personalization
                            let effectivePace = newRun.workingAvgPace > 0 ? newRun.workingAvgPace : newRun.rawAvgPace
                            let correction = TrainingCorrection(
                                runRecordID: newRun.id,
                                originalLabel: "Prescribed Drill",
                                correctedLabel: dto.detectedTypeRaw,
                                featureVector: [
                                    effectivePace,
                                    newRun.paceCV,
                                    newRun.paceSlope,
                                    newRun.percentZone4,
                                    newRun.duration / 60.0
                                ],
                                createdAt: dto.date,
                                isProcessed: false
                            )
                            modelContext.insert(correction)
                            logger.info("Inserted ground-truth TrainingCorrection for prescribed drill: \(dto.detectedTypeRaw)")
                        }

                        if (index + 1) % 25 == 0 || (index + 1) == sortedNewWorkouts.count {
                            try? modelContext.save()
                        }
                        priorRunData.append(
                            HealthKitManager.RunBaselineData(
                                date: dto.date,
                                pace: dto.workingAvgPace > 0 ? dto.workingAvgPace : dto.rawAvgPace,
                                hr: dto.workingAvgHeartRate > 0 ? dto.workingAvgHeartRate : dto.rawAvgHeartRate,
                                cadence: dto.workingAvgCadence > 0 ? dto.workingAvgCadence : dto.rawAvgCadence,
                                duration: dto.duration,
                                isPrescribedDrill: dto.framboiseTags.contains("prescribedDrill")
                            )
                        )
                        logger.info("Persisted run \(index + 1)/\(sortedNewWorkouts.count) (\(dto.date))")
                    }

                    syncProgress = (index + 1, sortedNewWorkouts.count)

                    // Yield briefly to keep the main runloop and UI responsive
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
            }

            // 4. Preload AI analysis ONLY for runs within the last 7 days or past 5 runs
            let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            let descriptor = FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])

            if let allRuns = try? modelContext.fetch(descriptor) {
                let runsToPreload = allRuns.prefix(5).filter { run in
                    run.insight == nil &&
                    (run.workingAvgCadence > 0 || run.workingAvgHeartRate > 0) &&
                    (run.date >= sevenDaysAgo || (allRuns.firstIndex(where: { $0.id == run.id }) ?? 5) < 5)
                }
                let container = modelContext.container

                if !runsToPreload.isEmpty {
                    syncStatusMessage = "Generating AI Coaching..."
                    syncProgress = nil
                }

                for run in runsToPreload where run.insight == nil {
                    let runId = run.persistentModelID
                    if #available(iOS 26.0, *) {
                        logger.info("Generating AI insight sequentially for run \(run.date)")
                        let analyzer = RunAnalyzerActor(modelContainer: container)
                        await analyzer.generateAnalysis(for: runId)
                    }

                    // Throttle sequentially to avoid on-device model rate limits and thermal overload
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                }

                // 5. Update MacroProfile (compute once, persist locally for RAG Analyst Chat)
                let readiness = ReadinessEvaluator.assess(runRecords: allRuns)
                let recentValidPaces = allRuns.prefix(15).map(\.workingAvgPace).filter { $0 > 0 }
                let basePace = recentValidPaces.isEmpty ? nil : (recentValidPaces.reduce(0, +) / Double(recentValidPaces.count))

                let recentValidHRs = allRuns.prefix(15).map(\.workingAvgHeartRate).filter { $0 > 0 }
                let baseHR = recentValidHRs.isEmpty ? nil : (recentValidHRs.reduce(0, +) / Double(recentValidHRs.count))

                let recentValidCads = allRuns.prefix(15).map(\.workingAvgCadence).filter { $0 > 0 }
                let baseCad = recentValidCads.isEmpty ? nil : (recentValidCads.reduce(0, +) / Double(recentValidCads.count))

                let validEFs = allRuns.prefix(15).compactMap(\.efficiencyFactor)
                let baseEF = validEFs.isEmpty ? nil : (validEFs.reduce(0, +) / Double(validEFs.count))

                let profile = MacroProfile(
                    acwr: readiness.acwr,
                    acuteLoad: readiness.acuteLoad,
                    chronicWeeklyLoad: readiness.chronicWeeklyLoad,
                    baselinePace: basePace,
                    baselineHR: baseHR,
                    baselineCadence: baseCad,
                    baselineEfficiencyFactor: baseEF,
                    updatedAt: Date()
                )
                profile.save()
            }

        } catch is CancellationError {
            logger.info("Sync data task cancelled.")
        } catch {
            logger.error("Failed to sync data: \(error.localizedDescription)")
            await MainActor.run {
                self.syncError = error.localizedDescription
                self.showError = true
            }
        }
    }
}

struct AppStoreTourView: View {
    @Query(sort: \RunRecord.date, order: .reverse) private var queryRuns: [RunRecord]
    var existingRuns: [RunRecord]
    @State private var tourStep: Int = 0
    @State private var isPulsing: Bool = false

    private var allRuns: [RunRecord] {
        queryRuns.isEmpty ? existingRuns : queryRuns
    }

    private var targetRun: RunRecord? {
        allRuns.first { $0.workingAvgCadence > 0 } ?? allRuns.first
    }

    private var baseCadence: Int? {
        if let target = targetRun, target.workingAvgCadence > 0 {
            return Int(target.workingAvgCadence)
        }
        return 165
    }

    var body: some View {
        ZStack {
            switch tourStep {
            case 0:
                DashboardView(onSync: nil)
                    .transition(.opacity)
            case 1:
                if let targetRun {
                    NavigationStack {
                        RunDetailView(runRecord: targetRun)
                    }
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                } else {
                    DashboardView(onSync: nil)
                }
            case 2:
                NavigationStack {
                    DrillsLibraryView()
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            case 3:
                drillReadoutView
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            case 4:
                NavigationStack {
                    ScrollView {
                        ProgressionChartView(allRuns: allRuns, defaultHorizon: .allTime)
                            .padding()
                    }
                    .navigationTitle("Cadence Progression")
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            default:
                DashboardView(onSync: nil)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Color.blue.opacity(isPulsing ? 0.3 : 0.05))
                .frame(width: 4, height: 4)
                .padding(4)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                        isPulsing = true
                    }
                }
        }
        .animation(.easeInOut(duration: 0.6), value: tourStep)
        .task {
            // Choreographed 24.5-second tour for App Store Preview (15-30s Apple requirement)
            try? await Task.sleep(nanoseconds: 4_500_000_000) // 4.5s on Dashboard
            withAnimation { tourStep = 1 }                    // 5.5s on Run Detail (Classification + Timeline + Biometrics)
            try? await Task.sleep(nanoseconds: 5_500_000_000)
            withAnimation { tourStep = 2 }                    // 4.0s on Pre-Run Library
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            withAnimation { tourStep = 3 }                    // 5.0s on Drill Breakdown Modal (5-Point Readout + Timeline + Watch Export)
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            withAnimation { tourStep = 4 }                    // 5.5s on Cadence Progression Chart
            try? await Task.sleep(nanoseconds: 5_500_000_000)
        }
    }

    @ViewBuilder
    private var drillReadoutView: some View {
        let template = DrillTemplate.template(for: .cadencePyramids)
        let targetCadence: String? = baseCadence.map { template.calculateTargetCadence($0) }
        let drill = PreRunDrill(
            id: .cadencePyramids,
            previousCadence: baseCadence,
            targetCadence: targetCadence,
            duration: .tenMinutes,
            hapticMode: .on
        )
        let readout = DrillReadout.readout(
            for: .cadencePyramids,
            customTitle: template.title,
            targetCadence: targetCadence,
            previousCadence: baseCadence,
            customDuration: .tenMinutes
        )
        let plan = drill.buildWorkoutPlan()
        let dto = DrillPrescriptionDTO(
            title: template.title,
            preRunDrillId: PreRunDrillId.cadencePyramids.rawValue,
            purpose: template.defaultPurpose,
            targetCadence: targetCadence,
            previousCadence: baseCadence,
            durationMinutes: DrillDuration.tenMinutes.rawValue,
            hapticMode: HapticFeedbackMode.on.rawValue
        )

        DrillInterstitialReadoutView(
            readout: readout,
            workoutPlan: plan,
            prescriptionDTO: dto,
            onCommitToWatch: nil
        )
    }
}

#Preview {
    let previewContainer: ModelContainer = {
        do {
            let schema = Schema([RunRecord.self, CoachingInsight.self, DrillRecommendation.self, TrainingCorrection.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    ContentView()
        .modelContainer(previewContainer)
}
