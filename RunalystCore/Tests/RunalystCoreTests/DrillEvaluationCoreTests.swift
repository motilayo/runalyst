import Foundation
@testable import RunalystCore
import Testing

@Suite("Drill Evaluation Core Tests")
struct DrillEvaluationCoreTests {

    @Test("Evaluates continuous drill adherence correctly")
    func testContinuousDrillEvaluation() {
        let now = Date()
        let buckets = [
            TelemetryBucket(timestamp: now, durationSeconds: 60, distanceMeters: 180, paceSecondsPerKm: 333, cadenceSPM: 165, heartRateBPM: 140),
            TelemetryBucket(timestamp: now.addingTimeInterval(60), durationSeconds: 60, distanceMeters: 180, paceSecondsPerKm: 333, cadenceSPM: 167, heartRateBPM: 142)
        ]

        let context = DrillEvaluationContextCore(
            drillIdentifier: "zone2_run",
            effectiveTargetMin: 162,
            effectiveTargetMax: 170,
            baselineCadence: 160,
            oscDelta: -0.5,
            isAerobicContinuous: true
        )

        let summary = DrillEvaluationCore.evaluateContinuous(buckets: buckets, context: context)
        #expect(summary.intervalsMet == 1)
        #expect(summary.totalIntervals == 1)
        #expect(summary.workCadenceAvg == 166)
        #expect(summary.tier == .exceeded)
    }

    @Test("Serializes and deserializes framboise tags with rich reps")
    func testFramboiseTagsRoundTrip() {
        let rep1 = DrillIntervalRepCore(
            repIndex: 1,
            workCadence: 172,
            workHeartRate: 155,
            recoveryCadence: 135,
            recoveryHeartRate: 125,
            isMet: true,
            durationSeconds: 30.0,
            workPaceSecondsPerKm: 300.0,
            recoveryPaceSecondsPerKm: 450.0
        )
        let rep2 = DrillIntervalRepCore(
            repIndex: 2,
            workCadence: 175,
            workHeartRate: 160,
            recoveryCadence: 138,
            recoveryHeartRate: 128,
            isMet: true,
            durationSeconds: 30.0,
            workPaceSecondsPerKm: 295.0,
            recoveryPaceSecondsPerKm: 440.0
        )

        let summary = DrillIntervalSummaryCore(
            drillIdentifier: "cadence_pyramids",
            intervalsMet: 2,
            totalIntervals: 2,
            workCadenceAvg: 174,
            recoveryCadenceAvg: 137,
            reps: [rep1, rep2],
            tier: .met,
            verdict: "Great execution"
        )

        let tags = summary.framboiseTags
        #expect(tags.contains(where: { $0.hasPrefix("drillIntervals:2/2") }))

        let restored = DrillIntervalSummaryCore.from(tags: tags, drillIdentifier: "cadence_pyramids")
        #expect(restored != nil)
        #expect(restored?.intervalsMet == 2)
        #expect(restored?.totalIntervals == 2)
        #expect(restored?.reps.count == 2)
        #expect(restored?.reps[0].workCadence == 172)
        #expect(restored?.reps[0].recoveryHeartRateDrop == 30)
    }
}
