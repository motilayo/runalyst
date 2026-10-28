import Foundation

/// Pure deterministic temporal snapshot engine.
///
/// Governed by CONSTITUTION.md:
/// 1. Sans-I/O Air-Gap: Pure Foundation only. Zero dynamic wall-clock instantiation, zero system Calendar.
/// 2. Half-Open Interval Math: W_current = [T_Monday_Start, T_Next_Monday_Start).
/// 3. Invariant 1 (Conservation of Distance): Sum of workouts strictly equals window volume.
/// 4. Invariant 2 (Calendar Disjointness): Calendar weeks are strictly non-overlapping.
/// 5. Invariant 3 (Dimensional Pace): Total duration divided by total distance (seconds/km).
/// 6. Invariant 4 (Duration-Weighted Kinematics): Sum(metric * duration) / Sum(duration).
public struct CalendarWeekSlice: Sendable, Codable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let startEpoch: TimeInterval
    public let endEpoch: TimeInterval
    public let totalDistanceMeters: Double
    public let totalDurationSeconds: Double
    public let workoutCount: Int
    public let activeDaysCount: Int
    public let dimensionalPaceSecPerKm: Double?
    public let durationWeightedCadence: Double?
    public let durationWeightedHeartRate: Double?
    public let classificationBreakdown: [String: Int]

    public var totalDistanceKm: Double {
        totalDistanceMeters / 1000.0
    }

    public init(
        id: String,
        label: String,
        startEpoch: TimeInterval,
        endEpoch: TimeInterval,
        totalDistanceMeters: Double,
        totalDurationSeconds: Double,
        workoutCount: Int,
        activeDaysCount: Int = 0,
        dimensionalPaceSecPerKm: Double?,
        durationWeightedCadence: Double?,
        durationWeightedHeartRate: Double?,
        classificationBreakdown: [String: Int]
    ) {
        self.id = id
        self.label = label
        self.startEpoch = startEpoch
        self.endEpoch = endEpoch
        self.totalDistanceMeters = totalDistanceMeters
        self.totalDurationSeconds = totalDurationSeconds
        self.workoutCount = workoutCount
        self.activeDaysCount = activeDaysCount
        self.dimensionalPaceSecPerKm = dimensionalPaceSecPerKm
        self.durationWeightedCadence = durationWeightedCadence
        self.durationWeightedHeartRate = durationWeightedHeartRate
        self.classificationBreakdown = classificationBreakdown
    }

    public static func zero(id: String, label: String, startEpoch: TimeInterval, endEpoch: TimeInterval) -> CalendarWeekSlice {
        CalendarWeekSlice(
            id: id,
            label: label,
            startEpoch: startEpoch,
            endEpoch: endEpoch,
            totalDistanceMeters: 0,
            totalDurationSeconds: 0,
            workoutCount: 0,
            activeDaysCount: 0,
            dimensionalPaceSecPerKm: nil,
            durationWeightedCadence: nil,
            durationWeightedHeartRate: nil,
            classificationBreakdown: [:]
        )
    }
}

public struct RollingWindowSlice: Sendable, Codable, Equatable {
    public let windowDays: Int
    public let startEpoch: TimeInterval
    public let endEpoch: TimeInterval
    public let totalDistanceMeters: Double
    public let totalDurationSeconds: Double
    public let workoutCount: Int
    public let activeDaysCount: Int
    public let dimensionalPaceSecPerKm: Double?
    public let durationWeightedCadence: Double?
    public let durationWeightedHeartRate: Double?

    public var totalDistanceKm: Double {
        totalDistanceMeters / 1000.0
    }

    public init(
        windowDays: Int,
        startEpoch: TimeInterval,
        endEpoch: TimeInterval,
        totalDistanceMeters: Double,
        totalDurationSeconds: Double,
        workoutCount: Int,
        activeDaysCount: Int,
        dimensionalPaceSecPerKm: Double?,
        durationWeightedCadence: Double?,
        durationWeightedHeartRate: Double?
    ) {
        self.windowDays = windowDays
        self.startEpoch = startEpoch
        self.endEpoch = endEpoch
        self.totalDistanceMeters = totalDistanceMeters
        self.totalDurationSeconds = totalDurationSeconds
        self.workoutCount = workoutCount
        self.activeDaysCount = activeDaysCount
        self.dimensionalPaceSecPerKm = dimensionalPaceSecPerKm
        self.durationWeightedCadence = durationWeightedCadence
        self.durationWeightedHeartRate = durationWeightedHeartRate
    }
}

public struct TemporalSnapshotReport: Sendable, Codable, Equatable {
    public let thisWeek: CalendarWeekSlice
    public let lastWeek: CalendarWeekSlice
    public let twoWeeksAgo: CalendarWeekSlice
    public let threeWeeksAgo: CalendarWeekSlice
    public let calendarWeeks: [CalendarWeekSlice]
    public let trailing7Days: RollingWindowSlice
    public let trailing28Days: RollingWindowSlice
    public let trailing30Days: RollingWindowSlice
    public let activeDaysCount30d: Int
    public let weeklyAverageKm30d: Double
    public let runsPerWeek30d: Double
    public let workoutDensityTier: String

