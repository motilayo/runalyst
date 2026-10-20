import SwiftData
import XCTest
@testable import Runalyst

final class TrainingCalendarTests: XCTestCase {

    // MARK: - Helpers

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

    private func makeTestProfile() -> RunnerProfile {
        RunnerProfile(
            experienceLevel: "Intermediate",
            trainingGoal: "Base Building",
            userHeightCm: 175,
            current30DayDistanceKm: 120,
            weeklyAverageKm: 28,
            runsPerWeek: 4
        )
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

    // MARK: - 1. Calendar Anchoring: Sunday-to-Saturday Across Locales

    func testTrainingCalendar_Anchoring_SundayToSaturday_US_GB_CA() {
        let locales = [
            Locale(identifier: "en_US"),
            Locale(identifier: "en_GB"),
            Locale(identifier: "fr_CA")
        ]

        // Tuesday, October 20, 2026
        let tuesday = makeDate(year: 2026, month: 10, day: 20)

        for locale in locales {
            var rawCal = Calendar(identifier: .gregorian)
            rawCal.locale = locale
            let trainingCal = TrainingCalendar(calendar: rawCal)

            // Week interval containing Tuesday Oct 20 must be Sunday Oct 18 to Saturday Oct 24
            let (start, end) = trainingCal.weekInterval(containing: tuesday)

            XCTAssertEqual(trainingCal.formatISO(start), "2026-10-18", "Locale \(locale.identifier) week must start on Sunday Oct 18")
            XCTAssertEqual(trainingCal.formatISO(end), "2026-10-24", "Locale \(locale.identifier) week must end on Saturday Oct 24")

            // Next week interval must be Sunday Oct 25 to Saturday Oct 31
            let (nextStart, nextEnd) = trainingCal.nextWeekInterval(relativeTo: tuesday)
            XCTAssertEqual(trainingCal.formatISO(nextStart), "2026-10-25", "Next week must start on Sunday Oct 25")
            XCTAssertEqual(trainingCal.formatISO(nextEnd), "2026-10-31", "Next week must end on Saturday Oct 31")
        }
    }

    // MARK: - 2. Anchor String Generation

    func testTrainingCalendar_AnchorString_FormatAndDetails() {
        let tuesday = makeDate(year: 2026, month: 10, day: 20)
        let calendar = TrainingCalendar(now: tuesday)

        let anchor = calendar.anchor(now: tuesday, useMetric: true)

        XCTAssertTrue(anchor.contains("TODAY: Tuesday, 2026-10-20") || anchor.contains("Today: Tue 2026-10-20"))
        XCTAssertTrue(anchor.contains("2026-10-18") && anchor.contains("2026-10-24"))
        XCTAssertTrue(anchor.contains("2026-10-25") && anchor.contains("2026-10-31"))
    }

    // MARK: - 3. Week Boundary: Saturday Completed Gives No Remaining Days

    @MainActor
    func testTrainingCalendar_WeekBoundary_SaturdayCompleted_EmptyRemainingThisWeek() {
        // Saturday, October 24, 2026
        let saturday = makeDate(year: 2026, month: 10, day: 24)
        let cal = TrainingCalendar(now: saturday)

        let completedRun = makeRunRecord(date: saturday, duration: 2400, distanceMeters: 7000)
        let profile = makeTestProfile()

        let context = ScheduleEvaluationContext(
            runRecords: [completedRun],
            activeGoal: "Base Building",
            profile: profile,
            useMetric: true
        )

        let schedule = cal.evaluateSchedule(
            from: saturday,
            to: saturday,
            context: context
        )

        XCTAssertEqual(schedule.count, 1)
        guard let day = schedule.first else {
            XCTFail("Schedule was empty")
            return
        }
        XCTAssertEqual(day.weekday, "Saturday")
        XCTAssertEqual(day.relative, ScheduleDay.RelativeDay.today)
        XCTAssertEqual(day.completion, ScheduleDay.CompletionStatus.completed)

        // Remaining days this week strictly after today (Sunday-to-Saturday week ends on Saturday)
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: saturday) else {
            XCTFail("Failed to compute tomorrow")
            return
        }
        let weekEnd = cal.weekInterval(containing: saturday).end
        XCTAssertTrue(tomorrow > weekEnd, "After Saturday, there are zero remaining days in the current week")
    }

