import XCTest
import WorkoutKit
@testable import Runalyst

final class WorkoutPlanTests: XCTestCase {
    func testDrillWorkoutPlans() {
        for id in PreRunDrillId.allCases {
            let outdoorDrill = PreRunDrill(id: id, previousCadence: 160, isIndoor: false)
            let outdoorPlan = outdoorDrill.buildWorkoutPlan()
            if case .custom(let customOutdoor) = outdoorPlan.workout {
                XCTAssertEqual(customOutdoor.location, .outdoor)
            } else {
                XCTFail("Expected custom workout for outdoor \(id.rawValue)")
            }

            let indoorDrill = PreRunDrill(id: id, previousCadence: 160, targetCadence: "155-161", isIndoor: true)
            let indoorPlan = indoorDrill.buildWorkoutPlan()
            if case .custom(let customIndoor) = indoorPlan.workout {
                XCTAssertEqual(customIndoor.location, .indoor)
                if !id.isHeartRateTargeted && !id.isAerobicContinuous {
                    XCTAssertTrue(customIndoor.displayName?.contains("155-161 SPM") == true)
                }
            } else {
                XCTFail("Expected custom workout for indoor \(id.rawValue)")
            }
            print("Successfully built outdoor & indoor plans for \(id.rawValue)")
        }

        let alertThreshold = CadenceThresholdAlert.cadence(160.0)
        XCTAssertTrue(CustomWorkout.supportsAlert(alertThreshold, activity: .running, location: .outdoor))
        XCTAssertTrue(CustomWorkout.supportsGoal(.time(3, .minutes), activity: .running, location: .outdoor))
        XCTAssertTrue(CustomWorkout.supportsGoal(.time(2, .minutes), activity: .running, location: .outdoor))
        XCTAssertTrue(CustomWorkout.supportsGoal(.time(1, .minutes), activity: .running, location: .outdoor))
        let hrZoneAlert = HeartRateZoneAlert(zone: 2)
        XCTAssertTrue(CustomWorkout.supportsAlert(hrZoneAlert, activity: .running, location: .outdoor))
        XCTAssertTrue(CustomWorkout.supportsAlert(hrZoneAlert, activity: .running, location: .indoor))
    }

    func testZone2RunWorkoutPlanAndTarget() {
        let drill = PreRunDrill(id: .zone2Run, previousCadence: 160)
        XCTAssertNil(drill.effectiveTargetCadence)
        let plan = drill.buildWorkoutPlan()
        XCTAssertNotNil(plan)
        let template = DrillTemplate.template(for: .zone2Run)
        XCTAssertEqual(template.title, "Zone 2 Run")
        XCTAssertEqual(template.defaultEffort, "Zone 2 Aerobic")
    }

    func testAerobicFlushWorkoutPlanAndTarget() {
        let drill = PreRunDrill(id: .aerobicFlush, previousCadence: 160)
        XCTAssertNil(drill.effectiveTargetCadence)
        let plan = drill.buildWorkoutPlan()
        XCTAssertNotNil(plan)
        let template = DrillTemplate.template(for: .aerobicFlush)
        XCTAssertEqual(template.title, "Aerobic Flush")
        XCTAssertEqual(template.defaultEffort, "Zone 1 Active Recovery")
    }

    func testWorkoutPhaseTimelineGeneration() {
        // Strides 15 min: Warmup (5m) + 6 x (20s work + 60s walk) + Cooldown (2m)
        let stridesDrill = PreRunDrill(id: .strides, duration: .fifteenMinutes)
        let stridesPhases = stridesDrill.generatePhases()

        XCTAssertFalse(stridesPhases.isEmpty)
        XCTAssertEqual(stridesPhases.first?.kind, .warmup)
        XCTAssertEqual(stridesPhases.first?.durationSeconds, 300)
        XCTAssertEqual(stridesPhases.first?.formattedDuration, "5m")

        let workPhases = stridesPhases.filter { $0.kind == .work }
        let recPhases = stridesPhases.filter {
            if case .recovery = $0.kind { return true }
            return false
        }
        XCTAssertEqual(workPhases.count, 6)
        XCTAssertEqual(recPhases.count, 6)
        XCTAssertEqual(workPhases.first?.durationSeconds, 20)
        XCTAssertEqual(recPhases.first?.durationSeconds, 60)
        XCTAssertEqual(recPhases.first?.name, "Walk")

        XCTAssertEqual(stridesPhases.last?.kind, .cooldown)
        XCTAssertEqual(stridesPhases.last?.durationSeconds, 120)

        // All drill cases across durations generate non-empty phases
        for drillId in PreRunDrillId.allCases {
            for duration in DrillDuration.allCases {
                let drill = PreRunDrill(id: drillId, duration: duration)
                let phases = drill.generatePhases()
                XCTAssertFalse(phases.isEmpty, "Phases should not be empty for \(drillId) at \(duration)")
                XCTAssertTrue(phases.allSatisfy { $0.durationSeconds > 0 })
            }
        }
    }

    func testZone2RunWorkoutPlanDurationIntegrity() {
        let drill = PreRunDrill(id: .zone2Run, duration: .thirtyMinutes)
        let plan = drill.buildWorkoutPlan()
        if case .custom(let customWorkout) = plan.workout {
            XCTAssertEqual(customWorkout.warmup?.goal, .time(5, .minutes))
            XCTAssertEqual(customWorkout.cooldown?.goal, .time(5, .minutes))
            XCTAssertEqual(customWorkout.blocks.count, 1)
            XCTAssertEqual(customWorkout.blocks.first?.iterations, 1)
            XCTAssertEqual(customWorkout.blocks.first?.steps.first?.step.goal, .time(1200, .seconds))
        } else {
            XCTFail("Expected custom workout for Zone 2 run")
        }
    }

