import XCTest
import HealthKit
@testable import Runalyst

final class DrillPatternRecognitionTests: XCTestCase {

    private func createBucket(offsetSeconds: Double, cadence: Double, hr: Double, pace: Double = 300.0, duration: Double = 15.0) -> BucketData {
        let baseDate = Date(timeIntervalSince1970: 1700000000)
        return BucketData(
            startTime: baseDate.addingTimeInterval(offsetSeconds),
            distanceMeters: (duration / pace) * 1000.0,
            durationSeconds: duration,
            meanPaceSecPerKm: pace,
            meanCadence: cadence,
            meanHR: hr,
            meanVerticalOscillation: 9.0
        )
    }

    func testRhythmIntervalsPatternDetection() {
        var buckets: [BucketData] = []
        var t: Double = 0

        // Warmup: 180s at 150 SPM
        for _ in 0..<12 {
            buckets.append(createBucket(offsetSeconds: t, cadence: 150.0, hr: 135.0))
            t += 15.0
        }

        // 5 reps: 45s work at ~164 SPM, 75s recovery at 144 SPM
        for rep in 0..<5 {
            let repCadence = 164.0 + Double(rep % 2) * 0.5
            for _ in 0..<3 { // 45s
                buckets.append(createBucket(offsetSeconds: t, cadence: repCadence, hr: 160.0))
                t += 15.0
            }
            for _ in 0..<5 { // 75s
                buckets.append(createBucket(offsetSeconds: t, cadence: 144.0, hr: 138.0))
                t += 15.0
            }
        }

        let match = DrillPatternRecognizer.recognizeDrill(
            buckets: buckets,
            baselineCadence: 152,
            workoutDuration: t
        )

        XCTAssertNotNil(match, "Rhythm Intervals pattern must be recognized")
        XCTAssertEqual(match?.drillId, .rhythmIntervals)
        XCTAssertGreaterThanOrEqual(match?.confidence ?? 0, 0.90)
        XCTAssertEqual(match?.detectedIntervalCount, 5)
    }

    func testRhythmIntervalsFloatRecoveryPatternDetection() {
        var buckets: [BucketData] = []
        var t: Double = 0

        // Warmup: 120s at 150 SPM
        for _ in 0..<8 {
            buckets.append(createBucket(offsetSeconds: t, cadence: 150.0, hr: 135.0))
            t += 15.0
        }

        // 4 reps (10 min drill): 30s work at 158 SPM (+8 above 150 baseline), 45s easy jog float recovery at 149 SPM (-1 below baseline)
        for _ in 0..<4 {
            for _ in 0..<2 { // 30s
                buckets.append(createBucket(offsetSeconds: t, cadence: 158.0, hr: 155.0))
                t += 15.0
            }
            for _ in 0..<3 { // 45s
                buckets.append(createBucket(offsetSeconds: t, cadence: 149.0, hr: 140.0))
                t += 15.0
            }
        }

        // Cooldown: 60s at 148 SPM
        for _ in 0..<4 {
            buckets.append(createBucket(offsetSeconds: t, cadence: 148.0, hr: 132.0))
            t += 15.0
        }

        let match = DrillPatternRecognizer.recognizeDrill(
            buckets: buckets,
            baselineCadence: 150,
            workoutDuration: t
        )

        XCTAssertNotNil(match, "Rhythm Intervals with float recovery (9 SPM contrast) must be recognized")
        XCTAssertEqual(match?.drillId, .rhythmIntervals)
        XCTAssertEqual(match?.detectedIntervalCount, 4)
    }

