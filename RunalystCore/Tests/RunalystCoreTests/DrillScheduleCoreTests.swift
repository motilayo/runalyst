import Foundation
@testable import RunalystCore
import Testing

@Suite("Drill Schedule & Takeaway Core Tests")
struct DrillScheduleCoreTests {

    @Test("Canonical template minutes mapping")
    func testCanonicalTemplateMinutes() {
        #expect(DrillScheduleCore.canonicalTemplateMinutes(forRawMinutes: 5) == 5)
        #expect(DrillScheduleCore.canonicalTemplateMinutes(forRawMinutes: 7) == 10)
        #expect(DrillScheduleCore.canonicalTemplateMinutes(forRawMinutes: 8) == 10)
        #expect(DrillScheduleCore.canonicalTemplateMinutes(forRawMinutes: 10) == 10)
        #expect(DrillScheduleCore.canonicalTemplateMinutes(forRawMinutes: 12) == 10)
        #expect(DrillScheduleCore.canonicalTemplateMinutes(forRawMinutes: 15) == 15)
        #expect(DrillScheduleCore.canonicalTemplateMinutes(forRawMinutes: 20) == 20)
        #expect(DrillScheduleCore.canonicalTemplateMinutes(forRawMinutes: 27) == 30)
        #expect(DrillScheduleCore.canonicalTemplateMinutes(forRawMinutes: 30) == 30)
        #expect(DrillScheduleCore.canonicalTemplateMinutes(forRawMinutes: 35) == 35)
        #expect(DrillScheduleCore.canonicalTemplateMinutes(forRawMinutes: 40) == 40)
        #expect(DrillScheduleCore.canonicalTemplateMinutes(forRawMinutes: 50) == 50)
    }

    @Test("Walk recovery defaults per drill archetype")
    func testWalkRecoveryDefaults() {
        #expect(DrillScheduleCore.defaultIsWalkRecovery(for: "cadence_pyramids") == true)
        #expect(DrillScheduleCore.defaultIsWalkRecovery(for: "tempo_surges") == true)
        #expect(DrillScheduleCore.defaultIsWalkRecovery(for: "strides") == true)
        #expect(DrillScheduleCore.defaultIsWalkRecovery(for: "neuromuscular_primer") == true)
        #expect(DrillScheduleCore.defaultIsWalkRecovery(for: "hill_bounds") == true)

        #expect(DrillScheduleCore.defaultIsWalkRecovery(for: "rhythm_intervals") == false)
        #expect(DrillScheduleCore.defaultIsWalkRecovery(for: "fartlek_primer") == false)
        #expect(DrillScheduleCore.defaultIsWalkRecovery(for: "aerobic_flush") == false)
        #expect(DrillScheduleCore.defaultIsWalkRecovery(for: "recovery_jog") == false)
        #expect(DrillScheduleCore.defaultIsWalkRecovery(for: "zone2_run") == false)
    }

    @Test("Acute fatigue 10-minute Cadence Pyramids trims to exact 7-minute geometry")
    func testAcuteFatigue10MinCadencePyramids() {
        let schedule = DrillScheduleCore.schedule(
            for: "cadence_pyramids",
            durationMinutes: 10,
            readinessState: "acuteFatigue"
        )

        #expect(schedule.warmupSeconds == 90.0)
        #expect(schedule.iterations == 2)
        #expect(schedule.workSeconds == 30.0)
        #expect(schedule.recoverySeconds == 45.0)
        #expect(schedule.cooldownSeconds == 180.0)
        #expect(schedule.totalDurationSeconds == 420)
        #expect(schedule.formattedTotalDuration == "7 min")
        #expect(schedule.preciseStructureSummary == "1.5m in • 2x (30s / 45s) • 3m out")

        let breakdown = schedule.generateStructureBreakdownProse()
        #expect(breakdown.contains("1.5-minute easy warm-up jog"))
        #expect(breakdown.contains("2 sets of 30-second intervals"))
        #expect(breakdown.contains("45 seconds of walk recovery"))
        #expect(breakdown.contains("3-minute cool-down"))
    }

    @Test("35-minute Tempo Surges main run preserves walk recovery and dynamic 7-minute cool-down")
    func testTempoSurges35MinutesMainRun() {
        let schedule = DrillScheduleCore.schedule(
            for: "tempo_surges",
            durationMinutes: 35,
            readinessState: "productive"
        )

        #expect(schedule.warmupSeconds == 240.0)
        #expect(schedule.iterations == 4)
        #expect(schedule.workSeconds == 180.0)
        #expect(schedule.recoverySeconds == 180.0)
        #expect(schedule.cooldownSeconds == 420.0)
        #expect(schedule.totalDurationSeconds == 2100)
        #expect(schedule.formattedTotalDuration == "35 min")
        #expect(schedule.isWalkRecovery == true)
        #expect(schedule.preciseStructureSummary == "4m in • 4x (3m / 3m) • 7m out")

        let breakdown = schedule.generateStructureBreakdownProse()
        #expect(breakdown.contains("finishing with a 7-minute cool-down."))
        #expect(!breakdown.contains("2-minute cool-down"))
    }

