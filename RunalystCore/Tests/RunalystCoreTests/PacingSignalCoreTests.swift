import Foundation
@testable import RunalystCore
import Testing

@Suite("Pacing Signal Core Tests")
struct PacingSignalCoreTests {

    // MARK: - Kalman Filter 1D Tests

    @Test("Seeding without ramp: first valid HR seeds estimate directly")
    func testKalmanSeedingWithoutRamp() {
        var filter = KalmanFilter1D.standardHeartRate
        #expect(filter.currentEstimate == nil)

        let result = filter.step(142.0)
        #expect(result.estimate == 142.0)
        #expect(result.isValid == true)
        #expect(filter.currentEstimate == 142.0)
    }

    @Test("Artifact rejection: single 215 BPM spike damped and recovers within 10 ticks")
    func testKalmanArtifactRejection() {
        var filter = KalmanFilter1D.standardHeartRate

        // Establish stable 150 BPM baseline
        for _ in 1...20 {
            _ = filter.step(150.0)
        }

        // Single 215 BPM spike
        let spikeResult = filter.step(215.0)
        guard let spikeEstimate = spikeResult.estimate else {
            Issue.record("Spike estimate should not be nil")
            return
        }

        let rise = spikeEstimate - 150.0
        #expect(rise < 15.0, "Spike must be damped to rise by less than 15 BPM")
        #expect(rise > 0.0, "Estimate should reflect an upward step")

        // 10 subsequent normal ticks at 150 BPM
        var lastEstimate: Double = 0.0
        for _ in 1...10 {
            if let est = filter.step(150.0).estimate {
                lastEstimate = est
            }
        }

        let residual = abs(lastEstimate - 150.0)
        #expect(residual <= 2.0, "Estimate must return within 2 BPM of 150 within 10 ticks")
    }

    @Test("Dropout handling: nil or out-of-range HR preserves prior estimate and flags invalid")
    func testKalmanDropoutHandling() {
        var filter = KalmanFilter1D.standardHeartRate
        _ = filter.step(148.0)

        // Missing sample (nil)
        let dropResult = filter.step(nil)
        #expect(dropResult.estimate == 148.0)
        #expect(dropResult.isValid == false)

        // Physiologically invalid sample below range (< 30 BPM)
        let lowResult = filter.step(22.0)
        #expect(lowResult.estimate == 148.0)
        #expect(lowResult.isValid == false)

        // Physiologically invalid sample above range (> 230 BPM)
        let highResult = filter.step(245.0)
        #expect(highResult.estimate == 148.0)
        #expect(highResult.isValid == false)

        // Filter reset
        filter.reset()
        #expect(filter.currentEstimate == nil)
        let unseededDrop = filter.step(nil)
        #expect(unseededDrop.estimate == nil)
        #expect(unseededDrop.isValid == false)
    }

    @Test("Speed Kalman filter operates within 0 to 12 m/s bounds")
    func testSpeedKalmanBounds() {
        var filter = KalmanFilter1D.standardSpeed
        let seed = filter.step(3.33)
        #expect(seed.estimate == 3.33)
        #expect(seed.isValid == true)

        let invalidSpeed = filter.step(15.0) // > 12 m/s
        #expect(invalidSpeed.estimate == 3.33)
        #expect(invalidSpeed.isValid == false)
    }

    // MARK: - Ring Buffer & Window Coverage Tests

    @Test("Window coverage gate: statistic is nil when coverage is under 80%")
    func testWindowCoverageGate() {
        var ringBuffer = TelemetryRingBuffer(capacity: 900)

        // Append 30 ticks: 20 with cadence 168 SPM, 10 without cadence
        for s in 1...30 {
            let cadence: Double? = (s <= 20) ? 168.0 : nil
            let tick = ConditionedTelemetryTick(
                elapsedSeconds: TimeInterval(s),
                heartRateBPM: 145.0,
                isHeartRateValid: true,
                speedMetersPerSecond: 3.33,
                isSpeedValid: true,
                cadenceSPM: cadence,
                powerWatts: 220.0,
                groundContactTimeMs: 240.0,
                verticalOscillationCm: 8.5,
                strideLengthMeters: 1.18,
                gradeFraction: 0.0
            )
            ringBuffer.append(tick)
        }

        // Coverage is 20 / 30 = 66.7% < 80% threshold
        let statsBelowThreshold = ringBuffer.shortWindowStats(for: .cadence)
        #expect(statsBelowThreshold == nil)

        // Reset buffer and test above 80% threshold (25 valid ticks, 5 missing out of 30)
        var validBuffer = TelemetryRingBuffer(capacity: 900)
        for s in 1...30 {
            let cadence: Double? = (s <= 25) ? 168.0 : nil
            let tick = ConditionedTelemetryTick(
                elapsedSeconds: TimeInterval(s),
                heartRateBPM: 145.0,
                isHeartRateValid: true,
                speedMetersPerSecond: 3.33,
                isSpeedValid: true,
                cadenceSPM: cadence,
                powerWatts: 220.0,
                groundContactTimeMs: 240.0,
                verticalOscillationCm: 8.5,
                strideLengthMeters: 1.18,
                gradeFraction: 0.0
            )
            validBuffer.append(tick)
        }

        let statsAboveThreshold = validBuffer.shortWindowStats(for: .cadence)
        #expect(statsAboveThreshold != nil)
        #expect(statsAboveThreshold?.sampleCount == 25)
        #expect(statsAboveThreshold?.mean == 168.0)
    }

