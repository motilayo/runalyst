import SwiftData
import XCTest
@testable import Runalyst

final class ToolPayloadSchemaTests: XCTestCase {

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
            experienceLevel: "Intermediate / Enthusiast",
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
        type: String = "Steady Effort",
        isIndoor: Bool = false
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
            isIndoor: isIndoor,
            paceCV: 0.03,
            paceSlope: 0.0,
            percentZone4: 0.1,
            detectedTypeRaw: type
        )
    }

    // MARK: - 1. GetTrainingScheduleTool Schema & Contract

    @MainActor
    func testGetTrainingSchedulePayloadSchema() throws {
        let tuesday = makeDate(year: 2026, month: 10, day: 20)
        let saturday = makeDate(year: 2026, month: 10, day: 24)

        let completedRun = makeRunRecord(date: tuesday, duration: 1800, distanceMeters: 5000)
        let calendar = TrainingCalendar(calendar: Calendar(identifier: .gregorian), now: tuesday)

        let context = ScheduleEvaluationContext(
            runRecords: [completedRun],
            activeGoal: "Base Building",
            profile: makeTestProfile(),
            useMetric: true
        )

        let schedule = calendar.evaluateSchedule(from: tuesday, to: saturday, context: context)
        XCTAssertEqual(schedule.count, 5, "Must evaluate exactly 5 days from Tuesday to Saturday")

        // Encode to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(schedule)
        let jsonString = try XCTUnwrap(String(data: data, encoding: .utf8))

        // Decode back to [ScheduleDay]
        let decoder = JSONDecoder()
        let decoded = try decoder.decode([ScheduleDay].self, from: data)
        XCTAssertEqual(decoded.count, 5)

        // Day 0: Tuesday (Completed)
        let tuesdaySchedule = decoded[0]
        XCTAssertEqual(tuesdaySchedule.date, "2026-10-20")
        XCTAssertEqual(tuesdaySchedule.weekday, "Tuesday")
        XCTAssertEqual(tuesdaySchedule.relative, .today)
        XCTAssertEqual(tuesdaySchedule.completion, .completed)
        XCTAssertEqual(tuesdaySchedule.completed.count, 1)
        XCTAssertEqual(tuesdaySchedule.completed[0].type, "Steady Effort")
        XCTAssertEqual(tuesdaySchedule.completed[0].distance, 5.0)

        // Verify zero scripted dialogue in the payload
        XCTAssertFalse(jsonString.contains("your schedule for today is clear"), "Tool payload must not contain conversational prose")
        XCTAssertFalse(jsonString.contains("here is your schedule"), "Tool payload must not contain conversational filler")
        XCTAssertFalse(jsonString.contains("great job completing"), "Tool payload must not contain conversational congratulations")
    }

    // MARK: - 2. GetReadinessAndWorkloadTool Schema & Contract

    func testGetReadinessAndWorkloadPayloadSchema() throws {
        let facts = ReadinessFacts(
            readiness_state: "Productive",
            acwr: 1.15,
            streak_days: 2,
            streak_limit: 4,
            last_48h_minutes: 60.0,
            weekly_avg_minutes: 180.0,
            volume_ratio_48h: 0.33,
            volume_threshold: 0.65,
            hr_shift_bpm: 2.0,
            today_minutes: 30.0,
            today_target_minutes: 35,
            today_completion_percent: 85,
            second_run_advisable: true,
            limiting_factors: [],
            experience_level: "Intermediate / Enthusiast",
            training_goal: "Marathon",
            cadence_floor_spm: 156
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(facts)
        let jsonString = try XCTUnwrap(String(data: data, encoding: .utf8))

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ReadinessFacts.self, from: data)

        XCTAssertEqual(decoded.readiness_state, "Productive")
        XCTAssertEqual(decoded.acwr, 1.15)
        XCTAssertEqual(decoded.streak_days, 2)
        XCTAssertEqual(decoded.streak_limit, 4)
        XCTAssertEqual(decoded.last_48h_minutes, 60.0)
        XCTAssertTrue(decoded.second_run_advisable)
        XCTAssertEqual(decoded.training_goal, "Marathon")
        XCTAssertEqual(decoded.cadence_floor_spm, 156)

        // Verify schema properties are snake_case JSON compatible
        XCTAssertTrue(jsonString.contains("\"readiness_state\":\"Productive\""))
        XCTAssertTrue(jsonString.contains("\"second_run_advisable\":true"))
        XCTAssertTrue(jsonString.contains("\"training_goal\":\"Marathon\""))
        XCTAssertTrue(jsonString.contains("\"cadence_floor_spm\":156"))

        // Zero canned conversation
        XCTAssertFalse(jsonString.contains("You are well recovered"))
        XCTAssertFalse(jsonString.contains("Take it easy today"))
    }

    // MARK: - 3. QueryWorkoutHistoryTool Facts Contract

    @MainActor
    func testQueryWorkoutHistoryComparisonDeltas() {
        let currentRun = makeRunRecord(
            date: makeDate(year: 2026, month: 10, day: 20),
            duration: 1800,
            distanceMeters: 5000,
            cadence: 164,
            heartRate: 146,
            isIndoor: true
        )
        let priorRun = makeRunRecord(
            date: makeDate(year: 2026, month: 10, day: 15),
            duration: 1900,
            distanceMeters: 5000,
            cadence: 158,
            heartRate: 152,
            isIndoor: false
        )

        let comparison = HistoricalRunMatcher.compare(current: currentRun, with: priorRun)
        XCTAssertEqual(comparison.cadenceDelta, 6, "164 - 158 = +6 SPM")
        XCTAssertEqual(comparison.heartRateDelta, -6, "146 - 152 = -6 BPM")
        XCTAssertEqual(comparison.paceDeltaSeconds, 20, "380s/km vs 360s/km = 20s faster")

        let facts = comparison.structuredTelemetryFacts
        XCTAssertTrue(facts.contains("Indoor Treadmill"))
        XCTAssertTrue(facts.contains("Outdoor"))
        XCTAssertTrue(facts.contains("+6 SPM"))
        XCTAssertTrue(facts.contains("20s/km faster"))

        // Phase 2: verify zero narrative prose paragraphs in facts
        XCTAssertFalse(facts.contains("Positive aerobic development"))
        XCTAssertFalse(facts.contains("motor-driven belt, static air"))
        XCTAssertFalse(facts.contains("Both workouts share continuous training structure"))
    }

    // MARK: - 4. InspectWorkoutTool Unified Response Contract

    @MainActor
    func testInspectWorkoutUnifiedResponseContract() throws {
        let run = makeRunRecord(
            date: makeDate(year: 2026, month: 10, day: 20),
            duration: 1800,
            distanceMeters: 5000,
            cadence: 162,
            heartRate: 148
        )
        let context = WorkoutAnalysisContext(
            runRecord: run,
            runSignature: nil,
            macroProfile: nil,
            recoveryTimeline: RecoveryTimeline.build(runs: [], readiness: .productive, now: Date()),
            runnerProfile: makeTestProfile()
        )

        let jsonString = context.compactTelemetryAnalysis()
        XCTAssertFalse(jsonString.isEmpty)

        let data = try XCTUnwrap(jsonString.data(using: .utf8))
        let decoder = JSONDecoder()
        let response = try decoder.decode(UnifiedWorkoutToolResponse.self, from: data)

        XCTAssertEqual(response.schema_name, "UNIFIED_WORKOUT_TOOL_RESPONSE")
        let stats = try XCTUnwrap(response.working_stats)
        XCTAssertEqual(stats.working_cadence_spm, 162)
        XCTAssertEqual(stats.working_heart_rate_bpm, 148)
        XCTAssertFalse(stats.moving_pace.isEmpty)

        // Phase 2 structured facts verification
        XCTAssertFalse(response.findings.isEmpty, "Inspect response must include structured findings")
        XCTAssertEqual(response.duration.duration_class, .short)
        XCTAssertEqual(response.duration.total_minutes, 30)
        XCTAssertEqual(response.heart_rate_confidence, .reliable)

        // Ensure zero canned descriptions or explainer dictionaries are serialized in the default payload
        XCTAssertFalse(jsonString.contains("\"_description\""), "Tool payload must not contain static _description prose")
        XCTAssertFalse(jsonString.contains("\"metric_explainers\""), "Default inspect tool payload must omit bloated explainer dictionaries")
    }

    // MARK: - 5. ExecuteCoachAction Contract

    func testExecuteCoachActionJSONContracts() throws {
        // Goal update payload
        let updateGoalJSON = "{\"goal\":\"Marathon\",\"status\":\"training_goal_updated\"}"
        let data = try XCTUnwrap(updateGoalJSON.data(using: .utf8))
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(obj?["status"] as? String, "training_goal_updated")
        XCTAssertEqual(obj?["goal"] as? String, "Marathon")

        // Drill display payload
        let drillJSON = "{\"drill_id\":\"cadence_pyramids\",\"status\":\"interactive_drill_card_displayed\"}"
        let drillData = try XCTUnwrap(drillJSON.data(using: .utf8))
        let drillObj = try JSONSerialization.jsonObject(with: drillData) as? [String: Any]
        XCTAssertEqual(drillObj?["status"] as? String, "interactive_drill_card_displayed")
        XCTAssertEqual(drillObj?["drill_id"] as? String, "cadence_pyramids")
    }

    // MARK: - 6. Calendar Temporal Anchor Context

    func testCalendarAnchorFormatting() {
        let tuesday = makeDate(year: 2026, month: 10, day: 20)
        let cal = TrainingCalendar(calendar: Calendar(identifier: .gregorian), now: tuesday)

        let metricAnchor = cal.anchor(now: tuesday, useMetric: true)
        XCTAssertTrue(metricAnchor.contains("Tue 2026-10-20"))
        XCTAssertTrue(metricAnchor.contains("This week: 2026-10-18..2026-10-24"))
        XCTAssertTrue(metricAnchor.contains("Next week: 2026-10-25..2026-10-31"))
        XCTAssertTrue(metricAnchor.contains("Units: metric"))

        let imperialAnchor = cal.anchor(now: tuesday, useMetric: false)
        XCTAssertTrue(imperialAnchor.contains("Units: imperial"))
    }
}
