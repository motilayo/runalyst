import XCTest
import SwiftData
@testable import Runalyst
@testable import RunalystCore

final class CrossSurfaceIdempotencyTests: XCTestCase {

    private func makeRun(
        date: Date,
        duration: Double,
        distanceMeters: Double,
        detectedTypeRaw: String,
        framboiseTags: [String] = []
    ) -> RunRecord {
        let run = RunRecord(
            hkWorkoutID: UUID(),
            date: date,
            totalDistanceMeters: distanceMeters,
            duration: duration,
            rawAvgPace: duration > 0 ? (duration / (distanceMeters / 1000.0)) : 360.0,
            rawAvgHeartRate: 160.0,
            rawAvgCadence: 156.0,
            workingAvgPace: duration > 0 ? (duration / (distanceMeters / 1000.0)) : 360.0,
            workingAvgCadence: 156.0,
            workingAvgHeartRate: 160.0,
            paceCV: 0.05,
            paceSlope: 0.0,
            percentZone4: 0.1,
            detectedTypeRaw: detectedTypeRaw
        )
        run.framboiseTags = framboiseTags
        return run
    }

    @MainActor
    func testCardiacDriftFatigue_DashboardWorkoutsAndChatProduceIdenticalPaceAndDuration() {
        let calendar = Calendar.current
        let now = Date()
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else {
            XCTFail("Failed to construct yesterday date")
            return
        }

        // Run from yesterday with cardiac drift tag and pace ~7:00/km (420 s/km)
        let yesterdayFartlek = makeRun(
            date: yesterday,
            duration: 2520.0,
            distanceMeters: 6000.0, // 420 s/km
            detectedTypeRaw: "Fartlek",
            framboiseTags: ["cardiacDrift"]
        )

        let runs = [yesterdayFartlek]
        let goal = "5K"
        let level = "Intermediate"
        let useMetric = true

        DailyTrainingStateStore.shared.invalidate()

        // 1. Surface 1: Workouts Tab State
        let workoutsState = DailyTrainingStateStore.shared.resolveState(
            runRecords: runs,
            activeGoal: goal,
            experienceLevel: level,
            useMetric: useMetric,
            now: now
        )

        let workoutsSession = workoutsState.activeSession
        XCTAssertEqual(workoutsSession.intent, .recoveryFlush, "Fatigue/drift must lock into .recoveryFlush, not .train or .fullRest")
        XCTAssertEqual(workoutsSession.durationBand, "15–20 Min")
        XCTAssertEqual(workoutsSession.mainRunDurationMinutes, 20)
        XCTAssertFalse(workoutsSession.paceBand.isEmpty)

        // 2. Surface 2: Training Zone Engine Prescription (Powers Dashboard Glass-Box & Targets)
        let profile = RunnerProfile.compute(from: runs)
        let tzInput = TrainingZoneInput(
            baselinePaceSec: yesterdayFartlek.workingAvgPace,
            workoutPaceSec: yesterdayFartlek.workingAvgPace,
            activeGoal: goal,
            experienceLevel: level,
            readyForHard: false,
            daysSinceWorkout: 1,
            heightAdjustedCadenceFloor: profile.heightAdjustedCadenceFloor,
            useMetricSystem: useMetric,
            userHeightCm: profile.userHeightCm,
            totalHistoricalRunsCount: runs.count
        )
        let dashboardRx = TrainingZoneEngine.computePrescription(tzInput, runs: runs)

        XCTAssertEqual(dashboardRx.nextSessionName, workoutsSession.sessionTitle, "Dashboard prescription session title must match Workouts tab")
        XCTAssertEqual(dashboardRx.prescribedDurationBand, workoutsSession.durationBand, "Dashboard prescription duration must match Workouts tab")
        XCTAssertEqual(dashboardRx.prescribedPaceBand, workoutsSession.paceBand, "Dashboard prescription pace must match Workouts tab")

        // 3. Surface 3: AI Chat Schedule Timeline Tool
        let cal = TrainingCalendar(calendar: calendar)
        let schedule = cal.evaluateSchedule(
            from: now,
            to: calendar.date(byAdding: .day, value: 1, to: now) ?? now,
            context: ScheduleEvaluationContext(runRecords: runs, activeGoal: goal, profile: profile, useMetric: useMetric)
        )

        guard let todaySchedule = schedule.first(where: { $0.relative == .today }) else {
            XCTFail("Schedule missing today")
            return
        }

        XCTAssertEqual(todaySchedule.planned.title, workoutsSession.sessionTitle, "Chat planned session title must match Workouts tab")
        XCTAssertEqual(todaySchedule.planned.minutesHigh, workoutsSession.mainRunDurationMinutes, "Chat planned minutes must match Workouts tab")
        XCTAssertEqual(todaySchedule.planned.paceBand, workoutsSession.paceBand, "Chat planned pace band must match Workouts tab")
        XCTAssertEqual(todaySchedule.planned.intent, .recoveryFlush, "Chat planned intent must be .recoveryFlush")

        // 4. Compact Summary Token Parity
        let compactSummary = TrainingCalendar.formatCompactScheduleSummary(days: [todaySchedule])
        XCTAssertTrue(compactSummary.contains(workoutsSession.sessionTitle), "Chat summary must contain exact session title")
        XCTAssertTrue(compactSummary.contains("15-20 min"), "Chat summary must contain 15-20 min")
        XCTAssertTrue(compactSummary.contains(workoutsSession.paceBand), "Chat summary must contain exact pace band")
    }

