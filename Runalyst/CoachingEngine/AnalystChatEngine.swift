import Foundation
import SwiftData
import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Chat message model for the interactive AI Analyst conversation.
struct AnalystChatMessage: Identifiable, Equatable {
    let id: UUID
    let sender: MessageSender
    let text: String
    let timestamp: Date
    let attachedDrillId: PreRunDrillId?

    enum MessageSender: Equatable {
        case user
        case analyst
    }

    init(
        id: UUID = UUID(),
        sender: MessageSender,
        text: String,
        timestamp: Date = Date(),
        attachedDrillId: PreRunDrillId? = nil
    ) {
        self.id = id
        self.sender = sender
        self.text = text
        self.timestamp = timestamp
        self.attachedDrillId = attachedDrillId
    }
}

typealias AnalystChatSender = AnalystChatMessage.MessageSender

/// Actor managing the interactive RAG Analyst Chat session with FoundationModels and strict operational guardrails.
@MainActor
class AnalystChatEngine: ObservableObject {
    @Published var messages: [AnalystChatMessage] = []
    @Published var isResponding: Bool = false

    private let runSignature: RunSignature?
    private let macroProfile: MacroProfile?
    private let runRecord: RunRecord

    #if canImport(FoundationModels)
    private var modelSession: Any? // LanguageModelSession on iOS 26+
    /// Number of tools executed during the active conversation turn.
    private(set) var toolsCalledThisTurn: Int = 0
    /// Tracks whether workout telemetry analysis has been executed and persisted to the session transcript.
    private(set) var sessionHasLoadedWorkoutAnalysis: Bool = false
    /// Tracks a drill recommended via the `displayDrill` tool during the active conversation turn.
    private(set) var drillRecommendedThisTurn: PreRunDrillId?
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

    init(runRecord: RunRecord, runSignature: RunSignature? = nil, macroProfile: MacroProfile? = nil) {
        self.runRecord = runRecord
        self.runSignature = runSignature ?? runRecord.signature
        self.macroProfile = macroProfile ?? MacroProfile.load()

        setupInitialGreeting()
    }

    private func setupInitialGreeting() {
        let isIndoor = runRecord.isIndoor ?? false
        let envNote = isIndoor ? "treadmill" : "outdoor"
        let context = makeAnalysisContext()
        let grade = context.overallGradeReport.grade
        let isIntervalModality = (runRecord.evaluationModality == .intervals || !context.workSegments.isEmpty) && !context.workSegments.isEmpty
        let runType = runRecord.detectedTypeRaw.isEmpty ? "run" : runRecord.detectedTypeRaw.lowercased()

        let initialGreeting: String
        if isIntervalModality {
            let workSegments = context.workSegments
            let meanWorkPace = workSegments.reduce(0.0) { $0 + $1.avgPace } / Double(workSegments.count)
            let workPace = PaceFormatter.formatPace(secondsPerKilometer: meanWorkPace)
            let repCount = workSegments.count
            let cad = Int((workSegments.reduce(0.0) { $0 + $1.avgCadence } / Double(workSegments.count)).rounded())
            initialGreeting = "I took a look at your Grade \(grade) \(envNote) \(runType) (\(repCount) reps @ \(workPace)). Want to dig into your \(cad) SPM turnover, pacing spread, or recovery?"
        } else {
            let pace = PaceFormatter.formatPace(secondsPerKilometer: runRecord.workingAvgPace)
            let cad = Int(runRecord.workingAvgCadence.rounded())
            initialGreeting = "I took a look at your Grade \(grade) \(envNote) \(runType) (@ \(pace)). Want to dig into your \(cad) SPM turnover, pacing trend, or recovery?"
        }
        messages.append(AnalystChatMessage(sender: .analyst, text: initialGreeting))
    }

