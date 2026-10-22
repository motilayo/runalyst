import Foundation
import Testing
@testable import RunalystCore

@Suite("FramboiseCore Crucible Invariant Tests")
struct FramboiseCoreTests {

    @Test("filterRunningSamples drops stationary samples and walking breaks while enforcing 125 SPM floor")
    func deadStopFiltering() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let buckets = [
            // Stationary: 0 m/s, 0 SPM -> Drop
            TelemetryBucket(timestamp: now, durationSeconds: 60, distanceMeters: 0, paceSecondsPerKm: 0, cadenceSPM: 0, heartRateBPM: 85),
            // Walking break: 60m in 60s = 1.0 m/s (< 1.5), cadence 105 (< 125) -> Drop
            TelemetryBucket(timestamp: now.addingTimeInterval(60), durationSeconds: 60, distanceMeters: 60, paceSecondsPerKm: 1000, cadenceSPM: 105, heartRateBPM: 110),
            // Running by speed: 120m in 60s = 2.0 m/s (> 1.65), cadence 126 (>= 125) -> Keep
            TelemetryBucket(timestamp: now.addingTimeInterval(120), durationSeconds: 60, distanceMeters: 120, paceSecondsPerKm: 500, cadenceSPM: 126, heartRateBPM: 145),
            // Running by cadence: 80m in 60s = 1.33 m/s, cadence 155 (>= 130) -> Keep
            TelemetryBucket(timestamp: now.addingTimeInterval(180), durationSeconds: 60, distanceMeters: 80, paceSecondsPerKm: 750, cadenceSPM: 155, heartRateBPM: 140),
            // No cadence sensor, pure speed: 110m in 60s = 1.83 m/s (> 1.5) -> Keep
            TelemetryBucket(timestamp: now.addingTimeInterval(240), durationSeconds: 60, distanceMeters: 110, paceSecondsPerKm: 545, cadenceSPM: 0, heartRateBPM: 138)
        ]

