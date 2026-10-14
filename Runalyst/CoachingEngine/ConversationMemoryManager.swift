import Foundation

/// Turn intent domain classified deterministically by Swift before invoking the LLM.
enum TurnDomain: Sendable, Equatable {
    case workoutTelemetryAnalysis   // Past workout metrics, splits, biomechanics
    case futureSessionPlanning       // Tomorrow, next run, pacing, duration
    case compositeWorkoutAndPlanning // Dual question: "Why did HR spike and can I run tomorrow?"
    case physiologicalEducation      // Concept explanation: VO2 Max, threshold, cadence
    case subjectiveDistressReported  // Illness, fever, sickness, acute injury, extreme exhaustion
    case outOfScopeInquiry           // Trivia, non-running topics, general chat
    case elaborationOrFollowUp       // Follow-up: "That's all?", "Tell me more", "Why?"
}

/// Managed context and memory scoping synthesized for a single conversation turn.
struct ManagedTurnContext: Sendable, Equatable {
    let turnDomain: TurnDomain
    let turnIndex: Int
    let isSubjectiveDistress: Bool
    let cleanConversationDigest: String
    let turnGuidance: String
    let stripWorkoutPayload: Bool
    let prunePhysiologicalVerdicts: Bool

    init(
        turnDomain: TurnDomain,
        turnIndex: Int = 0,
        isSubjectiveDistress: Bool = false,
        cleanConversationDigest: String = "",
        turnGuidance: String = "",
        stripWorkoutPayload: Bool = false,
        prunePhysiologicalVerdicts: Bool = false
    ) {
        self.turnDomain = turnDomain
        self.turnIndex = turnIndex
        self.isSubjectiveDistress = isSubjectiveDistress
        self.cleanConversationDigest = cleanConversationDigest
        self.turnGuidance = turnGuidance
        self.stripWorkoutPayload = stripWorkoutPayload
        self.prunePhysiologicalVerdicts = prunePhysiologicalVerdicts
    }

    var promptHeader: String {
        var lines: [String] = []
        lines.append("TURN CONTEXT & DIRECTIVE:")
        lines.append("- Domain: \(turnDomain) (Turn \(turnIndex))")
        lines.append("- Memory Guidance: \(turnGuidance)")
        if !cleanConversationDigest.isEmpty {
            lines.append("- Conversation Digest:\n\(cleanConversationDigest)")
        }
        return lines.joined(separator: "\n")
    }
}

