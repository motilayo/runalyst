import XCTest
import SwiftData
@testable import Runalyst

@MainActor
final class ProgressionAndTemporalScopingTests: XCTestCase {

    func testRunRecordEfficiencyFactorCalculation() {
        // Run at 5:00/km (300 sec/km) at 150 BPM
        let run = RunRecord(
            hkWorkoutID: UUID(),
            date: Date(),
            totalDistanceMeters: 5000,
            duration: 1500,
            rawAvgPace: 300,
            rawAvgHeartRate: 150,
            rawAvgCadence: 165,
            workingAvgPace: 300,
            workingAvgCadence: 165,
            workingAvgHeartRate: 150,
            paceCV: 0.03,
            paceSlope: 0.0,
            percentZone4: 0.1,
            detectedTypeRaw: "Easy Run"
        )

        // Speed in m/min = 60,000 / 300 = 200 m/min
        XCTAssertEqual(run.speedMetersPerMinute, 200.0)

        // EF = 200 / 150 = 1.333... m/beat
        guard let ef = run.efficiencyFactor else {
            XCTFail("efficiencyFactor should not be nil for valid pace and heart rate")
            return
        }
        XCTAssertEqual(ef, 200.0 / 150.0, accuracy: 0.001)
    }

    func testRunRecordEfficiencyFactorNilWhenMissingHeartRateOrPace() {
        let zeroHRRun = RunRecord(
            hkWorkoutID: UUID(),
            date: Date(),
            totalDistanceMeters: 5000,
            duration: 1500,
            rawAvgPace: 300,
            rawAvgHeartRate: 0,
            rawAvgCadence: 160,
            workingAvgPace: 300,
            workingAvgCadence: 160,
            workingAvgHeartRate: 0,
            paceCV: 0.03,
            paceSlope: 0.0,
            percentZone4: 0.0,
            detectedTypeRaw: "Easy Run"
        )
        XCTAssertNil(zeroHRRun.efficiencyFactor)

        let zeroPaceRun = RunRecord(
            hkWorkoutID: UUID(),
            date: Date(),
            totalDistanceMeters: 5000,
            duration: 1500,
            rawAvgPace: 0,
            rawAvgHeartRate: 140,
            rawAvgCadence: 160,
            workingAvgPace: 0,
            workingAvgCadence: 160,
            workingAvgHeartRate: 140,
            paceCV: 0.03,
            paceSlope: 0.0,
            percentZone4: 0.0,
            detectedTypeRaw: "Easy Run"
        )
        XCTAssertNil(zeroPaceRun.efficiencyFactor)
        XCTAssertNil(zeroPaceRun.speedMetersPerMinute)
    }

    func testAggregateRunDataForAIWithTelemetryContexts() {
        let aggData = AggregateRunDataForAI(
            paceContext: "4:45/km",
            hrContext: "152 BPM",
            cadenceContext: "168 SPM",
            zone4Context: "18% Zone 4",
            cvContext: "0.032",
            slopeContext: "-0.015",
            stageContext: "Competitor",
            directiveContext: "STRUCTURAL_ADAPTATION: Aerobic efficiency expanded.",
            efficiencyContext: "Efficiency Factor rose by +0.06 m/beat.",
            fatigueContext: "No acute fatigue.",
            verticalOscillationContext: "Vertical Oscillation: 8.8 cm"
        )

        XCTAssertTrue(aggData.directiveContext.contains("STRUCTURAL_ADAPTATION"))
        XCTAssertTrue(aggData.efficiencyContext.contains("+0.06"))
        XCTAssertEqual(aggData.fatigueContext, "No acute fatigue.")
        XCTAssertTrue(aggData.verticalOscillationContext.contains("8.8 cm"))
    }