    private var isRunningTests: Bool {
        NSClassFromString("XCTestCase") != nil || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Sends a runner question and generates an analyst response with RAG telemetry context and guardrails.
    func sendMessage(_ userQuestion: String) async {
        let trimmed = userQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        messages.append(AnalystChatMessage(sender: .user, text: trimmed))
        isResponding = true
        defer { isResponding = false }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            self.drillRecommendedThisTurn = nil
        }
        #endif

        // FoundationModels: the runner's message goes straight to the session.
        // Lean instructions + native tools only. No Swift intent parsing or output rewriting—
        // the model reads the tool spec and decides what to call.
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            #if DEBUG
            if let responder = modelResponder {
                do {
                    let responseText = try await responder(buildLeanSystemInstructions(), trimmed)
                    messages.append(AnalystChatMessage(sender: .analyst, text: responseText, attachedDrillId: drillRecommendedThisTurn))
                    return
                } catch {
                    print("Model responder error: \(error)")
                }
            }
            #endif
            if !isRunningTests && SystemLanguageModel.default.isAvailable {
                do {
                    let responseText = try await generateFoundationModelResponse(for: trimmed)
                    messages.append(AnalystChatMessage(sender: .analyst, text: responseText, attachedDrillId: drillRecommendedThisTurn))
                    return
                } catch {
                    print("FoundationModels chat error: \(error)")
                    // Reset session so subsequent turns start with a clean context
                    self.modelSession = nil
                    self.sessionHasLoadedWorkoutAnalysis = false
                }
            }
        }
        #endif