    // MARK: - 4. Stability: Planned Session on Thursday Identical Across Windows

    @MainActor
    func testPlannerStability_PlannedSessionOnThursday_IdenticalAcrossWindows() {
        let tuesdayNow = makeDate(year: 2026, month: 10, day: 20)
        let mondayNow = makeDate(year: 2026, month: 10, day: 19)
        let targetThursday = makeDate(year: 2026, month: 10, day: 22)

        let profile = makeTestProfile()

        // 1. Target Thursday evaluated with Tuesday "now"
        let sessionFromTue = SessionSynthesisEngine.plannedSession(
            on: targetThursday,
            runRecords: [],
            activeGoal: "Base Building",
            profile: profile,
            useMetric: true,
            now: tuesdayNow
        )

        // 2. Target Thursday evaluated with Monday "now"
        let sessionFromMon = SessionSynthesisEngine.plannedSession(
            on: targetThursday,
            runRecords: [],
            activeGoal: "Base Building",
            profile: profile,
            useMetric: true,
            now: mondayNow
        )

        XCTAssertEqual(sessionFromTue.kind, sessionFromMon.kind)
        XCTAssertEqual(sessionFromTue.title, sessionFromMon.title)
        XCTAssertEqual(sessionFromTue.minutesLow, sessionFromMon.minutesLow)
        XCTAssertEqual(sessionFromTue.minutesHigh, sessionFromMon.minutesHigh)
        XCTAssertEqual(sessionFromTue.paceBand, sessionFromMon.paceBand)
        XCTAssertEqual(sessionFromTue.provisional, true, "Days past tomorrow are always marked provisional")
    }

    // MARK: - 5. Acceptance Criterion 1 & 2: Today Completed & Rest of Week (Tue Completed -> Wed..Sat)

    @MainActor
    func testEvaluateSchedule_TodayCompleted_RestOfWeekIsWednesdayToSaturday() {
        let tuesdayNow = makeDate(year: 2026, month: 10, day: 20)
        let cal = TrainingCalendar(now: tuesdayNow)

        let run1 = makeRunRecord(date: tuesdayNow.addingTimeInterval(-7200), duration: 600, distanceMeters: 1000, type: "Cadence Pyramids")
        let run2 = makeRunRecord(date: tuesdayNow.addingTimeInterval(-3600), duration: 3000, distanceMeters: 6000, type: "Easy Run")

        let profile = makeTestProfile()

        let contextWithRuns = ScheduleEvaluationContext(
            runRecords: [run1, run2],
            activeGoal: "Base Building",
            profile: profile,
            useMetric: true
        )

        // Query today
        let todaySchedule = cal.evaluateSchedule(
            from: tuesdayNow,
            to: tuesdayNow,
            context: contextWithRuns
        )

        XCTAssertEqual(todaySchedule.count, 1)
        let todayDay = todaySchedule[0]
        XCTAssertEqual(todayDay.relative, ScheduleDay.RelativeDay.today)
        XCTAssertEqual(todayDay.completion, ScheduleDay.CompletionStatus.completed)
        XCTAssertEqual(todayDay.completed.count, 2)
        XCTAssertEqual(todayDay.weekday, "Tuesday")

        // Query rest of this week: from today through Saturday (2026-10-20 to 2026-10-24)
        let saturday = cal.weekInterval(containing: tuesdayNow).end
        let weekSchedule = cal.evaluateSchedule(
            from: tuesdayNow,
            to: saturday,
            context: contextWithRuns
        )

        XCTAssertEqual(weekSchedule.count, 5, "Tuesday through Saturday is 5 days")
        XCTAssertEqual(weekSchedule[0].weekday, "Tuesday")
        XCTAssertEqual(weekSchedule[0].completion, ScheduleDay.CompletionStatus.completed)
        XCTAssertEqual(weekSchedule[1].weekday, "Wednesday")
        XCTAssertEqual(weekSchedule[1].relative, ScheduleDay.RelativeDay.tomorrow)
        XCTAssertEqual(weekSchedule[1].completion, ScheduleDay.CompletionStatus.upcoming)
        XCTAssertEqual(weekSchedule[2].weekday, "Thursday")
        XCTAssertEqual(weekSchedule[3].weekday, "Friday")
        XCTAssertEqual(weekSchedule[4].weekday, "Saturday")

        // Tomorrow's title does NOT overwrite today's title
        XCTAssertNotEqual(todayDay.planned.title, weekSchedule[1].planned.title)
    }

