import Foundation
import SwiftData
import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Chat message delivery status.
enum MessageDeliveryStatus: Equatable, Sendable {
    case delivered
    case failed(retryPrompt: String)
}

/// Chat message model for the interactive AI Analyst conversation.
struct AnalystChatMessage: Identifiable, Equatable {
    let id: UUID
    let sender: MessageSender
    let text: String
    let timestamp: Date
    let attachedDrillId: PreRunDrillId?
    let attachedSession: PrescribedDailySession?
    let attachedExplainerKey: String?
    let attachedSchedule: [MicrocycleDay]?
    let status: MessageDeliveryStatus

    enum MessageSender: Equatable {
        case user
        case analyst
    }

    init(
        id: UUID = UUID(),
        sender: MessageSender,
        text: String,
        timestamp: Date = Date(),
        attachedDrillId: PreRunDrillId? = nil,
        attachedSession: PrescribedDailySession? = nil,
        attachedExplainerKey: String? = nil,
        attachedSchedule: [MicrocycleDay]? = nil,
        status: MessageDeliveryStatus = .delivered
    ) {
        self.id = id
        self.sender = sender
        self.text = text
        self.timestamp = timestamp
        self.attachedDrillId = attachedDrillId
        self.attachedSession = attachedSession
        self.attachedExplainerKey = attachedExplainerKey
        self.attachedSchedule = attachedSchedule
        self.status = status
    }
}

typealias AnalystChatSender = AnalystChatMessage.MessageSender

/// Defines the scope and framing of an AI Analyst conversation.
enum AnalystChatMode: Equatable, Sendable {
    /// Anchored to inspecting a specific historical workout.
    case runInspection
    /// Anchored globally as the athlete's macro running & recovery coach.
    case macroCoach
}

/// Actor managing the interactive RAG Analyst Chat session with FoundationModels and strict operational guardrails.
@MainActor
class AnalystChatEngine: ObservableObject {
    @Published var messages: [AnalystChatMessage] = []
    @Published var isResponding: Bool = false

    private let mode: AnalystChatMode
    private let runSignature: RunSignature?
    private let macroProfile: MacroProfile?
    private let runRecord: RunRecord

    #if canImport(FoundationModels)
    private var modelSession: Any? // LanguageModelSession on iOS 26+
    /// Tracks a drill recommended during the active conversation turn.
    var drillRecommendedThisTurn: PreRunDrillId?
    /// Tracks a prescribed daily session recommended during the active conversation turn.
    var sessionRecommendedThisTurn: PrescribedDailySession?
    /// Tracks an interactive explainer card recommended during the active conversation turn.
    var explainerRecommendedThisTurn: String?
    /// Tracks an upcoming schedule card recommended during the active conversation turn.
    var scheduleRecommendedThisTurn: [MicrocycleDay]?

    // MARK: - Bounded-Memory State Tracking
    private var turnsSinceSessionRecycle: Int = 0
    private var lastTurnUsedHeavyTool: Bool = false
    private var toolInvokedDuringActiveTurn: Bool = false
    #endif

    #if DEBUG
    /// Optional closure allowing unit tests to simulate model free-speech responses and inspect system instructions.
    var modelResponder: ((_ systemInstructions: String, _ userQuestion: String) async throws -> String)?
    #endif