/// Swift Conversation Memory Manager and Semantic Intent Router.
enum ConversationMemoryManager {
    /// Classifies user question into a TurnDomain and compiles turn-scoped memory guidance.
    static func buildTurnContext(
        userQuestion: String,
        messages: [AnalystChatMessage],
        recoveryStateDescription: String,
        daysSinceWorkout: Int
    ) -> ManagedTurnContext {
        let lower = userQuestion.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let userTurnIndex = max(0, messages.filter { $0.sender == .user }.count)

        // 1. Subjective Distress Detection (Illness, Fever, Extreme Exhaustion, Acute Injury)
        let distressWords: Set<String> = [
            "sick", "fever", "cough", "flu", "ill", "exhausted", "vomit", "dizzy", "headache"
        ]
        let distressPhrases = [
            "throat hurt", "sore throat", "barely slept", "didn't sleep", "didnt sleep",
            "feel awful", "feeling awful", "threw up", "chest pain", "strain my"
        ]
        let tokens = Set(lower.split(whereSeparator: { !$0.isLetter }).map(String.init))
        let isWordDistress = !tokens.isDisjoint(with: distressWords)
        let isPhraseDistress = distressPhrases.contains(where: { lower.contains($0) })

        if isWordDistress || isPhraseDistress {
            return ManagedTurnContext(
                turnDomain: .subjectiveDistressReported,
                turnIndex: userTurnIndex,
                isSubjectiveDistress: true,
                cleanConversationDigest: summarizeHistory(messages),
                turnGuidance: "The runner reported physical illness, fever, or acute distress. Prioritize rest, hydration, and recovery above all training goals. Do not recommend running.",
                stripWorkoutPayload: false,
                prunePhysiologicalVerdicts: false
            )
        }

        // 2. Out-of-Scope Detection (General Trivia, Coding, Non-running inquiries)
        let outOfScopeTriggers = [
            "who won the", "president of", "capital of", "recipe for", "how do i fix a flat tire on my bike",
            "movie", "actor", "weather in", "write python", "write swift code"
        ]
        if outOfScopeTriggers.contains(where: { lower.contains($0) }) {
            return ManagedTurnContext(
                turnDomain: .outOfScopeInquiry,
                turnIndex: userTurnIndex,
                isSubjectiveDistress: false,
                cleanConversationDigest: "",
                turnGuidance: "The user is asking a general knowledge or non-running question. Answer concisely in 1–2 sentences, then politely pivot the conversation back to their personal running data and goals.",
                stripWorkoutPayload: true,
                prunePhysiologicalVerdicts: true
            )
        }

        // 2.5. Follow-Up / Elaboration Detection ("That's all?", "Tell me more", "Why?", "Explain further")
        let cleanLower = lower.replacingOccurrences(of: "’", with: "'")
        let elaborationExactMatches: Set<String> = [
            "that's all?", "that's all", "thats all?", "thats all", "is that all?", "is that all",
            "tell me more", "tell me more.", "more details", "can you elaborate?", "can you elaborate",
            "elaborate", "elaborate please", "why?", "why is that?", "why did that happen?",
            "what else?", "what else", "go deeper", "break it down further", "anything else?",
            "anything else", "continue", "explain further", "expand on that", "can you explain why?",
            "so what does that mean?"
        ]
        let elaborationPrefixes = [
            "that's all", "thats all", "is that all", "tell me more", "more details",
            "can you elaborate", "elaborate on", "go deeper", "break it down further",
            "explain further", "expand on", "what else can you tell"
        ]
        let isElaborationMatch = elaborationExactMatches.contains(cleanLower) ||
            elaborationPrefixes.contains(where: { cleanLower.hasPrefix($0) })

        if isElaborationMatch {
            let substantive = messages.filter { $0.text.count > 10 }
            let lastUserMsg = substantive.last(where: { $0.sender == .user })?.text.lowercased() ?? ""
            let lastCoachMsg = substantive.last(where: { $0.sender == .analyst })?.text.lowercased() ?? ""

            let isComparisonTopic = lastUserMsg.contains("compare") ||
                lastUserMsg.contains("versus") ||
                lastUserMsg.contains(" vs ") ||
                lastCoachMsg.contains("comparing your") ||
                lastCoachMsg.contains(" vs ") ||
                lastCoachMsg.contains("faster in current") ||
                lastCoachMsg.contains("slower in current")

            let isIntervalTopic = lastUserMsg.contains("interval") ||
                lastUserMsg.contains("rep") ||
                lastCoachMsg.contains("interval") ||
                lastCoachMsg.contains("rep ")

            let isCardiacTopic = lastUserMsg.contains("heart") ||
                lastUserMsg.contains("hr") ||
                lastUserMsg.contains("drift") ||
                lastCoachMsg.contains("cardiac drift") ||
                lastCoachMsg.contains("decoupling")

            let guidance: String
            if isComparisonTopic {
                guidance = """
                TURN FOCUS: In-Depth Workout Comparison Elaboration.
                The runner is asking for deeper insights on the comparison between this session and the historical run.
                1. DO NOT reset the conversation to an unsolicited overall summary of this workout.
                2. DO NOT prescribe tomorrow's workout or mention future readiness.
                3. Contrast the underlying physiological and mechanical mechanisms:
                   • Contrast workout modalities: discrete interval work bouts with active recovery valleys vs continuous steady/tempo threshold effort.
                   • Explain why average heart rate was lower/higher: recovery intervals allow heart rate recovery, or continuous pacing maintains unbroken cardiac cost.
                   • Contrast mechanical demands: motor-driven treadmill belt vs outdoor pavement propulsion, lack of air resistance vs convective wind cooling.
                   • Explain what cadence and pace stability reveal about aerobic progress.
                """
            } else if isIntervalTopic {
                guidance = """
                TURN FOCUS: In-Depth Interval Performance Elaboration.
                The runner is asking to go deeper into their interval rep execution.
                1. DO NOT reset to a generic overview or prescribe tomorrow's session.
                2. Analyze work rep pacing repeatability, recovery heart rate drops, and cadence maintenance through the late reps.
                """
            } else if isCardiacTopic {
                guidance = """
                TURN FOCUS: In-Depth Cardiovascular Decoupling Elaboration.
                Explain the physiological drivers of cardiac drift (thermal accumulation, stroke volume reduction, aerobic decoupling).
                DO NOT volunteer tomorrow's workout prescription.
                """
            } else {
                guidance = """
                TURN FOCUS: In-Depth Conversational Elaboration.
                The runner wants deeper coaching on the previous topic. Provide advanced physiological and biomechanical insights without resetting to an unsolicited workout summary or prescribing tomorrow's session.
                """
            }

            return ManagedTurnContext(
                turnDomain: .elaborationOrFollowUp,
                turnIndex: userTurnIndex,
                isSubjectiveDistress: false,
                cleanConversationDigest: summarizeHistory(messages),
                turnGuidance: guidance,
                stripWorkoutPayload: false,
                prunePhysiologicalVerdicts: false
            )
        }

        // 3. Composite Intent Detection (Workout Telemetry + Future Planning)
        let workoutMarkers = ["heart rate", "hr", "cadence", "split", "fade", "bounce", "oscillation", "today's run", "that run", "my run", "why did"]
        let futureMarkers = ["tomorrow", "next run", "should i rest", "should i run", "can i run", "how long", "what pace", "take a rest day"]

        let hasWorkoutIntent = workoutMarkers.contains(where: { lower.contains($0) })
        let hasFutureIntent = futureMarkers.contains(where: { lower.contains($0) })

        if hasWorkoutIntent && hasFutureIntent {
            let guidance = "COMPOSITE BRIDGING DIRECTIVE: Answer sequentially: First, explain the root cause of the past workout exertion using the physiological verdicts. Second, evaluate tomorrow's readiness using strictly the Current Recovery Status (\(recoveryStateDescription)) and the Locked Training Prescription Table. Do not assume past exertion from a previous session prohibits running tomorrow unless the recovery timeline explicitly requires active recovery."
            return ManagedTurnContext(
                turnDomain: .compositeWorkoutAndPlanning,
                turnIndex: userTurnIndex,
                isSubjectiveDistress: false,
                cleanConversationDigest: summarizeHistory(messages),
                turnGuidance: guidance,
                stripWorkoutPayload: false,
                prunePhysiologicalVerdicts: false
            )
        }

        // 4. Future Session Planning Only (Aggressive turn-scoping prunes retrospective verdicts)
        if hasFutureIntent || lower.contains("ready") || lower.contains("rest day") || lower.contains("push hard") {
            let restNote = daysSinceWorkout > 0 ? "You have had \(daysSinceWorkout) days of rest since your last session." : "This workout was today."
            let guidance = "TURN FOCUS: Future Training & Readiness. Ground your response strictly in the Current Recovery Status (\(recoveryStateDescription)) and Locked Prescription Table. \(restNote) Answer whether I can run and detail the prescribed next session. DO NOT repeat past workout metrics, cardiac drift, or split details. Focus 100% on the upcoming session."
            let shouldPruneVerdicts = userTurnIndex > 0 || true
            return ManagedTurnContext(
                turnDomain: .futureSessionPlanning,
                turnIndex: userTurnIndex,
                isSubjectiveDistress: false,
                cleanConversationDigest: summarizeHistory(messages, pruneRetrospectiveDetail: true),
                turnGuidance: guidance,
                stripWorkoutPayload: false,
                prunePhysiologicalVerdicts: shouldPruneVerdicts
            )
        }

        // 5. Physiological Concept Education
        let educationMarkers = ["what is", "what does", "explain", "meaning of", "define"]
        let conceptTerms = ["vo2", "threshold", "cadence", "cardiac drift", "vertical ratio", "efficiency factor", "aerobic base"]
        if educationMarkers.contains(where: { lower.contains($0) }) && conceptTerms.contains(where: { lower.contains($0) }) {
            return ManagedTurnContext(
                turnDomain: .physiologicalEducation,
                turnIndex: userTurnIndex,
                isSubjectiveDistress: false,
                cleanConversationDigest: summarizeHistory(messages),
                turnGuidance: "TURN FOCUS: Running Concept Education. Explain the physiological concept clearly, connecting it to running mechanics.",
                stripWorkoutPayload: false,
                prunePhysiologicalVerdicts: false
            )
        }

        // 6. Positive Highlights Focus ("What went well?")
        let positiveMarkers = ["went well", "what went well", "highlights", "positives", "good about", "did well", "strengths"]
        if positiveMarkers.contains(where: { lower.contains($0) }) {
            let guidance = "TURN FOCUS: Workout Highlights & Strengths. Focus exclusively on what was executed well (e.g. cadence stability above floor, strong work reps, base-building alignment). DO NOT volunteer unsolicited criticisms, cardiac drift, or fatigue warnings."
            return ManagedTurnContext(
                turnDomain: .workoutTelemetryAnalysis,
                turnIndex: userTurnIndex,
                isSubjectiveDistress: false,
                cleanConversationDigest: summarizeHistory(messages),
                turnGuidance: guidance,
                stripWorkoutPayload: false,
                prunePhysiologicalVerdicts: false
            )
        }

        // 7. Tactical Improvement Focus ("What could be better?")
        let improvementMarkers = ["could be better", "what went wrong", "what to improve", "how to improve", "areas to improve", "critique", "weaknesses"]
        if improvementMarkers.contains(where: { lower.contains($0) }) {
            let guidance = "TURN FOCUS: Areas for Technique & Pacing Improvement. Explain tactical execution adjustments for this workout (e.g. pacing consistency across work reps, maintaining cadence turnover late in the run). DO NOT volunteer next-session workouts or future zone tables."
            return ManagedTurnContext(
                turnDomain: .workoutTelemetryAnalysis,
                turnIndex: userTurnIndex,
                isSubjectiveDistress: false,
                cleanConversationDigest: summarizeHistory(messages),
                turnGuidance: guidance,
                stripWorkoutPayload: false,
                prunePhysiologicalVerdicts: false
            )
        }

        // 8. Default: Workout Telemetry Analysis
        return ManagedTurnContext(
            turnDomain: .workoutTelemetryAnalysis,
            turnIndex: userTurnIndex,
            isSubjectiveDistress: false,
            cleanConversationDigest: summarizeHistory(messages),
            turnGuidance: "TURN FOCUS: Workout Telemetry & Biomechanics. Explain what happened during this specific workout using the physiological verdicts.",
            stripWorkoutPayload: false,
            prunePhysiologicalVerdicts: false
        )
    }

    /// Compiles a concise digest of recent turns to avoid token bloat and context contamination.
    private static func summarizeHistory(_ messages: [AnalystChatMessage], pruneRetrospectiveDetail: Bool = false) -> String {
        // Exclude the initial greeting and only take last 3 exchanges
        let substantive = messages.filter { $0.text.count > 10 }
        let recent = substantive.suffix(4)
        guard !recent.isEmpty else { return "" }

        var lines: [String] = []
        for msg in recent {
            if pruneRetrospectiveDetail && msg.sender == .analyst {
                continue
            }
            let sender = msg.sender == .user ? "Runner" : "Coach"
            let snippet = msg.text.prefix(120).replacingOccurrences(of: "\n", with: " ")
            lines.append("  • \(sender): \(snippet)...")
        }
        return lines.joined(separator: "\n")
    }
}