        let trimmed = FramboiseCore.filterRunningSamples(buckets: buckets)
        #expect(trimmed.count == 3)
        #expect(trimmed[0].distanceMeters == 120)
        #expect(trimmed[1].distanceMeters == 80)
        #expect(trimmed[2].distanceMeters == 110)
    }

    @Test("calculateWorkingAverages calculates pure aggregate pace and arithmetic means")
    func workingAveragesCalculation() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let buckets = [
            TelemetryBucket(timestamp: now, durationSeconds: 60, distanceMeters: 200, paceSecondsPerKm: 300, cadenceSPM: 160, heartRateBPM: 140, groundContactTimeMs: 240, verticalOscillationCm: 8.8, strideLengthMeters: 1.10),
            TelemetryBucket(timestamp: now.addingTimeInterval(60), durationSeconds: 60, distanceMeters: 200, paceSecondsPerKm: 300, cadenceSPM: 164, heartRateBPM: 144, groundContactTimeMs: 250, verticalOscillationCm: 9.2, strideLengthMeters: 1.30)
        ]

        let averages = FramboiseCore.calculateWorkingAverages(trimmed: buckets)
        #expect(averages.workingCadence == 162.0)
        #expect(averages.workingHR == 142.0)
        #expect(averages.workingDistance == 400.0)
        #expect(averages.workingDuration == 120.0)
        // 400 meters in 120 seconds -> 120 / 0.4 = 300 s/km
        #expect(abs(averages.workingPace - 300.0) < 0.001)
        #expect(abs((averages.workingOscillation ?? 0) - 9.0) < 0.001)
        #expect(abs((averages.workingStrideLength ?? 0) - 1.20) < 0.001)
        #expect(abs((averages.workingGroundContactTime ?? 0) - 245.0) < 0.001)
    }

    @Test("calculateWorkingAverages excludes zero buckets for biomechanical metrics")
    func workingAveragesZeroBucketExclusion() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let buckets = [
            TelemetryBucket(timestamp: now, durationSeconds: 60, distanceMeters: 200, paceSecondsPerKm: 300, cadenceSPM: 160, heartRateBPM: 140, verticalOscillationCm: 8.8, strideLengthMeters: 1.10),
            TelemetryBucket(timestamp: now.addingTimeInterval(60), durationSeconds: 60, distanceMeters: 200, paceSecondsPerKm: 300, cadenceSPM: 164, heartRateBPM: 144, verticalOscillationCm: nil, strideLengthMeters: nil),
            TelemetryBucket(timestamp: now.addingTimeInterval(120), durationSeconds: 60, distanceMeters: 200, paceSecondsPerKm: 300, cadenceSPM: 162, heartRateBPM: 142, verticalOscillationCm: 9.2, strideLengthMeters: 1.30)
        ]

        let averages = FramboiseCore.calculateWorkingAverages(trimmed: buckets)
        // (8.8 + 9.2) / 2 = 9.0
        let osc = try #require(averages.workingOscillation)
        #expect(abs(osc - 9.0) < 0.001)

        // (1.10 + 1.30) / 2 = 1.20
        let stride = try #require(averages.workingStrideLength)
        #expect(abs(stride - 1.20) < 0.001)
    }

    @Test("calculateWorkingAverages enforces duration safety constraint when trimmedDuration exceeds raw")
    func durationSafetyConstraint() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let buckets = [
            TelemetryBucket(timestamp: now, durationSeconds: 60, distanceMeters: 200, paceSecondsPerKm: 300, cadenceSPM: 160, heartRateBPM: 140),
            TelemetryBucket(timestamp: now.addingTimeInterval(60), durationSeconds: 60, distanceMeters: 200, paceSecondsPerKm: 300, cadenceSPM: 160, heartRateBPM: 140)
        ]

        // 2 buckets = 120s, but raw workout duration was recorded as 100s
        let averages = FramboiseCore.calculateWorkingAverages(trimmed: buckets, rawWorkoutDuration: 100.0)
        #expect(averages.workingDuration == 100.0)
    }

    @Test("Mathematical feature vector (CV, slope, Zone 4) computes deterministically")
    func mathematicalFeatures() {
        // Uniform paces: CV should be near zero
        let uniformPaces = [300.0, 300.0, 300.0, 300.0]
        #expect(FramboiseCore.calculatePaceCV(bucketPaces: uniformPaces) == 0.0)

        // Accelerating paces: 360 -> 340 -> 320 -> 300 (slope = -20)
        let acceleratingPaces = [360.0, 340.0, 320.0, 300.0]
        let slope = FramboiseCore.calculatePaceSlope(bucketPaces: acceleratingPaces)
        #expect(abs(slope - (-20.0)) < 0.001)

        // Decelerating cadence: 170 -> 168 -> 166 -> 164 (slope = -2)
        let deceleratingCadences = [170.0, 168.0, 166.0, 164.0]
        let cadSlope = FramboiseCore.calculateCadenceSlope(bucketCadences: deceleratingCadences)
        #expect(abs(cadSlope - (-2.0)) < 0.001)

        // Zone 4 percentage with max HR 200 (Zone 4 threshold = 170)
        let hrs = [150.0, 160.0, 172.0, 180.0]
        let z4 = FramboiseCore.calculatePercentZone4(bucketHRs: hrs, maxHR: 200.0)
        #expect(z4 == 0.5)
    }

    @Test("computeWorkingStats scrubs city run traffic stops and populates WorkingStats")
    func computeWorkingStatsCityRun() {
        let fixture = GoldenTelemetryFixtures.cityRunTrafficStops
        let buckets = fixture.toTelemetryBuckets()

        #expect(buckets.count == 20)
        let stats = FramboiseCore.computeWorkingStats(buckets: buckets)

        #expect(stats.deadStopsCount == 3)
        #expect(stats.workingDurationSeconds == 17 * 30.0)
        #expect(stats.rawTotalDurationSeconds == 20 * 30.0)
        #expect(stats.workingAvgCadenceSPM == 165.0)
        #expect(abs(stats.workingAvgPaceSecondsPerKm - 330.0) < 0.001)
        #expect(stats.workingAvgHeartRateBPM == 152.0)
    }

    @Test("computeWorkingStats survives adversarial sensor jitter on authentic intervals")
    func computeWorkingStatsAdversarialJitter() {
        let fixture = GoldenTelemetryFixtures.authenticIntervals31Min
        let idealBuckets = fixture.toTelemetryBuckets()
        let noisyBuckets = TelemetryNoiseInjector.injectSensorJitter(to: idealBuckets, seed: 12345)

        let idealStats = FramboiseCore.computeWorkingStats(buckets: idealBuckets)
        let noisyStats = FramboiseCore.computeWorkingStats(buckets: noisyBuckets)

        // Distance within +/- 1.5% under GPS multipath jitter
        let distanceRatio = noisyStats.workingDistanceMeters / idealStats.workingDistanceMeters
        #expect(distanceRatio >= 0.985 && distanceRatio <= 1.015)

        // Cadence within +/- 0.5 SPM under accelerometer noise
        #expect(abs(noisyStats.workingAvgCadenceSPM - idealStats.workingAvgCadenceSPM) < 0.5)

        // Heart Rate within +/- 0.5 BPM under optical sensor noise
        #expect(abs(noisyStats.workingAvgHeartRateBPM - idealStats.workingAvgHeartRateBPM) < 0.5)

        // Pace within +/- 3.0 s/km
        #expect(abs(noisyStats.workingAvgPaceSecondsPerKm - idealStats.workingAvgPaceSecondsPerKm) < 3.0)
    }
}
