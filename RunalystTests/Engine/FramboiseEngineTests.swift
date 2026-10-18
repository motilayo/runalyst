import XCTest
@testable import Runalyst

final class FramboiseEngineTests: XCTestCase {
    var engine: FramboiseEngine!

    override func setUp() async throws {
        engine = FramboiseEngine()
    }

    func testTrimDeadStops() async {
        let buckets = [
            BucketData(startTime: Date(), distanceMeters: 0, meanPaceSecPerKm: 0, meanCadence: 0, meanHR: 100),
            BucketData(startTime: Date(), distanceMeters: 100, meanPaceSecPerKm: 300, meanCadence: 160, meanHR: 140),
            BucketData(startTime: Date(), distanceMeters: 0.1, meanPaceSecPerKm: 0, meanCadence: 20, meanHR: 120)
        ]

        let trimmed = await engine.trimDeadStops(buckets: buckets)
        XCTAssertEqual(trimmed.count, 1)
        XCTAssertEqual(trimmed[0].distanceMeters, 100)
    }

    func testCalculateWorkingAverages() async {
        let buckets = [
            BucketData(startTime: Date(), distanceMeters: 200, meanPaceSecPerKm: 300, meanCadence: 160, meanHR: 140),
            BucketData(startTime: Date(), distanceMeters: 200, meanPaceSecPerKm: 300, meanCadence: 164, meanHR: 144)
        ]

        let averages = await engine.calculateWorkingAverages(trimmed: buckets)
        XCTAssertEqual(averages.workingCadence, 162)
        XCTAssertEqual(averages.workingHR, 142)
        XCTAssertEqual(averages.workingDistance, 400, accuracy: 0.01)
        XCTAssertEqual(averages.workingDuration, 120, accuracy: 0.01)
        // 400 meters in 120 seconds -> 120 / 0.4 = 300 sec/km
        XCTAssertEqual(averages.workingPace, 300, accuracy: 0.01)
    }

    func testCalculateWorkingAverages_VerticalOscillationExcludesZeroBuckets() async {
        let buckets = [
            BucketData(startTime: Date(), distanceMeters: 200, meanPaceSecPerKm: 300, meanCadence: 160, meanHR: 140, meanVerticalOscillation: 8.8),
            BucketData(startTime: Date(), distanceMeters: 200, meanPaceSecPerKm: 300, meanCadence: 164, meanHR: 144, meanVerticalOscillation: 0.0), // no sample this minute
            BucketData(startTime: Date(), distanceMeters: 200, meanPaceSecPerKm: 300, meanCadence: 162, meanHR: 142, meanVerticalOscillation: 9.2)
        ]

        let averages = await engine.calculateWorkingAverages(trimmed: buckets)
        // Only the two non-zero buckets (8.8 and 9.2) should be averaged -> 9.0, not (8.8 + 0 + 9.2) / 3 = 6.0
        XCTAssertEqual(averages.workingOscillation, 9.0, accuracy: 0.01)
    }

    func testCalculateWorkingAverages_StrideLengthAveragingAndFallback() async {
        let buckets = [
            BucketData(startTime: Date(), distanceMeters: 200, meanPaceSecPerKm: 300, meanCadence: 160, meanHR: 140, meanStrideLength: 1.10),
            BucketData(startTime: Date(), distanceMeters: 200, meanPaceSecPerKm: 300, meanCadence: 164, meanHR: 144, meanStrideLength: 0.0), // zero sample
            BucketData(startTime: Date(), distanceMeters: 200, meanPaceSecPerKm: 300, meanCadence: 162, meanHR: 142, meanStrideLength: 1.30)
        ]

        let averages = await engine.calculateWorkingAverages(trimmed: buckets)
        // (1.10 + 1.30) / 2 = 1.20
        if let workingStride = averages.workingStrideLength {
            XCTAssertEqual(workingStride, 1.20, accuracy: 0.01)
        } else {
            XCTFail("workingStrideLength should not be nil")
        }

        // Fully active inherits raw stride
        let fullyActiveAverages = await engine.calculateWorkingAverages(
            trimmed: buckets,
            rawWorkoutDuration: 180,
            rawWorkoutDistance: 600,
            originalBucketCount: 3,
            rawAvgStrideLength: 1.22
        )
        XCTAssertEqual(fullyActiveAverages.workingStrideLength, 1.22)
    }

    func testFilterRunningSamples_DropsStationaryAndWalking() async {
        let buckets = [
            // Stationary: 0 m/s, 0 SPM -> Drop
            BucketData(startTime: Date(), distanceMeters: 0, meanPaceSecPerKm: 0, meanCadence: 0, meanHR: 90),
            // Walking break: 60m in 60s = 1.0 m/s (< 1.5), cadence 105 (< 130) -> Drop
            BucketData(startTime: Date(), distanceMeters: 60, meanPaceSecPerKm: 1000, meanCadence: 105, meanHR: 110),
            // Running by speed: 120m in 60s = 2.0 m/s (> 1.5), cadence 125 -> Keep
            BucketData(startTime: Date(), distanceMeters: 120, meanPaceSecPerKm: 500, meanCadence: 125, meanHR: 145),
            // Running by cadence: 80m in 60s = 1.33 m/s, cadence 150 (> 130) -> Keep
            BucketData(startTime: Date(), distanceMeters: 80, meanPaceSecPerKm: 750, meanCadence: 150, meanHR: 140)
        ]

        let filtered = await engine.filterRunningSamples(buckets: buckets)
        XCTAssertEqual(filtered.count, 2)
        XCTAssertEqual(filtered[0].distanceMeters, 120)
        XCTAssertEqual(filtered[1].distanceMeters, 80)
    }

    func testCalculateWorkingAverages_EnforcesDurationSafetyConstraint() async {
        let buckets = [
            BucketData(startTime: Date(), distanceMeters: 200, meanPaceSecPerKm: 300, meanCadence: 160, meanHR: 140),
            BucketData(startTime: Date(), distanceMeters: 200, meanPaceSecPerKm: 300, meanCadence: 160, meanHR: 140)
        ]
        // 2 buckets = 120 seconds, but raw workout duration was 100 seconds
        let averages = await engine.calculateWorkingAverages(trimmed: buckets, rawWorkoutDuration: 100)
        XCTAssertEqual(averages.workingDuration, 100, "workingDuration must be <= rawWorkoutDuration")
    }

    func testCalculateWorkingAverages_PureAggregateRatioPace() async {
        // Harmonic distortion check:
        // Bucket 1: 100m in 60s (pace = 600 s/km)
        // Bucket 2: 300m in 60s (pace = 200 s/km)
        // Arithmetic mean of paces = (600 + 200) / 2 = 400 s/km (WRONG)
        // Aggregate ratio = 120s / 0.4km = 300 s/km (CORRECT)
        let buckets = [
            BucketData(startTime: Date(), distanceMeters: 100, meanPaceSecPerKm: 600, meanCadence: 150, meanHR: 130),
            BucketData(startTime: Date(), distanceMeters: 300, meanPaceSecPerKm: 200, meanCadence: 170, meanHR: 160)
        ]
        let averages = await engine.calculateWorkingAverages(trimmed: buckets)
        XCTAssertEqual(averages.workingPace, 300, accuracy: 0.01, "workingPace must use pure aggregate ratio (duration / distanceKm)")
    }

    func testCalculatePaceCV() async {
        let paces = [300.0, 300.0, 300.0, 300.0]
        let calculatedCV = await engine.calculatePaceCV(bucketPaces: paces)
        XCTAssertEqual(calculatedCV, 0, accuracy: 0.001)

        let variablePaces = [200.0, 400.0]
        let calculatedCV2 = await engine.calculatePaceCV(bucketPaces: variablePaces)
        // mean = 300. variance = sum((x-300)^2) / 1 = 10000 + 10000 = 20000. sigma = sqrt(20000) ~ 141.42
        // CV = 141.42 / 300 = 0.471
        XCTAssertEqual(calculatedCV2, 0.471, accuracy: 0.01)
    }

