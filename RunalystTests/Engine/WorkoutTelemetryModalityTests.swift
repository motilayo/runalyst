import XCTest
@testable import Runalyst

final class WorkoutTelemetryModalityTests: XCTestCase {

    private func createRun(
        type: String,
        duration: Double = 1800.0,
        workingHR: Double = 138.0,
        workingCadence: Double = 160.0,
        workingPace: Double = 330.0,
        drillName: String? = nil,
        percentZone4: Double = 0.02
    ) -> RunRecord {
        let run = RunRecord(
            id: UUID(),
            hkWorkoutID: UUID(),
            date: Date(),
            totalDistanceMeters: 5000.0,
            duration: duration,
            rawAvgPace: workingPace,
            rawAvgHeartRate: workingHR,
            rawAvgCadence: workingCadence,
            workingAvgPace: workingPace,
            workingAvgCadence: workingCadence,
            workingAvgHeartRate: workingHR,
            paceCV: 0.05,
            paceSlope: 0.0,
            percentZone4: percentZone4,
            detectedTypeRaw: type
        )
        if let drillName = drillName {
            run.framboiseTags.append("drill:\(drillName)")
            run.framboiseTags.append("userLinkedDrill")
        }
        return run
    }

    func testAerobicWorkoutsRouteToHeartRate() {
        let aerobicTypes = ["Zone 2", "Easy Run", "Steady Effort", "Long Run", "Recovery Run"]

        for type in aerobicTypes {
            let run = createRun(type: type, workingHR: 136.0)
            let modality = WorkoutTelemetryModalityResolver.defaultModality(for: run)
            XCTAssertEqual(
                modality,
                .heartRate,
                "Workout type '\(type)' must route primarily to Heart Rate Trajectory."
            )
        }
    }

    func testContinuousAerobicDrillsRouteToHeartRate() {
        let continuousDrills = ["Zone 2 Run", "Zone 2 Easy Aerobic Base", "Aerobic Flush", "Recovery Jog"]

        for drill in continuousDrills {
            let run = createRun(type: "Other", workingHR: 134.0, drillName: drill)
            let modality = WorkoutTelemetryModalityResolver.defaultModality(for: run)
            XCTAssertEqual(
                modality,
                .heartRate,
                "Continuous aerobic drill '\(drill)' must route primarily to Heart Rate Trajectory."
            )
        }
    }

    func testTechniqueAndIntervalWorkoutsRouteToCadence() {
        let intervalTypes = [
            "Cadence Pyramids",
            "Rhythm Intervals",
            "Fartlek",
            "Tempo Surges",
            "Strides",
            "Intervals",
            "Hill Repeats"
        ]

        for type in intervalTypes {
            let run = createRun(type: type, workingHR: 165.0)
            let modality = WorkoutTelemetryModalityResolver.defaultModality(for: run)
            XCTAssertEqual(
                modality,
                .cadence,
                "Technique/interval workout '\(type)' must route primarily to Cadence Rhythm."
            )
        }
    }

    func testMissingHeartRateFallsBackToCadence() {
        let runWithoutHR = createRun(type: "Zone 2", workingHR: 0.0)
        let modality = WorkoutTelemetryModalityResolver.defaultModality(for: runWithoutHR)
        XCTAssertEqual(
            modality,
            .cadence,
            "Zone 2 workout with 0 BPM heart rate must gracefully fall back to Cadence Rhythm."
        )
    }

    func testLowConfidenceHeartRateSensorFallsBackToCadence() {
        // Run with active pace (300 s/km = 5:00/km) for 10 minutes but implausibly low HR (62 BPM)
        let lowConfidenceRun = createRun(type: "Easy Run", duration: 600.0, workingHR: 62.0, workingPace: 300.0)
        XCTAssertTrue(lowConfidenceRun.isHeartRateSensorLowConfidence)

        let modality = WorkoutTelemetryModalityResolver.defaultModality(for: lowConfidenceRun)
        XCTAssertEqual(
            modality,
            .cadence,
            "Low sensor confidence HR must gracefully fall back to Cadence Rhythm."
        )
    }

    func testWorkoutTelemetryModalityMetadata() {
        XCTAssertEqual(WorkoutTelemetryModality.heartRate.id, "Heart Rate")
        XCTAssertEqual(WorkoutTelemetryModality.heartRate.iconName, "heart.fill")

        XCTAssertEqual(WorkoutTelemetryModality.cadence.id, "Cadence Rhythm")
        XCTAssertEqual(WorkoutTelemetryModality.cadence.iconName, "metronome.fill")
    }
}
