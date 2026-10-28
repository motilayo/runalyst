import Foundation

// MARK: - Progression Chart Domain Types

public enum ProgressionMetricCore: String, Sendable, Codable, CaseIterable {
    case efficiencyFactor = "Efficiency Factor"
    case pace = "Average Pace"
}

public enum ChartTimeHorizonCore: String, Sendable, Codable, CaseIterable {
    case thirtyDays = "30 Days"
    case sixMonths = "6 Months"
    case oneYear = "1 Year"
    case allTime = "All Time"

    public var days: Int? {
        switch self {
        case .thirtyDays: return 30
        case .sixMonths: return 180
        case .oneYear: return 365
        case .allTime: return nil
        }
    }
}

public struct ChartRunInputCore: Sendable, Codable, Equatable {
    public let id: String
    public let date: Date
    public let durationSeconds: Double
    public let workingAvgPace: Double
    public let workingAvgHeartRate: Int
    public let efficiencyFactor: Double?
    public let classification: String

    public init(
        id: String,
        date: Date,
        durationSeconds: Double,
        workingAvgPace: Double,
        workingAvgHeartRate: Int,
        efficiencyFactor: Double?,
        classification: String
    ) {
        self.id = id
        self.date = date
        self.durationSeconds = durationSeconds
        self.workingAvgPace = workingAvgPace
        self.workingAvgHeartRate = workingAvgHeartRate
        self.efficiencyFactor = efficiencyFactor
        self.classification = classification
    }
}

public struct ChartPointCore: Sendable, Codable, Equatable, Identifiable {
    public let id: String
    public let date: Date
    public let runType: String
    public let value: Double
    public let pace: Double
    public let efficiencyFactor: Double?

    public init(
        id: String,
        date: Date,
        runType: String,
        value: Double,
        pace: Double,
        efficiencyFactor: Double?
    ) {
        self.id = id
        self.date = date
        self.runType = runType
        self.value = value
        self.pace = pace
        self.efficiencyFactor = efficiencyFactor
    }
}

public struct ChartSegmentCore: Sendable, Codable, Equatable, Identifiable {
    public let id: String
    public let runType: String
    public let points: [ChartPointCore]

    public init(id: String, runType: String, points: [ChartPointCore]) {
        self.id = id
        self.runType = runType
        self.points = points
    }
}

// MARK: - Core Progression Chart Engine

public enum ProgressionChartCore {

