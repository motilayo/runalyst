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

    // MARK: - 6. Leaked Tool Syntax Sanitization and Fallback Action Execution

    func testLeakedExecuteCoachActionDisplayDrillIsSanitizedAndAttachesDrillCard() async {
        let run = makeRunRecord(date: Date())
        let engine = AnalystChatEngine(runRecord: run, mode: .macroCoach)

        engine.modelResponder = { _, _ in
            """
            With your 48-hour volume compressing gently and no limiting factors beyond a mild cardiac drift, a tempo-surge session is ideal—it builds strength while keeping intensity manageable. I'll display the tempo-surge drill for you right now.

            Next run recommendation: tempo-surge session.

            executeCoachAction:display_drill:tempo_surges
            """
        }

        await engine.sendMessage("When should I run next, and what kind of session should I focus on?")

        XCTAssertEqual(engine.messages.count, 2)
        let analystMsg = engine.messages[1]
        XCTAssertEqual(analystMsg.sender, .analyst)

        // Raw action token must be stripped from visible text
        XCTAssertFalse(analystMsg.text.contains("executeCoachAction"))
        XCTAssertFalse(analystMsg.text.contains("display_drill"))

        // Drill card must be seamlessly attached via fallback
        XCTAssertEqual(analystMsg.attachedDrillId, .tempoSurges)
    }

    func testLeakedDirectDisplayDrillIsSanitized() async {
        let run = makeRunRecord(date: Date())
        let engine = AnalystChatEngine(runRecord: run, mode: .macroCoach)

        engine.modelResponder = { _, _ in
            """
            Focus: A 45-minute easy-pace run to reinforce your progress.

            I'll display the easy-pace drill to guide you.

            display_drill: easy_pace_drill
            """
        }

        await engine.sendMessage("When should I run next?")

        XCTAssertEqual(engine.messages.count, 2)
        let analystMsg = engine.messages[1]
        XCTAssertFalse(analystMsg.text.contains("display_drill"))
        XCTAssertFalse(analystMsg.text.contains("easy_pace_drill"))
    }

    func testLeakedToolSyntaxInHistoryIsSanitizedFromRecentDialoguePrompt() {
        let run = makeRunRecord(date: Date())
        let engine = AnalystChatEngine(runRecord: run, mode: .macroCoach)

        // Simulate an earlier message that had raw leaked tokens
        engine.messages.append(AnalystChatMessage(sender: .user, text: "What drill should I do?", status: .delivered))
        engine.messages.append(
            AnalystChatMessage(
                sender: .analyst,
                text: "Here is your plan. executeCoachAction:display_drill:tempo_surges",
                status: .delivered
            )
        )
        engine.messages.append(AnalystChatMessage(sender: .user, text: "Should I run tomorrow?", status: .delivered))

        if #available(iOS 26.0, *) {
            let instructions = engine.buildLeanSystemInstructions()

            // Reference dialogue block must NOT contain the leaked action strings
            let recentDialogue = instructions.components(separatedBy: "RECENT DIALOGUE (Reference Only):").last?
                .components(separatedBy: "TOOLS:").first ?? ""
            XCTAssertFalse(recentDialogue.contains("executeCoachAction"))
            XCTAssertFalse(recentDialogue.contains("display_drill"))
            XCTAssertTrue(recentDialogue.contains("Coach: \"Here is your plan.\""))
        }
    }

    // MARK: - 7. Standalone "Display the drill." Sanitization & Action Detection

    func testSanitizerCleansStandaloneDisplayTheDrillAndProvidesCleanText() {
        if #available(iOS 26.0, *) {
            let sanitized = AnalystResponseSanitizer.sanitize(text: "Display the drill.")
            XCTAssertEqual(sanitized.detectedAction, .displayDrill)
            XCTAssertEqual(sanitized.text, "Here is the drill to focus on.")

            let sanitizedWithSpecific = AnalystResponseSanitizer.sanitize(text: "Display drill: cadence_pyramids")
            XCTAssertEqual(sanitizedWithSpecific.detectedAction, .displayDrill)
            XCTAssertEqual(sanitizedWithSpecific.text, "Here is the Cadence Pyramids drill to focus on.")
        }
    }

    // MARK: - 8. Proactive Drill Attachment on Demand

    func testExplicitUserDrillRequestAttachesDrillCardEvenWithoutToolCall() async {
        let run = makeRunRecord(date: Date())
        let engine = AnalystChatEngine(runRecord: run, mode: .macroCoach)

        // Model returns pure prose with no tool call and no leaked token
        engine.modelResponder = { _, _ in
            "Cadence pyramids are a fantastic way to train a lighter foot strike and keep your bounce controlled."
        }

        await engine.sendMessage("Focus on the cadence pyramid drill")

        XCTAssertEqual(engine.messages.count, 2)
        let analystMsg = engine.messages[1]
        XCTAssertEqual(analystMsg.sender, .analyst)
        XCTAssertEqual(analystMsg.attachedDrillId, .cadencePyramids, "Drill card must be attached proactively when user asks for cadence pyramids")
    }

    // MARK: - 9. Affirmative Confirmation ("Display the drill." / "Yes") Attaches Prior Mentioned Drill

    func testAffirmativeConfirmationFollowingDrillMentionAttachesDrillCard() async {
        let run = makeRunRecord(date: Date())
        let engine = AnalystChatEngine(runRecord: run, mode: .macroCoach)

        // Turn 1: Coach recommends Cadence Pyramids
        engine.messages.append(AnalystChatMessage(sender: .user, text: "How can I improve my rhythm?", status: .delivered))
        engine.messages.append(AnalystChatMessage(sender: .analyst, text: "I recommend trying the Cadence Pyramids drill before your next easy run.", status: .delivered))

        // Turn 2: User responds "Display the drill."
        engine.modelResponder = { _, _ in
            "Here is the workout structure for you."
        }

        await engine.sendMessage("Display the drill.")

        XCTAssertEqual(engine.messages.count, 4)
        let lastMsg = engine.messages[3]
        XCTAssertEqual(lastMsg.attachedDrillId, .cadencePyramids, "Affirmative command must attach the drill mentioned in dialogue")
    }

    // MARK: - 10. Tomorrow Run Query Proactively Attaches Session Card

    func testTomorrowRunQueryProactivelyAttachesSessionCard() async {
        let run = makeRunRecord(date: Date())
        let engine = AnalystChatEngine(runRecord: run, mode: .macroCoach)

        engine.modelResponder = { _, _ in
            "Tomorrow is planned as a scheduled rest day to allow your legs to recover fully."
        }

        await engine.sendMessage("Can I run tomorrow?")

        XCTAssertEqual(engine.messages.count, 2)
        let analystMsg = engine.messages[1]
        XCTAssertNotNil(analystMsg.attachedSession, "Session card must be attached when runner asks about tomorrow's schedule")
    }

    // MARK: - 11. System Prompt Characters Strictly Under 1200 With Full History

    func testSystemInstructionsUnder1200CharactersWithFourTurns() {
        let run = makeRunRecord(date: Date())
        let engine = AnalystChatEngine(runRecord: run, mode: .macroCoach)

        // Populate 4 full turns of dialogue
        for i in 1...4 {
            engine.messages.append(AnalystChatMessage(sender: .user, text: "Question number \(i) about my workout pacing and heart rate recovery?", status: .delivered))
            engine.messages.append(AnalystChatMessage(sender: .analyst, text: "Answer number \(i) explaining the physiological reason why pacing was stable.", status: .delivered))
        }

        if #available(iOS 26.0, *) {
            let instructions = engine.buildLeanSystemInstructions()

            // Verify prompt rules
            XCTAssertTrue(instructions.contains("ACWR: Acute:Chronic Workload Ratio"), "Prompt must ground ACWR acronym")
            XCTAssertTrue(instructions.contains("Proactive Cards: Never ask permission"), "Prompt must ban permission asking")
            XCTAssertTrue(instructions.contains("Display the drill"), "Prompt must explicitly forbid echoing display the drill")

            // TN3193 character budget ceiling
            XCTAssertTrue(instructions.count < 1200, "System instructions must stay strictly under 1,200 chars (was \(instructions.count))")
        }
    }

    // MARK: - 12. Next Scheduled Run Resolution (Not Tomorrow's Rest Day)

    func testWhenIsMyNextScheduledRunAttachesUpcomingRunSessionCardNotRestDay() async {
        let run = makeRunRecord(date: Date())
        let engine = AnalystChatEngine(runRecord: run, mode: .macroCoach)

        engine.modelResponder = { _, _ in
            "Your next scheduled run is on Thursday: a 30-minute Easy Aerobic run."
        }

        await engine.sendMessage("So when is my next scheduled run?")

        XCTAssertEqual(engine.messages.count, 2)
        let analystMsg = engine.messages[1]
        XCTAssertNotNil(analystMsg.attachedSession, "Session card must be attached when runner asks for next scheduled run")
        XCTAssertFalse(analystMsg.attachedSession?.isRestDay ?? true, "Attached session must be an actual run, not a rest day")
    }

    // MARK: - 13. Sanitizer Strips Trailing Repetitive Offers

    func testSanitizerStripsTrailingSharpenFormOffers() {
        if #available(iOS 26.0, *) {
            let input1 = "Tomorrow is a rest day—no run scheduled. Take this time to recover and prepare for your next session. Would you like a drill to sharpen your running form or anything else?"
            let cleaned1 = AnalystResponseSanitizer.sanitize(text: input1).text
            XCTAssertEqual(cleaned1, "Tomorrow is a rest day—no run scheduled. Take this time to recover and prepare for your next session.")

            let input2 = "Your readiness is strong—great! But tomorrow is a rest day for recovery. Would you like me to display your current readiness and workload overview?"
            let cleaned2 = AnalystResponseSanitizer.sanitize(text: input2).text
            XCTAssertEqual(cleaned2, "Your readiness is strong—great! But tomorrow is a rest day for recovery.")
        }
    }

    // MARK: - 14. Decoupled Macro Coach (Zero Runs / No RunRecord Anchor)

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
            "Tomorrow is a scheduled rest day. Take time to recover."
        }

        await engine.sendMessage("Should I run tomorrow?")

        XCTAssertEqual(engine.messages.count, 2)
        let analystMsg = engine.messages[1]
        XCTAssertNotNil(analystMsg.attachedSession, "Session card should attach proactively even without an anchored runRecord")
    }
}
