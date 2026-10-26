import Foundation

// MARK: - Query Sort & Filter Specifications

public enum HistoricalSortMetricCore: String, Sendable, Codable, Equatable {
    case date
    case distance
    case duration
    case pace
    case cadence
    case heartRate
    case efficiencyFactor
}

public enum HistoricalSortDirectionCore: String, Sendable, Codable, Equatable {
    case ascending
    case descending
}

public enum HistoricalEnvironmentFilterCore: String, Sendable, Codable, Equatable {
    case all
    case outdoor
    case indoor
}

public struct HistoricalQueryCriteriaCore: Sendable, Equatable {
    public var metric: HistoricalSortMetricCore = .date
    public var direction: HistoricalSortDirectionCore = .descending
    public var environment: HistoricalEnvironmentFilterCore = .all
    public var modality: String?
    public var targetYear: Int?
    public var targetMonth: Int?
    public var targetDay: Int?
    public var limit: Int = 1
    public var requiresPriorToCurrentRun: Bool = false

    public init(
        metric: HistoricalSortMetricCore = .date,
        direction: HistoricalSortDirectionCore = .descending,
        environment: HistoricalEnvironmentFilterCore = .all,
        modality: String? = nil,
        targetYear: Int? = nil,
        targetMonth: Int? = nil,
        targetDay: Int? = nil,
        limit: Int = 1,
        requiresPriorToCurrentRun: Bool = false
    ) {
        self.metric = metric
        self.direction = direction
        self.environment = environment
        self.modality = modality
        self.targetYear = targetYear
        self.targetMonth = targetMonth
        self.targetDay = targetDay
        self.limit = limit
        self.requiresPriorToCurrentRun = requiresPriorToCurrentRun
    }

    public static func parse(from query: String, currentRunIsIndoor: Bool? = nil, referenceDate: Date? = nil) -> HistoricalQueryCriteriaCore {
        let lower = query.lowercased()
        var criteria = HistoricalQueryCriteriaCore()

        let mentionsOutdoor = lower.contains("outdoor") || lower.contains("outside") || lower.contains("road") || lower.contains("trail")
        let mentionsIndoor = lower.contains("indoor") || lower.contains("treadmill")

        if mentionsOutdoor && !mentionsIndoor {
            criteria.environment = .outdoor
        } else if mentionsIndoor && !mentionsOutdoor {
            criteria.environment = .indoor
        } else if mentionsOutdoor && mentionsIndoor {
            if let isIndoor = currentRunIsIndoor {
                criteria.environment = isIndoor ? .outdoor : .indoor
            } else {
                criteria.environment = .outdoor
            }
        }

        let isChronologicalOldest = lower.contains("oldest") || lower.contains("first") || lower.contains("earliest") || lower.contains("initial") || lower.contains("beginning")
        let isFastestOrBest = lower.contains("fastest") || lower.contains("best") || lower.contains("peak efficiency") || lower.contains("highest efficiency")
        let isSlowestOrWorst = lower.contains("slowest") || lower.contains("worst") || lower.contains("toughest") || lower.contains("lowest efficiency")

        if isChronologicalOldest {
            criteria.metric = .date
            criteria.direction = .ascending
        } else if lower.contains("longest") {
            criteria.metric = .distance
            criteria.direction = .descending
        } else if lower.contains("shortest") {
            criteria.metric = .distance
            criteria.direction = .ascending
        } else if isFastestOrBest {
            criteria.metric = .efficiencyFactor
            criteria.direction = .descending
        } else if isSlowestOrWorst {
            criteria.metric = .efficiencyFactor
            criteria.direction = .ascending
        } else if lower.contains("highest hr") || lower.contains("highest heart rate") || lower.contains("max hr") {
            criteria.metric = .heartRate
            criteria.direction = .descending
        } else if lower.contains("lowest hr") || lower.contains("lowest heart rate") {
            criteria.metric = .heartRate
            criteria.direction = .ascending
        } else {
            criteria.metric = .date
            criteria.direction = .descending
        }

        let mentionsPriorExplicitly = lower.contains("previous") || lower.contains("prior") || lower.contains("before this") || (lower.contains("last run") && !lower.contains("first"))
        criteria.requiresPriorToCurrentRun = mentionsPriorExplicitly

        if let yearRegex = try? NSRegularExpression(pattern: #"\b(20\d{2})\b"#) {
            let nsRange = NSRange(lower.startIndex..<lower.endIndex, in: lower)
            if let match = yearRegex.firstMatch(in: lower, range: nsRange),
               let r = Range(match.range(at: 1), in: lower),
               let y = Int(lower[r]) {
                criteria.targetYear = y
            }
        }

        let months: [(name: String, number: Int)] = [
            ("january", 1), ("jan", 1),
            ("february", 2), ("feb", 2),
            ("march", 3), ("mar", 3),
            ("april", 4), ("apr", 4),
            ("may", 5),
            ("june", 6), ("jun", 6),
            ("july", 7), ("jul", 7),
            ("august", 8), ("aug", 8),
            ("september", 9), ("sept", 9), ("sep", 9),
            ("october", 10), ("oct", 10),
            ("november", 11), ("nov", 11),
            ("december", 12), ("dec", 12)
        ]
        for m in months where lower.contains(m.name) {
            criteria.targetMonth = m.number
            break
        }

        if let dayRegex = try? NSRegularExpression(pattern: #"\b(\d{1,2})(?:st|nd|rd|th)?\b"#) {
            let nsRange = NSRange(lower.startIndex..<lower.endIndex, in: lower)
            let matches = dayRegex.matches(in: lower, range: nsRange)
            for match in matches {
                if let dayRange = Range(match.range(at: 1), in: lower),
                   let dayVal = Int(lower[dayRange]), dayVal >= 1 && dayVal <= 31,
                   dayVal != criteria.targetYear {
                    criteria.targetDay = dayVal
                    break
                }
            }
        }

        if criteria.targetMonth == nil || criteria.targetDay == nil {
            if let slashRegex = try? NSRegularExpression(pattern: #"\b(\d{1,2})/(\d{1,2})\b"#) {
                let nsRange = NSRange(lower.startIndex..<lower.endIndex, in: lower)
                if let match = slashRegex.firstMatch(in: lower, range: nsRange),
                   let mRange = Range(match.range(at: 1), in: lower),
                   let dRange = Range(match.range(at: 2), in: lower),
                   let mVal = Int(lower[mRange]), let dVal = Int(lower[dRange]),
                   mVal >= 1 && mVal <= 12, dVal >= 1 && dVal <= 31 {
                    criteria.targetMonth = mVal
                    criteria.targetDay = dVal
                }
            }
        }

        if lower.contains("yesterday") {
            let base = referenceDate ?? Date()
            let yesterday = base.addingTimeInterval(-86400)
            let comps = Calendar.current.dateComponents([.year, .month, .day], from: yesterday)
            criteria.targetYear = comps.year
            criteria.targetMonth = comps.month
            criteria.targetDay = comps.day
        }

        let modalities = ["intervals", "tempo", "steady", "progression", "recovery", "fartlek", "long run", "pyramids", "hill repeats"]
        for mod in modalities where lower.contains(mod) {
            criteria.modality = mod
            break
        }

        return criteria
    }
}

