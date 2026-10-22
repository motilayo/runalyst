import Foundation
import Testing
@testable import RunalystCore

@Suite("OrthogonalToolsCore Crucible Tests")
struct OrthogonalToolsCoreTests {

    @Test("inspectWorkout projects pure mathematical facts from WorkingStats")
    func inspectWorkoutProjection() {
        let stats = WorkingStats(
            workingDistanceMeters: 5200.0,
            workingDurationSeconds: 1560.0,
            workingAvgPaceSecondsPerKm: 300.0,
            workingAvgCadenceSPM: 168.0,
            workingAvgHeartRateBPM: 155.0,
            rawTotalDistanceMeters: 5350.0,
            rawTotalDurationSeconds: 1680.0,
            rawAvgPaceSecondsPerKm: 314.0,
            rawAvgCadenceSPM: 162.0,
            rawAvgHeartRateBPM: 152.0,
            paceCV: 0.045,
            paceSlope: -0.02,
            percentZone4: 0.22,
            deadStopsCount: 2,
            isIndoor: false,
            needsInclineReview: false,
            detectedClassification: "Steady Effort"
        )

        let inspection = OrthogonalToolsCore.inspectWorkout(stats: stats)

        #expect(inspection.workingDistanceMeters == 5200.0)
        #expect(inspection.workingDurationSeconds == 1560.0)
        #expect(inspection.workingAvgPaceSecondsPerKm == 300.0)
        #expect(inspection.rawTotalDistanceMeters == 5350.0)
        #expect(inspection.deadStopsCount == 2)
        #expect(inspection.paceCV == 0.045)
        #expect(inspection.detectedClassification == "Steady Effort")
        #expect(inspection.efficiencyFactor != nil)
    }

    @Test("getReadinessAndWorkload projects pure domain flags and safety directives")
    func readinessAndWorkloadProjection() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let day: TimeInterval = 24 * 3600

        // 4 weeks of training load
        var sessions: [WorkloadSession] = []
        for i in [25, 22, 19, 16, 13, 10] {
            sessions.append(WorkloadSession(
                date: now.addingTimeInterval(-Double(i) * day),
                durationMinutes: 40.0,
                distanceMeters: 6000.0,
                percentZone4: 0.10
            ))
        }

        // Heavy recent 48 hours: 100 minutes of running
        sessions.append(WorkloadSession(
            date: now.addingTimeInterval(-12 * 3600),
            durationMinutes: 60.0,
            distanceMeters: 9000.0,
            percentZone4: 0.30
        ))
        sessions.append(WorkloadSession(
            date: now.addingTimeInterval(-36 * 3600),
            durationMinutes: 40.0,
            distanceMeters: 6000.0,
            percentZone4: 0.20
        ))

        let projection = OrthogonalToolsCore.getReadinessAndWorkload(
            sessions: sessions,
            now: now,
            todayCompletedMinutes: 45.0,
            todayTargetMinutes: 45,
            cadenceFloorSPM: 152,
            streakDays: 3,
            streakLimit: 6,
            userDistress: nil
        )