    @Test("Deload and acute fatigue modulate 15-minute Strides correctly")
    func testStridesReadinessModulation() {
        // Deload: 5m warmup + 3 x (20s sprint + 90s walk = 330s) + 2m cooldown = 750s = 12m 30s
        let deloadSched = DrillScheduleCore.schedule(
            for: "strides",
            durationMinutes: 15,
            readinessState: "deload"
        )
        #expect(deloadSched.totalDurationSeconds == 750)
        #expect(deloadSched.formattedTotalDuration == "12m 30s")
        #expect(deloadSched.iterations == 3)
        #expect(deloadSched.recoverySeconds == 90.0)

        // Acute fatigue: 5m warmup + 3 x (20s sprint + 60s walk = 240s) + 2m cooldown = 660s = 11 min
        let fatigueSched = DrillScheduleCore.schedule(
            for: "strides",
            durationMinutes: 15,
            readinessState: "acuteFatigue"
        )
        #expect(fatigueSched.totalDurationSeconds == 660)
        #expect(fatigueSched.formattedTotalDuration == "11 min")
        #expect(fatigueSched.iterations == 3)
        #expect(fatigueSched.recoverySeconds == 60.0)
    }

    @Test("Aerobic strain evaluation accurately flags overreach and boundary violations")
    func testAerobicStrainEvaluation() {
        // Zone 4 overreach by percentage
        let highZ4 = AerobicStrainEvaluation.evaluate(
            workingAvgHeartRate: 140.0,
            percentZone4: 0.18,
            zone2Ceiling: 144.0,
            isRecoveryPrescription: false
        )
        #expect(highZ4.isZone4Overreach == true)
        #expect(highZ4.isCeilingExceeded == true)
        #expect(highZ4.effectiveCeilingBPM == 144.0)

        // Recovery ceiling enforcement
        let recoveryStrain = AerobicStrainEvaluation.evaluate(
            workingAvgHeartRate: 138.0,
            percentZone4: 0.0,
            zone2Ceiling: 144.0,
            isRecoveryPrescription: true
        )
        #expect(recoveryStrain.effectiveCeilingBPM == 135.0)
        #expect(recoveryStrain.isCeilingExceeded == true)
        #expect(recoveryStrain.isZone4Overreach == false)

        // Controlled zone 2 run
        let controlled = AerobicStrainEvaluation.evaluate(
            workingAvgHeartRate: 132.0,
            percentZone4: 0.01,
            zone2Ceiling: 144.0,
            isRecoveryPrescription: false
        )
        #expect(controlled.isCeilingExceeded == false)
        #expect(controlled.isZone4Overreach == false)
    }

    @Test("RunTakeawaySummary evaluates cadence floor matching diagnostic copy")
    func testTakeawaySummaryCadenceFloorMatching() {
        // Cadence == floor (150 == 150)
        let summaryMatch = RunTakeawaySummary.evaluate(
            detectedTypeRaw: "Steady Effort",
            workingAvgCadence: 150.0,
            workingAvgHeartRate: 138.0,
            percentZone4: 0.0,
            heightAdjustedCadenceFloor: 150,
            isIndoor: false
        )
        let cadBulletMatch = summaryMatch.bullets.first { $0.contains("Turnover averaged") }
        #expect(cadBulletMatch != nil)
        #expect(cadBulletMatch?.contains("matching your 150 SPM mechanical floor") == true)
        #expect(cadBulletMatch?.contains("safely above") == false)

        // Cadence > floor (158 > 150)
        let summaryAbove = RunTakeawaySummary.evaluate(
            detectedTypeRaw: "Steady Effort",
            workingAvgCadence: 158.0,
            workingAvgHeartRate: 138.0,
            percentZone4: 0.0,
            heightAdjustedCadenceFloor: 150,
            isIndoor: false
        )
        let cadBulletAbove = summaryAbove.bullets.first { $0.contains("Turnover averaged") }
        #expect(cadBulletAbove?.contains("safely above your 150 SPM mechanical floor") == true)

        // Cadence < floor (144 < 150)
        let summaryBelow = RunTakeawaySummary.evaluate(
            detectedTypeRaw: "Steady Effort",
            workingAvgCadence: 144.0,
            workingAvgHeartRate: 138.0,
            percentZone4: 0.0,
            heightAdjustedCadenceFloor: 150,
            isIndoor: false
        )
        let cadBulletBelow = summaryBelow.bullets.first { $0.contains("Turnover averaged") }
        #expect(cadBulletBelow?.contains("6 SPM below your 150 SPM mechanical floor") == true)
        #expect(summaryBelow.headline == "Mechanical Floor Missed")
    }

    @Test("RunTakeawaySummary evaluates indoor thermal strain and boundary headlines")
    func testTakeawaySummaryIndoorAndBoundaries() {
        // Indoor thermal drift
        let summaryIndoor = RunTakeawaySummary.evaluate(
            detectedTypeRaw: "Steady Effort",
            workingAvgCadence: 155.0,
            workingAvgHeartRate: 148.0,
            percentZone4: 0.16,
            heightAdjustedCadenceFloor: 150,
            isIndoor: true,
            hasCardiacDrift: true,
            cardiacDriftMagnitudeBPM: 14
        )
        #expect(summaryIndoor.headline == "Target Ceiling Exceeded")
        let cardioBullet = summaryIndoor.bullets.first { $0.contains("thermal buildup") }
        #expect(cardioBullet != nil)
        #expect(cardioBullet?.contains("148 BPM average drifted above your 144 BPM target ceiling under indoor thermal load") == true)

        // Both ceiling and floor missed
        let summaryBoth = RunTakeawaySummary.evaluate(
            detectedTypeRaw: "Steady Effort",
            workingAvgCadence: 142.0,
            workingAvgHeartRate: 152.0,
            percentZone4: 0.20,
            heightAdjustedCadenceFloor: 150
        )
        #expect(summaryBoth.headline == "Target Ceiling & Floor Missed")
    }
}
