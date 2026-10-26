import SwiftUI
import UIKit
import SwiftData
import HealthKit
import WorkoutKit

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \RunRecord.date, order: .reverse) private var runRecords: [RunRecord]

    @AppStorage("useMetricSystem") private var useMetricSystem: Bool = Locale.current.measurementSystem == .metric
    @AppStorage("minimumRunDistance") private var minimumRunDistance: Double = 1.0
    @AppStorage("trainingGoal") private var trainingGoal: String = "Base Building"

    @State private var isSyncing: Bool = true
    @State private var selectedFilter: String?

    @AppStorage("dashboardTimeRange") private var timeRange: String = "7 Days"
    @AppStorage("lastBaselineChangeTimestamp") private var lastBaselineChangeTimestamp: Double = 0
    @AppStorage("lastWatchExportTimestamp") private var lastWatchExportTimestamp: Double = 0
    @AppStorage("lastExportedDrillId") private var lastExportedDrillId: String = ""

    @AppStorage("cachedHeadline_7Day") private var cachedHeadline7Day: String = ""
    @AppStorage("cachedBody_7Day") private var cachedBody7Day: String = ""

    @AppStorage("cachedHeadline_30Day") private var cachedHeadline30Day: String = ""
    @AppStorage("cachedBody_30Day") private var cachedBody30Day: String = ""

    @AppStorage("cachedHeadline_AllTime") private var cachedHeadlineAllTime: String = ""
    @AppStorage("cachedBody_AllTime") private var cachedBodyAllTime: String = ""

    @AppStorage("lastInsightFingerprint") private var lastInsightFingerprint: String = ""

    @State private var isFetchingInsight = false
    @State private var showingAnalystChat = false
    @State private var showingTrendsExplainer = false

    private var timeRangeRuns: [RunRecord] {
        let now = Date()
        let activeRuns = runRecords.filter { !$0.isDeleted && $0.modelContext != nil }
        if timeRange == "7 Days", let limit = Calendar.current.date(byAdding: .day, value: -7, to: now) {
            return activeRuns.filter { $0.date >= limit }
        } else if timeRange == "30 Days", let limit = Calendar.current.date(byAdding: .day, value: -30, to: now) {
            return activeRuns.filter { $0.date >= limit }
        }
        return activeRuns
    }

    private var filteredRunRecords: [RunRecord] {
        let minDistanceInMeters = useMetricSystem ? (minimumRunDistance * 1000.0) : (minimumRunDistance * 1609.344)
        var filtered = timeRangeRuns.filter { $0.totalDistanceMeters >= (minDistanceInMeters - 0.01) }

        if let filter = selectedFilter {
            filtered = filtered.filter { $0.matchesFilter(filter) }
        }
        return filtered
    }

    var baselineCadence: Int? {
        let runs = timeRangeRuns.filter { $0.workingAvgCadence > 0 }
        guard !runs.isEmpty else { return nil }
        let totalDuration = runs.map(\.duration).reduce(0, +)
        guard totalDuration > 0 else {
            return Int(runs.map(\.workingAvgCadence).reduce(0, +)) / runs.count
        }
        return Int(runs.map { $0.workingAvgCadence * $0.duration }.reduce(0, +) / totalDuration)
    }

    var baselinePace: Double? {
        let runs = timeRangeRuns.filter { $0.workingAvgPace > 0 }
        guard !runs.isEmpty else { return nil }
        let totalDuration = runs.map(\.duration).reduce(0, +)
        guard totalDuration > 0 else {
            return runs.map(\.workingAvgPace).reduce(0, +) / Double(runs.count)
        }
        return runs.map { $0.workingAvgPace * $0.duration }.reduce(0, +) / totalDuration
    }

    var canonicalAthleteBaselineCadence: Int? {
        SessionSynthesisEngine.computeWeightedBaselineStats(from: runRecords, priorTo: Date()).map { Int($0.avgCadence.rounded()) }
    }

    var baselineHeartRate: Int? {
        let runs = timeRangeRuns.filter { $0.workingAvgHeartRate > 0 }
        guard !runs.isEmpty else { return nil }
        let totalDuration = runs.map(\.duration).reduce(0, +)
        guard totalDuration > 0 else {
            return Int(runs.map(\.workingAvgHeartRate).reduce(0, +)) / runs.count
        }
        return Int(runs.map { Double($0.workingAvgHeartRate) * $0.duration }.reduce(0, +) / totalDuration)
    }

    var canonicalAthleteBaselinePace: Double? {
        SessionSynthesisEngine.computeWeightedBaselineStats(from: runRecords, priorTo: Date())?.avgPace
    }

    private var previousBaselineCadence: Int? {
        let calendar = Calendar.current
        let now = Date()
        let previousRuns: [RunRecord]
        if timeRange == "7 Days" {
            guard let start = calendar.date(byAdding: .day, value: -14, to: now),
                  let end = calendar.date(byAdding: .day, value: -7, to: now) else { return nil }
            previousRuns = runRecords.filter { $0.date >= start && $0.date < end && $0.workingAvgCadence > 0 }
        } else if timeRange == "30 Days" {
            guard let start = calendar.date(byAdding: .day, value: -60, to: now),
                  let end = calendar.date(byAdding: .day, value: -30, to: now) else { return nil }
            previousRuns = runRecords.filter { $0.date >= start && $0.date < end && $0.workingAvgCadence > 0 }
        } else {
            return nil
        }
        guard !previousRuns.isEmpty else { return nil }
        let totalDuration = previousRuns.map(\.duration).reduce(0, +)
        guard totalDuration > 0 else {
            return Int(previousRuns.map(\.workingAvgCadence).reduce(0, +)) / previousRuns.count
        }
        return Int(previousRuns.map { $0.workingAvgCadence * $0.duration }.reduce(0, +) / totalDuration)
    }

    private var previousBaselinePace: Double? {
        let calendar = Calendar.current
        let now = Date()
        let previousRuns: [RunRecord]
        if timeRange == "7 Days" {
            guard let start = calendar.date(byAdding: .day, value: -14, to: now),
                  let end = calendar.date(byAdding: .day, value: -7, to: now) else { return nil }
            previousRuns = runRecords.filter { $0.date >= start && $0.date < end && $0.workingAvgPace > 0 }
        } else if timeRange == "30 Days" {
            guard let start = calendar.date(byAdding: .day, value: -60, to: now),
                  let end = calendar.date(byAdding: .day, value: -30, to: now) else { return nil }
            previousRuns = runRecords.filter { $0.date >= start && $0.date < end && $0.workingAvgPace > 0 }
        } else {
            return nil
        }
        guard !previousRuns.isEmpty else { return nil }
        let totalDuration = previousRuns.map(\.duration).reduce(0, +)
        guard totalDuration > 0 else {
            return previousRuns.map(\.workingAvgPace).reduce(0, +) / Double(previousRuns.count)
        }
        return previousRuns.map { $0.workingAvgPace * $0.duration }.reduce(0, +) / totalDuration
    }

    private var trajectoryAssessment: SessionSynthesisEngine.TrajectoryAssessment {
        SessionSynthesisEngine.evaluate30DayTrajectory(from: timeRangeRuns, now: Date())
    }

    private var isTrajectoryEaseUp: Bool {
        timeRange == "30 Days" && trajectoryAssessment.verdict == .easeUp
    }

    private var workoutDensityTier: String {
        let uniqueDays = Set(timeRangeRuns.map { Calendar.current.startOfDay(for: $0.date) })
        let count = uniqueDays.count
        if count == 0 { return "—" }
        switch timeRange {
        case "7 Days":
            if count <= 2 { return "Low" }
            if count <= 3 { return "Moderate" }
            if count <= 5 { return "Optimal" }
            return "High"
        default: // 30 Days
            if isTrajectoryEaseUp && count >= 14 {
                return "High"
            }
            if count <= 6 { return "Low" }
            if count <= 12 { return "Moderate" }
            if count <= 18 { return "Optimal" }
            return "High"
        }
    }

    // Extract unique classifications and drill names for filter chips
    var availableFilters: [String] {
        var classifications = Set<String>()
        var drills = Set<String>()

        for run in runRecords where !run.isDeleted && run.modelContext != nil {
            classifications.insert(run.normalizedClassification)
            if let drillName = run.prescribedDrillName {
                drills.insert(drillName)
            }
        }

        let canonicalOrder = [
            "Easy Run", "Steady Effort", "Tempo Run", "Intervals",
            "Long Run", "Progression Run", "Recovery Run", "Fartlek",
            "Hill Repeats", "Urban Traffic"
        ]

        let sortedClassifications = canonicalOrder.filter { classifications.contains($0) }
            + classifications.filter { !canonicalOrder.contains($0) }.sorted()
        let sortedDrills = drills.sorted()

        return sortedClassifications + sortedDrills
    }

    var onSync: ((Bool) async -> Void)?

    @State private var globalVO2Max: Double?
    @State private var baselineVO2Max: Double?

    @ViewBuilder
    private var filterControlsSection: some View {
        HStack(spacing: 10) {
            Picker("Time Range", selection: $timeRange) {
                Text("7 Days").tag("7 Days")
                Text("30 Days").tag("30 Days")
            }
            .pickerStyle(.segmented)
            .onChange(of: timeRange) { _, _ in
                UISelectionFeedbackGenerator().selectionChanged()
            }

            Menu {
                Section("Minimum Distance") {
                    ForEach([0.5, 1.0, 2.0, 3.0, 5.0, 10.0], id: \.self) { dist in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            minimumRunDistance = dist
                        } label: {
                            HStack {
                                Text("\(String(format: "%.1f", dist)) \(useMetricSystem ? "km" : "mi")")
                                if abs(minimumRunDistance - dist) < 0.05 {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.left.and.right")
                        .font(.system(size: 11, weight: .bold))
                    Text("≥ \(String(format: "%.1f", minimumRunDistance)) \(useMetricSystem ? "km" : "mi")")
                        .font(.caption2.bold())
                        .monospacedDigit()
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(UIColor.secondarySystemFill))
                .clipShape(Capsule())
            }
            .accessibilityLabel("Filter by minimum distance: \(String(format: "%.1f", minimumRunDistance)) \(useMetricSystem ? "km" : "mi")")
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private var dashboardRunnerProfile: RunnerProfile {
        RunnerProfile.compute(from: runRecords, trainingGoal: trainingGoal, now: Date())
    }

    private var dashboardRecoveryTimeline: RecoveryTimeline {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        let recent = runRecords.filter { $0.date >= cutoff }
        let snapshots = recent.map(ReadinessRunSnapshot.init(run:))
        let readiness = ReadinessEvaluator.assess(runRecords: runRecords)
        return RecoveryTimeline.build(runs: snapshots, readiness: readiness, now: Date())
    }

    private var isTodayCompleted: Bool {
        let cal = Calendar.current
        let todayRuns = runRecords.filter { cal.isDateInToday($0.date) && !$0.isDeleted }
        return SessionSynthesisEngine.isWorkoutDayComplete(runs: todayRuns)
    }

    private var currentDailyTrainingState: DailyTrainingState {
        let profile = dashboardRunnerProfile
        return DailyTrainingStateStore.shared.resolveState(
            runRecords: runRecords,
            activeGoal: trainingGoal,
            experienceLevel: profile.experienceLevel,
            useMetric: useMetricSystem,
            userHeightCm: profile.userHeightCm
        )
    }

    private func targetPill(text: String, color: Color = .purple) -> some View {
        Text(text)
            .font(.caption.bold())
            .monospacedDigit()
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func directivePills(for state: DailyTrainingState) -> some View {
        let session = state.activeSession
        let isCompleted = state.isTodayCompleted
        let hasPace = session.paceBand != "No Pacing Target" && session.intent != .fullRest

        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                if isCompleted {
                    targetPill(text: "Today: Done ✓", color: .green)
                    let tomorrowText = session.intent == .fullRest ? "Rest" : session.durationBand
                    targetPill(text: "Tomorrow: \(tomorrowText)", color: .purple)
                    if hasPace {
                        targetPill(text: "Pace: \(session.paceBand)", color: Color(red: 0.0, green: 0.55, blue: 1.0))
                    }
                } else if session.intent == .fullRest {
                    targetPill(text: "Full Rest Day", color: .green)
                    targetPill(text: "Rest & Structural Recovery", color: .purple)
                } else if session.intent == .recoveryFlush {
                    targetPill(text: "Active Flush", color: .teal)
                    targetPill(text: session.durationBand, color: .purple)
                    if hasPace {
                        targetPill(text: "Pace: \(session.paceBand)", color: Color(red: 0.0, green: 0.55, blue: 1.0))
                    }
                    targetPill(text: session.hrCap, color: Color(red: 1.0, green: 0.22, blue: 0.55))
                } else {
                    targetPill(text: session.durationBand, color: .purple)
                    if hasPace {
                        targetPill(text: "Pace: \(session.paceBand)", color: Color(red: 0.0, green: 0.55, blue: 1.0))
                    }
                    targetPill(text: session.hrCap, color: Color(red: 1.0, green: 0.22, blue: 0.55))
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if isCompleted {
                        targetPill(text: "Today: Done ✓", color: .green)
                        let tomorrowText = session.intent == .fullRest ? "Rest" : session.durationBand
                        targetPill(text: "Tomorrow: \(tomorrowText)", color: .purple)
                    } else if session.intent == .fullRest {
                        targetPill(text: "Full Rest Day", color: .green)
                        targetPill(text: "Rest & Structural Recovery", color: .purple)
                    } else if session.intent == .recoveryFlush {
                        targetPill(text: "Active Flush", color: .teal)
                        targetPill(text: session.durationBand, color: .purple)
                    } else {
                        targetPill(text: session.durationBand, color: .purple)
                        if hasPace {
                            targetPill(text: "Pace: \(session.paceBand)", color: Color(red: 0.0, green: 0.55, blue: 1.0))
                        }
                    }
                }
                if isCompleted || session.intent == .fullRest {
                    if hasPace {
                        targetPill(text: "Pace: \(session.paceBand)", color: Color(red: 0.0, green: 0.55, blue: 1.0))
                    }
                } else {
                    targetPill(text: session.hrCap, color: Color(red: 1.0, green: 0.22, blue: 0.55))
                }
            }
        }
    }

    @ViewBuilder
    private var aiInsightCard: some View {
        let is7Day = timeRange == "7 Days"
        let iconName = is7Day ? "sparkles" : "chart.line.uptrend.xyaxis"
        let iconColor: Color = is7Day ? .purple : .orange
        let cardTitle = is7Day ? "AI COACH • TODAY'S DIRECTIVE" : "AI Coach • 30-Day Trends"
        let cardSubtitle = is7Day ? "Readiness & Target Guidance" : "Aerobic Adaptation & Efficiency"
        let loadingText = is7Day ? "Analyzing readiness & recovery..." : "Analyzing 30-day trends..."

        VStack(alignment: .leading, spacing: 10) {
            let headline = currentHeadline()
            let bodyText = currentBody()

            if isFetchingInsight && headline.isEmpty {
                AnimatedLoadingView(
                    text: loadingText,
                    isHorizontal: true,
                    imageSize: 18,
                    textFont: .subheadline,
                    textColor: .secondary,
                    iconColor: .primary,
                    spacing: 8
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: iconName)
                        .foregroundColor(iconColor)
                        .font(is7Day ? .subheadline.bold() : .headline)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(cardTitle)
                            .font(is7Day ? .caption.bold() : .subheadline.bold())
                            .foregroundColor(is7Day ? .purple : .primary)
                        if !is7Day {
                            Text(cardSubtitle)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showingTrendsExplainer = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Learn more about this insight")
                }

                if is7Day {
                    let displayHeadline = headline.isEmpty ? "Easy Recovery Needed" : headline
                    Text(displayHeadline)
                        .font(.title3.bold())
                        .foregroundColor(.primary)

                    directivePills(for: currentDailyTrainingState)

                    let defaultPlaceholder = "Complete more runs this week to evaluate acute fatigue and recovery trends."
                    Text(bodyText.isEmpty ? defaultPlaceholder : bodyText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                } else {
                    let displayHeadline = headline.isEmpty ? "Aerobic Base Stabilizing" : headline
                    Text(displayHeadline)
                        .font(.title3.bold())
                        .foregroundColor(.primary)

                    HStack(spacing: 6) {
                        Text("Goal: \(trainingGoal)")
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.12))
                            .foregroundColor(.orange)
                            .clipShape(Capsule())

                        if isTrajectoryEaseUp {
                            Text("Cumulative Strain")
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.red.opacity(0.12))
                                .foregroundColor(.red)
                                .clipShape(Capsule())
                        } else {
                            Text("Aerobic Base Expanding")
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.12))
                                .foregroundColor(.green)
                                .clipShape(Capsule())
                        }
                    }

                    let defaultPlaceholder = "Complete more runs over the next 30 days to measure structural aerobic adaptation."
                    Text(bodyText.isEmpty ? defaultPlaceholder : bodyText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: 16, padding: 16, accentColor: is7Day ? .purple : .orange)
        .sheet(isPresented: $showingTrendsExplainer) {
            let is7Day = timeRange == "7 Days"
            let headline = currentHeadline()
            let bodyText = currentBody()
            GlassBoxExplainerSheet(
                title: is7Day ? "Today's Training Directive" : "30-Day Aerobic Profile",
                categoryBadge: is7Day ? "Acute Readiness" : "Longitudinal Adaptation",
                whatSummary: headline.isEmpty
                    ? (is7Day ? "Daily training directive calculated from acute fatigue and recovery balance." : "Your rolling 30-day baseline captures aerobic base stabilization.")
                    : headline,
                whyItMatters: bodyText.isEmpty
                    ? "Consistent volume at conversational heart rates establishes capillary density and neuromuscular economy while protecting joint health."
                    : bodyText,
                howItWorks: is7Day
                    ? "Evaluates your last 48-hour volume against your 28-day chronic workload using Banister impulse-response modeling to lock in today's safe duration and pace bands."
                    : "Calculates rolling 30-day time-locked medians across pause-trimmed Working Pace, heart rate, and cadence to determine your physiological trajectory.",
                formula: is7Day
                    ? "ACWR = Acute Load (7D) ÷ Chronic Load (28D)"
                    : "Efficiency Factor = Speed (m/s) ÷ (Heart Rate - Resting HR)",
                targetRange: is7Day
                    ? "ACWR: 0.8–1.3 (Optimal Zone) • \(currentDailyTrainingState.activeSession.hrCap)"
                    : "Cadence Floor: ≥ \(dashboardRunnerProfile.heightAdjustedCadenceFloor) SPM • Stable or Rising Efficiency Factor"
            )
        }
        .onAppear {
            if timeRange != "7 Days" && timeRange != "30 Days" {
                timeRange = "7 Days"
            }
            checkAndFetchInsight()
        }
        .onChange(of: timeRange) {
            checkAndFetchInsight()
            refreshBaselineVO2Max()
            lastBaselineChangeTimestamp = Date().timeIntervalSince1970
            autoSyncStaleWatchDrillIfNeeded()
        }
        .onChange(of: trainingGoal) {
            checkAndFetchInsight()
            DailyTrainingStateStore.shared.invalidate()
        }
        .onChange(of: minimumRunDistance) {
            lastBaselineChangeTimestamp = Date().timeIntervalSince1970
            autoSyncStaleWatchDrillIfNeeded()
        }
    }

    private func sanitizeCoachingText(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasSuffix("}") || cleaned.hasSuffix("{") || cleaned.hasSuffix("\"") {
            cleaned = String(cleaned.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cleaned
    }

    private func currentHeadline() -> String {
        let raw: String
        switch timeRange {
        case "7 Days": raw = cachedHeadline7Day
        case "30 Days": raw = cachedHeadline30Day
        case "All Time": raw = cachedHeadlineAllTime
        default: raw = ""
        }
        return sanitizeCoachingText(raw)
    }

    private func currentBody() -> String {
        let raw: String
        switch timeRange {
        case "7 Days": raw = cachedBody7Day
        case "30 Days": raw = cachedBody30Day
        case "All Time": raw = cachedBodyAllTime
        default: raw = ""
        }
        return sanitizeCoachingText(raw)
    }

    private func checkAndFetchInsight() {
        guard timeRange != "All Time" else {
            isFetchingInsight = false
            return
        }
        let currentFingerprint = "\(timeRange)_\(trainingGoal)_\(DailyTrainingStateStore.computeFingerprint(runs: runRecords))"
        if currentFingerprint != lastInsightFingerprint {
            // Invalidate cache
            cachedHeadline7Day = ""
            cachedBody7Day = ""
            cachedHeadline30Day = ""
            cachedBody30Day = ""
            cachedHeadlineAllTime = ""
            cachedBodyAllTime = ""
            lastInsightFingerprint = currentFingerprint
        }

        if currentHeadline().isEmpty || currentBody().isEmpty {
            fetchInsight()
        }
    }

    private func fetchInsight() {
        guard timeRange != "All Time" else { return }
        guard !isFetchingInsight else { return }
        guard !timeRangeRuns.isEmpty else { return }
        isFetchingInsight = true

        let avgPace = timeRangeRuns.map(\.workingAvgPace).reduce(0, +) / Double(timeRangeRuns.count)
        let validHRRuns = timeRangeRuns.filter { $0.workingAvgHeartRate > 0 }
        let avgHR = validHRRuns.isEmpty ? 0 : validHRRuns.map(\.workingAvgHeartRate).reduce(0, +) / Double(validHRRuns.count)
        let validCadenceRuns = timeRangeRuns.filter { $0.workingAvgCadence > 0 }
        let avgCadence = validCadenceRuns.isEmpty ? 0 : validCadenceRuns.map(\.workingAvgCadence).reduce(0, +) / Double(validCadenceRuns.count)
        let avgCV = timeRangeRuns.map(\.paceCV).reduce(0, +) / Double(timeRangeRuns.count)
        let avgSlope = timeRangeRuns.map(\.paceSlope).reduce(0, +) / Double(timeRangeRuns.count)
        let zone4Sum = timeRangeRuns.map(\.percentZone4).reduce(0, +) / Double(timeRangeRuns.count)

        let paceContext = PaceFormatter.formatPace(secondsPerKilometer: avgPace)
        let hrContext = avgHR > 0 ? "\(Int(avgHR)) BPM" : "No heart rate data"
        let cadenceContext = avgCadence > 0 ? "\(Int(avgCadence)) SPM" : "No cadence data"
        let zone4Context = "\(Int(zone4Sum * 100))% Zone 4"
        let cvContext = String(format: "%.3f", avgCV)
        let slopeContext = String(format: "%.3f", avgSlope)
        let stageContext = "Competitor"

        let targetTimeRange = timeRange
        let directiveContext: String
        let efficiencyContext: String
        let fatigueContext: String
        let verticalOscillationContext: String

        if targetTimeRange == "7 Days" {
            // 7-DAY VIEW: Tactical Coach (Single Source of Truth: DailyTrainingState)
            let activeSession = currentDailyTrainingState.activeSession
            switch activeSession.intent {
            case .fullRest:
                directiveContext = "PRIORITY_FULL_REST: Training state is locked to FULL REST (0 minutes running). RATIONALE: \(activeSession.groundedRationale). Direct the runner clearly to take a full rest day with zero running to let their musculoskeletal system adapt toward their \(trainingGoal) goal."
            case .recoveryFlush:
                directiveContext = "PRIORITY_RECOVERY_FLUSH: Training state is locked to ACTIVE RECOVERY FLUSH (\(activeSession.durationBand), \(activeSession.paceBand), \(activeSession.hrCap)). RATIONALE: \(activeSession.groundedRationale). Direct the runner to keep effort very light and heart rate strictly controlled toward their \(trainingGoal) goal."
            case .train:
                directiveContext = "PRIORITY_TRAIN: Training state is locked to \(activeSession.sessionTitle) (\(activeSession.durationBand), \(activeSession.paceBand)). RATIONALE: \(activeSession.groundedRationale). Guide the runner on target pacing, turnover discipline, and form toward their \(trainingGoal) goal."
            }
            fatigueContext = ""
            efficiencyContext = ""
            verticalOscillationContext = ""
        } else {
            // 30-DAY VIEW: Goal Readiness & Trajectory Analyst
            let assessment = SessionSynthesisEngine.evaluate30DayTrajectory(from: timeRangeRuns, now: Date())
            switch assessment.verdict {
            case .easeUp:
                directiveContext = "TRAJECTORY_EASE_UP: Over the past 30 days, training data indicates cumulative overworking and declining efficiency (aerobic cost is climbing). For their stated goal of \(trainingGoal), tell the runner clearly that they are overworking and need to ease up on volume or intensity so their body can absorb the training and avoid declining instead of improving."
                efficiencyContext = "Efficiency Factor declined over the past month. Cardiac drift and physiological strain accumulating."
            case .onTrack:
                let hrDeltaText = assessment.hrDelta < 0 ? "\(Int(abs(assessment.hrDelta))) BPM lower" : "stable"
                let vrDeltaText = assessment.avgRecentVR > 0 ? ", Vertical Ratio: \(String(format: "%.1f", assessment.avgRecentVR))%" : ""
                directiveContext = "TRAJECTORY_ON_TRACK: Over the past 30 days, aerobic efficiency, cardiac response, and running economy have clearly improved (Efficiency Factor increased by \(String(format: "%.2f", assessment.efDelta)), heart rate at \(paceContext) is \(hrDeltaText)\(vrDeltaText)). Tell the runner clearly that they are solidly on track for their \(trainingGoal) goal and their consistency is paying off."
                efficiencyContext = "Efficiency Factor rose by +\(String(format: "%.2f", assessment.efDelta)) m/beat. Aerobic capacity expanding."
            case .stepItUp:
                directiveContext = "TRAJECTORY_STEP_IT_UP: Over the past 30 days, baseline fitness is steady and well-calibrated, but performance has plateaued. Tell the runner their performances show their body has adapted and they have more to give, encouraging them to step up their training slightly in pace, volume, or quality to chase their \(trainingGoal) goal."
                efficiencyContext = "Efficiency Factor stable at \(String(format: "%.2f", max(1.2, assessment.avgRecentEF))) m/beat."
            }
            if assessment.avgRecentVR > 0 {
                verticalOscillationContext = "Vertical Oscillation: \(String(format: "%.1f", assessment.avgRecentOsc)) cm (VR: \(String(format: "%.1f", assessment.avgRecentVR))%)"
            } else {
                verticalOscillationContext = assessment.avgRecentOsc > 0 ? "Vertical Oscillation: \(String(format: "%.1f", assessment.avgRecentOsc)) cm" : "Vertical form steady"
            }
            fatigueContext = ""
        }

        let runData = AggregateRunDataForAI(
            paceContext: paceContext,
            hrContext: hrContext,
            cadenceContext: cadenceContext,
            zone4Context: zone4Context,
            cvContext: cvContext,
            slopeContext: slopeContext,
            stageContext: stageContext,
            directiveContext: directiveContext,
            efficiencyContext: efficiencyContext,
            fatigueContext: fatigueContext,
            verticalOscillationContext: verticalOscillationContext
        )

        Task {
            do {
                if #available(iOS 26.0, *) {
                    let insight = try await CoachingEngine.shared.generateDashboardInsight(for: targetTimeRange, runData: runData)
                    await MainActor.run {
                        switch targetTimeRange {
                        case "7 Days":
                            self.cachedHeadline7Day = insight.headline
                            self.cachedBody7Day = insight.body
                        case "30 Days":
                            self.cachedHeadline30Day = insight.headline
                            self.cachedBody30Day = insight.body
                        default: break
                        }
                        self.isFetchingInsight = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.isFetchingInsight = false
                }
            }
        }
    }

    private func autoSyncStaleWatchDrillIfNeeded() {
        guard !lastExportedDrillId.isEmpty else { return }
        guard #available(iOS 17.0, *) else { return }
        guard let baseCadence = canonicalAthleteBaselineCadence else { return }

        let preRunId = PreRunDrillId(rawValue: lastExportedDrillId) ?? .rhythmIntervals
        let template = DrillTemplate.template(for: preRunId)
        let computedTarget = template.calculateTargetCadence(baseCadence)

        Task {
            let dto = DrillPrescriptionDTO(
                title: template.title,
                preRunDrillId: preRunId.rawValue,
                purpose: template.defaultPurpose,
                targetCadence: computedTarget,
                previousCadence: baseCadence
            )
            do {
                let bridge = WorkoutBridge()
                await WorkoutScheduler.shared.removeAllWorkouts()
                try await bridge.scheduleDrill(dto: dto)
                await MainActor.run {
                    self.lastWatchExportTimestamp = Date().timeIntervalSince1970
                }
            } catch {}
        }
    }

    private func refreshBaselineVO2Max() {
        let now = Date()
        let boundaryDate: Date? = {
            switch timeRange {
            case "7 Days": return Calendar.current.date(byAdding: .day, value: -7, to: now)
            case "30 Days": return Calendar.current.date(byAdding: .day, value: -30, to: now)
            default: return nil
            }
        }()

        Task {
            do {
                if let targetDate = boundaryDate {
                    let historicalVO2 = try await HealthKitManager.shared.fetchVO2MaxClosestTo(date: targetDate)
                    await MainActor.run {
                        self.baselineVO2Max = historicalVO2
                    }
                } else {
                    await MainActor.run {
                        self.baselineVO2Max = nil
                    }
                }
            } catch {
                // Keep current baselineVO2Max
            }
        }
    }

    @ViewBuilder
    private var fitnessBaselineCard: some View {
        FitnessBaselineCard(
            globalVO2Max: globalVO2Max,
            baselineVO2Max: baselineVO2Max,
            baselineCadence: baselineCadence,
            previousBaselineCadence: previousBaselineCadence,
            baselinePace: baselinePace,
            previousBaselinePace: previousBaselinePace,
            workoutDensityTier: workoutDensityTier,
            timeRangeRunsCount: timeRangeRuns.count,
            timeRangeName: timeRange
        )
        .padding(.horizontal)
    }

    @ViewBuilder
    private var activityVolumeSummaryCard: some View {
        ActivityVolumeSummaryCard(
            runs: timeRangeRuns,
            timeRange: timeRange,
            useMetricSystem: useMetricSystem,
            activeGoal: trainingGoal
        )
        .padding(.horizontal)
    }

    @ViewBuilder
    private var filterChips: some View {
        if !availableFilters.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        selectedFilter = nil
                    }) {
                        Text("All")
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selectedFilter == nil ? Color.accentColor : Color(UIColor.secondarySystemGroupedBackground))
                            .foregroundColor(selectedFilter == nil ? .white : .primary)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Color(UIColor.separator).opacity(0.3), lineWidth: selectedFilter == nil ? 0 : 0.5)
                            )
                    }

                    ForEach(availableFilters, id: \.self) { filter in
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            if selectedFilter == filter {
                                selectedFilter = nil
                            } else {
                                selectedFilter = filter
                            }
                        }) {
                            let iconName: String = {
                                if let drillId = PreRunDrillId.allCases.first(where: { $0.title == filter }) {
                                    return drillId.iconName
                                }
                                return RunalystIcon.forClassification(filter, isIndoor: false)
                            }()

                            HStack(spacing: 4) {
                                Image(systemName: iconName)
                                Text(filter)
                            }
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selectedFilter == filter ? Color.accentColor : Color(UIColor.secondarySystemGroupedBackground))
                            .foregroundColor(selectedFilter == filter ? .white : .primary)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Color(UIColor.separator).opacity(0.3), lineWidth: selectedFilter == filter ? 0 : 0.5)
                            )
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 2)
            .onChange(of: availableFilters) { _, newFilters in
                if let selected = selectedFilter, !newFilters.contains(selected) {
                    selectedFilter = nil
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        // 1. Pinned Filter Controls (Locked to top beneath header)
                        filterControlsSection

                        // 2. AI Coach Directive / 30-Day Trends Card
                        if !timeRangeRuns.isEmpty {
                            aiInsightCard
                                .padding(.horizontal)
                        }

                        // 3 & 4. Activity Volume & Fitness Baseline Cockpit
                        if horizontalSizeClass == .regular && !timeRangeRuns.isEmpty {
                            HStack(alignment: .top, spacing: 16) {
                                ActivityVolumeSummaryCard(
                                    runs: timeRangeRuns,
                                    timeRange: timeRange,
                                    useMetricSystem: useMetricSystem,
                                    activeGoal: trainingGoal
                                )
                                FitnessBaselineCard(
                                    globalVO2Max: globalVO2Max,
                                    baselineVO2Max: baselineVO2Max,
                                    baselineCadence: baselineCadence,
                                    previousBaselineCadence: previousBaselineCadence,
                                    baselinePace: baselinePace,
                                    previousBaselinePace: previousBaselinePace,
                                    workoutDensityTier: workoutDensityTier,
                                    timeRangeRunsCount: timeRangeRuns.count,
                                    timeRangeName: timeRange,
                                    forceTwoColumnLayout: true
                                )
                            }
                            .padding(.horizontal)
                        } else {
                            if !timeRangeRuns.isEmpty {
                                activityVolumeSummaryCard
                            }
                            fitnessBaselineCard
                        }

                        // 4. Past Runs Section Header & Run-Type Filters
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(selectedFilter == nil ? "Past Runs" : "Filtered Runs")
                                    .font(.title3.bold())
                                    .foregroundColor(.primary)

                                Spacer()

                                if selectedFilter != nil {
                                    Button("Clear Filter") {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        selectedFilter = nil
                                    }
                                    .font(.caption.bold())
                                    .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.horizontal)

                            if !availableFilters.isEmpty {
                                filterChips
                            }
                        }
                        .padding(.top, 4)
                        .id("pastRunsSection")

                        if filteredRunRecords.isEmpty {
                            if isSyncing && runRecords.isEmpty {
                                AnimatedLoadingView(text: "Analyzing your running history...")
                                    .padding(.top, 100)
                            } else if let filter = selectedFilter {
                                ContentUnavailableView {
                                    Label("No \(filter) Runs", systemImage: "line.3.horizontal.decrease.circle")
                                } description: {
                                    Text("No runs match the \"\(filter)\" filter in \(timeRange.lowercased()).")
                                } actions: {
                                    Button("Clear Filter") {
                                        selectedFilter = nil
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                                .padding(.top, 40)
                            } else if !timeRangeRuns.isEmpty {
                                let minDistanceUnit = useMetricSystem ? "km" : "mi"
                                ContentUnavailableView {
                                    Label("No Runs Found", systemImage: "figure.run")
                                } description: {
                                    Text("No runs meet the minimum distance of \(String(format: "%.1f", minimumRunDistance)) \(minDistanceUnit).")
                                } actions: {
                                    Button("Reset Distance Filter") {
                                        minimumRunDistance = useMetricSystem ? 1.0 : 0.6
                                    }
                                    .buttonStyle(.bordered)
                                }
                                .padding(.top, 40)
                            } else {
                                ContentUnavailableView(
                                    "No Runs Found",
                                    systemImage: "figure.run.circle",
                                    description: Text("Go for a run with your Apple Watch and it will appear here.")
                                )
                                .padding(.top, 60)
                            }
                        } else {
                            if horizontalSizeClass == .regular {
                                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                                    ForEach(filteredRunRecords) { run in
                                        NavigationLink(value: run) {
                                            RunListRowView(runRecord: run)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal)
                            } else {
                                ForEach(filteredRunRecords) { run in
                                    NavigationLink(value: run) {
                                        RunListRowView(runRecord: run)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        AIDisclaimerFooter()
                            .padding(.horizontal)
                            .padding(.top, 8)
                            .padding(.bottom, 16)
                    }
                    .frame(maxWidth: horizontalSizeClass == .regular ? 1040 : .infinity)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)
            }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 80)
            }
            .navigationDestination(for: RunRecord.self) { runRecord in
                RunDetailView(runRecord: runRecord)
            }
            .task {
                if ProcessInfo.processInfo.environment["RUNALYST_PREVIEW_SCREEN"] == "AUTO_TOUR" {
                    Task {
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        withAnimation(.easeInOut(duration: 2.0)) {
                            scrollProxy.scrollTo("pastRunsSection", anchor: .top)
                        }
                    }
                }
                if ProcessInfo.processInfo.environment["RUNALYST_PREVIEW_SCREEN"] == nil {
                    do {
                        try await HealthKitManager.shared.requestAuthorization()
                        if let vo2s = try? await HealthKitManager.shared.fetchRecentGlobalVO2Maxes(limit: 1), !vo2s.isEmpty {
                            globalVO2Max = vo2s[0]
                        }
                        refreshBaselineVO2Max()
                    } catch {
                        print("Error requesting HealthKit authorization on dashboard: \(error.localizedDescription)")
                    }
                } else {
                    refreshBaselineVO2Max()
                }

                if let onSync {
                    await onSync(false)
                    isSyncing = false
                }
            }
            .refreshable {
                guard !isSyncing else { return }
                isSyncing = true
                defer { isSyncing = false }

                let syncTask = Task {
                    if let onSync {
                        await onSync(false)
                    }
                }
                _ = await syncTask.value

                if let vo2s = try? await HealthKitManager.shared.fetchRecentGlobalVO2Maxes(limit: 1), !vo2s.isEmpty {
                    globalVO2Max = vo2s[0]
                }
                refreshBaselineVO2Max()

                // Invalidate cache
                DailyTrainingStateStore.shared.invalidate()
                cachedHeadline7Day = ""
                cachedBody7Day = ""
                cachedHeadline30Day = ""
                cachedBody30Day = ""
                cachedHeadlineAllTime = ""
                cachedBodyAllTime = ""
                fetchInsight()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            .sheet(isPresented: $showingAnalystChat) {
                AnalystChatView(mode: .macroCoach, modelContext: modelContext)
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Dashboard")
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
            }
        }
    }
}
