import Testing
import Foundation
@testable import RunalystCore

@Suite("SessionSynthesisCore & Horizon Tests")
struct SessionSynthesisCoreTests {

    @Test("Cadence Floor adjusts with runner height")
    func testHeightAdjustedCadenceFloor() {
        let tall = SessionSynthesisCore.heightAdjustedCadenceFloor(heightCm: 190.0)
        let standard = SessionSynthesisCore.heightAdjustedCadenceFloor(heightCm: 175.0)
        let short = SessionSynthesisCore.heightAdjustedCadenceFloor(heightCm: 160.0)

        #expect(standard == 150)
        #expect(tall < 150)
        #expect(short > 150)
    }

    @Test("Weighted Baseline computes duration and classification weighting")
    func testWeightedBaselineCalculation() {
        let now = Date(timeIntervalSince1970: 1700000000)
        let run1 = SynthesisRunSample(
            date: now.addingTimeInterval(-86400 * 2),
            durationSeconds: 3600,
            distanceMeters: 10000,
            workingAvgPaceSecPerKm: 360,
            workingAvgCadenceSPM: 160,
            workingAvgHeartRateBPM: 145,
            percentZone4: 0.1,
            detectedType: "Easy Run"
        )
        let run2 = SynthesisRunSample(
            date: now.addingTimeInterval(-86400 * 4),
            durationSeconds: 1800,
            distanceMeters: 6000,
            workingAvgPaceSecPerKm: 300,
            workingAvgCadenceSPM: 170,
            workingAvgHeartRateBPM: 165,
            percentZone4: 0.5,
            detectedType: "Intervals"
        )

        let baseline = SessionSynthesisCore.computeWeightedBaseline(from: [run1, run2], priorTo: now)
        #expect(baseline.cadence >= 155 && baseline.cadence <= 170)
        #expect(baseline.pace >= 300 && baseline.pace <= 360)
    }

    @Test("Day completion rule requires 20 min main run or 30 min cumulative")
    func testDayCompletionRule() {
        let now = Date(timeIntervalSince1970: 1700000000)
        let shortPrimer = SynthesisRunSample(
            date: now,
            durationSeconds: 600,
            distanceMeters: 1500,
            workingAvgPaceSecPerKm: 360,
            workingAvgCadenceSPM: 165,
            workingAvgHeartRateBPM: 140,
            percentZone4: 0.1,
            detectedType: "Cadence Pyramids",
            isPrimer: true
        )
        #expect(!SessionSynthesisCore.isWorkoutDayComplete(runs: [shortPrimer]))

        let mainRun = SynthesisRunSample(
            date: now.addingTimeInterval(600),
            durationSeconds: 1500,
            distanceMeters: 4000,
            workingAvgPaceSecPerKm: 375,
            workingAvgCadenceSPM: 158,
            workingAvgHeartRateBPM: 142,
            percentZone4: 0.05,
            detectedType: "Easy Run",
            isPrimer: false
        )
        #expect(SessionSynthesisCore.isWorkoutDayComplete(runs: [shortPrimer, mainRun]))
    }

    @Test("5th day horizon long run pairs title, duration, and intensity zone")
    func testHorizonLongRunCoupling() {
        // Thursday 2023-11-16: Days +1 (Fri), +2 (Sat), +3 (Sun), +4 (Mon), +5 (Tue)
        // With weekday templates: Fri (6 km), Sat (Long Run 10 km on Sat)
        // Let's test from Sunday so Friday is offset 5 without Saturday having occurred yet:
        // Sunday 2023-11-12: +1 (Mon), +2 (Tue), +3 (Wed), +4 (Thu), +5 (Fri) -> No Long Run in Mon-Fri!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        var comps = DateComponents()
        comps.year = 2023
        comps.month = 11
        comps.day = 12 // Sunday
        comps.hour = 12
        let sunday = cal.date(from: comps) ?? Date()

        let context = AthleteSynthesisContext(
            activeGoal: "10K Progression",
            experienceLevel: "Intermediate",
            useMetric: true,
            userHeightCm: 175.0,
            now: sunday,
            calendar: cal
        )

        let horizon = SessionHorizonCore.synthesizeHorizon(
            startDate: cal.date(byAdding: .day, value: 1, to: sunday) ?? sunday,
            daysCount: 5,
            runs: [],
            context: context
        )

        #expect(horizon.count == 5)
        let fifthDay = horizon[4]
        #expect(fifthDay.sessionTitle.contains("Long Run 10 km"))
        #expect(fifthDay.spec.minutesLow == 50)
        #expect(fifthDay.spec.minutesHigh == 65)
        #expect(fifthDay.spec.paceBand != nil)
    }

