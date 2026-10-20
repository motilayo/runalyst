import XCTest
@testable import Runalyst
#if canImport(WorkoutKit)
import WorkoutKit
#endif

final class ReadinessModifierTests: XCTestCase {

    // MARK: - Helper Factory

    private func makeRun(
        daysAgo: Double,
        distanceKm: Double = 5.0,
        durationMinutes: Double = 30.0,
        percentZone4: Double = 0.05,
        type: String = "Steady Effort",
        tags: Set<String> = [],
        now: Date = Date()
    ) -> ReadinessRunSnapshot {
        let date = now.addingTimeInterval(-daysAgo * 86400)
        return ReadinessRunSnapshot(
            date: date,
            distanceMeters: distanceKm * 1000.0,
            durationSeconds: durationMinutes * 60.0,
            percentZone4: percentZone4,
            detectedType: type,
            tags: tags
        )
    }

    // MARK: - Evaluator Tests

    func testProductiveStateWhenLoadIsBalanced() {
        let now = Date()
        // 4 weeks of consistent training: 3 runs per week, 30 mins each, 5 km each, Zone 2
        var runs: [ReadinessRunSnapshot] = []
        for day in [2, 4, 6, 9, 11, 13, 16, 18, 20, 23, 25, 27] {
            runs.append(makeRun(daysAgo: Double(day), distanceKm: 6.0, durationMinutes: 35.0, percentZone4: 0.05, now: now))
        }

        let assessment = ReadinessEvaluator.assess(runs: runs, now: now)
        XCTAssertEqual(assessment.state, .productive)
        XCTAssertTrue(assessment.triggers.isEmpty)
        if let acwr = assessment.acwr {
            XCTAssertGreaterThanOrEqual(acwr, 0.8)
            XCTAssertLessThanOrEqual(acwr, 1.3)
        }

        // Target remains standard
        let target = ReadinessModifier.adaptTarget("170 SPM", baselineCadence: 155, drillId: .strides, state: assessment.state)
        XCTAssertFalse(target.isCadenceRelaxed)
        XCTAssertEqual(target.targetCadence, "170 SPM")
    }

    func testAcuteFatigueFromACWRSpike() {
        let now = Date()
        var runs: [ReadinessRunSnapshot] = []
        // Light baseline for 3 trailing weeks (1 run per week, 20 mins)
        for day in [10, 17, 24] {
            runs.append(makeRun(daysAgo: Double(day), distanceKm: 3.0, durationMinutes: 20.0, percentZone4: 0.0, now: now))
        }
        // Heavy spike in trailing 7 days (4 long, intense workouts)
        for day in [1, 2, 4, 6] {
            runs.append(makeRun(daysAgo: Double(day), distanceKm: 10.0, durationMinutes: 60.0, percentZone4: 0.50, type: "Intervals", now: now))
        }

        let assessment = ReadinessEvaluator.assess(runs: runs, now: now)
        XCTAssertEqual(assessment.state, .acuteFatigue)
        XCTAssertTrue(assessment.triggers.contains(where: {
            if case .acwrSpike = $0 { return true }
            return false
        }))

        // Cadence target should soften to baseline band
        let target = ReadinessModifier.adaptTarget("170-176", baselineCadence: 154, drillId: .strides, state: assessment.state)
        XCTAssertTrue(target.isCadenceRelaxed)
        XCTAssertEqual(target.targetCadence, "151-157")
    }

    func testAcuteFatigueFromConsecutiveHardDays() {
        let now = Date()
        var runs: [ReadinessRunSnapshot] = []
        // Consistent baseline over past 3 weeks
        for day in [8, 11, 14, 17, 20, 23] {
            runs.append(makeRun(daysAgo: Double(day), distanceKm: 5.0, durationMinutes: 30.0, now: now))
        }
        // Two consecutive days in Zone 4/5 within last 48 hours
        runs.append(makeRun(daysAgo: 2, distanceKm: 8.0, durationMinutes: 45.0, percentZone4: 0.40, type: "Tempo Run", now: now))
        runs.append(makeRun(daysAgo: 1, distanceKm: 8.0, durationMinutes: 45.0, percentZone4: 0.45, type: "Intervals", now: now))

        let assessment = ReadinessEvaluator.assess(runs: runs, now: now)
        XCTAssertEqual(assessment.state, .acuteFatigue)
        XCTAssertTrue(assessment.triggers.contains(.consecutiveHardDays))
    }

