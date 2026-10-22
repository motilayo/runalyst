import XCTest
@testable import Runalyst

final class DrillReadoutTests: XCTestCase {

    func testPostureCheckReadoutFormat() {
        let readout = DrillReadout.readout(for: .tempoSurges)

        XCTAssertEqual(readout.drillId, .tempoSurges)
        XCTAssertEqual(readout.title, "Posture Check")
        XCTAssertEqual(readout.subtitle, "Tempo Pre-Run • 10 min")
        XCTAssertEqual(
            readout.overview,
            "In this drill, you will complete a mechanical reset before your main run."
        )
        XCTAssertEqual(
            readout.breakdown,
            "You’ll start with a 2.5-minute easy warm-up jog. This is followed by 5 sets of intervals where you will run at a high, brisk cadence for 30 seconds, followed by a strict 60-second walk to catch your breath."
        )
        XCTAssertTrue(readout.coachingTip.contains("A taller posture reduces vertical bounce and saves energy."))
        XCTAssertTrue(readout.coachingTip.contains("160 SPM target without sprinting."))

        // Verify phase geometry
        let phases = readout.phases
        XCTAssertFalse(phases.isEmpty)

        // Warmup: 2.5 min = 150 seconds
        XCTAssertEqual(phases.first?.kind, .warmup)
        XCTAssertEqual(phases.first?.durationSeconds, 150)

        // 5 sets of (30s work + 60s walk)
        let workPhases = phases.filter { $0.kind == .work }
        let walkPhases = phases.filter {
            if case .recovery(let isWalk) = $0.kind {
                return isWalk
            }
            return false
        }
        XCTAssertEqual(workPhases.count, 5)
        XCTAssertEqual(walkPhases.count, 5)
        XCTAssertEqual(workPhases.first?.durationSeconds, 30)
        XCTAssertEqual(walkPhases.first?.durationSeconds, 60)

        let totalDuration = phases.reduce(0) { $0 + $1.durationSeconds }
        XCTAssertEqual(totalDuration, 600) // 10 minutes total
    }

    func testStridesReadoutFormat() {
        let readout = DrillReadout.readout(for: .strides)

        XCTAssertEqual(readout.drillId, .strides)
        XCTAssertEqual(readout.title, "Strides")
        XCTAssertEqual(readout.subtitle, "Interval Pre-Run • 15 min")
        XCTAssertEqual(
            readout.overview,
            "In this drill, you will wake up your leg turnover and find a quick, springy rhythm before your run."
        )
        XCTAssertEqual(
            readout.breakdown,
            "You’ll start with a 5-minute easy jog to warm up the joints, followed by 6 short interval sets. In each interval, you’ll accelerate into a 20-second sprint, followed immediately by a 60-second walk to let your heart rate drop completely."
        )
        XCTAssertTrue(readout.coachingTip.contains("Don't fight through fatigue."))
        XCTAssertTrue(readout.coachingTip.contains("Use the full 60-second walk to recover"))

        // Verify phase geometry
        let phases = readout.phases
        XCTAssertFalse(phases.isEmpty)

        // Warm-up: 5 minutes = 300 seconds
        XCTAssertEqual(phases.first?.kind, .warmup)
        XCTAssertEqual(phases.first?.durationSeconds, 300)

        // 6 sets of (20s sprint + 60s walk)
        let workPhases = phases.filter { $0.kind == .work }
        let walkPhases = phases.filter {
            if case .recovery(let isWalk) = $0.kind {
                return isWalk
            }
            return false
        }
        XCTAssertEqual(workPhases.count, 6)
        XCTAssertEqual(walkPhases.count, 6)
        XCTAssertEqual(workPhases.first?.durationSeconds, 20)
        XCTAssertEqual(walkPhases.first?.durationSeconds, 60)

        let totalDuration = phases.reduce(0) { $0 + $1.durationSeconds }
        XCTAssertEqual(totalDuration, 900) // 15 minutes total
    }