// MARK: - Candidate Sample Core

public struct HistoricalCandidateSampleCore: Sendable, Equatable {
    public let id: UUID
    public let date: Date
    public let durationSeconds: Double
    public let distanceMeters: Double
    public let paceSecondsPerKm: Double
    public let cadenceSPM: Double
    public let heartRateBPM: Double
    public let isIndoor: Bool
    public let efficiencyFactor: Double?
    public let classification: String
    public let detectedTypeRaw: String
    public let isPrimerWorkout: Bool

    public var computedEfficiencyScore: Double {
        if let ef = efficiencyFactor, ef > 0 { return ef }
        guard paceSecondsPerKm > 0, heartRateBPM > 0 else { return 0.0 }
        return (60_000.0 / paceSecondsPerKm) / heartRateBPM
    }

    public init(
        id: UUID,
        date: Date,
        durationSeconds: Double,
        distanceMeters: Double,
        paceSecondsPerKm: Double,
        cadenceSPM: Double,
        heartRateBPM: Double,
        isIndoor: Bool,
        efficiencyFactor: Double? = nil,
        classification: String = "",
        detectedTypeRaw: String = "",
        isPrimerWorkout: Bool = false
    ) {
        self.id = id
        self.date = date
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.paceSecondsPerKm = paceSecondsPerKm
        self.cadenceSPM = cadenceSPM
        self.heartRateBPM = heartRateBPM
        self.isIndoor = isIndoor
        self.efficiencyFactor = efficiencyFactor
        self.classification = classification
        self.detectedTypeRaw = detectedTypeRaw
        self.isPrimerWorkout = isPrimerWorkout
    }
}

// MARK: - Historical Query Core

public enum HistoricalQueryCore {

