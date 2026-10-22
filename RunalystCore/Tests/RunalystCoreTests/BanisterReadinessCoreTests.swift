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
}