    func testRhythmIntervalsFiveMinutesThreeRepsDetection() {
        var buckets: [BucketData] = []
        var t: Double = 0

        // Warmup: 60s at 150 SPM
        for _ in 0..<4 {
            buckets.append(createBucket(offsetSeconds: t, cadence: 150.0, hr: 130.0))
            t += 15.0
        }

        // 3 reps (5 min drill): 30s work at 162 SPM, 30s float recovery at 151 SPM
        for _ in 0..<3 {
            for _ in 0..<2 { // 30s
                buckets.append(createBucket(offsetSeconds: t, cadence: 162.0, hr: 154.0))
                t += 15.0
            }
            for _ in 0..<2 { // 30s
                buckets.append(createBucket(offsetSeconds: t, cadence: 151.0, hr: 138.0))
                t += 15.0
            }
        }

        // Cooldown: 30s at 148 SPM
        for _ in 0..<2 {
            buckets.append(createBucket(offsetSeconds: t, cadence: 148.0, hr: 130.0))
            t += 15.0
        }

        let match = DrillPatternRecognizer.recognizeDrill(
            buckets: buckets,
            baselineCadence: 152,
            workoutDuration: t
        )

        XCTAssertNotNil(match, "5-minute 3-rep Rhythm Intervals must be recognized")
        XCTAssertEqual(match?.drillId, .rhythmIntervals)
        XCTAssertEqual(match?.detectedIntervalCount, 3)
    }

    func testCadencePyramidsPatternDetection() {
        var buckets: [BucketData] = []
        var t: Double = 0

        // Warmup: 180s at 148 SPM
        for _ in 0..<12 {
            buckets.append(createBucket(offsetSeconds: t, cadence: 148.0, hr: 130.0))
            t += 15.0
        }

        // 4 reps: 154, 158, 162, 166 SPM with 90s recovery at 142 SPM
        for repCadence in [154.0, 158.0, 162.0, 166.0] {
            for _ in 0..<4 { // 60s
                buckets.append(createBucket(offsetSeconds: t, cadence: repCadence, hr: 155.0))
                t += 15.0
            }
            for _ in 0..<6 { // 90s
                buckets.append(createBucket(offsetSeconds: t, cadence: 142.0, hr: 138.0))
                t += 15.0
            }
        }

        let match = DrillPatternRecognizer.recognizeDrill(
            buckets: buckets,
            baselineCadence: 150,
            workoutDuration: t
        )

        XCTAssertNotNil(match, "Cadence Pyramids pattern must be recognized")
        XCTAssertEqual(match?.drillId, .cadencePyramids)
        XCTAssertGreaterThanOrEqual(match?.confidence ?? 0, 0.90)
        XCTAssertEqual(match?.detectedIntervalCount, 4)
    }

    func testStridesPatternDetection() {
        var buckets: [BucketData] = []
        var t: Double = 0

        // Warmup: 180s at 155 SPM
        for _ in 0..<12 {
            buckets.append(createBucket(offsetSeconds: t, cadence: 155.0, hr: 135.0))
            t += 15.0
        }

        // 6 reps: 30s sprint at 182 SPM, 60s walking recovery at 115 SPM
        for _ in 0..<6 {
            for _ in 0..<2 { // 30s sprint
                buckets.append(createBucket(offsetSeconds: t, cadence: 182.0, hr: 165.0))
                t += 15.0
            }
            for _ in 0..<4 { // 60s walk
                buckets.append(createBucket(offsetSeconds: t, cadence: 115.0, hr: 125.0))
                t += 15.0
            }
        }

        let match = DrillPatternRecognizer.recognizeDrill(
            buckets: buckets,
            baselineCadence: 155,
            workoutDuration: t
        )

        XCTAssertNotNil(match, "Strides pattern must be recognized")
        XCTAssertEqual(match?.drillId, .strides)
        XCTAssertGreaterThanOrEqual(match?.confidence ?? 0, 0.90)
        XCTAssertGreaterThanOrEqual(match?.detectedIntervalCount ?? 0, 5)
    }