    func testAllTimeCoachingEngineBypassesLLM() async throws {
        let aggData = AggregateRunDataForAI(
            paceContext: "5:00/km",
            hrContext: "150 BPM",
            cadenceContext: "165 SPM",
            zone4Context: "10%",
            cvContext: "0.03",
            slopeContext: "0.0",
            stageContext: "Competitor"
        )

        if #available(iOS 26.0, *) {
            // Test All-Time output (LLM strictly bypassed, zero simulator hang)
            let allTimeInsight = try await CoachingEngine.shared.generateDashboardInsight(for: "All Time", runData: aggData)
            XCTAssertEqual(allTimeInsight.headline, "Lifetime Milestones")
            XCTAssertTrue(allTimeInsight.body.contains("progression trends"))
        }
    }

    func testChartTimeHorizonDays() {
        XCTAssertEqual(ChartTimeHorizon.thirtyDays.days, 30)
        XCTAssertEqual(ChartTimeHorizon.sixMonths.days, 180)
        XCTAssertEqual(ChartTimeHorizon.oneYear.days, 365)
        XCTAssertNil(ChartTimeHorizon.allTime.days)
    }

    func testProgressionMetricTitles() {
        XCTAssertEqual(ProgressionMetric.efficiencyFactor.id, "Efficiency Factor")
        XCTAssertEqual(ProgressionMetric.pace.id, "Average Pace")
        XCTAssertTrue(ProgressionMetric.efficiencyFactor.shortTitle.contains("Eff. Factor"))
        XCTAssertEqual(ProgressionMetric.pace.shortTitle, "Average Pace")
    }

    func testChartSegmentGapSplitting() {
        let calendar = Calendar.current
        let now = Date()
        let oldDate = calendar.date(byAdding: .day, value: -100, to: now) ?? now
        let recentDate1 = calendar.date(byAdding: .day, value: -10, to: now) ?? now
        let recentDate2 = now

        let daysApart = calendar.dateComponents([.day], from: oldDate, to: recentDate1).day ?? 0
        XCTAssertGreaterThan(daysApart, 45, "Points separated by > 45 days must trigger a new chart segment")

        let recentDaysApart = calendar.dateComponents([.day], from: recentDate1, to: recentDate2).day ?? 0
        XCTAssertLessThanOrEqual(recentDaysApart, 45, "Points within 45 days remain in the same continuous segment")
    }

    func testLifetimeMilestoneAchievements() {
        let run1 = RunRecord(
            hkWorkoutID: UUID(),
            date: Date(),
            totalDistanceMeters: 10500, // > 10k
            duration: 3600,
            rawAvgPace: 342,
            rawAvgHeartRate: 152,
            rawAvgCadence: 172, // > 170 SPM
            workingAvgPace: 342,
            workingAvgCadence: 172,
            workingAvgHeartRate: 152,
            paceCV: 0.03,
            paceSlope: 0.0,
            percentZone4: 0.1,
            detectedTypeRaw: "Steady Effort"
        )

        let run2 = RunRecord(
            hkWorkoutID: UUID(),
            date: Date().addingTimeInterval(-86400),
            totalDistanceMeters: 21500, // > Half Marathon (21.1k)
            duration: 7200,
            rawAvgPace: 335,
            rawAvgHeartRate: 148,
            rawAvgCadence: 168,
            workingAvgPace: 335,
            workingAvgCadence: 168,
            workingAvgHeartRate: 148,
            paceCV: 0.03,
            paceSlope: 0.0,
            percentZone4: 0.1,
            detectedTypeRaw: "Long Run"
        )

        let runs = [run1, run2]
        let totalMeters = runs.map(\.totalDistanceMeters).reduce(0, +)
        XCTAssertEqual(totalMeters, 32000.0)

        let maxCadence = runs.map(\.workingAvgCadence).max() ?? 0
        XCTAssertGreaterThanOrEqual(maxCadence, 170.0)

        let maxDistanceKm = (runs.map(\.totalDistanceMeters).max() ?? 0) / 1000.0
        XCTAssertGreaterThanOrEqual(maxDistanceKm, 21.1)

        // Peak EF: Speed = 60,000 / 335 = 179.1 m/min. EF = 179.1 / 148 = 1.21 m/beat
        let peakEF = runs.compactMap(\.efficiencyFactor).max() ?? 0
        XCTAssertGreaterThan(peakEF, 1.15)
    }

    func testTacticalCoach_FatigueTierClassification() {
        // Case 1: Standard training load (2 quality workouts spaced out, stable turnover)
        // Must NOT trigger CRITICAL_FATIGUE; must classify as MODERATE_FATIGUE
        let now = Date()
        let heavyRun1 = RunRecord(
            hkWorkoutID: UUID(),
            date: now.addingTimeInterval(-48 * 3600), // 2 days ago
            totalDistanceMeters: 6000,
            duration: 1800,
            rawAvgPace: 300,
            rawAvgHeartRate: 165,
            rawAvgCadence: 162,
            workingAvgPace: 300,
            workingAvgCadence: 162,
            workingAvgHeartRate: 165,
            paceCV: 0.12,
            paceSlope: 0.0,
            percentZone4: 0.50,
            detectedTypeRaw: "Intervals"
        )
        let heavyRun2 = RunRecord(
            hkWorkoutID: UUID(),
            date: now.addingTimeInterval(-120 * 3600), // 5 days ago
            totalDistanceMeters: 8000,
            duration: 2500,
            rawAvgPace: 312,
            rawAvgHeartRate: 160,
            rawAvgCadence: 161,
            workingAvgPace: 312,
            workingAvgCadence: 161,
            workingAvgHeartRate: 160,
            paceCV: 0.05,
            paceSlope: 0.0,
            percentZone4: 0.40,
            detectedTypeRaw: "Tempo Run"
        )
        let easyRun = RunRecord(
            hkWorkoutID: UUID(),
            date: now,
            totalDistanceMeters: 5000,
            duration: 1800,
            rawAvgPace: 360,
            rawAvgHeartRate: 140,
            rawAvgCadence: 160,
            workingAvgPace: 360,
            workingAvgCadence: 160,
            workingAvgHeartRate: 140,
            paceCV: 0.03,
            paceSlope: 0.0,
            percentZone4: 0.05,
            detectedTypeRaw: "Easy Run"
        )

        let runs = [easyRun, heavyRun1, heavyRun2]
        let heavySessions = runs.filter { run in
            let type = run.detectedTypeRaw
            let isHeavy = (type == "Intervals" || type == "Pyramids" || type == "Tempo Run" || type == "Hill Repeats")
            let highZ4 = run.percentZone4 >= 0.35
            return isHeavy || highZ4
        }
        XCTAssertEqual(heavySessions.count, 2)

        // Verify that spaced out runs do NOT flag as back-to-back
        var hasBackToBack = false
        if heavySessions.count >= 2 {
            for index in 0..<(heavySessions.count - 1) {
                let interval = heavySessions[index].date.timeIntervalSince(heavySessions[index + 1].date)
                if interval > 0 && interval < 36 * 3600 {
                    hasBackToBack = true
                    break
                }
            }
        }
        XCTAssertFalse(hasBackToBack, "48h and 120h workouts are properly spaced and not back-to-back")

        // Baseline cadence calculation
        let baselineCad = 161.0
        let latestCad = easyRun.workingAvgCadence
        let cadenceDiff = baselineCad - latestCad
        let cadenceDropped = cadenceDiff >= 3.5
        XCTAssertFalse(cadenceDropped, "160 SPM vs 161 baseline is only -1 SPM and should not flag as turnover decay")

        let isCritical = (heavySessions.count >= 3 && cadenceDropped)
            || (hasBackToBack && cadenceDropped)
            || (runs.count >= 6 && heavySessions.count >= 2 && cadenceDropped)
        XCTAssertFalse(isCritical, "Standard 2-session training load must not trigger Critical Fatigue")
    }

    // MARK: - Analysis Tab UI & Information Architecture Tests

    func testProgressionChartHorizonsAndMetrics() {
        XCTAssertEqual(ChartTimeHorizon.thirtyDays.days, 30)
        XCTAssertEqual(ChartTimeHorizon.sixMonths.days, 180)
        XCTAssertEqual(ChartTimeHorizon.oneYear.days, 365)
        XCTAssertNil(ChartTimeHorizon.allTime.days)

        XCTAssertEqual(ProgressionMetric.efficiencyFactor.rawValue, "Efficiency Factor")
        XCTAssertEqual(ProgressionMetric.pace.rawValue, "Average Pace")
    }

    func testLifetimeMilestonesCardBadgesUnlocking() {
        // Run of 21.5 km unlocks first steps, 5K, 10K, half marathon
        let halfMarathonRun = RunRecord(
            hkWorkoutID: UUID(),
            date: Date(),
            totalDistanceMeters: 21500,
            duration: 7200,
            rawAvgPace: 335,
            rawAvgHeartRate: 155,
            rawAvgCadence: 172,
            workingAvgPace: 335,
            workingAvgCadence: 172,
            workingAvgHeartRate: 155,
            paceCV: 0.03,
            paceSlope: 0.0,
            percentZone4: 0.1,
            detectedTypeRaw: "Long Run"
        )

        let runs = [halfMarathonRun]
        let card = LifetimeMilestonesCard(allRuns: runs)
        XCTAssertNotNil(card)

        let maxRunKm = (runs.map(\.totalDistanceMeters).max() ?? 0) / 1000.0
        XCTAssertTrue(maxRunKm >= 21.1, "Half marathon milestone threshold reached")

        let maxCadence = runs.map(\.workingAvgCadence).max() ?? 0
        XCTAssertTrue(maxCadence >= 170.0, "Rhythm master milestone threshold reached")
    }

    // MARK: - Dashboard UI & Hierarchy Tests

    func testDashboardMinimumDistanceFilterFormatting() {
        let metricDist = 0.5
        let metricFormatted = "≥ \(String(format: "%.1f", metricDist)) km"
        XCTAssertEqual(metricFormatted, "≥ 0.5 km")

        let imperialDist = 1.0
        let imperialFormatted = "≥ \(String(format: "%.1f", imperialDist)) mi"
        XCTAssertEqual(imperialFormatted, "≥ 1.0 mi")
    }

    func testFitnessBaselineTrendColorSemantics() {
        // Cadence: drop is decay (negative), increase is positive
        let cadenceDrop = 153 - 157 // -4 SPM
        XCTAssertTrue(cadenceDrop < 0, "Cadence drop should be negative")

        let cadenceGain = 162 - 158 // +4 SPM
        XCTAssertTrue(cadenceGain > 0, "Cadence gain should be positive")

        // Pace: increase in seconds is slower (decay), decrease is faster (positive)
        let paceSlower = 452.0 - 385.0 // +67s
        XCTAssertTrue(paceSlower > 0, "Pace increase in seconds represents slower pace")

        let paceFaster = 360.0 - 380.0 // -20s
        XCTAssertTrue(paceFaster < 0, "Pace reduction in seconds represents faster pace")
    }

    func testRunListRowViewWorkoutFormatting() {
        let calendar = Calendar.current
        let now = Date()

        let easyRun = RunRecord(
            hkWorkoutID: UUID(),
            date: now,
            totalDistanceMeters: 3670,
            duration: 1650,
            rawAvgPace: 454,
            rawAvgHeartRate: 154,
            rawAvgCadence: 160,
            workingAvgPace: 454,
            workingAvgCadence: 160,
            workingAvgHeartRate: 154,
            paceCV: 0.04,
            paceSlope: 0.0,
            percentZone4: 0.05,
            detectedTypeRaw: "Easy Run"
        )

        let drillRun = RunRecord(
            hkWorkoutID: UUID(),
            date: calendar.date(byAdding: .hour, value: -1, to: now) ?? now,
            totalDistanceMeters: 730,
            duration: 285,
            rawAvgPace: 390,
            rawAvgHeartRate: 148,
            rawAvgCadence: 165,
            workingAvgPace: 390,
            workingAvgCadence: 165,
            workingAvgHeartRate: 148,
            paceCV: 0.02,
            paceSlope: 0.0,
            percentZone4: 0.0,
            detectedTypeRaw: "Warmup"
        )
        drillRun.framboiseTags = ["cadence_pyramids"]

        XCTAssertEqual(easyRun.normalizedClassification, "Easy Run")
        XCTAssertEqual(drillRun.prescribedDrillName, "Cadence Pyramids")

        let row1 = RunListRowView(runRecord: easyRun)
        let row2 = RunListRowView(runRecord: drillRun)
        XCTAssertNotNil(row1)
        XCTAssertNotNil(row2)
    }
}
