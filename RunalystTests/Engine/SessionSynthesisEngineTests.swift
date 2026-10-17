import XCTest
import SwiftData
@testable import Runalyst

final class SessionSynthesisEngineTests: XCTestCase {

    private func makeRun(
        id: UUID = UUID(),
        date: Date,
        duration: Double = 1800.0,
        distanceMeters: Double = 5000.0,
        workingAvgCadence: Double = 160.0,
        workingAvgHeartRate: Double = 145.0,
        detectedTypeRaw: String = "Steady Effort",
        framboiseTags: [String] = [],
        isIndoor: Bool = false
    ) -> RunRecord {
        RunRecord(
            id: id,
            hkWorkoutID: UUID(),
            date: date,
            totalDistanceMeters: distanceMeters,
            duration: duration,
            rawAvgPace: 360.0,
            rawAvgHeartRate: workingAvgHeartRate,
            rawAvgCadence: workingAvgCadence,
            workingAvgPace: 360.0,
            workingAvgCadence: workingAvgCadence,
            workingAvgHeartRate: workingAvgHeartRate,
            workingAvgVerticalOscillation: 8.5,
            rawAvgVerticalOscillation: 8.5,
            rawAvgStrideLength: 1.05,
            workingAvgStrideLength: 1.05,
            workingDistanceMeters: distanceMeters,
            workingDurationSeconds: duration,
            isIndoor: isIndoor,
            paceCV: 0.05,
            paceSlope: 0.0,
            percentZone4: 0.1,
            detectedTypeRaw: detectedTypeRaw,
            framboiseTags: framboiseTags,
            dataSourceRaw: "wrist"
        )
    }

    // MARK: - 1. Pre-Run State Tests

    @MainActor
    func testPreRunState_WithNoRunToday_SynthesizesGoalPrescriptionAndLinkedDrill() {
        let calendar = Calendar.current
        let now = Date()
        guard let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: now) else {
            XCTFail("Failed to construct date")
            return
        }

        let run = makeRun(date: twoDaysAgo, workingAvgCadence: 158.0, workingAvgHeartRate: 140.0)
        let state = SessionSynthesisEngine.evaluateDailyState(
            runRecords: [run],
            activeGoal: "5K",
            experienceLevel: "Intermediate",
            useMetric: true,
            now: now
        )