    public init(
        thisWeek: CalendarWeekSlice,
        lastWeek: CalendarWeekSlice,
        twoWeeksAgo: CalendarWeekSlice,
        threeWeeksAgo: CalendarWeekSlice,
        calendarWeeks: [CalendarWeekSlice],
        trailing7Days: RollingWindowSlice,
        trailing28Days: RollingWindowSlice,
        trailing30Days: RollingWindowSlice,
        activeDaysCount30d: Int,
        weeklyAverageKm30d: Double,
        runsPerWeek30d: Double,
        workoutDensityTier: String
    ) {
        self.thisWeek = thisWeek
        self.lastWeek = lastWeek
        self.twoWeeksAgo = twoWeeksAgo
        self.threeWeeksAgo = threeWeeksAgo
        self.calendarWeeks = calendarWeeks
        self.trailing7Days = trailing7Days
        self.trailing28Days = trailing28Days
        self.trailing30Days = trailing30Days
        self.activeDaysCount30d = activeDaysCount30d
        self.weeklyAverageKm30d = weeklyAverageKm30d
        self.runsPerWeek30d = runsPerWeek30d
        self.workoutDensityTier = workoutDensityTier
    }
}

public enum TemporalSnapshotCore {

    /// Anthropometric cadence floor calculation based on athlete height and workout intensity.
    /// Formula from CONSTITUTION.md: C_floor(H, Pace) = C_base(H) + Delta_C(Pace).
    public static func anthropometricCadenceFloor(heightCm: Double, paceCategory: String = "easy") -> Int {
        let base: Int
        if heightCm < 163.0 {
            base = 175
        } else if heightCm <= 173.0 {
            base = 170
        } else if heightCm <= 183.0 {
            base = 165
        } else {
            base = 160
        }

        let delta: Int
        let normalized = paceCategory.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("interval") || normalized.contains("5k") || normalized.contains("stride") {
            delta = 20
        } else if normalized.contains("tempo") || normalized.contains("threshold") || normalized.contains("steady") {
            delta = 10
        } else {
            delta = 0
        }

        return base + delta
    }

    /// Evaluates temporal snapshot reports from workout samples across discrete calendar weeks and rolling horizons.
    /// Purity rule: All times are derived from injected `now` and `calendar`.
    public static func evaluateSnapshot(
        runs: [VolumeRunSample],
        now: Date,
        calendar: Calendar
    ) -> TemporalSnapshotReport {
        let todayStart = calendar.startOfDay(for: now)

        // 1. Calculate the start of the current calendar week (Monday 00:00:00 default)
        // firstWeekday: 1 = Sunday, 2 = Monday
        let targetWeekday = calendar.firstWeekday
        let currentWeekday = calendar.component(.weekday, from: todayStart)
        let daysToSubtract = (currentWeekday - targetWeekday + 7) % 7
        let thisWeekStart = calendar.date(byAdding: .day, value: -daysToSubtract, to: todayStart) ?? todayStart

        // Discrete week anchors: half-open [W_start, W_next_start)
        let nextWeekStart = calendar.date(byAdding: .day, value: 7, to: thisWeekStart) ?? thisWeekStart
        let lastWeekStart = calendar.date(byAdding: .day, value: -7, to: thisWeekStart) ?? thisWeekStart
        let twoWeeksAgoStart = calendar.date(byAdding: .day, value: -14, to: thisWeekStart) ?? thisWeekStart
        let threeWeeksAgoStart = calendar.date(byAdding: .day, value: -21, to: thisWeekStart) ?? thisWeekStart

        // Discrete Calendar Weeks
        let w0Slice = buildWeekSlice(
            id: "w0",
            label: "This Wk",
            runs: runs,
            start: thisWeekStart,
            end: nextWeekStart,
            calendar: calendar
        )
        let w1Slice = buildWeekSlice(
            id: "w1",
            label: "Last Wk",
            runs: runs,
            start: lastWeekStart,
            end: thisWeekStart,
            calendar: calendar
        )
        let w2Slice = buildWeekSlice(
            id: "w2",
            label: "2W Ago",
            runs: runs,
            start: twoWeeksAgoStart,
            end: lastWeekStart,
            calendar: calendar
        )
        let w3Slice = buildWeekSlice(
            id: "w3",
            label: "3W Ago",
            runs: runs,
            start: threeWeeksAgoStart,
            end: twoWeeksAgoStart,
            calendar: calendar
        )
        let calendarWeeks = [w0Slice, w1Slice, w2Slice, w3Slice]

        // Rolling Horizon Windows (distinct from calendar weeks)
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now.addingTimeInterval(-7 * 86400)
        let twentyEightDaysAgo = calendar.date(byAdding: .day, value: -28, to: now) ?? now.addingTimeInterval(-28 * 86400)
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) ?? now.addingTimeInterval(-30 * 86400)

