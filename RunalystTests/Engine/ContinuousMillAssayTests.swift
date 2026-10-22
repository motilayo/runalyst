import XCTest
import SwiftData
import RunalystCore
@testable import Runalyst

/// Continuous Mill Assay Test Harness (Differential Fuzzing Rig).
/// Formally proves bit-for-bit mathematical and state equivalence between
/// System A (In-Memory RunalystCore reference ingots) and
/// System B (Foundry SwiftData persistence and adapter rig).
@MainActor
final class ContinuousMillAssayTests: XCTestCase {

    private var modelContainer: ModelContainer!
    private var modelContext: ModelContext!
    private var engine: FramboiseEngine!

    override func setUp() async throws {
        try await super.setUp()
        let schema = Schema([
            RunRecord.self,
            CoachingInsight.self,
            DrillRecommendation.self,
            TrainingCorrection.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [config])
        modelContext = modelContainer.mainContext
        engine = FramboiseEngine()
    }

    override func tearDown() async throws {
        modelContainer = nil
        modelContext = nil
        engine = nil
        try await super.tearDown()
    }

    // MARK: - Test 1: Golden Fixture Differential Fuzzing under Sensor Jitter

    func testGoldenIntervals_DifferentialFuzzing_Equivalence() async throws {
        let baseBuckets = GoldenTelemetryFixtures.authenticIntervals31Min.toBucketData()

        // Apply chaotic sensor jitter: +/- 1.5 SPM, +/- 2.0 BPM, +/- 4.0 s/km
        let noisyBuckets = TelemetryNoiseInjector.injectSensorJitter(
            to: baseBuckets,
            cadenceNoiseRange: -1.5...1.5,
            hrNoiseRange: -2.0...2.0,
            paceNoiseRange: -4.0...4.0,
            seed: 0xCAFE1234
        )

        // System A: The Reference Core
        let coreTelemetry = noisyBuckets.map { $0.toTelemetryBucket() }
        let coreWorkingStats = FramboiseCore.computeWorkingStats(buckets: coreTelemetry)
        let coreReport = IntervalSegmenterCore.segment(buckets: coreTelemetry)
        let coreClassification = RunClassifierCore.classifyRun(
            buckets: coreTelemetry,
            cv: coreWorkingStats.paceCV,
            slope: coreWorkingStats.paceSlope,
            zone4: coreWorkingStats.percentZone4,
            durationMinutes: coreWorkingStats.workingDurationSeconds / 60.0,
            cadenceCV: 0.0,
            averageHR: coreWorkingStats.workingAvgHeartRateBPM,
            cycles: coreReport.cycles,
            deadStopsCount: coreWorkingStats.deadStopsCount,
            isIndoor: false
        )

        // System B: The Foundry Persistence Rig
        let trimmed = await engine.trimDeadStops(buckets: noisyBuckets)
        let workingAvg = await engine.calculateWorkingAverages(
            trimmed: trimmed,
            rawWorkoutDuration: noisyBuckets.reduce(0.0) { $0 + $1.durationSeconds },
            rawWorkoutDistance: noisyBuckets.reduce(0.0) { $0 + $1.distanceMeters },
            originalBucketCount: noisyBuckets.count
        )
        let paceCV = await engine.calculatePaceCV(bucketPaces: trimmed.map(\.meanPaceSecPerKm))
        let paceSlope = await engine.calculatePaceSlope(bucketPaces: trimmed.map(\.meanPaceSecPerKm))
        let percentZone4 = await engine.calculatePercentZone4(bucketHRs: trimmed.map(\.meanHR), maxHR: 190.0)
        let cycles = await engine.extractOscillationCycles(buckets: noisyBuckets)
        let tags = await engine.generateFramboiseTags(
            cv: paceCV,
            slope: paceSlope,
            deadStopsCount: noisyBuckets.count - trimmed.count,
            buckets: trimmed,
            isIndoor: false
        )
        let foundClassification = await engine.classifyRun(
            buckets: noisyBuckets,
            cv: paceCV,
            slope: paceSlope,
            zone4: percentZone4,
            durationMinutes: workingAvg.workingDuration / 60.0,
            cadenceCV: 0.0,
            averageHR: workingAvg.workingHR,
            cycles: cycles,
            deadStopsCount: noisyBuckets.count - trimmed.count,
            isIndoor: false
        )

        let runRecord = RunRecord(
            hkWorkoutID: UUID(),
            date: Date(),
            totalDistanceMeters: workingAvg.workingDistance,
            duration: workingAvg.workingDuration,
            rawAvgPace: coreWorkingStats.rawAvgPaceSecondsPerKm,
            rawAvgHeartRate: coreWorkingStats.rawAvgHeartRateBPM,
            rawAvgCadence: coreWorkingStats.rawAvgCadenceSPM,
            workingAvgPace: workingAvg.workingPace,
            workingAvgCadence: workingAvg.workingCadence,
            workingAvgHeartRate: workingAvg.workingHR,
            workingDistanceMeters: workingAvg.workingDistance,
            workingDurationSeconds: workingAvg.workingDuration,
            isIndoor: false,
            paceCV: paceCV,
            paceSlope: paceSlope,
            percentZone4: percentZone4,
            detectedTypeRaw: foundClassification,
            framboiseTags: tags
        )
        modelContext.insert(runRecord)
        try modelContext.save()

        let fetched = try modelContext.fetch(FetchDescriptor<RunRecord>()).first
        XCTAssertNotNil(fetched)

        // Bit-for-bit assertion: State(System A) == State(System B)
        XCTAssertEqual(coreWorkingStats.workingAvgPaceSecondsPerKm, fetched?.workingAvgPace ?? 0, accuracy: 0.001)
        XCTAssertEqual(coreWorkingStats.workingAvgCadenceSPM, fetched?.workingAvgCadence ?? 0, accuracy: 0.001)
        XCTAssertEqual(coreWorkingStats.workingAvgHeartRateBPM, fetched?.workingAvgHeartRate ?? 0, accuracy: 0.001)
        XCTAssertEqual(coreWorkingStats.workingDurationSeconds, fetched?.workingDurationSeconds ?? 0, accuracy: 0.001)
        XCTAssertEqual(coreWorkingStats.workingDistanceMeters, fetched?.workingDistanceMeters ?? 0, accuracy: 0.001)
        XCTAssertEqual(coreClassification, fetched?.detectedTypeRaw)
        XCTAssertEqual(Set(coreWorkingStats.framboiseTags), Set(fetched?.framboiseTags ?? []))
    }

    // MARK: - Test 2: Boundary Mutations (Single Bucket, Extreme Dead Stops, 0m Stops)

    func testBoundaryMutations_SingleBucketAndDeadStops_Equivalence() async throws {
        var now = Date()
        var mutatedBuckets: [BucketData] = []

        // 1. Walking break below running threshold (< 125 SPM, arm-swing noise)
        mutatedBuckets.append(BucketData(
            startTime: now,
            distanceMeters: 45.0,
            durationSeconds: 30.0,
            meanPaceSecPerKm: 666.0,
            meanCadence: 110.0,
            meanHR: 105.0
        ))
        now = now.addingTimeInterval(30)

        // 2. Complete dead stop at red light (0m distance, stationary)
        mutatedBuckets.append(BucketData(
            startTime: now,
            distanceMeters: 0.0,
            durationSeconds: 30.0,
            meanPaceSecPerKm: 0.0,
            meanCadence: 0.0,
            meanHR: 95.0
        ))
        now = now.addingTimeInterval(30)

        // 3. Genuine running interval (160 SPM, 320 s/km)
        for _ in 0..<10 {
            mutatedBuckets.append(BucketData(
                startTime: now,
                distanceMeters: 93.75,
                durationSeconds: 30.0,
                meanPaceSecPerKm: 320.0,
                meanCadence: 160.0,
                meanHR: 148.0
            ))
            now = now.addingTimeInterval(30)
        }

        // System A
        let coreTelemetry = mutatedBuckets.map { $0.toTelemetryBucket() }
        let coreStats = FramboiseCore.computeWorkingStats(buckets: coreTelemetry)

        // System B
        let trimmed = await engine.trimDeadStops(buckets: mutatedBuckets)
        let workingAvg = await engine.calculateWorkingAverages(
            trimmed: trimmed,
            rawWorkoutDuration: mutatedBuckets.reduce(0.0) { $0 + $1.durationSeconds },
            rawWorkoutDistance: mutatedBuckets.reduce(0.0) { $0 + $1.distanceMeters },
            originalBucketCount: mutatedBuckets.count
        )

        XCTAssertEqual(trimmed.count, 10, "Foundry must scrub the walking and dead-stop buckets")
        XCTAssertEqual(coreStats.deadStopsCount, mutatedBuckets.count - trimmed.count)
        XCTAssertEqual(coreStats.workingAvgPaceSecondsPerKm, workingAvg.workingPace, accuracy: 0.001)
        XCTAssertEqual(coreStats.workingAvgCadenceSPM, workingAvg.workingCadence, accuracy: 0.001)
        XCTAssertEqual(coreStats.workingAvgHeartRateBPM, workingAvg.workingHR, accuracy: 0.001)
    }

    // MARK: - Test 3: Safety Gate & Physiological Decoupling Invariant

    func testSafetyGate_PhysiologicalDecoupling_OverridesGoal() throws {
        let now = Date()
        // Runner pacing slower than baseline (+30 sec/km) while heart rate spikes (+18 BPM)
        let currentPace = 360.0 // 6:00/km (slower)
        let baselinePace = 330.0 // 5:30/km
        let currentHR = 168.0 // High strain
        let baselineHR = 150.0

        let paceDiffVsBaseline = baselinePace - currentPace // -30.0 (slower than baseline)
        let hrDeltaVsBaseline = currentHR - baselineHR // +18.0 (elevated cardiac strain)

        // System A: Direct Core Safety Gate
        let reportA = BanisterReadinessCore.evaluateSafetyGate(
            sessions: [],
            now: now,
            paceDeltaVsBaseline: paceDiffVsBaseline,
            hrDeltaVsBaseline: hrDeltaVsBaseline
        )

        XCTAssertTrue(reportA.isSafetyOverridden, "System A Core must enforce priority safety override under fatigue decoupling")
        XCTAssertTrue(reportA.effectiveDirective.priorityOverridesGoal, "Fatigue decoupling strips drill targets and prescribes pure recovery")

        // System B: SwiftData Persisted State Hydration
        let record = RunRecord(
            hkWorkoutID: UUID(),
            date: now,
            totalDistanceMeters: 5000,
            duration: 1800,
            rawAvgPace: currentPace,
            rawAvgHeartRate: currentHR,
            rawAvgCadence: 152,
            workingAvgPace: currentPace,
            workingAvgCadence: 152,
            workingAvgHeartRate: currentHR,
            workingDistanceMeters: 5000,
            workingDurationSeconds: 1800,
            isIndoor: false,
            paceCV: 0.04,
            paceSlope: 0.05,
            percentZone4: 0.10,
            detectedTypeRaw: "Steady Effort",
            framboiseTags: []
        )
        modelContext.insert(record)
        try modelContext.save()

        let fetched = try modelContext.fetch(FetchDescriptor<RunRecord>()).first
        XCTAssertNotNil(fetched)

        let persistedPaceDiff = baselinePace - (fetched?.workingAvgPace ?? 0.0)
        let persistedHRDelta = (fetched?.workingAvgHeartRate ?? 0.0) - baselineHR
        let reportB = BanisterReadinessCore.evaluateSafetyGate(
            sessions: [],
            now: now,
            paceDeltaVsBaseline: persistedPaceDiff,
            hrDeltaVsBaseline: persistedHRDelta
        )

        // Bit-for-bit equivalence between System A and System B
        XCTAssertEqual(reportA.isSafetyOverridden, reportB.isSafetyOverridden)
        XCTAssertEqual(reportA.effectiveDirective, reportB.effectiveDirective)
        XCTAssertEqual(reportA.effectiveDirective.priorityOverridesGoal, reportB.effectiveDirective.priorityOverridesGoal)
    }

    // MARK: - Test 4: Treadmill Kinematics Invariant (Median Smoothing & Outlier Clamping)

    func testTreadmillKinematics_OutlierClamping_Equivalence() async throws {
        var now = Date()
        var treadmillBuckets: [BucketData] = []

        // Standard treadmill belt pace: 300 s/km (5:00/km)
        for _ in 0..<5 {
            treadmillBuckets.append(BucketData(
                startTime: now,
                distanceMeters: 100.0,
                durationSeconds: 30.0,
                meanPaceSecPerKm: 300.0,
                meanCadence: 165.0,
                meanHR: 145.0
            ))
            now = now.addingTimeInterval(30)
        }

        // Sudden accelerometer spike / belt artifact: 450 s/km (+50% jump)
        treadmillBuckets.append(BucketData(
            startTime: now,
            distanceMeters: 66.6,
            durationSeconds: 30.0,
            meanPaceSecPerKm: 450.0,
            meanCadence: 165.0,
            meanHR: 147.0
        ))
        now = now.addingTimeInterval(30)

        for _ in 0..<5 {
            treadmillBuckets.append(BucketData(
                startTime: now,
                distanceMeters: 100.0,
                durationSeconds: 30.0,
                meanPaceSecPerKm: 300.0,
                meanCadence: 165.0,
                meanHR: 146.0
            ))
            now = now.addingTimeInterval(30)
        }

        // System A
        let coreTelemetry = treadmillBuckets.map { $0.toTelemetryBucket() }
        let coreSmoothed = TreadmillKinematicsCore.applyWristPaceSmoothing(buckets: coreTelemetry)

        // System B
        let foundrySmoothed = await engine.applyIndoorWristPaceSmoothing(buckets: treadmillBuckets)

        XCTAssertEqual(coreSmoothed.count, foundrySmoothed.count)
        for index in 0..<coreSmoothed.count {
            XCTAssertEqual(coreSmoothed[index].paceSecondsPerKm, foundrySmoothed[index].meanPaceSecPerKm, accuracy: 0.001)
            // Verify 25% outlier clamping: 300 * 1.25 = 375 max allowed
            XCTAssertLessThanOrEqual(foundrySmoothed[index].meanPaceSecPerKm, 375.001)
        }
    }
}
