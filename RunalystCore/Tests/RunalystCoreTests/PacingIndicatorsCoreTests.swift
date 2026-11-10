import Foundation
@testable import RunalystCore
import Testing

@Suite("Pacing Indicators Core Tests")
struct PacingIndicatorsCoreTests {

    // MARK: - Helpers

    private func makeRingBuffer(
        tickCount: Int = 180,
        hr: Double = 150.0,
        speed: Double = 3.33,
        power: Double? = 270.0,
        cadence: Double = 168.0,
        gct: Double = 240.0,
        grade: Double = 0.0
    ) -> TelemetryRingBuffer {
        var ringBuffer = TelemetryRingBuffer(capacity: 900)
        for s in 1...tickCount {
            let tick = ConditionedTelemetryTick(
                elapsedSeconds: TimeInterval(s),
                heartRateBPM: hr,
                isHeartRateValid: true,
                speedMetersPerSecond: speed,
                isSpeedValid: true,
                cadenceSPM: cadence,
                powerWatts: power,
                groundContactTimeMs: gct,
                verticalOscillationCm: 8.5,
                strideLengthMeters: 1.18,
                gradeFraction: grade
            )
            ringBuffer.append(tick)
        }
        return ringBuffer
    }

    // MARK: - Efficiency Drift Tracker Tests

    @Test("Cardiac drift detected: EF_0 = 1.80 and current EF = 1.68 yields deltaEF approx -0.0667")
    func testCardiacDriftDetected() {
        var tracker = EfficiencyDriftTracker(location: .outdoor)
        tracker.lockBaseline(ef: 1.80, source: .power)

        // 180 ticks with power 252 W and HR 150 BPM -> current EF = 252 / 150 = 1.68
        let buffer = makeRingBuffer(tickCount: 180, hr: 150.0, power: 252.0)
        let delta = tracker.deltaEF(from: buffer)

        guard let delta else {
            Issue.record("deltaEF should not be nil")
            return
        }

        // Expected: (1.68 - 1.80) / 1.80 = -0.12 / 1.80 = -0.066666...
        let expected = (1.68 - 1.80) / 1.80
        #expect(abs(delta - expected) < 0.0001)
        #expect(abs(delta - (-0.0667)) < 0.001)
    }

    @Test("Hill climb without power does not fake drift: speed-based EF on 4% grade yields nil")
    func testHillClimbWithoutPowerSuspendsDeltaEF() {
        var tracker = EfficiencyDriftTracker(location: .outdoor)
        // Baseline derived from speed without power
        tracker.lockBaseline(ef: 3.33 / 150.0, source: .speed)

        // 4% uphill grade (|grade| = 0.04 > 0.015 grade guard)
        let hillBuffer = makeRingBuffer(
            tickCount: 180,
            hr: 165.0,
            speed: 2.85,
            power: nil,
            grade: 0.04
        )

        let deltaOnHill = tracker.deltaEF(from: hillBuffer)
        #expect(deltaOnHill == nil, "Speed-based deltaEF must be suspended on grades > 1.5%")

        // Flat grade should compute deltaEF normally
        let flatBuffer = makeRingBuffer(
            tickCount: 180,
            hr: 165.0,
            speed: 2.85,
            power: nil,
            grade: 0.0
        )
        let deltaOnFlat = tracker.deltaEF(from: flatBuffer)
        #expect(deltaOnFlat != nil)
    }

    @Test("Source mismatch: EF_0 locked from power drops to nil when power drops out")
    func testSourceMismatchYieldsNil() {
        var tracker = EfficiencyDriftTracker(location: .outdoor)
        tracker.lockBaseline(ef: 1.80, source: .power)

        // Running session where power has dropped out (power: nil)
        let noPowerBuffer = makeRingBuffer(tickCount: 180, hr: 150.0, speed: 3.33, power: nil)

        // Current EF derives from speed fallback, but baseline was power -> source mismatch
        let delta = tracker.deltaEF(from: noPowerBuffer)
        #expect(delta == nil, "deltaEF must not compare speed-derived EF against power-derived baseline")
    }