    private var baselineStats: (avgPace: Double, avgCadence: Double, avgHR: Double)? {
        guard let context = runRecord.modelContext,
              let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: runRecord.date) else {
            return nil
        }
        let targetDate = runRecord.date
        let descriptor = FetchDescriptor<RunRecord>(
            predicate: #Predicate<RunRecord> { $0.date >= thirtyDaysAgo && $0.date < targetDate }
        )
        guard let prior = try? context.fetch(descriptor), !prior.isEmpty else { return nil }
        let validPaces = prior.map(\.workingAvgPace).filter { $0 > 0 }
        let validCads = prior.map(\.workingAvgCadence).filter { $0 > 0 }
        let validHRs = prior.map(\.workingAvgHeartRate).filter { $0 > 0 }
        guard !validPaces.isEmpty, !validCads.isEmpty, !validHRs.isEmpty else { return nil }
        return (
            avgPace: validPaces.reduce(0, +) / Double(validPaces.count),
            avgCadence: validCads.reduce(0, +) / Double(validCads.count),
            avgHR: validHRs.reduce(0, +) / Double(validHRs.count)
        )
    }

    init(
        runRecord: RunRecord,
        mode: AnalystChatMode = .runInspection,
        runSignature: RunSignature? = nil,
        macroProfile: MacroProfile? = nil
    ) {
        self.runRecord = runRecord
        self.mode = mode
        self.runSignature = runSignature ?? runRecord.signature
        self.macroProfile = macroProfile ?? MacroProfile.load()
    }

    /// Sends a runner question and generates an analyst response with RAG telemetry context and guardrails.
    func sendMessage(_ userQuestion: String) async {
        let trimmed = userQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !isResponding else { return }

        messages.append(AnalystChatMessage(sender: .user, text: trimmed, status: .delivered))
        isResponding = true

        await executeChatTurn(userQuestion: trimmed, isRetry: false)
    }

    /// Retries a previously failed message in place without duplicating user message bubbles.
    func retryMessage(failedMessageId: UUID) async {
        guard !isResponding else { return }
        guard let index = messages.firstIndex(where: { $0.id == failedMessageId }),
              case .failed(let retryPrompt) = messages[index].status else { return }

        // Mutate synchronously on MainActor before awaiting
        messages.remove(at: index)
        isResponding = true

        await executeChatTurn(userQuestion: retryPrompt, isRetry: true)
    }

    private func executeChatTurn(userQuestion: String, isRetry: Bool) async {
        defer { isResponding = false }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            self.drillRecommendedThisTurn = nil
            self.sessionRecommendedThisTurn = nil
            self.explainerRecommendedThisTurn = nil
            self.scheduleRecommendedThisTurn = nil

            // Proactive Sliding-Window Transcript Compaction:
            // Recycle the ephemeral session if 3 turns have elapsed or if the last turn invoked a tool.
            if self.turnsSinceSessionRecycle >= 3 || self.lastTurnUsedHeavyTool {
                self.modelSession = nil
            }
        }
        #endif

        // FoundationModels: the runner's message goes straight to the session.
        // Lean instructions + native tools only.
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            #if DEBUG
            if let responder = modelResponder {
                do {
                    let responseText = try await responder(buildLeanSystemInstructions(), userQuestion)
                    messages.append(
                        AnalystChatMessage(
                            sender: .analyst,
                            text: responseText,
                            attachedDrillId: drillRecommendedThisTurn,
                            attachedSession: sessionRecommendedThisTurn,
                            attachedExplainerKey: explainerRecommendedThisTurn,
                            attachedSchedule: scheduleRecommendedThisTurn,
                            status: .delivered
                        )
                    )
                    self.lastTurnUsedHeavyTool = self.toolInvokedDuringActiveTurn
                    self.turnsSinceSessionRecycle += 1
                    self.toolInvokedDuringActiveTurn = false
                    return
                } catch {
                    if isNonRetryableError(error) {
                        messages.append(
                            AnalystChatMessage(
                                sender: .analyst,
                                text: systemUnavailableMessage(),
                                status: .failed(retryPrompt: userQuestion)
                            )
                        )
                        return
                    }
                    print("Model responder error: \(error)")
                }
            }
            #endif
            if SystemLanguageModel.default.isAvailable {
                do {
                    let responseText = try await generateFoundationModelResponse(for: userQuestion)
                    messages.append(
                        AnalystChatMessage(
                            sender: .analyst,
                            text: responseText,
                            attachedDrillId: drillRecommendedThisTurn,
                            attachedSession: sessionRecommendedThisTurn,
                            attachedExplainerKey: explainerRecommendedThisTurn,
                            attachedSchedule: scheduleRecommendedThisTurn,
                            status: .delivered
                        )
                    )
                    self.lastTurnUsedHeavyTool = self.toolInvokedDuringActiveTurn
                    self.turnsSinceSessionRecycle += 1
                    self.toolInvokedDuringActiveTurn = false
                    return
                } catch {
                    print("FoundationModels chat error: \(error)")
                    self.modelSession = nil
                    if (error is CancellationError) || Task.isCancelled {
                        return
                    }
                }
            }
        }
        #endif

        // No simulated coach: if the on-device model can't answer, record failure with retry prompt.
        messages.append(
            AnalystChatMessage(
                sender: .analyst,
                text: systemUnavailableMessage(),
                status: .failed(retryPrompt: userQuestion)
            )
        )
    }

    // MARK: - Analysis Context Factory

    func makeAnalysisContext(isSubjectiveDistress: Bool = false) -> WorkoutAnalysisContext {
        let totalRuns = (try? runRecord.modelContext?.fetchCount(FetchDescriptor<RunRecord>())) ?? 1
        return WorkoutAnalysisContext(
            runRecord: runRecord,
            runSignature: runSignature,
            macroProfile: macroProfile,
            recoveryTimeline: recoveryTimeline,
            baselineStats: baselineStats,
            runnerProfile: runnerProfile,
            isSubjectiveDistress: isSubjectiveDistress,
            totalHistoricalRunsCount: totalRuns
        )
    }

    // MARK: - System Instructions

    #if canImport(FoundationModels)
    /// Context only: which run, which units, which language, and the medical boundary.
    /// Tool semantics live in each `Tool.description` / `@Guide`; facts live in tool payloads.
    @available(iOS 26.0, *)
    func buildLeanSystemInstructions() -> String {
        let calendar = TrainingCalendar(now: Date())
        let useMetric = (UserDefaults.standard.object(forKey: "useMetricSystem") as? Bool) ?? true
        let language = Locale.current.language.languageCode?.identifier ?? "en"

        let contextBlock: String
        if mode == .macroCoach {
            let allRuns = (try? runRecord.modelContext?.fetch(FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? [runRecord]
            let todayRuns = allRuns.filter { calendar.calendar.isDateInToday($0.date) && !$0.isDeleted }
            let stateDesc: String
            if todayRuns.isEmpty {
                stateDesc = "Pre-run (0 sessions logged today)."
            } else {
                let totalSec = todayRuns.reduce(0.0) { $0 + $1.duration }
                let durMin = Int(totalSec) / 60
                let durSec = Int(totalSec) % 60
                let durStr = String(format: "%d:%02d", durMin, durSec)
                let totalMeters = todayRuns.reduce(0.0) { $0 + ($1.totalDistanceMeters > 0 ? $1.totalDistanceMeters : $1.effectiveWorkingDistanceMeters) }
                let distStr = useMetric ? String(format: "%.2f km", totalMeters / 1000.0) : String(format: "%.2f mi", totalMeters / 1609.344)
                stateDesc = "Completed today (\(todayRuns.count) sessions, \(durStr), \(distStr))."
            }
            contextBlock = """
            Scope: Macro AI Coach.
            \(calendar.anchor(useMetric: useMetric))
            Athlete State: \(stateDesc)
            """
        } else {
            let daysDiff = max(0, Calendar.current.dateComponents([.day], from: runRecord.date, to: Date()).day ?? 0)
            let dateStr = TrainingCalendar.weekdayFormatter.string(from: runRecord.date)
            let temporalGrounding = daysDiff == 0 ? "Today" : "\(dateStr) (\(daysDiff)d ago)"
            let runType = runRecord.normalizedClassification
            let envNote = (runRecord.isIndoor ?? false) ? "Indoor Treadmill" : "Outdoor"
            contextBlock = """
            Scope: Workout Inspection.
            \(calendar.anchor(useMetric: useMetric))
            Reviewing: \(runType) (\(envNote), \(temporalGrounding)).
            """
        }

        var recentContextBlock = ""
        let deliveredMessages = self.messages.filter { $0.status == .delivered }
        let completedHistory = deliveredMessages.dropLast(self.messages.last?.sender == .user ? 1 : 0)
        let recentTurns = completedHistory.suffix(4)

        if !recentTurns.isEmpty {
            var lines: [String] = ["RECENT DIALOGUE (Reference Only):"]
            for msg in recentTurns {
                let role = msg.sender == .user ? "Runner" : "Coach"
                let cleaned = msg.text.replacingOccurrences(of: "\n", with: " ")
                lines.append("• \(role): \"\(cleaned)\"")
            }
            recentContextBlock = "\n\n" + lines.joined(separator: "\n")
        }

        return """
        You are Runalyst—an empathetic running coach. Speak directly to the runner with warmth and brevity.

        CONTEXT:
        \(contextBlock)\(recentContextBlock)

        TOOLS:
        • `getTrainingSchedule`: Query calendar workouts ('yyyy-MM-dd').
        • `getReadinessAndWorkload`: Query recovery, ACWR, volume, second-run safety.
        • `queryWorkoutHistory`: Compare runs or analyze 30-day performance arc.
        • `inspectWorkout`: Inspect workout metrics, intervals, splits.
        • `executeCoachAction`: Actions ('display_schedule', 'display_drill', 'display_explainer', 'update_goal', 'export_to_watch', 'record_feedback').

        RULES:
        • If today is completed, state schedule is clear and note completed work before pivoting to tomorrow.
        • Rest of week: remaining days ending Saturday. Next week: Sunday through Saturday.
        • Units: SPM, min/km, min/mi. No LaTeX.
        • Medical Safety: On pain/illness, urge rest and medical care.
        • Outside Running: Warmly refocus on running.

        Respond in \(language).
        """
    }

    @available(iOS 26.0, *)
    func getOrCreateSession() -> LanguageModelSession {
        if let existing = modelSession as? LanguageModelSession {
            return existing
        }

        // Reset counters inside session creation in one canonical place
        self.turnsSinceSessionRecycle = 0
        self.lastTurnUsedHeavyTool = false
        self.toolInvokedDuringActiveTurn = false

        let inspectWorkoutTool = InspectWorkoutTool { [weak self] _ in
            guard let self else { return "" }
            self.toolInvokedDuringActiveTurn = true
            return self.makeAnalysisContext().compactTelemetryAnalysis()
        }

        let getTrainingScheduleTool = GetTrainingScheduleTool { [weak self] query in
            guard let self else { return "No schedule days planned." }
            self.toolInvokedDuringActiveTurn = true
            let allRuns = (try? self.runRecord.modelContext?.fetch(FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? [self.runRecord]
            let activeGoal = UserDefaults.standard.string(forKey: "trainingGoal") ?? "Base Building"
            let profile = RunnerProfile.compute(from: allRuns)
            let useMetric = (UserDefaults.standard.object(forKey: "useMetricSystem") as? Bool) ?? true
            let calendar = TrainingCalendar(calendar: Calendar.current)

            let fromDate = calendar.parseISO(query.from) ?? calendar.startOfDay(for: Date())
            let toDate: Date
            if let toStr = query.to, let parsedTo = calendar.parseISO(toStr) {
                toDate = calendar.startOfDay(for: parsedTo)
            } else {
                toDate = fromDate
            }

            let context = ScheduleEvaluationContext(
                runRecords: allRuns,
                activeGoal: activeGoal,
                profile: profile,
                useMetric: useMetric
            )

            let schedule = calendar.evaluateSchedule(
                from: fromDate,
                to: toDate,
                context: context
            )

            return TrainingCalendar.formatCompactScheduleSummary(days: schedule)
        }

        let getReadinessAndWorkloadTool = GetReadinessAndWorkloadTool { [weak self] query in
            guard let self else { return "{}" }
            self.toolInvokedDuringActiveTurn = true
            let isDistress = query.userReportedDistress == true
            let analysis = self.makeAnalysisContext(isSubjectiveDistress: isDistress)
            let allRuns = (try? self.runRecord.modelContext?.fetch(FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? [self.runRecord]
            let activeGoal = UserDefaults.standard.string(forKey: "trainingGoal") ?? "Base Building"
            let profile = RunnerProfile.compute(from: allRuns)
            let useMetric = (UserDefaults.standard.object(forKey: "useMetricSystem") as? Bool) ?? true

            let cal = Calendar.current
            let todayRuns = allRuns.filter { cal.isDateInToday($0.date) && !$0.isDeleted }
            let completedMinutes = todayRuns.reduce(0.0) { $0 + $1.duration } / 60.0
            let (_, targetMinutes) = SessionSynthesisEngine.aerobicDurationForExperience(profile.experienceLevel)
            let completionPercent = targetMinutes > 0 ? Int(round(Double(completedMinutes) / Double(targetMinutes) * 100.0)) : 100

            let streakSummary = StreakAndVolumeSummary.evaluate(
                runs: allRuns,
                experienceLevel: profile.experienceLevel,
                trainingGoal: activeGoal,
                now: Date()
            )

            var limitingFactors: [String] = []
            if isDistress || analysis.lockedPrescription.isSubjectiveOverride {
                limitingFactors.append("runner_reported_distress")
            }
            if streakSummary.consecutiveRunDays >= streakSummary.maxConsecutiveDays {
                limitingFactors.append("streak_limit_reached")
            }
            if streakSummary.volumeRatio48h >= streakSummary.volumeCompressionThreshold {
                limitingFactors.append("48h_volume_compression")
            }
            if streakSummary.backToBackHRDecouplingBPM >= 5.0 {
                limitingFactors.append("cardiac_drift")
            }
            if completionPercent >= 80 {
                limitingFactors.append("daily_volume_satisfied")
            }

            let secondRunAdvisable: Bool
            if isDistress || analysis.lockedPrescription.isSubjectiveOverride {
                secondRunAdvisable = false
            } else if todayRuns.isEmpty {
                secondRunAdvisable = true
            } else if todayRuns.count == 1 && (todayRuns[0].duration <= 1320 && (todayRuns[0].prescribedDrillName != nil || todayRuns[0].totalDistanceMeters <= 2000)) {
                secondRunAdvisable = true
            } else if completionPercent >= 80 || streakSummary.shouldRecommendRestDay || streakSummary.volumeRatio48h >= 0.50 {
                secondRunAdvisable = false
            } else {
                secondRunAdvisable = true
            }

            let readinessState: String
            if isDistress || analysis.lockedPrescription.isSubjectiveOverride {
                readinessState = "distress"
            } else {
                readinessState = self.currentReadiness.state.rawValue
            }

            let facts = ReadinessFacts(
                readiness_state: readinessState,
                acwr: self.currentReadiness.acwr,
                streak_days: streakSummary.consecutiveRunDays,
                streak_limit: streakSummary.maxConsecutiveDays,
                last_48h_minutes: streakSummary.last48hDurationMinutes,
                weekly_avg_minutes: streakSummary.trailingWeeklyDurationMinutes,
                volume_ratio_48h: streakSummary.volumeRatio48h,
                volume_threshold: streakSummary.volumeCompressionThreshold,
                hr_shift_bpm: streakSummary.backToBackHRDecouplingBPM,
                today_minutes: completedMinutes,
                today_target_minutes: targetMinutes,
                today_completion_percent: completionPercent,
                second_run_advisable: secondRunAdvisable,
                limiting_factors: limitingFactors,
                experience_level: profile.experienceLevel,
                training_goal: activeGoal,
                cadence_floor_spm: profile.heightAdjustedCadenceFloor
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            if let data = try? encoder.encode(facts),
               let json = String(data: data, encoding: .utf8) {
                return json
            }
            return "{}"
        }

        let queryWorkoutHistoryTool = QueryWorkoutHistoryTool { [weak self] query in
            guard let self else { return "{}" }
            self.toolInvokedDuringActiveTurn = true
            let context = self.runRecord.modelContext
            switch query.scope {
            case .performanceArc:
                return HistoricalRunMatcher.analyzePerformanceArc(relativeTo: self.runRecord, in: context).structuredTelemetryFacts
            case .recentRuns:
                return HistoricalRunMatcher.listRecentRuns(relativeTo: self.runRecord, in: context)
            case .lookup:
                let target = query.target.flatMap { $0.isEmpty ? nil : $0 } ?? "oldest"
                return HistoricalRunMatcher.lookupRun(matching: target, relativeTo: self.runRecord, in: context)
            case .compare:
                let target = query.target.flatMap { $0.isEmpty ? nil : $0 } ?? "previous"
                if let other = query.compareWith, !other.isEmpty,
                   let comparison = HistoricalRunMatcher.compareRuns(queryA: target, queryB: other, relativeTo: self.runRecord, in: context) {
                    return comparison.structuredTelemetryFacts
                }
                guard let prior = HistoricalRunMatcher.findRun(matching: target, relativeTo: self.runRecord, in: context) else {
                    return "{\"status\":\"no_matching_run\",\"target\":\"\(target)\"}"
                }
                return HistoricalRunMatcher.compare(current: self.runRecord, with: prior).structuredTelemetryFacts
            }
        }

        let coachActionTool = ExecuteCoachActionTool { [weak self] query in
            guard let self else { return "{}" }
            self.toolInvokedDuringActiveTurn = true
            let allRuns = (try? self.runRecord.modelContext?.fetch(FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? [self.runRecord]
            let activeGoal = UserDefaults.standard.string(forKey: "trainingGoal") ?? "Base Building"
            let profile = RunnerProfile.compute(from: allRuns)
            let useMetric = (UserDefaults.standard.object(forKey: "useMetricSystem") as? Bool) ?? true
            let calendar = TrainingCalendar(calendar: Calendar.current)

            switch query.action {
            case .displaySession, .displaySchedule:
                let today = calendar.startOfDay(for: Date())
                let fromDate = query.from.flatMap(calendar.parseISO) ?? today
                let toDate = query.to.flatMap(calendar.parseISO) ?? fromDate

                let context = ScheduleEvaluationContext(
                    runRecords: allRuns,
                    activeGoal: activeGoal,
                    profile: profile,
                    useMetric: useMetric
                )

                let schedule = calendar.evaluateSchedule(
                    from: fromDate,
                    to: toDate,
                    context: context
                )

                if query.action == .displaySession || schedule.count == 1 {
                    let dailyState = SessionSynthesisEngine.evaluateDailyState(
                        runRecords: allRuns,
                        activeGoal: activeGoal,
                        experienceLevel: profile.experienceLevel,
                        useMetric: useMetric,
                        userHeightCm: profile.userHeightCm,
                        now: Date()
                    )
                    let sessionToAttach: PrescribedDailySession?
                    switch dailyState {
                    case .preRun(let session):
                        sessionToAttach = session
                    case .completedToday(_, let tomorrowSession):
                        sessionToAttach = tomorrowSession
                    }
                    self.sessionRecommendedThisTurn = sessionToAttach
                    let title = sessionToAttach?.sessionTitle ?? (schedule.first?.planned.title ?? "Upcoming Workout")
                    return "{\"session_title\":\"\(title)\",\"status\":\"session_card_displayed\"}"
                } else {
                    let microcycleDays: [MicrocycleDay] = schedule.map { day in
                        let isRest = day.planned.kind == .rest
                        let icon = isRest ? "bed.double.fill" : "figure.run"
                        let durStr = isRest ? "0 min" : "\(day.planned.minutesLow)–\(day.planned.minutesHigh) min"
                        return MicrocycleDay(
                            id: "\(day.date)-\(day.planned.title)",
                            dayLabel: day.weekday,
                            sessionTitle: "\(day.planned.title) • \(durStr)",
                            iconName: icon,
                            isRestDay: isRest
                        )
                    }
                    self.scheduleRecommendedThisTurn = microcycleDays
                    return "{\"days_count\":\(microcycleDays.count),\"status\":\"schedule_card_displayed\"}"
                }

            case .displayDrill:
                let resolved = PreRunDrillId.resolve(from: query.payload ?? "") ?? .cadencePyramids
                self.drillRecommendedThisTurn = resolved
                return "{\"drill_id\":\"\(resolved.rawValue)\",\"status\":\"interactive_drill_card_displayed\"}"

            case .exportToWatch:
                let resolved = PreRunDrillId.resolve(from: query.payload ?? "") ?? .cadencePyramids
                let template = DrillTemplate.template(for: resolved)
                let baseCadence = Int(self.runRecord.workingAvgCadence) > 0 ? Int(self.runRecord.workingAvgCadence) : 155
                let target = template.calculateTargetCadence(baseCadence)
                let dto = DrillPrescriptionDTO(
                    title: template.title,
                    preRunDrillId: resolved.rawValue,
                    purpose: template.defaultPurpose,
                    targetCadence: target,
                    previousCadence: baseCadence
                )
                Task {
                    let bridge = WorkoutBridge()
                    try? await bridge.scheduleDrill(dto: dto)
                }
                return "{\"drill_id\":\"\(resolved.rawValue)\",\"status\":\"exported_to_watch\"}"

            case .updateGoal:
                let newGoal: String
                if let directGoal = query.goal {
                    newGoal = directGoal.rawValue
                } else if let payloadGoal = query.payload?.trimmingCharacters(in: .whitespacesAndNewlines), !payloadGoal.isEmpty {
                    let lower = payloadGoal.lowercased()
                    if lower.contains("marathon") && !lower.contains("half") {
                        newGoal = "Marathon"
                    } else if lower.contains("half") {
                        newGoal = "Half Marathon"
                    } else if lower.contains("10k") {
                        newGoal = "10K Race"
                    } else if lower.contains("5k") {
                        newGoal = "5K Race"
                    } else if lower.contains("fun") {
                        newGoal = "Just for Fun"
                    } else if lower.contains("injury") {
                        newGoal = "Injury Recovery"
                    } else {
                        newGoal = payloadGoal
                    }
                } else {
                    newGoal = "Base Building"
                }
                UserDefaults.standard.set(newGoal, forKey: "trainingGoal")
                return "{\"goal\":\"\(newGoal)\",\"status\":\"training_goal_updated\"}"

            case .displayExplainer:
                let rawKey = query.payload?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let asset = CoachingAssetLibrary.resolve(key: rawKey) ?? CoachingAssetLibrary.defaultAsset(for: rawKey)
                self.explainerRecommendedThisTurn = asset.key
                return "{\"explainer_key\":\"\(asset.key)\",\"status\":\"interactive_explainer_card_displayed\"}"

            case .recordFeedback:
                let feedback = query.payload ?? ""
                if !feedback.isEmpty {
                    self.runRecord.framboiseTags.append("feedback:\(feedback.prefix(40))")
                    try? self.runRecord.modelContext?.save()
                }
                return "{\"status\":\"feedback_recorded\"}"
            }
        }

        let tools: [any Tool] = [
            inspectWorkoutTool,
            getTrainingScheduleTool,
            getReadinessAndWorkloadTool,
            queryWorkoutHistoryTool,
            coachActionTool
        ]
        let instructions = buildLeanSystemInstructions()
        let session = LanguageModelSession(
            model: SystemLanguageModel.default,
            tools: tools,
            instructions: instructions
        )
        self.modelSession = session
        return session
    }

    @available(iOS 26.0, *)
    private func isNonRetryableError(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let genError = error as? LanguageModelSession.GenerationError {
            switch genError {
            case .guardrailViolation, .refusal, .unsupportedLanguageOrLocale:
                return true
            default:
                return false
            }
        }
        return false
    }

    @available(iOS 26.0, *)
    private func generateFoundationModelResponse(for userQuestion: String) async throws -> String {
        do {
            let response = try await getOrCreateSession().respond(to: userQuestion)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            if isNonRetryableError(error) {
                throw error
            }

            // Invariant 3: Cooperative cancellation across the 300ms backoff
            try await Task.sleep(for: .milliseconds(300))
            try Task.checkCancellation()

            self.modelSession = nil
            let retry = try await getOrCreateSession().respond(to: userQuestion)
            return retry.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    #endif

    /// Synthesizes 1,000-meter splits from phase segments if physical splits were not persisted.
    nonisolated static func synthesizeSplitsFromSegments(_ segments: [PhaseSegment], splitDistanceMeters: Double = 1000.0) -> [RunSplit] {
        RunSplit.synthesize(from: segments, splitDistanceMeters: splitDistanceMeters)
    }

    // MARK: - Honest System Status (No Fake Canned Responses)

    private func systemUnavailableMessage() -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if !SystemLanguageModel.default.isAvailable {
                return "AI Coach interactive conversation requires Apple Intelligence on iOS 26 or later. Please ensure Apple Intelligence is enabled in Settings."
            }
        }
        #endif
        return "I'm having trouble analyzing this run right now. Please try asking again in a moment."
    }

    // MARK: - Readiness & Recovery Timeline

    var readinessAssessment: ReadinessAssessment {
        assessReadiness(asOf: runRecord.date)
    }

    var currentReadiness: ReadinessAssessment {
        assessReadiness(asOf: Date())
    }

    private func assessReadiness(asOf date: Date) -> ReadinessAssessment {
        if let context = runRecord.modelContext {
            return ReadinessEvaluator.assess(context: context, now: date)
        }
        if let profile = macroProfile {
            let state: ReadinessState = (profile.acwr ?? 1.0) > 1.4 ? .acuteFatigue : .productive
            return ReadinessAssessment(
                state: state,
                triggers: [],
                acuteLoad: profile.acuteLoad,
                chronicWeeklyLoad: profile.chronicWeeklyLoad,
                acwr: profile.acwr,
                mileageDropFraction: nil
            )
        }
        return ReadinessAssessment.productive
    }

    var isHeavySession: Bool {
        ReadinessRunSnapshot(run: runRecord).isHardSession
    }

    private var recentSnapshots: [ReadinessRunSnapshot] {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        var snapshots: [ReadinessRunSnapshot] = []
        if let context = runRecord.modelContext {
            let descriptor = FetchDescriptor<RunRecord>(
                predicate: #Predicate<RunRecord> { $0.date >= cutoff },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            snapshots = (try? context.fetch(descriptor))?.map(ReadinessRunSnapshot.init(run:)) ?? []
        }
        if !snapshots.contains(where: { $0.date == runRecord.date }) {
            snapshots.append(ReadinessRunSnapshot(run: runRecord))
        }
        return snapshots
    }

    var recoveryTimeline: RecoveryTimeline {
        RecoveryTimeline.build(runs: recentSnapshots, readiness: currentReadiness, now: Date())
    }

    var runnerProfile: RunnerProfile {
        var historicalRuns: [RunRecord] = []
        if let context = runRecord.modelContext {
            let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
            let desc = FetchDescriptor<RunRecord>(predicate: #Predicate<RunRecord> { $0.date >= cutoff })
            historicalRuns = (try? context.fetch(desc)) ?? []
        }
        if !historicalRuns.contains(where: { $0.date == runRecord.date }) {
            historicalRuns.append(runRecord)
        }
        return RunnerProfile.compute(from: historicalRuns, now: Date())
    }
}
