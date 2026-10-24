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
    private let runRecord: RunRecord?
    private var explicitModelContext: ModelContext?

    var modelContext: ModelContext? {
        explicitModelContext ?? runRecord?.modelContext
    }

    func setModelContextIfNeeded(_ context: ModelContext) {
        if self.explicitModelContext == nil {
            self.explicitModelContext = context
        }
    }

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
    private var toolInvokedDuringActiveTurn: Bool = false
    #endif

    #if DEBUG
    /// Optional closure allowing unit tests to simulate model free-speech responses and inspect system instructions.
    var modelResponder: ((_ systemInstructions: String, _ userQuestion: String) async throws -> String)?
    #endif

    private var baselineStats: (avgPace: Double, avgCadence: Double, avgHR: Double)? {
        let targetDate = runRecord?.date ?? Date()
        guard let context = modelContext,
              let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: targetDate) else {
            return nil
        }
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
        self.explicitModelContext = runRecord.modelContext
        self.mode = mode
        self.runSignature = runSignature ?? runRecord.signature
        self.macroProfile = macroProfile ?? MacroProfile.load()
    }

    init(
        modelContext: ModelContext? = nil,
        runRecord: RunRecord? = nil,
        mode: AnalystChatMode = .macroCoach,
        runSignature: RunSignature? = nil,
        macroProfile: MacroProfile? = nil
    ) {
        self.runRecord = runRecord
        self.explicitModelContext = modelContext ?? runRecord?.modelContext
        self.mode = mode
        self.runSignature = runSignature ?? runRecord?.signature
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
            // Recycle the ephemeral session if 4 turns have elapsed.
            if self.turnsSinceSessionRecycle >= 4 {
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
                    let cleaned = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
                    messages.append(
                        AnalystChatMessage(
                            sender: .analyst,
                            text: cleaned,
                            attachedDrillId: drillRecommendedThisTurn,
                            attachedSession: sessionRecommendedThisTurn,
                            attachedExplainerKey: explainerRecommendedThisTurn,
                            attachedSchedule: scheduleRecommendedThisTurn,
                            status: .delivered
                        )
                    )
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
                    let cleaned = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
                    messages.append(
                        AnalystChatMessage(
                            sender: .analyst,
                            text: cleaned,
                            attachedDrillId: drillRecommendedThisTurn,
                            attachedSession: sessionRecommendedThisTurn,
                            attachedExplainerKey: explainerRecommendedThisTurn,
                            attachedSchedule: scheduleRecommendedThisTurn,
                            status: .delivered
                        )
                    )
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
        let run = runRecord ?? (try? modelContext?.fetch(FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])))?.first ?? RunRecord(
            hkWorkoutID: UUID(),
            date: Date(),
            totalDistanceMeters: 0,
            duration: 0,
            rawAvgPace: 0,
            rawAvgHeartRate: 0,
            rawAvgCadence: 0,
            workingAvgPace: 0,
            workingAvgCadence: 0,
            workingAvgHeartRate: 0,
            paceCV: 0,
            paceSlope: 0,
            percentZone4: 0,
            detectedTypeRaw: "Run"
        )
        let totalRuns = (try? modelContext?.fetchCount(FetchDescriptor<RunRecord>())) ?? 1
        return WorkoutAnalysisContext(
            runRecord: run,
            runSignature: runSignature ?? run.signature,
            macroProfile: macroProfile,
            recoveryTimeline: recoveryTimeline,
            baselineStats: baselineStats,
            runnerProfile: runnerProfile,
            isSubjectiveDistress: isSubjectiveDistress,
            totalHistoricalRunsCount: totalRuns
        )
    }

    func makeAnalysisContext(for targetRun: RunRecord?, isSubjectiveDistress: Bool = false) -> WorkoutAnalysisContext? {
        guard let run = targetRun ?? runRecord else { return nil }
        let totalRuns = (try? modelContext?.fetchCount(FetchDescriptor<RunRecord>())) ?? 1
        return WorkoutAnalysisContext(
            runRecord: run,
            runSignature: runSignature ?? run.signature,
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

        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "EEE, MMM d, yyyy"
        let today = calendar.startOfDay(for: Date())
        let todayDateStr = df.string(from: today)

        let contextBlock: String
        if mode == .macroCoach {
            let allRuns = (try? modelContext?.fetch(FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? (runRecord.map { [$0] } ?? [])
            let todayRuns = allRuns.filter { calendar.calendar.isDateInToday($0.date) && !$0.isDeleted }
            let activeGoal = UserDefaults.standard.string(forKey: "trainingGoal") ?? "Base Building"
            let profile = RunnerProfile.compute(from: allRuns)
            let todaySchedule = calendar.evaluateSchedule(
                from: today,
                to: today,
                context: ScheduleEvaluationContext(runRecords: allRuns, activeGoal: activeGoal, profile: profile, useMetric: useMetric)
            ).first

            let scheduledTodayStr: String
            if let plan = todaySchedule?.planned {
                if plan.kind == .rest {
                    scheduledTodayStr = "Rest Day"
                } else {
                    scheduledTodayStr = "\(plan.title) (\(plan.minutesLow)–\(plan.minutesHigh) min)"
                }
            } else {
                scheduledTodayStr = "Rest Day"
            }

            let tomorrow = calendar.calendar.date(byAdding: .day, value: 1, to: today) ?? today
            let tomorrowDateStr = df.string(from: tomorrow)
            let tomorrowSchedule = calendar.evaluateSchedule(
                from: calendar.startOfDay(for: tomorrow),
                to: calendar.startOfDay(for: tomorrow),
                context: ScheduleEvaluationContext(runRecords: allRuns, activeGoal: activeGoal, profile: profile, useMetric: useMetric)
            ).first

            let scheduledTomorrowStr: String
            if let plan = tomorrowSchedule?.planned {
                if plan.kind == .rest {
                    scheduledTomorrowStr = "Rest Day"
                } else {
                    scheduledTomorrowStr = "\(plan.title) (\(plan.minutesLow)–\(plan.minutesHigh) min)"
                }
            } else {
                scheduledTomorrowStr = "Rest Day"
            }

            let loggedTodayStr = todayRuns.isEmpty ? "None" : "\(todayRuns.count) run"

            var nextRunNote = ""
            if let next = findNextScheduledRun() {
                let nextDateStr = df.string(from: next.date)
                nextRunNote = " Next: \(nextDateStr) (\(next.day.planned.minutesHigh)m)."
            }
            contextBlock = "Today: (\(todayDateStr)) \(scheduledTodayStr) (\(loggedTodayStr)). Tomorrow: (\(tomorrowDateStr)) \(scheduledTomorrowStr).\(nextRunNote)"
        } else if let runRecord {
            let daysDiff = max(0, Calendar.current.dateComponents([.day], from: runRecord.date, to: Date()).day ?? 0)
            let runDateStr = df.string(from: runRecord.date)
            let temporalGrounding = daysDiff == 0 ? "Today" : "\(runDateStr) (\(daysDiff)d ago)"
            let runType = runRecord.normalizedClassification
            let envNote = (runRecord.isIndoor ?? false) ? "Indoor" : "Outdoor"
            contextBlock = "Today is \(todayDateStr). Workout: \(runType) (\(envNote), \(temporalGrounding))."
        } else {
            contextBlock = "General Coaching: Today is \(todayDateStr)."
        }

        var recentContextBlock = ""
        let deliveredMessages = self.messages.filter { $0.status == .delivered }
        let completedHistory = deliveredMessages.dropLast(self.messages.last?.sender == .user ? 1 : 0)
        let recentTurns = completedHistory.suffix(2)

        if !recentTurns.isEmpty {
            var lines: [String] = ["RECENT DIALOGUE (Reference Only):"]
            for msg in recentTurns {
                let role = msg.sender == .user ? "Runner" : "Coach"
                let cleaned = msg.text.replacingOccurrences(of: "\n", with: " ")
                let truncated = cleaned.count > 30 ? "\(cleaned.prefix(28))..." : cleaned
                lines.append("• \(role): \"\(truncated)\"")
            }
            recentContextBlock = "\n\n" + lines.joined(separator: "\n")
        }

        return """
        Runalyst coach. Empathy, warmth, brevity.

        CONTEXT:
        \(contextBlock)\(recentContextBlock)

        TOOLS:
        • `getTrainingSchedule`: Timeline.
        • `getReadinessAndWorkload`: Fatigue, ACWR.
        • `queryWorkoutHistory`: History.
        • `inspectWorkout`: Splits.
        • `executeCoachAction`: Actions (prescribe_drill, explain_metric, export_to_watch, record_feedback, update_goal).

        RULES:
        • Outside Running: Sidestep non-running topics gracefully.
        • Medical Safety: Urge rest on pain/fatigue. Never bring up unasked second runs.
        • Units: SPM, min/km. No LaTeX. Steady runs use splits, never reps.
        • Workload: Trust 'workload_zone' ('underload', 'optimal', 'overreaching', 'spike'). Underload means volume is light, not high.
        • Silent Tools: Never write command names or code syntax in conversational text.

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
        self.toolInvokedDuringActiveTurn = false

        let inspectWorkoutTool = InspectWorkoutTool { [weak self] _ in
            guard let self else { return "" }
            self.toolInvokedDuringActiveTurn = true
            if self.runRecord != nil || (try? self.modelContext?.fetchCount(FetchDescriptor<RunRecord>())) ?? 0 > 0 {
                return self.makeAnalysisContext().compactTelemetryAnalysis()
            }
            return "{\"status\":\"no_workout_recorded\"}"
        }

        let getTrainingScheduleTool = GetTrainingScheduleTool { [weak self] query in
            guard let self else { return "No schedule days planned." }
            return self.executeTrainingScheduleQuery(query: query)
        }

        let getReadinessAndWorkloadTool = GetReadinessAndWorkloadTool { [weak self] _ in
            guard let self else { return "{}" }
            return self.executeReadinessAndWorkloadQuery()
        }

        let queryWorkoutHistoryTool = QueryWorkoutHistoryTool { [weak self] query in
            guard let self else { return "{}" }
            self.toolInvokedDuringActiveTurn = true
            let context = self.modelContext
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
                if let run = self.runRecord {
                    return HistoricalRunMatcher.compare(current: run, with: prior).structuredTelemetryFacts
                } else if let latest = (try? context?.fetch(FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])))?.first, latest.id != prior.id {
                    return HistoricalRunMatcher.compare(current: latest, with: prior).structuredTelemetryFacts
                } else {
                    return "{\"status\":\"insufficient_runs_for_comparison\"}"
                }
            }
        }

        let coachActionTool = ExecuteCoachActionTool { [weak self] query in
            guard let self else { return "{\"error\":\"engine_deallocated\"}" }
            return await self.executeCoachAction(query: query)
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
        assessReadiness(asOf: mode == .macroCoach ? Date() : (runRecord?.date ?? Date()))
    }

    var currentReadiness: ReadinessAssessment {
        assessReadiness(asOf: Date())
    }

    private func assessReadiness(asOf date: Date) -> ReadinessAssessment {
        if let context = modelContext {
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
        guard let run = runRecord else { return false }
        return ReadinessRunSnapshot(run: run).isHardSession
    }

    private var recentSnapshots: [ReadinessRunSnapshot] {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        var snapshots: [ReadinessRunSnapshot] = []
        if let context = modelContext {
            let descriptor = FetchDescriptor<RunRecord>(
                predicate: #Predicate<RunRecord> { $0.date >= cutoff },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            snapshots = (try? context.fetch(descriptor))?.map(ReadinessRunSnapshot.init(run:)) ?? []
        }
        if let run = runRecord, !snapshots.contains(where: { $0.date == run.date }) {
            snapshots.append(ReadinessRunSnapshot(run: run))
        }
        return snapshots
    }

    var recoveryTimeline: RecoveryTimeline {
        RecoveryTimeline.build(runs: recentSnapshots, readiness: currentReadiness, now: Date())
    }

    var runnerProfile: RunnerProfile {
        var historicalRuns: [RunRecord] = []
        if let context = modelContext {
            let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
            let desc = FetchDescriptor<RunRecord>(predicate: #Predicate<RunRecord> { $0.date >= cutoff })
            historicalRuns = (try? context.fetch(desc)) ?? []
        }
        if let run = runRecord, !historicalRuns.contains(where: { $0.date == run.date }) {
            historicalRuns.append(run)
        }
        return RunnerProfile.compute(from: historicalRuns, now: Date())
    }

    func findNextScheduledRun() -> (date: Date, day: ScheduleDay)? {
        let allRuns = (try? self.modelContext?.fetch(FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? (self.runRecord.map { [$0] } ?? [])
        let activeGoal = UserDefaults.standard.string(forKey: "trainingGoal") ?? "Base Building"
        let profile = RunnerProfile.compute(from: allRuns)
        let useMetric = (UserDefaults.standard.object(forKey: "useMetricSystem") as? Bool) ?? true
        let calendar = TrainingCalendar(calendar: Calendar.current)
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let schedule = calendar.evaluateSchedule(
            from: tomorrow,
            to: calendar.calendar.date(byAdding: .day, value: 7, to: today) ?? today,
            context: ScheduleEvaluationContext(runRecords: allRuns, activeGoal: activeGoal, profile: profile, useMetric: useMetric)
        )
        for day in schedule {
            if day.planned.kind != .rest, let date = calendar.parseISO(day.date) {
                return (date, day)
            }
        }
        return nil
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    @discardableResult
    func executeTrainingScheduleQuery(query: GetTrainingScheduleQuery) -> String {
        self.toolInvokedDuringActiveTurn = true
        let allRuns = (try? self.modelContext?.fetch(FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? (self.runRecord.map { [$0] } ?? [])
        let activeGoal = UserDefaults.standard.string(forKey: "trainingGoal") ?? "Base Building"
        let profile = RunnerProfile.compute(from: allRuns)
        let useMetric = (UserDefaults.standard.object(forKey: "useMetricSystem") as? Bool) ?? true
        let calendar = TrainingCalendar(calendar: Calendar.current)

        let fromDate = calendar.parseISO(query.from) ?? calendar.startOfDay(for: Date())
        let toDate: Date
        let isExplicitWindow = query.to != nil
        if let toStr = query.to, let parsedTo = calendar.parseISO(toStr) {
            toDate = calendar.startOfDay(for: parsedTo)
        } else {
            toDate = calendar.calendar.date(byAdding: .day, value: 6, to: fromDate) ?? fromDate
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

        // Unified Schedule Dance: bind the interactive visual representation alongside the query
        if !isExplicitWindow {
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

            if let session = sessionToAttach, session.isRestDay, let next = findNextScheduledRun() {
                let day = next.day
                let primerTitle = day.planned.primerTitle ?? "Strides"
                let primerId = PreRunDrillId.resolve(from: primerTitle) ?? .strides
                let dateStr = TrainingCalendar.weekdayFormatter.string(from: next.date)
                let cadenceFloor = day.planned.cadenceFloor ?? 155
                let primerTarget = DrillTemplate.template(for: primerId).calculateTargetCadence(cadenceFloor)

                self.sessionRecommendedThisTurn = PrescribedDailySession(
                    targetGoal: activeGoal,
                    sessionTitle: day.planned.title,
                    durationBand: "\(day.planned.minutesLow)–\(day.planned.minutesHigh) min",
                    paceBand: day.planned.paceBand ?? "Easy Aerobic",
                    hrCap: day.planned.hrCap ?? "< 152 BPM",
                    cadenceFloor: cadenceFloor,
                    groundedRationale: "Scheduled next run on your training calendar.",
                    readinessStateText: "Upcoming Planned Session",
                    readinessTriggerLead: nil,
                    primerDrillId: primerId,
                    primerDrillTitle: primerTitle,
                    primerTargetCadence: primerTarget,
                    primerWorkDescription: "Pre-run technique primer.",
                    primerPhasesDuration: "10 min",
                    isTrimmed: false,
                    microcycle: [],
                    mainSessionTemplateId: .zone2Run,
                    mainRunDurationMinutes: day.planned.minutesHigh,
                    completedPrimerRun: nil,
                    isRestDay: false,
                    dayLabel: dateStr,
                    isToday: false
                )
            } else {
                self.sessionRecommendedThisTurn = sessionToAttach
            }
        } else if schedule.count == 1 {
            let dailyState = SessionSynthesisEngine.evaluateDailyState(
                runRecords: allRuns,
                activeGoal: activeGoal,
                experienceLevel: profile.experienceLevel,
                useMetric: useMetric,
                userHeightCm: profile.userHeightCm,
                now: fromDate
            )
            switch dailyState {
            case .preRun(let session):
                self.sessionRecommendedThisTurn = session
            case .completedToday(_, let tomorrowSession):
                self.sessionRecommendedThisTurn = tomorrowSession
            }
        } else {
            let microcycleDays: [MicrocycleDay] = schedule.compactMap { day in
                if day.relative == .today && day.completion == .completed {
                    return nil
                }
                let isRest = day.planned.kind == .rest
                let icon = isRest ? "bed.double.fill" : "figure.run"
                let title = isRest ? day.planned.title : "\(day.planned.title) • \(day.planned.minutesLow)–\(day.planned.minutesHigh) min"
                return MicrocycleDay(
                    id: "\(day.date)-\(day.planned.title)",
                    dayLabel: day.weekday,
                    sessionTitle: title,
                    iconName: icon,
                    isRestDay: isRest
                )
            }
            self.scheduleRecommendedThisTurn = microcycleDays
        }
        self.harmonizeAttachments()

        return TrainingCalendar.formatCompactScheduleSummary(days: schedule)
    }

    @available(iOS 26.0, *)
    @discardableResult
    func executeReadinessAndWorkloadQuery() -> String {
        self.toolInvokedDuringActiveTurn = true
        let allRuns = (try? self.modelContext?.fetch(FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? (self.runRecord.map { [$0] } ?? [])
        let activeGoal = UserDefaults.standard.string(forKey: "trainingGoal") ?? "Base Building"
        let profile = RunnerProfile.compute(from: allRuns)

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
        if todayRuns.isEmpty {
            secondRunAdvisable = true
        } else if todayRuns.count == 1 && (todayRuns[0].duration <= 1320 && (todayRuns[0].prescribedDrillName != nil || todayRuns[0].totalDistanceMeters <= 2000)) {
            secondRunAdvisable = true
        } else if completionPercent >= 80 || streakSummary.shouldRecommendRestDay || streakSummary.volumeRatio48h >= 0.50 {
            secondRunAdvisable = false
        } else {
            secondRunAdvisable = true
        }

        let acwrVal = self.currentReadiness.acwr
        let workloadZone: WorkloadZone
        if let acwr = acwrVal {
            if acwr < 0.8 {
                workloadZone = .underload
            } else if acwr <= 1.3 {
                workloadZone = .optimal
            } else if acwr <= 1.5 {
                workloadZone = .overreaching
            } else {
                workloadZone = .spike
            }
        } else {
            workloadZone = .optimal
        }

        let facts = ReadinessFacts(
            readiness_state: self.currentReadiness.state.rawValue,
            acwr: acwrVal,
            workload_zone: workloadZone,
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

    @available(iOS 26.0, *)
    @discardableResult
    func executeCoachAction(query: ExecuteCoachActionQuery) async -> String {
        self.toolInvokedDuringActiveTurn = true
        let allRuns = (try? self.modelContext?.fetch(FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? (self.runRecord.map { [$0] } ?? [])
        let profile = RunnerProfile.compute(from: allRuns)

        switch query.action {
        case .prescribeDrill:
            let cal = Calendar.current
            let todayRuns = allRuns.filter { cal.isDateInToday($0.date) && !$0.isDeleted }
            let completedMinutes = todayRuns.reduce(0.0) { $0 + $1.duration } / 60.0
            let (_, targetMinutes) = SessionSynthesisEngine.aerobicDurationForExperience(profile.experienceLevel)
            let isFatigued = completedMinutes >= Double(targetMinutes) * 0.8 || todayRuns.count >= 2

            if isFatigued {
                return "{\"status\":\"drill_blocked_due_to_daily_fatigue\",\"message\":\"Runner already completed daily training volume. Rest is prioritized.\"}"
            }

            let resolved = PreRunDrillId.resolve(from: query.payload ?? "") ?? .strides
            self.drillRecommendedThisTurn = resolved
            harmonizeAttachments()
            return "{\"drill_id\":\"\(resolved.rawValue)\",\"drill_name\":\"\(resolved.title)\",\"status\":\"drill_prescribed\",\"message\":\"The \(resolved.title) technique drill is attached to your recommendation.\"}"

        case .exportToWatch:
            let resolved = PreRunDrillId.resolve(from: query.payload ?? "") ?? .strides
            let template = DrillTemplate.template(for: resolved)
            let baseCadence = Int(self.runRecord?.workingAvgCadence ?? 0) > 0 ? Int(self.runRecord?.workingAvgCadence ?? 0) : 155
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

        case .explainMetric:
            let rawKey = query.payload?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let asset = CoachingAssetLibrary.resolve(key: rawKey) ?? CoachingAssetLibrary.defaultAsset(for: rawKey)
            self.explainerRecommendedThisTurn = asset.key
            harmonizeAttachments()
            return "{\"explainer_key\":\"\(asset.key)\",\"title\":\"\(asset.title)\",\"status\":\"metric_explained\",\"message\":\"The \(asset.title) diagnostic explainer is attached.\"}"

        case .recordFeedback:
            let feedback = query.payload ?? ""
            if !feedback.isEmpty, let run = self.runRecord {
                run.framboiseTags.append("feedback:\(feedback.prefix(40))")
                try? run.modelContext?.save()
            }
            return "{\"status\":\"feedback_recorded\"}"
        }
    }

    private func harmonizeAttachments() {
        if let session = self.sessionRecommendedThisTurn, let drill = self.drillRecommendedThisTurn {
            if session.primerDrillId == drill {
                self.drillRecommendedThisTurn = nil
            }
        }
        if self.sessionRecommendedThisTurn != nil {
            self.scheduleRecommendedThisTurn = nil
        }
    }
    #endif
}
