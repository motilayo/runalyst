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

    @AppStorage("selectedTab") private var selectedTab: Int = 0

    private var previewScreen: String? {
        UserDefaults.standard.string(forKey: "RUNALYST_PREVIEW_SCREEN") ?? ProcessInfo.processInfo.environment["RUNALYST_PREVIEW_SCREEN"]
    }

    var body: some View {
        Group {
            if let previewScreen {
                PreviewRouterView(previewScreen: previewScreen, existingRuns: existingRuns)
            } else if hasCompletedOnboarding {
                TabView(selection: $selectedTab) {
                    DashboardView(onSync: { force in
                        await syncData(force: force)
                    })
                    .tabItem {
                        Label("Dashboard", systemImage: "square.grid.2x2.fill")
                    }
                    .tag(0)

                    WorkoutsView()
                        .tabItem {
                            Label("Workouts", systemImage: "figure.run")
                        }
                        .tag(1)

                    AnalysisDashboardView()
                        .tabItem {
                            Label("Analysis", systemImage: "chart.bar.fill")
                        }
                        .tag(2)

                    NavigationStack {
                        SettingsView(onForceSync: { force in
                            await syncData(force: force)
                        })
                    }
                    .tabItem {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                    .tag(3)
                }
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
                    SyncProgressBannerView(
                        isSyncing: isSyncing,
                        syncProgress: syncProgress,
                        syncStatusMessage: syncStatusMessage
                    )
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

            // 3. Extract and insert new runs incrementally (oldest to newest)
            // Chronological order ensures trailing 30-day baselines are available for accurate classification.
            let sortedNewWorkouts = newWorkouts.sorted { $0.startDate < $1.startDate }
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
                            runSignatureData: dto.runSignatureData,
                            ambientTemperatureCelsius: dto.ambientTemperatureCelsius,
                            ambientHumidity: dto.ambientHumidity
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
                                    let resolvedDrillId = drill.preRunDrillId.flatMap(PreRunDrillId.init(rawValue:))
                                        ?? PreRunDrillId.resolve(from: drill.drillTitle)
                                    let matchesId = drill.preRunDrillId.map { dto.framboiseTags.contains($0) } ?? false
                                    let matchesTag = dto.framboiseTags.contains("drill:\(drill.drillTitle)")
                                    let matchesTitle = drill.drillTitle.localizedCaseInsensitiveCompare(dto.detectedTypeRaw) == .orderedSame
                                    let matchesResolved: Bool = {
                                        guard let rId = resolvedDrillId else { return false }
                                        return dto.framboiseTags.contains(rId.rawValue) ||
                                               dto.framboiseTags.contains("drill:\(rId.title)") ||
                                               dto.framboiseTags.contains("drill:\(rId.rawValue)") ||
                                               dto.detectedTypeRaw.localizedCaseInsensitiveCompare(rId.title) == .orderedSame ||
                                               dto.detectedTypeRaw.localizedCaseInsensitiveCompare(rId.correspondingClassification) == .orderedSame
                                    }()
                                    if matchesTitle || matchesId || matchesTag || matchesResolved {
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
            let nsError = error as NSError
            let isAuthNotDetermined = (error as? HKError)?.code == .errorAuthorizationNotDetermined ||
                                      (nsError.domain == HKErrorDomain && nsError.code == HKError.Code.errorAuthorizationNotDetermined.rawValue) ||
                                      error.localizedDescription.localizedCaseInsensitiveContains("Authorization not determined")
            if isAuthNotDetermined {
                logger.info("HealthKit authorization not yet determined; skipping sync error alert.")
            } else {
                logger.error("Failed to sync data: \(error.localizedDescription)")
                await MainActor.run {
                    self.syncError = error.localizedDescription
                    self.showError = true
                }
            }
        }
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