    @MainActor
    func testStreakVolumeCompression_DashboardWorkoutsAndChatProduceIdenticalFullRestDay() {
        let calendar = Calendar.current
        let now = Date()

        // 4 consecutive hard days pushing streak cap and volume ratio
        var runs: [RunRecord] = []
        for daysAgo in 1...4 {
            let runDate = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
            let r = makeRun(
                date: runDate,
                duration: 3600.0,
                distanceMeters: 8000.0,
                detectedTypeRaw: "Tempo Run"
            )
            runs.append(r)
        }

        DailyTrainingStateStore.shared.invalidate()

        let state = DailyTrainingStateStore.shared.resolveState(
            runRecords: runs,
            activeGoal: "5K",
            experienceLevel: "Novice",
            useMetric: true,
            now: now
        )

        let session = state.activeSession
        XCTAssertEqual(session.intent, .fullRest, "Streak limit reached must lock into .fullRest")
        XCTAssertTrue(session.isRestDay, "isRestDay must be true for full rest")
        XCTAssertEqual(session.mainRunDurationMinutes, 0, "Full rest day must prescribe 0 min running")
        XCTAssertEqual(session.paceBand, "No Pacing Target", "Full rest day must specify No Pacing Target")

        // Chat Tool Parity
        let cal = TrainingCalendar(calendar: calendar)
        let profile = RunnerProfile.compute(from: runs)
        let schedule = cal.evaluateSchedule(
            from: now,
            to: now,
            context: ScheduleEvaluationContext(runRecords: runs, activeGoal: "5K", profile: profile, useMetric: true)
        )
        guard let todayDay = schedule.first else {
            XCTFail("Schedule missing today")
            return
        }

        XCTAssertEqual(todayDay.planned.kind, .rest, "Chat planned kind must be .rest")
        XCTAssertEqual(todayDay.planned.intent, .fullRest, "Chat planned intent must be .fullRest")
        XCTAssertEqual(todayDay.planned.minutesHigh, 0, "Chat planned duration must be 0")
        XCTAssertNil(todayDay.planned.paceBand, "Chat planned pace band must be nil for rest")

        let summary = TrainingCalendar.formatCompactScheduleSummary(days: [todayDay])
        XCTAssertTrue(summary.contains("Rest Day (No run scheduled)"), "Chat summary must indicate Rest Day")
    }
}
