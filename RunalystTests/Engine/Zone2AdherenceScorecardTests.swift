import XCTest
@testable import Runalyst

@MainActor
final class Zone2AdherenceScorecardTests: XCTestCase {
    private func makeRun(
        avgHR: Double,
        avgCadence: Double = 153,
        percentZone4: Double = 0.0,
        type: String = "Easy Run"
    ) -> RunRecord {
        RunRecord(
            hkWorkoutID: UUID(),
            date: Date(),
            totalDistanceMeters: 5000,
            duration: 2400,
            rawAvgPace: 467,
            rawAvgHeartRate: avgHR,
            rawAvgCadence: avgCadence,
            workingAvgPace: 467,
            workingAvgCadence: avgCadence,
            workingAvgHeartRate: avgHR,
            workingDistanceMeters: 5000,
            workingDurationSeconds: 2400,
            paceCV: 0.05,
            paceSlope: 0.0,
            percentZone4: percentZone4,
            detectedTypeRaw: type
        )
    }

    func testZone2AdherenceExceededWhenPreservedCeilingAndHighCadence() {
        let run = makeRun(avgHR: 140, avgCadence: 156, percentZone4: 0.01)
        let adherence = DrillExecutionScorecard.calculateAdherence(
            runRecord: run,
            drillId: .zone2Run,
            baselineCadence: 150
        )
        XCTAssertEqual(adherence.tier, .exceeded)
        XCTAssertEqual(adherence.tier.badgeText(for: .zone2Run), "Optimal")
    }

    func testZone2AdherenceMetWhenWithinCeiling() {
        let run = makeRun(avgHR: 143, avgCadence: 152, percentZone4: 0.03)
        let adherence = DrillExecutionScorecard.calculateAdherence(
            runRecord: run,
            drillId: .zone2Run,
            baselineCadence: 150
        )
        XCTAssertEqual(adherence.tier, .met)
        XCTAssertEqual(adherence.tier.badgeText(for: .zone2Run), "Target Met")
        XCTAssertTrue(adherence.tierDescription.contains("Successfully maintained"))
    }

    func testZone2AdherencePartiallyMetWhenModerateDrift() {
        let run = makeRun(avgHR: 148, avgCadence: 153, percentZone4: 0.04)
        let adherence = DrillExecutionScorecard.calculateAdherence(
            runRecord: run,
            drillId: .zone2Run,
            baselineCadence: 150
        )
        XCTAssertEqual(adherence.tier, .partiallyMet)
        XCTAssertEqual(adherence.tier.badgeText(for: .zone2Run), "Partially Met")
        XCTAssertTrue(adherence.tierDescription.contains("Zone 3"))
    }

    func testZone2AdherenceNotMetWhenElevatedStrain() {
        // Run with 154 BPM average heart rate must fail Zone 2 (ceiling 144 BPM)
        let run = makeRun(avgHR: 154, avgCadence: 153, percentZone4: 0.0)
        let adherence = DrillExecutionScorecard.calculateAdherence(
            runRecord: run,
            drillId: .zone2Run,
            baselineCadence: 150
        )
        XCTAssertEqual(adherence.tier, .notMet)
        XCTAssertEqual(adherence.tier.badgeText(for: .zone2Run), "Not Met")
        XCTAssertTrue(adherence.tierDescription.contains("exceeded Zone 2"))
    }

    func testZone1AdherenceTiers() {
        let optimalRun = makeRun(avgHR: 122, percentZone4: 0.0, type: "Recovery Run")
        let optimalAdherence = DrillExecutionScorecard.calculateAdherence(
            runRecord: optimalRun,
            drillId: .aerobicFlush,
            baselineCadence: 150
        )
        XCTAssertEqual(optimalAdherence.tier, .exceeded)

        let metRun = makeRun(avgHR: 133, percentZone4: 0.02, type: "Recovery Run")
        let metAdherence = DrillExecutionScorecard.calculateAdherence(
            runRecord: metRun,
            drillId: .aerobicFlush,
            baselineCadence: 150
        )
        XCTAssertEqual(metAdherence.tier, .met)

        let notMetRun = makeRun(avgHR: 145, percentZone4: 0.15, type: "Recovery Run")
        let notMetAdherence = DrillExecutionScorecard.calculateAdherence(
            runRecord: notMetRun,
            drillId: .aerobicFlush,
            baselineCadence: 150
        )
        XCTAssertEqual(notMetAdherence.tier, .notMet)
    }
}