        let rolling7d = buildRollingSlice(windowDays: 7, runs: runs, start: sevenDaysAgo, end: now, calendar: calendar)
        let rolling28d = buildRollingSlice(windowDays: 28, runs: runs, start: twentyEightDaysAgo, end: now, calendar: calendar)
        let rolling30d = buildRollingSlice(windowDays: 30, runs: runs, start: thirtyDaysAgo, end: now, calendar: calendar)

        // 30-Day Density & Averages
        let weeksIn30d = 30.0 / 7.0
        let weeklyAvgKm30d = rolling30d.totalDistanceKm / weeksIn30d
        let runsPerWeek30d = Double(rolling30d.activeDaysCount) / weeksIn30d

        let densityTier: String
        if rolling30d.workoutCount >= 18 {
            densityTier = "Optimal"
        } else if rolling30d.workoutCount >= 10 {
            densityTier = "Moderate"
        } else {
            densityTier = "Building"
        }

        return TemporalSnapshotReport(
            thisWeek: w0Slice,
            lastWeek: w1Slice,
            twoWeeksAgo: w2Slice,
            threeWeeksAgo: w3Slice,
            calendarWeeks: calendarWeeks,
            trailing7Days: rolling7d,
            trailing28Days: rolling28d,
            trailing30Days: rolling30d,
            activeDaysCount30d: rolling30d.activeDaysCount,
            weeklyAverageKm30d: weeklyAvgKm30d,
            runsPerWeek30d: runsPerWeek30d,
            workoutDensityTier: densityTier
        )
    }

    // MARK: - Private Aggregators

    private static func buildWeekSlice(
        id: String,
        label: String,
        runs: [VolumeRunSample],
        start: Date,
        end: Date,
        calendar: Calendar
    ) -> CalendarWeekSlice {
        let matching = runs.filter { $0.date >= start && $0.date < end }
        let totalDist = matching.reduce(0.0) { $0 + $1.totalDistanceMeters }
        let totalDuration = matching.reduce(0.0) { $0 + $1.durationSeconds }
        let uniqueDays = Set(matching.map { calendar.startOfDay(for: $0.date) })
        let activeDays = uniqueDays.count

        // Dimensional Average Pace: Duration / Distance
        let pace: Double? = (totalDist > 0 && totalDuration > 0)
            ? (totalDuration / (totalDist / 1000.0))
            : nil

        // Duration-Weighted Cadence
        let weightedCadence: Double? = (totalDuration > 0)
            ? (matching.reduce(0.0) { $0 + ($1.workingAvgCadence * $1.durationSeconds) } / totalDuration)
            : nil

        // Duration-Weighted Heart Rate
        let weightedHR: Double? = (totalDuration > 0)
            ? (matching.reduce(0.0) { $0 + (Double($1.workingAvgHeartRate) * $1.durationSeconds) } / totalDuration)
            : nil

        var breakdown: [String: Int] = [:]
        for run in matching {
            breakdown[run.classification, default: 0] += 1
        }

        return CalendarWeekSlice(
            id: id,
            label: label,
            startEpoch: start.timeIntervalSince1970,
            endEpoch: end.timeIntervalSince1970,
            totalDistanceMeters: totalDist,
            totalDurationSeconds: totalDuration,
            workoutCount: matching.count,
            activeDaysCount: activeDays,
            dimensionalPaceSecPerKm: pace,
            durationWeightedCadence: weightedCadence,
            durationWeightedHeartRate: weightedHR,
            classificationBreakdown: breakdown
        )
    }

    private static func buildRollingSlice(
        windowDays: Int,
        runs: [VolumeRunSample],
        start: Date,
        end: Date,
        calendar: Calendar
    ) -> RollingWindowSlice {
        let matching = runs.filter { $0.date >= start && $0.date <= end }
        let totalDist = matching.reduce(0.0) { $0 + $1.totalDistanceMeters }
        let totalDuration = matching.reduce(0.0) { $0 + $1.durationSeconds }

        let pace: Double? = (totalDist > 0 && totalDuration > 0)
            ? (totalDuration / (totalDist / 1000.0))
            : nil

        let weightedCadence: Double? = (totalDuration > 0)
            ? (matching.reduce(0.0) { $0 + ($1.workingAvgCadence * $1.durationSeconds) } / totalDuration)
            : nil

        let weightedHR: Double? = (totalDuration > 0)
            ? (matching.reduce(0.0) { $0 + (Double($1.workingAvgHeartRate) * $1.durationSeconds) } / totalDuration)
            : nil

        let uniqueDays = Set(matching.map { calendar.startOfDay(for: $0.date) })

        return RollingWindowSlice(
            windowDays: windowDays,
            startEpoch: start.timeIntervalSince1970,
            endEpoch: end.timeIntervalSince1970,
            totalDistanceMeters: totalDist,
            totalDurationSeconds: totalDuration,
            workoutCount: matching.count,
            activeDaysCount: uniqueDays.count,
            dimensionalPaceSecPerKm: pace,
            durationWeightedCadence: weightedCadence,
            durationWeightedHeartRate: weightedHR
        )
    }
}
