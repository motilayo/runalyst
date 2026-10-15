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

        // 1.5. Musculoskeletal Pain, Joint Discomfort or Injury Inquiry
        let painKeywords = ["pain", "hurt", "hurts", "hurting", "knee", "shin", "achilles", "plantar", "injury", "injured", "soreness", "swollen", "painkiller"]
        if painKeywords.contains(where: { lower.contains($0) }) {
            return ManagedTurnContext(
                turnDomain: .workoutTelemetryAnalysis,
                turnIndex: userTurnIndex,
                isSubjectiveDistress: false,
                cleanConversationDigest: summarizeHistory(messages),
                turnGuidance: "The runner mentioned pain, soreness, or potential injury (e.g. knee discomfort). Clarify you are an AI telemetry analyst, not a doctor or physical therapist, and advise seeking medical help if pain is acute, sharp, or persistent. Corroborate with their telemetry (cadence vs. floor, pace, and vertical oscillation) to explain potential overstriding or braking forces. If they seek medical care, prioritize recovery. If they choose to run, recommend an appropriate form drill next (e.g. Cadence Pyramids or Strides).",
                stripWorkoutPayload: false,
                prunePhysiologicalVerdicts: false
            )
        }

        // 2. Out-of-Scope Detection (General Trivia, Coding, Non-running inquiries)
        if isOutOfScopeQuery(lower) {
            return ManagedTurnContext(
                turnDomain: .outOfScopeInquiry,
                turnIndex: userTurnIndex,
                isSubjectiveDistress: false,
                cleanConversationDigest: "",
                turnGuidance: "The user is asking a general knowledge, non-running, or out-of-scope question. Acknowledge what they asked in a friendly sentence (e.g., clarifying that you coach running, not general trivia, dance, or cooking), then pivot back to their running. CRITICAL: NEVER invent, estimate, or quote workout metrics (paces, cadences, interval splits) when pivoting. Simply ask how you can help with their running training or recovery.",
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
            "so what does that mean?", "so what's the verdict?", "so what's the verdict",
            "what's the verdict?", "what's the verdict", "what is the verdict?", "what is the verdict"
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

            let isFuturePlanningTopic = lastUserMsg.contains("tomorrow") ||
                lastUserMsg.contains("next run") ||
                lastUserMsg.contains("green light") ||
                lastCoachMsg.contains("tomorrow") ||
                lastCoachMsg.contains("readiness") ||
                lastCoachMsg.contains("standing")

            if isFuturePlanningTopic {
                return ManagedTurnContext(
                    turnDomain: .futureSessionPlanning,
                    turnIndex: userTurnIndex,
                    isSubjectiveDistress: false,
                    cleanConversationDigest: summarizeHistory(messages, pruneRetrospectiveDetail: true),
                    turnGuidance: "TURN FOCUS: Future Training & Readiness. The runner is asking for the final readiness verdict on running tomorrow. Ground your answer strictly in fetchReadinessAndPrescription without quoting past workout metrics.",
                    stripWorkoutPayload: false,
                    prunePhysiologicalVerdicts: true
                )
            }

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
                2. Analyze work rep pacing consistency, recovery heart rate drops, and cadence maintenance through the late reps.
                """
            } else if isCardiacTopic {
                guidance = """
                TURN FOCUS: In-Depth Heart Rate & Effort Elaboration.
                Explain the physiological drivers of cardiac drift (thermal buildup in static room air, dehydration, or aerobic fatigue).
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

        // 2.8. Session & Drill Sequencing ("Which order should I do both runs?", "Which one first?")
        let isSequencingIntent = lower.contains("which order") ||
            lower.contains("what order") ||
            lower.contains("order should i") ||
            lower.contains("in what order") ||
            lower.contains("which one first") ||
            lower.contains("which should i do first") ||
            lower.contains("which run first") ||
            lower.contains("both runs") ||
            lower.contains("both sessions") ||
            lower.contains("both workouts") ||
            lower.contains("before or after") ||
            lower.contains("same day") ||
            (lower.contains("order") && (lower.contains("run") || lower.contains("drill") || lower.contains("session") || lower.contains("both")))

        if isSequencingIntent {
            let guidance = """
            TURN FOCUS: Session & Drill Sequencing.
            The runner is asking about the order, scheduling, or combination of recommended sessions and form drills.
            1. Recommend completing the recovery session (e.g. Zone 1 Active Recovery Flush) first to allow fatigue to clear.
            2. Recommend scheduling the form drill (e.g. Cadence Pyramids or Strides) during the warm-up of their next active training session when neuromuscular coordination is fresh.
            3. DO NOT reset the conversation or recite past workout metrics. Answer their sequencing question directly.
            """
            return ManagedTurnContext(
                turnDomain: .futureSessionPlanning,
                turnIndex: userTurnIndex,
                isSubjectiveDistress: false,
                cleanConversationDigest: summarizeHistory(messages, pruneRetrospectiveDetail: true),
                turnGuidance: guidance,
                stripWorkoutPayload: false,
                prunePhysiologicalVerdicts: true
            )
        }

        // 3. Composite Intent Detection (Workout Telemetry + Future Planning)
        let workoutMarkers = [
            "heart rate", "hr", "cadence", "split", "fade", "bounce", "oscillation",
            "today's run", "that run", "my run", "why did", "interval", "intervals",
            "rep", "reps", "work pace", "turnover"
        ]
        let futureMarkers = [
            "tomorrow", "next run", "should i rest", "should i run", "can i run",
            "how long", "what pace", "take a rest day", "green light", "run again",
            "run similar", "run another", "run a similar", "verdict", "what's the verdict",
            "whats the verdict", "ready to push", "ready for a similar",
            "which order", "what order", "both runs", "both sessions", "which one first",
            "which should i do first", "before or after", "same day", "schedule", "routine"
        ]

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
            turnGuidance: "TURN FOCUS: Workout Telemetry & Biomechanics. Detail the workout's execution, pacing, cadence, and physiological verdicts using data from native tool calls.",
            stripWorkoutPayload: false,
            prunePhysiologicalVerdicts: false
        )
    }

    /// Evaluates whether an input query is asking an out-of-scope, non-running question.
    static func isOutOfScopeQuery(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let triggers = [
            "dougie", "dance", "dancing", "twerk", "waltz", "salsa", "hip hop",
            "sing", "song", "lyrics", "rap", "music", "guitar", "piano",
            "recipe", "cook", "bake", "pancake", "cake", "pizza", "burger", "cocktail",
            "movie", "actor", "actress", "film", "cinema", "video game", "play game", "chess", "poker",
            "write python", "write swift", "write code", "coding", "javascript", "html", "css",
            "who won the", "president of", "capital of", "weather in", "stock market", "crypto", "bitcoin",
            "tell me a joke", "write a poem", "write a story", "bedtime story"
        ]
        return triggers.contains { lower.contains($0) }
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
