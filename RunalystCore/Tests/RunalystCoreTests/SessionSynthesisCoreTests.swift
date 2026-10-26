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
}
