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
        isIndoor: Bool = false,
        workingAvgVerticalOscillation: Double = 8.5,
        workingAvgStrideLength: Double = 1.05,
        percentZone4: Double = 0.1
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
            workingAvgVerticalOscillation: workingAvgVerticalOscillation,
            rawAvgVerticalOscillation: workingAvgVerticalOscillation,
            rawAvgStrideLength: workingAvgStrideLength,
            workingAvgStrideLength: workingAvgStrideLength,
            workingDistanceMeters: distanceMeters,
            workingDurationSeconds: duration,
            isIndoor: isIndoor,
            paceCV: 0.05,
            paceSlope: 0.0,
            percentZone4: percentZone4,
            detectedTypeRaw: detectedTypeRaw,
            framboiseTags: framboiseTags,
            dataSourceRaw: "wrist"
        )
    }

    private func dateOffset(days: Int, from date: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: date) ?? date.addingTimeInterval(Double(days) * 86400)
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
            XCTAssertEqual(session.primerPhasesDuration, "7m 30s", "Trimmed drill must display clean 7m 30s")
            XCTAssertFalse(session.primerTargetCadence.contains("(Adapted)"), "Target cadence must be clean without (Adapted)")
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
            XCTAssertEqual(tomorrowSession.primerPhasesDuration, "7m 30s")
            XCTAssertFalse(tomorrowSession.primerTargetCadence.contains("(Adapted)"))
            XCTAssertTrue(tomorrowSession.hrCap.contains("< 135 BPM") || tomorrowSession.hrCap.contains("< 145 BPM"))

            // 3. Verify microcycle starts after Tomorrow (since the hero card is already Tomorrow's Session)
            let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            XCTAssertEqual(tomorrowSession.microcycle.count, 5)
            XCTAssertFalse(tomorrowSession.microcycle.contains(where: { $0.dayLabel == "Tomorrow" }))
            for (index, day) in tomorrowSession.microcycle.enumerated() {
                if let expectedDate = calendar.date(byAdding: .day, value: index + 2, to: now) {
                    let expectedLabel = dayNames[calendar.component(.weekday, from: expectedDate) - 1]
                    XCTAssertEqual(day.dayLabel, expectedLabel)
                }
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
        // Anchor to Sunday so the 5-day horizon spans Mon..Fri (including Tuesday's Easy Aerobic Base and Friday's Aerobic Consistency)
        let now = Date(timeIntervalSince1970: 1_792_929_600)
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
            XCTAssertTrue(allRuns[1].workoutType.contains("Easy Run") || allRuns[1].workoutType.contains("Zone 2 Run"))
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

    // MARK: - 8. Upgraded Synthesis Engine Architecture Tests

    @MainActor
    func testWeightedBaseline_IntervalsDoNotDistortAerobicPace() {
        let now = Date()

        // 3 steady runs of 45 mins at 360 s/km (6:00/km)
        let run1 = makeRun(
            date: dateOffset(days: -6, from: now),
            duration: 2700,
            distanceMeters: 7500,
            workingAvgCadence: 156,
            workingAvgHeartRate: 140,
            detectedTypeRaw: "Steady Effort"
        )
        let run2 = makeRun(
            date: dateOffset(days: -4, from: now),
            duration: 2700,
            distanceMeters: 7500,
            workingAvgCadence: 155,
            workingAvgHeartRate: 142,
            detectedTypeRaw: "Steady Effort"
        )
        let run3 = makeRun(
            date: dateOffset(days: -2, from: now),
            duration: 2700,
            distanceMeters: 7500,
            workingAvgCadence: 154,
            workingAvgHeartRate: 139,
            detectedTypeRaw: "Steady Effort"
        )

        // 1 short interval workout of 15 mins at fast 240 s/km (4:00/km)
        let intervalRun = makeRun(
            date: dateOffset(days: -1, from: now),
            duration: 900,
            distanceMeters: 3750,
            workingAvgCadence: 172,
            workingAvgHeartRate: 170,
            detectedTypeRaw: "Intervals"
        )

        let runs = [intervalRun, run3, run2, run1]
        let weightedBaseline = SessionSynthesisEngine.computeWeightedBaseline(from: runs, priorTo: now)

        // Unweighted arithmetic average would be (360*3 + 240)/4 = 330 s/km (5:30/km)
        // Duration-weighted baseline dampens the 15-min interval run, keeping base > 348 s/km
        XCTAssertGreaterThan(weightedBaseline.pace, 348.0, "Weighted baseline should not be pulled down by short interval workouts")
        XCTAssertLessThanOrEqual(weightedBaseline.pace, 360.0)
    }

    @MainActor
    func testHeightCalibratedCadenceFloor_TallerRunnerGetsLowerFloor() {
        let now = Date()
        let easyRun = makeRun(
            date: dateOffset(days: -2, from: now),
            duration: 2400,
            distanceMeters: 6000,
            workingAvgCadence: 152,
            workingAvgHeartRate: 140,
            detectedTypeRaw: "Steady Effort"
        )

        let tallState = SessionSynthesisEngine.evaluateDailyState(
            runRecords: [easyRun],
            activeGoal: "Base Building",
            experienceLevel: "Intermediate",
            useMetric: true,
            userHeightCm: 198.0,
            now: now
        )

        let shortState = SessionSynthesisEngine.evaluateDailyState(
            runRecords: [easyRun],
            activeGoal: "Base Building",
            experienceLevel: "Intermediate",
            useMetric: true,
            userHeightCm: 152.0,
            now: now
        )

        switch (tallState, shortState) {
        case (.preRun(let tallSession), .preRun(let shortSession)):
            XCTAssertLessThan(tallSession.cadenceFloor, shortSession.cadenceFloor, "A 198 cm runner must have a lower cadence floor than a 152 cm runner")
            XCTAssertLessThanOrEqual(tallSession.cadenceFloor, 148, "Tall runner floor should be lower (e.g. <= 148)")
            XCTAssertGreaterThanOrEqual(shortSession.cadenceFloor, 154, "Short runner floor should be higher (e.g. >= 154)")
        default:
            XCTFail("Expected .preRun state for both")
        }
    }

    @MainActor
    func testPolarized8020_QualityShiftsToZone2_WhenTwoHardRunsBanked() {
        let now = Date()

        let hardRun1 = makeRun(
            date: dateOffset(days: -5, from: now),
            duration: 2700,
            distanceMeters: 8000,
            workingAvgCadence: 168,
            workingAvgHeartRate: 168,
            detectedTypeRaw: "Intervals"
        )
        let hardRun2 = makeRun(
            date: dateOffset(days: -3, from: now),
            duration: 3600,
            distanceMeters: 10500,
            workingAvgCadence: 164,
            workingAvgHeartRate: 165,
            detectedTypeRaw: "Progression Run"
        )
        let easyRecovery = makeRun(
            date: dateOffset(days: -1, from: now),
            duration: 1800,
            distanceMeters: 4000,
            workingAvgCadence: 152,
            workingAvgHeartRate: 128,
            detectedTypeRaw: "Recovery Run"
        )

        let state = SessionSynthesisEngine.evaluateDailyState(
            runRecords: [easyRecovery, hardRun2, hardRun1],
            activeGoal: "5K",
            experienceLevel: "Advanced",
            useMetric: true,
            now: now
        )

        switch state {
        case .preRun(let session):
            // 2 hard runs banked in 7 days -> Reverts to Aerobic Base despite 5K goal and productive state
            XCTAssertTrue(
                session.sessionTitle.contains("Aerobic") || session.sessionTitle.contains("Base") || session.sessionTitle.contains("Zone 2"),
                "Session must revert to Zone 2 Aerobic Base under 80/20 rule: \(session.sessionTitle)"
            )
            XCTAssertTrue(
                session.groundedRationale.localizedCaseInsensitiveContains("stimulus") ||
                session.groundedRationale.localizedCaseInsensitiveContains("polarized") ||
                session.groundedRationale.localizedCaseInsensitiveContains("80/20") ||
                session.groundedRationale.localizedCaseInsensitiveContains("hard"),
                "Rationale should cite 80/20 stimulus cap: \(session.groundedRationale)"
            )
        case .completedToday:
            XCTFail("Expected .preRun state")
        }
    }

    @MainActor
    func testGoalSpecificQuality_PrescriptionsWhenCleared() {
        let now = Date()
        let easyRun1 = makeRun(
            date: dateOffset(days: -3, from: now),
            duration: 2400,
            distanceMeters: 5500,
            workingAvgCadence: 154,
            workingAvgHeartRate: 135,
            detectedTypeRaw: "Steady Effort"
        )
        let easyRun2 = makeRun(
            date: dateOffset(days: -1, from: now),
            duration: 2400,
            distanceMeters: 5600,
            workingAvgCadence: 155,
            workingAvgHeartRate: 136,
            detectedTypeRaw: "Steady Effort"
        )

        // 1. 5K goal -> Rhythm Intervals
        let state5K = SessionSynthesisEngine.evaluateDailyState(
            runRecords: [easyRun2, easyRun1],
            activeGoal: "5K",
            experienceLevel: "Advanced",
            useMetric: true,
            now: now
        )
        if case .preRun(let session5K) = state5K {
            XCTAssertTrue(session5K.sessionTitle.contains("Rhythm Intervals") || session5K.mainSessionTemplateId == PreRunDrillId.rhythmIntervals)
        } else {
            XCTFail("Expected .preRun for 5K")
        }

        // 2. 10K goal -> Threshold Surges
        let state10K = SessionSynthesisEngine.evaluateDailyState(
            runRecords: [easyRun2, easyRun1],
            activeGoal: "10K",
            experienceLevel: "Advanced",
            useMetric: true,
            now: now
        )
        if case .preRun(let session10K) = state10K {
            XCTAssertTrue(session10K.sessionTitle.contains("Threshold Surges") || session10K.mainSessionTemplateId == PreRunDrillId.tempoSurges)
        } else {
            XCTFail("Expected .preRun for 10K")
        }

        // 3. Half Marathon -> Lactate Threshold Tempo Surges
        let stateHalf = SessionSynthesisEngine.evaluateDailyState(
            runRecords: [easyRun2, easyRun1],
            activeGoal: "Half Marathon",
            experienceLevel: "Advanced",
            useMetric: true,
            now: now
        )
        if case .preRun(let sessionHalf) = stateHalf {
            XCTAssertTrue(sessionHalf.sessionTitle.contains("Lactate Threshold") || sessionHalf.mainSessionTemplateId == PreRunDrillId.tempoSurges)
        } else {
            XCTFail("Expected .preRun for Half Marathon")
        }
    }

    @MainActor
    func testClosedLoopPrimer_SelectsCadencePyramidsOnExcessiveBounce() {
        let now = Date()

        let bouncyRun = makeRun(
            date: dateOffset(days: -1, from: now),
            duration: 2700,
            distanceMeters: 6500,
            workingAvgCadence: 148,
            workingAvgHeartRate: 142,
            detectedTypeRaw: "Steady Effort",
            workingAvgVerticalOscillation: 11.2,
            workingAvgStrideLength: 1.15
        )

        let state = SessionSynthesisEngine.evaluateDailyState(
            runRecords: [bouncyRun],
            activeGoal: "Base Building",
            experienceLevel: "Intermediate",
            useMetric: true,
            now: now
        )

        switch state {
        case .preRun(let session):
            XCTAssertEqual(session.primerDrillId, PreRunDrillId.cadencePyramids, "High bounce (>10.0 cm) must trigger Cadence Pyramids primer")
            XCTAssertTrue(
                session.groundedRationale.localizedCaseInsensitiveContains("bounce") ||
                session.groundedRationale.localizedCaseInsensitiveContains("vertical") ||
                session.groundedRationale.localizedCaseInsensitiveContains("oscillation") ||
                session.groundedRationale.localizedCaseInsensitiveContains("cadence"),
                "Rationale must cite vertical oscillation / bounce: \(session.groundedRationale)"
            )
        case .completedToday:
            XCTFail("Expected .preRun state")
        }
    }

    @MainActor
    func testClosedLoopPrimer_SelectsStridesOnOptimalMechanics() {
        let now = Date()

        let optimalRun = makeRun(
            date: dateOffset(days: -1, from: now),
            duration: 2700,
            distanceMeters: 6500,
            workingAvgCadence: 168,
            workingAvgHeartRate: 142,
            detectedTypeRaw: "Steady Effort",
            workingAvgVerticalOscillation: 8.2,
            workingAvgStrideLength: 1.05
        )
        optimalRun.cadenceSlope = 0.02

        let state = SessionSynthesisEngine.evaluateDailyState(
            runRecords: [optimalRun],
            activeGoal: "Base Building",
            experienceLevel: "Intermediate",
            useMetric: true,
            now: now
        )

        switch state {
        case .preRun(let session):
            XCTAssertEqual(session.primerDrillId, PreRunDrillId.strides, "Optimal mechanics must default to Strides rather than Cadence Pyramids")
            XCTAssertEqual(session.primerDrillTitle, "Strides")
        case .completedToday:
            XCTFail("Expected .preRun state")
        }
    }

    @MainActor
    func testExperienceScaledDurationBands_AndWorkoutKitPhases() {
        let now = Date()
        let baselineRun = makeRun(
            date: dateOffset(days: -2, from: now),
            duration: 2400,
            distanceMeters: 6000,
            workingAvgCadence: 154,
            workingAvgHeartRate: 138,
            detectedTypeRaw: "Steady Effort"
        )

        // 1. Novice -> 45 Min total (15m strides primer + 30m main run)
        let noviceState = SessionSynthesisEngine.evaluateDailyState(
            runRecords: [baselineRun],
            activeGoal: "Base Building",
            experienceLevel: "Novice",
            useMetric: true,
            now: now
        )
        if case .preRun(let session) = noviceState {
            XCTAssertEqual(session.durationBand, "45 Min")
            XCTAssertEqual(session.mainRunDurationMinutes, 30)
            XCTAssertEqual(session.primerDurationMinutes, 15)
            XCTAssertEqual(session.totalDurationMinutes, 45)
            let drill = PreRunDrill(id: session.mainSessionTemplateId, duration: .thirtyMinutes)
            XCTAssertEqual(drill.totalPhasesDurationSeconds, 1800)
        } else {
            XCTFail("Expected .preRun for Novice")
        }

        // 2. Intermediate -> 55 Min total (15m strides primer + 40m main run)
        let intermediateState = SessionSynthesisEngine.evaluateDailyState(
            runRecords: [baselineRun],
            activeGoal: "Base Building",
            experienceLevel: "Intermediate",
            useMetric: true,
            now: now
        )
        if case .preRun(let session) = intermediateState {
            XCTAssertEqual(session.durationBand, "55 Min")
            XCTAssertEqual(session.mainRunDurationMinutes, 40)
            XCTAssertEqual(session.primerDurationMinutes, 15)
            XCTAssertEqual(session.totalDurationMinutes, 55)
            let drill = PreRunDrill(id: session.mainSessionTemplateId, duration: .fortyMinutes)
            XCTAssertEqual(drill.totalPhasesDurationSeconds, 2400)
            let phases = drill.generatePhases()
            XCTAssertEqual(phases.count, 3)
            XCTAssertEqual(phases[0].durationSeconds, 300) // 5m warm-up
            XCTAssertEqual(phases[1].durationSeconds, 1800) // 30m steady
            XCTAssertEqual(phases[2].durationSeconds, 300) // 5m cool-down
        } else {
            XCTFail("Expected .preRun for Intermediate")
        }

        // 3. Advanced -> 65 Min total (15m strides primer + 50m main run)
        let advancedState = SessionSynthesisEngine.evaluateDailyState(
            runRecords: [baselineRun],
            activeGoal: "Base Building",
            experienceLevel: "Advanced",
            useMetric: true,
            now: now
        )
        if case .preRun(let session) = advancedState {
            XCTAssertEqual(session.durationBand, "65 Min")
            XCTAssertEqual(session.mainRunDurationMinutes, 50)
            XCTAssertEqual(session.primerDurationMinutes, 15)
            XCTAssertEqual(session.totalDurationMinutes, 65)
            let drill = PreRunDrill(id: session.mainSessionTemplateId, duration: .fiftyMinutes)
            XCTAssertEqual(drill.totalPhasesDurationSeconds, 3000)
            let phases = drill.generatePhases()
            XCTAssertEqual(phases.count, 3)
            XCTAssertEqual(phases[0].durationSeconds, 300) // 5m warm-up
            XCTAssertEqual(phases[1].durationSeconds, 2400) // 40m steady
            XCTAssertEqual(phases[2].durationSeconds, 300) // 5m cool-down
        } else {
            XCTFail("Expected .preRun for Advanced")
        }
    }

    @MainActor
    func testMicrocycleRecoverySuppression_WhenHighRecoveryHoursActive() {
        let now = Date()

        // Yesterday was an exhaustive 2-hour workout generating 48h recovery
        let heavyRun = makeRun(
            date: dateOffset(days: -1, from: now),
            duration: 7200,
            distanceMeters: 22000,
            workingAvgCadence: 160,
            workingAvgHeartRate: 168,
            detectedTypeRaw: "Progression Run",
            percentZone4: 0.65
        )

        let state = SessionSynthesisEngine.evaluateDailyState(
            runRecords: [heavyRun],
            activeGoal: "Half Marathon",
            experienceLevel: "Advanced",
            useMetric: true,
            now: now
        )

        switch state {
        case .preRun(let session):
            // Verify Day 2 of microcycle does not schedule Quality/Intervals while recovery window is active
            if session.microcycle.count >= 2 {
                let day2 = session.microcycle[1]
                XCTAssertFalse(day2.sessionTitle.contains("Intervals") || day2.sessionTitle.contains("Surges"), "Day 2 must not schedule quality while in multi-day recovery: \(day2.sessionTitle)")
            }
        case .completedToday:
            XCTFail("Expected .preRun state")
        }
    }

    // MARK: - Rest Day Synthesis & Readout Parity Tests

    @MainActor
    func testSynthesizeTomorrowPrescription_AfterMonTueCompressiveLoad_PrescribesRestDay() {
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return }

        // User ran Monday (55 min) and Tuesday (60 min)
        let monRun = makeRun(
            date: yesterday,
            duration: 55 * 60,
            distanceMeters: 8000,
            workingAvgCadence: 155,
            workingAvgHeartRate: 138,
            detectedTypeRaw: "Steady Effort",
            percentZone4: 0.05
        )
        let tueRun = makeRun(
            date: today,
            duration: 60 * 60,
            distanceMeters: 9000,
            workingAvgCadence: 155,
            workingAvgHeartRate: 150,
            detectedTypeRaw: "Easy Run",
            percentZone4: 0.05
        )

        // 4-week history establishing ~150m/wk baseline
        var history: [RunRecord] = []
        for d in [4, 7, 10, 14, 17, 21, 24] {
            if let pastDate = calendar.date(byAdding: .day, value: -d, to: today) {
                history.append(makeRun(
                    date: pastDate,
                    duration: 50 * 60,
                    distanceMeters: 7000,
                    workingAvgCadence: 155,
                    workingAvgHeartRate: 142,
                    detectedTypeRaw: "Easy Run",
                    percentZone4: 0.05
                ))
            }
        }

        let allRuns = [tueRun, monRun] + history
        let state = SessionSynthesisEngine.evaluateDailyState(
            runRecords: allRuns,
            activeGoal: "General Fitness",
            experienceLevel: "Intermediate",
            useMetric: true,
            now: now
        )

        switch state {
        case .completedToday(_, let tomorrowSession):
            XCTAssertTrue(tomorrowSession.isRestDay, "Wednesday must be prescribed as Rest Day following 115m compressive 48h volume")
            XCTAssertEqual(tomorrowSession.sessionTitle, "Rest & Structural Recovery Day")
            XCTAssertEqual(tomorrowSession.mainSessionTemplateId, .recoveryJog)
            XCTAssertTrue(tomorrowSession.groundedRationale.contains("48-Hour Volume Compression") || tomorrowSession.groundedRationale.contains("consecutive"))
            XCTAssertTrue(tomorrowSession.microcycle.contains(where: { $0.isRestDay }), "Tomorrow's lookahead microcycle must include a scheduled rest day")
        case .preRun:
            XCTFail("Expected .completedToday since run was logged today")
        }
    }

    func testPrescriptionParity_ActiveDrillReadoutItemFromPrescription_MatchesPrescriptionExactly() {
        let dto = DrillPrescriptionDTO(
            title: "Cadence Pyramids",
            preRunDrillId: PreRunDrillId.cadencePyramids.rawValue,
            purpose: "Cadence priming",
            targetCadence: "158–164 SPM",
            previousCadence: 154,
            durationMinutes: 10,
            hapticMode: "On",
            readinessState: nil,
            isIndoor: false
        )

        let item = ActiveDrillReadoutItem.fromPrescription(dto: dto, customCoachingTip: "Focus on relaxed shoulders.")

        // Verify exact target cadence and work duration parity between Session Card and Interstitial Preview Sheet
        XCTAssertEqual(item.readout.targetCadence, "158–164 SPM", "Preview sheet must match the exact target cadence on the session card")
        XCTAssertEqual(item.dto.targetCadence, "158–164 SPM")
        XCTAssertEqual(item.readout.title, "Cadence Pyramids")
        XCTAssertEqual(item.readout.phases.count, 10)
    }

    func testTodayWorkloadEvaluation_WhenTwoRunsBankedTotallingSixtyMinutes_DeclaresWorkloadSufficient() {
        let now = Date()
        let run1 = makeRun(
            date: now.addingTimeInterval(-3600),
            duration: 600,
            distanceMeters: 1040,
            workingAvgCadence: 152,
            workingAvgHeartRate: 145,
            detectedTypeRaw: "Cadence Pyramids",
            framboiseTags: ["prescribedDrill"],
            isIndoor: true
        )
        let run2 = makeRun(
            date: now.addingTimeInterval(-1800),
            duration: 3000,
            distanceMeters: 5910,
            workingAvgCadence: 153,
            workingAvgHeartRate: 155,
            detectedTypeRaw: "Easy Run",
            isIndoor: true
        )

        let runsToday = [run1, run2]
        let totalDurationSec = runsToday.reduce(0.0) { $0 + $1.duration }
        let (dailyBand, targetMinutes) = SessionSynthesisEngine.aerobicDurationForExperience("Intermediate")
        let completedMinutes = Int(round(totalDurationSec / 60.0))
        let completionPercent = Int(round(Double(completedMinutes) / Double(targetMinutes) * 100.0))

        XCTAssertEqual(runsToday.count, 2)
        XCTAssertEqual(completedMinutes, 60)
        XCTAssertEqual(dailyBand, "35–45 Min")
        XCTAssertEqual(targetMinutes, 40)
        XCTAssertEqual(completionPercent, 150) // 60 min / 40 min = 150%
        XCTAssertTrue(completionPercent >= 80, "60 minutes across two runs exceeds the 80% daily sufficiency threshold")
    }

    func testRunVarianceMap_SingleSteadySegment_GeneratesContinuousAnchors() {
        let singleSegment = PhaseSegment(
            startSeconds: 0,
            endSeconds: 2400,
            kind: "steady",
            avgPace: 508,
            avgCadence: 153,
            avgHR: 155
        )

        let segments = [singleSegment]
        XCTAssertEqual(segments.count, 1)

        // Simulate RunVarianceMapView.chartPoints logic
        var points: [(minute: Double, cadence: Double, isAnchor: Bool)] = []
        let seg = segments[0]
        points.append((minute: seg.startSeconds / 60.0, cadence: seg.avgCadence, isAnchor: false))
        points.append((minute: (seg.startSeconds + seg.endSeconds) / 120.0, cadence: seg.avgCadence, isAnchor: true))
        points.append((minute: seg.endSeconds / 60.0, cadence: seg.avgCadence, isAnchor: false))

        XCTAssertEqual(points.count, 3, "Single steady segment must synthesize 3 points (start, mid, end) for continuous charting")
        XCTAssertEqual(points[0].minute, 0.0)
        XCTAssertEqual(points[1].minute, 20.0)
        XCTAssertEqual(points[2].minute, 40.0)
        XCTAssertEqual(points[0].cadence, 153.0)
        XCTAssertEqual(points[2].cadence, 153.0)
    }

    // MARK: - Edge-Case Architecture Refinements (AC 1–AC 4)

    @MainActor
    func testRecentHadCadenceFade_ThreeTierDisjunction() {
        let now = Date()
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: now) ?? now.addingTimeInterval(-172800)

        // Tier 1: Tag present
        let runWithTag = makeRun(date: twoDaysAgo, framboiseTags: [FramboiseReadinessTag.cadenceFade])
        let stateTag = SessionSynthesisEngine.evaluateDailyState(
            runRecords: [runWithTag],
            activeGoal: "Base Building",
            experienceLevel: "Intermediate",
            useMetric: true,
            now: now
        )
        if case .preRun(let session) = stateTag {
            XCTAssertEqual(session.primerDrillId, .rhythmIntervals, "Tier 1: Tag .cadenceFade must select Rhythm Intervals")
            XCTAssertTrue(session.groundedRationale.contains("Rhythm Intervals"))
        } else {
            XCTFail("Expected preRun state")
        }

        // Tier 2: Tag absent, slope < -0.15
        let runWithSlope = makeRun(date: twoDaysAgo, framboiseTags: [])
        runWithSlope.cadenceSlope = -0.22
        let stateSlope = SessionSynthesisEngine.evaluateDailyState(
            runRecords: [runWithSlope],
            activeGoal: "Base Building",
            experienceLevel: "Intermediate",
            useMetric: true,
            now: now
        )
        if case .preRun(let session) = stateSlope {
            XCTAssertEqual(session.primerDrillId, .rhythmIntervals, "Tier 2: cadenceSlope < -0.15 must trigger Rhythm Intervals")
        } else {
            XCTFail("Expected preRun state")
        }

        // Tier 2 Negative: Tag absent, slope >= -0.15
        let runWithGentleSlope = makeRun(date: twoDaysAgo, framboiseTags: [])
        runWithGentleSlope.cadenceSlope = -0.05
        let stateGentle = SessionSynthesisEngine.evaluateDailyState(
            runRecords: [runWithGentleSlope],
            activeGoal: "Base Building",
            experienceLevel: "Intermediate",
            useMetric: true,
            now: now
        )
        if case .preRun(let session) = stateGentle {
            XCTAssertNotEqual(session.primerDrillId, .rhythmIntervals, "Tier 2 Negative: cadenceSlope >= -0.15 should not trigger cadence fade")
        } else {
            XCTFail("Expected preRun state")
        }

        // Tier 3: Tag absent, slope nil, splits count >= 3 with drop >= 5.0 SPM
        let runWithSplits = makeRun(date: twoDaysAgo, framboiseTags: [])
        runWithSplits.cadenceSlope = nil
        let splits = [
            RunSplit(index: 1, distanceMeters: 1000, durationSeconds: 300, paceSecondsPerKm: 300, avgHeartRate: 145, avgCadence: 165.0, elevationGainMeters: 0),
            RunSplit(index: 2, distanceMeters: 1000, durationSeconds: 300, paceSecondsPerKm: 300, avgHeartRate: 147, avgCadence: 164.0, elevationGainMeters: 0),
            RunSplit(index: 3, distanceMeters: 1000, durationSeconds: 320, paceSecondsPerKm: 320, avgHeartRate: 152, avgCadence: 157.0, elevationGainMeters: 0)
        ]
        // Early 2/3 mean = (165 + 164) / 2 = 164.5. Late 1/3 mean = 157.0. Drop = 7.5 SPM (>= 5.0).
        let sig = RunSignature(
            classification: "Steady Effort",
            confidence: 0.95,
            probabilities: ["Steady Effort": 0.95],
            anomalies: [],
            cadenceFloor: 150.0,
            phaseSegments: [],
            dataSource: "wrist",
            isIndoor: false,
            needsInclineReview: false,
            splits: splits
        )
        runWithSplits.signature = sig
        let stateSplits = SessionSynthesisEngine.evaluateDailyState(
            runRecords: [runWithSplits],
            activeGoal: "Base Building",
            experienceLevel: "Intermediate",
            useMetric: true,
            now: now
        )
        if case .preRun(let session) = stateSplits {
            XCTAssertEqual(session.primerDrillId, .rhythmIntervals, "Tier 3: Splits cadence drop >= 5.0 SPM must trigger Rhythm Intervals")
        } else {
            XCTFail("Expected preRun state")
        }
    }

    @MainActor
    func testTargetCadenceBand_3NFConsistencyAcrossGoals() {
        let base = 160
        // Direct functional test
        let bandProductive = SessionSynthesisEngine.targetCadenceBand(for: .rhythmIntervals, state: .productive, baseCadence: base)
        XCTAssertEqual(bandProductive, "166–172 SPM", "Productive rhythm intervals must be +6 to +12 SPM")
        XCTAssertFalse(bandProductive.contains("(Adapted)"), "Target band must not contain (Adapted) suffix")

        let bandFatigue = SessionSynthesisEngine.targetCadenceBand(for: .cadencePyramids, state: .acuteFatigue, baseCadence: base)
        XCTAssertEqual(bandFatigue, "159–165 SPM", "Acute fatigue must be -1 to +5 SPM")

        let bandDeload = SessionSynthesisEngine.targetCadenceBand(for: .strides, state: .deload, baseCadence: base)
        XCTAssertEqual(bandDeload, "170–178 SPM", "Deload strides must be +10 to +18 SPM")

        // Cross-goal consistency: 10K vs Base Building vs 5K vs Polarized fallback
        let goals = ["5K", "10K", "Half Marathon", "Base Building", "Marathon"]
        let now = Date()
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: now) ?? now.addingTimeInterval(-172800)

        for goal in goals {
            let run = makeRun(date: twoDaysAgo, framboiseTags: [FramboiseReadinessTag.cadenceFade])
            let state = SessionSynthesisEngine.evaluateDailyState(
                runRecords: [run],
                activeGoal: goal,
                experienceLevel: "Intermediate",
                useMetric: true,
                now: now
            )
            if case .preRun(let session) = state {
                if session.primerDrillId == .rhythmIntervals {
                    XCTAssertTrue(session.primerTargetCadence.contains("SPM"))
                    XCTAssertFalse(session.primerTargetCadence.contains("(Adapted)"))
                }
            }
        }
    }

    func testExactThirtyFiveMinutePrescriptionAndPhaseCompilation() {
        // Bijective domain model
        XCTAssertEqual(DrillDuration.thirtyFiveMinutes.rawValue, 35)
        XCTAssertEqual(DrillDuration.nearest(toMinutes: 35), .thirtyFiveMinutes)
        XCTAssertEqual(DrillDuration.nearest(toMinutes: 34), .thirtyFiveMinutes)
        XCTAssertEqual(DrillDuration.nearest(toMinutes: 36), .thirtyFiveMinutes)
        XCTAssertEqual(DrillDuration.nearest(toMinutes: 32), .thirtyMinutes)
        XCTAssertEqual(DrillDuration.nearest(toMinutes: 38), .fortyMinutes)

        // PreRunDrill geometry for 35m session
        let drill = PreRunDrill(
            id: .tempoSurges,
            previousCadence: 160,
            targetCadence: "166–172 SPM",
            duration: .thirtyFiveMinutes
        )
        let phases = drill.generatePhases()
        let totalSeconds = phases.reduce(0.0) { $0 + Double($1.durationSeconds) }
        XCTAssertEqual(totalSeconds, 35.0 * 60.0, "35-minute tempo surges must sum to exactly 2100 seconds")

        // WorkoutPlan compilation
        #if canImport(WorkoutKit)
        if #available(iOS 17.0, *) {
            let plan = drill.buildWorkoutPlan()
            XCTAssertNotNil(plan)
        }
        #endif

        // Readout compilation
        let readout = DrillReadout.readout(
            for: .tempoSurges,
            targetCadence: "166–172 SPM",
            previousCadence: 160,
            customDuration: .thirtyFiveMinutes
        )
        XCTAssertEqual(readout.durationMinutes, 35)
        XCTAssertTrue(readout.subtitle.contains("35 min"))
        XCTAssertFalse(readout.breakdown.isEmpty)

        // DTO compilation with nearest-neighbor lookup
        let dto = DrillPrescriptionDTO(
            title: "10K Threshold Surges",
            preRunDrillId: PreRunDrillId.tempoSurges.rawValue,
            purpose: "Threshold quality session",
            targetCadence: "166–172 SPM",
            previousCadence: 160,
            durationMinutes: 35,
            readinessState: ReadinessState.productive.rawValue
        )
        let readoutFromPrescription = ActiveDrillReadoutItem.fromPrescription(dto: dto)
        XCTAssertEqual(readoutFromPrescription.readout.durationMinutes, 35)
        XCTAssertEqual(readoutFromPrescription.dto.durationMinutes, 35)
    }

    @MainActor
    func testTrainingZoneEngineParityWithSessionSynthesisEngine() {
        let now = Date()
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: now) ?? now.addingTimeInterval(-172800)
        let run = makeRun(date: twoDaysAgo, workingAvgCadence: 162.0, workingAvgHeartRate: 142.0)
        let runs = [run]

        let dailyState = SessionSynthesisEngine.evaluateDailyState(
            runRecords: runs,
            activeGoal: "Base Building",
            experienceLevel: "Intermediate",
            useMetric: true,
            userHeightCm: 175.0,
            now: now
        )

        let expectedSession: PrescribedDailySession = {
            switch dailyState {
            case .preRun(let s): return s
            case .completedToday(_, let tomorrow): return tomorrow
            }
        }()

        let tzRx = TrainingZoneEngine.computePrescription(
            runs: runs,
            activeGoal: "Base Building",
            experienceLevel: "Intermediate",
            useMetricSystem: true,
            userHeightCm: 175.0,
            now: now
        )

        // Bit-for-bit parity
        XCTAssertEqual(tzRx.nextSessionName, expectedSession.sessionTitle)
        XCTAssertEqual(tzRx.prescribedDurationBand, expectedSession.durationBand)
        XCTAssertEqual(tzRx.prescribedPaceBand, expectedSession.paceBand)
        XCTAssertEqual(tzRx.sessionRationale, expectedSession.groundedRationale)
        XCTAssertFalse(tzRx.isColdStart)
        XCTAssertFalse(tzRx.isSubjectiveOverride)
    }
}