    func testAcuteFatigueFromCadenceFadeTelemetry() {
        let now = Date()
        var runs: [ReadinessRunSnapshot] = []
        for day in [8, 12, 16, 20] {
            runs.append(makeRun(daysAgo: Double(day), distanceKm: 5.0, durationMinutes: 30.0, now: now))
        }
        // Last two runs both exhibit cadence turnover decay
        runs.append(makeRun(daysAgo: 3, distanceKm: 7.0, durationMinutes: 40.0, tags: [FramboiseReadinessTag.cadenceFade], now: now))
        runs.append(makeRun(daysAgo: 1, distanceKm: 7.0, durationMinutes: 40.0, tags: [FramboiseReadinessTag.cadenceFade], now: now))

        let assessment = ReadinessEvaluator.assess(runs: runs, now: now)
        XCTAssertEqual(assessment.state, .acuteFatigue)
        XCTAssertTrue(assessment.triggers.contains(.cadenceFade))
    }

    func testAcuteFatigueFromCardiacDrift() {
        let now = Date()
        var runs: [ReadinessRunSnapshot] = []
        for day in [8, 12, 16, 20] {
            runs.append(makeRun(daysAgo: Double(day), distanceKm: 5.0, durationMinutes: 30.0, now: now))
        }
        runs.append(makeRun(daysAgo: 1, distanceKm: 8.0, durationMinutes: 50.0, tags: [FramboiseReadinessTag.cardiacDrift], now: now))

        let assessment = ReadinessEvaluator.assess(runs: runs, now: now)
        XCTAssertEqual(assessment.state, .acuteFatigue)
        XCTAssertTrue(assessment.triggers.contains(.cardiacDrift))
    }

    func testDeloadWeekModulation() {
        let now = Date()
        var runs: [ReadinessRunSnapshot] = []
        // Trailing 3 weeks: high mileage (30 km/week)
        for day in [8, 10, 12, 15, 17, 19, 22, 24, 26] {
            runs.append(makeRun(daysAgo: Double(day), distanceKm: 10.0, durationMinutes: 60.0, percentZone4: 0.15, now: now))
        }
        // Acute 7 days: volume drops by 35% (only 2 easy runs, 8 km total, 0% Zone 4)
        runs.append(makeRun(daysAgo: 4, distanceKm: 4.0, durationMinutes: 25.0, percentZone4: 0.0, type: "Easy Run", now: now))
        runs.append(makeRun(daysAgo: 2, distanceKm: 4.0, durationMinutes: 25.0, percentZone4: 0.0, type: "Easy Run", now: now))

        let assessment = ReadinessEvaluator.assess(runs: runs, now: now)
        XCTAssertEqual(assessment.state, .deload)
        XCTAssertTrue(assessment.triggers.contains(where: {
            if case .mileageDeload = $0 { return true }
            return false
        }))

        // Cadence target PRESERVED during deload
        let target = ReadinessModifier.adaptTarget("170-176", baselineCadence: 154, drillId: .strides, state: assessment.state)
        XCTAssertFalse(target.isCadenceRelaxed)
        XCTAssertEqual(target.targetCadence, "170-176")

        // PreRunDrill should scale volume by half and extend recovery by 1.5x
        let drill = PreRunDrill(
            id: .strides,
            previousCadence: 154,
            targetCadence: "170-176",
            duration: .fifteenMinutes,
            readinessState: .deload
        )
        // Standard Strides 15min: 6 x 20 sec, 60 sec walk
        // Deload: 3 x 20 sec, 90 sec walk
        XCTAssertEqual(drill.intervalSpec.iterations, 3)
        XCTAssertEqual(drill.intervalSpec.workSeconds, 20)
        XCTAssertEqual(drill.intervalSpec.recoverySeconds, 90)
        XCTAssertEqual(drill.defaultWorkString, "3 x 20 sec strides")
        XCTAssertEqual(drill.defaultRecoveryString, "90 sec walk recovery")
    }

    func testContinuousDrillsExemption() {
        let drills: [PreRunDrillId] = [.aerobicFlush, .recoveryJog, .zone2Run]
        for drillId in drills {
            XCTAssertFalse(ReadinessState.acuteFatigue.applies(to: drillId))
            XCTAssertFalse(ReadinessState.deload.applies(to: drillId))
            let drill = PreRunDrill(id: drillId, previousCadence: 150, duration: .tenMinutes, readinessState: .acuteFatigue)
            XCTAssertNil(drill.readinessAdjustedIntervalSpec)
        }
    }

    // MARK: - ActiveDrillReadoutItem Integration & Watch Parity

