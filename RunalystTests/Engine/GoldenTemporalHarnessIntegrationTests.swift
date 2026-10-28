import XCTest
import SwiftData
@testable import Runalyst
@testable import RunalystCore

@MainActor
final class GoldenTemporalHarnessIntegrationTests: XCTestCase {

    func testIntegrationConservationOfDistanceAcrossRunRecords() throws {
        let (now, calendar, volumeSamples) = GoldenTemporalFixtures.makeReferenceTimeline()

        // Create SwiftData RunRecord instances from authentic volume samples
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

        // Current calendar week boundary: Monday 00:00:00 to Next Monday 00:00:00
        let todayStart = calendar.startOfDay(for: now)
        let mondayStart = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        let nextMondayStart = calendar.date(byAdding: .day, value: 7, to: mondayStart) ?? mondayStart

        let thisWeekRuns = runRecords.filter { $0.date >= mondayStart && $0.date < nextMondayStart }
        let totalDistanceKm = thisWeekRuns.reduce(0.0) { $0 + $1.totalDistanceMeters } / 1000.0

        XCTAssertEqual(thisWeekRuns.count, 4, "Must contain exactly 4 workouts this week")
        XCTAssertEqual(totalDistanceKm, 9.46, "This week total distance must equal 9.46 km")
        XCTAssertNotEqual(totalDistanceKm, 19.5, "This week must never report 19.5 km")
    }

    func testIntegrationDimensionalPaceVsUnweightedPace() throws {
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

        let todayStart = calendar.startOfDay(for: now)
        let mondayStart = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        let thisWeekRuns = runRecords.filter { $0.date >= mondayStart }

        let totalDuration = thisWeekRuns.reduce(0.0) { $0 + $1.duration }
        let totalDistanceKm = thisWeekRuns.reduce(0.0) { $0 + $1.totalDistanceMeters } / 1000.0

        let dimensionalPace = totalDuration / totalDistanceKm
        let unweightedPace = thisWeekRuns.map(\.workingAvgPace).reduce(0.0, +) / Double(thisWeekRuns.count)

        XCTAssertEqual(dimensionalPace, 467.86, accuracy: 0.1, "Dimensional pace must be 467.86 s/km")
        XCTAssertEqual(unweightedPace, 447.25, accuracy: 0.1, "Unweighted pace has a 20.6s error")
        XCTAssertNotEqual(dimensionalPace, unweightedPace)
    }
}
