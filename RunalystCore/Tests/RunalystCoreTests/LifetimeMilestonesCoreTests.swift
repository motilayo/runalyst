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
            #expect(fiveKBadge.earnedMetricSubtitle(useMetric: true) == "6.4 km")
            #expect(fiveKBadge.earnedMetricSubtitle(useMetric: false) == "4.0 mi")
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
        #expect(badgeMap[.halfMarathon]?.earnedMetricSubtitle(useMetric: true) == "21.2 km")
        #expect(badgeMap[.halfMarathon]?.earnedMetricSubtitle(useMetric: false) == "13.2 mi")
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
            #expect(proseWithDate == "You earned this award by logging a single run of at least 5 km. Best qualifying run: 6.42 km on 2026-10-09.")

            let proseWithoutDate = fiveKBadge.earnedNarrativeProse(useMetric: true, formattedDate: nil)
            #expect(proseWithoutDate == "You earned this award by logging a single run of at least 5 km. Best qualifying run: 6.42 km.")
        }

        #expect(tenKBadge != nil)
        if let tenKBadge {
            let lockedProse = tenKBadge.earnedNarrativeProse(useMetric: true, formattedDate: nil)
            #expect(lockedProse == "Complete a single run of at least 10 km to unlock this award. Current progress: 64%.")
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
