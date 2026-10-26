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
        XCTAssertEqual(workoutsSession.durationBand, "27 Min")
        XCTAssertEqual(workoutsSession.mainRunDurationMinutes, 20)
        XCTAssertEqual(workoutsSession.totalDurationMinutes, 27)
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
        XCTAssertEqual(todaySchedule.planned.minutesHigh, workoutsSession.totalDurationMinutes, "Chat planned minutes must match Workouts tab")
        XCTAssertEqual(todaySchedule.planned.paceBand, workoutsSession.paceBand, "Chat planned pace band must match Workouts tab")
        XCTAssertEqual(todaySchedule.planned.intent, .recoveryFlush, "Chat planned intent must be .recoveryFlush")

        // 4. Compact Summary Token Parity
        let compactSummary = TrainingCalendar.formatCompactScheduleSummary(days: [todaySchedule])
        XCTAssertTrue(compactSummary.contains(workoutsSession.sessionTitle), "Chat summary must contain exact session title")
        XCTAssertTrue(compactSummary.contains("\(workoutsSession.totalDurationMinutes) min"), "Chat summary must contain exact duration")
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

    @MainActor
    func testUpcomingSchedule_CalendarToolAndActiveSessionMicrocycleMatch() {
        let calendar = Calendar.current
        let now = Date()
        guard let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: now) else {
            XCTFail("Failed to construct date")
            return
        }
        let run1 = makeRun(date: twoDaysAgo, duration: 2400, distanceMeters: 6000, detectedTypeRaw: "Easy Run")
        let runs = [run1]

        let profile = RunnerProfile.compute(from: runs, trainingGoal: "Base Building", experienceLevel: "Intermediate", now: now)

        DailyTrainingStateStore.shared.invalidate()
        let state = DailyTrainingStateStore.shared.resolveState(
            runRecords: runs,
            activeGoal: "Base Building",
            experienceLevel: profile.experienceLevel,
            useMetric: true,
            now: now
        )

        let cal = TrainingCalendar(calendar: calendar)
        guard let horizonEnd = calendar.date(byAdding: .day, value: 5, to: now) else {
            XCTFail("Failed to construct horizon end date")
            return
        }
        let schedule = cal.evaluateSchedule(
            from: now,
            to: horizonEnd,
            context: ScheduleEvaluationContext(runRecords: runs, activeGoal: "Base Building", profile: profile, useMetric: true)
        )

        // Today matches
        guard let todaySched = schedule.first(where: { $0.relative == .today }) else {
            XCTFail("Missing today in schedule")
            return
        }
        XCTAssertEqual(todaySched.planned.title, state.activeSession.sessionTitle)
        XCTAssertEqual(todaySched.planned.minutesHigh, state.activeSession.totalDurationMinutes)

        // Upcoming days in microcycle (Tomorrow + future horizon) match schedule
        let upcomingDays = schedule.filter { $0.relative == .tomorrow || $0.relative == .future }
        XCTAssertEqual(upcomingDays.count, state.activeSession.microcycle.count)
        for (schedDay, microSession) in zip(upcomingDays, state.activeSession.microcycle) {
            XCTAssertEqual(schedDay.planned.title, microSession.sessionTitle, "Schedule title must match microcycle title for \(schedDay.date)")
            XCTAssertEqual(schedDay.planned.kind == .rest, microSession.isRestDay, "Schedule rest state must match microcycle rest state for \(schedDay.date)")
        }
    }

    func testWeightedBaselineStats_EquivalenceAcrossCallSites() {
        let calendar = Calendar.current
        let now = Date()
        guard let d1 = calendar.date(byAdding: .day, value: -3, to: now),
              let d2 = calendar.date(byAdding: .day, value: -5, to: now),
              let d3 = calendar.date(byAdding: .day, value: -10, to: now) else {
            XCTFail("Failed to construct dates")
            return
        }

        let r1 = makeRun(date: d1, duration: 1800, distanceMeters: 4500, detectedTypeRaw: "Easy Run")
        let r2 = makeRun(date: d2, duration: 3600, distanceMeters: 10000, detectedTypeRaw: "Tempo Run")
        r2.workingAvgCadence = 162.0
        let r3 = makeRun(date: d3, duration: 5400, distanceMeters: 15000, detectedTypeRaw: "Long Run")
        r3.workingAvgCadence = 150.0

        let runs = [r1, r2, r3]

        // 1. SessionSynthesisEngine.computeWeightedBaselineStats
        guard let canonical = SessionSynthesisEngine.computeWeightedBaselineStats(from: runs, priorTo: now) else {
            XCTFail("Failed to compute weighted baseline stats")
            return
        }

        // 2. RunRecord.computeHistoricalBaselineCadence prior to r1.date
        let runRecordBaseline = r1.computeHistoricalBaselineCadence(in: runs)
        let priorToR1Canonical = SessionSynthesisEngine.computeWeightedBaselineStats(from: runs, priorTo: r1.date)

        // Calculate expected duration-weighted cadence across all 3 runs:
        // (156*1800 + 162*3600 + 150*5400) / (1800 + 3600 + 5400)
        // = (280800 + 583200 + 810000) / 10800 = 1674000 / 10800 = 155.0
        XCTAssertEqual(Int(canonical.avgCadence.rounded()), 155)
        XCTAssertEqual(runRecordBaseline, priorToR1Canonical?.avgCadence, "RunRecord cadence baseline must strictly match canonical engine stats prior to run date")

        // 3. GoalReadinessCard dynamic metrics delegated to RunnerProfile.compute
        let profile = RunnerProfile.compute(from: runs, trainingGoal: "Base Building", now: now)
        XCTAssertEqual(profile.current30DayDistanceKm, 29.5, accuracy: 0.1)
        XCTAssertEqual(profile.weeklyAverageKm, 29.5 / (30.0 / 7.0), accuracy: 0.1)
        XCTAssertEqual(profile.longestRunKm, 15.0, accuracy: 0.1)
    }

    func testDrillCardConfig_LockedDurationTrimmingUnderFatigue() {
        let fatigueConfig = DrillCardConfig(
            lockedDurationMinutes: 7,
            readinessState: .acuteFatigue
        )
        XCTAssertEqual(fatigueConfig.effectiveDurationTitle, "7 min")

        let productiveConfig = DrillCardConfig(
            lockedDurationMinutes: 10,
            readinessState: .productive
        )
        XCTAssertEqual(productiveConfig.effectiveDurationTitle, "10 min")
    }

    @MainActor
    func testReadinessAndWorkloadFacts_TargetMinutesMatchesLockedDailyState() {
        guard #available(iOS 26.0, *) else { return }
        let calendar = Calendar.current
        let now = Date()
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else {
            XCTFail("Failed to construct date")
            return
        }
        let run1 = makeRun(date: yesterday, duration: 2400, distanceMeters: 6000, detectedTypeRaw: "Easy Run")
        let runs = [run1]

        UserDefaults.standard.set("Base Building", forKey: "trainingGoal")
        UserDefaults.standard.set(true, forKey: "useMetricSystem")
        let profile = RunnerProfile.compute(from: runs, trainingGoal: "Base Building", now: now)
        UserDefaults.standard.set(profile.experienceLevel, forKey: "experienceLevel")

        DailyTrainingStateStore.shared.invalidate()
        let state = DailyTrainingStateStore.shared.resolveState(
            runRecords: runs,
            activeGoal: "Base Building",
            experienceLevel: profile.experienceLevel,
            useMetric: true,
            now: now
        )

        let engine = AnalystChatEngine(runRecord: run1)
        let json = engine.executeReadinessAndWorkloadQuery()
        guard let data = json.data(using: .utf8),
              let facts = try? JSONDecoder().decode(ReadinessFacts.self, from: data) else {
            XCTFail("Failed to decode ReadinessFacts JSON")
            return
        }

        XCTAssertEqual(facts.today_target_minutes, state.todaySession?.totalDurationMinutes ?? 0, "Chat tool facts must report identical today_target_minutes as locked state")
        XCTAssertNil(facts.status_guidance, "Tool must not generate scripted dialogue strings")
    }
}
