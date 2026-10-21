import Foundation
import Testing
@testable import RunalystCore

@Suite("IntervalSegmenterCore Crucible Tests")
struct IntervalSegmenterCoreTests {

    @Test("Authentic 31-minute interval workout is correctly segmented into corroborated cycles")
    func authenticIntervalsSegmented() {
        let fixture = GoldenTelemetryFixtures.authenticIntervals31Min
        let buckets = fixture.toTelemetryBuckets()

        let report = IntervalSegmenterCore.segment(buckets: buckets)

        #expect(report.isIntermittentWorkout == true)
        #expect(report.cycles.count >= 2)

        for cycle in report.cycles {
            #expect(cycle.isCorroborated == true)
            #expect(cycle.workCadenceSPM > cycle.recoveryCadenceSPM)
            #expect(cycle.workPaceSecondsPerKm < cycle.recoveryPaceSecondsPerKm)
        }

        #expect(report.cycleRegularityScore > 0.0)
    }

    @Test("Adversarial sensor jitter maintains interval cycle corroboration")
    func adversarialSensorJitterTolerance() {
        let fixture = GoldenTelemetryFixtures.authenticIntervals31Min
        let cleanBuckets = fixture.toTelemetryBuckets()
        let noisyBuckets = TelemetryNoiseInjector.injectSensorJitter(to: cleanBuckets, seed: 9999)

        let cleanReport = IntervalSegmenterCore.segment(buckets: cleanBuckets)
        let noisyReport = IntervalSegmenterCore.segment(buckets: noisyBuckets)

        #expect(noisyReport.isIntermittentWorkout == true)
        #expect(abs(noisyReport.cycles.count - cleanReport.cycles.count) <= 1)

        let cleanCorroborated = cleanReport.cycles.filter(\.isCorroborated).count
        let noisyCorroborated = noisyReport.cycles.filter(\.isCorroborated).count
        #expect(noisyCorroborated >= cleanCorroborated - 1)
    }

    @Test("Hilly steady aerobic run is not misclassified as interval surges")
    func hillySteadyRunNotIntervals() {
        let fixture = GoldenTelemetryFixtures.hillySteadyAerobicRun
        let buckets = fixture.toTelemetryBuckets()

        let report = IntervalSegmenterCore.segment(buckets: buckets)

        // Hilly run has pace fluctuations, but cadence is flat (160 SPM).
        // Biometric corroboration gate must reject it as an intermittent interval workout.
        #expect(report.isIntermittentWorkout == false)
    }

    @Test("Continuous monotonic progression run is detected across quintiles")
    func continuousMonotonicProgressionDetected() {
        let fixture = GoldenTelemetryFixtures.monotonicProgressionRun
        let buckets = fixture.toTelemetryBuckets()

        let isProgression = IntervalSegmenterCore.evaluateQuintileProgression(buckets: buckets)
        #expect(isProgression == true)

        let report = IntervalSegmenterCore.segment(buckets: buckets)
        #expect(report.isMonotonicProgression == true)
        #expect(report.isIntermittentWorkout == false)
    }

    @Test("Sub-20s phase debouncing merges momentary cadence flutter")
    func sub20sPhaseDebouncing() {
        var buckets: [TelemetryBucket] = []
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

        // 100 seconds of work (50 buckets of 2s) at 165 SPM, 320 s/km
        for i in 0..<50 {
            buckets.append(TelemetryBucket(
                timestamp: baseDate.addingTimeInterval(Double(i) * 2.0),
                durationSeconds: 2.0,
                distanceMeters: (2.0 / 320.0) * 1000.0,
                paceSecondsPerKm: 320.0,
                cadenceSPM: 165.0,
                heartRateBPM: 160.0
            ))
        }

        // 10-second momentary dip (< 20s) at 145 SPM (5 buckets of 2s)
        for i in 0..<5 {
            buckets.append(TelemetryBucket(
                timestamp: baseDate.addingTimeInterval(100.0 + Double(i) * 2.0),
                durationSeconds: 2.0,
                distanceMeters: (2.0 / 400.0) * 1000.0,
                paceSecondsPerKm: 400.0,
                cadenceSPM: 145.0,
                heartRateBPM: 155.0
            ))
        }

        // Another 100 seconds of work (50 buckets of 2s) at 165 SPM
        for i in 0..<50 {
            buckets.append(TelemetryBucket(
                timestamp: baseDate.addingTimeInterval(110.0 + Double(i) * 2.0),
                durationSeconds: 2.0,
                distanceMeters: (2.0 / 320.0) * 1000.0,
                paceSecondsPerKm: 320.0,
                cadenceSPM: 165.0,
                heartRateBPM: 162.0
            ))
        }

        let cycles = IntervalSegmenterCore.extractOscillationCycles(buckets: buckets)
        // With debouncing, the 10s dip (< 20s) is merged into the surrounding work phase
        #expect(cycles.isEmpty)
    }

    @Test("Dominant pace surge corroborates even with high cardiac lag")
    func dominantPaceSurgeCorroboration() {
        var buckets: [TelemetryBucket] = []
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

        // Recovery: 3 min at 480 s/km, 148 SPM, 150 BPM
        for i in 0..<6 {
            buckets.append(TelemetryBucket(
                timestamp: baseDate.addingTimeInterval(Double(i) * 30.0),
                durationSeconds: 30.0,
                distanceMeters: (30.0 / 480.0) * 1000.0,
                paceSecondsPerKm: 480.0,
                cadenceSPM: 148.0,
                heartRateBPM: 150.0
            ))
        }

        // Dominant surge: 3 min at 360 s/km (120 s/km faster!), 160 SPM, 151 BPM (cardiac lag: +1 BPM)
        for i in 0..<6 {
            buckets.append(TelemetryBucket(
                timestamp: baseDate.addingTimeInterval(180.0 + Double(i) * 30.0),
                durationSeconds: 30.0,
                distanceMeters: (30.0 / 360.0) * 1000.0,
                paceSecondsPerKm: 360.0,
                cadenceSPM: 160.0,
                heartRateBPM: 151.0
            ))
        }

        // Recovery: 3 min at 480 s/km, 148 SPM, 152 BPM
        for i in 0..<6 {
            buckets.append(TelemetryBucket(
                timestamp: baseDate.addingTimeInterval(360.0 + Double(i) * 30.0),
                durationSeconds: 30.0,
                distanceMeters: (30.0 / 480.0) * 1000.0,
                paceSecondsPerKm: 480.0,
                cadenceSPM: 148.0,
                heartRateBPM: 152.0
            ))
        }

        let cycles = IntervalSegmenterCore.extractOscillationCycles(buckets: buckets)
        #expect(cycles.count >= 1)
        #expect(cycles.first?.isDominantPaceSurge == true)
        #expect(cycles.first?.isCorroborated == true)
    }
}