    func testCalculatePaceSlope() async {
        let paces = [300.0, 310.0, 320.0, 330.0]
        let slope = await engine.calculatePaceSlope(bucketPaces: paces)
        // Increasing by 10 per bucket -> slope = +10
        XCTAssertEqual(slope, 10, accuracy: 0.01)

        let paces2 = [300.0, 290.0, 280.0, 270.0]
        let slope2 = await engine.calculatePaceSlope(bucketPaces: paces2)
        // Decreasing by 10 per bucket -> slope = -10
        XCTAssertEqual(slope2, -10, accuracy: 0.01)
    }

    // MARK: - Topological Signature Classification Tests (ADR-0003)

    func testSept24IncidentReplay_SteadyEffortWithWarmupAndFadeNotFartlek() async {
        // September 24 incident replay: 32:46 run with warmup -> cruise -> fade arc
        // cv ≈ 0.08, cadenceCV ≈ 0.028 (which falsely crossed legacy scalar thresholds)
        // With topological signature analysis, 0 or 1 alternating cycles exist -> Steady Effort!
        var buckets: [BucketData] = []
        var currentTime = Date()

        // 1. Warmup (5 min = 10 30-second buckets): ~451 s/km (7'31"), 150 SPM, 135 HR
        for _ in 0..<10 {
            buckets.append(BucketData(
                startTime: currentTime,
                distanceMeters: 66.5,
                durationSeconds: 30.0,
                meanPaceSecPerKm: 451.0,
                meanCadence: 150.0,
                meanHR: 135.0
            ))
            currentTime = currentTime.addingTimeInterval(30.0)
        }

        // 2. Steady Cruise (20 min = 40 30-second buckets): ~402 s/km (6'42"), 156 SPM, 152 HR
        for _ in 0..<40 {
            buckets.append(BucketData(
                startTime: currentTime,
                distanceMeters: 74.6,
                durationSeconds: 30.0,
                meanPaceSecPerKm: 402.0,
                meanCadence: 156.0,
                meanHR: 152.0
            ))
            currentTime = currentTime.addingTimeInterval(30.0)
        }

        // 3. Late-Run Fatigue Fade (7 min = 14 30-second buckets): ~451 s/km (7'31"), 148 SPM, 155 HR
        for _ in 0..<14 {
            buckets.append(BucketData(
                startTime: currentTime,
                distanceMeters: 66.5,
                durationSeconds: 30.0,
                meanPaceSecPerKm: 451.0,
                meanCadence: 148.0,
                meanHR: 155.0
            ))
            currentTime = currentTime.addingTimeInterval(30.0)
        }

        let cycles = await engine.extractOscillationCycles(buckets: buckets)
        XCTAssertLessThan(cycles.count, 3, "Smooth continuous arc must produce < 3 oscillation cycles")

        let classification = await engine.classifyRun(
            buckets: buckets,
            cv: 0.08,
            slope: 0.0,
            zone4: 0.25,
            durationMinutes: 32.7,
            cadenceCV: 0.028,
            averageHR: 156.0
        )

        XCTAssertNotEqual(classification, "Fartlek", "Continuous warmup/cruise/fade run must NEVER be classified as Fartlek")
        XCTAssertNotEqual(classification, "Intervals", "Continuous warmup/cruise/fade run must NEVER be classified as Intervals")
        XCTAssertEqual(classification, "Steady Effort")
    }

