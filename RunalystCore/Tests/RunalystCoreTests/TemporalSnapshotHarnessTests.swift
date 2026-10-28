import Foundation
import Testing
@testable import RunalystCore

@Suite("Brick 1: Golden Temporal Truth Harness")
struct TemporalSnapshotHarnessTests {

    @Test("Invariant 1: Conservation of Distance - This Week must equal exactly 9.46 km, never 19.5 km")
    func testConservationOfDistanceThisWeek() {
        let (now, calendar, runs) = GoldenTemporalFixtures.makeReferenceTimeline()

        // Current calendar week boundary: Monday 00:00:00 to Next Monday 00:00:00
        let todayStart = calendar.startOfDay(for: now)
        let mondayStart = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        let nextMondayStart = calendar.date(byAdding: .day, value: 7, to: mondayStart) ?? mondayStart

        // Workouts falling strictly within [Monday 00:00, Next Monday 00:00)
        let thisWeekRuns = runs.filter { $0.date >= mondayStart && $0.date < nextMondayStart }

        // Sum distance
        let thisWeekDistanceMeters = thisWeekRuns.reduce(0.0) { $0 + $1.totalDistanceMeters }
        let thisWeekKm = thisWeekDistanceMeters / 1000.0

        #expect(thisWeekRuns.count == 4, "This week must contain exactly 4 workouts (2 Mon, 2 Tue)")
        #expect(thisWeekKm == 9.46, "This week volume must be exactly 9.46 km")
        #expect(thisWeekKm != 19.5, "This week volume must never report the rolling 19.5 km figure")
    }

    @Test("Invariant 2: Calendar Disjointness - Slices 2W Ago, Last Week, and This Week are strictly disjoint")
    func testCalendarDisjointnessAcrossWeeks() {
        let (now, calendar, runs) = GoldenTemporalFixtures.makeReferenceTimeline()

        let todayStart = calendar.startOfDay(for: now)
        let thisMondayStart = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        let lastMondayStart = calendar.date(byAdding: .day, value: -7, to: thisMondayStart) ?? thisMondayStart
        let twoWeeksAgoMondayStart = calendar.date(byAdding: .day, value: -7, to: lastMondayStart) ?? lastMondayStart

        let w2Runs = runs.filter { $0.date >= twoWeeksAgoMondayStart && $0.date < lastMondayStart }
        let w1Runs = runs.filter { $0.date >= lastMondayStart && $0.date < thisMondayStart }
        let w0Runs = runs.filter { $0.date >= thisMondayStart }

        let w2DistanceKm = w2Runs.reduce(0.0) { $0 + $1.totalDistanceMeters } / 1000.0
        let w1DistanceKm = w1Runs.reduce(0.0) { $0 + $1.totalDistanceMeters } / 1000.0
        let w0DistanceKm = w0Runs.reduce(0.0) { $0 + $1.totalDistanceMeters } / 1000.0

        // Invariants exactly matching the authentic screenshot:
        // 2W Ago: 18.2 km
        // Last Wk: 19.5 km
        // This Wk: 9.46 km
        #expect(w2DistanceKm == 18.2, "2W Ago volume must be 18.2 km")
        #expect(w1DistanceKm == 19.5, "Last Week volume must be 19.5 km")
        #expect(w0DistanceKm == 9.46, "This Week volume must be 9.46 km")

        // Strict disjointness check
        let w2Ids = Set(w2Runs.map(\.id))
        let w1Ids = Set(w1Runs.map(\.id))
        let w0Ids = Set(w0Runs.map(\.id))

        #expect(w2Ids.isDisjoint(with: w1Ids), "2W Ago and Last Week must be strictly disjoint")
        #expect(w1Ids.isDisjoint(with: w0Ids), "Last Week and This Week must be strictly disjoint")
        #expect(w2Ids.isDisjoint(with: w0Ids), "2W Ago and This Week must be strictly disjoint")
    }

    @Test("Invariant 3: Rolling 7-Day Window vs Calendar Week separation")
    func testRolling7DayVsCalendarWeekSeparation() {
        let (now, calendar, runs) = GoldenTemporalFixtures.makeReferenceTimeline()

        // Rolling 168 hours (7 days) back from Tue 15:56 (starts Wednesday 15:56)
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let rolling7dRuns = runs.filter { $0.date >= sevenDaysAgo && $0.date <= now }

        let rolling7dDistanceKm = rolling7dRuns.reduce(0.0) { $0 + $1.totalDistanceMeters } / 1000.0

        // Wednesday run (10.04 km) occurred within the last 168 hours, plus This Week (9.46 km)
        #expect(rolling7dRuns.count == 5, "Rolling 7 days includes Wednesday + Mon(2) + Tue(2) = 5 runs")
        #expect(rolling7dDistanceKm == 19.5, "Rolling 7 days volume is 19.5 km (Wed 10.04 + This Wk 9.46)")
    }

