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
        let monday = makeDate(year: 2026, month: 10, day: 19)
        let tuesday = makeDate(year: 2026, month: 10, day: 20)
        let wednesday = makeDate(year: 2026, month: 10, day: 21)

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
}