    func testActiveDrillReadoutItemAdaptiveFidelity() {
        let now = Date()
        var runs: [ReadinessRunSnapshot] = []
        for day in [8, 12, 16, 20] {
            runs.append(makeRun(daysAgo: Double(day), distanceKm: 5.0, durationMinutes: 30.0, now: now))
        }
        runs.append(makeRun(daysAgo: 1, distanceKm: 8.0, durationMinutes: 50.0, tags: [FramboiseReadinessTag.cardiacDrift], now: now))

        let readiness = ReadinessEvaluator.assess(runs: runs, now: now)
        XCTAssertEqual(readiness.state, .acuteFatigue)

        let standardDTO = DrillPrescriptionDTO(
            title: "Strides",
            preRunDrillId: PreRunDrillId.strides.rawValue,
            purpose: "Wake up your legs",
            targetCadence: "170-176",
            previousCadence: 155,
            durationMinutes: 15
        )

        let item = ActiveDrillReadoutItem.adaptive(dto: standardDTO, readiness: readiness)

        // Readout UI verification
        XCTAssertTrue(item.readout.isReadinessAdjusted)
        XCTAssertEqual(item.readout.readinessState, .acuteFatigue)
        XCTAssertEqual(item.readout.standardTargetCadence, "170-176 SPM")
        XCTAssertEqual(item.readout.targetCadence, "152-158 SPM")
        XCTAssertEqual(item.readout.adaptedWork, "3 x 20 sec strides")
        XCTAssertNotNil(item.readout.readinessContext)

        // DTO carrying state for Watch export
        XCTAssertEqual(item.dto.readinessState, ReadinessState.acuteFatigue.rawValue)
        XCTAssertEqual(item.dto.targetCadence, "152-158")

        // Phase timeline parity
        let workPhases = item.readout.phases.filter { $0.kind == .work }
        XCTAssertEqual(workPhases.count, 3)
    }

    // MARK: - Framboise Telemetry Detectors

    func testFramboiseCadenceFadeDetection() async {
        let engine = FramboiseEngine()
        let now = Date()

        // 12 buckets: first 8 at 168 SPM, last 4 drop to 160 SPM
        var buckets: [BucketData] = []
        for idx in 0..<8 {
            buckets.append(BucketData(
                startTime: now.addingTimeInterval(Double(idx * 60)),
                distanceMeters: 200,
                durationSeconds: 60,
                meanPaceSecPerKm: 300,
                meanCadence: 168.0,
                meanHR: 145.0
            ))
        }
        for idx in 8..<12 {
            buckets.append(BucketData(
                startTime: now.addingTimeInterval(Double(idx * 60)),
                distanceMeters: 200,
                durationSeconds: 60,
                meanPaceSecPerKm: 305,
                meanCadence: 160.0,
                meanHR: 147.0
            ))
        }

        let isFaded = await engine.detectCadenceFade(buckets: buckets)
        XCTAssertTrue(isFaded)

        let tags = await engine.generateFramboiseTags(cv: 0.05, slope: 0.01, deadStopsCount: 0, buckets: buckets)
        XCTAssertTrue(tags.contains("cadenceFade"))
    }

    func testFramboiseCardiacDriftDetection() async {
        let engine = FramboiseEngine()
        let now = Date()

        // 12 buckets: pace remains constant at 300 s/km, HR climbs from 135 to 148 BPM
        var buckets: [BucketData] = []
        for idx in 0..<12 {
            let hr = 135.0 + Double(idx) * 1.2
            buckets.append(BucketData(
                startTime: now.addingTimeInterval(Double(idx * 60)),
                distanceMeters: 200,
                durationSeconds: 60,
                meanPaceSecPerKm: 300.0,
                meanCadence: 162.0,
                meanHR: hr
            ))
        }

        let isDrift = await engine.detectCardiacDrift(buckets: buckets, paceSlope: 0.0)
        XCTAssertTrue(isDrift)

        let tags = await engine.generateFramboiseTags(cv: 0.02, slope: 0.0, deadStopsCount: 0, buckets: buckets)
        XCTAssertTrue(tags.contains("cardiacDrift"))
    }

    // MARK: - Streak & Volume Compression Tests

    @MainActor
    private func makeTestRunRecord(
        date: Date,
        durationMinutes: Double,
        distanceMeters: Double = 7000,
        workingAvgCadence: Double = 160,
        workingAvgHeartRate: Double = 145,
        percentZone4: Double = 0.05,
        detectedTypeRaw: String = "Easy Run"
    ) -> RunRecord {
        RunRecord(
            hkWorkoutID: UUID(),
            date: date,
            totalDistanceMeters: distanceMeters,
            duration: durationMinutes * 60,
            rawAvgPace: 400,
            rawAvgHeartRate: workingAvgHeartRate,
            rawAvgCadence: workingAvgCadence,
            workingAvgPace: 400,
            workingAvgCadence: workingAvgCadence,
            workingAvgHeartRate: workingAvgHeartRate,
            paceCV: 0.04,
            paceSlope: 0.0,
            percentZone4: percentZone4,
            detectedTypeRaw: detectedTypeRaw
        )
    }

