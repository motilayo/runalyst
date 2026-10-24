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
                    let sanitized = AnalystResponseSanitizer.sanitize(text: responseText)
                    var wasExplicitToolDrill = false
                    if let action = sanitized.detectedAction {
                        if action == .displayDrill { wasExplicitToolDrill = true }
                        applyFallbackCoachAction(action: action, payload: sanitized.detectedPayload)
                    }
                    resolveProactiveAttachments(userQuestion: userQuestion, sanitizedText: sanitized.text, wasExplicitToolDrill: wasExplicitToolDrill)
                    messages.append(
                        AnalystChatMessage(
                            sender: .analyst,
                            text: sanitized.text,
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
                    let sanitized = AnalystResponseSanitizer.sanitize(text: responseText)
                    var wasExplicitToolDrill = false
                    if let action = sanitized.detectedAction {
                        if action == .displayDrill { wasExplicitToolDrill = true }
                        applyFallbackCoachAction(action: action, payload: sanitized.detectedPayload)
                    }
                    resolveProactiveAttachments(userQuestion: userQuestion, sanitizedText: sanitized.text, wasExplicitToolDrill: wasExplicitToolDrill)
                    messages.append(
                        AnalystChatMessage(
                            sender: .analyst,
                            text: sanitized.text,
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
                let cleaned = AnalystResponseSanitizer.sanitize(text: msg.text).text.replacingOccurrences(of: "\n", with: " ")
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
        • `executeCoachAction`: Actions (display_drill, display_schedule, display_session, display_explainer, export_to_watch, record_feedback, update_goal).

        RULES:
        • Outside Running: Sidestep non-running topics gracefully.
        • Medical Safety: Urge rest on pain/fatigue. Never bring up unasked second runs.
        • Units: SPM, min/km. No LaTeX. Steady runs use splits, never reps.
        • ACWR: Acute:Chronic Workload Ratio (<0.8=low, >1.4=spike; low != overload).
        • Proactive Cards: Never ask permission to show drills/schedule; trigger directly.
        • Silent Tools: Never write commands ('executeCoachAction', 'display_drill', 'Display the drill') in text.

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
            self.toolInvokedDuringActiveTurn = true
            let allRuns = (try? self.modelContext?.fetch(FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? (self.runRecord.map { [$0] } ?? [])
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

            let isOverride = isDistress || self.makeAnalysisContext(isSubjectiveDistress: isDistress).lockedPrescription.isSubjectiveOverride

            var limitingFactors: [String] = []
            if isOverride {
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
            if isOverride {
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
            if isOverride {
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
            guard let self else { return "{}" }
            self.toolInvokedDuringActiveTurn = true
            let allRuns = (try? self.modelContext?.fetch(FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? (self.runRecord.map { [$0] } ?? [])
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
                    return "{\"session_title\":\"\(title)\",\"status\":\"interactive_session_card_displayed\",\"message\":\"The \(title) workout session card is displayed directly below your response.\"}"
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
                    return "{\"days_count\":\(microcycleDays.count),\"status\":\"interactive_schedule_card_displayed\",\"message\":\"The training schedule timeline card is displayed directly below your response.\"}"
                }

            case .displayDrill:
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
                return "{\"drill_id\":\"\(resolved.rawValue)\",\"drill_name\":\"\(resolved.title)\",\"status\":\"interactive_drill_card_displayed\",\"message\":\"The \(resolved.title) interactive workout card is displayed directly below your response.\"}"

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

            case .displayExplainer:
                let rawKey = query.payload?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let asset = CoachingAssetLibrary.resolve(key: rawKey) ?? CoachingAssetLibrary.defaultAsset(for: rawKey)
                self.explainerRecommendedThisTurn = asset.key
                return "{\"explainer_key\":\"\(asset.key)\",\"title\":\"\(asset.title)\",\"status\":\"interactive_explainer_card_displayed\",\"message\":\"The \(asset.title) explainer card is displayed directly below your response.\"}"

            case .recordFeedback:
                let feedback = query.payload ?? ""
                if !feedback.isEmpty, let run = self.runRecord {
                    run.framboiseTags.append("feedback:\(feedback.prefix(40))")
                    try? run.modelContext?.save()
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

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    func applyFallbackCoachAction(action: CoachActionType, payload: String?) {
        switch action {
        case .displayDrill:
            if self.drillRecommendedThisTurn == nil {
                let drillStr = payload ?? ""
                if let resolved = PreRunDrillId.resolve(from: drillStr) {
                    self.drillRecommendedThisTurn = resolved
                } else if drillStr.contains("tempo") || drillStr.contains("surge") {
                    self.drillRecommendedThisTurn = .tempoSurges
                } else if drillStr.contains("pyramid") || drillStr.contains("cadence") {
                    self.drillRecommendedThisTurn = .cadencePyramids
                } else if drillStr.contains("stride") {
                    self.drillRecommendedThisTurn = .strides
                } else if drillStr.contains("rhythm") {
                    self.drillRecommendedThisTurn = .rhythmIntervals
                } else if drillStr.contains("hill") {
                    self.drillRecommendedThisTurn = .hillBounds
                } else {
                    self.drillRecommendedThisTurn = .strides
                }
            }
        case .displaySchedule:
            if self.scheduleRecommendedThisTurn == nil {
                let allRuns = (try? self.modelContext?.fetch(FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? (self.runRecord.map { [$0] } ?? [])
                let activeGoal = UserDefaults.standard.string(forKey: "trainingGoal") ?? "Base Building"
                let profile = RunnerProfile.compute(from: allRuns)
                let useMetric = (UserDefaults.standard.object(forKey: "useMetricSystem") as? Bool) ?? true
                let calendar = TrainingCalendar(calendar: Calendar.current)
                let today = calendar.startOfDay(for: Date())
                let toDate: Date = {
                    if payload == "rest_of_week" {
                        let weekEnd = calendar.weekInterval(containing: today).end
                        return weekEnd > today ? weekEnd : (calendar.calendar.date(byAdding: .day, value: 4, to: today) ?? today)
                    }
                    return calendar.calendar.date(byAdding: .day, value: 5, to: today) ?? today
                }()
                let schedule = calendar.evaluateSchedule(
                    from: today,
                    to: toDate,
                    context: ScheduleEvaluationContext(runRecords: allRuns, activeGoal: activeGoal, profile: profile, useMetric: useMetric)
                )
                self.scheduleRecommendedThisTurn = schedule.compactMap { day in
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
            }
        case .displaySession:
            if self.sessionRecommendedThisTurn == nil {
                let allRuns = (try? self.modelContext?.fetch(FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? (self.runRecord.map { [$0] } ?? [])
                let activeGoal = UserDefaults.standard.string(forKey: "trainingGoal") ?? "Base Building"
                let profile = RunnerProfile.compute(from: allRuns)
                let useMetric = (UserDefaults.standard.object(forKey: "useMetricSystem") as? Bool) ?? true
                let dailyState = SessionSynthesisEngine.evaluateDailyState(
                    runRecords: allRuns,
                    activeGoal: activeGoal,
                    experienceLevel: profile.experienceLevel,
                    useMetric: useMetric,
                    userHeightCm: profile.userHeightCm,
                    now: Date()
                )
                switch dailyState {
                case .preRun(let session):
                    self.sessionRecommendedThisTurn = session
                case .completedToday(_, let tomorrowSession):
                    self.sessionRecommendedThisTurn = tomorrowSession
                }
            }
        case .displayExplainer:
            if self.explainerRecommendedThisTurn == nil, let rawKey = payload?.trimmingCharacters(in: .whitespacesAndNewlines), !rawKey.isEmpty {
                let asset = CoachingAssetLibrary.resolve(key: rawKey) ?? CoachingAssetLibrary.defaultAsset(for: rawKey)
                self.explainerRecommendedThisTurn = asset.key
            }
        case .updateGoal:
            if let newGoal = payload?.trimmingCharacters(in: .whitespacesAndNewlines), !newGoal.isEmpty {
                UserDefaults.standard.set(newGoal, forKey: "trainingGoal")
            }
        case .exportToWatch, .recordFeedback:
            break
        }
    }

    private func resolveProactiveAttachments(userQuestion: String, sanitizedText: String, wasExplicitToolDrill: Bool = false) {
        let lowerUser = userQuestion.lowercased()
        let lowerResponse = sanitizedText.lowercased()

        let allRuns = (try? self.modelContext?.fetch(FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? (self.runRecord.map { [$0] } ?? [])
        let cal = Calendar.current
        let todayRuns = allRuns.filter { cal.isDateInToday($0.date) && !$0.isDeleted }
        let completedMinutes = todayRuns.reduce(0.0) { $0 + $1.duration } / 60.0
        let profile = RunnerProfile.compute(from: allRuns)
        let (_, targetMinutes) = SessionSynthesisEngine.aerobicDurationForExperience(profile.experienceLevel)
        let isTodayDone = completedMinutes >= Double(targetMinutes) * 0.8 || todayRuns.count >= 2

        // 1. Standalone Drill Attachment
        if self.drillRecommendedThisTurn == nil {
            if isAffirmativeOrDisplayCommand(lowerUser) {
                // User explicitly said "yes" or "display the drill"
                if let drill = findRecentDrillMentionInHistory() {
                    self.drillRecommendedThisTurn = drill
                }
            } else if isNextRunQuery(lowerUser) {
                // When answering next run, check if coach specifically recommended a primer drill in response
                if let drill = PreRunDrillId.resolve(from: sanitizedText) {
                    self.drillRecommendedThisTurn = drill
                }
            } else if lowerUser.contains("which drill") || lowerUser.contains("what drill") || lowerUser.contains("suggest a drill") || lowerUser.contains("give me a drill") || lowerUser.contains("recommend a drill") || lowerUser.contains("show me a drill") || lowerUser.contains("need a drill") || lowerUser.contains("drill to") || lowerUser.contains("drill for") || lowerUser.contains("drill would") || lowerUser.contains("strides") || lowerUser.contains("cadence pyramid") || lowerUser.contains("tempo surge") || lowerUser.contains("rhythm interval") {
                if let drill = PreRunDrillId.resolve(from: userQuestion) ?? PreRunDrillId.resolve(from: sanitizedText) {
                    self.drillRecommendedThisTurn = drill
                }
            }
        }

        // 2. Proactive Session / Schedule Attachment
        if self.sessionRecommendedThisTurn == nil && self.scheduleRecommendedThisTurn == nil {
            if isNextRunQuery(lowerUser) {
                let activeGoal = UserDefaults.standard.string(forKey: "trainingGoal") ?? "Base Building"
                let useMetric = (UserDefaults.standard.object(forKey: "useMetricSystem") as? Bool) ?? true
                let dailyState = SessionSynthesisEngine.evaluateDailyState(
                    runRecords: allRuns,
                    activeGoal: activeGoal,
                    experienceLevel: profile.experienceLevel,
                    useMetric: useMetric,
                    userHeightCm: profile.userHeightCm,
                    now: Date()
                )
                let tomorrowSession: PrescribedDailySession = {
                    switch dailyState {
                    case .preRun(let s): return s
                    case .completedToday(_, let tomorrow): return tomorrow
                    }
                }()

                if !tomorrowSession.isRestDay {
                    self.sessionRecommendedThisTurn = tomorrowSession
                } else if let next = findNextScheduledRun() {
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
                }
            } else if isTomorrowOrNextRunQuery(lowerUser) {
                let activeGoal = UserDefaults.standard.string(forKey: "trainingGoal") ?? "Base Building"
                let useMetric = (UserDefaults.standard.object(forKey: "useMetricSystem") as? Bool) ?? true
                let dailyState = SessionSynthesisEngine.evaluateDailyState(
                    runRecords: allRuns,
                    activeGoal: activeGoal,
                    experienceLevel: profile.experienceLevel,
                    useMetric: useMetric,
                    userHeightCm: profile.userHeightCm,
                    now: Date()
                )
                switch dailyState {
                case .preRun(let session):
                    self.sessionRecommendedThisTurn = session
                case .completedToday(_, let tomorrowSession):
                    self.sessionRecommendedThisTurn = tomorrowSession
                }
            } else if isWeeklyScheduleQuery(lowerUser) {
                applyFallbackCoachAction(action: .displaySchedule, payload: lowerUser.contains("rest of the week") ? "rest_of_week" : nil)
            }
        }

        // 3. Deduplicate and Harmonize Attachments
        deduplicateAndAlignAttachments(userQuestion: userQuestion, wasExplicitToolDrill: wasExplicitToolDrill)
    }

    private func deduplicateAndAlignAttachments(userQuestion: String, wasExplicitToolDrill: Bool = false) {
        let lowerUser = userQuestion.lowercased()
        let isExplicitStandaloneDrillQuery = wasExplicitToolDrill || (lowerUser.contains("drill") && !isNextRunQuery(lowerUser) && !isTomorrowOrNextRunQuery(lowerUser) && !isWeeklyScheduleQuery(lowerUser))

        if let session = self.sessionRecommendedThisTurn {
            // When an upcoming or daily session is attached, suppress standalone schedule cards (only show the session)
            if isNextRunQuery(lowerUser) || isTomorrowOrNextRunQuery(lowerUser) {
                self.scheduleRecommendedThisTurn = nil
            }

            if let drill = self.drillRecommendedThisTurn {
                if !drill.isAerobicContinuous {
                    let alignedPrimerTarget: String = {
                        let template = DrillTemplate.template(for: drill)
                        return template.calculateTargetCadence(session.cadenceFloor)
                    }()
                    let alignedSession = PrescribedDailySession(
                        targetGoal: session.targetGoal,
                        sessionTitle: session.sessionTitle,
                        durationBand: session.durationBand,
                        paceBand: session.paceBand,
                        hrCap: session.hrCap,
                        cadenceFloor: session.cadenceFloor,
                        groundedRationale: session.groundedRationale,
                        readinessStateText: session.readinessStateText,
                        readinessTriggerLead: session.readinessTriggerLead,
                        primerDrillId: drill,
                        primerDrillTitle: drill.title,
                        primerTargetCadence: alignedPrimerTarget,
                        primerWorkDescription: session.primerWorkDescription,
                        primerPhasesDuration: session.primerPhasesDuration,
                        isTrimmed: session.isTrimmed,
                        microcycle: session.microcycle,
                        mainSessionTemplateId: session.mainSessionTemplateId,
                        mainRunDurationMinutes: session.mainRunDurationMinutes,
                        completedPrimerRun: session.completedPrimerRun,
                        isRestDay: session.isRestDay,
                        dayLabel: session.dayLabel,
                        isToday: session.isToday,
                        readinessState: session.readinessState
                    )
                    self.sessionRecommendedThisTurn = alignedSession

                    if !isExplicitStandaloneDrillQuery {
                        self.drillRecommendedThisTurn = nil
                    }
                }
            }
        }

        // 4. Suppress duplicate explainer cards if a drill card or daily session is already attached
        if let explainer = self.explainerRecommendedThisTurn {
            let drillAliases = ["pre_run_primer", "primer", "form_primer", "technique_drill", "cadence_pyramids", "rhythm_intervals", "tempo_surges", "strides", "drill", "drills"]
            if drillAliases.contains(explainer.lowercased()) && (self.drillRecommendedThisTurn != nil || self.sessionRecommendedThisTurn != nil) {
                self.explainerRecommendedThisTurn = nil
            }
        }
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

    private func isNextRunQuery(_ text: String) -> Bool {
        text.contains("next run") || text.contains("next workout") || text.contains("run next") || text.contains("next scheduled run") || (text.contains("when") && text.contains("run") && !text.contains("last"))
    }

    private func isAffirmativeOrDisplayCommand(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines))
        let directMatches: Set<String> = [
            "yes", "yeah", "yep", "sure", "please", "yes please", "ok", "okay",
            "display the drill", "display drill", "show me", "show it", "show drill",
            "show the drill", "focus on the cadence pyramid drill", "focus on the drill"
        ]
        if directMatches.contains(trimmed) { return true }
        if trimmed.hasPrefix("show ") || trimmed.hasPrefix("display ") { return true }
        return trimmed == "yes" || trimmed.hasPrefix("yes ")
    }

    private func isTomorrowOrNextRunQuery(_ text: String) -> Bool {
        text.contains("tomorrow") || text.contains("next run") || text.contains("next workout") || text.contains("run next")
    }

    private func isWeeklyScheduleQuery(_ text: String) -> Bool {
        text.contains("schedule") || text.contains("this week") || text.contains("rest of the week") || text.contains("calendar") || text.contains("microcycle")
    }

    private func findRecentDrillMentionInHistory() -> PreRunDrillId? {
        for msg in messages.reversed() {
            if let drill = msg.attachedDrillId {
                return drill
            }
            if let resolved = PreRunDrillId.resolve(from: msg.text) {
                return resolved
            }
        }
        return nil
    }
    #endif
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
public struct SanitizedAnalystResponse: Equatable {
    public let text: String
    public let detectedAction: CoachActionType?
    public let detectedPayload: String?
}

@available(iOS 26.0, *)
public enum AnalystResponseSanitizer {
    /// Strips leaked tool invocation signatures from the LLM response text and extracts any embedded action.
    public static func sanitize(text: String) -> SanitizedAnalystResponse {
        var working = text
        var detectedAction: CoachActionType?
        var detectedPayload: String?

        // 1. Check for executeCoachAction:action:payload or executeCoachAction:action
        let execPattern = #"(?i)executecoachaction:([a-z0-9_\-]+)(?::([a-z0-9_\-]+))?"#
        if let regex = try? NSRegularExpression(pattern: execPattern) {
            if let match = regex.firstMatch(in: working, range: NSRange(working.startIndex..., in: working)) {
                if let actionRange = Range(match.range(at: 1), in: working),
                   let action = parseActionType(String(working[actionRange])) {
                    detectedAction = action
                }
                if match.numberOfRanges > 2, match.range(at: 2).location != NSNotFound,
                   let payloadRange = Range(match.range(at: 2), in: working) {
                    detectedPayload = String(working[payloadRange])
                }
            }
            working = regex.stringByReplacingMatches(in: working, range: NSRange(working.startIndex..., in: working), withTemplate: "")
        }

        // 2. Check for executeCoachAction('action', ...)
        let fnPattern = #"(?i)executecoachaction\(\s*['"]?([a-z0-9_\-]+)['"]?(?:\s*,\s*(?:payload:\s*)?['"]?([a-z0-9_\-]+)['"]?)?\s*\)"#
        if let regex = try? NSRegularExpression(pattern: fnPattern) {
            if detectedAction == nil, let match = regex.firstMatch(in: working, range: NSRange(working.startIndex..., in: working)) {
                if let actionRange = Range(match.range(at: 1), in: working),
                   let action = parseActionType(String(working[actionRange])) {
                    detectedAction = action
                }
                if match.numberOfRanges > 2, match.range(at: 2).location != NSNotFound,
                   let payloadRange = Range(match.range(at: 2), in: working) {
                    detectedPayload = String(working[payloadRange])
                }
            }
            working = regex.stringByReplacingMatches(in: working, range: NSRange(working.startIndex..., in: working), withTemplate: "")
        }

        // 3. Check for direct action: display_drill: easy_pace_drill or display_schedule
        let directPattern = #"(?i)\b(display_drill|display_schedule|display_session|display_explainer|update_goal|export_to_watch|record_feedback)(?::\s*([a-z0-9_\-]+)|\s+([a-z0-9_\-]+))?"#
        if let regex = try? NSRegularExpression(pattern: directPattern) {
            if detectedAction == nil, let match = regex.firstMatch(in: working, range: NSRange(working.startIndex..., in: working)) {
                if let actionRange = Range(match.range(at: 1), in: working),
                   let action = parseActionType(String(working[actionRange])) {
                    detectedAction = action
                }
                if match.numberOfRanges > 2, match.range(at: 2).location != NSNotFound,
                   let payloadRange = Range(match.range(at: 2), in: working) {
                    detectedPayload = String(working[payloadRange])
                } else if match.numberOfRanges > 3, match.range(at: 3).location != NSNotFound,
                          let payloadRange = Range(match.range(at: 3), in: working) {
                    detectedPayload = String(working[payloadRange])
                }
            }
            working = regex.stringByReplacingMatches(in: working, range: NSRange(working.startIndex..., in: working), withTemplate: "")
        }

        // 4. Check for standalone command lines like "Display the drill." or "Display drill: ..."
        let commandLinePattern = #"(?im)^\s*(?:i(?:'ll| will)\s+)?display\s+(?:the\s+)?(drill|schedule|session|explainer)(?:\s*:\s*([a-z0-9_\-]+))?[\.\?!]?\s*$"#
        if let regex = try? NSRegularExpression(pattern: commandLinePattern) {
            if detectedAction == nil, let match = regex.firstMatch(in: working, range: NSRange(working.startIndex..., in: working)) {
                if let actionRange = Range(match.range(at: 1), in: working),
                   let action = parseActionType("display_" + String(working[actionRange])) {
                    detectedAction = action
                }
                if match.numberOfRanges > 2, match.range(at: 2).location != NSNotFound,
                   let payloadRange = Range(match.range(at: 2), in: working) {
                    detectedPayload = String(working[payloadRange])
                }
            }
            working = regex.stringByReplacingMatches(in: working, range: NSRange(working.startIndex..., in: working), withTemplate: "")
        }

        // Clean up markdown ticks around removed commands and collapse blank lines
        let cleanedLines = working.components(separatedBy: .newlines)
            .map { line -> String in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed == "``" || trimmed == "`" {
                    return ""
                }
                return trimmed
            }
        let joined = cleanedLines.joined(separator: "\n")
        var cleaned = joined
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // If the model leaked a pure command with no conversational text, provide a natural coach statement
        if cleaned.isEmpty, let action = detectedAction {
            switch action {
            case .displayDrill:
                if let payload = detectedPayload, let drill = PreRunDrillId.resolve(from: payload) {
                    cleaned = "Here is the \(drill.title) drill to focus on."
                } else {
                    cleaned = "Here is the drill to focus on."
                }
            case .displaySchedule:
                cleaned = "Here is your upcoming training schedule."
            case .displaySession:
                cleaned = "Here is your next planned session."
            case .displayExplainer:
                cleaned = "Here is the visual explainer."
            case .updateGoal:
                cleaned = "I've updated your training goal."
            case .exportToWatch:
                cleaned = "I've sent the workout to your Apple Watch."
            case .recordFeedback:
                cleaned = "Thanks for the feedback; I've noted that for your training."
            }
        }

        // 5. Strip trailing repetitive calls-to-action (e.g. "Would you like a drill to sharpen your running form?")
        let trailingOfferPattern = #"(?i)[\.\?!]?\s*(?:(?:would you like|shall i|let me know if you(?:'d| would)? like|do you want me to)[^\.\?!]*(?:drill|schedule|plan|overview|readiness|step|cadence|rhythm|form|turnover|anything)[^\.\?!]*[\.\?!]?)\s*$"#
        if let regex = try? NSRegularExpression(pattern: trailingOfferPattern) {
            let nsCleaned = cleaned as NSString
            let range = NSRange(location: 0, length: nsCleaned.length)
            let stripped = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: ".")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !stripped.isEmpty && stripped != "." {
                cleaned = stripped
            }
        }
        cleaned = cleaned.replacingOccurrences(of: #"\.{2,}"#, with: ".", options: .regularExpression)

        return SanitizedAnalystResponse(
            text: cleaned,
            detectedAction: detectedAction,
            detectedPayload: detectedPayload
        )
    }

    private static func parseActionType(_ raw: String) -> CoachActionType? {
        let clean = raw.lowercased().replacingOccurrences(of: "-", with: "_").trimmingCharacters(in: CharacterSet(charactersIn: "'\"() \t"))
        switch clean {
        case "display_drill", "displaydrill": return .displayDrill
        case "display_schedule", "displayschedule": return .displaySchedule
        case "display_session", "displaysession": return .displaySession
        case "display_explainer", "displayexplainer": return .displayExplainer
        case "export_to_watch", "exporttowatch": return .exportToWatch
        case "update_goal", "updategoal": return .updateGoal
        case "record_feedback", "recordfeedback": return .recordFeedback
        default: return nil
        }
    }

    private static func parseDirectActionLine(_ line: String) -> (CoachActionType, String?)? {
        let knownActions: [(String, CoachActionType)] = [
            ("display_drill", .displayDrill),
            ("display_schedule", .displaySchedule),
            ("display_session", .displaySession),
            ("display_explainer", .displayExplainer),
            ("export_to_watch", .exportToWatch),
            ("update_goal", .updateGoal),
            ("record_feedback", .recordFeedback)
        ]

        let lower = line.lowercased()
        for (prefix, action) in knownActions {
            if lower == prefix {
                return (action, nil)
            }
            if lower.hasPrefix("\(prefix):") {
                let payload = String(line.dropFirst(prefix.count + 1)).trimmingCharacters(in: .whitespaces)
                return (action, payload.isEmpty ? nil : payload)
            }
            if lower.hasPrefix("\(prefix) ") {
                let payload = String(line.dropFirst(prefix.count + 1)).trimmingCharacters(in: .whitespaces)
                return (action, payload.isEmpty ? nil : payload)
            }
        }
        return nil
    }

    private static func parseFunctionCall(_ line: String) -> (CoachActionType, String?)? {
        let inner = line.dropFirst("executecoachaction(".count)
        let clean = inner.trimmingCharacters(in: CharacterSet(charactersIn: ") \t"))
        let parts = clean.components(separatedBy: ",")
        guard let first = parts.first else { return nil }
        guard let action = parseActionType(first) else { return nil }
        var payload: String?
        if parts.count > 1 {
            let second = parts[1].replacingOccurrences(of: "payload:", with: "")
            let trimmedSecond = second.trimmingCharacters(in: CharacterSet(charactersIn: "'\" \t"))
            if !trimmedSecond.isEmpty {
                payload = trimmedSecond
            }
        }
        return (action, payload)
    }
}
#endif
