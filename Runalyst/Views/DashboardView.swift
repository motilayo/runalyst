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

    @AppStorage("dashboardTimeRange") private var timeRange: String = "30 Days"
    @AppStorage("lastBaselineChangeTimestamp") private var lastBaselineChangeTimestamp: Double = 0
    @AppStorage("lastWatchExportTimestamp") private var lastWatchExportTimestamp: Double = 0
    @AppStorage("lastExportedDrillId") private var lastExportedDrillId: String = ""
    @AppStorage("primerCompletedDate") private var primerCompletedDate: String = ""

    @AppStorage("cachedHeadline_7Day") private var cachedHeadline7Day: String = ""
    @AppStorage("cachedBody_7Day") private var cachedBody7Day: String = ""

    @AppStorage("cachedHeadline_30Day") private var cachedHeadline30Day: String = ""
    @AppStorage("cachedBody_30Day") private var cachedBody30Day: String = ""

    @AppStorage("cachedHeadline_AllTime") private var cachedHeadlineAllTime: String = ""
    @AppStorage("cachedBody_AllTime") private var cachedBodyAllTime: String = ""

    @AppStorage("lastInsightRunCount") private var lastInsightRunCount: Int = 0

    @State private var isFetchingInsight = false
    @State private var showingAnalystChat = false

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
        let calendar = Calendar.current
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let recentRuns = runRecords.filter { $0.date >= thirtyDaysAgo && $0.workingAvgCadence > 0 }
        let candidateRuns = recentRuns.isEmpty ? runRecords.filter { $0.workingAvgCadence > 0 } : recentRuns
        guard !candidateRuns.isEmpty else { return nil }
        let totalDuration = candidateRuns.map(\.duration).reduce(0, +)
        guard totalDuration > 0 else {
            return Int(candidateRuns.map(\.workingAvgCadence).reduce(0, +)) / candidateRuns.count
        }
        return Int(candidateRuns.map { $0.workingAvgCadence * $0.duration }.reduce(0, +) / totalDuration)
    }

    var canonicalAthleteBaselinePace: Double? {
        let calendar = Calendar.current
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let recentRuns = runRecords.filter { $0.date >= thirtyDaysAgo && $0.workingAvgPace > 0 }
        let candidateRuns = recentRuns.isEmpty ? runRecords.filter { $0.workingAvgPace > 0 } : recentRuns
        guard !candidateRuns.isEmpty else { return nil }
        let totalDuration = candidateRuns.map(\.duration).reduce(0, +)
        guard totalDuration > 0 else {
            return candidateRuns.map(\.workingAvgPace).reduce(0, +) / Double(candidateRuns.count)
        }
        return candidateRuns.map { $0.workingAvgPace * $0.duration }.reduce(0, +) / totalDuration
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

    private var isTrajectoryEaseUp: Bool {
        if timeRange == "30 Days" {
            let validRuns = timeRangeRuns.filter { $0.workingAvgPace > 0 && $0.workingAvgHeartRate > 0 }
            let midDate = Calendar.current.date(byAdding: .day, value: -15, to: Date()) ?? Date()
            let recentRuns = validRuns.filter { $0.date >= midDate }
            let olderRuns = validRuns.filter { $0.date < midDate }
            let recentEF = recentRuns.compactMap(\.efficiencyFactor)
            let olderEF = olderRuns.compactMap(\.efficiencyFactor)
            let avgRecentEF = recentEF.isEmpty ? 0.0 : (recentEF.reduce(0, +) / Double(recentEF.count))
            let avgOlderEF = olderEF.isEmpty ? 0.0 : (olderEF.reduce(0, +) / Double(olderEF.count))
            let efDelta = (avgRecentEF > 0 && avgOlderEF > 0) ? (avgRecentEF - avgOlderEF) : 0.0

            let recentHR = recentRuns.map(\.workingAvgHeartRate).reduce(0, +) / Double(max(1, recentRuns.count))
            let olderHR = olderRuns.map(\.workingAvgHeartRate).reduce(0, +) / Double(max(1, olderRuns.count))
            let hrDelta = (recentHR > 0 && olderHR > 0) ? (recentHR - olderHR) : 0.0

            return (efDelta <= -0.02 && olderEF.count >= 2) || (hrDelta >= 3.0 && olderHR > 0)
        }
        return false
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

    private var isPrimerCompletedToday: Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return primerCompletedDate == formatter.string(from: Date())
    }

    private func togglePrimerCompletedToday() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let today = formatter.string(from: Date())
        if primerCompletedDate == today {
            primerCompletedDate = ""
        } else {
            primerCompletedDate = today
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 14, weight: .semibold))
                    Text("\(String(format: "%.1f", minimumRunDistance))\(useMetricSystem ? "k" : "m")")
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
        RunnerProfile.compute(from: runRecords, now: Date())
    }

    private var dashboardRecoveryTimeline: RecoveryTimeline {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        let recent = runRecords.filter { $0.date >= cutoff }
        let snapshots = recent.map(ReadinessRunSnapshot.init(run:))
        let readiness = ReadinessEvaluator.assess(runRecords: runRecords)
        return RecoveryTimeline.build(runs: snapshots, readiness: readiness, now: Date())
    }

    private var deterministicPrescription: LockedTrainingPrescription? {
        guard let latestRun = runRecords.first else { return nil }
        let profile = dashboardRunnerProfile
        let tzInput = TrainingZoneInput(
            baselinePaceSec: canonicalAthleteBaselinePace ?? latestRun.workingAvgPace,
            workoutPaceSec: latestRun.workingAvgPace,
            activeGoal: trainingGoal,
            experienceLevel: profile.experienceLevel,
            readyForHard: dashboardRecoveryTimeline.readyForHard,
            daysSinceWorkout: Calendar.current.dateComponents([.day], from: latestRun.date, to: Date()).day ?? 0,
            heightAdjustedCadenceFloor: profile.heightAdjustedCadenceFloor,
            useMetricSystem: useMetricSystem,
            isSubjectiveDistress: false,
            totalHistoricalRunsCount: runRecords.count
        )
        return TrainingZoneEngine.computePrescription(tzInput)
    }

    private func hrCapText(for rx: LockedTrainingPrescription) -> String {
        if rx.intensityCategory.contains("RECOVERY") || rx.intensityCategory.contains("ZONE_2") || !dashboardRecoveryTimeline.readyForHard {
            return "HR: < 145"
        } else if rx.intensityCategory.contains("THRESHOLD") || rx.intensityCategory.contains("TEMPO") {
            return "HR: 155–168"
        } else {
            return "HR: < 155"
        }
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
                }

                if is7Day {
                    let displayHeadline = headline.isEmpty ? "Easy Recovery Needed" : headline
                    Text(displayHeadline)
                        .font(.title3.bold())
                        .foregroundColor(.primary)

                    if let rx = deterministicPrescription {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) {
                                targetPill(text: rx.compactDurationBand, color: .purple)
                                targetPill(text: "Pace: \(rx.prescribedPaceBand)", color: Color(red: 0.0, green: 0.55, blue: 1.0))
                                targetPill(text: hrCapText(for: rx), color: Color(red: 1.0, green: 0.22, blue: 0.55))
                            }
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    targetPill(text: rx.compactDurationBand, color: .purple)
                                    targetPill(text: "Pace: \(rx.prescribedPaceBand)", color: Color(red: 0.0, green: 0.55, blue: 1.0))
                                    targetPill(text: hrCapText(for: rx), color: Color(red: 1.0, green: 0.22, blue: 0.55))
                                }
                            }
                        }
                    }
                } else if !headline.isEmpty {
                    Text(headline)
                        .font(.headline)
                        .foregroundColor(.primary)
                }

                let defaultPlaceholder = is7Day
                    ? "Complete more runs this week to evaluate acute fatigue and recovery trends."
                    : "Complete more runs over the next 30 days to measure structural aerobic adaptation."

                Text(bodyText.isEmpty ? defaultPlaceholder : bodyText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineSpacing(2)

                AIDisclaimerFooter()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(UIColor.separator).opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        .onAppear {
            if timeRange != "7 Days" && timeRange != "30 Days" {
                timeRange = "30 Days"
            }
            checkAndFetchInsight()
        }
        .onChange(of: timeRange) {
            checkAndFetchInsight()
            refreshBaselineVO2Max()
            lastBaselineChangeTimestamp = Date().timeIntervalSince1970
            autoSyncStaleWatchDrillIfNeeded()
        }
        .onChange(of: minimumRunDistance) {
            lastBaselineChangeTimestamp = Date().timeIntervalSince1970
            autoSyncStaleWatchDrillIfNeeded()
        }
    }

    private func currentHeadline() -> String {
        switch timeRange {
        case "7 Days": return cachedHeadline7Day
        case "30 Days": return cachedHeadline30Day
        case "All Time": return cachedHeadlineAllTime
        default: return ""
        }
    }

    private func currentBody() -> String {
        switch timeRange {
        case "7 Days": return cachedBody7Day
        case "30 Days": return cachedBody30Day
        case "All Time": return cachedBodyAllTime
        default: return ""
        }
    }

    private func checkAndFetchInsight() {
        guard timeRange != "All Time" else {
            isFetchingInsight = false
            return
        }
        let currentRunCount = runRecords.count
        if currentRunCount != lastInsightRunCount {
            // Invalidate cache
            cachedHeadline7Day = ""
            cachedBody7Day = ""
            cachedHeadline30Day = ""
            cachedBody30Day = ""
            cachedHeadlineAllTime = ""
            cachedBodyAllTime = ""
            lastInsightRunCount = currentRunCount
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
            // 7-DAY VIEW: Tactical Coach (Readiness & Acute Fatigue)
            let heavySessions = timeRangeRuns.filter { run in
                let type = run.detectedTypeRaw
                let isHeavy = (type == "Intervals" || type == "Pyramids" || type == "Tempo Run" || type == "Hill Repeats")
                let highZ4 = run.percentZone4 >= 0.35
                return isHeavy || highZ4
            }
            let heavyCount = heavySessions.count

            // Check for consecutive hard sessions (less than 36 hours apart)
            var hasBackToBackHeavy = false
            if heavySessions.count >= 2 {
                for index in 0..<(heavySessions.count - 1) {
                    let interval = heavySessions[index].date.timeIntervalSince(heavySessions[index + 1].date)
                    if interval > 0 && interval < 36 * 3600 {
                        hasBackToBackHeavy = true
                        break
                    }
                }
            }

            let latestRun = timeRangeRuns.first
            let hasFatigueDrift = latestRun?.framboiseTags.contains("fatigueDrift") ?? false

            // Resolve personalized baseline cadence: prefer 30-day historical, then previous 7-day, then current 7-day
            let personalizedBaselineCadence: Double = {
                if let historical = latestRun?.computeHistoricalBaselineCadence(in: runRecords) {
                    return historical
                }
                if let prev = previousBaselineCadence {
                    return Double(prev)
                }
                if let base = baselineCadence {
                    return Double(base)
                }
                return 160.0
            }()

            let latestCad = latestRun?.workingAvgCadence ?? personalizedBaselineCadence
            let cadenceDiff = personalizedBaselineCadence - latestCad
            let cadenceDropped = (latestCad > 0) && (cadenceDiff >= 3.5)

            // High acute density: 6+ runs in 7 days
            let isHighDensity = timeRangeRuns.count >= 6

            let isCriticalFatigue = (heavyCount >= 3 && (cadenceDropped || hasFatigueDrift))
                || (hasBackToBackHeavy && (cadenceDropped || hasFatigueDrift))
                || (isHighDensity && heavyCount >= 2 && cadenceDropped && hasFatigueDrift)

            let isModerateFatigue = heavyCount >= 2
                || cadenceDropped
                || hasFatigueDrift
                || hasBackToBackHeavy
                || (isHighDensity && heavyCount >= 1)

            if isCriticalFatigue {
                let dropText = cadenceDropped ? " with confirmed turnover decay of \(Int(round(cadenceDiff))) SPM" : ""
                directiveContext = "CRITICAL_FATIGUE: Acute cumulative overload detected (\(heavyCount) hard sessions\(dropText)). PRIORITY: Tell the runner to take a full rest day or very gentle walk next, focusing on bringing fatigue down and resting their legs before their next run toward their \(trainingGoal) goal."
                fatigueContext = "\(heavyCount) hard sessions; verified turnover decay under high acute density. Full rest recommended."
            } else if isModerateFatigue {
                let turnoverNote = cadenceDropped
                    ? "Turnover shows mild decay (-3 to -4 SPM) after intense work."
                    : "Cadence turnover remains stable, but acute training density is high."
                directiveContext = "MODERATE_FATIGUE: Productive training fatigue from recent quality work. \(turnoverNote) PRIORITY: Tell the runner to do an easy recovery jog or light cross-training next, focusing on keeping their heart rate low and relaxed to consolidate fitness toward their \(trainingGoal) goal."
                fatigueContext = "Moderate training strain from recent quality sessions. Recommend easy aerobic recovery in Zone 2."
            } else {
                directiveContext = "HIGH_READINESS: Balanced load, fresh legs, and consistent turnover. Athlete is primed for their next key workout. Recommend what kind of run to do next (such as a tempo run, intervals, or steady aerobic run) and what to focus on improving (like quickening cadence turnover, maintaining a steady pace, or building stamina) toward their \(trainingGoal) goal."
                fatigueContext = "Readiness optimal. No acute cardiac or turnover fatigue."
            }
            efficiencyContext = ""
            verticalOscillationContext = ""
        } else {
            // 30-DAY VIEW: Goal Readiness & Trajectory Analyst
            let validRuns = timeRangeRuns.filter { $0.workingAvgPace > 0 && $0.workingAvgHeartRate > 0 }
            let midDate = Calendar.current.date(byAdding: .day, value: -15, to: Date()) ?? Date()

            let recentRuns = validRuns.filter { $0.date >= midDate }
            let olderRuns = validRuns.filter { $0.date < midDate }

            let recentEF = recentRuns.compactMap(\.efficiencyFactor)
            let olderEF = olderRuns.compactMap(\.efficiencyFactor)

            let avgRecentEF = recentEF.isEmpty ? 0.0 : (recentEF.reduce(0, +) / Double(recentEF.count))
            let avgOlderEF = olderEF.isEmpty ? 0.0 : (olderEF.reduce(0, +) / Double(olderEF.count))
            let efDelta = (avgRecentEF > 0 && avgOlderEF > 0) ? (avgRecentEF - avgOlderEF) : 0.0

            let recentOscs = recentRuns.compactMap { $0.workingAvgVerticalOscillation ?? $0.rawAvgVerticalOscillation }
            let olderOscs = olderRuns.compactMap { $0.workingAvgVerticalOscillation ?? $0.rawAvgVerticalOscillation }
            let avgRecentOsc = recentOscs.isEmpty ? 0.0 : (recentOscs.reduce(0, +) / Double(recentOscs.count))
            let avgOlderOsc = olderOscs.isEmpty ? 0.0 : (olderOscs.reduce(0, +) / Double(olderOscs.count))
            let oscDelta = (avgRecentOsc > 0 && avgOlderOsc > 0) ? (avgRecentOsc - avgOlderOsc) : 0.0

            let recentVRs = recentRuns.compactMap(\.verticalRatio)
            let olderVRs = olderRuns.compactMap(\.verticalRatio)
            let avgRecentVR = recentVRs.isEmpty ? 0.0 : (recentVRs.reduce(0, +) / Double(recentVRs.count))
            let avgOlderVR = olderVRs.isEmpty ? 0.0 : (olderVRs.reduce(0, +) / Double(olderVRs.count))
            let vrDelta = (avgRecentVR > 0 && avgOlderVR > 0) ? (avgRecentVR - avgOlderVR) : 0.0

            let recentHR = recentRuns.map(\.workingAvgHeartRate).reduce(0, +) / Double(max(1, recentRuns.count))
            let olderHR = olderRuns.map(\.workingAvgHeartRate).reduce(0, +) / Double(max(1, olderRuns.count))
            let hrDelta = (recentHR > 0 && olderHR > 0) ? (recentHR - olderHR) : 0.0

            if (efDelta <= -0.02 && olderEF.count >= 2) || (hrDelta >= 3.0 && olderHR > 0) {
                directiveContext = "TRAJECTORY_EASE_UP: Over the past 30 days, training data indicates cumulative overworking and declining efficiency (aerobic cost is climbing). For their stated goal of \(trainingGoal), tell the runner clearly that they are overworking and need to ease up on volume or intensity so their body can absorb the training and avoid declining instead of improving."
                efficiencyContext = "Efficiency Factor declined over the past month. Cardiac drift and physiological strain accumulating."
            } else if efDelta > 0.02 || hrDelta < -2.0 || oscDelta < -0.2 || vrDelta < -0.3 {
                let hrDeltaText = hrDelta < 0 ? "\(Int(abs(hrDelta))) BPM lower" : "stable"
                let vrDeltaText = avgRecentVR > 0 ? ", Vertical Ratio: \(String(format: "%.1f", avgRecentVR))%" : ""
                directiveContext = "TRAJECTORY_ON_TRACK: Over the past 30 days, aerobic efficiency, cardiac response, and running economy have clearly improved (Efficiency Factor increased by \(String(format: "%.2f", efDelta)), heart rate at \(paceContext) is \(hrDeltaText)\(vrDeltaText)). Tell the runner clearly that they are solidly on track for their \(trainingGoal) goal and their consistency is paying off."
                efficiencyContext = "Efficiency Factor rose by +\(String(format: "%.2f", efDelta)) m/beat. Aerobic capacity expanding."
            } else {
                directiveContext = "TRAJECTORY_STEP_IT_UP: Over the past 30 days, baseline fitness is steady and well-calibrated, but performance has plateaued. Tell the runner their performances show their body has adapted and they have more to give, encouraging them to step up their training slightly in pace, volume, or quality to chase their \(trainingGoal) goal."
                efficiencyContext = "Efficiency Factor stable at \(String(format: "%.2f", max(1.2, avgRecentEF))) m/beat."
            }
            if avgRecentVR > 0 {
                verticalOscillationContext = "Vertical Oscillation: \(String(format: "%.1f", avgRecentOsc)) cm (VR: \(String(format: "%.1f", avgRecentVR))%)"
            } else {
                verticalOscillationContext = avgRecentOsc > 0 ? "Vertical Oscillation: \(String(format: "%.1f", avgRecentOsc)) cm" : "Vertical form steady"
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

    private func sanitizeSpuriousDrillTags() {
        var didMutate = false
        // Purge any stale intents created by the bug that infected UserDefaults
        let existingIntents = WorkoutBridge.recentIntents()
        let legitimateIntents = existingIntents.filter { intent in
            intent.matchedWorkoutID != nil || (intent.durationMinutes <= 15 && intent.targetCadence != nil)
        }
        if legitimateIntents.count != existingIntents.count {
            WorkoutBridge.persistIntents(legitimateIntents)
        }

        let canonicalDrillIds = Set(PreRunDrillId.allCases.map(\.rawValue))
        let canonicalDrillTitles = Set(PreRunDrillId.allCases.map(\.title))

        for run in runRecords {
            guard run.framboiseTags.contains("prescribedDrill") else { continue }
            // Never scrub manual user drill bindings or unlinks
            if run.framboiseTags.contains("userLinkedDrill") || run.framboiseTags.contains("userUnlinkedDrill") {
                continue
            }

            // A continuous aerobic run (duration >= 12 minutes / 720s or distance >= 1.5 km)
            // that was falsely recognized as Rhythm Intervals or continuous drill
            let hasRhythm = run.framboiseTags.contains("drill:Rhythm Intervals") || run.framboiseTags.contains("rhythm_intervals")
            let hasZone2 = run.framboiseTags.contains("drill:Zone 2 Run") || run.framboiseTags.contains("zone_2_run")
            let hasRecovery = run.framboiseTags.contains("drill:Recovery Jog") || run.framboiseTags.contains("recovery_jog")

            if (hasRhythm || hasZone2 || hasRecovery) && (run.duration >= 720.0 || run.totalDistanceMeters >= 1500.0) {
                run.framboiseTags.removeAll { tag in
                    tag == "prescribedDrill" ||
                    tag.hasPrefix("drill:") ||
                    tag.hasPrefix("drillIntervals:") ||
                    tag.hasPrefix("drillWorkCadence:") ||
                    tag.hasPrefix("drillRecCadence:") ||
                    tag.hasPrefix("drillReps:") ||
                    canonicalDrillIds.contains(tag) ||
                    canonicalDrillTitles.contains(tag)
                }
                if run.detectedTypeRaw == "Intervals" {
                    run.detectedTypeRaw = "Steady Effort"
                }
                didMutate = true
            }
        }

        if didMutate {
            try? modelContext.save()
        }
    }

    private var activePrimerId: PreRunDrillId {
        if timeRange == "7 Days" && (!dashboardRecoveryTimeline.readyForHard || currentHeadline().localizedCaseInsensitiveContains("fatigue")) {
            return .aerobicFlush
        } else if let cadence = canonicalAthleteBaselineCadence, cadence < 150 {
            return .cadencePyramids
        } else if let cadence = canonicalAthleteBaselineCadence, cadence < 160 {
            return .rhythmIntervals
        } else {
            return .neuromuscularPrimer
        }
    }

    @ViewBuilder
    private var proactiveCoachCard: some View {
        ProactiveCoachCard(
            activePrimerId: activePrimerId,
            baselineCadence: canonicalAthleteBaselineCadence,
            timeRange: timeRange,
            runRecords: runRecords,
            isPrimerCompletedToday: isPrimerCompletedToday,
            onTogglePrimerCompleted: { togglePrimerCompletedToday() }
        )
    }

    private func autoSyncStaleWatchDrillIfNeeded() {
        guard !lastExportedDrillId.isEmpty else { return }
        guard #available(iOS 17.0, *) else { return }
        guard let baseCadence = canonicalAthleteBaselineCadence else { return }

        let preRunId = PreRunDrillId(rawValue: lastExportedDrillId) ?? activePrimerId
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
                            HStack(spacing: 4) {
                                if let drillId = PreRunDrillId.allCases.first(where: { $0.title == filter }) {
                                    Image(systemName: drillId.iconName)
                                }
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
            .padding(.vertical, 4)
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
                    LazyVStack(spacing: 20) {
                        // 1. Pinned Filter Controls (Locked to top beneath header)
                        filterControlsSection

                        // 2. AI Coach Directive / 30-Day Trends Card
                        if !timeRangeRuns.isEmpty {
                            if horizontalSizeClass == .regular {
                                HStack(alignment: .top, spacing: 16) {
                                    aiInsightCard
                                    proactiveCoachCard
                                }
                                .padding(.horizontal)
                            } else {
                                aiInsightCard
                                    .padding(.horizontal)
                            }
                        }

                        // 3. Fitness Baseline Quadrant Card
                        fitnessBaselineCard

                        // 4. Proactive Coach Card (Phone portrait layout)
                        if !timeRangeRuns.isEmpty && horizontalSizeClass != .regular {
                            proactiveCoachCard
                                .padding(.horizontal)
                        }

                    if !availableFilters.isEmpty {
                        filterChips
                    }

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
                        if !filteredRunRecords.isEmpty {
                            Section(header: Text(selectedFilter == nil ? "Past Runs" : "Filtered Runs")
                                                .font(.title3.bold())
                                                .padding(.horizontal)
                                                .frame(maxWidth: .infinity, alignment: .leading)) {
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
                            .id("pastRunsSection")
                        }
                    }
                }
                .padding(.vertical)
            }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 100)
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
                sanitizeSpuriousDrillTags()
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
                sanitizeSpuriousDrillTags()

                // Invalidate cache
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
                if let latestRun = runRecords.first {
                    AnalystChatView(runRecord: latestRun)
                }
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Dashboard")
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
            }
        }
    }
}
