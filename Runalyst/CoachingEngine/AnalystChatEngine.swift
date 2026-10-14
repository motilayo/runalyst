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

    enum MessageSender: Equatable {
        case user
        case analyst
    }

    init(id: UUID = UUID(), sender: MessageSender, text: String, timestamp: Date = Date()) {
        self.id = id
        self.sender = sender
        self.text = text
        self.timestamp = timestamp
    }
}

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
        let runType = runRecord.detectedTypeRaw.isEmpty ? "Run" : runRecord.detectedTypeRaw
        let isIndoor = runRecord.isIndoor ?? false
        let envNote = isIndoor ? "on the treadmill" : "outdoors"
        let initialGreeting = "I took a look at your \(runType) \(envNote). What would you like to explore about your form, effort, or recovery?"
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

        // --- Guardrail 1: Medical Boundary ---
        let lowercased = trimmed.lowercased()
        let medicalKeywords = ["pain", "hurt", "injured", "injury", "shin splint", "plantar", "achilles", "knee pain", "diagnosis", "doctor", "strain my"]
        if medicalKeywords.contains(where: { lowercased.contains($0) }) {
            let medicalReferral = "I'm an AI running coach, not a doctor or physical therapist. If you're experiencing pain or persistent soreness, please take time to rest and check in with a doctor or physical therapist."
            messages.append(AnalystChatMessage(sender: .analyst, text: medicalReferral))
            return
        }

        // --- Guardrail 2: Hardware Boundary (Indoor GPS inquiry) ---
        let gpsKeywords = ["gps", "route", "map", "elevation gain", "hills outside"]
        if (runRecord.isIndoor ?? false) && gpsKeywords.contains(where: { lowercased.contains($0) }) {
            let hardwareExplanation = "This run was recorded on a treadmill indoors. Apple Watch turns off GPS and elevation tracking indoors because there are no satellites or hills inside. We track your run using your arm swing, cadence, and heart rate instead."
            messages.append(AnalystChatMessage(sender: .analyst, text: hardwareExplanation))
            return
        }

        // --- Guardrail 3: Subjective Gear / Shoe Boundary ---
        let gearKeywords = ["shoes", "shoe", "vaporfly", "alphafly", "superblast", "hoka", "nike", "saucony", "gear to buy", "what shoes"]
        if gearKeywords.contains(where: { lowercased.contains($0) }) {
            let gearResponse = "I focus on your running form, cadence, and effort rather than specific shoe brands. The best shoe is whatever feels comfortable for you, but keeping a quick, light step under your hips does the most to protect your legs."
            messages.append(AnalystChatMessage(sender: .analyst, text: gearResponse))
            return
        }

        // Test responder hook (for unit tests / mock free speak)
        let cal = Calendar.current
        let daysDiff = cal.dateComponents([.day], from: cal.startOfDay(for: runRecord.date), to: cal.startOfDay(for: Date())).day ?? 0
        let turnContext = ConversationMemoryManager.buildTurnContext(
            userQuestion: trimmed,
            messages: messages,
            recoveryStateDescription: recoveryTimeline.state.rawValue,
            daysSinceWorkout: daysDiff
        )

        #if DEBUG
        if let responder = modelResponder {
            do {
                let systemInstructions = buildSystemInstructions(for: trimmed, turnContext: turnContext)
                let responseText = try await responder(systemInstructions, trimmed)
                messages.append(AnalystChatMessage(sender: .analyst, text: responseText))
                return
            } catch {
                print("Model responder error: \(error)")
            }
        }
        #endif

        // FoundationModels on-device generation with rich Workout Data Sheet & Turn-Aware Memory
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if !isRunningTests && SystemLanguageModel.default.isAvailable {
                do {
                    let responseText = try await generateFoundationModelResponse(for: trimmed, turnContext: turnContext)
                    messages.append(AnalystChatMessage(sender: .analyst, text: responseText))
                    return
                } catch {
                    print("FoundationModels chat error: \(error)")
                }
            }
        }
        #endif

        // Clean, data-grounded fallback response (offline / non-AI hardware)
        let fallbackResponse = generateDataGroundedFallback(for: trimmed, turnContext: turnContext)
        messages.append(AnalystChatMessage(sender: .analyst, text: fallbackResponse))
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

    // MARK: - Legacy System Instructions Assembly

    func buildSystemInstructions(for userQuestion: String? = nil, turnContext: ManagedTurnContext? = nil) -> String {
        let cal = Calendar.current
        let daysDiff = cal.dateComponents([.day], from: cal.startOfDay(for: runRecord.date), to: cal.startOfDay(for: Date())).day ?? 0
        let resolvedTurnContext = turnContext ?? (userQuestion.map {
            ConversationMemoryManager.buildTurnContext(
                userQuestion: $0,
                messages: messages,
                recoveryStateDescription: recoveryTimeline.state.rawValue,
                daysSinceWorkout: daysDiff
            )
        })
        let analysis = makeAnalysisContext(isSubjectiveDistress: resolvedTurnContext?.isSubjectiveDistress ?? false)
        return AnalystPromptBuilder.buildSystemInstructions(analysis: analysis, turnContext: resolvedTurnContext)
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    func buildLeanSystemInstructions() -> String {
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        let runType = runRecord.detectedTypeRaw.isEmpty ? "Run" : runRecord.detectedTypeRaw
        let isIndoor = runRecord.isIndoor ?? false
        let envNote = isIndoor ? "Indoor Treadmill (belt-driven, static air)" : "Outdoors"
        return """
        You are my personal running coach and exercise physiologist.
        Speak directly to me ("you" / "your") like an experienced, objective running coach in natural conversation (1 to 3 short paragraphs). Clear, direct, perceptive, and data-backed. Never refer to me as "the runner" or in the third person.

        WORKOUT CONTEXT:
        Reviewing workout: \(runType) (\(envNote)).

        TOOLS & DATA ACCESS:
        You have access to 6 deterministic native tools to query my running math and physics:
        1. `fetchWorkoutAnalysis`: Retrieves retrospective telemetry, running economy, efficiency factor, stride archetype, cadence, lap splits, second-half cardiac drift, and deterministic physiological verdicts. MANDATORY to call when evaluating running economy, stride efficiency, cadence, pacing, or overall workout performance.
        2. `fetchIntervalPerformance`: Retrieves discrete interval rep breakdown (work reps, paces, turnover, heart rates, active recovery phases, recovery heart rate drops, pace repeatability across sets, and belt vs road mechanics). MANDATORY to call when evaluating interval workouts or rep execution.
        3. `fetchWorkoutPhysics`: Retrieves modeled physical and physiological realities: treadmill belt kinetics and braking shock when cadence dips, indoor static air thermal build vs convective wind cooling, gravitational hill resistance, and cardiac lag.
        4. `fetchReadinessAndPrescription`: Retrieves current recovery timeline, rest days elapsed, readiness status, and the locked prescription table for upcoming sessions.
        5. `fetchAthleteProfile`: Retrieves my 30-day training load, experience level, and height-calibrated cadence floor.
        6. `fetchHistoricalWorkout`: Retrieves stored historical workout telemetry to compare this session against a specific past workout (by date, e.g. 'September 14', or by type, e.g. 'previous intervals'). MANDATORY to call when comparing runs or evaluating progress vs a previous session.

        EXECUTION RULES — ZERO STALLING:
        • SILENT, IMMEDIATE TOOL INVOCATION: You MUST invoke the appropriate tool immediately in your first turn to retrieve the facts.
        • NEVER announce, promise, or narrate tool retrieval. NEVER say phrases like:
          - "I need to pull your most recent workout analysis"
          - "I'll retrieve the analysis" / "I will retrieve the analysis"
          - "Let's start there"
          - "To assess your ..., I need to ..."
          - "Let me check your workout"
        • Call the tool silently and immediately, receive the returned telemetry, and output ONLY your final coaching response once the tool returns data.
        • For running economy, stride efficiency, cadence, or overall performance: call `fetchWorkoutAnalysis`.
        • For interval reps, work/recovery splits, or pace consistency: call `fetchIntervalPerformance`.
        • For treadmill physics, room heat, or biomechanics: call `fetchWorkoutPhysics`.
        • For tomorrow's run, recovery, or readiness: call `fetchReadinessAndPrescription`.
        • For comparisons with a past run or specific date: call `fetchHistoricalWorkout`.
        • For conceptual questions (e.g. "What is VO2 Max?", "What is cardiac drift?"): explain the concept simply using your internal knowledge. If relevant to my run, call tools to connect it to my data.
        • For out-of-scope questions unrelated to running, health, or fitness: do NOT call tools; answer in 1 concise sentence and redirect to training.

        SAFETY & BOUNDARIES:
        • Athlete Safety Override: If I mention physical illness, fever, flu, or sharp injury pain, SAFETY OVERRIDES ALL TRAINING. Advise rest and recovery immediately without calling training tools or prescribing workouts.
        • Deterministic Authority: The returned math and physics verdicts are your indisputable mathematical conclusions. Never contradict them or invent numbers outside the returned data.
        • Never claim a flat treadmill intensifies gravitational load (gravity is normal 1g); flat treadmill drift is thermal accumulation from zero convective airflow.
        • Bold accent numbers and units (e.g. **156 SPM**, **7:15/km**, **1.42**).

        Respond in \(language).
        """
    }

    @available(iOS 26.0, *)
    func getOrCreateSession() -> LanguageModelSession {
        if let existing = modelSession as? LanguageModelSession {
            return existing
        }

        let workoutTool = FetchWorkoutAnalysisTool { [weak self] _ in
            guard let self else { return "" }
            return self.makeAnalysisContext().groundedPromptSummary()
        }

        let intervalTool = FetchIntervalPerformanceTool { [weak self] _ in
            guard let self else { return "" }
            return self.makeAnalysisContext().formatIntervalPerformanceSummary()
        }

        let physicsTool = FetchWorkoutPhysicsTool { [weak self] query in
            guard let self else { return "" }
            return self.makeAnalysisContext().formatWorkoutPhysicsSummary(domain: query.domain)
        }

        let readinessTool = FetchReadinessAndPrescriptionTool { [weak self] _ in
            guard let self else { return "" }
            let dummyTurn = ManagedTurnContext(
                turnDomain: .futureSessionPlanning,
                stripWorkoutPayload: false,
                prunePhysiologicalVerdicts: true
            )
            return self.makeAnalysisContext().groundedPromptSummary(turnContext: dummyTurn)
        }

        let profileTool = FetchAthleteProfileTool { [weak self] _ in
            guard let self else { return "" }
            let profile = self.runnerProfile
            return """
            ATHLETE PROFILE:
            - Experience Level: \(profile.experienceLevel)
            - Training Goal: \(profile.trainingGoal)
            - 30-Day Load: \(profile.loadSummary)
            - Height-Calibrated Cadence Floor: \(profile.heightAdjustedCadenceFloor) SPM
            """
        }

        let historicalTool = FetchHistoricalWorkoutTool { [weak self] query in
            guard let self else { return "No historical data available." }
            let target = query.target ?? ""
            if let priorRun = HistoricalRunMatcher.findRun(matching: target, relativeTo: self.runRecord, in: self.runRecord.modelContext) {
                return HistoricalRunMatcher.compare(current: self.runRecord, with: priorRun).summary
            } else {
                return "No historical workout found matching '\(target)' in stored records."
            }
        }

        let tools: [any Tool] = [workoutTool, intervalTool, physicsTool, readinessTool, profileTool, historicalTool]
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
    private func generateFoundationModelResponse(for userQuestion: String, turnContext: ManagedTurnContext) async throws -> String {
        let session = getOrCreateSession()
        let response = try await session.respond(to: userQuestion)
        let responseText = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Guard against LLM conversational stalling where the on-device model announces
        // future retrieval intent instead of delivering completed analysis.
        if Self.isStallResponse(responseText) {
            return generateDataGroundedFallback(for: userQuestion, turnContext: turnContext)
        }

        return responseText
    }
    #endif

    /// Evaluates whether an LLM generation stalled by announcing future data retrieval instead of answering.
    static func isStallResponse(_ text: String) -> Bool {
        let lower = text.lowercased()
        let stallPatterns = [
            "need to pull",
            "pull your most recent",
            "pull your workout",
            "retrieve the analysis",
            "retrieve your workout",
            "i'll retrieve",
            "i will retrieve",
            "let's start there",
            "lets start there",
            "let me retrieve",
            "let me pull",
            "let me fetch",
            "let me check",
            "i need to check your workout",
            "i need to fetch",
            "to assess your running economy",
            "to assess your"
        ]
        let matchesPattern = stallPatterns.contains { lower.contains($0) }
        let containsNumbers = text.rangeOfCharacter(from: .decimalDigits) != nil
        return matchesPattern && !containsNumbers
    }

    /// Synthesizes 1,000-meter splits from phase segments if physical splits were not persisted.
    static func synthesizeSplitsFromSegments(_ segments: [PhaseSegment], splitDistanceMeters: Double = 1000.0) -> [RunSplit] {
        RunSplit.synthesize(from: segments, splitDistanceMeters: splitDistanceMeters)
    }

    // MARK: - Data-Grounded Fallback Response (Offline / Non-AI Hardware)

    private func generateDataGroundedFallback(for userQuestion: String, turnContext: ManagedTurnContext? = nil) -> String {
        let analysis = makeAnalysisContext(isSubjectiveDistress: turnContext?.isSubjectiveDistress ?? false)
        return AnalystFallbackResponder.generateResponse(
            for: userQuestion,
            turnContext: turnContext,
            analysis: analysis,
            runRecord: runRecord
        )
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
