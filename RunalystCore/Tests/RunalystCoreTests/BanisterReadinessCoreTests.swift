import Foundation
import Testing
@testable import RunalystCore

@Suite("BanisterReadinessCore Crucible Tests")
struct BanisterReadinessCoreTests {

    @Test("ACWR calculation correctly evaluates zones from historical session load")
    func acwrCalculationAndZones() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let day: TimeInterval = 24 * 3600

        var sessions: [WorkloadSession] = []

        // Weeks 1-3 (days -28 to -8): Steady chronic base (3 runs/week of 40 mins, 10% Zone 4)
        for i in [26, 24, 21, 19, 17, 14, 12, 10, 8] {
            sessions.append(WorkloadSession(
                date: now.addingTimeInterval(-Double(i) * day),
                durationMinutes: 40.0,
                distanceMeters: 7000.0,
                percentZone4: 0.10,
                isHardSession: false
            ))
        }

        // Acute week (days -6 to -1): 3 runs of 40 mins
        for i in [6, 4, 2] {
            sessions.append(WorkloadSession(
                date: now.addingTimeInterval(-Double(i) * day),
                durationMinutes: 40.0,
                distanceMeters: 7000.0,
                percentZone4: 0.10,
                isHardSession: false
            ))
        }

        let (_, _, acwr, zone) = BanisterReadinessCore.calculateACWR(sessions: sessions, now: now)