    @Test("Quality workouts receive Zone 4/5 pace bands instead of Zone 2 or literal string")
    func testQualityWorkoutPaceBands() {
        let specMon = SessionHorizonCore.templateSpecForWeekday(
            weekday: 2, // Monday 10K
            activeGoal: "10K Progression",
            experienceLevel: "Intermediate",
            useMetric: true
        )
        #expect(specMon.intensityZone == .zone4Tempo)

        let specThu = SessionHorizonCore.templateSpecForWeekday(
            weekday: 5, // Thursday 5K
            activeGoal: "5K Rhythm",
            experienceLevel: "Intermediate",
            useMetric: true
        )
        #expect(specThu.intensityZone == .zone5Interval)
    }

    @Test("MacroVolumeCore 30-Day 4-week buckets sum strictly to 30-day total and match 7-Day total")
    func testMacroVolumeCoreExactPartitioning() {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US_POSIX")
        let now = Date(timeIntervalSince1970: 1_793_050_000)

        // Include runs across the entire 30-day window (including days 24..29 ago which old Sunday-to-Sunday weeks dropped!)
        let dayOffsets: [(daysAgo: Int, meters: Double)] = [
            (29, 9500),
            (26, 9500),
            (20, 12700),
            (18, 12700),
            (13, 6650),
            (10, 6650),
            (8, 23000),
            (2, 6400)
        ]

        let samples = dayOffsets.enumerated().map { idx, item in
            let date = cal.date(byAdding: .day, value: -item.daysAgo, to: now) ?? now
            return VolumeRunSample(
                id: UUID(),
                date: date,
                totalDistanceMeters: item.meters,
                durationSeconds: item.meters * 0.36,
                workingAvgPace: 360,
                workingAvgHeartRate: 148,
                workingAvgCadence: 158,
                classification: idx % 2 == 0 ? "Easy Run" : "Steady Effort"
            )
        }

        let summary30d = MacroVolumeCore.evaluateVolumeSummary(
            allRuns: samples,
            timeRange: "30 Days",
            now: now,
            calendar: cal
        )
        let summary7d = MacroVolumeCore.evaluateVolumeSummary(
            allRuns: samples,
            timeRange: "7 Days",
            now: now,
            calendar: cal
        )

        #expect(abs(summary30d.totalDistanceMeters - 87_100.0) < 0.01)

        let snapshot = TemporalSnapshotCore.evaluateSnapshot(runs: samples, now: now, calendar: cal)
        let thisWeekMeters = summary30d.trailing4Weeks.last?.distanceMeters ?? 0.0
        #expect(abs(thisWeekMeters - snapshot.thisWeek.totalDistanceMeters) < 0.01)

        let sum7Days = summary7d.trailing7Days.map(\.distanceMeters).reduce(0.0, +)
        #expect(abs(sum7Days - summary7d.totalDistanceMeters) < 0.01)
    }

    @Test("DashboardTrajectorySynthesis reconciles stale On Track headline when Building Base")
    func testDashboardTrajectoryReconcileHeadline() {
        let assessment = TrajectoryAssessment(
            verdict: .onTrack,
            efDelta: 0.05,
            hrDelta: -2.0,
            oscDelta: -0.2,
            vrDelta: -0.1,
            avgRecentEF: 1.15,
            avgRecentOsc: 8.8,
            avgRecentVR: 8.2
        )
        let benchmark = GoalBenchmarkCore.evaluate(
            goal: "10K Race",
            currentWeeklyKm: 20.3,
            longestRunKm: 10.6,
            userHeightCm: 175.0,
            experienceLevel: "Intermediate / Enthusiast"
        )
        let synthesis = MacroVolumeCore.evaluateDashboardTrajectory(
            assessment: assessment,
            benchmark: benchmark,
            trainingGoal: "10K Race",
            paceContext: "6:00 /km"
        )

        #expect(synthesis.directiveCode == "TRAJECTORY_BUILDING_BASE")
        #expect(synthesis.badgeLabel == "Building Base")
        #expect(synthesis.canonicalHeadline == "Building Aerobic Base")
        #expect(synthesis.reconcileHeadline("On Track For Goal") == "Building Aerobic Base")
        #expect(synthesis.reconcileHeadline("") == "Building Aerobic Base")
        #expect(synthesis.reconcileHeadline("Steady Base Momentum") == "Steady Base Momentum")
    }
}
