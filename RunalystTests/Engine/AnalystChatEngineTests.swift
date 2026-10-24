import SwiftData
import XCTest
#if canImport(FoundationModels)
import FoundationModels
#endif
@testable import Runalyst

@MainActor
final class AnalystChatEngineTests: XCTestCase {

    private func makeDate(year: Int, month: Int, day: Int, hour: Int = 10) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = 0
        comps.second = 0
        comps.timeZone = TimeZone(identifier: "America/New_York") ?? TimeZone.current
        let cal = Calendar(identifier: .gregorian)
        return cal.date(from: comps) ?? Date()
    }

    private func makeRunRecord(
        date: Date,
        duration: Double = 1800,
        distanceMeters: Double = 5000,
        cadence: Double = 160,
        heartRate: Double = 145,
        type: String = "Easy Run"
    ) -> RunRecord {
        RunRecord(
            hkWorkoutID: UUID(),
            date: date,
            totalDistanceMeters: distanceMeters,
            duration: duration,
            rawAvgPace: duration / (distanceMeters / 1000.0),
            rawAvgHeartRate: heartRate,
            rawAvgCadence: cadence,
            workingAvgPace: duration / (distanceMeters / 1000.0),
            workingAvgCadence: cadence,
            workingAvgHeartRate: heartRate,
            paceCV: 0.04,
            paceSlope: 0.0,
            percentZone4: 0.0,
            detectedTypeRaw: type
        )
    }

    // MARK: - 1. Compact Schedule Projection

    func testCompactScheduleProjectionFormat() {
        let completedSummary = CompletedWorkoutSummary(
            type: "Fartlek",
            minutes: 32.5,
            distance: 5.27,
            unit: "km",
            targetMet: true,
            avgHeartRate: 152,
            avgCadence: 164
        )

        let day1 = ScheduleDay(
            date: "2026-10-19",
            weekday: "Monday",
            relative: .today,
            completion: .completed,
            completed: [completedSummary],
            planned: PlannedSession(
                kind: .run,
                title: "Zone 2 Easy Aerobic Base",
                minutesLow: 30,
                minutesHigh: 30,
                paceBand: "7:44-8:14/km"
            )
        )

        let day2 = ScheduleDay(
            date: "2026-10-20",
            weekday: "Tuesday",
            relative: .tomorrow,
            completion: .upcoming,
            completed: [],
            planned: PlannedSession(
                kind: .run,
                title: "Zone 2 Easy Aerobic Base",
                minutesLow: 30,
                minutesHigh: 30,
                paceBand: "7:44-8:14/km",
                primerTitle: "Cadence Pyramids"
            )
        )

        let day3 = ScheduleDay(
            date: "2026-10-21",
            weekday: "Wednesday",
            relative: .future,
            completion: .upcoming,
            completed: [],
            planned: PlannedSession(
                kind: .rest,
                title: "Rest Day",
                minutesLow: 0,
                minutesHigh: 0
            )
        )

        let formatted = TrainingCalendar.formatCompactScheduleSummary(days: [day1, day2, day3])

        XCTAssertTrue(formatted.contains("SCHEDULE TIMELINE:"))
        XCTAssertTrue(formatted.contains("Today (Monday, 2026-10-19): 5.27 km Fartlek (COMPLETED)"))
        XCTAssertTrue(formatted.contains("Tomorrow (Tuesday, 2026-10-20): Planned: Zone 2 Easy Aerobic Base (30 min @ 7:44-8:14/km), Primer: Cadence Pyramids"))
        XCTAssertTrue(formatted.contains("Wednesday (2026-10-21): Rest Day (No run scheduled)"))

        // Must not contain raw JSON markers
        XCTAssertFalse(formatted.contains("\"date\":"))
        XCTAssertFalse(formatted.contains("\"weekday\":"))
        XCTAssertFalse(formatted.contains("{\""))
    }

    // MARK: - 2. Invariant 1: Echo Chamber Guard in Context Slicing

    func testEchoChamberInvariantDropsPendingUserPrompt() {
        let run = makeRunRecord(date: Date())
        let engine = AnalystChatEngine(runRecord: run, mode: .macroCoach)

        // Add turn 1: completed
        engine.messages.append(AnalystChatMessage(sender: .user, text: "What's my best run?", status: .delivered))
        engine.messages.append(AnalystChatMessage(sender: .analyst, text: "Your best run was on Friday.", status: .delivered))

        // Add a failed message (must NOT be included in context)
        engine.messages.append(AnalystChatMessage(sender: .analyst, text: "Failed attempt", status: .failed(retryPrompt: "retry me")))

        // Add turn 2: currently pending user prompt
        engine.messages.append(AnalystChatMessage(sender: .user, text: "Should I run tomorrow?", status: .delivered))

        if #available(iOS 26.0, *) {
            let instructions = engine.buildLeanSystemInstructions()

            // Turn 1 must be present in reference dialogue
            XCTAssertTrue(instructions.contains("Runner: \"What's my best run?\""))
            XCTAssertTrue(instructions.contains("Coach: \"Your best run was on Friday.\""))

            // Failed message must NOT be in reference dialogue
            XCTAssertFalse(instructions.contains("Failed attempt"))

            // Active pending user question must NOT be in reference dialogue (Invariant 1)
            XCTAssertFalse(instructions.contains("Runner: \"Should I run tomorrow?\""))
        }
    }

    // MARK: - 3. Invariant 4: Retry In-Place Without Duplicate User Bubbles

    func testRetryMessageInPlaceWithoutDuplicateUserBubble() async {
        let run = makeRunRecord(date: Date())
        let engine = AnalystChatEngine(runRecord: run, mode: .macroCoach)

        // Set up initial state with a failed turn
        let userMessage = AnalystChatMessage(sender: .user, text: "Should I run tomorrow?", status: .delivered)
        let failedAnalystId = UUID()
        let failedMessage = AnalystChatMessage(
            id: failedAnalystId,
            sender: .analyst,
            text: "I'm having trouble analyzing this run right now.",
            status: .failed(retryPrompt: "Should I run tomorrow?")
        )

        engine.messages = [userMessage, failedMessage]
        XCTAssertEqual(engine.messages.count, 2)

        // Configure responder to succeed on retry
        engine.modelResponder = { _, question in
            XCTAssertEqual(question, "Should I run tomorrow?")
            return "You are clear to run tomorrow for 30 minutes easy."
        }

        // Execute in-place retry
        await engine.retryMessage(failedMessageId: failedAnalystId)

        // Verify bipartite structure: exactly 1 user bubble, exactly 1 analyst bubble
        XCTAssertEqual(engine.messages.count, 2)
        XCTAssertEqual(engine.messages[0].sender, .user)
        XCTAssertEqual(engine.messages[0].text, "Should I run tomorrow?")

        XCTAssertEqual(engine.messages[1].sender, .analyst)
        XCTAssertEqual(engine.messages[1].text, "You are clear to run tomorrow for 30 minutes easy.")
        XCTAssertEqual(engine.messages[1].status, .delivered)
    }

    // MARK: - 4. Non-Retryable Error Immediately Fails

    func testNonRetryableCancellationErrorFailsImmediately() async {
        let run = makeRunRecord(date: Date())
        let engine = AnalystChatEngine(runRecord: run, mode: .macroCoach)

        engine.modelResponder = { _, _ in
            throw CancellationError()
        }

        await engine.sendMessage("Analyze my last run")

        XCTAssertEqual(engine.messages.count, 2)
        XCTAssertEqual(engine.messages[0].sender, .user)
        XCTAssertEqual(engine.messages[1].sender, .analyst)
        if case .failed(let prompt) = engine.messages[1].status {
            XCTAssertEqual(prompt, "Analyze my last run")
        } else {
            XCTFail("Status must be .failed on non-retryable error")
        }
    }

    // MARK: - 5. Re-entrancy Lock

    func testReentrancyLockIgnoresConcurrentSend() async {
        let run = makeRunRecord(date: Date())
        let engine = AnalystChatEngine(runRecord: run, mode: .macroCoach)

        engine.isResponding = true
        await engine.sendMessage("This should be ignored due to mutex")

        XCTAssertTrue(engine.messages.isEmpty)
    }

    // MARK: - 6. Native Tool-Calling Architecture & Zero Response-Sniffing

    func testNativeToolExecutionAttachesDrillCard() async {
        let run = makeRunRecord(date: Date().addingTimeInterval(-86400))
        let engine = AnalystChatEngine(runRecord: run, mode: .macroCoach)

        engine.modelResponder = { _, _ in
            await engine.executeCoachAction(query: ExecuteCoachActionQuery(action: .displayDrill, payload: "tempo_surges"))
            return "With your 48-hour volume compressing gently, a tempo-surge session is ideal to build turnover."
        }

        await engine.sendMessage("What kind of session should I focus on?")

        XCTAssertEqual(engine.messages.count, 2)
        let analystMsg = engine.messages[1]
        XCTAssertEqual(analystMsg.sender, .analyst)
        XCTAssertEqual(analystMsg.attachedDrillId, .tempoSurges)
        XCTAssertEqual(analystMsg.text, "With your 48-hour volume compressing gently, a tempo-surge session is ideal to build turnover.")
    }

    func testPureConversationalResponseWithoutToolCallAttachesZeroCards() async {
        let run = makeRunRecord(date: Date())
        let engine = AnalystChatEngine(runRecord: run, mode: .macroCoach)

        engine.modelResponder = { _, _ in
            "Focus: A 45-minute easy-pace run to reinforce your progress and build aerobic capacity."
        }

        await engine.sendMessage("When should I run next?")

        XCTAssertEqual(engine.messages.count, 2)
        let analystMsg = engine.messages[1]
        XCTAssertNil(analystMsg.attachedDrillId, "Without tool invocation, drill card must be nil")
        XCTAssertNil(analystMsg.attachedSession, "Without tool invocation, session card must be nil")
        XCTAssertNil(analystMsg.attachedSchedule, "Without tool invocation, schedule card must be nil")
        XCTAssertNil(analystMsg.attachedExplainerKey, "Without tool invocation, explainer card must be nil")
        XCTAssertEqual(analystMsg.text, "Focus: A 45-minute easy-pace run to reinforce your progress and build aerobic capacity.")
    }

    func testRecentDialogueInSystemInstructionsFormatsCleanly() {
        let run = makeRunRecord(date: Date())
        let engine = AnalystChatEngine(runRecord: run, mode: .macroCoach)

        engine.messages.append(AnalystChatMessage(sender: .user, text: "What drill should I do?", status: .delivered))
        engine.messages.append(AnalystChatMessage(sender: .analyst, text: "Here is your plan for today.", status: .delivered))
        engine.messages.append(AnalystChatMessage(sender: .user, text: "Should I run tomorrow?", status: .delivered))

        if #available(iOS 26.0, *) {
            let instructions = engine.buildLeanSystemInstructions()
            let recentDialogue = instructions.components(separatedBy: "RECENT DIALOGUE (Reference Only):").last?
                .components(separatedBy: "TOOLS:").first ?? ""
            XCTAssertTrue(recentDialogue.contains("Coach: \"Here is your plan for today.\""))
        }
    }

    // MARK: - 7. Native Tool-Calling: Session & Schedule Cards

    func testNativeToolExecutionAttachesSessionCard() async {
        let run = makeRunRecord(date: Date())
        let engine = AnalystChatEngine(runRecord: run, mode: .macroCoach)

        engine.modelResponder = { _, _ in
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            engine.executeTrainingScheduleQuery(query: GetTrainingScheduleQuery(from: df.string(from: Date())))
            return "Here is your planned workout session."
        }

        await engine.sendMessage("What is my next workout session?")

        XCTAssertEqual(engine.messages.count, 2)
        let analystMsg = engine.messages[1]
        XCTAssertNotNil(analystMsg.attachedSession, "Session card must be attached when tool executes schedule query")
    }

    func testNativeToolExecutionAttachesScheduleCard() async {
        let run = makeRunRecord(date: Date())
        let engine = AnalystChatEngine(runRecord: run, mode: .macroCoach)

        engine.modelResponder = { _, _ in
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            let today = Date()
            let future = Calendar.current.date(byAdding: .day, value: 7, to: today) ?? today
            engine.executeTrainingScheduleQuery(query: GetTrainingScheduleQuery(from: df.string(from: today), to: df.string(from: future)))
            return "Here is your upcoming training schedule for the week."
        }

        await engine.sendMessage("Show me my schedule for this week")

        XCTAssertEqual(engine.messages.count, 2)
        let analystMsg = engine.messages[1]
        XCTAssertNotNil(analystMsg.attachedSchedule, "Schedule card must be attached when tool executes schedule query")
        XCTAssertFalse(analystMsg.attachedSchedule?.isEmpty ?? true)
    }

    // MARK: - 8. Zero Guessing: Text Mention Without Tool Call Attaches Zero Cards

    func testConversationalDrillDiscussionWithoutToolCallAttachesZeroCards() async {
        let run = makeRunRecord(date: Date())
        let engine = AnalystChatEngine(runRecord: run, mode: .macroCoach)

        engine.modelResponder = { _, _ in
            "Cadence pyramids are a fantastic way to train a lighter foot strike and keep your bounce controlled."
        }

        await engine.sendMessage("Focus on the cadence pyramid drill")

        XCTAssertEqual(engine.messages.count, 2)
        let analystMsg = engine.messages[1]
        XCTAssertEqual(analystMsg.sender, .analyst)
        XCTAssertNil(analystMsg.attachedDrillId, "Pure conversational text mentioning a drill must never attach a card without tool invocation")
    }

    func testAffirmativeConfirmationWithToolCallAttachesDrillCard() async {
        let run = makeRunRecord(date: Date().addingTimeInterval(-86400))
        let engine = AnalystChatEngine(runRecord: run, mode: .macroCoach)

        engine.messages.append(AnalystChatMessage(sender: .user, text: "How can I improve my rhythm?", status: .delivered))
        engine.messages.append(AnalystChatMessage(sender: .analyst, text: "I recommend trying the Cadence Pyramids drill before your next easy run.", status: .delivered))

        engine.modelResponder = { _, _ in
            await engine.executeCoachAction(query: ExecuteCoachActionQuery(action: .displayDrill, payload: "cadence_pyramids"))
            return "Here is the workout structure for you."
        }

        await engine.sendMessage("Display the drill.")

        XCTAssertEqual(engine.messages.count, 4)
        let lastMsg = engine.messages[3]
        XCTAssertEqual(lastMsg.attachedDrillId, .cadencePyramids, "Tool execution attaches the prescribed drill card")
    }

    func testTomorrowRunQueryWithToolCallAttachesSessionCard() async {
        let run = makeRunRecord(date: Date())
        let engine = AnalystChatEngine(runRecord: run, mode: .macroCoach)

        engine.modelResponder = { _, _ in
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            engine.executeTrainingScheduleQuery(query: GetTrainingScheduleQuery(from: df.string(from: Date())))
            return "Tomorrow is planned as a scheduled session to allow steady adaptation."
        }

        await engine.sendMessage("Can I run tomorrow?")

        XCTAssertEqual(engine.messages.count, 2)
        let analystMsg = engine.messages[1]
        XCTAssertNotNil(analystMsg.attachedSession, "Session card must attach when tool executes schedule query")
    }

    // MARK: - 9. System Prompt Character Budget (< 1200)

    func testSystemInstructionsUnder1200CharactersWithFourTurns() {
        let run = makeRunRecord(date: Date())
        let engine = AnalystChatEngine(runRecord: run, mode: .macroCoach)

        for i in 1...4 {
            engine.messages.append(AnalystChatMessage(sender: .user, text: "Question number \(i) about my workout pacing and heart rate recovery?", status: .delivered))
            engine.messages.append(AnalystChatMessage(sender: .analyst, text: "Answer number \(i) explaining the physiological reason why pacing was stable.", status: .delivered))
        }

        if #available(iOS 26.0, *) {
            let instructions = engine.buildLeanSystemInstructions()

            XCTAssertTrue(instructions.contains("Workload: Trust 'workload_zone'"), "Prompt must ground workload zone")
            XCTAssertTrue(instructions.contains("Silent Tools: Never write command names"), "Prompt must ban leaking tool command names")
            XCTAssertTrue(instructions.contains("Medical Safety"), "Prompt must enforce medical safety boundaries")
            XCTAssertTrue(instructions.count < 1200, "System instructions must stay strictly under 1,200 chars (was \(instructions.count))")
        }
    }

    // MARK: - 10. Next Scheduled Run Resolution via Tool Execution

    func testWhenIsMyNextScheduledRunAttachesUpcomingRunSessionCardNotRestDay() async {
        let run = makeRunRecord(date: Date())
        let engine = AnalystChatEngine(runRecord: run, mode: .macroCoach)

        engine.modelResponder = { _, _ in
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            engine.executeTrainingScheduleQuery(query: GetTrainingScheduleQuery(from: df.string(from: Date())))
            return "Your next scheduled run is on Thursday: a 30-minute Easy Aerobic run."
        }

        await engine.sendMessage("So when is my next scheduled run?")

        XCTAssertEqual(engine.messages.count, 2)
        let analystMsg = engine.messages[1]
        XCTAssertNotNil(analystMsg.attachedSession, "Session card must be attached when tool executes schedule query")
        XCTAssertFalse(analystMsg.attachedSession?.isRestDay ?? true, "Attached session must be an actual run, not a rest day")
        XCTAssertNotNil(analystMsg.attachedSession?.dayLabel)
        if let dayLabel = analystMsg.attachedSession?.dayLabel {
            XCTAssertFalse(analystMsg.attachedSession?.sessionTitle.hasSuffix(" (\(dayLabel))") ?? false, "Session title should not append day in parentheses")
        }
        XCTAssertFalse(analystMsg.attachedSession?.isToday ?? true, "Upcoming next run must not be marked as today")
    }

    // MARK: - 11. Pure Conversational Delivery (Zero Regex Hacking)

    func testModelConversationalResponsePreservedPurelyWithoutMutilation() async {
        let run = makeRunRecord(date: Date())
        let engine = AnalystChatEngine(runRecord: run, mode: .macroCoach)

        let originalProse = "Tomorrow is a rest day—no run scheduled. Take this time to recover and prepare for your next session."
        engine.modelResponder = { _, _ in
            originalProse
        }

        await engine.sendMessage("Can I run tomorrow?")

        XCTAssertEqual(engine.messages.count, 2)
        let analystMsg = engine.messages[1]
        XCTAssertEqual(analystMsg.text, originalProse, "Conversational prose must be delivered exactly as emitted without regex mutilation")
        XCTAssertNil(analystMsg.attachedSession, "Without tool invocation, no session card is attached")
    }

    func testInformationalPrimerQueryDoesNotAttachDrillCard() async {
        let run = makeRunRecord(date: Date())
        let engine = AnalystChatEngine(runRecord: run, mode: .macroCoach)

        engine.modelResponder = { _, _ in
            "A pre-run primer is an optional 5–10 min neuromuscular activation drill done before main runs to activate turnover and protect joints."
        }

        await engine.sendMessage("What is the purpose of the pre run primer?")

        XCTAssertEqual(engine.messages.count, 2)
        let analystMsg = engine.messages[1]
        XCTAssertEqual(analystMsg.sender, .analyst)
        XCTAssertNil(analystMsg.attachedDrillId, "Informational query about primers must not attach an interactive drill card")
    }

    func testInformationalCadenceQueryDoesNotAttachDrillCard() async {
        let run = makeRunRecord(date: Date())
        let engine = AnalystChatEngine(runRecord: run, mode: .macroCoach)

        engine.modelResponder = { _, _ in
            "Your cadence of 156 SPM was consistent with your baseline for this pace. Keep rhythm smooth."
        }

        await engine.sendMessage("Why is my cadence 156 SPM?")

        XCTAssertEqual(engine.messages.count, 2)
        let analystMsg = engine.messages[1]
        XCTAssertEqual(analystMsg.sender, .analyst)
        XCTAssertNil(analystMsg.attachedDrillId, "Informational cadence query must not attach an interactive drill card")
    }

    func testExplicitStridesRequestWithToolCallAttachesStridesCard() async {
        let run = makeRunRecord(date: Date().addingTimeInterval(-86400))
        let engine = AnalystChatEngine(runRecord: run, mode: .macroCoach)

        engine.modelResponder = { _, _ in
            await engine.executeCoachAction(query: ExecuteCoachActionQuery(action: .displayDrill, payload: "strides"))
            return "Strides help activate your nervous system and encourage light, quick turnover."
        }

        await engine.sendMessage("Can you show me strides?")

        XCTAssertEqual(engine.messages.count, 2)
        let analystMsg = engine.messages[1]
        XCTAssertEqual(analystMsg.sender, .analyst)
        XCTAssertEqual(analystMsg.attachedDrillId, .strides, "Explicit tool call for strides must attach Strides drill card")
    }

    // MARK: - 12. Decoupled Macro Coach

    func testMacroCoachDecoupledFromRunRecordInitializesAndGeneratesInstructionsUnder1200Chars() {
        if #available(iOS 26.0, *) {
            let engine = AnalystChatEngine(modelContext: nil, runRecord: nil, mode: .macroCoach)
            let instructions = engine.buildLeanSystemInstructions()

            XCTAssertFalse(instructions.isEmpty)
            XCTAssertTrue(instructions.contains("Today:"), "System instructions should provide today schedule context")
            XCTAssertTrue(instructions.count < 1200, "System instructions must stay strictly under 1,200 chars (was \(instructions.count))")
        }
    }

    func testMacroCoachDecoupledCanAnswerQuestionsAndAttachCards() async {
        let engine = AnalystChatEngine(modelContext: nil, runRecord: nil, mode: .macroCoach)

        engine.modelResponder = { _, _ in
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            engine.executeTrainingScheduleQuery(query: GetTrainingScheduleQuery(from: df.string(from: Date())))
            return "Tomorrow is a scheduled session. Take time to prepare."
        }

        await engine.sendMessage("Should I run tomorrow?")

        XCTAssertEqual(engine.messages.count, 2)
        let analystMsg = engine.messages[1]
        XCTAssertNotNil(analystMsg.attachedSession, "Session card should attach when tool executes schedule query")
    }

    // MARK: - 13. Tool Attachment Deduplication

    func testWhenNextRunQueryRecommendsDrillAlignsPrimerAndDeduplicatesCard() async {
        let engine = AnalystChatEngine(modelContext: nil, runRecord: nil, mode: .macroCoach)

        engine.modelResponder = { _, _ in
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            engine.executeTrainingScheduleQuery(query: GetTrainingScheduleQuery(from: df.string(from: Date())))
            await engine.executeCoachAction(query: ExecuteCoachActionQuery(action: .displayDrill, payload: "strides"))
            return "Your next run is scheduled for Friday. Warm up with strides."
        }

        await engine.sendMessage("When should I run next, and what kind of session should I focus on?")

        XCTAssertEqual(engine.messages.count, 2)
        let analystMsg = engine.messages[1]
        XCTAssertNotNil(analystMsg.attachedSession, "Session card should be attached for next run query")
        XCTAssertNil(analystMsg.attachedDrillId, "Standalone drill card must be deduplicated when session card is attached")
    }

    func testExplicitDrillQueryPreservesStandaloneDrillCard() async {
        let engine = AnalystChatEngine(modelContext: nil, runRecord: nil, mode: .macroCoach)

        engine.modelResponder = { _, _ in
            await engine.executeCoachAction(query: ExecuteCoachActionQuery(action: .displayDrill, payload: "cadence_pyramids"))
            return "Try Cadence Pyramids to develop light, quick foot strikes and reduce knee stress."
        }

        await engine.sendMessage("Which drill would help improve my running form and cadence?")

        XCTAssertEqual(engine.messages.count, 2)
        let analystMsg = engine.messages[1]
        XCTAssertEqual(analystMsg.attachedDrillId, .cadencePyramids, "Explicit drill tool call surfaces standalone drill card")
        XCTAssertNil(analystMsg.attachedSession, "Explicit drill tool call does not attach a session card")
    }

    func testMacroCoachInstructionsIncludeExplicitCalendarDateGrounding() {
        if #available(iOS 26.0, *) {
            let engine = AnalystChatEngine(modelContext: nil, runRecord: nil, mode: .macroCoach)
            let instructions = engine.buildLeanSystemInstructions()

            let cal = Calendar(identifier: .gregorian)
            let year = cal.component(.year, from: Date())
            XCTAssertTrue(instructions.contains("\(year)"), "System instructions must include the current year for temporal grounding")
        }
    }

    func testInformationalPrimerQueryDoesNotAttachWorkoutCard() async {
        let engine = AnalystChatEngine(modelContext: nil, runRecord: nil, mode: .macroCoach)

        engine.modelResponder = { _, _ in
            "The pre-run primer is a 5-10 minute neuromuscular activation routine done before your run to prime turnover and prepare your stride."
        }

        await engine.sendMessage("What is the purpose of the pre run primer?")

        XCTAssertEqual(engine.messages.count, 2)
        let analystMsg = engine.messages[1]
        XCTAssertNil(analystMsg.attachedDrillId, "Informational query must not attach a drill card")
        XCTAssertNil(analystMsg.attachedSession, "Informational query must not attach a full workout session card")
    }

    func testExecuteCoachActionDisplayDrillOutputsHumanReadableTitleAndStatus() async throws {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let engine = AnalystChatEngine(modelContext: nil, runRecord: nil, mode: .macroCoach)
            _ = engine.getOrCreateSession()
            let tool = ExecuteCoachActionTool { query in
                let resolved = PreRunDrillId.resolve(from: query.payload ?? "") ?? .strides
                engine.drillRecommendedThisTurn = resolved
                return "{\"drill_id\":\"\(resolved.rawValue)\",\"drill_name\":\"\(resolved.title)\",\"status\":\"interactive_drill_card_displayed\",\"message\":\"The \(resolved.title) interactive workout card is displayed directly below your response.\"}"
            }
            let result = try await tool.call(arguments: ExecuteCoachActionQuery(action: .displayDrill, payload: "cadence_pyramids"))
            XCTAssertTrue(result.contains("\"drill_name\":\"Cadence Pyramids\""))
            XCTAssertTrue(result.contains("Cadence Pyramids interactive workout card is displayed"))
            XCTAssertEqual(engine.drillRecommendedThisTurn, .cadencePyramids)
        }
        #endif
    }

    func testAnalystChatSheetDestinationIdentifiableContracts() {
        let explainerInfo = MetricExplainerInfo(
            title: "Vertical Oscillation",
            definition: "Bounce amplitude during flight phase.",
            userMetricDisplay: "8.4 cm"
        )
        let explainerDestination = AnalystChatView.SheetDestination.explainer(explainerInfo)
        XCTAssertEqual(explainerDestination.id, "explainer_\(explainerInfo.id)")

        let libraryDestination = AnalystChatView.SheetDestination.drillsLibrary
        XCTAssertEqual(libraryDestination.id, "drills_library")

        let dto = DrillPrescriptionDTO(
            title: "Cadence Pyramids",
            preRunDrillId: PreRunDrillId.cadencePyramids.rawValue,
            purpose: "Prime neuro-muscular turnover",
            targetCadence: "165-170",
            previousCadence: 160,
            durationMinutes: 6
        )
        let readoutItem = ActiveDrillReadoutItem.fromPrescription(dto: dto)
        let readoutDestination = AnalystChatView.SheetDestination.readout(readoutItem)
        XCTAssertEqual(readoutDestination.id, "readout_\(readoutItem.id)")
    }

    func testReadinessFactsWorkloadZoneClassification() throws {
        let facts = ReadinessFacts(
            readiness_state: "productive",
            acwr: 0.60,
            workload_zone: .underload,
            streak_days: 0,
            streak_limit: 4,
            last_48h_minutes: 0,
            weekly_avg_minutes: 120,
            volume_ratio_48h: 0.0,
            volume_threshold: 0.65,
            hr_shift_bpm: 0,
            today_minutes: 0,
            today_target_minutes: 35,
            today_completion_percent: 0,
            second_run_advisable: true,
            limiting_factors: [],
            experience_level: "Beginner",
            training_goal: "Base Building",
            cadence_floor_spm: 155
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(facts)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("\"workload_zone\":\"underload\""))
        XCTAssertFalse(json.contains("runner_reported_distress"))
    }

    func testTrainingScheduleDefaultsTo7DayMicrocycleAndHydratesNextSessionCard() async throws {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            let container = try ModelContainer(for: RunRecord.self, configurations: config)
            let context = container.mainContext

            // Seed a past run to establish profile
            let run = makeRunRecord(date: Date().addingTimeInterval(-86400 * 3), duration: 1800, distanceMeters: 4000)
            context.insert(run)
            try context.save()

            let engine = AnalystChatEngine(modelContext: context, runRecord: nil, mode: .macroCoach)
            _ = engine.getOrCreateSession()

            let cal = Calendar.current
            let df = DateFormatter()
            df.calendar = cal
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = "yyyy-MM-dd"
            let todayStr = df.string(from: Date())

            // Call getTrainingSchedule with to: nil (unified query)
            let tool = GetTrainingScheduleTool { query in
                engine.executeTrainingScheduleQuery(query: query)
            }

            let result = try await tool.call(arguments: GetTrainingScheduleQuery(from: todayStr, to: nil))

            // Tool must return multi-day timeline
            XCTAssertTrue(result.contains("SCHEDULE TIMELINE:"))
            // Engine must automatically bind the next session card
            XCTAssertNotNil(engine.sessionRecommendedThisTurn, "Querying the schedule must directly hydrate the next session card")
        }
        #endif
    }
}
