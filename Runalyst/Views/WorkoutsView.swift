import SwiftUI
import SwiftData
import WorkoutKit

/// Dedicated "Workouts" Tab View.
/// Mirrors the visual architecture of the user mental model and blueprint mockups:
/// Top Goal header, Daily Prescription card, Linked Pre-Run Drill card, and Microcycle Progression.
struct WorkoutsView: View {
    @Query(sort: \RunRecord.date, order: .reverse) private var runRecords: [RunRecord]
    @AppStorage("trainingGoal") private var trainingGoal: String = "Base Building"
    @AppStorage("useMetricSystem") private var useMetricSystem: Bool = Locale.current.measurementSystem == .metric
    @AppStorage("preferredWorkoutIsIndoor") private var preferredWorkoutIsIndoor: Bool = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var showingUserProfile = false
    @State private var showingAnalystChat = false
    @State private var showingDrillsLibrary = false
    @State private var isDrillCompleted = false
    @State private var selectedRunForDetail: RunRecord?
    @State private var watchExportSuccessMessage: String?
    @State private var showingExportAlert = false
    @State private var activeReadoutItem: ActiveDrillReadoutItem?
    @State private var isSyncing = false

    var overrideDailyState: DailyTrainingState?
    var onSync: ((Bool) async -> Void)?