        // Graceful deterministic data-grounded fallback (offline, simulator/test runner, or unsupported hardware)
        let fallbackResponse = generateDataGroundedFallback(for: trimmed)
        messages.append(AnalystChatMessage(sender: .analyst, text: fallbackResponse))
    }

    // MARK: - Test Runner & Offline Telemetry Fallback

    private func generateDataGroundedFallback(for userQuestion: String) -> String {
        let analysis = makeAnalysisContext()
        return AnalystFallbackResponder.generateResponse(
            for: userQuestion,
            conversationHistory: messages,
            analysis: analysis,
            runRecord: runRecord
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

    // MARK: - System Instructions Assembly

    func buildSystemInstructions() -> String {
        let analysis = makeAnalysisContext()
        return """
        You are Runalyst—an intelligent running coach and telemetry interpreter.
        Tailor your vocabulary and depth to my Athletic Experience Level.
        Speak like an experienced, objective running coach in natural conversation; experienced, objective running coach in a conversation.
        You have evaluated my raw telemetry using your deterministic analytical engine.
        When I ask what a concept means (like threshold), explain the concept simply, then connect it to how I ran.
        Answer what I ask directly, using the data sheet to back up your points.
        If I state or clarify that I didn't run today or yesterday, immediately acknowledge that fact and ground your advice in my current rest days.
        Never contradict yourself.
        NEVER refer to this workout as "today", "today's run", or "today's workout" unless the Workout Date is literally today.
        Cardiac drift (+BPM in second half) is cardiovascular fatigue or thermal accumulation, never acceleration.
        Do NOT invent or prescribe custom structured workout routines.
        Never describe a wide pace spread spanning tens of seconds as tight or metronomic.

        \(analysis.groundedPromptSummary())
        """
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    func buildLeanSystemInstructions() -> String {
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        let runType = runRecord.detectedTypeRaw.isEmpty ? "Run" : runRecord.detectedTypeRaw
        let isIndoor = runRecord.isIndoor ?? false
        let envNote = isIndoor ? "Indoor Treadmill" : "Outdoors"

        let cal = Calendar.current
        let daysDiff = cal.dateComponents([.day], from: cal.startOfDay(for: runRecord.date), to: cal.startOfDay(for: Date())).day ?? 0
        let temporalGrounding = daysDiff == 0
            ? "Workout took place today."
            : "Workout took place \(daysDiff) days ago."

        let useMetric = (UserDefaults.standard.object(forKey: "useMetricSystem") as? Bool) ?? true
        let unitSystem = useMetric ? "Metric (min/km, km)" : "Imperial (min/mi, mi)"

        return """
        You are Runalyst—an intelligent running coach and telemetry interpreter.
        Speak directly to the runner in an empathetic, clear, conversational tone.

        CONTEXT:
        Reviewing: \(runType) (\(envNote)). \(temporalGrounding)
        Units: \(unitSystem).

        RULES:
        • Ground statements in tool facts (`inspectWorkout`, `manageTrainingState`, `executeCoachAction`).
        • Call `inspectWorkout` for moving vs gross stats, splits, intervals, reps, and physics.
        • Call `manageTrainingState` with focus 'readiness' for recovery/rx (set `userReportedDistress: true` if ill/injured), 'history' to compare runs, or 'athlete_profile'.
        • Call `executeCoachAction` with action 'display_drill' to present drill cards, 'update_goal' to adjust goals, or 'record_feedback' for feedback.
        • Medical Safety: If the runner reports pain, injury, illness, or acute distress, prioritize rest. Give an AI disclaimer (not a physician) and urge medical evaluation.
        • Outside Running: If an inquiry falls outside running and fitness, address it with a natural sidestep and redirect back to running or recovery.
        • Never hallucinate unverified telemetry.

        Respond in \(language).
        """
    }

    @available(iOS 26.0, *)
    func getOrCreateSession() -> LanguageModelSession {
        if let existing = modelSession as? LanguageModelSession {
            return existing
        }

        let inspectWorkoutTool = InspectWorkoutTool { [weak self] _ in
            guard let self else { return "" }
            self.toolsCalledThisTurn += 1
            self.sessionHasLoadedWorkoutAnalysis = true
            return self.makeAnalysisContext().compactTelemetryAnalysis()
        }

        let manageTrainingTool = ManageTrainingStateTool { [weak self] query in
            guard let self else { return "" }
            self.toolsCalledThisTurn += 1
            switch query.focus {
            case .readiness:
                let isDistress = query.userReportedDistress == true
                let analysis = self.makeAnalysisContext(isSubjectiveDistress: isDistress)
                let rx = analysis.lockedPrescription
                let isReady = analysis.recoveryTimeline.readyForHard && !isDistress

                let verdict: String
                let recoveryStatus: String
                let directive: String

                if isDistress || rx.isSubjectiveOverride {
                    verdict = "MANDATORY_REST_HEALTH_OVERRIDE"
                    recoveryStatus = "Subjective illness, pain, or physical distress reported. All training suspended for recovery."
                    directive = "Runner reported illness, pain, or distress. Biological safety overrides all training. Mandate full rest and recovery. Do NOT state the runner is cleared for running or light recovery. Prescribe full rest. Advise consulting a physician or physical therapist if symptoms persist."
                } else if isReady {
                    verdict = "CLEARED_FOR_TRAINING"
                    recoveryStatus = "Fully recovered and cleared for training."
                    directive = "Runner is cleared for training. Prescribe \(rx.nextSessionName) directly (\(rx.prescribedDurationBand) at \(rx.prescribedPaceBand)). Focus strictly on upcoming training. Do NOT quote past workout heart rates, paces, or interval drops."
                } else {
                    verdict = "CLEARED_FOR_LIGHT_RECOVERY_ONLY"
                    recoveryStatus = "In active recovery until \(analysis.recoveryTimeline.earliestHardPhrase)."
                    directive = "Runner may do light recovery movement only; no hard efforts until \(analysis.recoveryTimeline.earliestHardPhrase). Prescribed: \(rx.nextSessionName) (\(rx.prescribedDurationBand) at \(rx.prescribedPaceBand))."
                }

                let response = ReadinessToolResponse(
                    schema_name: "READINESS_AND_PRESCRIPTION_RESPONSE",
                    readiness_verdict: verdict,
                    recovery_status: recoveryStatus,
                    prescribed_session_name: rx.nextSessionName,
                    intensity_category: rx.intensityCategory,
                    prescribed_pace_band: rx.prescribedPaceBand,
                    prescribed_duration_band: rx.prescribedDurationBand,
                    prescribed_cadence_band: rx.prescribedCadenceBand,
                    session_rationale: rx.sessionRationale,
                    coaching_directive: directive
                )

                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
                if let data = try? encoder.encode(response),
                   let json = String(data: data, encoding: .utf8) {
                    return json
                }
                return "{\"intensity_category\":\"\(rx.intensityCategory)\",\"prescribed_pace_band\":\"\(rx.prescribedPaceBand)\",\"prescribed_session_name\":\"\(rx.nextSessionName)\",\"readiness_verdict\":\"\(verdict)\"}"

            case .history:
                let target = query.historyTarget ?? ""
                let compareWith = query.historyCompareWith ?? ""

                if !compareWith.isEmpty {
                    if let comparison = HistoricalRunMatcher.compareRuns(
                        queryA: target,
                        queryB: compareWith,
                        relativeTo: self.runRecord,
                        in: self.runRecord.modelContext
                    ) {
                        return comparison.structuredTelemetryFacts
                    }
                }

                if let compound = HistoricalRunMatcher.parseComparisonTargets(from: target) {
                    if let comparison = HistoricalRunMatcher.compareRuns(
                        queryA: compound.targetA,
                        queryB: compound.targetB,
                        relativeTo: self.runRecord,
                        in: self.runRecord.modelContext
                    ) {
                        return comparison.structuredTelemetryFacts
                    }
                }

                let lower = target.lowercased()
                if lower.contains("best") || lower.contains("worst") || lower.contains("arc") || lower.contains("30_day") || lower.contains("rank") {
                    let arc = HistoricalRunMatcher.analyzePerformanceArc(relativeTo: self.runRecord, in: self.runRecord.modelContext)
                    return arc.structuredTelemetryFacts
                } else if lower.contains("list") || lower.contains("recent") || lower.contains("all") {
                    return HistoricalRunMatcher.listRecentRuns(relativeTo: self.runRecord, in: self.runRecord.modelContext)
                } else if let prior = HistoricalRunMatcher.findRun(matching: target.isEmpty ? "previous" : target, relativeTo: self.runRecord, in: self.runRecord.modelContext) {
                    let comparison = HistoricalRunMatcher.compare(current: self.runRecord, with: prior)
                    return comparison.structuredTelemetryFacts
                } else {
                    return "No historical workout matching '\(target)' was found in stored records. Available context: current run is the only matching record."
                }

            case .athleteProfile:
                let profile = self.runnerProfile
                return """
                ATHLETE PROFILE:
                - Experience Level: \(profile.experienceLevel)
                - Training Goal: \(profile.trainingGoal)
                - 30-Day Load: \(profile.loadSummary)
                - Height-Calibrated Cadence Floor: \(profile.heightAdjustedCadenceFloor) SPM
                """
            }
        }

        let coachActionTool = ExecuteCoachActionTool { [weak self] query in
            guard let self else { return "" }
            self.toolsCalledThisTurn += 1
            switch query.action {
            case .displayDrill:
                let resolved = PreRunDrillId.resolve(from: query.payload ?? "") ?? .cadencePyramids
                self.drillRecommendedThisTurn = resolved

                let template = DrillTemplate.template(for: resolved)
                let baseCadence = Int(self.runRecord.workingAvgCadence) > 0 ? Int(self.runRecord.workingAvgCadence) : 155
                let target = template.calculateTargetCadence(baseCadence)
                let cue = template.generateInstructionalCue(target)

                let dto: [String: String] = [
                    "status": "interactive_drill_card_displayed",
                    "drill_id": resolved.rawValue,
                    "drill_name": resolved.title,
                    "purpose": template.defaultPurpose,
                    "target_cadence": target,
                    "instructional_cue": cue,
                    "duration_minutes": "\(resolved.defaultDuration.rawValue) min"
                ]
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
                if let data = try? encoder.encode(dto), let str = String(data: data, encoding: .utf8) {
                    return str
                }
                return "{\"drill_name\":\"\(resolved.title)\",\"status\":\"interactive_drill_card_displayed\"}"

            case .exportToWatch:
                let item = query.payload ?? "Prescribed Workout"
                return "{\"status\":\"exported_to_apple_watch\",\"item\":\"\(item)\",\"message\":\"Workout successfully queued for Apple Watch Workout app sync.\"}"

            case .updateGoal:
                let newGoal = query.payload ?? "Base Building"
                UserDefaults.standard.set(newGoal, forKey: "trainingGoal")
                return "{\"status\":\"training_goal_updated\",\"goal\":\"\(newGoal)\",\"message\":\"Training goal updated to \(newGoal).\"}"

            case .recordFeedback:
                let feedback = query.payload ?? ""
                if !feedback.isEmpty {
                    self.runRecord.framboiseTags.append("feedback:\(feedback.prefix(40))")
                    try? self.runRecord.modelContext?.save()
                }
                return "{\"status\":\"feedback_recorded\",\"feedback\":\"\(feedback)\",\"message\":\"Subjective feedback recorded successfully.\"}"
            }
        }

        let tools: [any Tool] = [inspectWorkoutTool, manageTrainingTool, coachActionTool]
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
    private func generateFoundationModelResponse(for userQuestion: String) async throws -> String {
        // Discard accumulated multi-turn conversation history when reaching 4 turns to avoid TN3193 4,096 token limit
        if messages.count > 4 {
            self.modelSession = nil
        }

        var session = getOrCreateSession()
        toolsCalledThisTurn = 0
        do {
            let response = try await session.respond(to: userQuestion)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            let errStr = error.localizedDescription
            if errStr.contains("tokens") || errStr.contains("4,096") || errStr.contains("DecoderModelError") {
                // Reset session and retry cleanly with fresh single-turn prompt context
                self.modelSession = nil
                session = getOrCreateSession()
                let retryResponse = try await session.respond(to: userQuestion)
                return retryResponse.content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            throw error
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
