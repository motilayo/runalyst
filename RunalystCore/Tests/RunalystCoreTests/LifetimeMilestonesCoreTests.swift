import Foundation
@testable import RunalystCore
import Testing

@Suite("Lifetime Milestones Core Tests")
struct LifetimeMilestonesCoreTests {

    // MARK: - Spec Scenarios

    @Test("Evaluating 5K Milestone with multiple qualifying runs matches best run and count")
    func testEvaluatingFiveKMultipleQualifyingRuns() {
        let run1ID = UUID()
        let run2ID = UUID()
        let run3ID = UUID()
        let refDate = Date(timeIntervalSince1970: 1_700_000_000)

        let sample1 = MilestoneRunSample(
            id: run1ID,
            date: refDate.addingTimeInterval(-86400 * 3),
            totalDistanceMeters: 5200.0,
            durationSeconds: 1600.0,
            workingAvgPace: 307.0,
            workingAvgCadence: 165.0
        )
        let sample2 = MilestoneRunSample(
            id: run2ID,
            date: refDate.addingTimeInterval(-86400 * 2),
            totalDistanceMeters: 6400.0,
            durationSeconds: 1950.0,
            workingAvgPace: 304.0,
            workingAvgCadence: 166.0
        )
        let sample3 = MilestoneRunSample(
            id: run3ID,
            date: refDate.addingTimeInterval(-86400 * 1),
            totalDistanceMeters: 3100.0,
            durationSeconds: 950.0,
            workingAvgPace: 306.0,
            workingAvgCadence: 164.0
        )

        let summary = LifetimeMilestonesCore.evaluate(samples: [sample1, sample2, sample3])
        let fiveKBadge = summary.badges.first { $0.identifier == .fiveK }

        #expect(fiveKBadge != nil)
        if let fiveKBadge {
            #expect(fiveKBadge.isUnlocked == true)
            #expect(fiveKBadge.timesEarnedCount == 2)
            #expect(fiveKBadge.qualifyingRunID == run2ID)
            #expect(fiveKBadge.progressFraction == 1.0)
            #expect(fiveKBadge.medallionShape == .splitHorizonDistance)
            #expect(fiveKBadge.earnedMetricSubtitle(useMetric: true) == "6.40 km")
            #expect(fiveKBadge.earnedMetricSubtitle(useMetric: false) == "3.98 mi")
        }
    }

    @Test("Evaluating 5K Milestone selects fastest 5K-tier run over longer or out-of-bracket runs")
    func testEvaluatingFiveKSelectsFastestTierRun() {
        let runFastFiveKID = UUID()
        let runSlowLongerFiveKID = UUID()
        let runTenKID = UUID()
        let refDate = Date(timeIntervalSince1970: 1_700_000_000)

        // 6.40 km at pace 300 s/km (5:00/km) - fastest within 5K bracket [5000m, 10000m)
        let fastFiveK = MilestoneRunSample(
            id: runFastFiveKID,
            date: refDate.addingTimeInterval(-86400 * 3),
            totalDistanceMeters: 6400.0,
            durationSeconds: 1920.0,
            workingAvgPace: 300.0,
            workingAvgCadence: 168.0
        )
        // 9.64 km at pace 340 s/km (5:40/km) - longer within 5K bracket, but slower
        let slowLongerFiveK = MilestoneRunSample(
            id: runSlowLongerFiveKID,
            date: refDate.addingTimeInterval(-86400 * 2),
            totalDistanceMeters: 9640.0,
            durationSeconds: 3277.6,
            workingAvgPace: 340.0,
            workingAvgCadence: 160.0
        )
        // 12.00 km at pace 290 s/km (4:50/km) - faster pace, but belongs to 10K+ bracket (>= 10,000m)
        let tenKRun = MilestoneRunSample(
            id: runTenKID,
            date: refDate.addingTimeInterval(-86400 * 1),
            totalDistanceMeters: 12_000.0,
            durationSeconds: 3480.0,
            workingAvgPace: 290.0,
            workingAvgCadence: 172.0
        )

        let summary = LifetimeMilestonesCore.evaluate(samples: [fastFiveK, slowLongerFiveK, tenKRun])
        let fiveKBadge = summary.badges.first { $0.identifier == .fiveK }
        let tenKBadge = summary.badges.first { $0.identifier == .tenK }

        #expect(fiveKBadge != nil)
        if let fiveKBadge {
            #expect(fiveKBadge.isUnlocked == true)
            #expect(fiveKBadge.timesEarnedCount == 3)
            #expect(fiveKBadge.qualifyingRunID == runFastFiveKID)
            #expect(fiveKBadge.qualifyingDistanceMeters == 6400.0)
            #expect(fiveKBadge.earnedMetricSubtitle(useMetric: true) == "6.40 km")
        }

        #expect(tenKBadge != nil)
        if let tenKBadge {
            #expect(tenKBadge.isUnlocked == true)
            #expect(tenKBadge.timesEarnedCount == 1)
            #expect(tenKBadge.qualifyingRunID == runTenKID)
            #expect(tenKBadge.qualifyingDistanceMeters == 12_000.0)
            #expect(tenKBadge.earnedMetricSubtitle(useMetric: true) == "12.00 km")
        }
    }