    private var dailyState: DailyTrainingState {
        if let overrideDailyState {
            return overrideDailyState
        }
        let profile = RunnerProfile.compute(from: runRecords, trainingGoal: trainingGoal)
        return SessionSynthesisEngine.evaluateDailyState(
            runRecords: runRecords,
            activeGoal: trainingGoal,
            experienceLevel: profile.experienceLevel,
            useMetric: useMetricSystem,
            userHeightCm: profile.userHeightCm
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
                .frame(maxWidth: horizontalSizeClass == .regular ? 920 : .infinity)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 100)
            }
            .refreshable {
                guard !isSyncing else { return }
                isSyncing = true
                defer { isSyncing = false }

                UIImpactFeedbackGenerator(style: .medium).impactOccurred()

                let syncTask = Task {
                    if let onSync {
                        await onSync(false)
                    }
                }
                _ = await syncTask.value
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Workouts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    CoachPillButton {
                        showingAnalystChat = true
                    }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .sheet(isPresented: $showingAnalystChat) {
                AnalystChatView(mode: .macroCoach)
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
                        let envLabel = (dto.isIndoor ?? preferredWorkoutIsIndoor) ? "Indoor" : "Outdoor"
                        watchExportSuccessMessage = "\(dto.title) (\(envLabel)) scheduled to Apple Watch."
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
        unifiedSessionCard(session: session)

        // Microcycle Progression Horizon
        microcycleSection(microcycle: session.microcycle)

        // Runs & Drills Library Discovery Banner
        drillsLibraryBanner
    }

    // MARK: - Completed Today Content (Post-Run State)

    @ViewBuilder
    private func completedTodayContent(completedRun: RunRecordSnapshot, tomorrowSession: PrescribedDailySession) -> some View {
        let allRunsToday = completedRun.allCompletedRunsToday

        // Today's Session Complete Banner
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(
                    allRunsToday.count > 1 ? "Today's Sessions Complete (\(allRunsToday.count))" : "Today's Session Complete",
                    systemImage: "checkmark.circle.fill"
                )
                .font(.headline.weight(.bold))
                .foregroundColor(.green)
                Spacer()
                if allRunsToday.count == 1 {
                    if completedRun.isPrimerDrill {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                            Text("Target Met")
                                .font(.caption.bold())
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.18))
                        .foregroundColor(.green)
                        .clipShape(Capsule())
                    } else {
                        Text("Grade \(completedRun.letterGrade)")
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.18))
                            .foregroundColor(.green)
                            .clipShape(Capsule())
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(allRunsToday) { snap in
                    let targetRun = runRecords.first(where: { $0.id == snap.id })

                    Button {
                        if let targetRun {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            selectedRunForDetail = targetRun
                        }
                    } label: {
                        let iconName = snap.isPrimerDrill ? RunalystIcon.cadencePyramids : (snap.isIndoor ? RunalystIcon.indoor : RunalystIcon.outdoor)
                        let iconColor = snap.isPrimerDrill ? RunalystColor.cadence : (snap.isIndoor ? RunalystColor.indoor : RunalystColor.outdoor)

                        HStack(alignment: .center, spacing: 10) {
                            Image(systemName: iconName)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(iconColor)
                                .frame(width: 28, height: 28)
                                .background(iconColor.opacity(0.12))
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(snap.workoutType)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                    .truncationMode(.tail)
                                Text("\(snap.durationFormatted) • \(snap.distanceFormatted)")
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundColor(.secondary)
                            }

                            Spacer(minLength: 8)

                            if allRunsToday.count > 1 {
                                if snap.isPrimerDrill {
                                    HStack(spacing: 3) {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 9, weight: .bold))
                                        Text("Target Met")
                                            .font(.caption2.bold())
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.green.opacity(0.15))
                                    .foregroundColor(.green)
                                    .clipShape(Capsule())
                                    .fixedSize()
                                } else {
                                    Text("Grade \(snap.letterGrade)")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.green.opacity(0.15))
                                        .foregroundColor(.green)
                                        .clipShape(Capsule())
                                        .fixedSize()
                                }
                            }

                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(UIColor.tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(targetRun == nil)
                }
            }
        }
        .liquidGlass(cornerRadius: 16, padding: 18, accentColor: .green)

        // Tomorrow's Session
        VStack(alignment: .leading, spacing: 8) {
            Text("Tomorrow's Session")
                .font(.headline.weight(.bold))
                .foregroundColor(.primary)
                .padding(.horizontal, 4)

            tomorrowPreviewCard(session: tomorrowSession)

            microcycleSection(microcycle: tomorrowSession.microcycle)

            drillsLibraryBanner
        }
    }

    // MARK: - Tomorrow's Preview Card (Refined Apple-Grade Architecture)

    private func tomorrowPreviewCard(session: PrescribedDailySession) -> some View {
        PrescribedSessionCardView(
            session: session,
            isToday: false,
            dayLabel: tomorrowDayName(),
            preferredWorkoutIsIndoor: $preferredWorkoutIsIndoor,
            onPreviewPrimer: {
                openPrimerReadout(for: session)
            },
            onPreviewMainRun: {
                openMainRunReadout(for: session)
            }
        )
    }

    private func tomorrowDayName() -> String {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE"
        return formatter.string(from: tomorrow)
    }

    // MARK: - Unified Daily Session Card (Today's Active Session)

    private func unifiedSessionCard(session: PrescribedDailySession) -> some View {
        PrescribedSessionCardView(
            session: session,
            isToday: true,
            preferredWorkoutIsIndoor: $preferredWorkoutIsIndoor,
            onPreviewPrimer: {
                openPrimerReadout(for: session)
            },
            onPreviewMainRun: {
                openMainRunReadout(for: session)
            }
        )
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

                    Text("Primers, cadence pyramids & intervals")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
            .liquidGlass(cornerRadius: 16, padding: 14, accentColor: Color(red: 0.0, green: 0.55, blue: 1.0))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    private func openPrimerReadout(for session: PrescribedDailySession) {
        let state = session.resolvedReadinessState
        let dto = DrillPrescriptionDTO(
            title: session.primerDrillTitle,
            preRunDrillId: session.primerDrillId.rawValue,
            purpose: session.groundedRationale,
            targetCadence: session.primerTargetCadence,
            previousCadence: session.cadenceFloor,
            durationMinutes: session.primerDrillId.defaultDuration.rawValue,
            hapticMode: "On",
            readinessState: state == .productive ? nil : state.rawValue,
            isIndoor: preferredWorkoutIsIndoor
        )
        activeReadoutItem = ActiveDrillReadoutItem.fromPrescription(
            dto: dto,
            customCoachingTip: session.groundedRationale
        )
    }

    private func openMainRunReadout(for session: PrescribedDailySession) {
        let mainDrillId = session.mainSessionTemplateId
        let state = session.resolvedReadinessState
        let dto = DrillPrescriptionDTO(
            title: session.sessionTitle,
            preRunDrillId: mainDrillId.rawValue,
            purpose: session.groundedRationale,
            targetCadence: mainDrillId.isHeartRateTargeted ? nil : "\(session.cadenceFloor)-\(session.cadenceFloor + 6)",
            previousCadence: session.cadenceFloor,
            durationMinutes: session.mainRunDurationMinutes,
            hapticMode: "On",
            readinessState: state == .productive ? nil : state.rawValue,
            isIndoor: preferredWorkoutIsIndoor
        )
        activeReadoutItem = ActiveDrillReadoutItem.fromPrescription(
            dto: dto,
            customCoachingTip: session.groundedRationale
        )
    }

    private func microcycleSection(microcycle: [MicrocycleDay]) -> some View {
        UpcomingScheduleCardView(microcycle: microcycle)
    }
}