    @MainActor
    func testStreakAndVolumeSummary_TwoConsecutiveDays_TriggersRestDayForIntermediate() {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return }

        // 4-week historical volume: 3 runs/week of 50 min = 150 min/wk baseline
        var history: [RunRecord] = []
        for d in [4, 7, 10, 14, 17, 21, 24] {
            if let pastDate = calendar.date(byAdding: .day, value: -d, to: today) {
                history.append(makeTestRunRecord(
                    date: pastDate,
                    durationMinutes: 50,
                    distanceMeters: 7000,
                    workingAvgCadence: 160,
                    workingAvgHeartRate: 145
                ))
            }
        }

        // Mon: 55m, Tue: 60m = 115m total in 48h
        let monRun = makeTestRunRecord(
            date: yesterday,
            durationMinutes: 55,
            distanceMeters: 8000,
            workingAvgCadence: 155,
            workingAvgHeartRate: 138,
            detectedTypeRaw: "Steady Effort"
        )
        let tueRun = makeTestRunRecord(
            date: today,
            durationMinutes: 60,
            distanceMeters: 9000,
            workingAvgCadence: 155,
            workingAvgHeartRate: 150,
            detectedTypeRaw: "Easy Run"
        )

        let allRuns = [tueRun, monRun] + history
        let summary = StreakAndVolumeSummary.evaluate(
            runs: allRuns,
            experienceLevel: "Intermediate",
            trainingGoal: "General Fitness",
            now: now
        )

        XCTAssertTrue(summary.shouldRecommendRestDay, "115m in 48h against ~150m/wk baseline must trigger rest for Intermediate")
        XCTAssertEqual(summary.consecutiveRunDays, 2)
        XCTAssertGreaterThan(summary.volumeRatio48h, summary.volumeCompressionThreshold)
        XCTAssertNotNil(summary.restDayReason)
        XCTAssertTrue(summary.restDayReason?.contains("48-Hour Volume Compression") ?? false)
    }

    @MainActor
    func testStreakAndVolumeSummary_AdvancedRunnerWithHighVolume_DoesNotPrematurelyTriggerRest() {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return }

        // Advanced marathoner: 300 min/week baseline
        var history: [RunRecord] = []
        for d in [3, 5, 8, 11, 14, 18, 22, 25] {
            if let pastDate = calendar.date(byAdding: .day, value: -d, to: today) {
                history.append(makeTestRunRecord(
                    date: pastDate,
                    durationMinutes: 75,
                    distanceMeters: 12000,
                    workingAvgCadence: 168,
                    workingAvgHeartRate: 145
                ))
            }
        }

        // 2 days of modest volume: 45m + 45m = 90m (30% of baseline)
        let run1 = makeTestRunRecord(
            date: yesterday,
            durationMinutes: 45,
            distanceMeters: 8000,
            workingAvgCadence: 168,
            workingAvgHeartRate: 140
        )
        let run2 = makeTestRunRecord(
            date: today,
            durationMinutes: 45,
            distanceMeters: 8000,
            workingAvgCadence: 168,
            workingAvgHeartRate: 142
        )

        let allRuns = [run2, run1] + history
        let summary = StreakAndVolumeSummary.evaluate(
            runs: allRuns,
            experienceLevel: "Advanced",
            trainingGoal: "Marathon",
            now: now
        )

        XCTAssertFalse(summary.shouldRecommendRestDay, "Advanced marathoner running 2 moderate days should not be forced into rest")
        XCTAssertEqual(summary.consecutiveRunDays, 2)
    }

    func testShortPrimers_DoNotTriggerConsecutiveHardDays() {
        let now = Date()
        // Two consecutive days with short 10-minute Pre-Run Primers (0% Zone 4)
        let primer1 = makeRun(daysAgo: 1, distanceKm: 1.5, durationMinutes: 10.0, percentZone4: 0.0, type: "Strides", tags: ["prescribedDrill"], now: now)
        let primer2 = makeRun(daysAgo: 0.1, distanceKm: 1.5, durationMinutes: 10.0, percentZone4: 0.0, type: "Cadence Pyramids", tags: ["prescribedDrill"], now: now)

        XCTAssertFalse(primer1.isHardSession, "Short primer drill must not count as hard session")
        XCTAssertFalse(primer2.isHardSession, "Short primer drill must not count as hard session")

        let assessment = ReadinessEvaluator.assess(runs: [primer2, primer1], now: now)
        XCTAssertFalse(assessment.triggers.contains(.consecutiveHardDays), "Primers must not trigger consecutive hard days")
    }
}