    @Test("Evaluating locked 100K Century Volume badge progress and metric subtitle")
    func testEvaluatingLockedCenturyVolumeProgress() {
        let refDate = Date(timeIntervalSince1970: 1_700_000_000)
        let sample = MilestoneRunSample(
            id: UUID(),
            date: refDate,
            totalDistanceMeters: 64_500.0,
            durationSeconds: 20_000.0,
            workingAvgPace: 310.0,
            workingAvgCadence: 162.0
        )

        let summary = LifetimeMilestonesCore.evaluate(samples: [sample])
        let centuryBadge = summary.badges.first { $0.identifier == .centuryVolume }

        #expect(centuryBadge != nil)
        if let centuryBadge {
            #expect(centuryBadge.isUnlocked == false)
            #expect(abs(centuryBadge.progressFraction - 0.645) < 0.001)
            #expect(centuryBadge.earnedMetricSubtitle(useMetric: true) == "64.5 / 100 km")
            #expect(centuryBadge.medallionShape == .splitHorizonDistance)
        }
    }

    // MARK: - Medallion Geometry & Repeat Count Tests

    @Test("Verifies all 9 milestone badges have correct medallion geometric shapes")
    func testMilestoneMedallionShapes() {
        let summary = LifetimeMilestonesCore.evaluate(samples: [])
        let badgeMap = Dictionary(uniqueKeysWithValues: summary.badges.map { ($0.identifier, $0.medallionShape) })

        #expect(badgeMap[.firstRun] == .circleRecord)
        #expect(badgeMap[.rhythmMaster] == .circleRecord)
        #expect(badgeMap[.aerobicEngine] == .circleRecord)

        #expect(badgeMap[.fiveK] == .splitHorizonDistance)
        #expect(badgeMap[.tenK] == .splitHorizonDistance)
        #expect(badgeMap[.halfMarathon] == .splitHorizonDistance)
        #expect(badgeMap[.centuryVolume] == .splitHorizonDistance)
        #expect(badgeMap[.fiveHundredK] == .splitHorizonDistance)

        #expect(badgeMap[.consistency] == .hexagonStreak)
    }

    @Test("Calculates repeat counts accurately for unlocked badges")
    func testRepeatCountsForBadges() {
        let refDate = Date(timeIntervalSince1970: 1_700_000_000)
        var samples: [MilestoneRunSample] = []

        // Generate 22 runs of 10.5 km at 172 SPM and 1.40 EF
        for index in 0..<22 {
            samples.append(
                MilestoneRunSample(
                    id: UUID(),
                    date: refDate.addingTimeInterval(Double(-index * 86400)),
                    totalDistanceMeters: 10_500.0,
                    durationSeconds: 3150.0,
                    workingAvgPace: 300.0,
                    workingAvgCadence: 172.0,
                    efficiencyFactor: 1.40
                )
            )
        }

        let summary = LifetimeMilestonesCore.evaluate(samples: samples)
        let badgeMap = Dictionary(uniqueKeysWithValues: summary.badges.map { ($0.identifier, $0) })

        // 22 runs >= 5000m -> timesEarnedCount == 22
        #expect(badgeMap[.fiveK]?.timesEarnedCount == 22)
        // 22 runs >= 10,000m -> timesEarnedCount == 22
        #expect(badgeMap[.tenK]?.timesEarnedCount == 22)
        // 22 runs * 10.5 km = 231 km -> centuryVolume earned 2 times (200km)
        #expect(badgeMap[.centuryVolume]?.timesEarnedCount == 2)
        // 22 runs with cadence >= 170 -> 22
        #expect(badgeMap[.rhythmMaster]?.timesEarnedCount == 22)
        // 22 runs with EF >= 1.35 -> 22
        #expect(badgeMap[.aerobicEngine]?.timesEarnedCount == 22)
        // 22 runs / 10 -> 2
        #expect(badgeMap[.consistency]?.timesEarnedCount == 2)
    }

    // MARK: - Subtitle & Prose Formatting Tests