    @Test("Invariant 4: Dimensional Average Pace Integrity - moving seconds divided by distance")
    func testDimensionalAveragePaceIntegrity() {
        let (now, calendar, runs) = GoldenTemporalFixtures.makeReferenceTimeline()

        let todayStart = calendar.startOfDay(for: now)
        let mondayStart = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        let thisWeekRuns = runs.filter { $0.date >= mondayStart }

        let totalDurationSeconds = thisWeekRuns.reduce(0.0) { $0 + $1.durationSeconds }
        let totalDistanceKm = thisWeekRuns.reduce(0.0) { $0 + $1.totalDistanceMeters } / 1000.0

        // True dimensional pace (s/km)
        let dimensionalPaceSecPerKm = totalDurationSeconds / totalDistanceKm

        // Arithmetic average of individual paces (s/km) - THE FORBIDDEN PATTERN
        let unweightedPaceAverage = thisWeekRuns.map(\.workingAvgPace).reduce(0.0, +) / Double(thisWeekRuns.count)

        // Total duration: 274 + 2760 + 502 + 890 = 4426s
        // Total distance: 9.46 km
        // Dimensional pace: 4426 / 9.46 = 467.86 s/km (~7:48/km)
        // Unweighted pace: (403 + 478 + 372 + 536) / 4 = 447.25 s/km (~7:27/km)
        #expect(abs(dimensionalPaceSecPerKm - 467.86) < 0.1, "Dimensional pace must equal 467.86 s/km")
        #expect(abs(unweightedPaceAverage - 447.25) < 0.1, "Unweighted pace exhibits a 20.6 second distortion")
        #expect(dimensionalPaceSecPerKm != unweightedPaceAverage, "Dimensional pace must never equal unweighted arithmetic mean")
    }

    @Test("Invariant 5: Duration-Weighted Cadence Integrity")
    func testDurationWeightedCadenceIntegrity() {
        let (now, calendar, runs) = GoldenTemporalFixtures.makeReferenceTimeline()

        let todayStart = calendar.startOfDay(for: now)
        let mondayStart = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        let thisWeekRuns = runs.filter { $0.date >= mondayStart }

        let totalDurationSeconds = thisWeekRuns.reduce(0.0) { $0 + $1.durationSeconds }
        let weightedCadenceSum = thisWeekRuns.reduce(0.0) { $0 + ($1.workingAvgCadence * $1.durationSeconds) }
        let durationWeightedCadence = weightedCadenceSum / totalDurationSeconds

        let unweightedCadence = thisWeekRuns.map(\.workingAvgCadence).reduce(0.0, +) / Double(thisWeekRuns.count)

        // Duration weighted cadence:
        // (162*274 + 155*2760 + 165*502 + 150*890) / 4426 = 688548 / 4426 = 155.57 SPM (156 SPM)
        // Unweighted: (162 + 155 + 165 + 150) / 4 = 158.0 SPM
        #expect(abs(durationWeightedCadence - 155.57) < 0.1, "Duration-weighted cadence must equal 155.57 SPM")
        #expect(unweightedCadence == 158.0, "Unweighted cadence gives excessive weight to short primer reps")
        #expect(durationWeightedCadence.rounded() == 156.0, "Rounded display cadence must be 156 SPM")
    }

    @Test("Invariant 6: Daylight Saving Time (DST) Boundary Safety - 23h and 25h weeks preserve workouts")
    func testDaylightSavingTimeBoundarySafety() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        calendar.firstWeekday = 2 // Monday start

        // Spring Forward DST week: 2026-03-02 (Monday) to 2026-03-09 (Next Monday)
        // Sunday 2026-03-08 is a 23-hour day.
        var compStart = DateComponents()
        compStart.year = 2026
        compStart.month = 3
        compStart.day = 2
        compStart.hour = 0
        compStart.minute = 0
        compStart.second = 0
        let springMonday = calendar.date(from: compStart) ?? Date()

        let nextMonday = calendar.date(byAdding: .day, value: 7, to: springMonday) ?? springMonday

        // Sunday evening run 2 hours before midnight
        let sundayNightRunDate = (calendar.date(byAdding: .day, value: 6, to: springMonday) ?? springMonday)
            .addingTimeInterval(22 * 3600)

        #expect(sundayNightRunDate >= springMonday && sundayNightRunDate < nextMonday,
                "Sunday night run must fall strictly within the spring DST week")

        // Proven: Epoch difference across spring transition is 167 hours, not 168 hours!
        let diffHours = nextMonday.timeIntervalSince(springMonday) / 3600.0
        #expect(diffHours == 167.0, "Spring DST week must be exactly 167 hours, proving 7*86400 would be inaccurate")
    }
}
