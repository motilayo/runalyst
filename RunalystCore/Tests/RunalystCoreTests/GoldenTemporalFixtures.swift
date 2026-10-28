import Foundation
@testable import RunalystCore

/// Curated golden temporal fixtures representing real-world human workout timelines,
/// calendar week boundaries, multi-session days, and edge cases (DST, treadmill calibration).
public enum GoldenTemporalFixtures {

    private static func makeUUID(_ string: String) -> UUID {
        UUID(uuidString: string) ?? UUID()
    }

    /// Base reference time: Tuesday at 15:56:00 (Matching the user's authentic screenshot).
    ///
    /// Reconstructs the exact timeline that produced the 19.5 km bug:
    /// - 2W Ago (W_-2): 18.2 km
    /// - Last Week (W_-1): 19.5 km (Mon 9.46 km + Wed 10.04 km)
    /// - This Week (W_0): EXACTLY 9.46 km (Mon 0.68 + 5.77 km, Tue 1.35 + 1.66 km)
    /// - Trailing 7 Days (Rolling 168h): EXACTLY 19.5 km (Wed 10.04 km + This Wk 9.46 km)
    public static func makeReferenceTimeline() -> (
        referenceNow: Date,
        calendar: Calendar,
        runs: [VolumeRunSample]
    ) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        calendar.firstWeekday = 2 // Monday start

        // Base anchor: Tuesday 2026-10-27 at 15:56:00
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 27
        components.hour = 15
        components.minute = 56
        components.second = 0
        let now = calendar.date(from: components) ?? Date(timeIntervalSince1970: 1793130960)

