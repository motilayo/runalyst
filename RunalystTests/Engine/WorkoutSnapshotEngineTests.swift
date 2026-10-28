import XCTest
import SwiftData
@testable import Runalyst
@testable import RunalystCore

@MainActor
final class WorkoutSnapshotEngineTests: XCTestCase {

    func testWorkoutSnapshotEngineResolvesSnapshotAccurately() throws {
        let (now, calendar, volumeSamples) = GoldenTemporalFixtures.makeReferenceTimeline()

        let runRecords: [RunRecord] = volumeSamples.map { sample in
            RunRecord(
                hkWorkoutID: sample.id,
                date: sample.date,
                totalDistanceMeters: sample.totalDistanceMeters,
                duration: sample.durationSeconds,
                rawAvgPace: sample.workingAvgPace,
                rawAvgHeartRate: Double(sample.workingAvgHeartRate),
                rawAvgCadence: sample.workingAvgCadence,
                workingAvgPace: sample.workingAvgPace,
                workingAvgCadence: sample.workingAvgCadence,
                workingAvgHeartRate: Double(sample.workingAvgHeartRate),
                paceCV: 0.03,
                paceSlope: 0.0,
                percentZone4: 0.0,
                detectedTypeRaw: sample.classification
            )
        }

        WorkoutSnapshotEngine.shared.invalidate()
        let snapshot = WorkoutSnapshotEngine.shared.resolveSnapshot(
            runs: runRecords,
            now: now,
            calendar: calendar
        )

        // Verifies the exact authentic numbers from user screenshot
        XCTAssertEqual(snapshot.thisWeek.totalDistanceKm, 9.46)
        XCTAssertEqual(snapshot.lastWeek.totalDistanceKm, 19.5)
        XCTAssertEqual(snapshot.twoWeeksAgo.totalDistanceKm, 18.2)
        XCTAssertEqual(snapshot.trailing7Days.totalDistanceKm, 19.5)
        XCTAssertEqual(snapshot.thisWeek.workoutCount, 4)
    }

    func testTreadmillCalibrationMutationUpdatesSnapshot() throws {
        let (now, calendar, volumeSamples) = GoldenTemporalFixtures.makeReferenceTimeline()

        var runRecords: [RunRecord] = volumeSamples.map { sample in
            RunRecord(
                hkWorkoutID: sample.id,
                date: sample.date,
                totalDistanceMeters: sample.totalDistanceMeters,
                duration: sample.durationSeconds,
                rawAvgPace: sample.workingAvgPace,
                rawAvgHeartRate: Double(sample.workingAvgHeartRate),
                rawAvgCadence: sample.workingAvgCadence,
                workingAvgPace: sample.workingAvgPace,
                workingAvgCadence: sample.workingAvgCadence,
                workingAvgHeartRate: Double(sample.workingAvgHeartRate),
                paceCV: 0.03,
                paceSlope: 0.0,
                percentZone4: 0.0,
                detectedTypeRaw: sample.classification
            )
        }

        WorkoutSnapshotEngine.shared.invalidate()
        let initialSnapshot = WorkoutSnapshotEngine.shared.resolveSnapshot(
            runs: runRecords,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(initialSnapshot.thisWeek.totalDistanceKm, 9.46)

        // Simulate post-workout treadmill calibration on Tuesday easy run:
        // Distance calibrated from 1,660m (1.66km) to 2,000m (2.00km) (+340m)
        if let lastRun = runRecords.last {
            lastRun.totalDistanceMeters = 2000.0
            lastRun.workingDistanceMeters = 2000.0
        }

        WorkoutSnapshotEngine.shared.invalidate()
        let updatedSnapshot = WorkoutSnapshotEngine.shared.resolveSnapshot(
            runs: runRecords,
            now: now,
            calendar: calendar
        )

        // 9.46 km - 1.66 km + 2.00 km = 9.80 km
        XCTAssertEqual(updatedSnapshot.thisWeek.totalDistanceKm, 9.80, accuracy: 0.01)
    }
}