    public static func filterAndSort(
        candidates: [HistoricalCandidateSampleCore],
        criteria: HistoricalQueryCriteriaCore,
        referenceDate: Date? = nil
    ) -> [HistoricalCandidateSampleCore] {
        guard !candidates.isEmpty else { return [] }
        var working = candidates

        if criteria.requiresPriorToCurrentRun, let refDate = referenceDate {
            let priorOnly = working.filter { $0.date < refDate }
            if !priorOnly.isEmpty {
                working = priorOnly
            }
        }

        switch criteria.environment {
        case .outdoor:
            working = working.filter { !$0.isIndoor }
        case .indoor:
            working = working.filter { $0.isIndoor }
        case .all:
            break
        }

        if criteria.targetYear != nil || criteria.targetMonth != nil || criteria.targetDay != nil {
            let calendar = Calendar.current
            working = working.filter { run in
                let comps = calendar.dateComponents([.year, .month, .day], from: run.date)
                if let y = criteria.targetYear, comps.year != y { return false }
                if let m = criteria.targetMonth, comps.month != m { return false }
                if let d = criteria.targetDay, comps.day != d { return false }
                return true
            }
        }

        if let mod = criteria.modality {
            let filteredByMod = working.filter {
                $0.detectedTypeRaw.localizedCaseInsensitiveContains(mod) ||
                $0.classification.localizedCaseInsensitiveContains(mod)
            }
            if !filteredByMod.isEmpty {
                working = filteredByMod
            }
        }

        guard !working.isEmpty else { return [] }

        if criteria.metric == .efficiencyFactor || criteria.metric == .pace {
            let meaningful = working.filter { $0.distanceMeters >= 500 && $0.durationSeconds >= 180 }
            if !meaningful.isEmpty {
                working = meaningful
            }
        }

        let sorted = working.sorted { r1, r2 in
            switch criteria.metric {
            case .date:
                return criteria.direction == .ascending ? r1.date < r2.date : r1.date > r2.date
            case .distance:
                return criteria.direction == .ascending ? r1.distanceMeters < r2.distanceMeters : r1.distanceMeters > r2.distanceMeters
            case .duration:
                return criteria.direction == .ascending ? r1.durationSeconds < r2.durationSeconds : r1.durationSeconds > r2.durationSeconds
            case .pace:
                return criteria.direction == .ascending ? r1.paceSecondsPerKm < r2.paceSecondsPerKm : r1.paceSecondsPerKm > r2.paceSecondsPerKm
            case .cadence:
                return criteria.direction == .ascending ? r1.cadenceSPM < r2.cadenceSPM : r1.cadenceSPM > r2.cadenceSPM
            case .heartRate:
                return criteria.direction == .ascending ? r1.heartRateBPM < r2.heartRateBPM : r1.heartRateBPM > r2.heartRateBPM
            case .efficiencyFactor:
                let ef1 = r1.computedEfficiencyScore
                let ef2 = r2.computedEfficiencyScore
                if abs(ef1 - ef2) > 0.001 {
                    return criteria.direction == .ascending ? ef1 < ef2 : ef1 > ef2
                }
                return criteria.direction == .ascending ? r1.paceSecondsPerKm > r2.paceSecondsPerKm : r1.paceSecondsPerKm < r2.paceSecondsPerKm
            }
        }

        return sorted
    }

    public static func parseComparisonTargets(from query: String) -> (targetA: String, targetB: String)? {
        let lower = query.lowercased()

        let mentionsOutdoor = lower.contains("outdoor") || lower.contains("outside") || lower.contains("road")
        let mentionsIndoor = lower.contains("indoor") || lower.contains("treadmill")

        if mentionsOutdoor && mentionsIndoor {
            let outRange = lower.range(of: "outdoor") ?? lower.range(of: "outside") ?? lower.range(of: "road")
            let inRange = lower.range(of: "indoor") ?? lower.range(of: "treadmill")
            if let oR = outRange, let iR = inRange {
                if oR.lowerBound < iR.lowerBound {
                    return (targetA: "outdoor", targetB: "indoor")
                } else {
                    return (targetA: "indoor", targetB: "outdoor")
                }
            }
        }

        let splitters = [" vs ", " vs. ", " versus ", " compared to ", " to "]
        for split in splitters {
            if let range = lower.range(of: split) {
                var first = String(query[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let second = String(query[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)

                for prefix in ["compare my ", "compare ", "what is the difference between ", "what's the difference between "]
                    where first.lowercased().hasPrefix(prefix) {
                    first = String(first.dropFirst(prefix.count))
                }
                if !first.isEmpty && !second.isEmpty && second.count >= 3 {
                    return (targetA: first, targetB: second)
                }
            }
        }

        return nil
    }

    public static func computeDeltas(
        current: HistoricalCandidateSampleCore,
        prior: HistoricalCandidateSampleCore
    ) -> (paceDeltaSec: Int, cadDelta: Int, hrDelta: Int, distDelta: Double, durDelta: Double, daysDiff: Int) {
        let paceDeltaSec = Int(prior.paceSecondsPerKm.rounded() - current.paceSecondsPerKm.rounded())
        let cadDelta = Int(round(current.cadenceSPM)) - Int(round(prior.cadenceSPM))
        let hrDelta = Int(round(current.heartRateBPM)) - Int(round(prior.heartRateBPM))
        let distDelta = current.distanceMeters - prior.distanceMeters
        let durDelta = current.durationSeconds - prior.durationSeconds

        let cal = Calendar.current
        let daysDiff = cal.dateComponents([.day], from: cal.startOfDay(for: prior.date), to: cal.startOfDay(for: current.date)).day ?? 0

        return (paceDeltaSec, cadDelta, hrDelta, distDelta, durDelta, daysDiff)
    }
}