    @Test("Indoor without power: deltaEF is nil for entire session")
    func testIndoorWithoutPowerYieldsNil() {
        var tracker = EfficiencyDriftTracker(location: .indoor)

        // Indoor session without power
        let indoorBuffer = makeRingBuffer(tickCount: 600, hr: 150.0, speed: 3.33, power: nil)

        // Baseline lock fails because speed fallback is disabled indoors
        let locked = tracker.lockBaseline(from: indoorBuffer, in: 300...600)
        #expect(locked == false)

        let current = tracker.currentEF(from: indoorBuffer)
        #expect(current == nil)

        let delta = tracker.deltaEF(from: indoorBuffer)
        #expect(delta == nil)
    }

    // MARK: - Biomechanical Degradation Index Tests

    @Test("Form breakdown: GCT 240->260 ms and cadence 168->163 SPM triggers breakdown flag")
    func testFormBreakdownEvaluation() {
        var bdi = BiomechanicalDegradationIndex()
        bdi.lockBaseline(gct: 240.0, cadence: 168.0)

        // Short window: 30 ticks of GCT 260 ms (+8.33%) and cadence 163 SPM (-5 SPM)
        let buffer = makeRingBuffer(tickCount: 30, cadence: 163.0, gct: 260.0)

        guard let assessment = bdi.evaluate(from: buffer) else {
            Issue.record("Assessment should not be nil")
            return
        }

        // Expected gctDeltaFraction: (260 - 240) / 240 = 20 / 240 = 0.08333...
        #expect(abs(assessment.gctDeltaFraction - 0.0833) < 0.001)
        #expect(assessment.cadenceDropSPM == 5.0)
        #expect(assessment.formBreakdown == true)

        // Expected BDI: (260/240) * (168/163) - 1.0 = (1.0833333 * 1.0306748) - 1.0 = 0.11656...
        #expect(abs(assessment.bdi - 0.1166) < 0.001)
    }

    @Test("Relative not absolute: baseline of 275 ms at 158 SPM persisting unchanged does not trip breakdown")
    func testRelativeNotAbsoluteBaseline() {
        var bdi = BiomechanicalDegradationIndex()
        bdi.lockBaseline(gct: 275.0, cadence: 158.0)

        // Identical values in short window
        let buffer = makeRingBuffer(tickCount: 30, cadence: 158.0, gct: 275.0)

        guard let assessment = bdi.evaluate(from: buffer) else {
            Issue.record("Assessment should not be nil")
            return
        }

        #expect(assessment.gctDeltaFraction == 0.0)
        #expect(assessment.cadenceDropSPM == 0.0)
        #expect(assessment.formBreakdown == false)
        #expect(abs(assessment.bdi) < 0.0001)
    }

    @Test("Derives baseline directly from ring buffer calibration window")
    func testLockBaselineFromRingBuffer() {
        var buffer = TelemetryRingBuffer(capacity: 900)
        for s in 1...600 {
            let tick = ConditionedTelemetryTick(
                elapsedSeconds: TimeInterval(s),
                heartRateBPM: 145.0,
                isHeartRateValid: true,
                speedMetersPerSecond: 3.33,
                isSpeedValid: true,
                cadenceSPM: 170.0,
                powerWatts: 240.0,
                groundContactTimeMs: 235.0,
                verticalOscillationCm: 8.2,
                strideLengthMeters: 1.20,
                gradeFraction: 0.0
            )
            buffer.append(tick)
        }

        var tracker = EfficiencyDriftTracker(location: .outdoor)
        let efLocked = tracker.lockBaseline(from: buffer, in: 300...600)
        #expect(efLocked == true)
        #expect(tracker.efSource == .power)
        if let ef0 = tracker.ef0 {
            #expect(abs(ef0 - (240.0 / 145.0)) < 0.001)
        } else {
            Issue.record("EF_0 should be populated")
        }

        var bdi = BiomechanicalDegradationIndex()
        let bdiLocked = bdi.lockBaseline(from: buffer, in: 300...600)
        #expect(bdiLocked == true)
        #expect(bdi.gct0 == 235.0)
        #expect(bdi.cadence0 == 170.0)
    }
}