    func testDynamicActivationReadoutFormat() {
        let readout = DrillReadout.readout(for: .zone2Run)

        XCTAssertEqual(readout.drillId, .zone2Run)
        XCTAssertEqual(readout.title, "Dynamic Activation")
        XCTAssertEqual(readout.subtitle, "Long Run / Zone 2 Pre-Run • 5 min")
        XCTAssertEqual(
            readout.overview,
            "In this drill, you will complete a continuous warm-up to lubricate your joints without burning vital glycogen."
        )
        XCTAssertEqual(
            readout.breakdown,
            "You’ll execute a single, continuous 5-minute block of low-intensity movement. There are no sprints or intervals—just a steady, progressive effort to elevate your core temperature before your long miles."
        )
        XCTAssertTrue(readout.coachingTip.contains("Keep your breathing entirely through your nose."))
        XCTAssertTrue(readout.coachingTip.contains("Zone 2."))

        // Verify phase geometry
        let phases = readout.phases
        XCTAssertEqual(phases.count, 1)
        XCTAssertEqual(phases.first?.kind, .warmup)
        XCTAssertEqual(phases.first?.durationSeconds, 300) // 5 minutes total
    }

    func testCustomTargetCadenceInterpolation() {
        let readout = DrillReadout.readout(for: .tempoSurges, targetCadence: "164 SPM")
        XCTAssertEqual(readout.targetCadence, "164 SPM")
        XCTAssertTrue(readout.coachingTip.contains("164 SPM target without sprinting"))
    }

    func testAllPreRunDrillsProduceValidReadouts() {
        for drill in PreRunDrillId.allCases {
            let readout = DrillReadout.readout(for: drill)
            XCTAssertFalse(readout.title.isEmpty)
            XCTAssertFalse(readout.overview.isEmpty)
            XCTAssertFalse(readout.breakdown.isEmpty)
            XCTAssertFalse(readout.coachingTip.isEmpty)
            XCTAssertFalse(readout.phases.isEmpty)
            XCTAssertGreaterThan(readout.durationMinutes, 0)
        }
    }

    func testCoachingTipsMatchBetweenTemplateAndReadout() {
        for drillId in PreRunDrillId.allCases {
            let template = DrillTemplate.template(for: drillId)
            let templateCue = template.generateInstructionalCue("165 SPM")
            let readout = DrillReadout.readout(for: drillId, targetCadence: "165 SPM")
            XCTAssertEqual(
                readout.coachingTip,
                templateCue,
                "Coaching tip must exactly match template for \(drillId)"
            )
        }
    }

    func testRhythmIntervalsScalesAcrossAllDurations() {
        for duration in DrillDuration.allCases {
            let readout = DrillReadout.readout(for: .rhythmIntervals, customDuration: duration)
            XCTAssertTrue(
                readout.subtitle.contains("\(duration.rawValue) min"),
                "Subtitle should mention \(duration.rawValue) min"
            )
            XCTAssertEqual(
                readout.overview,
                "In this drill, you will complete a rhythmic tempo tune-up to establish a consistent, economical cadence."
            )
            XCTAssertEqual(readout.durationMinutes, duration.rawValue)
            let totalSeconds = readout.phases.reduce(0) { $0 + $1.durationSeconds }
            XCTAssertEqual(
                totalSeconds,
                duration.rawValue * 60,
                "Total seconds for rhythmIntervals at \(duration) must equal \(duration.rawValue * 60)"
            )
        }
    }

    func testNeuromuscularPrimerScalesAcrossAllDurations() {
        for duration in DrillDuration.allCases {
            let readout = DrillReadout.readout(for: .neuromuscularPrimer, customDuration: duration)
            XCTAssertTrue(
                readout.subtitle.contains("\(duration.rawValue) min"),
                "Subtitle should mention \(duration.rawValue) min"
            )
            XCTAssertEqual(
                readout.overview,
                "In this drill, you will complete quick-step bursts to wake up fast turnover and keep your stride springy and light."
            )
            XCTAssertEqual(readout.durationMinutes, duration.rawValue)
            let totalSeconds = readout.phases.reduce(0) { $0 + $1.durationSeconds }
            XCTAssertEqual(
                totalSeconds,
                duration.rawValue * 60,
                "Total seconds for neuromuscularPrimer at \(duration) must equal \(duration.rawValue * 60)"
            )
        }
    }

    func testAllDrillPhasesSumToExactSelectedDuration() {
        for drillId in PreRunDrillId.allCases {
            for duration in DrillDuration.allCases {
                let drill = PreRunDrill(id: drillId, duration: duration)
                let phases = drill.generatePhases()
                let totalSeconds = phases.reduce(0) { $0 + $1.durationSeconds }
                XCTAssertEqual(
                    totalSeconds,
                    duration.rawValue * 60,
                    "Total phase duration for \(drillId) at \(duration) must be exactly \(duration.rawValue * 60)s"
                )
            }
        }
    }

