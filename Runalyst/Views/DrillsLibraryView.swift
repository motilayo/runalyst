import SwiftUI
import SwiftData
import WorkoutKit

struct DrillsLibraryView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \RunRecord.date, order: .reverse) private var runRecords: [RunRecord]
    @State private var selectedCategory: String = "All"

    @AppStorage("dashboardTimeRange") private var dashboardTimeRange: String = "30 Days"
    @AppStorage("minimumRunDistance") private var minimumRunDistance: Double = 1.0
    @AppStorage("useMetricSystem") private var useMetricSystem: Bool = Locale.current.measurementSystem == .metric
    @AppStorage("lastBaselineChangeTimestamp") private var lastBaselineChangeTimestamp: Double = 0
    @AppStorage("lastWatchExportTimestamp") private var lastWatchExportTimestamp: Double = 0
    @AppStorage("lastExportedDrillId") private var lastExportedDrillId: String = ""
    @AppStorage("preferredWorkoutIsIndoor") private var preferredWorkoutIsIndoor: Bool = false

    @State private var activeReadoutItem: ActiveDrillReadoutItem?
    @State private var isAutoSyncing: Bool = false
    @State private var autoSyncSuccess: Bool = false

    let categories = ["All", "Foundation", "Threshold", "Speed"]

    private var filteredRunRecords: [RunRecord] {
        let minDistanceInMeters = useMetricSystem ? (minimumRunDistance * 1000.0) : (minimumRunDistance * 1609.344)
        var filtered = runRecords.filter { $0.totalDistanceMeters >= (minDistanceInMeters - 0.01) }
        let now = Date()
        if dashboardTimeRange == "7 Days", let limit = Calendar.current.date(byAdding: .day, value: -7, to: now) {
            filtered = filtered.filter { $0.date >= limit }
        } else if dashboardTimeRange == "30 Days", let limit = Calendar.current.date(byAdding: .day, value: -30, to: now) {
            filtered = filtered.filter { $0.date >= limit }
        }
        return filtered
    }

    private var baselineCadence: Int? {
        let recentRuns = filteredRunRecords.filter { $0.workingAvgCadence > 0 }
        guard !recentRuns.isEmpty else { return nil }
        return Int(recentRuns.map(\.workingAvgCadence).reduce(0, +)) / recentRuns.count
    }

    private var isExportStale: Bool {
        lastWatchExportTimestamp > 0 && lastBaselineChangeTimestamp > lastWatchExportTimestamp
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if isAutoSyncing, let base = baselineCadence {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(Color(red: 0.05, green: 0.45, blue: 0.5))
                        Text("Auto-updating Watch targets for your new \(base) SPM baseline...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                } else if autoSyncSuccess, let base = baselineCadence {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Watch targets auto-updated for your new \(base) SPM baseline ✓")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.12))
                    .cornerRadius(12)
                    .padding(.horizontal)
                } else if isExportStale, let base = baselineCadence {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Baseline Updated (\(base) SPM)")
                                .font(.caption.bold())
                                .foregroundColor(.primary)
                            Text("Update Watch targets to match your new baseline.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Sync Now") {
                            Task {
                                await autoSyncStaleExportIfNeeded()
                            }
                        }
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }

                // Run Environment Selector (Outdoor vs Indoor Treadmill)
                HStack(spacing: 10) {
                    Label(
                        preferredWorkoutIsIndoor ? "Indoor (Treadmill)" : "Outdoor (GPS)",
                        systemImage: preferredWorkoutIsIndoor ? "figure.run.square.stack" : "sun.max.fill"
                    )
                    .font(.caption.bold())
                    .foregroundColor(preferredWorkoutIsIndoor ? .purple : .blue)

                    Spacer()

                    Picker("Run Environment", selection: $preferredWorkoutIsIndoor) {
                        Text("Outdoor").tag(false)
                        Text("Indoor (Treadmill)").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 220)
                    .onChange(of: preferredWorkoutIsIndoor) { _, _ in
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal)

                // Category Picker
                Picker("Category", selection: $selectedCategory) {
                    ForEach(categories, id: \.self) { category in
                        Text(category).tag(category)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 2)

                // Section 1: Foundation & Recovery Primers
                if selectedCategory == "All" || selectedCategory == "Foundation" {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Foundation & Recovery Primers")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .padding(.horizontal)

                        if horizontalSizeClass == .regular {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                                DrillPrimerCardView(
                                    drillId: .recoveryJog,
                                    customTitle: "Recovery Jog",
                                    customTarget: "Zone 1 HR",
                                    baselineCadence: baselineCadence,
                                    onStart: handleStartDrill
                                )

                                DrillPrimerCardView(
                                    drillId: .zone2Run,
                                    customTitle: "Zone 2 Run",
                                    customTarget: "Zone 2 HR",
                                    baselineCadence: baselineCadence,
                                    onStart: handleStartDrill
                                )
                            }
                            .padding(.horizontal)
                        } else {
                            DrillPrimerCardView(
                                drillId: .recoveryJog,
                                customTitle: "Recovery Jog",
                                customTarget: "Zone 1 HR",
                                baselineCadence: baselineCadence,
                                onStart: handleStartDrill
                            )
                            .padding(.horizontal)

                            DrillPrimerCardView(
                                drillId: .zone2Run,
                                customTitle: "Zone 2 Run",
                                customTarget: "Zone 2 HR",
                                baselineCadence: baselineCadence,
                                onStart: handleStartDrill
                            )
                            .padding(.horizontal)
                        }
                    }
                }

                // Section 2: Speed & Efficiency Primers
                if selectedCategory == "All" || selectedCategory == "Speed" {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Speed & Efficiency Primers")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .padding(.horizontal)

                        if horizontalSizeClass == .regular {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                                DrillPrimerCardView(
                                    drillId: .cadencePyramids,
                                    baselineCadence: baselineCadence,
                                    onStart: handleStartDrill
                                )

                                DrillPrimerCardView(
                                    drillId: .strides,
                                    baselineCadence: baselineCadence,
                                    onStart: handleStartDrill
                                )

                                DrillPrimerCardView(
                                    drillId: .neuromuscularPrimer,
                                    baselineCadence: baselineCadence,
                                    onStart: handleStartDrill
                                )

                                DrillPrimerCardView(
                                    drillId: .hillBounds,
                                    baselineCadence: baselineCadence,
                                    onStart: handleStartDrill
                                )
                            }
                            .padding(.horizontal)
                        } else {
                            DrillPrimerCardView(
                                drillId: .cadencePyramids,
                                baselineCadence: baselineCadence,
                                onStart: handleStartDrill
                            )
                            .padding(.horizontal)

                            DrillPrimerCardView(
                                drillId: .strides,
                                baselineCadence: baselineCadence,
                                onStart: handleStartDrill
                            )
                            .padding(.horizontal)

                            DrillPrimerCardView(
                                drillId: .neuromuscularPrimer,
                                baselineCadence: baselineCadence,
                                onStart: handleStartDrill
                            )
                            .padding(.horizontal)

                            DrillPrimerCardView(
                                drillId: .hillBounds,
                                baselineCadence: baselineCadence,
                                onStart: handleStartDrill
                            )
                            .padding(.horizontal)
                        }
                    }
                }

                // Section 3: Threshold & Form Primers
                if selectedCategory == "All" || selectedCategory == "Threshold" {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Threshold & Form Primers")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .padding(.horizontal)

                        if horizontalSizeClass == .regular {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                                DrillPrimerCardView(
                                    drillId: .rhythmIntervals,
                                    baselineCadence: baselineCadence,
                                    onStart: handleStartDrill
                                )

                                DrillPrimerCardView(
                                    drillId: .tempoSurges,
                                    baselineCadence: baselineCadence,
                                    onStart: handleStartDrill
                                )

                                DrillPrimerCardView(
                                    drillId: .fartlekPrimer,
                                    baselineCadence: baselineCadence,
                                    onStart: handleStartDrill
                                )
                            }
                            .padding(.horizontal)
                        } else {
                            DrillPrimerCardView(
                                drillId: .rhythmIntervals,
                                baselineCadence: baselineCadence,
                                onStart: handleStartDrill
                            )
                            .padding(.horizontal)

                            DrillPrimerCardView(
                                drillId: .tempoSurges,
                                baselineCadence: baselineCadence,
                                onStart: handleStartDrill
                            )
                            .padding(.horizontal)

                            DrillPrimerCardView(
                                drillId: .fartlekPrimer,
                                baselineCadence: baselineCadence,
                                onStart: handleStartDrill
                            )
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .sheet(item: $activeReadoutItem) { item in
            DrillInterstitialReadoutView(
                readout: item.readout,
                workoutPlan: item.plan,
                prescriptionDTO: item.dto,
                onCommitToWatch: { _, dto in
                    self.lastExportedDrillId = dto.preRunDrillId ?? ""
                    self.lastWatchExportTimestamp = Date().timeIntervalSince1970
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("🏃 Runs & Drills")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if isExportStale {
                await autoSyncStaleExportIfNeeded()
            }
        }
        .onChange(of: baselineCadence) {
            if lastWatchExportTimestamp > 0 {
                Task {
                    await autoSyncStaleExportIfNeeded()
                }
            }
        }
    }

    private func handleStartDrill(plan: WorkoutPlan, dto: DrillPrescriptionDTO) {
        let readiness = ReadinessEvaluator.assess(runRecords: runRecords)
        activeReadoutItem = ActiveDrillReadoutItem.adaptive(dto: dto, readiness: readiness)
    }

    private func scheduleDrillToWatch(dto: DrillPrescriptionDTO) {
        Task {
            if #available(iOS 17.0, *) {
                do {
                    let bridge = WorkoutBridge()
                    try await bridge.scheduleDrill(dto: dto)
                    await MainActor.run {
                        self.lastExportedDrillId = dto.preRunDrillId ?? ""
                        self.lastWatchExportTimestamp = Date().timeIntervalSince1970
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                } catch {
                    print("[DrillsLibraryView] Error scheduling drill: \(error.localizedDescription)")
                }
            }
        }
    }

    private func autoSyncStaleExportIfNeeded() async {
        guard !lastExportedDrillId.isEmpty else { return }
        guard #available(iOS 17.0, *) else { return }
        guard let baseline = baselineCadence else { return }
        guard let preRunId = PreRunDrillId(rawValue: lastExportedDrillId) else { return }

        await MainActor.run {
            self.isAutoSyncing = true
        }

        let template = DrillTemplate.template(for: preRunId)
        let newTarget = template.calculateTargetCadence(baseline)

        let dto = DrillPrescriptionDTO(
            title: template.title,
            preRunDrillId: preRunId.rawValue,
            purpose: template.defaultPurpose,
            targetCadence: newTarget,
            previousCadence: baseline,
            isIndoor: preferredWorkoutIsIndoor
        )

        do {
            let bridge = WorkoutBridge()
            try await bridge.scheduleDrill(dto: dto)
            await MainActor.run {
                self.lastWatchExportTimestamp = Date().timeIntervalSince1970
                self.isAutoSyncing = false
                self.autoSyncSuccess = true
            }
        } catch {
            await MainActor.run {
                self.isAutoSyncing = false
            }
        }
    }
}