    func testTempoSurgesPatternDetection() {
        var buckets: [BucketData] = []
        var t: Double = 0

        // 20 min continuous tempo run (80 buckets), base cadence 162, HR 155
        for i in 0..<80 {
            if (20 <= i && i < 24) || (40 <= i && i < 44) || (60 <= i && i < 64) {
                // 60s surges: Cadence 174, HR 166 (Zone 4)
                buckets.append(createBucket(offsetSeconds: t, cadence: 174.0, hr: 166.0, pace: 240.0))
            } else {
                // Base tempo: Cadence 162, HR 155 (Zone 3)
                buckets.append(createBucket(offsetSeconds: t, cadence: 162.0, hr: 155.0, pace: 270.0))
            }
            t += 15.0
        }

        let match = DrillPatternRecognizer.recognizeDrill(
            buckets: buckets,
            baselineCadence: 160,
            workoutDuration: t,
            zone4Threshold: 161.5
        )

        XCTAssertNotNil(match, "Tempo Surges pattern must be recognized")
        XCTAssertEqual(match?.drillId, .tempoSurges)
        XCTAssertEqual(match?.detectedIntervalCount, 3)
    }

    func testSteadyContinuousRunDoesNotTriggerIntervalDrills() {
        var buckets: [BucketData] = []
        var t: Double = 0

        // 20-minute continuous run at steady turnover with normal variability
        for i in 0..<80 {
            let cadence = 160.0 + Double(i % 3) * 0.4
            buckets.append(createBucket(offsetSeconds: t, cadence: cadence, hr: 148.0))
            t += 15.0
        }

        let match = DrillPatternRecognizer.recognizeDrill(
            buckets: buckets,
            baselineCadence: 160,
            workoutDuration: t
        )

        XCTAssertNil(match, "Steady continuous run without drill signature must return nil")
    }

    func testZone2ContinuousRunIsNotFalselyRecognizedAsDrill() {
        var buckets: [BucketData] = []
        var t: Double = 0

        // 15-minute continuous run with low cadence CV and HR at 136 BPM (Zone 2)
        for i in 0..<60 {
            let cadence = 158.0 + Double(i % 2) * 0.2
            buckets.append(createBucket(offsetSeconds: t, cadence: cadence, hr: 136.0))
            t += 15.0
        }

        let match = DrillPatternRecognizer.recognizeDrill(
            buckets: buckets,
            baselineCadence: 158,
            workoutDuration: t,
            zone2Threshold: 142.0
        )

        XCTAssertNil(match, "Continuous Zone 2 run must return nil to prevent falsely tagging standard runs as drills")
    }

    func testRecoveryJogContinuousRunIsNotFalselyRecognizedAsDrill() {
        var buckets: [BucketData] = []
        var t: Double = 0

        // 15-minute continuous run with low cadence CV and HR at 122 BPM (Zone 1)
        for i in 0..<60 {
            let cadence = 152.0 + Double(i % 2) * 0.2
            buckets.append(createBucket(offsetSeconds: t, cadence: cadence, hr: 122.0))
            t += 15.0
        }

        let match = DrillPatternRecognizer.recognizeDrill(
            buckets: buckets,
            baselineCadence: 154,
            workoutDuration: t,
            zone1Threshold: 125.0
        )

        XCTAssertNil(match, "Continuous Recovery jog must return nil to prevent falsely tagging standard runs as drills")
    }

    func testUrbanTrafficStopsDoNotTriggerRhythmIntervals() {
        var buckets: [BucketData] = []
        var t: Double = 0

        // 20-minute steady run (162 SPM) with 2 red light stops (cadence 0 for 15s each)
        for i in 0..<80 {
            if i == 20 || i == 50 {
                buckets.append(createBucket(offsetSeconds: t, cadence: 0.0, hr: 130.0))
            } else {
                let cadence = 162.0 + Double(i % 2) * 0.4
                buckets.append(createBucket(offsetSeconds: t, cadence: cadence, hr: 148.0))
            }
            t += 15.0
        }

        let match = DrillPatternRecognizer.recognizeDrill(
            buckets: buckets,
            baselineCadence: 162,
            workoutDuration: t
        )

        XCTAssertNil(match, "Continuous run with street traffic stops must never be classified as Rhythm Intervals")
    }