    func testStridesReadinessWorkoutPlanDurationAlignment() {
        // Deload strides: 5m warmup + 3 x (20s sprint / 90s walk = 330s) + 2m cooldown = 750s (12m 30s)
        let deloadDrill = PreRunDrill(id: .strides, duration: .fifteenMinutes, readinessState: .deload)
        let deloadPlan = deloadDrill.buildWorkoutPlan()
        if case .custom(let customWorkout) = deloadPlan.workout {
            XCTAssertEqual(customWorkout.warmup?.goal, .time(5, .minutes))
            XCTAssertEqual(customWorkout.cooldown?.goal, .time(2, .minutes))
            XCTAssertEqual(customWorkout.blocks.first?.iterations, 3)
            XCTAssertEqual(customWorkout.blocks.first?.steps.count, 2)
            XCTAssertEqual(customWorkout.blocks.first?.steps[0].step.goal, .time(20, .seconds))
            XCTAssertEqual(customWorkout.blocks.first?.steps[1].step.goal, .time(90, .seconds))
        } else {
            XCTFail("Expected custom workout for deload Strides")
        }

        // Acute fatigue strides: 5m warmup + 3 x (20s sprint / 60s walk = 240s) + 2m cooldown = 660s (11m)
        let fatigueDrill = PreRunDrill(id: .strides, duration: .fifteenMinutes, readinessState: .acuteFatigue)
        let fatiguePlan = fatigueDrill.buildWorkoutPlan()
        if case .custom(let customWorkout) = fatiguePlan.workout {
            XCTAssertEqual(customWorkout.warmup?.goal, .time(5, .minutes))
            XCTAssertEqual(customWorkout.cooldown?.goal, .time(2, .minutes))
            XCTAssertEqual(customWorkout.blocks.first?.iterations, 3)
            XCTAssertEqual(customWorkout.blocks.first?.steps.count, 2)
            XCTAssertEqual(customWorkout.blocks.first?.steps[0].step.goal, .time(20, .seconds))
            XCTAssertEqual(customWorkout.blocks.first?.steps[1].step.goal, .time(60, .seconds))
        } else {
            XCTFail("Expected custom workout for fatigue Strides")
        }
    }

    // MARK: - Upcoming Schedule Card Scannability & Parsing Tests

    @MainActor
    func testUpcomingScheduleCardView_ParseSessionSchedule() {
        // Parenthesized format
        let p1 = UpcomingScheduleCardView.parseSessionSchedule("Aerobic Consistency Run (8 km)")
        XCTAssertEqual(p1.name, "Aerobic Consistency Run")
        XCTAssertEqual(p1.detail, "8 km")

        let p2 = UpcomingScheduleCardView.parseSessionSchedule("Zone 2 Steady (45m)")
        XCTAssertEqual(p2.name, "Zone 2 Steady")
        XCTAssertEqual(p2.detail, "45m")

        // Leading distance format
        let p3 = UpcomingScheduleCardView.parseSessionSchedule("6 km Easy Aerobic Run")
        XCTAssertEqual(p3.name, "Easy Aerobic Run")
        XCTAssertEqual(p3.detail, "6 km")

        // Trailing distance format
        let p4 = UpcomingScheduleCardView.parseSessionSchedule("Long Run 14 km")
        XCTAssertEqual(p4.name, "Long Run")
        XCTAssertEqual(p4.detail, "14 km")

        let p5 = UpcomingScheduleCardView.parseSessionSchedule("Long Run 8.5 mi")
        XCTAssertEqual(p5.name, "Long Run")
        XCTAssertEqual(p5.detail, "8.5 mi")

        // Bullet format
        let p6 = UpcomingScheduleCardView.parseSessionSchedule("Tempo Surges • 30m")
        XCTAssertEqual(p6.name, "Tempo Surges")
        XCTAssertEqual(p6.detail, "30m")

        // Rest Day
        let p7 = UpcomingScheduleCardView.parseSessionSchedule("Rest Day")
        XCTAssertEqual(p7.name, "Rest Day")
        XCTAssertNil(p7.detail)
    }

    @MainActor
    func testUpcomingScheduleCardView_ScheduleCategoryScannability() {
        let restDay = MicrocycleDay(id: "1", dayLabel: "Wed", sessionTitle: "Rest Day", iconName: "bed.double.fill", isRestDay: true)
        XCTAssertEqual(UpcomingScheduleCardView.ScheduleCategory.category(for: restDay), .rest)

        let longDay = MicrocycleDay(id: "2", dayLabel: "Thu", sessionTitle: "Long Run 14 km", iconName: "figure.run", isRestDay: false)
        XCTAssertEqual(UpcomingScheduleCardView.ScheduleCategory.category(for: longDay), .longRun)

        let speedDay = MicrocycleDay(id: "3", dayLabel: "Tue", sessionTitle: "Tempo Surges (30m)", iconName: "bolt.fill", isRestDay: false)
        XCTAssertEqual(UpcomingScheduleCardView.ScheduleCategory.category(for: speedDay), .speedTempo)

        let easyDay = MicrocycleDay(id: "4", dayLabel: "Sun", sessionTitle: "Aerobic Consistency Run (8 km)", iconName: "leaf.fill", isRestDay: false)
        XCTAssertEqual(UpcomingScheduleCardView.ScheduleCategory.category(for: easyDay), .easyRecovery)

        let steadyDay = MicrocycleDay(id: "5", dayLabel: "Mon", sessionTitle: "Zone 2 Steady (45m)", iconName: "figure.run", isRestDay: false)
        XCTAssertEqual(UpcomingScheduleCardView.ScheduleCategory.category(for: steadyDay), .steadyAerobic)
    }
}
