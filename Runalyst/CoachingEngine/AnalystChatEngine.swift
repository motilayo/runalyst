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
    /// Number of tools executed during the active conversation turn.
    private(set) var toolsCalledThisTurn: Int = 0
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
                    // Reset session so subsequent turns start with a clean context
                    self.modelSession = nil
                }
            }
        }
        #endif

        // Graceful deterministic data-grounded fallback (always available in offline, test, or error states)
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

        let cal = Calendar.current
        let daysDiff = cal.dateComponents([.day], from: cal.startOfDay(for: runRecord.date), to: cal.startOfDay(for: Date())).day ?? 0
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "EEEE, MMMM d"
        let workoutDateStr = dateFormatter.string(from: runRecord.date)
        let todayStr = dateFormatter.string(from: Date())

        let temporalGrounding = daysDiff == 0
            ? "This workout took place TODAY."
            : "This workout took place on \(workoutDateStr) (\(daysDiff) days ago). Today is \(todayStr). NEVER refer to this workout as 'today', 'today's session', or 'today's run'—refer to it accurately as 'your \(workoutDateStr) run' or 'your \(runType)'."

        let useMetric = (UserDefaults.standard.object(forKey: "useMetricSystem") as? Bool) ?? true
        let unitSystemInstruction = useMetric
            ? "USER UNIT SYSTEM: Metric. Quote paces strictly in min/km (e.g. 5:15/km) and distances in km (e.g. 5.0 km). NEVER dump imperial units (mi, min/mi) and NEVER output dual units like '7:36/km (12:14/mi)'. Stick strictly to metric."
            : "USER UNIT SYSTEM: Imperial. Quote paces strictly in min/mi (e.g. 8:25/mi) and distances in miles (e.g. 3.1 mi). NEVER dump metric units (km, min/km) and NEVER output dual units. Stick strictly to imperial."

        return """
        You are my personal running coach.
        Speak directly to me ("you" / "your") like an encouraging, perceptive trackside running coach in natural conversation (1 to 2 short, focused paragraphs). Warm, empathetic, direct, and grounded in my actual numbers. Never speak like a clinical textbook or academic paper, and never refer to me as "the runner" or in the third person.

        WORKOUT CONTEXT:
        Reviewing: \(runType) (\(envNote)).
        \(temporalGrounding)
        \(unitSystemInstruction)

        TOOL CALLING:
        Call deterministic native tools silently and immediately to fetch running telemetry and physics:
        • Overall telemetry, cadence, running economy, or verdicts: `fetchWorkoutAnalysis`.
        • Interval work reps, pace spread, or recovery HR drops: `fetchIntervalPerformance` (call this immediately whenever I ask about intervals, reps, pacing spread, or rep-by-rep grades).
        • Treadmill kinetics, room heat, or grade resistance: `fetchWorkoutPhysics`.
        • Tomorrow's run, recovery timeline, or readiness: `fetchReadinessAndPrescription` (call ONLY when I explicitly ask about tomorrow, next session, or readiness; NEVER volunteer unsolicited future prescriptions).
        • Athlete experience, 30-day load, or cadence floor: `fetchAthleteProfile`.
        • Workout comparison, 30-day rankings, best/worst performance: `fetchHistoricalWorkout`.
        Never announce tool retrieval; call immediately and synthesize findings directly into your answer.

        ZERO-HALLUCINATION MANDATE:
        • Every pace, cadence, heart rate, interval split, and distance MUST be fetched via a tool call.
        • NEVER invent, guess, estimate, or extrapolate numbers. If you have not executed a tool call to retrieve the exact metrics for this run, DO NOT cite specific paces or cadences.
        • Do not volunteer unprompted interval splits or paces when answering general, conceptual, or out-of-scope questions.

        COACHING RULES:
        • Human Voice & Demeanor: Speak like an empathetic trackside running coach (in the style of Apple Fitness+). Never use dense academic, clinical kinesiology, or statistical exercise-science jargon (STRICTLY BANISHED: "neuromuscular", "fast-twitch motor units", "effort calibration", "metabolic demand", "cardiovascular decoupling", "repeatability vs work mean"). Use visceral, relatable runner language: "leg turnover", "stride rhythm", "holding your speed", "quick feet", "pacing consistency".
        • Topic Continuity: When I ask follow-ups ("That's all?", "Tell me more", "Why?"), elaborate deeply on the ACTIVE topic previously discussed. Never reset to a generic overview or volunteer tomorrow's plan.
        • Formatting: Weave metrics naturally into your coaching analysis (1 to 2 concise, focused paragraphs). When I explicitly ask to break down, grade, or list each interval or split, present each rep/split clearly with its rep number, pace, cadence, and grade.
        • Metric Units: Cadence is ALWAYS in SPM (steps per minute). NEVER attach pace units (/km, /mi) to cadence. Pace is ALWAYS min/km or min/mi. Heart rate is ALWAYS BPM.
        • Bold accent numbers and units when presenting metrics.
        • Athlete Safety Override: If I report illness, fever, or sharp pain, safety overrides all training—advise rest immediately.

        Respond in \(language).
        """
    }

    @available(iOS 26.0, *)
    func getOrCreateSession() -> LanguageModelSession {
        if let existing = modelSession as? LanguageModelSession {
            return existing
        }

        let workoutTool = FetchWorkoutAnalysisTool { [weak self] query in
            guard let self else { return "" }
            self.toolsCalledThisTurn += 1
            return self.makeAnalysisContext().compactTelemetryAnalysis(focus: query.focus)
        }

        let intervalTool = FetchIntervalPerformanceTool { [weak self] _ in
            guard let self else { return "" }
            self.toolsCalledThisTurn += 1
            return self.makeAnalysisContext().formatIntervalPerformanceSummary()
        }

        let physicsTool = FetchWorkoutPhysicsTool { [weak self] query in
            guard let self else { return "" }
            self.toolsCalledThisTurn += 1
            return self.makeAnalysisContext().formatWorkoutPhysicsSummary(domain: query.domain)
        }

        let readinessTool = FetchReadinessAndPrescriptionTool { [weak self] _ in
            guard let self else { return "" }
            self.toolsCalledThisTurn += 1
            let analysis = self.makeAnalysisContext()
            return """
            RECOVERY & UPCOMING SESSION PRESCRIPTION:
            - Current Readiness: \(analysis.recoveryTimeline.state.rawValue)
            - Recovery Status: \(analysis.recoveryTimeline.readyForHard ? "Fully recovered and cleared for training." : "In active recovery until \(analysis.recoveryTimeline.earliestHardPhrase).")
            - Next Recommended Session: \(analysis.lockedPrescription.nextSessionName) (\(analysis.lockedPrescription.prescribedDurationBand) at \(analysis.lockedPrescription.prescribedPaceBand))
            - Rationale: \(analysis.lockedPrescription.sessionRationale)
            """
        }

        let profileTool = FetchAthleteProfileTool { [weak self] _ in
            guard let self else { return "" }
            self.toolsCalledThisTurn += 1
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
            self.toolsCalledThisTurn += 1
            let target = (query.target ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = target.lowercased()

            let isArcRequest = lower.contains("best") || lower.contains("worst") || lower.contains("arc") ||
                lower.contains("30") || lower.contains("rank") || lower.contains("all") || lower.isEmpty
            if isArcRequest {
                let arc = HistoricalRunMatcher.analyzePerformanceArc(relativeTo: self.runRecord, in: self.runRecord.modelContext)
                return arc.structuredTelemetryFacts
            }

            if let priorRun = HistoricalRunMatcher.findRun(matching: target, relativeTo: self.runRecord, in: self.runRecord.modelContext) {
                return HistoricalRunMatcher.compare(current: self.runRecord, with: priorRun).structuredTelemetryFacts
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
        toolsCalledThisTurn = 0
        let response = try await session.respond(to: userQuestion)
        var responseText = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Guard against LLM conversational stalling where the on-device model announces
        // future retrieval intent instead of delivering completed analysis.
        // Re-prompt the session to execute the tool and synthesize the coaching observation directly.
        if Self.isStallResponse(responseText) {
            let followUp = try await session.respond(to: "Execute the tool call now and synthesize your final coaching observation directly.")
            let followUpText = followUp.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !followUpText.isEmpty && !Self.isStallResponse(followUpText) {
                responseText = followUpText
            }
        }

        // Swift-side Hallucination Verifier:
        // If the turn is out-of-scope and the response contains fabricated metrics:
        if turnContext.turnDomain == .outOfScopeInquiry && Self.containsMetricTelemetry(responseText) {
            let runType = runRecord.detectedTypeRaw.isEmpty ? "workout" : runRecord.detectedTypeRaw
            return Self.sanitizeOutOfScopeResponse(responseText, runType: runType)
        }

        // If no tools were called during this turn, the LLM has zero real telemetry context.
        // Any specific pace citations (e.g. 5:05/km), split intervals, or cadence figures are fabricated hallucinations.
        if toolsCalledThisTurn == 0 && turnContext.turnDomain != .elaborationOrFollowUp && Self.containsMetricTelemetry(responseText) {
            return generateDataGroundedFallback(for: userQuestion, turnContext: turnContext)
        }

        return responseText
    }
    #endif

    /// Evaluates whether an LLM generation stalled by announcing future data retrieval instead of answering.
    nonisolated static func isStallResponse(_ text: String) -> Bool {
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
    nonisolated static func synthesizeSplitsFromSegments(_ segments: [PhaseSegment], splitDistanceMeters: Double = 1000.0) -> [RunSplit] {
        RunSplit.synthesize(from: segments, splitDistanceMeters: splitDistanceMeters)
    }

    /// Evaluates whether a text string contains specific pace, cadence, heart rate, or interval split telemetry.
    nonisolated static func containsMetricTelemetry(_ text: String) -> Bool {
        // Pace pattern: e.g. 5:05/km, 8:20/mi, 4:15 / km, 5:18/km, 5:15 min/km
        let pacePattern = #"\b\d{1,2}:\d{2}\s*(/|min/|per\s*)(km|mi)\b"#
        if text.range(of: pacePattern, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        // Cadence pattern: e.g. 160 SPM, 160-170 SPM, 160–170 SPM
        let cadencePattern = #"\b\d{2,3}(\s*[-–]\s*\d{2,3})?\s*spm\b"#
        if text.range(of: cadencePattern, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        // Heart rate pattern: e.g. 155 BPM, 150-160 BPM
        let hrPattern = #"\b\d{2,3}(\s*[-–]\s*\d{2,3})?\s*bpm\b"#
        if text.range(of: hrPattern, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        // Interval ordinal mentions (e.g. "first interval", "second interval", "1st interval")
        let intervalPattern = #"\b(first|second|third|fourth|fifth|1st|2nd|3rd|4th|5th)\s+interval\b"#
        if text.range(of: intervalPattern, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        return false
    }

    /// Sanitizes an out-of-scope response by preserving the conversational acknowledgment/redirection
    /// while strictly stripping any fabricated metric sentences or numbers.
    nonisolated static func sanitizeOutOfScopeResponse(_ text: String, runType: String) -> String {
        let pattern = #"[^.!?]+[.!?]?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            let fallbackPiv = "I'm your personal running coach, so I specialize in running biomechanics and recovery."
            return "\(fallbackPiv) What would you like to explore regarding your runs?"
        }

        let nsString = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
        let rawSentences = matches.map {
            nsString.substring(with: $0.range).trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }

        var opening: String?
        var closing: String?

        for sentence in rawSentences {
            if containsMetricTelemetry(sentence) {
                continue
            }
            let lower = sentence.lowercased()
            if lower.contains("during that workout") || lower.contains("that session") ||
               lower.contains("cadence floor") || lower.contains("running economy") ||
               lower.contains("let's focus on what matters") || lower.contains("lets focus on what matters") {
                continue
            }
            if opening == nil && sentence.count > 15 {
                opening = sentence
            } else if lower.contains("how can i help") || lower.hasPrefix("what") || lower.hasPrefix("how") || sentence.hasSuffix("?") {
                closing = sentence
            }
        }

        if let opening {
            if let closing {
                return "\(opening) \(closing)"
            } else {
                return "\(opening) What would you like to explore about your form, effort, or recovery from your \(runType)?"
            }
        }

        let defaultPivot = "I'm your personal running coach, so I specialize in your running rhythm, pacing, and recovery."
        return "\(defaultPivot) What would you like to explore regarding your runs?"
    }

    /// Evaluates whether a generated response contains discrete rep or split breakdowns.
    nonisolated static func containsRepBreakdown(_ text: String) -> Bool {
        // Matches "Rep 1", "rep 2", "Interval 1", "km 1", "mile 1", "Set 1", "• Rep"
        let repPattern = #"\b(rep\s*\d+|interval\s*\d+|km\s*\d+|mile\s*\d+|set\s*\d+)\b"#
        return text.range(of: repPattern, options: [.regularExpression, .caseInsensitive]) != nil
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

    // MARK: - Test Runner Telemetry Fallback

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