    @Test("Formats earned metric subtitles across metric and imperial systems")
    func testEarnedMetricSubtitles() {
        let refDate = Date(timeIntervalSince1970: 1_700_000_000)
        let sample = MilestoneRunSample(
            id: UUID(),
            date: refDate,
            totalDistanceMeters: 21_200.0,
            durationSeconds: 6360.0,
            workingAvgPace: 300.0,
            workingAvgCadence: 174.0,
            efficiencyFactor: 1.42
        )

        let summary = LifetimeMilestonesCore.evaluate(samples: [sample])
        let badgeMap = Dictionary(uniqueKeysWithValues: summary.badges.map { ($0.identifier, $0) })

        // Rhythm Master (174 SPM)
        #expect(badgeMap[.rhythmMaster]?.earnedMetricSubtitle(useMetric: true) == "174 SPM")
        // Aerobic Engine (1.42 EF)
        #expect(badgeMap[.aerobicEngine]?.earnedMetricSubtitle(useMetric: true) == "1.42 EF")
        // Half Marathon unlocked
        #expect(badgeMap[.halfMarathon]?.earnedMetricSubtitle(useMetric: true) == "21.20 km")
        #expect(badgeMap[.halfMarathon]?.earnedMetricSubtitle(useMetric: false) == "13.17 mi")
        // Consistency locked (1 / 10 runs)
        #expect(badgeMap[.consistency]?.earnedMetricSubtitle(useMetric: true) == "1 / 10 Runs")
    }

    @Test("Formats narrative prose for unlocked and locked states with Apple Fitness clarity")
    func testEarnedNarrativeProse() {
        let refDate = Date(timeIntervalSince1970: 1_700_000_000)
        let sample = MilestoneRunSample(
            id: UUID(),
            date: refDate,
            totalDistanceMeters: 6420.0,
            durationSeconds: 1950.0,
            workingAvgPace: 304.0,
            workingAvgCadence: 165.0
        )

        let summary = LifetimeMilestonesCore.evaluate(samples: [sample])
        let fiveKBadge = summary.badges.first { $0.identifier == .fiveK }
        let tenKBadge = summary.badges.first { $0.identifier == .tenK }

        #expect(fiveKBadge != nil)
        if let fiveKBadge {
            let proseWithDate = fiveKBadge.earnedNarrativeProse(useMetric: true, formattedDate: "2026-10-09")
            #expect(proseWithDate == "You earned this award by completing a 5K workout. Fastest 5K-tier run: 6.42 km on 2026-10-09.")

            let proseWithoutDate = fiveKBadge.earnedNarrativeProse(useMetric: true, formattedDate: nil)
            #expect(proseWithoutDate == "You earned this award by completing a 5K workout. Fastest 5K-tier run: 6.42 km.")
        }

        #expect(tenKBadge != nil)
        if let tenKBadge {
            let lockedProse = tenKBadge.earnedNarrativeProse(useMetric: true, formattedDate: nil)
            #expect(lockedProse == "Complete a single run of at least 10 km to unlock this award. Current progress: 64%.")
        }
    }

    @Test("Clinching workout selection and workout card metric formatting for cumulative milestones")
    func testClinchingRunSelectionAndWorkoutCardMetricText() {
        let refDate = Date(timeIntervalSince1970: 1_700_000_000)
        var samples: [MilestoneRunSample] = []

        let distances: [Double] = [
            10_000.0, // Run 0 (10 km)
            15_000.0, // Run 1 (25 km total)
            20_000.0, // Run 2 (45 km total)
            25_000.0, // Run 3 (70 km total)
            35_000.0, // Run 4 (105 km total -> clinches 100K Century)
            5_000.0,  // Run 5 (110 km total)
            5_000.0,  // Run 6 (115 km total)
            5_000.0,  // Run 7 (120 km total)
            5_000.0,  // Run 8 (125 km total)
            5_420.0,  // Run 9 (130.42 km total -> 10th run, clinches Consistency)
            6_000.0,  // Run 10 (136.42 km total)
            7_000.0   // Run 11 (143.42 km total -> most recent run)
        ]

        var runIDs: [UUID] = []
        for (index, dist) in distances.enumerated() {
            let id = UUID()
            runIDs.append(id)
            samples.append(
                MilestoneRunSample(
                    id: id,
                    date: refDate.addingTimeInterval(Double(index * 86400)),
                    totalDistanceMeters: dist,
                    durationSeconds: dist * 0.3,
                    workingAvgPace: 300.0,
                    workingAvgCadence: 168.0
                )
            )
        }

        let shuffled = samples.shuffled()
        let summary = LifetimeMilestonesCore.evaluate(samples: shuffled)
        let badgeMap = Dictionary(uniqueKeysWithValues: summary.badges.map { ($0.identifier, $0) })

        let centuryBadge = badgeMap[.centuryVolume]
        #expect(centuryBadge != nil)
        if let centuryBadge {
            #expect(centuryBadge.isUnlocked == true)
            #expect(centuryBadge.timesEarnedCount == 1)
            #expect(centuryBadge.qualifyingRunID == runIDs[4])
            #expect(centuryBadge.qualifyingDistanceMeters == 143_420.0)
            #expect(centuryBadge.earnedMetricSubtitle(useMetric: true) == "143.4 km")
            #expect(centuryBadge.workoutCardMetricText(useMetric: true, workoutDistanceMeters: distances[4]) == "35.00 km")
            #expect(centuryBadge.workoutCardMetricText(useMetric: false, workoutDistanceMeters: distances[4]) == "21.75 mi")
            #expect(centuryBadge.earnedNarrativeProse(useMetric: true, formattedDate: nil) ==
                "You earned this award by crossing 100 km of lifetime running volume (143.4 km lifetime total).")
        }

