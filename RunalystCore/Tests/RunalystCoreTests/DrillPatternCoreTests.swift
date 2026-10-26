import Foundation
@testable import RunalystCore
import Testing

@Suite("Drill Pattern Core Tests")
struct DrillPatternCoreTests {

    @Test("Matches strides pattern from accelerated work buckets")
    func testStridesDetection() {
        var buckets: [TelemetryBucket] = []
        let baseDate = Date(timeIntervalSince1970: 1700000000)
        var t: Double = 0

        // Warmup: 180s at 155 SPM
        for _ in 0..<12 {
            buckets.append(TelemetryBucket(
                timestamp: baseDate.addingTimeInterval(t),
                durationSeconds: 15.0,
                distanceMeters: 50.0,
                paceSecondsPerKm: 300.0,
                cadenceSPM: 155.0,
                heartRateBPM: 135.0
            ))
            t += 15.0
        }

        // 6 reps: 30s sprint at 182 SPM, 60s walking recovery at 115 SPM
        for _ in 0..<6 {
            for _ in 0..<2 { // 30s sprint
                buckets.append(TelemetryBucket(
                    timestamp: baseDate.addingTimeInterval(t),
                    durationSeconds: 15.0,
                    distanceMeters: 75.0,
                    paceSecondsPerKm: 200.0,
                    cadenceSPM: 182.0,
                    heartRateBPM: 165.0
                ))
                t += 15.0
            }
            for _ in 0..<4 { // 60s walk
                buckets.append(TelemetryBucket(
                    timestamp: baseDate.addingTimeInterval(t),
                    durationSeconds: 15.0,
                    distanceMeters: 30.0,
                    paceSecondsPerKm: 500.0,
                    cadenceSPM: 115.0,
                    heartRateBPM: 125.0
                ))
                t += 15.0
            }
        }

        let match = DrillPatternCore.recognizeDrill(
            buckets: buckets,
            baselineCadence: 155,
            workoutDuration: t
        )

        #expect(match != nil)
        #expect(match?.drillIdentifier == "strides")
        #expect(match?.detectedIntervalCount == 6)
        #expect(match?.avgWorkCadence == 182)
    }

    @Test("Matches schedule correctly across durations")
    func testScheduleMatching() {
        let schedule5Min = DrillScheduleCore.schedule(for: "cadence_pyramids", durationMinutes: 5)
        #expect(schedule5Min.durationMinutes == 5)
        #expect(schedule5Min.iterations == 3)

        let matches = schedule5Min.matches(
            workoutDuration: 300.0,
            detectedIterations: 3,
            avgWorkDuration: 20.0,
            avgRecoveryDuration: 30.0
        )
        #expect(matches == true)
    }
}