    func testWorkoutBridgeMatchDrillAutonomousRecognition() {
        var buckets: [BucketData] = []
        var t: Double = 0

        // Warmup: 180s at 150 SPM
        for _ in 0..<12 {
            buckets.append(createBucket(offsetSeconds: t, cadence: 150.0, hr: 135.0))
            t += 15.0
        }

        // 5 reps: 45s work at 164 SPM, 75s recovery at 144 SPM
        for _ in 0..<5 {
            for _ in 0..<3 {
                buckets.append(createBucket(offsetSeconds: t, cadence: 164.0, hr: 160.0))
                t += 15.0
            }
            for _ in 0..<5 {
                buckets.append(createBucket(offsetSeconds: t, cadence: 144.0, hr: 138.0))
                t += 15.0
            }
        }

        // Test WorkoutBridge.matchDrill overload with buckets and no prior intent
        let intent = WorkoutBridge.matchDrill(
            workoutDate: Date(),
            durationSeconds: t,
            metadata: nil,
            buckets: buckets,
            baselineCadence: 152
        )

        XCTAssertNotNil(intent, "WorkoutBridge must autonomously match Rhythm Intervals from buckets")
        XCTAssertEqual(intent?.drillTitle, "Rhythm Intervals")
        XCTAssertEqual(intent?.preRunDrillId, "rhythm_intervals")
    }

    func testAppleFitnessPlusIntervalRunIsNotRecognizedAsTempoSurges() {
        // User reported issue: Apple Fitness+ intervals run with 4 sets of song-based easy run + hard push
        // must NOT be classified as Tempo Surges.
        var buckets: [BucketData] = []
        var t: Double = 0

        // 4 songs with varying push and recovery lengths based on track arrangement
        // Song 1: 150s easy (158 SPM, 145 HR), 90s push (174 SPM, 166 HR)
        // Song 2: 180s easy (158 SPM, 148 HR), 150s push (175 SPM, 168 HR)
        // Song 3: 210s easy (157 SPM, 150 HR), 105s push (176 SPM, 170 HR)
        // Song 4: 180s easy (158 SPM, 152 HR), 135s push (176 SPM, 172 HR)
        let sets: [(easySec: Double, pushSec: Double)] = [
            (150.0, 90.0),
            (180.0, 150.0),
            (210.0, 105.0),
            (180.0, 135.0)
        ]

        for set in sets {
            let easyBuckets = Int(set.easySec / 15.0)
            for _ in 0..<easyBuckets {
                buckets.append(createBucket(offsetSeconds: t, cadence: 158.0, hr: 148.0, pace: 290.0))
                t += 15.0
            }
            let pushBuckets = Int(set.pushSec / 15.0)
            for _ in 0..<pushBuckets {
                buckets.append(createBucket(offsetSeconds: t, cadence: 175.0, hr: 168.0, pace: 240.0))
                t += 15.0
            }
        }

        let match = DrillPatternRecognizer.recognizeDrill(
            buckets: buckets,
            baselineCadence: 160,
            workoutDuration: t,
            zone4Threshold: 162.0
        )

        XCTAssertNil(match, "Apple Fitness+ song-based 4-set push/easy intervals must not match Runalyst Tempo Surges")
    }

    func testWorkoutBridgeExemptsAppleFitnessPlusWorkoutsFromDrillMatching() {
        var buckets: [BucketData] = []
        var t: Double = 0

        // Even if buckets artificially mimic a drill, Apple Fitness+ session metadata must reject drill matching
        for _ in 0..<12 {
            buckets.append(createBucket(offsetSeconds: t, cadence: 150.0, hr: 135.0))
            t += 15.0
        }
        for _ in 0..<5 {
            for _ in 0..<3 {
                buckets.append(createBucket(offsetSeconds: t, cadence: 164.0, hr: 160.0))
                t += 15.0
            }
            for _ in 0..<5 {
                buckets.append(createBucket(offsetSeconds: t, cadence: 144.0, hr: 138.0))
                t += 15.0
            }
        }

        let afpMetadata: [String: Any] = [
            HKMetadataKeyAppleFitnessPlusSession: true
        ]

        let intent = WorkoutBridge.matchDrill(
            workoutDate: Date(),
            durationSeconds: t,
            metadata: afpMetadata,
            buckets: buckets,
            baselineCadence: 152
        )

        XCTAssertNil(intent, "Apple Fitness+ guided sessions must never be tagged as Runalyst drills")
    }

