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
    /// Tracks whether workout telemetry analysis has been executed and persisted to the session transcript.
    private(set) var sessionHasLoadedWorkoutAnalysis: Bool = false
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
        let isIntervals = runRecord.evaluationModality == .intervals && runRecord.detectedTypeRaw == "Intervals"
        let context = makeAnalysisContext()
        let grade = context.overallGradeReport.grade

        let initialGreeting: String
        if isIntervals && !context.workSegments.isEmpty {
            let workSegments = context.workSegments
            let meanWorkPace = workSegments.reduce(0.0) { $0 + $1.avgPace } / Double(workSegments.count)
            let workPace = PaceFormatter.formatPace(secondsPerKilometer: meanWorkPace)
            let repCount = workSegments.count
            let cad = Int((workSegments.reduce(0.0) { $0 + $1.avgCadence } / Double(workSegments.count)).rounded())
            initialGreeting = "I took a look at your Grade \(grade) \(envNote) intervals (\(repCount) reps @ \(workPace)). Want to dig into your \(cad) SPM turnover, pacing spread, or recovery?"
        } else {
            let pace = PaceFormatter.formatPace(secondsPerKilometer: runRecord.workingAvgPace)
            let cad = Int(runRecord.workingAvgCadence.rounded())
            let runType = runRecord.detectedTypeRaw.isEmpty ? "run" : runRecord.detectedTypeRaw.lowercased()
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
                #if canImport(FoundationModels)
                let systemInstructions: String
                if #available(iOS 26.0, *) {
                    systemInstructions = buildLeanSystemInstructions()
                } else {
                    systemInstructions = buildSystemInstructions(for: trimmed, turnContext: turnContext)
                }
                #else
                let systemInstructions = buildSystemInstructions(for: trimmed, turnContext: turnContext)
                #endif
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
                    self.sessionHasLoadedWorkoutAnalysis = false
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
        let envNote = isIndoor ? "Indoor Treadmill" : "Outdoors"

        let cal = Calendar.current
        let daysDiff = cal.dateComponents([.day], from: cal.startOfDay(for: runRecord.date), to: cal.startOfDay(for: Date())).day ?? 0
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "EEEE, MMMM d"
        let workoutDateStr = dateFormatter.string(from: runRecord.date)
        let todayStr = dateFormatter.string(from: Date())

        let temporalGrounding = daysDiff == 0
            ? "This workout took place TODAY."
            : "This workout took place on \(workoutDateStr) (\(daysDiff) days ago). Today is \(todayStr). Refer to it accurately as 'your \(workoutDateStr) run' or 'your \(runType)'."

        let useMetric = (UserDefaults.standard.object(forKey: "useMetricSystem") as? Bool) ?? true
        let unitSystemInstruction = useMetric
            ? "Units: Metric. Quote paces in min/km and distances in km."
            : "Units: Imperial. Quote paces in min/mi and distances in miles."

        return """
        You are an interpreter. You have access to the runner's verified telemetry through your tools.
        Your duty as an interpreter is to understand the runner's request if it relates to running and respond to them, incorporating authentic data whenever needed via the appropriate tool calls.

        Ultimately, you understand the runner: where they are currently, where they want to be based on stated goals and intents expressed in conversations, how they are trying to get there, and how you can help them get there as a runner. It is not about perfection—it is about improvement, understanding, refinement, and excellence.

        The focus is on running and on the runner's specific metrics. Answers should directly befit the question asked. Speak directly to the runner in natural, conversational language.

        WORKOUT CONTEXT:
        Reviewing: \(runType) (\(envNote)).
        \(temporalGrounding)
        \(unitSystemInstruction)

        DATA & TOOL API SPECIFICATION:
        • `fetchWorkoutAnalysis` (incorporating `fetchIntervalPerformance`, `fetchWorkoutPhysics`, and `interval_scorecard`): Retrieves current workout telemetry, interval scorecards, rep-by-rep splits, modeled physics, and causal physiological verdicts.
        • `fetchHistoricalWorkout`: Queries, filters, and retrieves past workouts from athlete history (filter by target: 'outdoor' for last outdoor run, 'indoor' for treadmill, 'recent' to list workouts, 'previous' for last run, specific date 'September 30', or 'best_and_worst' for 30-day rankings). Use `compareWith` to compare two specific workouts (e.g. target: 'last indoor run', compareWith: 'last outdoor run') for exact Swift mathematical deltas and environmental contrasts.
        • `computeWorkoutMath`: Performs exact deterministic math on running metrics (pace deltas, percentage changes, heart rate differences, distance gaps).
        • `fetchReadinessAndPrescription`: Retrieves recovery timeline, training readiness, and prescribed upcoming sessions. Set `userReportedDistress: true` if runner reports pain, soreness, illness, or fatigue.
        • `fetchAthleteProfile`: Retrieves athlete baseline, experience level, 30-day cumulative training volume, and height-calibrated cadence floor.

        GUIDANCE:
        • Ground observations directly in data returned by tools.
        • Health, Wellbeing & Safety (Athlete Safety Override): If the runner reports joint or knee pain, soreness, or injury, clarify you are an AI interpreter and not a doctor or physical therapist, advise medical care, and analyze their telemetry (cadence, pace, vertical oscillation) to see if overstriding or braking impact is a factor. If they want to run, recommend an appropriate form drill next (e.g. Cadence Pyramids or Strides).
        • All other inquiries not related to running or health and wellbeing should be handled with care and caution.

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
            self.sessionHasLoadedWorkoutAnalysis = true
            return self.makeAnalysisContext().compactTelemetryAnalysis(focus: query.focus)
        }

        let historyTool = FetchHistoricalWorkoutTool { [weak self] query in
            guard let self else { return "" }
            self.toolsCalledThisTurn += 1
            let target = query.target ?? ""
            let compareWith = query.compareWith ?? ""

            // 1. Explicit cross-run comparison: target vs compareWith
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

            // 2. Compound query in target alone (e.g. "last outdoor run to last indoor run" or "outdoor vs indoor")
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

            // 3. Performance arc, recent catalog, or single-run comparison
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
        }

        let mathTool = ComputeWorkoutMathTool { [weak self] query in
            guard let self else { return "" }
            self.toolsCalledThisTurn += 1
            let result = WorkoutMathCalculator.calculate(
                operation: query.operation,
                valueA: query.valueA,
                valueB: query.valueB,
                metricType: query.metricType
            )
            return result.structuredFacts
        }

        let readinessTool = FetchReadinessAndPrescriptionTool { [weak self] query in
            guard let self else { return "" }
            self.toolsCalledThisTurn += 1
            let isDistress = query.userReportedDistress == true
            let analysis = self.makeAnalysisContext(isSubjectiveDistress: isDistress)
            let rx = analysis.lockedPrescription
            let isReady = analysis.recoveryTimeline.readyForHard && !isDistress
            let verdict = isReady ? "CLEARED_FOR_TRAINING" : "ACTIVE_RECOVERY_REQUIRED"
            let recoveryStatus = isReady
                ? "Fully recovered and cleared for training."
                : (isDistress ? "Subjective fatigue/distress reported. Mandatory recovery prescribed." : "In active recovery until \(analysis.recoveryTimeline.earliestHardPhrase).")
            let directive = isReady
                ? "Runner is cleared for training. Prescribe \(rx.nextSessionName) directly (\(rx.prescribedDurationBand) at \(rx.prescribedPaceBand)). Focus strictly on upcoming training. Do NOT quote past workout heart rates, paces, or interval drops."
                : "Runner is in active recovery. Prescribe gentle recovery flush or rest. Keep all movement strictly light and conversational."

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
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(response),
               let json = String(data: data, encoding: .utf8) {
                return json
            }

            return """
            {
              "readiness_verdict": "\(verdict)",
              "prescribed_session_name": "\(rx.nextSessionName)",
              "prescribed_pace_band": "\(rx.prescribedPaceBand)",
              "intensity_category": "\(rx.intensityCategory)"
            }
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

        let tools: [any Tool] = [workoutTool, historyTool, mathTool, readinessTool, profileTool]
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
        var response = try await session.respond(to: userQuestion)
        var responseText = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Guard against LLM conversational stalling where the on-device model announces
        // future retrieval intent instead of delivering completed analysis.
        if Self.isStallResponse(responseText) {
            response = try await session.respond(to: "Execute the tool call now and synthesize your final coaching observation directly.")
            let followUpText = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !followUpText.isEmpty && !Self.isStallResponse(followUpText) {
                responseText = followUpText
            } else {
                return generateDataGroundedFallback(for: userQuestion, turnContext: turnContext)
            }
        }

        // If the turn is asking about workout telemetry and the workout analysis has never been loaded,
        // and the model failed to call the tool (toolsCalledThisTurn == 0):
        if !sessionHasLoadedWorkoutAnalysis && turnContext.turnDomain == .workoutTelemetryAnalysis && toolsCalledThisTurn == 0 {
            response = try await session.respond(to: "Call fetchWorkoutAnalysis now to load the verified telemetry and interval reps for this run, then provide your coaching analysis. Do NOT guess numbers.")
            let followUpText = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !followUpText.isEmpty && !Self.isStallResponse(followUpText) {
                responseText = followUpText
            }
        }

        // ABSOLUTE ZERO-HALLUCINATION SAFETY GATE:
        // If the turn is workout telemetry and the model STILL never called the tool:
        // Any numbers in responseText are GUARANTEED to be hallucinated.
        // Never show hallucinated metrics to the user. Fall back to authentic Swift telemetry!
        if !sessionHasLoadedWorkoutAnalysis && turnContext.turnDomain == .workoutTelemetryAnalysis && toolsCalledThisTurn == 0 {
            return generateDataGroundedFallback(for: userQuestion, turnContext: turnContext)
        }

        // ZERO-HALLUCINATION FUTURE READINESS SAFETY GATE:
        // If the turn is asking about tomorrow, next run, or readiness, and the model failed to call fetchReadinessAndPrescription:
        if (turnContext.turnDomain == .futureSessionPlanning || turnContext.turnDomain == .compositeWorkoutAndPlanning) && toolsCalledThisTurn == 0 {
            response = try await session.respond(to: "Call fetchReadinessAndPrescription now to get the verified readiness verdict and locked prescription for tomorrow. Do NOT invent durations or paces.")
            let followUpText = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !followUpText.isEmpty && !Self.isStallResponse(followUpText) && toolsCalledThisTurn > 0 {
                responseText = followUpText
            } else {
                return generateDataGroundedFallback(for: userQuestion, turnContext: turnContext)
            }
        }

        // Swift-side Hallucination Verifier:
        // If the turn is out-of-scope and the response contains fabricated metrics:
        if turnContext.turnDomain == .outOfScopeInquiry && Self.containsMetricTelemetry(responseText) {
            let runType = runRecord.detectedTypeRaw.isEmpty ? "workout" : runRecord.detectedTypeRaw
            return Self.sanitizeOutOfScopeResponse(responseText, runType: runType)
        }

        return responseText
    }
    #endif

    /// Evaluates whether an LLM generation stalled by announcing future data retrieval instead of answering.
    nonisolated static func isStallResponse(_ text: String) -> Bool {
        let lower = text.lowercased()
        let stallPatterns = [
            "pulling the raw data",
            "pulling the data",
            "pulling raw data",
            "i'm pulling",
            "im pulling",
            "pulling now",
            "pull the raw data",
            "checking the raw data",
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
        guard matchesPattern else { return false }
        // If it announces pulling/retrieving data, it's a stall unless it already contains actual telemetry (pace with colon e.g. 5:42/km or SPM/BPM)
        let hasActualTelemetry = containsMetricTelemetry(text) || lower.contains("bpm") || lower.contains("spm")
        return !hasActualTelemetry
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
