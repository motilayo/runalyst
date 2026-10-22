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

struct DrillPrimerCardView: View {
    let drillId: PreRunDrillId
    var customTitle: String?
    var customPurpose: String?
    var customTarget: String?
    let baselineCadence: Int?
    var onStart: ((WorkoutPlan, DrillPrescriptionDTO) -> Void)?

    @Query(sort: \RunRecord.date, order: .reverse) private var runRecords: [RunRecord]
    @State private var selectedDuration: DrillDuration
    @AppStorage("drillHapticFeedbackMode") private var selectedHapticModeRaw: String = HapticFeedbackMode.on.rawValue
    @AppStorage("preferredWorkoutIsIndoor") private var preferredWorkoutIsIndoor: Bool = false

    init(
        drillId: PreRunDrillId,
        customTitle: String? = nil,
        customPurpose: String? = nil,
        customTarget: String? = nil,
        baselineCadence: Int? = nil,
        onStart: ((WorkoutPlan, DrillPrescriptionDTO) -> Void)? = nil
    ) {
        self.drillId = drillId
        self.customTitle = customTitle
        self.customPurpose = customPurpose
        self.customTarget = customTarget
        self.baselineCadence = baselineCadence
        self.onStart = onStart
        self._selectedDuration = State(initialValue: drillId.defaultDuration)
    }

    private var selectedHapticMode: HapticFeedbackMode {
        get { HapticFeedbackMode(rawValue: selectedHapticModeRaw) ?? .on }
        nonmutating set { selectedHapticModeRaw = newValue.rawValue }
    }

    var body: some View {
        let template = DrillTemplate.template(for: drillId)
        let displayTitle = customTitle ?? template.title
        let purpose = customPurpose ?? template.defaultPurpose
        let targetCadence: String? = baselineCadence.map { template.calculateTargetCadence($0) }
        let icon = drillId.iconName
        let iconColor = drillId.iconColor

        let isZone1 = drillId == .aerobicFlush || drillId == .recoveryJog
        let isZone2 = drillId == .zone2Run
        let hasCadenceTarget = !isZone1 && !isZone2

        let displayTargetText: String? = {
            if let customTarget = customTarget { return customTarget }
            if isZone1 {
                return "Zone 1 HR"
            }
            if isZone2 {
                return "Zone 2 HR"
            }
            if hasCadenceTarget {
                if let target = targetCadence {
                    return "\(target) SPM"
                } else {
                    return "Dynamic"
                }
            }
            return nil
        }()

        let previewDrill = PreRunDrill(
            id: drillId,
            previousCadence: baselineCadence,
            targetCadence: targetCadence,
            duration: selectedDuration,
            hapticMode: selectedHapticMode,
            isIndoor: preferredWorkoutIsIndoor
        )
        let phases = previewDrill.generatePhases()
        let totalDuration = max(1, phases.reduce(0) { $0 + $1.durationSeconds })

        VStack(alignment: .leading, spacing: 10) {
            // Header Row: Icon badge + Category + Duration Capsule + Preview Button
            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(iconColor.opacity(0.14))
                            .frame(width: 24, height: 24)
                        Image(systemName: icon)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(iconColor)
                    }

                    Text(drillId.isHeartRateTargeted ? "AEROBIC RUN" : "TECHNIQUE DRILL")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(iconColor)

                    Text("•")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    Text(selectedDuration.title.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(iconColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(iconColor.opacity(0.12))
                        .clipShape(Capsule())
                }

                Spacer()

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    startDrill(title: displayTitle, purpose: purpose, targetCadence: targetCadence)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "applewatch")
                            .font(.system(size: 9, weight: .bold))
                        Text("Preview")
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Color(UIColor.secondarySystemFill))
                    .foregroundColor(.primary)
                    .clipShape(Capsule())
                }
            }

            // Title & Subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.primary)

                Text(purpose)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            // Duration Selector (Scoped strictly to supported durations for this drill)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("DURATION")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Picker("Duration", selection: $selectedDuration) {
                        ForEach(drillId.supportedDurations, id: \.self) { dur in
                            Text(dur.title).tag(dur)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: drillId.supportedDurations.count > 3 ? 280 : 210)
                    .onChange(of: selectedDuration) { _, _ in
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                }
            }
            .padding(.vertical, 2)

            // 2x2 Metric Grid (matching Main Run Standard)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                drillMetricCell(
                    icon: "stopwatch.fill",
                    title: "Duration",
                    value: selectedDuration.title,
                    color: .secondary
                )
                drillMetricCell(
                    icon: drillId.isHeartRateTargeted ? "heart.fill" : "metronome.fill",
                    title: drillId.isHeartRateTargeted ? "Target HR" : "Cadence",
                    value: displayTargetText ?? "Dynamic",
                    color: drillId.isHeartRateTargeted ? Color(red: 1.0, green: 0.18, blue: 0.55) : Color(red: 0.0, green: 0.8, blue: 0.65)
                )
                drillMetricCell(
                    icon: "repeat",
                    title: "Intervals",
                    value: previewDrill.shortWorkSummary,
                    color: Color(red: 1.0, green: 0.58, blue: 0.0)
                )
                drillMetricCell(
                    icon: "figure.walk",
                    title: "Recovery",
                    value: previewDrill.shortRecoverySummary,
                    color: Color(red: 0.20, green: 0.72, blue: 0.92)
                )
            }

            // Treadmill Hint Footnote
            if preferredWorkoutIsIndoor {
                HStack(spacing: 5) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.purple)
                    Text(
                        drillId == .hillBounds
                        ? "Treadmill: Set 4–6% incline • Launches as Indoor Run on Watch"
                        : "Treadmill: Set 0.5–1.0% incline • Focus on HR & Cadence over wrist pace"
                    )
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 1)
            }

            // Sleek 4pt Phase Mini-Bar
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(phases) { phase in
                            let ratio = CGFloat(phase.durationSeconds) / CGFloat(totalDuration)
                            let w = max(4, (geo.size.width - CGFloat(phases.count - 1) * 2) * ratio)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(phase.kind.color)
                                .frame(width: w, height: 4)
                        }
                    }
                }
                .frame(height: 4)

                Text(previewDrill.structureSummary)
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.top, 2)
        }
        .padding(14)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(UIColor.separator).opacity(0.18), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
    }

    private func drillMetricCell(icon: String, title: String, value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(color)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(title.uppercased())
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: 11, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(UIColor.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func startDrill(title: String, purpose: String, targetCadence: String?) {
        let drill = PreRunDrill(
            id: drillId,
            previousCadence: baselineCadence,
            targetCadence: targetCadence,
            duration: selectedDuration,
            hapticMode: selectedHapticMode,
            isIndoor: preferredWorkoutIsIndoor
        )
        let plan = drill.buildWorkoutPlan()
        let dto = DrillPrescriptionDTO(
            title: title,
            preRunDrillId: drillId.rawValue,
            purpose: purpose,
            targetCadence: targetCadence,
            previousCadence: baselineCadence,
            durationMinutes: selectedDuration.rawValue,
            hapticMode: selectedHapticMode.rawValue,
            isIndoor: preferredWorkoutIsIndoor
        )
        onStart?(plan, dto)
    }
}