        #expect(acwr != nil)
        if let ratio = acwr {
            #expect(ratio >= 0.8 && ratio <= 1.3)
        }
        #expect(zone == .optimal)
    }

    @Test("Safety Gate triggers deterministically at ACWR overload threshold of 1.4")
    func safetyGateTriggersAtACWRThreshold() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let day: TimeInterval = 24 * 3600

        var sessions: [WorkloadSession] = []

        // Baseline: 4 weeks of light running (1 run/week of 30 min)
        for i in [25, 18, 11] {
            sessions.append(WorkloadSession(
                date: now.addingTimeInterval(-Double(i) * day),
                durationMinutes: 30.0,
                distanceMeters: 5000.0,
                percentZone4: 0.05,
                isHardSession: false
            ))
        }

        // Huge acute spike: 6 hard sessions in the past 7 days (45 min each, 50% Zone 4)
        for i in 1...6 {
            sessions.append(WorkloadSession(
                date: now.addingTimeInterval(-Double(i) * day),
                durationMinutes: 45.0,
                distanceMeters: 8000.0,
                percentZone4: 0.50,
                isHardSession: true
            ))
        }

        let userDirective = RunDirective.tempoSurges(pacingBand: .zone4LactateThreshold, durationMinutes: 45.0)

        let report = BanisterReadinessCore.evaluateSafetyGate(
            sessions: sessions,
            now: now,
            userStatedDirective: userDirective
        )

        #expect(report.zone == .spike)
        #expect(report.isSafetyOverridden == true)
        #expect(report.overrideReason?.contains("ACWR workload spike") == true)

        // Stated tempo surges race goal must be stripped and replaced with EasyAerobicRecovery
        switch report.effectiveDirective {
        case .easyAerobicRecovery(let band, let maxDur):
            #expect(band == .zone1Recovery)
            #expect(maxDur <= 35.0)
        default:
            Issue.record("Expected easyAerobicRecovery directive on ACWR overload spike")
        }
    }

    @Test("Safety Gate activates immediately on active SubjectiveDistressSignal")
    func safetyGateActivatesOnSubjectiveDistress() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let userDirective = RunDirective.cadencePyramids(targetFloorSPM: 165, targetCeilingSPM: 175, durationMinutes: 30.0)

        // Joint pain forces safety override
        let reportJointPain = BanisterReadinessCore.evaluateSafetyGate(
            sessions: [],
            now: now,
            subjectiveDistress: .jointPain,
            userStatedDirective: userDirective
        )
        #expect(reportJointPain.isSafetyOverridden == true)
        #expect(reportJointPain.overrideReason?.contains("jointPain") == true)
        #expect(reportJointPain.effectiveDirective.priorityOverridesGoal == true)

        // Acute fatigue forces safety override
        let reportFatigue = BanisterReadinessCore.evaluateSafetyGate(
            sessions: [],
            now: now,
            subjectiveDistress: .acuteFatigue,
            userStatedDirective: userDirective
        )
        #expect(reportFatigue.isSafetyOverridden == true)

        // Muscle soreness (mild DOMS) does NOT force safety override
        let reportSoreness = BanisterReadinessCore.evaluateSafetyGate(
            sessions: [],
            now: now,
            subjectiveDistress: .muscleSoreness,
            userStatedDirective: userDirective
        )
        #expect(reportSoreness.isSafetyOverridden == false)
        #expect(reportSoreness.effectiveDirective == userDirective)
    }

    @Test("Safety Gate activates on physiological cardiac strain decoupling")
    func safetyGateActivatesOnCardiacDecoupling() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let userDirective = RunDirective.strides(repetitions: 6, targetSPM: 175)

        // Runner was 15 s/km slower with 8 BPM higher heart rate
        let report = BanisterReadinessCore.evaluateSafetyGate(
            sessions: [],
            now: now,
            paceDeltaVsBaseline: -15.0,
            hrDeltaVsBaseline: 8.0,
            userStatedDirective: userDirective
        )

        #expect(report.isSafetyOverridden == true)
        #expect(report.overrideReason?.contains("cardiac strain decoupling") == true)

        switch report.effectiveDirective {
        case .easyAerobicRecovery(let band, _):
            #expect(band == .zone1Recovery)
        default:
            Issue.record("Expected easyAerobicRecovery on cardiac decoupling")
        }
    }

    @Test("Safety Gate activates on consecutive hard days within 72 hours")
    func safetyGateActivatesOnConsecutiveHardDays() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let day: TimeInterval = 24 * 3600

        // Two hard sessions on consecutive calendar days within the last 48 hours
        let sessions = [
            WorkloadSession(
                date: now.addingTimeInterval(-20 * 3600),
                durationMinutes: 45.0,
                distanceMeters: 8000.0,
                percentZone4: 0.40,
                isHardSession: true
            ),
            WorkloadSession(
                date: now.addingTimeInterval(-44 * 3600),
                durationMinutes: 50.0,
                distanceMeters: 9000.0,
                percentZone4: 0.45,
                isHardSession: true
            )
        ]

        let userDirective = RunDirective.rhythmIntervals(targetSPM: 168, durationMinutes: 30.0)

        let report = BanisterReadinessCore.evaluateSafetyGate(
            sessions: sessions,
            now: now,
            userStatedDirective: userDirective
        )

        #expect(report.isSafetyOverridden == true)
        #expect(report.overrideReason?.contains("Consecutive hard training sessions") == true)
        #expect(report.effectiveDirective.priorityOverridesGoal == true)
    }

    @Test("isTrueDeloadVolumeDrop returns false when 7-day drop is below threshold")
    func isTrueDeloadVolumeDropBelowThreshold() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let day: TimeInterval = 24 * 3600
        let trailingWeeklyMeters = 20_000.0

        // Strict 7-day volume: 18,000 m (only 10% drop, well below 25% threshold)
        let sessions = [
            WorkloadSession(
                date: now.addingTimeInterval(-2 * day),
                durationMinutes: 50.0,
                distanceMeters: 10_000.0,
                percentZone4: 0.10
            ),
            WorkloadSession(
                date: now.addingTimeInterval(-4 * day),
                durationMinutes: 45.0,
                distanceMeters: 8_000.0,
                percentZone4: 0.10
            )
        ]

        let isDeload = BanisterReadinessCore.isTrueDeloadVolumeDrop(
            sessions: sessions,
            trailingWeeklyMeters: trailingWeeklyMeters,
            now: now
        )

        #expect(isDeload == false)
    }

    @Test("isTrueDeloadVolumeDrop suppresses deload after 4-day rest gap following healthy prior week")
    func isTrueDeloadVolumeDropSuppressesRestGap() {
        // Monday morning anchor
        var calendar = Calendar(identifier: .gregorian)
        if let gmt = TimeZone(secondsFromGMT: 0) {
            calendar.timeZone = gmt
        }
        // 2023-10-23 08:00:00 GMT is a Monday
        var comps = DateComponents()
        comps.year = 2023
        comps.month = 10
        comps.day = 23
        comps.hour = 8
        comps.minute = 0
        comps.second = 0
        let now = calendar.date(from: comps) ?? Date(timeIntervalSince1970: 1_698_048_000)
        let day: TimeInterval = 24 * 3600

        // Trailing 3-week average: 20.43 km/wk (20,430 m)
        let trailingWeeklyMeters = 20_430.0

        // Prior completed calendar week (Oct 16-22) had 19.7 km (19,700 m):
        // Run 1: Mon Oct 16 07:00 (-7 days - 1 hour, strictly > 7 days ago so rolls out of strict acute slice)
        // Run 2: Wed Oct 18 07:00 (-5 days)
        // Run 3: Thu Oct 19 07:00 (-4 days - 1 hour)
        // Rest/walk gap: Fri Oct 20, Sat Oct 21, Sun Oct 22, Mon Oct 23 morning -> 4 days off
        let sessions = [
            WorkloadSession(
                date: now.addingTimeInterval(-7 * day - 3600),
                durationMinutes: 45.0,
                distanceMeters: 7_700.0,
                percentZone4: 0.05
            ),
            WorkloadSession(
                date: now.addingTimeInterval(-5 * day),
                durationMinutes: 40.0,
                distanceMeters: 6_000.0,
                percentZone4: 0.05
            ),
            WorkloadSession(
                date: now.addingTimeInterval(-4 * day - 3600),
                durationMinutes: 40.0,
                distanceMeters: 6_000.0,
                percentZone4: 0.05
            )
        ]

        // Strict 7-day acute volume has only the runs at -5d and -4d (12,000 m).
        // Drop vs 20,430 m = 1.0 - (12,000 / 20,430) = 41.2% (>= 25%).
        // But prior week volume = 19,700 m (96.4% of trailing average >= 80%), and daysSinceLastRun >= 2.
        let isDeload = BanisterReadinessCore.isTrueDeloadVolumeDrop(
            sessions: sessions,
            trailingWeeklyMeters: trailingWeeklyMeters,
            now: now,
            calendar: calendar
        )

        // Must return false to suppress false-positive deload and preserve .productive
        #expect(isDeload == false)
    }

    @Test("isTrueDeloadVolumeDrop returns true when acute drop is genuine deload without rest-gap suppression")
    func isTrueDeloadVolumeDropTrueWhenGenuineDeload() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let day: TimeInterval = 24 * 3600
        let trailingWeeklyMeters = 20_000.0

        // Runner ran yesterday (no rest gap, daysSinceLastRun = 1), but total 7-day volume is only 10,000 m (50% drop)
        let sessions = [
            WorkloadSession(
                date: now.addingTimeInterval(-1 * day),
                durationMinutes: 30.0,
                distanceMeters: 5_000.0,
                percentZone4: 0.05
            ),
            WorkloadSession(
                date: now.addingTimeInterval(-3 * day),
                durationMinutes: 30.0,
                distanceMeters: 5_000.0,
                percentZone4: 0.05
            )
        ]

        let isDeload = BanisterReadinessCore.isTrueDeloadVolumeDrop(
            sessions: sessions,
            trailingWeeklyMeters: trailingWeeklyMeters,
            now: now
        )

        // Genuine deload
        #expect(isDeload == true)
    }

    @Test("Scenario (e): 23.0 -> 21.6 -> 16.7 -> 19.7 km with 4-day rest/walk gap returns false for isTrueDeloadVolumeDrop, preserving productive readiness")
    func testRestGapResilientDeloadScenario() {
        var calendar = Calendar(identifier: .gregorian)
        if let gmt = TimeZone(secondsFromGMT: 0) {
            calendar.timeZone = gmt
        }
        // Monday morning anchor
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 11
        comps.day = 16
        comps.hour = 8
        comps.minute = 0
        comps.second = 0
        let mondayMorning = calendar.date(from: comps) ?? Date(timeIntervalSince1970: 1_794_816_000)
        let day: TimeInterval = 24 * 3600

        // Trailing 3-week progression: 23.0 km -> 21.6 km -> 16.7 km
        // Chronic baseline average: (23.0 + 21.6 + 16.7) / 3 = 20.433 km = 20,433.33 m
        let week1Meters = 23_000.0
        let week2Meters = 21_600.0
        let week3Meters = 16_700.0
        let trailingWeeklyMeters = (week1Meters + week2Meters + week3Meters) / 3.0

        // Week 4 (completed prior calendar week): 19.7 km (19,700 m) completed early in the week
        // Followed by 4-day rest/walk gap (Fri, Sat, Sun, Mon morning)
        let priorMondayRun = WorkloadSession(
            date: mondayMorning.addingTimeInterval(-7 * day - 3600), // > 7 days ago
            durationMinutes: 45.0,
            distanceMeters: 7_700.0,
            percentZone4: 0.05
        )
        let priorWednesdayRun = WorkloadSession(
            date: mondayMorning.addingTimeInterval(-5 * day),
            durationMinutes: 38.0,
            distanceMeters: 6_000.0,
            percentZone4: 0.05
        )
        let priorThursdayRun = WorkloadSession(
            date: mondayMorning.addingTimeInterval(-4 * day - 3600),
            durationMinutes: 37.0,
            distanceMeters: 6_000.0,
            percentZone4: 0.05
        )
        let sessions = [priorMondayRun, priorWednesdayRun, priorThursdayRun]

        // Strict 7-day acute slice has only Wednesday + Thursday runs = 12,000 m
        // Acute drop vs 20,433 m is ~41.3% (>= 25% threshold)
        // However, prior week volume = 19,700 m (96.4% of chronic baseline >= 80%), and daysSinceLastRun = 4 >= 2
        let isDeload = BanisterReadinessCore.isTrueDeloadVolumeDrop(
            sessions: sessions,
            trailingWeeklyMeters: trailingWeeklyMeters,
            now: mondayMorning,
            calendar: calendar
        )

        // Must return false, preserving productive readiness rather than triggering false deload
        #expect(isDeload == false)
    }
}
