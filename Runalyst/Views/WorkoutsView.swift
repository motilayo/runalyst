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
                .frame(maxWidth: horizontalSizeClass == .regular ? 720 : .infinity)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 20)
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Workouts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
                    AnalystChatView(runRecord: latestRun, mode: .macroCoach)
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
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: snap.isPrimerDrill ? "metronome.fill" : "figure.run")
                            .font(.caption.bold())
                            .foregroundColor(snap.isPrimerDrill ? Color(red: 0.0, green: 0.8, blue: 0.65) : Color(red: 0.0, green: 0.55, blue: 1.0))
                            .frame(width: 24, height: 24)
                            .background(
                                (snap.isPrimerDrill ? Color(red: 0.0, green: 0.8, blue: 0.65) : Color(red: 0.0, green: 0.55, blue: 1.0))
                                    .opacity(0.12)
                            )
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(snap.workoutType)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.primary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                            Text("\(snap.durationFormatted) • \(snap.distanceFormatted)")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(1)

                        HStack(spacing: 6) {
                            if allRunsToday.count > 1 {
                                if snap.isPrimerDrill {
                                    HStack(spacing: 3) {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 9, weight: .bold))
                                        Text("Target Met")
                                            .font(.caption2.bold())
                                    }
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color.green.opacity(0.15))
                                    .foregroundColor(.green)
                                    .clipShape(Capsule())
                                } else {
                                    Text("Grade \(snap.letterGrade)")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(Color.green.opacity(0.15))
                                        .foregroundColor(.green)
                                        .clipShape(Capsule())
                                }
                            }

                            if let targetRun = runRecords.first(where: { $0.id == snap.id }) {
                                Button {
                                    selectedRunForDetail = targetRun
                                } label: {
                                    HStack(spacing: 3) {
                                        Text(allRunsToday.count > 1 ? "Details" : "View Run Details")
                                            .font(.caption.bold())
                                        Image(systemName: "chevron.right")
                                            .font(.caption2.bold())
                                    }
                                    .foregroundColor(.green)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 8)
                                    .contentShape(Rectangle())
                                }
                            }
                        }
                    }
                    .padding(10)
                    .background(Color(UIColor.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
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
        let mainRunDrill = PreRunDrill(
            id: session.mainRunDrillId,
            previousCadence: session.cadenceFloor,
            targetCadence: session.mainRunDrillId.isHeartRateTargeted ? nil : "\(session.cadenceFloor)-\(session.cadenceFloor + 6)",
            duration: DrillDuration(rawValue: session.mainRunDurationMinutes) ?? .thirtyMinutes,
            readinessState: session.isTrimmed ? .acuteFatigue : .productive,
            isIndoor: preferredWorkoutIsIndoor
        )
        let mainPhases = mainRunDrill.generatePhases()
        let totalMainDuration = max(1, mainPhases.reduce(0) { $0 + $1.durationSeconds })

        let primerDrill = PreRunDrill(
            id: session.primerDrillId,
            previousCadence: session.cadenceFloor,
            targetCadence: session.primerTargetCadence,
            readinessState: session.isTrimmed ? .acuteFatigue : .productive,
            isIndoor: preferredWorkoutIsIndoor
        )
        let primerPhases = primerDrill.generatePhases()
        let totalPrimerDuration = max(1, primerPhases.reduce(0) { $0 + $1.durationSeconds })

        return VStack(alignment: .leading, spacing: 14) {
            // 1. Header Bar: Scheduled Day/Environment on left, Target Goal on right
            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.blue)

                    Text(tomorrowDayName())
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.primary)

                    // Indoor / Outdoor Quick Toggle
                    Button {
                        preferredWorkoutIsIndoor.toggle()
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: preferredWorkoutIsIndoor ? "figure.run.square.stack" : "sun.max.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text(preferredWorkoutIsIndoor ? "Indoor" : "Outdoor")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(preferredWorkoutIsIndoor ? .purple : .blue)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background((preferredWorkoutIsIndoor ? Color.purple : Color.blue).opacity(0.12))
                        .clipShape(Capsule())
                    }

                    Text(session.targetGoal)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color(UIColor.tertiarySystemGroupedBackground))
                        .clipShape(Capsule())
                }

                Spacer(minLength: 4)
            }

            // 2. Main Title & Empathetic Coaching Directive
            VStack(alignment: .leading, spacing: 4) {
                Text(session.sessionTitle)
                    .font(.title3.weight(.bold))
                    .foregroundColor(.primary)

                Text(session.groundedRationale)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 3. Integrated 2-Part Session Sequence (Pre-Run Primer ➔ Main Run in Order)
            VStack(spacing: 10) {
                // Pre-Run Primer Subcard (Enlarged & Rich)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 8) {
                        HStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(Color(red: 0.0, green: 0.8, blue: 0.65).opacity(0.14))
                                    .frame(width: 24, height: 24)
                                Image(systemName: "metronome.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(Color(red: 0.0, green: 0.8, blue: 0.65))
                            }

                            Text("PRE-RUN PRIMER")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Color(red: 0.0, green: 0.8, blue: 0.65))

                            Text("•")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)

                            Text(cleanPrimerDuration(session: session))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Color(red: 0.0, green: 0.8, blue: 0.65))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color(red: 0.0, green: 0.8, blue: 0.65).opacity(0.12))
                                .clipShape(Capsule())
                        }

                        Spacer()

                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            openPrimerReadout(for: session)
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

                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.primerDrillTitle)
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.primary)

                        Text("Target \(cleanPrimerTarget(session: session))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }

                    // Primer continuous segmented phase bar
                    VStack(alignment: .leading, spacing: 4) {
                        GeometryReader { geo in
                            HStack(spacing: 2) {
                                ForEach(primerPhases) { phase in
                                    let ratio = CGFloat(phase.durationSeconds) / CGFloat(totalPrimerDuration)
                                    let w = max(4, (geo.size.width - CGFloat(primerPhases.count - 1) * 2) * ratio)
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(phaseColor(phase.kind))
                                        .frame(width: w, height: 4)
                                }
                            }
                        }
                        .frame(height: 4)

                        Text(drillStructureSummary(drill: primerDrill))
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.top, 2)
                }
                .padding(12)
                .background(Color(UIColor.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                // Main Run Subcard (Enlarged & Integrated Targets)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 8) {
                        HStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(Color(red: 0.0, green: 0.55, blue: 1.0).opacity(0.14))
                                    .frame(width: 24, height: 24)
                                Image(systemName: "figure.run")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(Color(red: 0.0, green: 0.55, blue: 1.0))
                            }

                            Text("MAIN RUN")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Color(red: 0.0, green: 0.55, blue: 1.0))

                            Text("•")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)

                            Text(cleanMainRunDurationFormatted(session: session).uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Color(red: 0.0, green: 0.55, blue: 1.0))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color(red: 0.0, green: 0.55, blue: 1.0).opacity(0.12))
                                .clipShape(Capsule())
                        }

                        Spacer()

                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            openMainRunReadout(for: session)
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

                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.sessionTitle)
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.primary)

                        Text(session.isTrimmed ? "Active Recovery Flush • Easy Aerobic Intensity" : "Aerobic Consistency • Conversational Pacing")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Integrated 4-Target Grid (Directly inside Main Run!)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        metricCell(
                            icon: "stopwatch.fill",
                            title: "Duration",
                            value: cleanMainRunDurationFormatted(session: session),
                            color: .secondary
                        )
                        metricCell(
                            icon: preferredWorkoutIsIndoor ? "figure.run.square.stack" : "figure.run",
                            title: preferredWorkoutIsIndoor ? "Belt Pace" : "Pace",
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

                    if preferredWorkoutIsIndoor {
                        HStack(spacing: 5) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.purple)
                            Text(
                                session.mainRunDrillId == .hillBounds
                                ? "Treadmill: Set 4–6% incline on surges • Launches as Indoor Run on Watch"
                                : "Treadmill: Set 0.5–1.0% incline • Focus on HR & Cadence over wrist pace"
                            )
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 1)
                    }

                    // Main Run continuous segmented phase bar
                    VStack(alignment: .leading, spacing: 4) {
                        GeometryReader { geo in
                            HStack(spacing: 2) {
                                ForEach(mainPhases) { phase in
                                    let ratio = CGFloat(phase.durationSeconds) / CGFloat(totalMainDuration)
                                    let w = max(4, (geo.size.width - CGFloat(mainPhases.count - 1) * 2) * ratio)
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(phaseColor(phase.kind))
                                        .frame(width: w, height: 4)
                                }
                            }
                        }
                        .frame(height: 4)

                        Text(drillStructureSummary(drill: mainRunDrill))
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.top, 2)
                }
                .padding(12)
                .background(Color(UIColor.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground).opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color(UIColor.separator).opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
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
        VStack(alignment: .leading, spacing: 14) {
            // 1. Session Overline, Environment Toggle & Target Goal Badge
            HStack(spacing: 8) {
                Label("TODAY'S WORKOUT", systemImage: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(red: 0.0, green: 0.75, blue: 0.65))

                Spacer()

                // Outdoor / Indoor (Treadmill) Quick Toggle
                Button {
                    preferredWorkoutIsIndoor.toggle()
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: preferredWorkoutIsIndoor ? "figure.run.square.stack" : "sun.max.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(preferredWorkoutIsIndoor ? "Indoor" : "Outdoor")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(preferredWorkoutIsIndoor ? .purple : .blue)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background((preferredWorkoutIsIndoor ? Color.purple : Color.blue).opacity(0.12))
                    .clipShape(Capsule())
                }
                .accessibilityLabel(preferredWorkoutIsIndoor ? "Indoor Treadmill Mode, tap to switch to Outdoor" : "Outdoor Mode, tap to switch to Indoor Treadmill")

                Text(session.targetGoal)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(UIColor.tertiarySystemGroupedBackground))
                    .clipShape(Capsule())
            }

            // 2. Coach Directive & Rationale (No duplicate workout title!)
            Text(session.groundedRationale)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            // 3. Pre-Run Primer Card (Stage 1)
            preRunPrimerSection(session: session)

            // 4. Main Run Card (Stage 2 — matching visual structure)
            mainRunSection(session: session)
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

    // MARK: - Pre-Run Primer Subcard (Stage 1)

    private func preRunPrimerSection(session: PrescribedDailySession) -> some View {
        let preRunDrill = PreRunDrill(
            id: session.primerDrillId,
            previousCadence: session.cadenceFloor,
            targetCadence: session.primerTargetCadence,
            readinessState: session.isTrimmed ? .acuteFatigue : .productive,
            isIndoor: preferredWorkoutIsIndoor
        )
        let phases = preRunDrill.generatePhases()
        let completedPrimer = session.completedPrimerRun
        let effectiveCompleted = (completedPrimer != nil) || isDrillCompleted

        return VStack(alignment: .leading, spacing: 10) {
            // Overline: Badge & Duration on left, Action on right
            HStack(alignment: .center, spacing: 8) {
                Label(
                    effectiveCompleted ? "PRE-RUN PRIMER COMPLETE" : "PRE-RUN PRIMER",
                    systemImage: effectiveCompleted ? "checkmark.circle.fill" : "figure.run"
                )
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(effectiveCompleted ? .green : Color(red: 0.0, green: 0.8, blue: 0.65))

                if let completedPrimer {
                    Text("Target Met")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.14))
                        .clipShape(Capsule())
                } else {
                    Text(cleanPrimerDuration(session: session))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(red: 0.0, green: 0.8, blue: 0.65))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color(red: 0.0, green: 0.8, blue: 0.65).opacity(0.12))
                        .clipShape(Capsule())
                }

                Spacer()

                if let completedPrimer,
                   let matchedRun = runRecords.first(where: { $0.id == completedPrimer.id }) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        selectedRunForDetail = matchedRun
                    } label: {
                        HStack(spacing: 3) {
                            Text("Details")
                                .font(.caption.bold())
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(Color.green.opacity(0.15))
                        .foregroundColor(.green)
                        .clipShape(Capsule())
                    }
                } else {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        openPrimerReadout(for: session)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: effectiveCompleted ? "arrow.counterclockwise" : "play.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text(effectiveCompleted ? "Review" : "Start")
                                .font(.caption.bold())
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(effectiveCompleted ? Color(UIColor.secondarySystemFill) : Color.primary)
                        .foregroundColor(effectiveCompleted ? .primary : Color(UIColor.systemBackground))
                        .clipShape(Capsule())
                    }
                }
            }

            // Title and Target Details (Full width, no truncation!)
            VStack(alignment: .leading, spacing: 2) {
                Text(completedPrimer?.workoutType ?? session.primerDrillTitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.primary)

                if let completedPrimer {
                    Text("Completed • \(completedPrimer.durationFormatted) • \(completedPrimer.distanceFormatted)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundColor(.green)
                } else {
                    Text("Target \(cleanPrimerTarget(session: session))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }

            // Continuous segmented rhythm bar
            let totalDuration = max(1, phases.reduce(0) { $0 + $1.durationSeconds })
            VStack(alignment: .leading, spacing: 4) {
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

                Text(drillStructureSummary(drill: preRunDrill))
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.top, 2)
        }
        .padding(12)
        .background(Color(UIColor.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Main Run Subcard (Stage 2 — Symmetrical Structure)

    private func mainRunSection(session: PrescribedDailySession) -> some View {
        let mainRunDrill = PreRunDrill(
            id: session.mainRunDrillId,
            previousCadence: session.cadenceFloor,
            targetCadence: session.mainRunDrillId.isHeartRateTargeted ? nil : "\(session.cadenceFloor)-\(session.cadenceFloor + 6)",
            duration: DrillDuration(rawValue: session.mainRunDurationMinutes) ?? .thirtyMinutes,
            readinessState: session.isTrimmed ? .acuteFatigue : .productive,
            isIndoor: preferredWorkoutIsIndoor
        )
        let phases = mainRunDrill.generatePhases()

        return VStack(alignment: .leading, spacing: 10) {
            // Overline: Badge on left, Action on right
            HStack(alignment: .center, spacing: 8) {
                Label(
                    session.completedPrimerRun != nil ? "NEXT UP: MAIN RUN" : "MAIN RUN",
                    systemImage: "figure.run"
                )
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color(red: 0.0, green: 0.55, blue: 1.0))

                Text(cleanMainRunDurationFormatted(session: session).uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(red: 0.0, green: 0.55, blue: 1.0))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color(red: 0.0, green: 0.55, blue: 1.0).opacity(0.12))
                    .clipShape(Capsule())

                Spacer()

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    openMainRunReadout(for: session)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text("Start")
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Color.primary)
                    .foregroundColor(Color(UIColor.systemBackground))
                    .clipShape(Capsule())
                }
            }

            // Title and Subtitle (Full width, no truncation!)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.sessionTitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.primary)

                Text(session.isTrimmed ? "Active Recovery Flush • Easy Aerobic Intensity" : "Aerobic Consistency • Conversational Pacing")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Core Targets Grid (Formatted with ample room, zero truncation!)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                metricCell(
                    icon: "stopwatch.fill",
                    title: "Duration",
                    value: cleanMainRunDurationFormatted(session: session),
                    color: .secondary
                )
                metricCell(
                    icon: preferredWorkoutIsIndoor ? "figure.run.square.stack" : "figure.run",
                    title: preferredWorkoutIsIndoor ? "Belt Pace" : "Pace",
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

            if preferredWorkoutIsIndoor {
                HStack(spacing: 5) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.purple)
                    Text(
                        session.mainRunDrillId == .hillBounds
                        ? "Treadmill: Set 4–6% incline on surges • Launches as Indoor Run on Watch"
                        : "Treadmill: Set 0.5–1.0% incline • Focus on HR & Cadence over wrist pace"
                    )
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 1)
            }

            // Continuous segmented phase bar
            let totalDuration = max(1, phases.reduce(0) { $0 + $1.durationSeconds })
            VStack(alignment: .leading, spacing: 4) {
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

                Text(drillStructureSummary(drill: mainRunDrill))
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.top, 2)
        }
        .padding(12)
        .background(Color(UIColor.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func drillStructureSummary(drill: PreRunDrill) -> String {
        var parts: [String] = []
        let warmUp = Int(drill.warmUpDurationMinutes.rounded())
        if warmUp > 0 {
            parts.append("\(warmUp)m Warm-up")
        }
        let spec = drill.intervalSpec
        if let rec = spec.recoverySeconds, spec.iterations > 1 {
            let recLabel = spec.isWalk ? "walk" : "jog"
            parts.append("\(spec.iterations)x (\(spec.workSeconds)s work / \(rec)s \(recLabel))")
        } else if drill.id == .zone2Run || spec.iterations == 1 {
            let workMins = max(1, Int((Double(spec.workSeconds) / 60.0).rounded()))
            parts.append("\(workMins)m Steady")
        }
        let coolDown = Int(drill.coolDownDurationMinutes.rounded())
        if coolDown > 0 {
            parts.append("\(coolDown)m Cool-down")
        }
        return parts.joined(separator: " • ")
    }

    private func metricCell(icon: String, title: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 16)

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
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func sendMainRunToWatch(session: PrescribedDailySession) {
        Task {
            let bridge = WorkoutBridge()
            let mainDrillId = session.mainRunDrillId
            let dto = DrillPrescriptionDTO(
                title: session.sessionTitle,
                preRunDrillId: mainDrillId.rawValue,
                purpose: session.groundedRationale,
                targetCadence: mainDrillId.isHeartRateTargeted ? nil : "\(session.cadenceFloor)-\(session.cadenceFloor + 6)",
                previousCadence: session.cadenceFloor,
                durationMinutes: session.mainRunDurationMinutes,
                hapticMode: "On",
                readinessState: session.isTrimmed ? ReadinessState.acuteFatigue.rawValue : nil,
                isIndoor: preferredWorkoutIsIndoor
            )
            let envLabel = preferredWorkoutIsIndoor ? "Indoor" : "Outdoor"
            do {
                try await bridge.scheduleDrill(dto: dto)
                watchExportSuccessMessage = "\(session.sessionTitle) (\(envLabel)) sent to Apple Watch via WorkoutKit."
                showingExportAlert = true
            } catch {
                watchExportSuccessMessage = "Scheduled locally (\(envLabel)). Open Workout app on your Apple Watch to start."
                showingExportAlert = true
            }
        }
    }

    private func cleanPrimerDuration(session: PrescribedDailySession) -> String {
        var duration = session.primerPhasesDuration
            .replacingOccurrences(of: " drill", with: "")
        if let parenRange = duration.range(of: " (Trimmed") {
            duration = String(duration[..<parenRange.lowerBound])
        }
        return duration.uppercased()
    }

    private func cleanPrimerTarget(session: PrescribedDailySession) -> String {
        session.primerTargetCadence
    }

    private func cleanMainRunDurationFormatted(session: PrescribedDailySession) -> String {
        let mainRunDrill = PreRunDrill(
            id: session.mainRunDrillId,
            previousCadence: session.cadenceFloor,
            targetCadence: session.mainRunDrillId.isHeartRateTargeted ? nil : "\(session.cadenceFloor)-\(session.cadenceFloor + 6)",
            duration: DrillDuration(rawValue: session.mainRunDurationMinutes) ?? .thirtyMinutes,
            readinessState: session.isTrimmed ? .acuteFatigue : .productive,
            isIndoor: preferredWorkoutIsIndoor
        )
        let phases = mainRunDrill.generatePhases()
        let totalMinutes = phases.reduce(0) { $0 + $1.durationSeconds } / 60
        let minutes = totalMinutes > 0 ? totalMinutes : session.mainRunDurationMinutes
        return "\(minutes) Min"
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

    private func openPrimerReadout(for session: PrescribedDailySession) {
        let dto = DrillPrescriptionDTO(
            title: session.primerDrillTitle,
            preRunDrillId: session.primerDrillId.rawValue,
            purpose: session.groundedRationale,
            targetCadence: session.primerTargetCadence,
            previousCadence: session.cadenceFloor,
            durationMinutes: session.primerDrillId.defaultDuration.rawValue,
            hapticMode: "On",
            readinessState: session.isTrimmed ? ReadinessState.acuteFatigue.rawValue : nil,
            isIndoor: preferredWorkoutIsIndoor
        )
        let readiness = ReadinessEvaluator.assess(runRecords: runRecords)
        activeReadoutItem = ActiveDrillReadoutItem.adaptive(
            dto: dto,
            readiness: readiness
        )
    }

    private func openMainRunReadout(for session: PrescribedDailySession) {
        let mainDrillId = session.mainRunDrillId
        let dto = DrillPrescriptionDTO(
            title: session.sessionTitle,
            preRunDrillId: mainDrillId.rawValue,
            purpose: session.groundedRationale,
            targetCadence: mainDrillId.isHeartRateTargeted ? nil : "\(session.cadenceFloor)-\(session.cadenceFloor + 6)",
            previousCadence: session.cadenceFloor,
            durationMinutes: session.mainRunDurationMinutes,
            hapticMode: "On",
            readinessState: session.isTrimmed ? ReadinessState.acuteFatigue.rawValue : nil,
            isIndoor: preferredWorkoutIsIndoor
        )
        let readiness = ReadinessEvaluator.assess(runRecords: runRecords)
        activeReadoutItem = ActiveDrillReadoutItem.adaptive(
            dto: dto,
            readiness: readiness,
            customCoachingTip: session.groundedRationale
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
        let patterns = [
            " 16 km", " 14 km", " 10 km", " 8 km", " 7 km", " 6 km", " 5 km",
            " 10 mi", " 8.5 mi", " 6 mi", " 5 mi", " 4.5 mi", " 3.5 mi", " 3 mi",
            " 50m", " 45m", " 40m", " 35m", " 30m", " 25m", " 20m"
        ]
        for pattern in patterns where title.hasSuffix(pattern) {
            let name = String(title.dropLast(pattern.count))
            let detail = pattern.trimmingCharacters(in: .whitespaces)
            return (name, detail)
        }
        return (title, nil)
    }

    private func microcycleSection(microcycle: [MicrocycleDay]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("UPCOMING SCHEDULE")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(microcycle.enumerated()), id: \.element.id) { index, day in
                    HStack(spacing: 8) {
                        Image(systemName: day.iconName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(day.isRestDay ? .secondary : Color(red: 0.0, green: 0.55, blue: 1.0))
                            .frame(width: 20, alignment: .center)

                        Text(day.dayLabel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(day.isRestDay ? .secondary : .primary)
                            .frame(width: day.dayLabel == "Tomorrow" ? nil : 36, alignment: .leading)
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