        let consistencyBadge = badgeMap[.consistency]
        #expect(consistencyBadge != nil)
        if let consistencyBadge {
            #expect(consistencyBadge.isUnlocked == true)
            #expect(consistencyBadge.timesEarnedCount == 1)
            #expect(consistencyBadge.qualifyingRunID == runIDs[9])
            #expect(consistencyBadge.qualifyingDistanceMeters == 5420.0)
            #expect(consistencyBadge.earnedMetricSubtitle(useMetric: true) == "10+ Runs")
            #expect(consistencyBadge.workoutCardMetricText(useMetric: true, workoutDistanceMeters: distances[9]) == "5.42 km")
            #expect(consistencyBadge.workoutCardMetricText(useMetric: true, workoutDistanceMeters: nil) == "5.42 km")
            #expect(consistencyBadge.workoutCardMetricText(useMetric: false, workoutDistanceMeters: distances[9]) == "3.37 mi")
            #expect(consistencyBadge.earnedNarrativeProse(useMetric: true, formattedDate: nil) ==
                "You earned this award by completing your 10th structured running workout.")
        }
    }

    @Test("Multi-earned cumulative milestones narrative copy and clinching runs")
    func testMultiEarnedCumulativeMilestones() {
        let refDate = Date(timeIntervalSince1970: 1_700_000_000)
        var samples: [MilestoneRunSample] = []
        var runIDs: [UUID] = []

        for index in 0..<25 {
            let id = UUID()
            runIDs.append(id)
            samples.append(
                MilestoneRunSample(
                    id: id,
                    date: refDate.addingTimeInterval(Double(index * 86400)),
                    totalDistanceMeters: 25_000.0,
                    durationSeconds: 7500.0,
                    workingAvgPace: 300.0,
                    workingAvgCadence: 170.0
                )
            )
        }

        let summary = LifetimeMilestonesCore.evaluate(samples: samples)
        let badgeMap = Dictionary(uniqueKeysWithValues: summary.badges.map { ($0.identifier, $0) })

        if let century = badgeMap[.centuryVolume] {
            #expect(century.timesEarnedCount == 6)
            #expect(century.qualifyingRunID == runIDs[23])
            #expect(century.earnedNarrativeProse(useMetric: true, formattedDate: nil) ==
                "You earn this award for every 100 km of lifetime running volume. You crossed 600 km (625.0 km lifetime total).")
        }

        if let consistency = badgeMap[.consistency] {
            #expect(consistency.timesEarnedCount == 2)
            #expect(consistency.qualifyingRunID == runIDs[19])
            #expect(consistency.earnedNarrativeProse(useMetric: true, formattedDate: nil) ==
                "You earn this award for every 10 structured running workouts you complete. You logged your 20th workout.")
        }

        if let titan = badgeMap[.fiveHundredK] {
            #expect(titan.timesEarnedCount == 1)
            #expect(titan.qualifyingRunID == runIDs[19])
            #expect(titan.earnedNarrativeProse(useMetric: true, formattedDate: nil) ==
                "You earned this award by crossing 500 km of lifetime running volume (625.0 km lifetime total).")
        }
    }

    @Test("Empty samples collection safely initializes all badges locked with zero progress")
    func testEmptySamplesCollection() {
        let summary = LifetimeMilestonesCore.evaluate(samples: [])

        #expect(summary.totalDistanceMeters == 0.0)
        #expect(summary.totalDurationSeconds == 0.0)
        #expect(summary.totalRunsCount == 0)
        #expect(summary.unlockedBadgesCount == 0)

        for badge in summary.badges {
            #expect(badge.isUnlocked == false)
            #expect(badge.timesEarnedCount == 0)
            #expect(badge.progressFraction == 0.0)
            #expect(badge.qualifyingRunID == nil)
        }
    }
}