    // MARK: - 6. Acceptance Criterion 3: Rest of Week When Today Pending

    @MainActor
    func testEvaluateSchedule_TodayPending_ReturnsTodayAsPending() {
        let tuesdayNow = makeDate(year: 2026, month: 10, day: 20)
        let cal = TrainingCalendar(now: tuesdayNow)

        let profile = makeTestProfile()

        let emptyContext = ScheduleEvaluationContext(
            runRecords: [],
            activeGoal: "Base Building",
            profile: profile,
            useMetric: true
        )

        let schedule = cal.evaluateSchedule(
            from: tuesdayNow,
            to: tuesdayNow,
            context: emptyContext
        )

        XCTAssertEqual(schedule.count, 1)
        let todayDay = schedule[0]
        XCTAssertEqual(todayDay.relative, ScheduleDay.RelativeDay.today)
        XCTAssertEqual(todayDay.completion, ScheduleDay.CompletionStatus.pending)
        XCTAssertEqual(todayDay.completed.count, 0)
    }

    // MARK: - 7. Acceptance Criterion 4: Next Week Sun..Sat All Provisional Without Thursday Cutoff

    @MainActor
    func testEvaluateSchedule_NextWeek_FullSundayToSaturday_AllProvisional() {
        let tuesdayNow = makeDate(year: 2026, month: 10, day: 20)
        let cal = TrainingCalendar(now: tuesdayNow)

        let (nextSunday, nextSaturday) = cal.nextWeekInterval(relativeTo: tuesdayNow)
        XCTAssertEqual(cal.formatISO(nextSunday), "2026-10-25")
        XCTAssertEqual(cal.formatISO(nextSaturday), "2026-10-31")

        let profile = makeTestProfile()

        let emptyContext = ScheduleEvaluationContext(
            runRecords: [],
            activeGoal: "Base Building",
            profile: profile,
            useMetric: true
        )

        let nextWeekSchedule = cal.evaluateSchedule(
            from: nextSunday,
            to: nextSaturday,
            context: emptyContext
        )

        XCTAssertEqual(nextWeekSchedule.count, 7, "Next week must cover all 7 days from Sunday to Saturday")
        let weekdays = nextWeekSchedule.map { $0.weekday }
        XCTAssertEqual(weekdays, ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"])

        // All days past tomorrow must be marked provisional
        for day in nextWeekSchedule {
            XCTAssertTrue(day.planned.provisional, "Day \(day.weekday) must be provisional")
            XCTAssertTrue(day.completion == ScheduleDay.CompletionStatus.upcoming || day.completion == ScheduleDay.CompletionStatus.completed)
            XCTAssertEqual(day.relative, ScheduleDay.RelativeDay.future)
        }
    }

    // MARK: - 8. Acceptance Criterion 9: Goal Update Action

    func testExecuteCoachAction_UpdateGoal_PersistsEnumDirectly() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let actionQuery = ExecuteCoachActionQuery(action: .updateGoal, goal: .marathon)
            XCTAssertEqual(actionQuery.action, .updateGoal)
            XCTAssertEqual(actionQuery.goal, .marathon)
            XCTAssertEqual(actionQuery.goal?.rawValue, "Marathon")

            let halfMarathonQuery = ExecuteCoachActionQuery(action: .updateGoal, goal: .halfMarathon)
            XCTAssertEqual(halfMarathonQuery.goal?.rawValue, "Half Marathon")
        }
        #endif
    }
}