        #expect(projection.cadenceFloorSPM == 152)
        #expect(projection.last48hMinutes == 100.0)
        #expect(projection.streakDays == 3)
        #expect(projection.limitingFactors.contains("48h_volume_compression"))
        #expect(projection.limitingFactors.contains("daily_volume_satisfied"))
        #expect(projection.secondRunAdvisable == false)
    }

    @Test("getReadinessAndWorkload attaches safety directive on acute distress")
    func readinessAndWorkloadSafetyOverrideOnDistress() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let projection = OrthogonalToolsCore.getReadinessAndWorkload(
            sessions: [],
            now: now,
            todayCompletedMinutes: 0.0,
            todayTargetMinutes: 40,
            userDistress: .acuteFatigue
        )

        #expect(projection.readinessState == "distress")
        #expect(projection.limitingFactors.contains("safety_override_triggered"))
        #expect(projection.secondRunAdvisable == false)
        #expect(projection.safetyOverrideDirective?.priorityOverridesGoal == true)
    }

    @Test("compareWorkouts computes mathematical deltas and efficiency ratios")
    func workoutComparisonMath() {
        let dateA = Date(timeIntervalSince1970: 1_700_000_000)
        let dateB = dateA.addingTimeInterval(-7 * 24 * 3600) // 7 days prior

        let runA = WorkingStats(
            workingDistanceMeters: 6000.0,
            workingDurationSeconds: 1800.0,
            workingAvgPaceSecondsPerKm: 300.0,
            workingAvgCadenceSPM: 168.0,
            workingAvgHeartRateBPM: 150.0,
            rawTotalDistanceMeters: 6000.0,
            rawTotalDurationSeconds: 1800.0,
            rawAvgPaceSecondsPerKm: 300.0,
            rawAvgCadenceSPM: 168.0,
            rawAvgHeartRateBPM: 150.0,
            paceCV: 0.03,
            paceSlope: 0.0,
            percentZone4: 0.15
        )

        let runB = WorkingStats(
            workingDistanceMeters: 5000.0,
            workingDurationSeconds: 1600.0,
            workingAvgPaceSecondsPerKm: 320.0,
            workingAvgCadenceSPM: 162.0,
            workingAvgHeartRateBPM: 155.0,
            rawTotalDistanceMeters: 5000.0,
            rawTotalDurationSeconds: 1600.0,
            rawAvgPaceSecondsPerKm: 320.0,
            rawAvgCadenceSPM: 162.0,
            rawAvgHeartRateBPM: 155.0,
            paceCV: 0.04,
            paceSlope: 0.0,
            percentZone4: 0.10
        )

        let comparison = OrthogonalToolsCore.compareWorkouts(
            current: runA,
            currentDate: dateA,
            prior: runB,
            priorDate: dateB
        )

        #expect(comparison.paceDeltaSecondsPerKm == -20.0) // 20 s/km faster
        #expect(comparison.cadenceDeltaSPM == 6.0) // +6 SPM
        #expect(comparison.heartRateDeltaBPM == -5.0) // 5 BPM lower HR
        #expect(comparison.distanceDeltaMeters == 1000.0) // +1 km
        #expect(comparison.daysBetweenRuns == 7)
        #expect(comparison.efficiencyRatio != nil)
        if let effRatio = comparison.efficiencyRatio {
            #expect(effRatio > 1.0) // Higher running economy
        }
    }

    @Test("projectSchedule maps continuous timeline without fragmentation")
    func scheduleProjectionContinuousTimeline() {
        let day: TimeInterval = 24 * 3600
        let from = Date(timeIntervalSince1970: 1_700_000_000)
        let to = from.addingTimeInterval(3 * day)

        let planned = [
            (date: from, title: "Zone 2 Steady", minMinutes: 30, maxMinutes: 40, isRest: false),
            (date: from.addingTimeInterval(day), title: "Rest & Mobility", minMinutes: 0, maxMinutes: 0, isRest: true),
            (date: from.addingTimeInterval(2 * day), title: "Cadence Pyramids", minMinutes: 25, maxMinutes: 30, isRest: false)
        ]

        let completed = [
            (date: from.addingTimeInterval(3600), durationMinutes: 35.0)
        ]

        let projections = OrthogonalToolsCore.projectSchedule(
            from: from,
            to: to,
            plannedSessions: planned,
            completedSessions: completed
        )

        #expect(projections.count == 4)
        #expect(projections[0].plannedTitle == "Zone 2 Steady")
        #expect(projections[0].completedMinutes == 35.0)
        #expect(projections[0].isCompleted == true)
        #expect(projections[1].isRestDay == true)
        #expect(projections[2].plannedTitle == "Cadence Pyramids")
    }

    @Test("executeCoachAction enforces safety gate override")
    func executeCoachActionEnforcesSafety() {
        let requested = RunDirective.tempoSurges(pacingBand: .zone4LactateThreshold, durationMinutes: 45.0)

        let safeReport = BanisterReadinessReport(
            acuteLoad: 120.0,
            chronicWeeklyLoad: 110.0,
            acwr: 1.09,
            zone: .optimal,
            isSafetyOverridden: false,
            overrideReason: nil,
            effectiveDirective: requested
        )

        let clearOutcome = OrthogonalToolsCore.executeCoachAction(
            action: "export_to_watch",
            requestedDirective: requested,
            safetyReport: safeReport
        )

        #expect(clearOutcome.statusCode == "action_executed")
        #expect(clearOutcome.effectiveDirective == requested)
        #expect(clearOutcome.isSafetyOverridden == false)

        let safetyOverrideDirective = RunDirective.easyAerobicRecovery(pacingBand: .zone1Recovery, maxDurationMinutes: 30.0)
        let overriddenReport = BanisterReadinessReport(
            acuteLoad: 240.0,
            chronicWeeklyLoad: 110.0,
            acwr: 2.18,
            zone: .spike,
            isSafetyOverridden: true,
            overrideReason: "ACWR overload spike",
            effectiveDirective: safetyOverrideDirective
        )

        let overriddenOutcome = OrthogonalToolsCore.executeCoachAction(
            action: "export_to_watch",
            requestedDirective: requested,
            safetyReport: overriddenReport
        )

        #expect(overriddenOutcome.statusCode == "overridden_by_safety")
        #expect(overriddenOutcome.effectiveDirective == safetyOverrideDirective)
        #expect(overriddenOutcome.isSafetyOverridden == true)
    }
}