        switch state {
        case .preRun(let session):
            XCTAssertEqual(session.targetGoal, "5K")
            XCTAssertFalse(session.sessionTitle.isEmpty)
            XCTAssertFalse(session.durationBand.isEmpty)
            XCTAssertFalse(session.paceBand.isEmpty)
            XCTAssertTrue(session.hrCap.contains("BPM"))
            XCTAssertGreaterThanOrEqual(session.cadenceFloor, 140)
            XCTAssertFalse(session.groundedRationale.isEmpty)
            XCTAssertFalse(session.primerDrillTitle.isEmpty)
            XCTAssertFalse(session.primerTargetCadence.isEmpty)
            XCTAssertEqual(session.microcycle.count, 5)
            XCTAssertEqual(session.microcycle[0].dayLabel, "Tomorrow")
            XCTAssertFalse(session.microcycle[1].dayLabel.isEmpty)
        case .completedToday:
            XCTFail("Expected .preRun state when no run has been logged today")
        }
    }

    // MARK: - 2. Cardiac Drift & Fatigue Adaptation Tests

    @MainActor
    func testPreRunState_WithPostCardiacDriftFatigue_DowngradesPrescriptionAndTrimsDrill() {
        let calendar = Calendar.current
        let now = Date()
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else {
            XCTFail("Failed to construct date")
            return
        }

        // Run from yesterday with cardiac drift tag
        let yesterdayFartlek = makeRun(
            date: yesterday,
            duration: 2700.0,
            distanceMeters: 7500.0,
            workingAvgCadence: 156.0,
            workingAvgHeartRate: 162.0,
            detectedTypeRaw: "Fartlek",
            framboiseTags: ["cardiacDrift", "fatigueDrift"]
        )

        let state = SessionSynthesisEngine.evaluateDailyState(
            runRecords: [yesterdayFartlek],
            activeGoal: "5K",
            experienceLevel: "Intermediate",
            useMetric: true,
            now: now
        )

        switch state {
        case .preRun(let session):
            XCTAssertTrue(session.isTrimmed, "Drill should be trimmed to protect fatigued legs after cardiac drift")
            XCTAssertEqual(session.primerPhasesDuration, "7m 30s drill (Trimmed from 10 min)", "Trimmed drill must display 7m 30s (Trimmed from 10 min)")
            XCTAssertTrue(
                session.sessionTitle.contains("Recovery") || session.sessionTitle.contains("Base") || session.sessionTitle.contains("Aerobic"),
                "Prescription must downgrade to active recovery or easy base"
            )
            XCTAssertTrue(session.hrCap.contains("< 145 BPM") || session.hrCap.contains("< 152 BPM") || session.hrCap.contains("< 135 BPM"))
            XCTAssertTrue(
                session.groundedRationale.localizedCaseInsensitiveContains("drift") || session.groundedRationale.localizedCaseInsensitiveContains("fatigue"),
                "Rationale should cite cardiac drift or fatigue: \(session.groundedRationale)"
            )
        case .completedToday:
            XCTFail("Expected .preRun state for yesterday's workout")
        }
    }

    // MARK: - 3. Post-Run State (Completed Today) Tests

    @MainActor
    func testCompletedTodayState_WhenRunLoggedToday_PromotesAndAdaptsTomorrow() {
        let now = Date()

        // Runner already ran today (e.g. an indoor Fartlek)
        let todaysFartlek = makeRun(
            date: now.addingTimeInterval(-3600), // 1 hour ago today
            duration: 2475.0, // 41:15
            distanceMeters: 6200.0,
            workingAvgCadence: 164.0,
            workingAvgHeartRate: 158.0,
            detectedTypeRaw: "Fartlek",
            framboiseTags: ["indoor"],
            isIndoor: true
        )

        let state = SessionSynthesisEngine.evaluateDailyState(
            runRecords: [todaysFartlek],
            activeGoal: "5K",
            experienceLevel: "Intermediate",
            useMetric: true,
            now: now
        )

        switch state {
        case .preRun:
            XCTFail("Expected .completedToday state when a run was recorded today")
        case .completedToday(let completedRun, let tomorrowSession):
            // 1. Verify today's completed session banner
            XCTAssertEqual(completedRun.id, todaysFartlek.id)
            XCTAssertTrue(completedRun.workoutType.contains("Fartlek"))
            XCTAssertFalse(completedRun.durationFormatted.isEmpty)
            XCTAssertFalse(completedRun.distanceFormatted.isEmpty)
            XCTAssertFalse(completedRun.letterGrade.isEmpty)

            // 2. Verify tomorrow's session promotes and adapts
            XCTAssertTrue(
                tomorrowSession.sessionTitle.contains("Recovery") || tomorrowSession.sessionTitle.contains("Flush"),
                "Tomorrow should be downgraded to an active recovery flush after today's fartlek"
            )
            XCTAssertTrue(tomorrowSession.isTrimmed, "Tomorrow's drill must be trimmed to protect legs")
            XCTAssertEqual(tomorrowSession.primerPhasesDuration, "7m 30s drill (Trimmed from 10 min)")
            XCTAssertTrue(tomorrowSession.hrCap.contains("< 135 BPM") || tomorrowSession.hrCap.contains("< 145 BPM"))
        }
    }

    // MARK: - 4. Microcycle Horizon Tests

    @MainActor
    func testMicrocycleHorizon_GeneratesThreeDayLookahead() {
        let now = Date()
        let microcycle = SessionSynthesisEngine.generateMicrocycle(
            activeGoal: "5K",
            now: now,
            useMetric: true,
            isRecoveryWindow: false
        )

        XCTAssertEqual(microcycle.count, 5)
        XCTAssertEqual(microcycle[0].dayLabel, "Tomorrow")
        XCTAssertFalse(microcycle[1].dayLabel.isEmpty)

        for day in microcycle {
            XCTAssertFalse(day.id.isEmpty)
            XCTAssertFalse(day.sessionTitle.isEmpty)
            XCTAssertFalse(day.iconName.isEmpty)
        }

        // Verify 5K metric calibration: long run is 7 km, never 13 mi!
        XCTAssertTrue(microcycle.contains(where: { $0.sessionTitle.contains("7 km") }))
        XCTAssertFalse(microcycle.contains(where: { $0.sessionTitle.contains("13 mi") }))
        XCTAssertFalse(microcycle.contains(where: { $0.sessionTitle.contains("6 mi") }))
    }

    @MainActor
    func testMicrocycleHorizon_UnderRecoveryWindow_ShiftsTomorrowToRecoveryFlush() {
        let now = Date()
        let microcycle = SessionSynthesisEngine.generateMicrocycle(
            activeGoal: "5K",
            now: now,
            useMetric: true,
            isRecoveryWindow: true
        )

        XCTAssertEqual(microcycle[0].dayLabel, "Tomorrow")
        XCTAssertTrue(microcycle[0].sessionTitle.contains("Recovery Flush"))
        XCTAssertFalse(microcycle[0].sessionTitle.contains("Threshold"))
    }

    @MainActor
    func testMicrocycleHorizon_ImperialUnits_FormatsMilesProperly() {
        let now = Date()
        let microcycle = SessionSynthesisEngine.generateMicrocycle(
            activeGoal: "5K",
            now: now,
            useMetric: false,
            isRecoveryWindow: false
        )

        XCTAssertTrue(microcycle.contains(where: { $0.sessionTitle.contains("3 mi") }))
        XCTAssertTrue(microcycle.contains(where: { $0.sessionTitle.contains("4.5 mi") }))
    }

    // MARK: - 5. Relative Workout Referencing Tests

    @MainActor
    func testRelativeWorkoutReference_WhenRunWasThursdayAndTodayIsSaturday_ReturnsThursdaysFartlek() throws {
        let calendar = Calendar.current
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 10
        comps.day = 17 // Saturday Oct 17, 2026
        comps.hour = 16
        comps.minute = 12
        let saturday = try XCTUnwrap(calendar.date(from: comps))

        comps.day = 15 // Thursday Oct 15, 2026
        comps.hour = 8
        comps.minute = 30
        let thursday = try XCTUnwrap(calendar.date(from: comps))

        let ref = SessionSynthesisEngine.relativeWorkoutReference(for: thursday, relativeTo: saturday, workoutType: "Fartlek")
        XCTAssertEqual(ref, "Thursday's Fartlek", "Run on Thursday Oct 15 viewed on Saturday Oct 17 must reference Thursday's Fartlek, never Yesterday's")

        // Also test rationale synthesis
        let thursdayRun = makeRun(
            date: thursday,
            duration: 2400.0,
            distanceMeters: 6500.0,
            workingAvgCadence: 156.0,
            workingAvgHeartRate: 165.0,
            detectedTypeRaw: "Fartlek",
            framboiseTags: ["cardiacDrift"]
        )

        let state = SessionSynthesisEngine.evaluateDailyState(
            runRecords: [thursdayRun],
            activeGoal: "Base Building",
            experienceLevel: "Intermediate",
            useMetric: true,
            now: saturday
        )

        switch state {
        case .preRun(let session):
            XCTAssertTrue(session.groundedRationale.contains("Thursday's Fartlek"), "Rationale must cite Thursday's Fartlek: \(session.groundedRationale)")
            XCTAssertFalse(session.groundedRationale.contains("Yesterday's"), "Rationale must NOT cite Yesterday when run was on Thursday: \(session.groundedRationale)")
            XCTAssertTrue(session.groundedRationale.contains("aerobic foundation"), "Base Building goal must cite aerobic foundation: \(session.groundedRationale)")
        case .completedToday:
            XCTFail("Expected .preRun state")
        }
    }
}
