import SwiftUI
import SwiftData
import WorkoutKit

/// Dedicated "Workouts" Tab View.
/// Mirrors the visual architecture of the user mental model and blueprint mockups:
/// Top Goal header, Daily Prescription card, Linked Pre-Run Drill card, and Microcycle Progression.
struct WorkoutsView: View {
    @Query(sort: \RunRecord.date, order: .reverse) private var runRecords: [RunRecord]
    @AppStorage("trainingGoal") private var trainingGoal: String = "5K"
    @AppStorage("useMetricSystem") private var useMetricSystem: Bool = Locale.current.measurementSystem == .metric

    @State private var showingUserProfile = false
    @State private var showingAnalystChat = false
    @State private var showingDrillsLibrary = false
    @State private var isDrillCompleted = false
    @State private var selectedRunForDetail: RunRecord?
    @State private var watchExportSuccessMessage: String?
    @State private var showingExportAlert = false
    @State private var activeReadoutItem: ActiveDrillReadoutItem?

    private var dailyState: DailyTrainingState {
        let profile = RunnerProfile.compute(from: runRecords, trainingGoal: trainingGoal)
        return SessionSynthesisEngine.evaluateDailyState(
            runRecords: runRecords,
            activeGoal: trainingGoal,
            experienceLevel: profile.experienceLevel,
            useMetric: useMetricSystem
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    switch dailyState {
                    case .preRun(let session):
                        preRunContent(session: session)
                    case .completedToday(let completedRun, let tomorrowSession):
                        completedTodayContent(completedRun: completedRun, tomorrowSession: tomorrowSession)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 90)
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Workouts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingDrillsLibrary = true
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "figure.run.square.stack")
                            Text("Drills")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundColor(Color(red: 0.0, green: 0.55, blue: 1.0))
                    }
                    .accessibilityLabel("Runs & Drills Library")
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if !runRecords.isEmpty {
                        Button {
                            showingAnalystChat = true
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        } label: {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .foregroundColor(.purple)
                        }
                        .accessibilityLabel("AI Coach")
                    }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .sheet(isPresented: $showingAnalystChat) {
                if let latestRun = runRecords.first {
                    AnalystChatView(runRecord: latestRun)
                }
            }
            .sheet(isPresented: $showingUserProfile) {
                UserProfileView()
            }
            .sheet(isPresented: $showingDrillsLibrary) {
                NavigationStack {
                    DrillsLibraryView()
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") {
                                    showingDrillsLibrary = false
                                }
                                .font(.subheadline.bold())
                            }
                        }
                }
            }
            .navigationDestination(item: $selectedRunForDetail) { run in
                RunDetailView(runRecord: run)
            }
            .sheet(item: $activeReadoutItem) { item in
                DrillInterstitialReadoutView(
                    readout: item.readout,
                    workoutPlan: item.plan,
                    prescriptionDTO: item.dto,
                    onCommitToWatch: { _, dto in
                        watchExportSuccessMessage = "\(dto.title) scheduled to Apple Watch."
                        showingExportAlert = true
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .alert("Apple Watch Sync", isPresented: $showingExportAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(watchExportSuccessMessage ?? "Workout sent to Apple Watch.")
            }
        }
    }

    // MARK: - Pre-Run Content (Before Today's Run)

    @ViewBuilder
    private func preRunContent(session: PrescribedDailySession) -> some View {
        // Concept A: Unified Daily Session Card (Pre-Run Primer on top, Main Run below)
        unifiedSessionCard(session: session, isTomorrow: false)

        // Microcycle Progression Horizon
        microcycleSection(microcycle: session.microcycle)

        // Runs & Drills Library Discovery Banner
        drillsLibraryBanner
    }

    // MARK: - Completed Today Content (Post-Run State)

    @ViewBuilder
    private func completedTodayContent(completedRun: RunRecordSnapshot, tomorrowSession: PrescribedDailySession) -> some View {
        // Today's Session Complete Banner
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Today's Session Complete", systemImage: "checkmark.circle.fill")
                    .font(.headline.weight(.bold))
                    .foregroundColor(.green)
                Spacer()
                Text("Grade \(completedRun.letterGrade)")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.18))
                    .foregroundColor(.green)
                    .clipShape(Capsule())
            }

            Text("\(completedRun.workoutType) • \(completedRun.durationFormatted) • \(completedRun.distanceFormatted)")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.primary)

            if let targetRun = runRecords.first(where: { $0.id == completedRun.id }) {
                Button {
                    selectedRunForDetail = targetRun
                } label: {
                    HStack(spacing: 4) {
                        Text("View Run Details")
                            .font(.subheadline.bold())
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                    }
                    .foregroundColor(.green)
                }
                .padding(.top, 4)
            }
        }
        .padding(18)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.green.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)

        // Tomorrow's Promoted & Adapted Prescription
        VStack(alignment: .leading, spacing: 8) {
            Text("Tomorrow's Updated Prescription")
                .font(.headline.weight(.bold))
                .foregroundColor(.primary)
                .padding(.horizontal, 4)

            unifiedSessionCard(session: tomorrowSession, isTomorrow: true)

            microcycleSection(microcycle: tomorrowSession.microcycle)

            drillsLibraryBanner
        }
    }

    // MARK: - Unified Daily Session Card (Concept A)

    private func unifiedSessionCard(session: PrescribedDailySession, isTomorrow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // 1. Session Overline & Target Goal Badge
            HStack {
                Label(isTomorrow ? "TOMORROW'S TARGET" : "TODAY'S WORKOUT", systemImage: isTomorrow ? "arrow.forward.circle.fill" : "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(isTomorrow ? .blue : Color(red: 0.0, green: 0.75, blue: 0.65))

                Spacer()

                Text(session.targetGoal)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(UIColor.tertiarySystemGroupedBackground))
                    .clipShape(Capsule())
            }

            // 2. Session Title & Grounded Rationale
            VStack(alignment: .leading, spacing: 6) {
                Text(session.sessionTitle)
                    .font(.title2.weight(.bold))
                    .foregroundColor(.primary)

                Text(session.groundedRationale)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 3. Pre-Run Primer (Done First)
            preRunPrimerSection(session: session)

            // 4. Main Run Targets (Done Second)
            mainRunSection(session: session)

            // 5. Unified Action Buttons
            HStack(spacing: 10) {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    openReadout(for: session)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.caption.bold())
                        Text("Start Workout")
                            .font(.subheadline.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Color.primary)
                    .foregroundColor(Color(UIColor.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    sendSessionToWatch(session: session)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "applewatch")
                            .font(.subheadline)
                        Text("Send to Watch")
                            .font(.subheadline.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Color(UIColor.tertiarySystemGroupedBackground))
                    .foregroundColor(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(.top, 2)
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color(UIColor.separator).opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
    }

    // MARK: - Pre-Run Primer Subcard (Done First)

    private func preRunPrimerSection(session: PrescribedDailySession) -> some View {
        let preRunDrill = PreRunDrill(
            id: session.primerDrillId,
            previousCadence: session.cadenceFloor,
            targetCadence: session.primerTargetCadence,
            readinessState: session.isTrimmed ? .acuteFatigue : .productive
        )
        let phases = preRunDrill.generatePhases()

        return VStack(alignment: .leading, spacing: 8) {
            // Overline inside primer section
            HStack {
                Label("PRE-RUN PRIMER", systemImage: "figure.run")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(red: 0.0, green: 0.8, blue: 0.65))

                Spacer()

                if session.isTrimmed {
                    Text("Trimmed for Readiness")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            // Sub-row: Title & subtitle on left, actions on right
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.primerDrillTitle)
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.primary)

                    Text(cleanPrimerSubtitle(session: session))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                Spacer(minLength: 6)

                // Inline quick Start button
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    openReadout(for: session)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text("Start")
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(Color.primary)
                    .foregroundColor(Color(UIColor.systemBackground))
                    .clipShape(Capsule())
                }

                // Completion toggle
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        isDrillCompleted.toggle()
                    }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } label: {
                    Image(systemName: isDrillCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundColor(isDrillCompleted ? .green : .secondary)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel(isDrillCompleted ? "Primer completed" : "Mark primer completed")
            }

            // Continuous 4pt segmented rhythm bar
            let totalDuration = max(1, phases.reduce(0) { $0 + $1.durationSeconds })
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(phases) { phase in
                        let ratio = CGFloat(phase.durationSeconds) / CGFloat(totalDuration)
                        let w = max(4, (geo.size.width - CGFloat(phases.count - 1) * 2) * ratio)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(phaseColor(phase.kind))
                            .frame(width: w, height: 4)
                    }
                }
            }
            .frame(height: 4)
            .padding(.top, 2)
        }
        .padding(12)
        .background(Color(UIColor.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Main Run Targets (Done Second)

    private func mainRunSection(session: PrescribedDailySession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Overline inside main run card
            HStack {
                Label("MAIN RUN", systemImage: "figure.run")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(red: 0.0, green: 0.55, blue: 1.0))

                Spacer()

                Text(session.durationBand)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(red: 0.0, green: 0.55, blue: 1.0))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color(red: 0.0, green: 0.55, blue: 1.0).opacity(0.12))
                    .clipShape(Capsule())
            }

            // Sub-row: Title & target parameters
            VStack(alignment: .leading, spacing: 2) {
                Text(session.sessionTitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.primary)

                Text("Target: \(session.paceBand) • \(session.hrCap.replacingOccurrences(of: "HR: ", with: "Max HR: "))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            // Core Targets Grid
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                metricCell(
                    icon: "stopwatch.fill",
                    title: "Duration",
                    value: session.durationBand,
                    color: .secondary
                )
                metricCell(
                    icon: "figure.run",
                    title: "Pace",
                    value: session.paceBand,
                    color: Color(red: 0.0, green: 0.55, blue: 1.0)
                )
                metricCell(
                    icon: "heart.fill",
                    title: "Max HR",
                    value: session.hrCap.replacingOccurrences(of: "HR: ", with: ""),
                    color: Color(red: 1.0, green: 0.22, blue: 0.55)
                )
                metricCell(
                    icon: "metronome.fill",
                    title: "Cadence",
                    value: "≥ \(session.cadenceFloor) SPM",
                    color: Color(red: 0.0, green: 0.8, blue: 0.65)
                )
            }
        }
        .padding(12)
        .background(Color(UIColor.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func metricCell(icon: String, title: String, value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                Text(value)
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func sendSessionToWatch(session: PrescribedDailySession) {
        Task {
            let bridge = WorkoutBridge()
            let dto = DrillPrescriptionDTO(
                title: session.sessionTitle,
                preRunDrillId: session.primerDrillId.rawValue,
                purpose: session.groundedRationale,
                targetCadence: "\(session.cadenceFloor) SPM",
                previousCadence: session.cadenceFloor,
                durationMinutes: 30,
                hapticMode: "on",
                readinessState: session.isTrimmed ? "acuteFatigue" : "productive"
            )
            do {
                try await bridge.scheduleDrill(dto: dto)
                watchExportSuccessMessage = "Prescription successfully sent to Apple Watch via WorkoutKit."
                showingExportAlert = true
            } catch {
                watchExportSuccessMessage = "Scheduled locally. Open Workout app on your Apple Watch to start."
                showingExportAlert = true
            }
        }
    }

    private func cleanPrimerSubtitle(session: PrescribedDailySession) -> String {
        var duration = session.primerPhasesDuration
            .replacingOccurrences(of: " drill", with: "")
        if let parenRange = duration.range(of: " (Trimmed") {
            duration = String(duration[..<parenRange.lowerBound])
        }
        var target = session.primerTargetCadence
            .replacingOccurrences(of: " (Adapted)", with: "")
        return "\(duration) • Target \(target)"
    }

    // MARK: - Runs & Drills Library Discovery Banner

    private var drillsLibraryBanner: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showingDrillsLibrary = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "figure.run.square.stack")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color(red: 0.0, green: 0.55, blue: 1.0))
                    .frame(width: 40, height: 40)
                    .background(Color(red: 0.0, green: 0.55, blue: 1.0).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Runs & Drills Library")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.primary)

                    Text("Explore primers, cadence pyramids & interval formats")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
            .padding(14)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(UIColor.separator).opacity(0.12), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    private func phaseColor(_ kind: WorkoutPhase.Kind) -> Color {
        switch kind {
        case .warmup, .cooldown: return .blue
        case .work: return .orange
        case .recovery: return Color(UIColor.systemGray4)
        case .steady: return Color(red: 0.0, green: 0.55, blue: 1.0)
        }
    }

    private func openReadout(for session: PrescribedDailySession) {
        let dto = DrillPrescriptionDTO(
            title: session.primerDrillTitle,
            preRunDrillId: session.primerDrillId.rawValue,
            purpose: session.groundedRationale,
            targetCadence: session.primerTargetCadence,
            previousCadence: session.cadenceFloor,
            durationMinutes: session.isTrimmed ? 7 : 10
        )
        let readiness = ReadinessEvaluator.assess(runRecords: runRecords)
        activeReadoutItem = ActiveDrillReadoutItem.adaptive(
            dto: dto,
            readiness: readiness
        )
    }

    // MARK: - This Week's Schedule

    private func parseSessionSchedule(_ title: String) -> (name: String, detail: String?) {
        // Handle parentheses like "Zone 1 Recovery Flush (40m)" or "(4 km)"
        if let openParen = title.range(of: " ("), title.hasSuffix(")") {
            let name = String(title[..<openParen.lowerBound])
            let detail = String(title[openParen.upperBound...].dropLast())
            return (name, detail)
        }
        // Handle trailing distance/duration like "Tempo Surges 30m" or "Long Run 16 km" or "Zone 2 Steady 45m"
        let patterns = [" 16 km", " 10 mi", " 7 km", " 4.5 mi", " 5 km", " 3 mi", " 30m", " 45m", " 40m", " 50m"]
        for pattern in patterns where title.hasSuffix(pattern) {
            let name = String(title.dropLast(pattern.count))
            let detail = pattern.trimmingCharacters(in: .whitespaces)
            return (name, detail)
        }
        return (title, nil)
    }

    private func microcycleSection(microcycle: [MicrocycleDay]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("THIS WEEK'S SCHEDULE")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(microcycle.enumerated()), id: \.element.id) { index, day in
                    HStack(spacing: 10) {
                        Image(systemName: day.iconName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(day.isRestDay ? .secondary : Color(red: 0.0, green: 0.55, blue: 1.0))
                            .frame(width: 20, alignment: .center)

                        Text(day.dayLabel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(day.isRestDay ? .secondary : .primary)
                            .frame(width: 78, alignment: .leading)
                            .lineLimit(1)

                        let parsed = parseSessionSchedule(day.sessionTitle)

                        Text(parsed.name)
                            .font(.subheadline)
                            .foregroundColor(day.isRestDay ? .secondary : .primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        Spacer(minLength: 6)

                        if let detail = parsed.detail {
                            Text(detail)
                                .font(.system(size: 12, weight: .semibold))
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color(UIColor.tertiarySystemGroupedBackground))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    if index < microcycle.count - 1 {
                        Divider()
                            .padding(.leading, 42)
                    }
                }
            }
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(UIColor.separator).opacity(0.15), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        }
        .padding(.top, 4)
    }
}
