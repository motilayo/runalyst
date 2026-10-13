import Foundation

/// Turn intent domain classified deterministically by Swift before invoking the LLM.
enum TurnDomain: Sendable, Equatable {
    case workoutTelemetryAnalysis   // Past workout metrics, splits, biomechanics
    case futureSessionPlanning       // Tomorrow, next run, pacing, duration
    case compositeWorkoutAndPlanning // Dual question: "Why did HR spike and can I run tomorrow?"
    case physiologicalEducation      // Concept explanation: VO2 Max, threshold, cadence
    case subjectiveDistressReported  // Illness, fever, sickness, acute injury, extreme exhaustion
    case outOfScopeInquiry           // Trivia, non-running topics, general chat
}

/// Managed context and memory scoping synthesized for a single conversation turn.
struct ManagedTurnContext: Sendable, Equatable {
    let turnDomain: TurnDomain
    let isSubjectiveDistress: Bool
    let cleanConversationDigest: String
    let turnGuidance: String
    let stripWorkoutPayload: Bool

    var promptHeader: String {
        var lines: [String] = []
        lines.append("TURN CONTEXT & DIRECTIVE:")
        lines.append("- Domain: \(turnDomain)")
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
                isSubjectiveDistress: true,
                cleanConversationDigest: summarizeHistory(messages),
                turnGuidance: "The runner reported physical illness, fever, or acute distress. Prioritize rest, hydration, and recovery above all training goals. Do not recommend running.",
                stripWorkoutPayload: false
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
                isSubjectiveDistress: false,
                cleanConversationDigest: "",
                turnGuidance: "The user is asking a general knowledge or non-running question. Answer concisely in 1–2 sentences, then politely pivot the conversation back to their personal running data and goals.",
                stripWorkoutPayload: true
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
                isSubjectiveDistress: false,
                cleanConversationDigest: summarizeHistory(messages),
                turnGuidance: guidance,
                stripWorkoutPayload: false
            )
        }

        // 4. Future Session Planning Only
        if hasFutureIntent || lower.contains("ready") || lower.contains("rest day") || lower.contains("push hard") {
            let restNote = daysSinceWorkout > 0 ? "You have had \(daysSinceWorkout) days of rest since your last session." : "This workout was today."
            let guidance = "TURN FOCUS: Future Training & Readiness. Ground your response strictly in the Current Recovery Status (\(recoveryStateDescription)) and Locked Prescription Table. \(restNote) Answer whether I can run and detail the prescribed next session. DO NOT volunteer an unprompted retrospective review of past workouts or splits. Focus 100% on the upcoming session."
            return ManagedTurnContext(
                turnDomain: .futureSessionPlanning,
                isSubjectiveDistress: false,
                cleanConversationDigest: summarizeHistory(messages),
                turnGuidance: guidance,
                stripWorkoutPayload: false
            )
        }

        // 5. Physiological Concept Education
        let educationMarkers = ["what is", "what does", "explain", "meaning of", "define"]
        let conceptTerms = ["vo2", "threshold", "cadence", "cardiac drift", "vertical ratio", "efficiency factor", "aerobic base"]
        if educationMarkers.contains(where: { lower.contains($0) }) && conceptTerms.contains(where: { lower.contains($0) }) {
            return ManagedTurnContext(
                turnDomain: .physiologicalEducation,
                isSubjectiveDistress: false,
                cleanConversationDigest: summarizeHistory(messages),
                turnGuidance: "TURN FOCUS: Running Concept Education. Explain the physiological concept clearly, connecting it to running mechanics.",
                stripWorkoutPayload: false
            )
        }

        // 6. Default: Workout Telemetry Analysis
        return ManagedTurnContext(
            turnDomain: .workoutTelemetryAnalysis,
            isSubjectiveDistress: false,
            cleanConversationDigest: summarizeHistory(messages),
            turnGuidance: "TURN FOCUS: Workout Telemetry & Biomechanics. Explain what happened during this specific workout using the physiological verdicts.",
            stripWorkoutPayload: false
        )
    }

    /// Compiles a concise digest of recent turns to avoid token bloat and context contamination.
    private static func summarizeHistory(_ messages: [AnalystChatMessage]) -> String {
        // Exclude the initial greeting and only take last 3 exchanges
        let substantive = messages.filter { $0.text.count > 10 }
        let recent = substantive.suffix(4)
        guard !recent.isEmpty else { return "" }

        var lines: [String] = []
        for msg in recent {
            let sender = msg.sender == .user ? "Runner" : "Coach"
            let snippet = msg.text.prefix(120).replacingOccurrences(of: "\n", with: " ")
            lines.append("  • \(sender): \(snippet)...")
        }
        return lines.joined(separator: "\n")
    }
}