    func testCadencePyramidsReadinessAdaptationDurationCohesion() {
        let dto = DrillPrescriptionDTO(
            title: "Cadence Pyramids",
            preRunDrillId: PreRunDrillId.cadencePyramids.rawValue,
            purpose: "Rhythm and turnover",
            targetCadence: "163-169 SPM",
            previousCadence: 159,
            durationMinutes: 10
        )
        let fatigueAssessment = ReadinessAssessment(
            state: .acuteFatigue,
            triggers: [.consecutiveHardDays],
            acuteLoad: 350.0,
            chronicWeeklyLoad: 200.0,
            acwr: 1.75,
            mileageDropFraction: nil
        )

        let activeItem = ActiveDrillReadoutItem.adaptive(
            dto: dto,
            readiness: fatigueAssessment
        )

        let readout = activeItem.readout
        // Phase math: 2m warm-up (120s) + 2 x (30s work + 45s walk = 150s) + 3m cool-down (180s) = 450s = 7m 30s
        XCTAssertEqual(readout.totalDurationSeconds, 450)
        XCTAssertEqual(readout.formattedDuration, "7m 30s")

        // Must display mathematically exact 7m 30s in subtitle, NEVER rounding up to 8 min
        XCTAssertTrue(readout.subtitle.contains("7m 30s"), "Subtitle must contain 7m 30s")
        XCTAssertFalse(readout.subtitle.contains("8 min"), "Subtitle must never display rounded-up 8 min")
        // Overview states the drill purpose without redundant duration
        XCTAssertEqual(
            readout.overview,
            "In this drill, you will complete a cadence progression to eliminate overstriding and protect your knees."
        )
        XCTAssertFalse(readout.overview.contains("7m 30s"), "Overview must not contain duration")
        XCTAssertFalse(readout.overview.contains("10-minute"), "Overview must not contain duration")
    }

    func testStridesFromPrescriptionDeloadReadoutCohesion() {
        let dto = DrillPrescriptionDTO(
            title: "Strides",
            preRunDrillId: PreRunDrillId.strides.rawValue,
            purpose: "Deload turnover",
            targetCadence: "165 SPM",
            previousCadence: 160,
            durationMinutes: 15,
            readinessState: ReadinessState.deload.rawValue
        )

        let activeItem = ActiveDrillReadoutItem.fromPrescription(
            dto: dto,
            customCoachingTip: "Deload phase in progress."
        )

        let readout = activeItem.readout
        // Phase math: 5m warmup (300s) + 3 x (20s sprint + 90s walk = 330s) + 2m cooldown (120s) = 750s = 12m 30s
        XCTAssertEqual(readout.totalDurationSeconds, 750)
        XCTAssertEqual(readout.formattedDuration, "12m 30s")
        XCTAssertTrue(readout.subtitle.contains("12m 30s"))
        XCTAssertFalse(readout.subtitle.contains("15 min"))
        XCTAssertTrue(readout.breakdown.contains("3 sets of 20-second strides"))
        XCTAssertTrue(readout.breakdown.contains("90 seconds of walk recovery"))
        XCTAssertEqual(readout.readinessState, .deload)
    }

    func testStridesFromPrescriptionAcuteFatigueReadoutCohesion() {
        let dto = DrillPrescriptionDTO(
            title: "Strides",
            preRunDrillId: PreRunDrillId.strides.rawValue,
            purpose: "Active recovery turnover",
            targetCadence: "165 SPM",
            previousCadence: 160,
            durationMinutes: 15,
            readinessState: ReadinessState.acuteFatigue.rawValue
        )

        let activeItem = ActiveDrillReadoutItem.fromPrescription(
            dto: dto,
            customCoachingTip: "Acute fatigue recovery."
        )

        let readout = activeItem.readout
        // Phase math: 5m warmup (300s) + 3 x (20s sprint + 60s walk = 240s) + 2m cooldown (120s) = 660s = 11 min
        XCTAssertEqual(readout.totalDurationSeconds, 660)
        XCTAssertEqual(readout.formattedDuration, "11 min")
        XCTAssertTrue(readout.subtitle.contains("11 min"))
        XCTAssertFalse(readout.subtitle.contains("15 min"))
        XCTAssertTrue(readout.breakdown.contains("3 sets of 20-second strides"))
        XCTAssertTrue(readout.breakdown.contains("1 minute of walk recovery"))
        XCTAssertEqual(readout.readinessState, .acuteFatigue)
    }
}