    func testTrueFartlekClassification_IrregularSurges() async {
        // True Fartlek: 5 irregular surges of highly variable durations (30s, 120s, 45s, 180s, 30s)
        // alternating with variable recovery jogs (60s, 150s, 45s, 90s, 60s)
        var buckets: [BucketData] = []
        var currentTime = Date()

        // Warmup: 3 min (12 buckets of 15s) at 145 SPM, 480 s/km
        for _ in 0..<12 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 31.25, durationSeconds: 15, meanPaceSecPerKm: 480, meanCadence: 145, meanHR: 130))
            currentTime = currentTime.addingTimeInterval(15)
        }

        // Rep 1: 30s surge (2 buckets) at 178 SPM, 320 s/km, 165 HR; 60s rec (4 buckets) at 138 SPM, 500 s/km, 140 HR
        for _ in 0..<2 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 46.87, durationSeconds: 15, meanPaceSecPerKm: 320, meanCadence: 178, meanHR: 165))
            currentTime = currentTime.addingTimeInterval(15)
        }
        for _ in 0..<4 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 30.0, durationSeconds: 15, meanPaceSecPerKm: 500, meanCadence: 138, meanHR: 140))
            currentTime = currentTime.addingTimeInterval(15)
        }

        // Rep 2: 120s surge (8 buckets) at 176 SPM, 330 s/km, 168 HR; 150s rec (10 buckets) at 138 SPM, 510 s/km, 138 HR
        for _ in 0..<8 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 45.45, durationSeconds: 15, meanPaceSecPerKm: 330, meanCadence: 176, meanHR: 168))
            currentTime = currentTime.addingTimeInterval(15)
        }
        for _ in 0..<10 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 29.4, durationSeconds: 15, meanPaceSecPerKm: 510, meanCadence: 138, meanHR: 138))
            currentTime = currentTime.addingTimeInterval(15)
        }

        // Rep 3: 45s surge (3 buckets) at 178 SPM, 320 s/km, 166 HR; 45s rec (3 buckets) at 140 SPM, 500 s/km, 140 HR
        for _ in 0..<3 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 46.87, durationSeconds: 15, meanPaceSecPerKm: 320, meanCadence: 178, meanHR: 166))
            currentTime = currentTime.addingTimeInterval(15)
        }
        for _ in 0..<3 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 30.0, durationSeconds: 15, meanPaceSecPerKm: 500, meanCadence: 140, meanHR: 140))
            currentTime = currentTime.addingTimeInterval(15)
        }

        // Rep 4: 180s surge (12 buckets) at 174 SPM, 340 s/km, 167 HR; 90s rec (6 buckets) at 139 SPM, 500 s/km, 140 HR
        for _ in 0..<12 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 44.1, durationSeconds: 15, meanPaceSecPerKm: 340, meanCadence: 174, meanHR: 167))
            currentTime = currentTime.addingTimeInterval(15)
        }
        for _ in 0..<6 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 30.0, durationSeconds: 15, meanPaceSecPerKm: 500, meanCadence: 139, meanHR: 140))
            currentTime = currentTime.addingTimeInterval(15)
        }

        // Rep 5: 30s surge (2 buckets) at 180 SPM, 310 s/km, 168 HR; 60s rec (4 buckets) at 138 SPM, 500 s/km, 140 HR
        for _ in 0..<2 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 48.38, durationSeconds: 15, meanPaceSecPerKm: 310, meanCadence: 180, meanHR: 168))
            currentTime = currentTime.addingTimeInterval(15)
        }
        for _ in 0..<4 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 30.0, durationSeconds: 15, meanPaceSecPerKm: 500, meanCadence: 138, meanHR: 140))
            currentTime = currentTime.addingTimeInterval(15)
        }

        let cycles = await engine.extractOscillationCycles(buckets: buckets)
        XCTAssertGreaterThanOrEqual(cycles.count, 3, "True Fartlek must detect >= 3 oscillation cycles")

        let regularity = await engine.calculateCycleRegularity(cycles: cycles)
        XCTAssertLessThan(regularity, 0.65, "Irregular Fartlek surge durations must produce regularity < 0.65")

        let classification = await engine.classifyRun(
            buckets: buckets,
            cv: 0.13,
            slope: 0.0,
            zone4: 0.35,
            durationMinutes: 25.0,
            cadenceCV: 0.045,
            averageHR: 155.0
        )
        XCTAssertEqual(classification, "Fartlek")
    }

    func testStructuredIntervalsClassification_MetronomicReps() async {
        // Structured Intervals: 4 uniform reps (60s work, 60s recovery)
        var buckets: [BucketData] = []
        var currentTime = Date()

        for _ in 0..<4 {
            // Work: 60s (2 buckets of 30s) at 180 SPM, 300 s/km, 172 HR
            for _ in 0..<2 {
                buckets.append(BucketData(startTime: currentTime, distanceMeters: 100, durationSeconds: 30, meanPaceSecPerKm: 300, meanCadence: 180, meanHR: 172))
                currentTime = currentTime.addingTimeInterval(30)
            }
            // Recovery: 60s (2 buckets of 30s) at 135 SPM, 520 s/km, 138 HR
            for _ in 0..<2 {
                buckets.append(BucketData(startTime: currentTime, distanceMeters: 57.7, durationSeconds: 30, meanPaceSecPerKm: 520, meanCadence: 135, meanHR: 138))
                currentTime = currentTime.addingTimeInterval(30)
            }
        }

        let cycles = await engine.extractOscillationCycles(buckets: buckets)
        XCTAssertGreaterThanOrEqual(cycles.count, 3, "Interval workout must produce >= 3 oscillation cycles")

        let regularity = await engine.calculateCycleRegularity(cycles: cycles)
        XCTAssertGreaterThanOrEqual(regularity, 0.65, "Metronomic intervals must produce regularity >= 0.65")

        let classification = await engine.classifyRun(
            buckets: buckets,
            cv: 0.15,
            slope: 0.0,
            zone4: 0.50,
            durationMinutes: 20.0,
            cadenceCV: 0.050,
            averageHR: 160.0
        )
        XCTAssertEqual(classification, "Intervals")
    }

    func testProgressionRun_QuintileMonotonicity() async {
        // Progression Run: 5 quintiles accelerating monotonically (lower pace = faster)
        var buckets: [BucketData] = []
        var currentTime = Date()

        let paces = [400.0, 375.0, 350.0, 325.0, 300.0]
        for pace in paces {
            // 4 buckets per quintile = 20 buckets total (10 min)
            for _ in 0..<4 {
                buckets.append(BucketData(startTime: currentTime, distanceMeters: 30.0 / (pace / 1000.0), durationSeconds: 30, meanPaceSecPerKm: pace, meanCadence: 162, meanHR: 150))
                currentTime = currentTime.addingTimeInterval(30)
            }
        }

        let isMonotonic = await engine.evaluateQuintileProgression(buckets: buckets)
        XCTAssertTrue(isMonotonic, "Continuously accelerating quintiles must pass quintile progression test")

        let classification = await engine.classifyRun(
            buckets: buckets,
            cv: 0.06,
            slope: -0.30,
            zone4: 0.20,
            durationMinutes: 25.0,
            cadenceCV: 0.015,
            averageHR: 152.0
        )
        XCTAssertEqual(classification, "Progression Run")
    }

    func testSteadyRunWithSingleTrafficStop_RemainsContinuous() async {
        // Continuous run with a single 30s stop midway
        var buckets: [BucketData] = []
        var currentTime = Date()

        // 10 buckets cruising at 158 SPM
        for _ in 0..<10 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 80, durationSeconds: 30, meanPaceSecPerKm: 375, meanCadence: 158, meanHR: 148))
            currentTime = currentTime.addingTimeInterval(30)
        }
        // 1 bucket traffic stop at 0 SPM
        buckets.append(BucketData(startTime: currentTime, distanceMeters: 0, durationSeconds: 30, meanPaceSecPerKm: 0, meanCadence: 0, meanHR: 120))
        currentTime = currentTime.addingTimeInterval(30)
        // 10 buckets cruising at 158 SPM
        for _ in 0..<10 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 80, durationSeconds: 30, meanPaceSecPerKm: 375, meanCadence: 158, meanHR: 148))
            currentTime = currentTime.addingTimeInterval(30)
        }

        let cycles = await engine.extractOscillationCycles(buckets: buckets)
        XCTAssertLessThan(cycles.count, 3, "A single traffic pause must produce at most 1 cycle, not triggering intermittent classification")

        let classification = await engine.classifyRun(
            buckets: buckets,
            cv: 0.09,
            slope: 0.0,
            zone4: 0.15,
            durationMinutes: 21.0,
            cadenceCV: 0.030,
            averageHR: 146.0
        )
        XCTAssertNotEqual(classification, "Fartlek")
        XCTAssertNotEqual(classification, "Intervals")
        XCTAssertTrue(classification == "Steady Effort" || classification == "Easy Run")
    }

    func testProgressiveIntervals_CorrectlyIdentifiedAsIntervals() async {
        var buckets: [BucketData] = []
        var currentTime = Date()

        // Warmup: 6 minutes (12 buckets of 30s) at 145 SPM, 450 s/km
        for _ in 0..<12 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 66.6, durationSeconds: 30, meanPaceSecPerKm: 450, meanCadence: 145, meanHR: 130))
            currentTime = currentTime.addingTimeInterval(30)
        }

        // 3 progressive intervals
        let workPaces = [340.0, 320.0, 300.0]
        let workCadences = [160.0, 168.0, 174.0]

        for i in 0..<3 {
            // Work: 2 minutes (4 buckets)
            for _ in 0..<4 {
                buckets.append(BucketData(startTime: currentTime, distanceMeters: 30.0 / (workPaces[i] / 1000.0), durationSeconds: 30, meanPaceSecPerKm: workPaces[i], meanCadence: workCadences[i], meanHR: 165 + Double(i * 5)))
                currentTime = currentTime.addingTimeInterval(30)
            }
            // Recovery: 2 minutes (4 buckets) at 142 SPM, 460 s/km
            for _ in 0..<4 {
                buckets.append(BucketData(startTime: currentTime, distanceMeters: 65.2, durationSeconds: 30, meanPaceSecPerKm: 460, meanCadence: 142, meanHR: 140))
                currentTime = currentTime.addingTimeInterval(30)
            }
        }

        let cycles = await engine.extractOscillationCycles(buckets: buckets)
        XCTAssertGreaterThanOrEqual(cycles.count, 3, "Progressive intervals must detect >= 3 oscillation cycles with rolling baseline")

        let classification = await engine.classifyRun(
            buckets: buckets,
            cv: 0.15,
            slope: 0.0,
            zone4: 0.50,
            durationMinutes: 30.0,
            cadenceCV: 0.050,
            averageHR: 155.0
        )
        XCTAssertEqual(classification, "Intervals")
    }

    func testWarmupAndCooldownWithoutQuintiles_DoesNotClassifyAsProgression() async {
        var buckets: [BucketData] = []
        var currentTime = Date()

        // 5 quintiles (4 buckets each)
        // Q1: Warmup (400 s/km)
        // Q2: Cruise (350 s/km)
        // Q3: Slower (360 s/km) - breaks monotonicity
        // Q4: Fast (330 s/km)
        // Q5: Fastest (320 s/km)
        let paces = [400.0, 350.0, 360.0, 330.0, 320.0]
        for pace in paces {
            for _ in 0..<4 {
                buckets.append(BucketData(startTime: currentTime, distanceMeters: 30.0 / (pace / 1000.0), durationSeconds: 30, meanPaceSecPerKm: pace, meanCadence: 160, meanHR: 150))
                currentTime = currentTime.addingTimeInterval(30)
            }
        }

        let isProgression = await engine.evaluateQuintileProgression(buckets: buckets)
        XCTAssertFalse(isProgression, "Non-monotonic middle splits must fail quintile progression")

        let classification = await engine.classifyRun(
            buckets: buckets,
            cv: 0.06,
            slope: -0.50, // Strong negative slope
            zone4: 0.20,
            durationMinutes: 25.0,
            cadenceCV: 0.015,
            averageHR: 152.0
        )
        XCTAssertNotEqual(classification, "Progression Run", "Scalar slope should not override quintile failure")
        XCTAssertTrue(classification == "Steady Effort" || classification == "Easy Run")
    }

    func testHillySteadyRun_DoesNotFalsePositiveIntervals() async {
        var buckets: [BucketData] = []
        var currentTime = Date()

        // Hilly steady run: constant effort/cadence, but pace fluctuates wildly
        let paces = [360.0, 300.0, 420.0, 350.0, 290.0, 430.0, 360.0] // Flat, Downhill, Uphill, etc.
        for pace in paces {
            for _ in 0..<4 {
                // Cadence stays strictly at 160 SPM
                buckets.append(BucketData(startTime: currentTime, distanceMeters: 30.0 / (pace / 1000.0), durationSeconds: 30, meanPaceSecPerKm: pace, meanCadence: 160, meanHR: 155))
                currentTime = currentTime.addingTimeInterval(30)
            }
        }

        let cycles = await engine.extractOscillationCycles(buckets: buckets)
        XCTAssertLessThan(cycles.count, 3, "Pace fluctuations without cadence surges should not trigger oscillation cycles")
    }

    func testProgressionRun_WithEarlyPlateau_ClassifiesCorrectly() async {
        var buckets: [BucketData] = []
        var currentTime = Date()

        // Q1 = 400, Q2 = 400 (Plateau), Q3 = 375, Q4 = 350, Q5 = 325
        // This has 3 faster transitions (Q2->Q3, Q3->Q4, Q4->Q5)
        let paces = [400.0, 400.0, 375.0, 350.0, 325.0]
        for pace in paces {
            for _ in 0..<4 {
                buckets.append(BucketData(startTime: currentTime, distanceMeters: 30.0 / (pace / 1000.0), durationSeconds: 30, meanPaceSecPerKm: pace, meanCadence: 162, meanHR: 150))
                currentTime = currentTime.addingTimeInterval(30)
            }
        }

        let isProgression = await engine.evaluateQuintileProgression(buckets: buckets)
        XCTAssertTrue(isProgression, "Progression run with an early plateau and 3 faster transitions must pass")
    }

    func testModelManager_ProgressiveIntervals_OverridesCoreMLToIntervals() async {
        let modelManager = ModelManager()

        var buckets: [BucketData] = []
        var currentTime = Date()

        // Warmup: 6 minutes (12 buckets of 30s) at 145 SPM, 450 s/km
        for _ in 0..<12 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 66.6, durationSeconds: 30, meanPaceSecPerKm: 450, meanCadence: 145, meanHR: 130))
            currentTime = currentTime.addingTimeInterval(30)
        }

        // 3 progressive intervals
        let workPaces = [340.0, 320.0, 300.0]
        let workCadences = [160.0, 168.0, 174.0]

        for i in 0..<3 {
            // Work: 2 minutes (4 buckets)
            for _ in 0..<4 {
                buckets.append(BucketData(startTime: currentTime, distanceMeters: 30.0 / (workPaces[i] / 1000.0), durationSeconds: 30, meanPaceSecPerKm: workPaces[i], meanCadence: workCadences[i], meanHR: 165 + Double(i * 5)))
                currentTime = currentTime.addingTimeInterval(30)
            }
            // Recovery: 2 minutes (4 buckets) at 142 SPM, 460 s/km
            for _ in 0..<4 {
                buckets.append(BucketData(startTime: currentTime, distanceMeters: 65.2, durationSeconds: 30, meanPaceSecPerKm: 460, meanCadence: 142, meanHR: 140))
                currentTime = currentTime.addingTimeInterval(30)
            }
        }

        let classification = await modelManager.predictRunType(
            buckets: buckets,
            paceDelta: -50.0,
            hrDelta: 25.0,
            percentZone4: 0.55,
            cadenceDelta: 12.0,
            verticalOscillation: 9.0,
            runnerStage: 1,
            cv: 0.13,
            slope: -0.30,
            durationMinutes: 30.0,
            cadenceCV: 0.048,
            rawAverageHR: 155.0
        )

        XCTAssertEqual(classification, "Intervals", "Progressive intervals through ModelManager must classify as Intervals")
    }

    func testLongIntervalsWithTerminalRepAndActiveRecovery_ClassifiesAsIntervals() async {
        // Simulates 31:24 workout: Warm-up + 3 long intervals (5.5m) with active recovery (2.5m)
        // Interval 3 ends at the completion of the workout (terminal rep).
        var buckets: [BucketData] = []
        var currentTime = Date()

        // Warm-up: 7.5 min (15 windows of 30s) at 152 SPM, 448 s/km, 138 HR
        for _ in 0..<15 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 67.0, durationSeconds: 30, meanPaceSecPerKm: 448, meanCadence: 152, meanHR: 138))
            currentTime = currentTime.addingTimeInterval(30)
        }

        // Rep 1: 5.5 min (11 windows) at 158 SPM (+6 SPM), 350 s/km (98 s/km faster), 156 HR
        for _ in 0..<11 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 85.7, durationSeconds: 30, meanPaceSecPerKm: 350, meanCadence: 158, meanHR: 156))
            currentTime = currentTime.addingTimeInterval(30)
        }

        // Recovery 1: 2.5 min (5 windows) at 153 SPM, 440 s/km, 153 HR
        for _ in 0..<5 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 68.2, durationSeconds: 30, meanPaceSecPerKm: 440, meanCadence: 153, meanHR: 153))
            currentTime = currentTime.addingTimeInterval(30)
        }

        // Rep 2: 5.5 min (11 windows) at 163 SPM (+7 SPM), 320 s/km (120 s/km faster), 164 HR
        for _ in 0..<11 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 93.8, durationSeconds: 30, meanPaceSecPerKm: 320, meanCadence: 163, meanHR: 164))
            currentTime = currentTime.addingTimeInterval(30)
        }

        // Recovery 2: 2.5 min (5 windows) at 156 SPM, 430 s/km, 161 HR
        for _ in 0..<5 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 69.8, durationSeconds: 30, meanPaceSecPerKm: 430, meanCadence: 156, meanHR: 161))
            currentTime = currentTime.addingTimeInterval(30)
        }

        // Rep 3 (Terminal): 5.5 min (11 windows) at 170 SPM, 305 s/km, 172 HR (Ends workout)
        for _ in 0..<11 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 98.4, durationSeconds: 30, meanPaceSecPerKm: 305, meanCadence: 170, meanHR: 172))
            currentTime = currentTime.addingTimeInterval(30)
        }

        let cycles = await engine.extractOscillationCycles(buckets: buckets)
        XCTAssertGreaterThanOrEqual(cycles.count, 3, "All 3 long interval cycles including terminal rep must be corroborated")

        let classification = await engine.classifyRun(
            buckets: buckets,
            cv: 0.16,
            slope: -0.24,
            zone4: 0.49,
            durationMinutes: 31.4,
            cadenceCV: 0.066,
            averageHR: 156.0
        )
        XCTAssertEqual(classification, "Intervals", "3-rep long interval session must classify as Intervals, never Progression Run")
    }

    func testHighCVWorkout_WithAcceleratingQuintiles_DoesNotClassifyAsProgression() async {
        // A workout with accelerating quintiles but high pace CV (cv >= 0.09) must NOT be Progression Run
        var buckets: [BucketData] = []
        var currentTime = Date()

        // 5 accelerating quintiles
        let paces = [440.0, 385.0, 370.0, 340.0, 320.0]
        for pace in paces {
            for _ in 0..<4 {
                buckets.append(BucketData(startTime: currentTime, distanceMeters: 30.0 / (pace / 1000.0), durationSeconds: 30, meanPaceSecPerKm: pace, meanCadence: 160, meanHR: 150))
                currentTime = currentTime.addingTimeInterval(30)
            }
        }

        let isQuintilesAccelerating = await engine.evaluateQuintileProgression(buckets: buckets)
        XCTAssertTrue(isQuintilesAccelerating)

        // When CV is high (e.g. 0.14 from intermittent surges), classifyRun must not return Progression Run
        let classification = await engine.classifyRun(
            buckets: buckets,
            cv: 0.14,
            slope: -0.25,
            zone4: 0.40,
            durationMinutes: 25.0,
            cadenceCV: 0.045,
            averageHR: 150.0,
            cycles: [] // Even if 0 cycles were found, high CV prevents Progression Run
        )
        XCTAssertNotEqual(classification, "Progression Run", "High pace CV (>= 0.09) must prevent Progression Run classification")
    }

    func testCalculateSplits_ContinuousRunPartitionsExactKilometers() async {
        var buckets: [BucketData] = []
        var now = Date()

        // 12 buckets: each 200 meters in 60s (300 s/km = 5:00/km) -> 2,400 meters total
        for i in 1...12 {
            buckets.append(BucketData(
                startTime: now,
                distanceMeters: 200.0,
                durationSeconds: 60.0,
                meanPaceSecPerKm: 300.0,
                meanCadence: 160.0 + Double(i),
                meanHR: 140.0 + Double(i),
                elevationGainMeters: 2.0
            ))
            now = now.addingTimeInterval(60.0)
        }

        let splits = await engine.calculateSplits(from: buckets, splitDistanceMeters: 1000.0)
        // 2,400 meters -> km 1 (1000m), km 2 (1000m), km 3 (400m partial)
        XCTAssertEqual(splits.count, 3)

        // Split 1: 1000 meters in 300 seconds
        XCTAssertEqual(splits[0].index, 1)
        XCTAssertEqual(splits[0].distanceMeters, 1000.0, accuracy: 0.01)
        XCTAssertEqual(splits[0].durationSeconds, 300.0, accuracy: 0.01)
        XCTAssertEqual(splits[0].paceSecondsPerKm, 300.0, accuracy: 0.01)
        XCTAssertEqual(splits[0].elevationGainMeters, 10.0, accuracy: 0.01)

        // Split 2: 1000 meters in 300 seconds
        XCTAssertEqual(splits[1].index, 2)
        XCTAssertEqual(splits[1].distanceMeters, 1000.0, accuracy: 0.01)
        XCTAssertEqual(splits[1].durationSeconds, 300.0, accuracy: 0.01)

        // Split 3: 400 meters in 120 seconds (pace is still 120 / 0.4 = 300 s/km)
        XCTAssertEqual(splits[2].index, 3)
        XCTAssertEqual(splits[2].distanceMeters, 400.0, accuracy: 0.01)
        XCTAssertEqual(splits[2].durationSeconds, 120.0, accuracy: 0.01)
        XCTAssertEqual(splits[2].paceSecondsPerKm, 300.0, accuracy: 0.01)
    }

    func testGeneratePhaseSegments_BridgesMomentaryRepHesitation_ExactNineReps() async {
        // Authentically simulate 9 x 400m intervals where Rep 4 experiences a momentary
        // 20-second track-curve / watch-check hesitation (pace dips to steady).
        var buckets: [BucketData] = []
        var now = Date()

        // 1. Warm-up: 5 minutes at steady 330 s/km (5:30/km), 160 SPM
        for _ in 0..<10 {
            buckets.append(BucketData(startTime: now, distanceMeters: 90.9, durationSeconds: 30, meanPaceSecPerKm: 330, meanCadence: 160, meanHR: 135))
            now = now.addingTimeInterval(30)
        }

        // 2. 9 Interval Reps: Reps 1 to 3, Reps 5 to 9 are clean 90s work (210 s/km, 185 SPM) + 90s recovery (390 s/km, 140 SPM)
        // Rep 4 has a 20s hesitation in the middle.
        for rep in 1...9 {
            if rep == 4 {
                // First half of Rep 4: 35s work
                buckets.append(BucketData(startTime: now, distanceMeters: 166.7, durationSeconds: 35, meanPaceSecPerKm: 210, meanCadence: 185, meanHR: 168))
                now = now.addingTimeInterval(35)
                // Hesitation / curve: 20s steady
                buckets.append(BucketData(startTime: now, distanceMeters: 64.5, durationSeconds: 20, meanPaceSecPerKm: 310, meanCadence: 162, meanHR: 164))
                now = now.addingTimeInterval(20)
                // Second half of Rep 4: 35s work
                buckets.append(BucketData(startTime: now, distanceMeters: 166.7, durationSeconds: 35, meanPaceSecPerKm: 210, meanCadence: 185, meanHR: 170))
                now = now.addingTimeInterval(35)
            } else {
                // Standard 90s work rep (3 buckets of 30s)
                for _ in 0..<3 {
                    buckets.append(BucketData(startTime: now, distanceMeters: 142.8, durationSeconds: 30, meanPaceSecPerKm: 210, meanCadence: 185, meanHR: 170))
                    now = now.addingTimeInterval(30)
                }
            }

            // Recovery: 90s (3 buckets of 30s)
            for _ in 0..<3 {
                buckets.append(BucketData(startTime: now, distanceMeters: 76.9, durationSeconds: 30, meanPaceSecPerKm: 390, meanCadence: 140, meanHR: 138))
                now = now.addingTimeInterval(30)
            }
        }

        // 3. Cool-down: 5 minutes at steady 360 s/km (6:00/km)
        for _ in 0..<10 {
            buckets.append(BucketData(startTime: now, distanceMeters: 83.3, durationSeconds: 30, meanPaceSecPerKm: 360, meanCadence: 155, meanHR: 130))
            now = now.addingTimeInterval(30)
        }

        let phaseSegments = await engine.generatePhaseSegments(from: buckets)
        let workSegments = phaseSegments.filter { $0.kind == "work" }

        XCTAssertEqual(workSegments.count, 9, "Engine must bridge the 20s hesitation in Rep 4 and yield exactly 9 work intervals, not 10")
    }

    func testGeneratePhaseSegments_FiltersIsolatedWarmupStride_ExactNineReps() async {
        // Authentically simulate 10 minutes of warmup with an isolated 25s stride at minute 3
        // followed by 6 minutes of steady jogging before the 9-rep interval set begins.
        var buckets: [BucketData] = []
        var now = Date()

        // 1. Warm-up Part 1: 3 minutes steady (6 buckets of 30s) at 330 s/km, 160 SPM
        for _ in 0..<6 {
            buckets.append(BucketData(startTime: now, distanceMeters: 90.9, durationSeconds: 30, meanPaceSecPerKm: 330, meanCadence: 160, meanHR: 135))
            now = now.addingTimeInterval(30)
        }

        // 2. Warm-up Stride: 25s surge at 220 s/km, 184 SPM
        buckets.append(BucketData(startTime: now, distanceMeters: 113.6, durationSeconds: 25, meanPaceSecPerKm: 220, meanCadence: 184, meanHR: 148))
        now = now.addingTimeInterval(25)

        // 3. Warm-up Part 2: 6 minutes steady (12 buckets of 30s) at 330 s/km before workout begins
        for _ in 0..<12 {
            buckets.append(BucketData(startTime: now, distanceMeters: 90.9, durationSeconds: 30, meanPaceSecPerKm: 330, meanCadence: 160, meanHR: 138))
            now = now.addingTimeInterval(30)
        }

        // 4. Main 9 Interval Reps: 90s work (215 s/km) + 90s recovery (390 s/km)
        for _ in 1...9 {
            for _ in 0..<3 {
                buckets.append(BucketData(startTime: now, distanceMeters: 139.5, durationSeconds: 30, meanPaceSecPerKm: 215, meanCadence: 184, meanHR: 168))
                now = now.addingTimeInterval(30)
            }
            for _ in 0..<3 {
                buckets.append(BucketData(startTime: now, distanceMeters: 76.9, durationSeconds: 30, meanPaceSecPerKm: 390, meanCadence: 140, meanHR: 138))
                now = now.addingTimeInterval(30)
            }
        }

        let phaseSegments = await engine.generatePhaseSegments(from: buckets)
        let workSegments = phaseSegments.filter { $0.kind == "work" }

        XCTAssertEqual(workSegments.count, 9, "Engine must filter out the isolated warmup stride and yield exactly 9 work intervals, not 10")
    }

    func testConsolidatePhaseSegments_ReplacesFragmentedOrOutlierSegments() {
        // Direct test of FramboiseEngine.consolidatePhaseSegments on an existing 10-segment payload
        let rawSegments: [PhaseSegment] = [
            PhaseSegment(startSeconds: 0, endSeconds: 300, kind: "steady", avgPace: 330, avgCadence: 160, avgHR: 135),
            // Rep 1
            PhaseSegment(startSeconds: 300, endSeconds: 390, kind: "work", avgPace: 210, avgCadence: 185, avgHR: 168),
            PhaseSegment(startSeconds: 390, endSeconds: 480, kind: "recovery", avgPace: 390, avgCadence: 140, avgHR: 138),
            // Rep 2
            PhaseSegment(startSeconds: 480, endSeconds: 570, kind: "work", avgPace: 212, avgCadence: 185, avgHR: 169),
            PhaseSegment(startSeconds: 570, endSeconds: 660, kind: "recovery", avgPace: 390, avgCadence: 140, avgHR: 138),
            // Rep 3
            PhaseSegment(startSeconds: 660, endSeconds: 750, kind: "work", avgPace: 210, avgCadence: 186, avgHR: 170),
            PhaseSegment(startSeconds: 750, endSeconds: 840, kind: "recovery", avgPace: 390, avgCadence: 140, avgHR: 139),
            // Rep 4 (Fragmented by a 20s steady gap)
            PhaseSegment(startSeconds: 840, endSeconds: 875, kind: "work", avgPace: 210, avgCadence: 185, avgHR: 169),
            PhaseSegment(startSeconds: 875, endSeconds: 895, kind: "steady", avgPace: 310, avgCadence: 162, avgHR: 165),
            PhaseSegment(startSeconds: 895, endSeconds: 930, kind: "work", avgPace: 210, avgCadence: 185, avgHR: 171),
            PhaseSegment(startSeconds: 930, endSeconds: 1020, kind: "recovery", avgPace: 390, avgCadence: 140, avgHR: 140),
            // Reps 5 to 9
            PhaseSegment(startSeconds: 1020, endSeconds: 1110, kind: "work", avgPace: 211, avgCadence: 185, avgHR: 171),
            PhaseSegment(startSeconds: 1110, endSeconds: 1200, kind: "recovery", avgPace: 390, avgCadence: 140, avgHR: 141),
            PhaseSegment(startSeconds: 1200, endSeconds: 1290, kind: "work", avgPace: 210, avgCadence: 185, avgHR: 172),
            PhaseSegment(startSeconds: 1290, endSeconds: 1380, kind: "recovery", avgPace: 390, avgCadence: 140, avgHR: 141),
            PhaseSegment(startSeconds: 1380, endSeconds: 1470, kind: "work", avgPace: 209, avgCadence: 186, avgHR: 173),
            PhaseSegment(startSeconds: 1470, endSeconds: 1560, kind: "recovery", avgPace: 390, avgCadence: 140, avgHR: 142),
            PhaseSegment(startSeconds: 1560, endSeconds: 1650, kind: "work", avgPace: 208, avgCadence: 186, avgHR: 174),
            PhaseSegment(startSeconds: 1650, endSeconds: 1740, kind: "recovery", avgPace: 390, avgCadence: 140, avgHR: 142),
            PhaseSegment(startSeconds: 1740, endSeconds: 1830, kind: "work", avgPace: 205, avgCadence: 188, avgHR: 176),
            PhaseSegment(startSeconds: 1830, endSeconds: 1920, kind: "recovery", avgPace: 390, avgCadence: 140, avgHR: 143),
            PhaseSegment(startSeconds: 1920, endSeconds: 2220, kind: "steady", avgPace: 360, avgCadence: 155, avgHR: 130)
        ]

        let consolidated = FramboiseEngine.consolidatePhaseSegments(rawSegments)
        let work = consolidated.filter { $0.kind == "work" }
        XCTAssertEqual(work.count, 9, "Consolidated segments must coalesce the fragmented Rep 4 into 1 rep, totaling exactly 9 work segments")
    }

    func testConsolidatePhaseSegments_NineIntervalsWithExtendedRest_PreservesAllNineReps() {
        var segments: [PhaseSegment] = []
        var t: Double = 0

        // Warmup: 300s steady
        segments.append(PhaseSegment(startSeconds: t, endSeconds: t + 300, kind: "steady", avgPace: 330, avgCadence: 160, avgHR: 135))
        t += 300

        // 8 intervals of 60s work + 60s recovery
        for _ in 1...8 {
            segments.append(PhaseSegment(startSeconds: t, endSeconds: t + 60, kind: "work", avgPace: 210, avgCadence: 185, avgHR: 170))
            t += 60
            segments.append(PhaseSegment(startSeconds: t, endSeconds: t + 60, kind: "recovery", avgPace: 380, avgCadence: 140, avgHR: 140))
            t += 60
        }

        // Extended recovery before rep 9 (180s recovery)
        segments.append(PhaseSegment(startSeconds: t, endSeconds: t + 180, kind: "recovery", avgPace: 400, avgCadence: 135, avgHR: 135))
        t += 180

        // Rep 9: 60s work at 186 SPM
        segments.append(PhaseSegment(startSeconds: t, endSeconds: t + 60, kind: "work", avgPace: 208, avgCadence: 186, avgHR: 174))
        t += 60

        // Cooldown: 300s steady
        segments.append(PhaseSegment(startSeconds: t, endSeconds: t + 300, kind: "steady", avgPace: 360, avgCadence: 155, avgHR: 130))

        let consolidated = FramboiseEngine.consolidatePhaseSegments(segments)
        let work = consolidated.filter { $0.kind == "work" }
        XCTAssertEqual(work.count, 9, "Engine must preserve all 9 work intervals and not drop the 9th rep due to extended rest")
    }

    func testGeneratePhaseSegments_FiveRepsWithElevatedHeartRateRecovery_PreservesAllFiveReps() async {
        // Simulates a 5-rep stride / interval drill where HR drifts up and remains elevated (159 BPM)
        // during Recovery 3, while recovery cadence is held at 158 SPM (above 150 floor) and 6:49/km pace.
        // Verifies that Recovery 3 is not erroneously classified as a work surge,
        // and that Rep 3 and Rep 4 are not merged into one giant 2m45s rep.
        var buckets: [BucketData] = []
        var now = Date()

        // Warm-up: 3 minutes steady (6 buckets of 30s) at 420 s/km (7:00/km), 150 SPM, 126 BPM
        for _ in 0..<6 {
            buckets.append(BucketData(startTime: now, distanceMeters: 71.4, durationSeconds: 30, meanPaceSecPerKm: 420, meanCadence: 150, meanHR: 126))
            now = now.addingTimeInterval(30)
        }

        // 5 reps of ~45s work + 75s recovery:
        // Rep 1: 45s at 322 s/km (5:22/km), 163 SPM, 146 BPM
        buckets.append(BucketData(startTime: now, distanceMeters: 139.7, durationSeconds: 45, meanPaceSecPerKm: 322, meanCadence: 163, meanHR: 146))
        now = now.addingTimeInterval(45)
        // Rec 1: 75s at 412 s/km (6:52/km), 158 SPM, 146 BPM
        buckets.append(BucketData(startTime: now, distanceMeters: 182.0, durationSeconds: 75, meanPaceSecPerKm: 412, meanCadence: 158, meanHR: 146))
        now = now.addingTimeInterval(75)

        // Rep 2: 45s at 344 s/km (5:44/km), 163 SPM, 153 BPM
        buckets.append(BucketData(startTime: now, distanceMeters: 130.8, durationSeconds: 45, meanPaceSecPerKm: 344, meanCadence: 163, meanHR: 153))
        now = now.addingTimeInterval(45)
        // Rec 2: 75s at 423 s/km (7:03/km), 158 SPM, 150 BPM
        buckets.append(BucketData(startTime: now, distanceMeters: 177.3, durationSeconds: 75, meanPaceSecPerKm: 423, meanCadence: 158, meanHR: 150))
        now = now.addingTimeInterval(75)

        // Rep 3: 45s at 335 s/km (5:35/km), 163 SPM, 159 BPM
        buckets.append(BucketData(startTime: now, distanceMeters: 134.3, durationSeconds: 45, meanPaceSecPerKm: 335, meanCadence: 163, meanHR: 159))
        now = now.addingTimeInterval(45)
        // Rec 3: 75s at 409 s/km (6:49/km), 158 SPM, 159 BPM (elevated HR >= 155, cadence >= 150 floor)
        buckets.append(BucketData(startTime: now, distanceMeters: 183.4, durationSeconds: 75, meanPaceSecPerKm: 409, meanCadence: 158, meanHR: 159))
        now = now.addingTimeInterval(75)

        // Rep 4: 45s at 343 s/km (5:43/km), 163 SPM, 162 BPM
        buckets.append(BucketData(startTime: now, distanceMeters: 131.2, durationSeconds: 45, meanPaceSecPerKm: 343, meanCadence: 163, meanHR: 162))
        now = now.addingTimeInterval(45)
        // Rec 4: 75s at 409 s/km (6:49/km), 158 SPM, 158 BPM
        buckets.append(BucketData(startTime: now, distanceMeters: 183.4, durationSeconds: 75, meanPaceSecPerKm: 409, meanCadence: 158, meanHR: 158))
        now = now.addingTimeInterval(75)

        // Rep 5: 45s at 343 s/km (5:43/km), 160 SPM, 162 BPM
        buckets.append(BucketData(startTime: now, distanceMeters: 131.2, durationSeconds: 45, meanPaceSecPerKm: 343, meanCadence: 160, meanHR: 162))
        now = now.addingTimeInterval(45)

        // Cooldown: 3 minutes walking at 564 s/km (9:24/km), 126 SPM, 141 BPM
        for _ in 0..<6 {
            buckets.append(BucketData(startTime: now, distanceMeters: 53.2, durationSeconds: 30, meanPaceSecPerKm: 564, meanCadence: 126, meanHR: 141))
            now = now.addingTimeInterval(30)
        }

        let phaseSegments = await engine.generatePhaseSegments(from: buckets, cadenceFloor: 150.0)
        let workSegments = phaseSegments.filter { $0.kind == "work" }

        XCTAssertEqual(workSegments.count, 5, "Must produce exactly 5 work segments without merging Rep 3 and Rep 4")
        for (idx, seg) in workSegments.enumerated() {
            XCTAssertLessThanOrEqual(seg.durationSeconds, 60.0, "Rep \(idx + 1) duration should be ~45s, not merged (was \(seg.durationSeconds)s)")
        }
    }

    func testConsolidatePhaseSegments_ScottTreadmillWorkout_PreservesTwelvePushesAndRejectsArtifact() {
        // Simulates Scott's Apple Fitness+ treadmill workout ("4 hills + 6 two-minute speed pushes + 2 one-minute all-out sprints"):
        // Total intended work efforts = 12 (4 hills + 2 one-minute sprints + 6 two-minute pushes).
        // Telemetry includes an erroneous 15s recovery jog spike at 6:25/km between the two 1-minute sprints.
        // Verifies:
        // 1. The 15s glitch at recovery pace (6:25/km) is rejected as steady/recovery
        // 2. Both 1-minute all-out sprints are preserved as separate distinct work reps (not merged)
        // 3. Exactly 12 true work intervals are produced
        var segments: [PhaseSegment] = []
        var t: Double = 0

        // Warmup: 300s steady at 155 SPM
        segments.append(PhaseSegment(startSeconds: t, endSeconds: t + 300, kind: "steady", avgPace: 380, avgCadence: 155, avgHR: 135))
        t += 300

        // Phase 1: 4 Hills (Reps 1 to 4)
        segments.append(PhaseSegment(startSeconds: t, endSeconds: t + 135, kind: "work", avgPace: 355, avgCadence: 158, avgHR: 150)) // Hill 1: 2m 15s
        t += 135
        segments.append(PhaseSegment(startSeconds: t, endSeconds: t + 60, kind: "recovery", avgPace: 434, avgCadence: 150, avgHR: 144))
        t += 60

        segments.append(PhaseSegment(startSeconds: t, endSeconds: t + 90, kind: "work", avgPace: 360, avgCadence: 155, avgHR: 144)) // Hill 2: 1m 30s
        t += 90
        segments.append(PhaseSegment(startSeconds: t, endSeconds: t + 60, kind: "recovery", avgPace: 423, avgCadence: 150, avgHR: 140))
        t += 60

        segments.append(PhaseSegment(startSeconds: t, endSeconds: t + 60, kind: "work", avgPace: 348, avgCadence: 159, avgHR: 142)) // Hill 3: 1m 00s
        t += 60
        segments.append(PhaseSegment(startSeconds: t, endSeconds: t + 60, kind: "recovery", avgPace: 435, avgCadence: 150, avgHR: 140))
        t += 60

        segments.append(PhaseSegment(startSeconds: t, endSeconds: t + 105, kind: "work", avgPace: 363, avgCadence: 157, avgHR: 150)) // Hill 4: 1m 45s
        t += 105
        segments.append(PhaseSegment(startSeconds: t, endSeconds: t + 60, kind: "recovery", avgPace: 437, avgCadence: 150, avgHR: 144))
        t += 60

        // Phase 2: Speed Push 1 (Rep 5: 2m 00s @ 5:26/km)
        segments.append(PhaseSegment(startSeconds: t, endSeconds: t + 120, kind: "work", avgPace: 326, avgCadence: 165, avgHR: 137))
        t += 120
        segments.append(PhaseSegment(startSeconds: t, endSeconds: t + 60, kind: "recovery", avgPace: 431, avgCadence: 150, avgHR: 144))
        t += 60

        // Phase 3: All-Out Sprint 1 (Rep 6: 1m 00s @ 5:25/km, 166 SPM)
        segments.append(PhaseSegment(startSeconds: t, endSeconds: t + 60, kind: "work", avgPace: 325, avgCadence: 166, avgHR: 158))
        t += 60

        // Recovery between sprints with a 15s artifact spike at recovery pace
        segments.append(PhaseSegment(startSeconds: t, endSeconds: t + 25, kind: "recovery", avgPace: 438, avgCadence: 150, avgHR: 152))
        t += 25
        segments.append(PhaseSegment(startSeconds: t, endSeconds: t + 15, kind: "work", avgPace: 385, avgCadence: 159, avgHR: 144)) // 6:25/km artifact
        t += 15
        segments.append(PhaseSegment(startSeconds: t, endSeconds: t + 35, kind: "recovery", avgPace: 435, avgCadence: 150, avgHR: 150))
        t += 35

        // Phase 4: All-Out Sprint 2 (Rep 8: 1m 00s @ 5:37/km, 162 SPM)
        segments.append(PhaseSegment(startSeconds: t, endSeconds: t + 60, kind: "work", avgPace: 337, avgCadence: 162, avgHR: 160))
        t += 60
        segments.append(PhaseSegment(startSeconds: t, endSeconds: t + 60, kind: "recovery", avgPace: 435, avgCadence: 150, avgHR: 148))
        t += 60

        // Phase 5: Speed Pushes 2 to 6 (~2 mins each)
        segments.append(PhaseSegment(startSeconds: t, endSeconds: t + 105, kind: "work", avgPace: 332, avgCadence: 164, avgHR: 169)) // Push 2: 1m 45s
        t += 105
        segments.append(PhaseSegment(startSeconds: t, endSeconds: t + 60, kind: "recovery", avgPace: 433, avgCadence: 150, avgHR: 150))
        t += 60

        segments.append(PhaseSegment(startSeconds: t, endSeconds: t + 135, kind: "work", avgPace: 337, avgCadence: 165, avgHR: 168)) // Push 3: 2m 15s
        t += 135
        segments.append(PhaseSegment(startSeconds: t, endSeconds: t + 60, kind: "recovery", avgPace: 460, avgCadence: 148, avgHR: 150))
        t += 60

        segments.append(PhaseSegment(startSeconds: t, endSeconds: t + 105, kind: "work", avgPace: 377, avgCadence: 158, avgHR: 156)) // Push 4: 1m 45s
        t += 105
        segments.append(PhaseSegment(startSeconds: t, endSeconds: t + 60, kind: "recovery", avgPace: 470, avgCadence: 148, avgHR: 152))
        t += 60

        segments.append(PhaseSegment(startSeconds: t, endSeconds: t + 120, kind: "work", avgPace: 344, avgCadence: 164, avgHR: 171)) // Push 5: 2m 00s
        t += 120
        segments.append(PhaseSegment(startSeconds: t, endSeconds: t + 60, kind: "recovery", avgPace: 452, avgCadence: 148, avgHR: 152))
        t += 60

        segments.append(PhaseSegment(startSeconds: t, endSeconds: t + 105, kind: "work", avgPace: 339, avgCadence: 161, avgHR: 169)) // Push 6: 1m 45s
        t += 105
        segments.append(PhaseSegment(startSeconds: t, endSeconds: t + 180, kind: "steady", avgPace: 466, avgCadence: 145, avgHR: 140))
        t += 180

        let consolidated = FramboiseEngine.consolidatePhaseSegments(segments)
        let work = consolidated.filter { $0.kind == "work" }

        XCTAssertEqual(work.count, 12, "Should preserve exactly 12 work efforts (4 hills + 2 one-minute sprints + 6 two-minute speed pushes), discarding the 15s artifact")
        XCTAssertEqual(work[5].durationSeconds, 60.0, "All-Out Sprint 1 must remain a clean 1-minute rep")
        XCTAssertEqual(work[6].durationSeconds, 60.0, "All-Out Sprint 2 must remain a clean 1-minute rep")
    }

    func testConsolidatePhaseSegments_ShericaTreadmillWorkout_PreservesSixCompoundRepsAndRejectsTrailingArtifact() {
        // Authentically extracted from the user's physical device database (RunRecord ID 0452BD1C-A23E-4A9B-A067-B8DDB7C0CDFB):
        // 30-minute Peloton treadmill workout with Sherica (6 rounds of 1-minute hard hill + 30-second all-out push back-to-back).
        // Each round consists of 1m hill + 30s push run back-to-back (~1m 15s - 2m 30s total) followed by true recovery.
        // In Round 2 and Round 6, treadmill flat transitions (60s and 45s steady at 158-159 SPM) occur between hill and push.
        // Verifies:
        // 1. Exactly 6 genuine compound interval reps are produced (matching the 6 prescribed rounds)
        // 2. All 6 reps are properly bounded by authentic recovery intervals
        let segments: [PhaseSegment] = [
            PhaseSegment(startSeconds: 0, endSeconds: 75, kind: "recovery", avgPace: 446.6, avgCadence: 149.4, avgHR: 116),
            PhaseSegment(startSeconds: 75, endSeconds: 90, kind: "steady", avgPace: 420.2, avgCadence: 153.5, avgHR: 130),
            PhaseSegment(startSeconds: 90, endSeconds: 105, kind: "recovery", avgPace: 411.2, avgCadence: 151.3, avgHR: 131),
            PhaseSegment(startSeconds: 105, endSeconds: 240, kind: "steady", avgPace: 409.3, avgCadence: 154.4, avgHR: 134),
            PhaseSegment(startSeconds: 240, endSeconds: 375, kind: "work", avgPace: 337.8, avgCadence: 164.6, avgHR: 152),
            PhaseSegment(startSeconds: 375, endSeconds: 390, kind: "steady", avgPace: 377.6, avgCadence: 159.3, avgHR: 163),
            PhaseSegment(startSeconds: 390, endSeconds: 465, kind: "recovery", avgPace: 407.6, avgCadence: 155.3, avgHR: 154),
            PhaseSegment(startSeconds: 465, endSeconds: 480, kind: "steady", avgPace: 380.7, avgCadence: 159.3, avgHR: 138),
            PhaseSegment(startSeconds: 480, endSeconds: 525, kind: "work", avgPace: 331.1, avgCadence: 164.6, avgHR: 150),
            PhaseSegment(startSeconds: 525, endSeconds: 585, kind: "steady", avgPace: 382.8, avgCadence: 158.3, avgHR: 157),
            PhaseSegment(startSeconds: 585, endSeconds: 615, kind: "work", avgPace: 303.0, avgCadence: 170.3, avgHR: 155),
            PhaseSegment(startSeconds: 615, endSeconds: 630, kind: "steady", avgPace: 361.8, avgCadence: 161.3, avgHR: 166),
            PhaseSegment(startSeconds: 630, endSeconds: 660, kind: "recovery", avgPace: 412.5, avgCadence: 155.3, avgHR: 165),
            PhaseSegment(startSeconds: 660, endSeconds: 675, kind: "steady", avgPace: 385.7, avgCadence: 159.3, avgHR: 162),
            PhaseSegment(startSeconds: 675, endSeconds: 705, kind: "recovery", avgPace: 381.6, avgCadence: 156.3, avgHR: 156),
            PhaseSegment(startSeconds: 705, endSeconds: 720, kind: "steady", avgPace: 368.2, avgCadence: 157.3, avgHR: 156),
            PhaseSegment(startSeconds: 720, endSeconds: 795, kind: "work", avgPace: 352.5, avgCadence: 161.7, avgHR: 162),
            PhaseSegment(startSeconds: 795, endSeconds: 825, kind: "steady", avgPace: 373.9, avgCadence: 159.3, avgHR: 163),
            PhaseSegment(startSeconds: 825, endSeconds: 840, kind: "walking", avgPace: 393.7, avgCadence: 107.4, avgHR: 161),
            PhaseSegment(startSeconds: 840, endSeconds: 975, kind: "recovery", avgPace: 392.4, avgCadence: 157.5, avgHR: 140),
            PhaseSegment(startSeconds: 975, endSeconds: 1125, kind: "work", avgPace: 332.7, avgCadence: 164.8, avgHR: 143),
            PhaseSegment(startSeconds: 1125, endSeconds: 1200, kind: "recovery", avgPace: 373.9, avgCadence: 158.5, avgHR: 134),
            PhaseSegment(startSeconds: 1200, endSeconds: 1350, kind: "work", avgPace: 322.0, avgCadence: 164.3, avgHR: 168),
            PhaseSegment(startSeconds: 1350, endSeconds: 1425, kind: "recovery", avgPace: 380.5, avgCadence: 156.9, avgHR: 135),
            PhaseSegment(startSeconds: 1425, endSeconds: 1440, kind: "steady", avgPace: 344.4, avgCadence: 159.3, avgHR: 164),
            PhaseSegment(startSeconds: 1440, endSeconds: 1485, kind: "work", avgPace: 326.8, avgCadence: 163.3, avgHR: 111),
            PhaseSegment(startSeconds: 1485, endSeconds: 1530, kind: "steady", avgPace: 354.5, avgCadence: 159.3, avgHR: 171),
            PhaseSegment(startSeconds: 1530, endSeconds: 1575, kind: "work", avgPace: 322.8, avgCadence: 166.0, avgHR: 175),
            PhaseSegment(startSeconds: 1575, endSeconds: 1650, kind: "steady", avgPace: 365.9, avgCadence: 160.1, avgHR: 139),
            PhaseSegment(startSeconds: 1650, endSeconds: 1674, kind: "recovery", avgPace: 400.2, avgCadence: 152.6, avgHR: 168)
        ]

        let consolidated = FramboiseEngine.consolidatePhaseSegments(segments)
        let work = consolidated.filter { $0.kind == "work" }

        XCTAssertEqual(work.count, 6, "Must yield exactly 6 compound interval reps matching the 6 rounds")
        XCTAssertEqual(work[0].durationSeconds, 135.0, "Rep 1 (Round 1): 2m 15s")
        XCTAssertEqual(work[1].durationSeconds, 135.0, "Rep 2 (Round 2 bridged): 2m 15s")
        XCTAssertEqual(work[2].durationSeconds, 75.0, "Rep 3 (Round 3): 1m 15s")
        XCTAssertEqual(work[3].durationSeconds, 150.0, "Rep 4 (Round 4): 2m 30s")
        XCTAssertEqual(work[4].durationSeconds, 150.0, "Rep 5 (Round 5): 2m 30s")
        XCTAssertEqual(work[5].durationSeconds, 135.0, "Rep 6 (Round 6 bridged): 2m 15s")
    }
}
