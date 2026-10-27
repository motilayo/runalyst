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

    @MainActor
    func testCompletedToday_MicrocycleMatchesTrainingCalendarScheduleOneForOne() {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US_POSIX")
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 10
        comps.day = 26 // Monday
        comps.hour = 8
        guard let monday = cal.date(from: comps) else {
            XCTFail("Failed to build Monday date")
            return
        }

        // 2 completed runs on Monday (Primer + Main Run)
        let primer = makeRun(date: monday.addingTimeInterval(-1800), duration: 600, distanceMeters: 1500, detectedTypeRaw: "Strides")
        primer.framboiseTags = ["prescribedDrill", "drill:Strides"]

        let mainRun = makeRun(date: monday, duration: 2400, distanceMeters: 6000, detectedTypeRaw: "Easy Run")

        let runs = [primer, mainRun]
        let goal = "10K Progression"
        let profile = RunnerProfile.compute(from: runs, trainingGoal: goal, now: monday)

        DailyTrainingStateStore.shared.invalidate()
        let dailyState = DailyTrainingStateStore.shared.resolveState(
            runRecords: runs,
            activeGoal: goal,
            experienceLevel: profile.experienceLevel,
            useMetric: true,
            userHeightCm: profile.userHeightCm,
            now: monday
        )

        guard case .completedToday(_, let tomorrowSession) = dailyState else {
            XCTFail("State must be .completedToday after main run is complete")
            return
        }

        let trainingCal = TrainingCalendar(calendar: cal, now: monday)
        let evalContext = ScheduleEvaluationContext(
            runRecords: runs,
            activeGoal: goal,
            profile: profile,
            useMetric: true
        )

        // Evaluate calendar schedule for rest of the week (Tuesday through Saturday)
        guard let tuesday = cal.date(byAdding: .day, value: 1, to: monday),
              let saturday = cal.date(byAdding: .day, value: 5, to: monday) else {
            XCTFail("Failed to construct horizon bounds")
            return
        }

        let scheduleDays = trainingCal.evaluateSchedule(from: tuesday, to: saturday, context: evalContext)
        XCTAssertEqual(scheduleDays.count, 5, "Expected 5 upcoming days (Tue-Sat)")

        // Check 1: Tuesday matches tomorrowSession
        let tuesdaySchedule = scheduleDays[0]
        XCTAssertEqual(tuesdaySchedule.planned.title, tomorrowSession.sessionTitle)
        XCTAssertEqual(tuesdaySchedule.planned.paceBand, tomorrowSession.paceBand)
        XCTAssertEqual(tuesdaySchedule.planned.cadenceFloor, tomorrowSession.cadenceFloor)

        // Check 2: Days +2...+5 match microcycle 1-for-1
        for (idx, microDay) in tomorrowSession.microcycle.enumerated() {
            guard idx + 1 < scheduleDays.count else { break }
            let schedDay = scheduleDays[idx + 1]
            XCTAssertEqual(microDay.sessionTitle, schedDay.planned.title, "Microcycle title must match schedule query for \(schedDay.weekday)")
            if let planned = microDay.plannedSession {
                XCTAssertEqual(planned.paceBand, schedDay.planned.paceBand, "Pace band must match for \(schedDay.weekday)")
                XCTAssertEqual(planned.minutesLow, schedDay.planned.minutesLow, "Minutes low must match for \(schedDay.weekday)")
                XCTAssertEqual(planned.minutesHigh, schedDay.planned.minutesHigh, "Minutes high must match for \(schedDay.weekday)")
            }
        }
    }

    @MainActor
    func testBuildingBaseVolume_DashboardAndChatSurfacesAgreeOnBuildingStatusAndNeverSayOnTrack() throws {
        let now = Date()
        let cal = Calendar.current

        let schema = Schema([RunRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        // 30 days of runs totaling 87.1 km (averaging 20.3 km/wk: 87.1 / (30/7) = 20.3 km/wk)
        // 14 runs over 30 days
        var runs: [RunRecord] = []
        for i in 0..<14 {
            let runDate = cal.date(byAdding: .day, value: -(i * 2), to: now) ?? now
            let run = makeRun(
                date: runDate,
                duration: 2700,
                distanceMeters: 6221.0, // ~6.22 km per run * 14 = ~87.1 km total
                detectedTypeRaw: "Easy Run",
                framboiseTags: i == 0 ? ["cardiacDrift"] : []
            )
            context.insert(run)
            runs.append(run)
        }
        try context.save()

        let goal = "10K Race"
        UserDefaults.standard.set(goal, forKey: "trainingGoal")

        let profile = RunnerProfile.compute(from: runs, trainingGoal: goal, now: now)
        XCTAssertEqual(profile.goalBenchmark.weeklyVolumeStatus, .building, "20.3 km/wk against 25-42 km target must evaluate to .building")
        XCTAssertEqual(profile.goalBenchmark.volumeGapKm, 4.7, accuracy: 0.1, "Volume gap must be 4.7 km")

        // 1. Chat Surface Verification
        if #available(iOS 26.0, *) {
            let chatEngine = AnalystChatEngine(modelContext: context, runRecord: runs.first, mode: .macroCoach)
            let chatTelemetry = chatEngine.executeReadinessAndWorkloadQueryForModel()

            XCTAssertTrue(chatTelemetry.contains("Building Base"), "Chat telemetry must state Building Base")
            XCTAssertTrue(chatTelemetry.contains("4.7 km below"), "Chat telemetry must specify volume gap")
            XCTAssertFalse(chatTelemetry.contains("Status: On Track"), "Chat telemetry must NEVER say On Track when building base")
            XCTAssertFalse(chatTelemetry.contains("Acutefatigue"), "Chat telemetry must NEVER leak raw camelCase code token Acutefatigue")
            XCTAssertTrue(chatTelemetry.contains("Biological Readiness: Recovering from Recent Effort"), "Chat telemetry must explain readiness in human coaching English")
        }

        // 2. Dashboard Surface Verification
        let assessment = SessionSynthesisEngine.evaluate30DayTrajectory(from: runs, now: now)
        let benchmark = profile.goalBenchmark
        let volumeStatus = benchmark.weeklyVolumeStatus

        let directiveContext: String
        if assessment.verdict == .easeUp {
            directiveContext = "TRAJECTORY_EASE_UP"
        } else if volumeStatus == .building {
            directiveContext = "TRAJECTORY_BUILDING_BASE"
        } else if volumeStatus == .exceeding {
            directiveContext = "TRAJECTORY_EXCEEDING"
        } else {
            directiveContext = "TRAJECTORY_ON_TRACK"
        }

        XCTAssertEqual(directiveContext, "TRAJECTORY_BUILDING_BASE", "Dashboard 30-day directive must evaluate to TRAJECTORY_BUILDING_BASE")
        XCTAssertNotEqual(directiveContext, "TRAJECTORY_ON_TRACK", "Dashboard 30-day directive must NEVER evaluate to TRAJECTORY_ON_TRACK when volume is below target band")

        // 3. Goal Readiness Card Surface Verification (SSOT)
        let goalSpec = GoalReadinessCard.evaluateGoalSpec(
            allRuns: runs,
            trainingGoal: goal,
            useMetricSystem: true,
            now: now
        )
        XCTAssertEqual(goalSpec.statusLabel, "Building Base", "Goal readiness card must evaluate to Building Base when weekly volume is below target")
        XCTAssertNotEqual(goalSpec.statusLabel, "Race Ready", "Goal readiness card must NEVER declare Race Ready when weekly volume is in building phase")
        XCTAssertTrue(goalSpec.coachingRationale.contains("toward 25 km/wk"), "Rationale must explain that volume is building toward the target foundation")
    }
}
