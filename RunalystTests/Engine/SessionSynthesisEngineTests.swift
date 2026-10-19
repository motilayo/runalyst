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
        let calendar = Calendar.current
        let now = calendar.date(bySettingHour: 15, minute: 0, second: 0, of: Date()) ?? Date()
        let runDate = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: now) ?? now.addingTimeInterval(-3600)

        // Runner already ran today (e.g. an indoor Fartlek)
        let todaysFartlek = makeRun(
            date: runDate, // 1 hour ago today
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

            // 3. Verify microcycle consecutive days (never skips the day after Tomorrow)
            let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            XCTAssertEqual(tomorrowSession.microcycle.count, 5)
            XCTAssertEqual(tomorrowSession.microcycle[0].dayLabel, "Tomorrow")
            if let twoDaysAhead = calendar.date(byAdding: .day, value: 2, to: now) {
                let expectedSecondLabel = dayNames[calendar.component(.weekday, from: twoDaysAhead) - 1]
                XCTAssertEqual(tomorrowSession.microcycle[1].dayLabel, expectedSecondLabel)
            }
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

    @MainActor
    func testMicrocycleHorizon_BaseBuildingGoal_SynthesizesAerobicConsistencySchedule() {
        let now = Date()
        let microcycle = SessionSynthesisEngine.generateMicrocycle(
            activeGoal: "Base Building",
            now: now,
            useMetric: true,
            isRecoveryWindow: false
        )

        XCTAssertEqual(microcycle.count, 5)
        // Verify Base Building contains Aerobic volume, not Marathon Pace Progress
        XCTAssertTrue(microcycle.contains(where: { $0.sessionTitle.contains("Aerobic Consistency") }))
        XCTAssertTrue(microcycle.contains(where: { $0.sessionTitle.contains("Easy Aerobic Base") }))
        XCTAssertFalse(microcycle.contains(where: { $0.sessionTitle.contains("Marathon Pace Progress") }))
        XCTAssertFalse(microcycle.contains(where: { $0.sessionTitle.contains("16 km") }))
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

    @MainActor
    func testPrimerCompletedToday_KeepsMainRunAvailableInPreRunState_ThenShowsBothWhenMainRunCompleted() throws {
        let calendar = Calendar.current
        let now = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: Date()) ?? Date()
        let primerDate = calendar.date(bySettingHour: 7, minute: 55, second: 0, of: now) ?? now.addingTimeInterval(-7200)
        let mainRunDate = calendar.date(bySettingHour: 8, minute: 12, second: 0, of: now) ?? now.addingTimeInterval(-5400)

        let primerRun = makeRun(
            date: primerDate,
            duration: 900.0, // 15:00
            distanceMeters: 1460.0,
            workingAvgCadence: 155.0,
            workingAvgHeartRate: 138.0,
            detectedTypeRaw: "Intervals",
            framboiseTags: ["prescribedDrill", "cadence_pyramids", "drill:Cadence Pyramids"],
            isIndoor: true
        )

        // 1. Only primer completed today -> must remain in .preRun so user can start the Main Run!
        let stateAfterPrimer = SessionSynthesisEngine.evaluateDailyState(
            runRecords: [primerRun],
            activeGoal: "Base Building",
            experienceLevel: "Intermediate",
            useMetric: true,
            now: now
        )

        switch stateAfterPrimer {
        case .preRun(let session):
            XCTAssertNotNil(session.completedPrimerRun, "Completed primer must be attached to today's session")
            XCTAssertEqual(session.completedPrimerRun?.id, primerRun.id)
            XCTAssertTrue(session.completedPrimerRun?.workoutType.contains("Cadence Pyramids") == true)
            XCTAssertEqual(session.completedPrimerRun?.distanceFormatted, "1.46 km")
            XCTAssertEqual(session.mainRunDrillId, .zone2Run)
        case .completedToday:
            XCTFail("Completing only the short Pre-Run Primer must NOT hide today's Main Run")
        }

        // 2. Now user also completes the 40-min Zone 2 Main Run today -> transitions to .completedToday with BOTH runs
        let mainRun = makeRun(
            date: mainRunDate,
            duration: 2401.0, // 40:01
            distanceMeters: 4480.0,
            workingAvgCadence: 153.0,
            workingAvgHeartRate: 138.0,
            detectedTypeRaw: "Easy Run",
            framboiseTags: ["prescribedDrill", "zone_2_run", "drill:Zone 2 Run"],
            isIndoor: true
        )

        let stateAfterMainRun = SessionSynthesisEngine.evaluateDailyState(
            runRecords: [mainRun, primerRun],
            activeGoal: "Base Building",
            experienceLevel: "Intermediate",
            useMetric: true,
            now: now
        )

        switch stateAfterMainRun {
        case .preRun:
            XCTFail("Expected .completedToday after both Primer and Main Run are completed")
        case .completedToday(let completedRun, _):
            let allRuns = completedRun.allCompletedRunsToday
            XCTAssertEqual(allRuns.count, 2, "Workouts page must reflect both the Cadence Pyramids drill and Zone 2 Run completed today")
            XCTAssertEqual(allRuns[0].id, primerRun.id)
            XCTAssertTrue(allRuns[0].workoutType.contains("Cadence Pyramids"))
            XCTAssertEqual(allRuns[0].distanceFormatted, "1.46 km")
            XCTAssertEqual(allRuns[1].id, mainRun.id)
            XCTAssertTrue(allRuns[1].workoutType.contains("Zone 2 Run"))
            XCTAssertEqual(allRuns[1].distanceFormatted, "4.48 km")
        }
    }

    @MainActor
    func testAdaptedPrimerTargetAndDuration_Preserves7m30sAnd155To161SPMAndIndoorFlag() {
        let dto = DrillPrescriptionDTO(
            title: "Cadence Pyramids",
            preRunDrillId: PreRunDrillId.cadencePyramids.rawValue,
            purpose: "Active recovery turnover",
            targetCadence: "155–161 SPM (Adapted)",
            previousCadence: 156,
            durationMinutes: 10,
            hapticMode: "On",
            readinessState: ReadinessState.acuteFatigue.rawValue,
            isIndoor: true
        )

        let item = ActiveDrillReadoutItem.adaptive(dto: dto, readiness: .productive)
        XCTAssertEqual(item.readout.totalDurationSeconds, 450, "Trimmed 10-min Cadence Pyramids must be 7m 30s (450s), never 15m")
        XCTAssertEqual(item.readout.formattedDuration, "7m 30s")
        XCTAssertEqual(item.dto.targetCadence, "155-161")
        XCTAssertEqual(item.dto.isIndoor, true)

        let drill = PreRunDrill(
            id: .cadencePyramids,
            previousCadence: 156,
            targetCadence: "155–161 SPM (Adapted)",
            duration: .tenMinutes,
            readinessState: .acuteFatigue,
            isIndoor: true
        )
        XCTAssertEqual(drill.effectiveTargetCadence, 155...161)
        XCTAssertEqual(drill.totalPhasesDurationSeconds, 450)
        XCTAssertEqual(drill.coolDownDurationMinutes, 3.0)
    }
}