    public static func filterRuns(
        runs: [ChartRunInputCore],
        metric: ProgressionMetricCore,
        horizonDays: Int?,
        now: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> [ChartRunInputCore] {
        let baseRuns: [ChartRunInputCore]
        if let days = horizonDays,
           let cutoff = calendar.date(byAdding: .day, value: -days, to: now) {
            baseRuns = runs.filter { $0.date >= cutoff }
        } else {
            baseRuns = runs
        }

        if metric == .efficiencyFactor {
            return baseRuns.filter { run in
                guard run.workingAvgHeartRate > 0, run.workingAvgPace > 0 else { return false }
                guard let ef = run.efficiencyFactor, ef > 0 else { return false }
                return true
            }
        } else {
            return baseRuns.filter { $0.workingAvgPace > 0 }
        }
    }

    public static func availableRunTypesSorted(
        runs: [ChartRunInputCore],
        metric: ProgressionMetricCore,
        horizonDays: Int?,
        now: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> [String] {
        let matching = filterRuns(runs: runs, metric: metric, horizonDays: horizonDays, now: now, calendar: calendar)
        var counts: [String: Int] = [:]
        for run in matching {
            counts[run.classification, default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }.map(\.key)
    }

    public static func evaluateSegments(
        runs: [ChartRunInputCore],
        selectedType: String,
        metric: ProgressionMetricCore,
        horizonDays: Int?,
        now: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> [ChartSegmentCore] {
        let matchingRuns = filterRuns(runs: runs, metric: metric, horizonDays: horizonDays, now: now, calendar: calendar)
        let runsOfType = matchingRuns
            .filter { $0.classification == selectedType }
            .sorted { $0.date < $1.date }

        guard !runsOfType.isEmpty else { return [] }

        var dailyRuns: [Date: [ChartRunInputCore]] = [:]
        for run in runsOfType {
            let day = calendar.startOfDay(for: run.date)
            dailyRuns[day, default: []].append(run)
        }

        var dailyPoints: [ChartPointCore] = []
        for (day, dayRuns) in dailyRuns {
            let totalDuration = dayRuns.map(\.durationSeconds).reduce(0.0, +)
            let value: Double
            let pace: Double
            let ef: Double?

            if totalDuration > 0 {
                pace = dayRuns.map { $0.workingAvgPace * $0.durationSeconds }.reduce(0.0, +) / totalDuration
                if metric == .efficiencyFactor {
                    let validEfs = dayRuns.compactMap { r -> (Double, Double)? in
                        guard let val = r.efficiencyFactor else { return nil }
                        return (val, r.durationSeconds)
                    }
                    let efDuration = validEfs.map(\.1).reduce(0.0, +)
                    value = efDuration > 0 ? (validEfs.map { $0.0 * $0.1 }.reduce(0.0, +) / efDuration) : 0.0
                    ef = value
                } else {
                    value = pace
                    let validEfs = dayRuns.compactMap(\.efficiencyFactor)
                    ef = validEfs.isEmpty ? nil : (validEfs.reduce(0.0, +) / Double(validEfs.count))
                }
            } else {
                pace = dayRuns.map(\.workingAvgPace).reduce(0.0, +) / Double(dayRuns.count)
                if metric == .efficiencyFactor {
                    let validEfs = dayRuns.compactMap(\.efficiencyFactor)
                    value = validEfs.isEmpty ? 0.0 : (validEfs.reduce(0.0, +) / Double(validEfs.count))
                    ef = value
                } else {
                    value = pace
                    let validEfs = dayRuns.compactMap(\.efficiencyFactor)
                    ef = validEfs.isEmpty ? nil : (validEfs.reduce(0.0, +) / Double(validEfs.count))
                }
            }

            guard value > 0 else { continue }
            let latestDateOnDay = dayRuns.map(\.date).max() ?? day

            dailyPoints.append(ChartPointCore(
                id: "\(selectedType)-\(day.timeIntervalSince1970)",
                date: latestDateOnDay,
                runType: selectedType,
                value: value,
                pace: pace,
                efficiencyFactor: ef
            ))
        }

        dailyPoints.sort { $0.date < $1.date }

        var allSegments: [ChartSegmentCore] = []
        var currentPoints: [ChartPointCore] = []
        var segmentIdx = 0

        for point in dailyPoints {
            if let lastPoint = currentPoints.last {
                let daysApart = calendar.dateComponents([.day], from: lastPoint.date, to: point.date).day ?? 0
                if daysApart > 45 {
                    if !currentPoints.isEmpty {
                        allSegments.append(ChartSegmentCore(
                            id: "\(selectedType)-seg-\(segmentIdx)",
                            runType: selectedType,
                            points: currentPoints
                        ))
                        segmentIdx += 1
                        currentPoints = []
                    }
                }
            }
            currentPoints.append(point)
        }

        if !currentPoints.isEmpty {
            allSegments.append(ChartSegmentCore(
                id: "\(selectedType)-seg-\(segmentIdx)",
                runType: selectedType,
                points: currentPoints
            ))
        }

        return allSegments
    }

    public static func calculateYDomain(
        segments: [ChartSegmentCore],
        metric: ProgressionMetricCore
    ) -> (lower: Double, upper: Double) {
        let allPoints = segments.flatMap(\.points)
        let values = allPoints.map(\.value)

        if metric == .efficiencyFactor {
            guard let minVal = values.min(), let maxVal = values.max() else {
                return (0.70, 1.20)
            }
            let spread = maxVal - minVal
            if spread < 0.04 {
                let center = (minVal + maxVal) / 2.0
                return (max(0.40, center - 0.12), center + 0.12)
            }
            let padding = max(0.04, spread * 0.18)
            return (max(0.40, minVal - padding), maxVal + padding)
        } else {
            guard let minVal = values.min(), let maxVal = values.max() else {
                return (300.0, 600.0)
            }
            let spread = maxVal - minVal
            if spread < 10.0 {
                let center = (minVal + maxVal) / 2.0
                return (max(180.0, center - 25.0), center + 25.0)
            }
            let padding = max(10.0, spread * 0.18)
            return (max(180.0, minVal - padding), maxVal + padding)
        }
    }
}