    func testWorkoutBridgeExemptsThirdPartyAppSessions() {
        let thirdPartyMetadata: [String: Any] = [
            "com.nike.running.session": true
        ]

        let isThirdParty = WorkoutBridge.isGuidedOrThirdPartySession(metadata: thirdPartyMetadata)
        XCTAssertTrue(isThirdParty, "Nike Running Club sessions must be recognized as third-party")

        let stravaMetadata: [String: Any] = [
            "StravaActivityId": "12345678"
        ]
        XCTAssertTrue(WorkoutBridge.isGuidedOrThirdPartySession(metadata: stravaMetadata), "Strava sessions must be recognized as third-party")
    }

    func testStrictDrillSchedule15MinTempoSurgesMatches() {
        var buckets: [BucketData] = []
        var t: Double = 0

        // 20 min continuous tempo run (80 buckets), base cadence 162, HR 155
        // 15-minute Tempo Surges: 3 iterations x 120s (8 buckets each)
        for i in 0..<80 {
            if (16 <= i && i < 24) || (36 <= i && i < 44) || (56 <= i && i < 64) {
                // 120s surges: Cadence 174, HR 166 (Zone 4)
                buckets.append(createBucket(offsetSeconds: t, cadence: 174.0, hr: 166.0, pace: 240.0))
            } else {
                // Base tempo: Cadence 162, HR 155 (Zone 3)
                buckets.append(createBucket(offsetSeconds: t, cadence: 162.0, hr: 155.0, pace: 270.0))
            }
            t += 15.0
        }

        let match = DrillPatternRecognizer.recognizeDrill(
            buckets: buckets,
            baselineCadence: 160,
            workoutDuration: t,
            zone4Threshold: 161.5
        )

        XCTAssertNotNil(match, "15-minute Tempo Surges (3 x 120s) must be recognized")
        XCTAssertEqual(match?.drillId, .tempoSurges)
        XCTAssertEqual(match?.detectedIntervalCount, 3)
    }

    func testRhythmIntervalsWithSlowWarmupAndFloatRecovery() {
        var buckets: [BucketData] = []
        var t: Double = 0

        // Slow warmup: 60s at 126 SPM
        for _ in 0..<4 {
            buckets.append(createBucket(offsetSeconds: t, cadence: 126.0, hr: 120.0))
            t += 15.0
        }

        // 5 reps: 45s work at 163 SPM, 75s easy jog float recovery at 157 SPM
        for _ in 0..<5 {
            for _ in 0..<3 { // 45s work
                buckets.append(createBucket(offsetSeconds: t, cadence: 163.0, hr: 160.0))
                t += 15.0
            }
            for _ in 0..<5 { // 75s float recovery
                buckets.append(createBucket(offsetSeconds: t, cadence: 157.0, hr: 142.0))
                t += 15.0
            }
        }

        let match = DrillPatternRecognizer.recognizeDrill(
            buckets: buckets,
            baselineCadence: 154,
            workoutDuration: t
        )

        XCTAssertNotNil(match, "Rhythm Intervals with 126 SPM slow warmup and 157 SPM float recovery must be autonomously recognized")
        XCTAssertEqual(match?.drillId, .rhythmIntervals)
        XCTAssertEqual(match?.detectedIntervalCount, 5)
        XCTAssertEqual(match?.avgWorkCadence, 163)
        XCTAssertEqual(match?.avgRecoveryCadence, 157)
    }
}