        // Monday start of this week: 2026-10-26 00:00:00
        let thisMondayStart = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) ?? now

        // Monday start of last week: 2026-10-19 00:00:00
        let lastMondayStart = calendar.date(byAdding: .day, value: -7, to: thisMondayStart) ?? thisMondayStart

        // Monday start of 2W ago: 2026-10-12 00:00:00
        let twoWeeksAgoMondayStart = calendar.date(byAdding: .day, value: -7, to: lastMondayStart) ?? lastMondayStart

        // 1. "2W Ago" Long Run (2026-10-18 09:00:00 - Sunday of W_-2) -> Exactly 18.2 km
        let run2WDate = (calendar.date(byAdding: .day, value: 6, to: twoWeeksAgoMondayStart) ?? twoWeeksAgoMondayStart)
            .addingTimeInterval(9 * 3600)
        let run2WAgo = VolumeRunSample(
            id: makeUUID("00000000-0000-0000-0000-000000000001"),
            date: run2WDate,
            totalDistanceMeters: 18200.0,
            durationSeconds: 7280.0,
            workingAvgPace: 400.0, // 6:40/km
            workingAvgHeartRate: 142,
            workingAvgCadence: 158.0,
            classification: "Long Run"
        )

        // 2. "Last Week" Monday Run (2026-10-19 07:30:00) -> 9.46 km (Outside rolling 168h, inside W_-1)
        let lastMonDate = (calendar.date(byAdding: .hour, value: 7, to: lastMondayStart) ?? lastMondayStart)
            .addingTimeInterval(30 * 60)
        let runLastWeekMon = VolumeRunSample(
            id: makeUUID("00000000-0000-0000-0000-000000000002"),
            date: lastMonDate,
            totalDistanceMeters: 9460.0,
            durationSeconds: 4400.0,
            workingAvgPace: 465.0,
            workingAvgHeartRate: 138,
            workingAvgCadence: 156.0,
            classification: "Easy Run"
        )

        // 3. "Last Week" Wednesday Run (2026-10-21 17:00:00) -> 10.04 km (Inside rolling 168h, inside W_-1)
        // Last Week Total = 9.46 km + 10.04 km = 19.50 km!
        let lastWedDate = (calendar.date(byAdding: .day, value: 2, to: lastMondayStart) ?? lastMondayStart)
            .addingTimeInterval(17 * 3600)
        let runLastWeekWed = VolumeRunSample(
            id: makeUUID("00000000-0000-0000-0000-000000000003"),
            date: lastWedDate,
            totalDistanceMeters: 10040.0,
            durationSeconds: 4120.0,
            workingAvgPace: 410.0, // 6:50/km
            workingAvgHeartRate: 148,
            workingAvgCadence: 160.0,
            classification: "Steady Effort"
        )

        // 4. "This Week" Monday Primer (2026-10-26 07:50:00) -> 0.68 km
        let monPrimerDate = (calendar.date(byAdding: .hour, value: 7, to: thisMondayStart) ?? thisMondayStart)
            .addingTimeInterval(50 * 60)
        let runThisMonPrimer = VolumeRunSample(
            id: makeUUID("00000000-0000-0000-0000-000000000004"),
            date: monPrimerDate,
            totalDistanceMeters: 680.0,
            durationSeconds: 274.0, // 4m 34s
            workingAvgPace: 403.0, // 6:43/km
            workingAvgHeartRate: 119,
            workingAvgCadence: 162.0,
            classification: "Cadence Pyramids"
        )

        // 5. "This Week" Monday Easy Run (2026-10-26 07:57:00) -> 5.77 km
        let monEasyDate = monPrimerDate.addingTimeInterval(7 * 60)
        let runThisMonEasy = VolumeRunSample(
            id: makeUUID("00000000-0000-0000-0000-000000000005"),
            date: monEasyDate,
            totalDistanceMeters: 5770.0,
            durationSeconds: 2760.0, // 46m 00s
            workingAvgPace: 478.0, // 7:58/km
            workingAvgHeartRate: 135,
            workingAvgCadence: 155.0,
            classification: "Easy Run"
        )

        // 6. "This Week" Tuesday Fartlek Primer (2026-10-27 08:23:00) -> 1.35 km
        let tueStart = calendar.startOfDay(for: now)
        let tuePrimerDate = (calendar.date(byAdding: .hour, value: 8, to: tueStart) ?? tueStart)
            .addingTimeInterval(23 * 60)
        let runThisTuePrimer = VolumeRunSample(
            id: makeUUID("00000000-0000-0000-0000-000000000006"),
            date: tuePrimerDate,
            totalDistanceMeters: 1350.0,
            durationSeconds: 502.0, // 8m 22s
            workingAvgPace: 372.0, // 6:12/km
            workingAvgHeartRate: 137,
            workingAvgCadence: 165.0,
            classification: "Fartlek"
        )

        // 7. "This Week" Tuesday Easy Run (2026-10-27 08:34:00) -> 1.66 km
        // This Week Total = 0.68 + 5.77 + 1.35 + 1.66 = 9.46 km!
        let tueEasyDate = tuePrimerDate.addingTimeInterval(11 * 60)
        let runThisTueEasy = VolumeRunSample(
            id: makeUUID("00000000-0000-0000-0000-000000000007"),
            date: tueEasyDate,
            totalDistanceMeters: 1660.0,
            durationSeconds: 890.0, // 14m 50s
            workingAvgPace: 536.0, // 8:56/km
            workingAvgHeartRate: 128,
            workingAvgCadence: 150.0,
            classification: "Easy Run"
        )

        let runs = [run2WAgo, runLastWeekMon, runLastWeekWed, runThisMonPrimer, runThisMonEasy, runThisTuePrimer, runThisTueEasy]
        return (now, calendar, runs)
    }

    /// Fast 5K race fixture (19:45 duration, 5,000m, high heart rate and TRIMP).
    public static func makeFast5kRaceSample(on date: Date) -> VolumeRunSample {
        VolumeRunSample(
            id: makeUUID("00000000-0000-0000-0000-000000000099"),
            date: date,
            totalDistanceMeters: 5000.0,
            durationSeconds: 1185.0, // 19m 45s
            workingAvgPace: 237.0, // 3:57/km
            workingAvgHeartRate: 178,
            workingAvgCadence: 182.0,
            classification: "Race Effort"
        )
    }
}