    @Test("Constant memory at 7,200 ticks: buffer capacity remains 900 and oldest tick is 6,301")
    func testConstantMemoryAt7200Ticks() {
        var ringBuffer = TelemetryRingBuffer(capacity: 900)

        for s in 1...7200 {
            let tick = ConditionedTelemetryTick(
                elapsedSeconds: TimeInterval(s),
                heartRateBPM: 145.0,
                isHeartRateValid: true,
                speedMetersPerSecond: 3.33,
                isSpeedValid: true,
                cadenceSPM: 168.0,
                powerWatts: 220.0,
                groundContactTimeMs: 240.0,
                verticalOscillationCm: 8.5,
                strideLengthMeters: 1.18,
                gradeFraction: 0.0
            )
            ringBuffer.append(tick)
        }

        #expect(ringBuffer.count == 900)
        #expect(ringBuffer.isFull == true)
        #expect(ringBuffer.latestTick?.elapsedSeconds == 7200.0)

        // Oldest retained tick must be 6,301 s
        let oldestStats = ringBuffer.stats(for: .filteredHeartRate, in: 6301.0...6301.0, minCoverage: 0.80)
        #expect(oldestStats != nil, "Tick 6,301 must still be retained in buffer")

        // Tick 6,300 s was overwritten
        let evictedStats = ringBuffer.stats(for: .filteredHeartRate, in: 6300.0...6300.0, minCoverage: 0.80)
        #expect(evictedStats == nil, "Tick 6,300 must have been evicted")

        // Trailing full buffer interval 6301...7200 s contains 900 ticks with 100% coverage
        let fullRetainedStats = ringBuffer.stats(for: .filteredHeartRate, in: 6301.0...7200.0, minCoverage: 0.80)
        #expect(fullRetainedStats != nil)
        #expect(fullRetainedStats?.sampleCount == 900)
    }

    @Test("Effective cadence prefers primary sensor over IMU pedometer fallback")
    func testEffectiveCadencePreference() {
        let tick1 = TelemetryTick(
            elapsedSeconds: 1.0,
            cadenceSPM: 172.0,
            imuCadenceSPM: 168.0
        )
        #expect(tick1.effectiveCadenceSPM == 172.0)

        let tick2 = TelemetryTick(
            elapsedSeconds: 2.0,
            cadenceSPM: nil,
            imuCadenceSPM: 166.0
        )
        #expect(tick2.effectiveCadenceSPM == 166.0)
    }

    // MARK: - Staleness Policy & Kinematic Helpers Tests

    @Test("TelemetryStalenessPolicy: validValue passes recent samples and nulls out stale ones > 5s")
    func testTelemetryStalenessPolicy() {
        // Fresh sample (1 second old)
        let fresh = TelemetryStalenessPolicy.validValue(155.0, sampleTimestamp: 10.0, currentElapsed: 11.0)
        #expect(fresh == 155.0)

        // Exactly at boundary (5.0 seconds old)
        let boundary = TelemetryStalenessPolicy.validValue(155.0, sampleTimestamp: 10.0, currentElapsed: 15.0)
        #expect(boundary == 155.0)

        // Stale sample (5.1 seconds old)
        let stale = TelemetryStalenessPolicy.validValue(155.0, sampleTimestamp: 10.0, currentElapsed: 15.1)
        #expect(stale == nil)

        // Missing value or timestamp
        #expect(TelemetryStalenessPolicy.validValue(nil, sampleTimestamp: 10.0, currentElapsed: 11.0) == nil)
        #expect(TelemetryStalenessPolicy.validValue(155.0, sampleTimestamp: nil, currentElapsed: 11.0) == nil)
    }

    @Test("TelemetryStalenessPolicy: computeGradeFraction computes slope and guards tiny distance")
    func testComputeGradeFraction() {
        // +4m altitude over 100m distance = 0.04 (4% grade)
        let slope = TelemetryStalenessPolicy.computeGradeFraction(altitudeDeltaMeters: 4.0, distanceDeltaMeters: 100.0)
        #expect(slope == 0.04)

        // Guard against stationary / tiny distance (<= 0.5m)
        let stationary = TelemetryStalenessPolicy.computeGradeFraction(altitudeDeltaMeters: 1.0, distanceDeltaMeters: 0.3)
        #expect(stationary == nil)
    }
}

