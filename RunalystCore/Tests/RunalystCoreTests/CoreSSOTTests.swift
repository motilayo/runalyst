import Foundation
import Testing
@testable import RunalystCore

@Suite("Core SSOT Consolidation Tests")
struct CoreSSOTTests {

    @Test("Lifetime Milestones & PRs accurately computes PRs and badge unlocks")
    func testLifetimeMilestonesEvaluation() {
        let now = Date(timeIntervalSince1970: 1700000000)
        let sample1 = MilestoneRunSample(
            id: UUID(),
            date: now.addingTimeInterval(-86400 * 5),
            totalDistanceMeters: 5200.0,
            durationSeconds: 1560.0,
            workingAvgPace: 300.0,
            workingAvgCadence: 165.0,
            efficiencyFactor: 1.25
        )
        let sample2 = MilestoneRunSample(
            id: UUID(),
            date: now.addingTimeInterval(-86400 * 2),
            totalDistanceMeters: 10500.0,
            durationSeconds: 2940.0,
            workingAvgPace: 280.0,
            workingAvgCadence: 172.0,
            efficiencyFactor: 1.38
        )

        let summary = LifetimeMilestonesCore.evaluate(samples: [sample1, sample2])

        #expect(summary.totalDistanceMeters == 15700.0)
        #expect(summary.totalDurationSeconds == 4500.0)
        #expect(summary.totalRunsCount == 2)
        #expect(summary.longestRunMeters == 10500.0)
        #expect(summary.fastestPaceSecondsPerKm == 280.0)
        #expect(summary.peakCadenceSPM == 172.0)
        #expect(summary.peakEfficiencyFactor == 1.38)

        // Verify badge unlocking
        let unlocked = Set(summary.badges.filter(\.isUnlocked).map(\.identifier))
        #expect(unlocked.contains(.firstRun))
        #expect(unlocked.contains(.fiveK))
        #expect(unlocked.contains(.tenK))
        #expect(unlocked.contains(.rhythmMaster))
        #expect(unlocked.contains(.aerobicEngine))
        #expect(!unlocked.contains(.halfMarathon))
        #expect(!unlocked.contains(.centuryVolume))
    }

    @Test("Progression Chart accurately aggregates daily runs and calculates Y domain")
    func testProgressionChartDailyAggregation() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1700000000)
        let dayStart = calendar.startOfDay(for: now)

        let r1 = ChartRunInputCore(
            id: "1",
            date: dayStart.addingTimeInterval(3600),
            durationSeconds: 1200.0,
            workingAvgPace: 320.0,
            workingAvgHeartRate: 140,
            efficiencyFactor: 1.20,
            classification: "Steady Effort"
        )
        let r2 = ChartRunInputCore(
            id: "2",
            date: dayStart.addingTimeInterval(7200),
            durationSeconds: 600.0,
            workingAvgPace: 300.0,
            workingAvgHeartRate: 145,
            efficiencyFactor: 1.30,
            classification: "Steady Effort"
        )

        let segments = ProgressionChartCore.evaluateSegments(
            runs: [r1, r2],
            selectedType: "Steady Effort",
            metric: .pace,
            horizonDays: 30,
            now: now,
            calendar: calendar
        )

        #expect(segments.count == 1)
        #expect(segments[0].points.count == 1)
        let expectedWeightedPace = (320.0 * 1200.0 + 300.0 * 600.0) / 1800.0
        #expect(abs(segments[0].points[0].value - expectedWeightedPace) < 0.01)

        let domain = ProgressionChartCore.calculateYDomain(segments: segments, metric: .pace)
        #expect(domain.lower < expectedWeightedPace)
        #expect(domain.upper > expectedWeightedPace)
    }

    @Test("Drill Adherence Core evaluates Zone 2 ceiling and cadence floor deterministically")
    func testDrillAdherenceEvaluation() {
        let inputExceeded = DrillAdherenceInputCore(
            drillIdentifier: "zone2_run",
            actualCadence: 156,
            actualHeartRate: 140,
            baselineCadence: 150,
            heightAdjustedCadenceFloor: 150,
            targetHeartRateZone: 2,
            percentZone4: 0.01,
            isHeartRateTargeted: true,
            isAerobicContinuous: true
        )
        let resultExceeded = DrillAdherenceCore.evaluateAdherence(input: inputExceeded)
        #expect(resultExceeded.tier == .exceeded)
        #expect(resultExceeded.tierDescription.contains("Preserved Zone 2 ceiling"))

        let inputDrift = DrillAdherenceInputCore(
            drillIdentifier: "zone2_run",
            actualCadence: 152,
            actualHeartRate: 158,
            baselineCadence: 150,
            heightAdjustedCadenceFloor: 150,
            targetHeartRateZone: 2,
            percentZone4: 0.25,
            isHeartRateTargeted: true,
            isAerobicContinuous: true
        )
        let resultDrift = DrillAdherenceCore.evaluateAdherence(input: inputDrift)
        #expect(resultDrift.tier == .notMet)
    }

    @Test("Banister ACWR formatStatus produces unified labels and risk color tokens")
    func testBanisterACWRStatus() {
        let low = BanisterReadinessCore.formatStatus(acwr: 0.72)
        #expect(low.zone == .low)
        #expect(low.displayText.contains("Building Base (0.72)"))
        #expect(low.colorName == "blue")

        let optimal = BanisterReadinessCore.formatStatus(acwr: 1.15)
        #expect(optimal.zone == .optimal)
        #expect(optimal.displayText.contains("Optimal (1.15)"))
        #expect(optimal.colorName == "green")

        let elevated = BanisterReadinessCore.formatStatus(acwr: 1.38)
        #expect(elevated.zone == .elevated)
        #expect(elevated.displayText.contains("Elevated (1.38)"))
        #expect(elevated.colorName == "orange")

        let spike = BanisterReadinessCore.formatStatus(acwr: 1.55)
        #expect(spike.zone == .spike)
        #expect(spike.displayText.contains("Spike Risk (1.55)"))
        #expect(spike.colorName == "red")
    }
}
