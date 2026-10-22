import Foundation
import SwiftData

enum HistoricalSortMetric: Sendable, Equatable {
    case date
    case distance
    case duration
    case pace
    case cadence
    case heartRate
    case efficiencyFactor
}

enum HistoricalSortDirection: Sendable, Equatable {
    case ascending
    case descending
}

enum HistoricalEnvironmentFilter: Sendable, Equatable {
    case all
    case outdoor
    case indoor
}

struct HistoricalQueryCriteria: Sendable, Equatable {
    typealias SortMetric = HistoricalSortMetric
    typealias Direction = HistoricalSortDirection
    typealias Environment = HistoricalEnvironmentFilter

    var metric: SortMetric = .date
    var direction: Direction = .descending
    var environment: Environment = .all
    var modality: String?
    var targetYear: Int?
    var targetMonth: Int?
    var targetDay: Int?
    var limit: Int = 1
    var requiresPriorToCurrentRun: Bool = false

    init(
        metric: SortMetric = .date,
        direction: Direction = .descending,
        environment: Environment = .all,
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

    static func parse(from query: String, relativeTo currentRun: RunRecord? = nil) -> HistoricalQueryCriteria {
        let lower = query.lowercased()
        var criteria = HistoricalQueryCriteria()

        // 1. Environment extraction
        let mentionsOutdoor = lower.contains("outdoor") || lower.contains("outside") || lower.contains("road") || lower.contains("trail")
        let mentionsIndoor = lower.contains("indoor") || lower.contains("treadmill")

        if mentionsOutdoor && !mentionsIndoor {
            criteria.environment = .outdoor
        } else if mentionsIndoor && !mentionsOutdoor {
            criteria.environment = .indoor
        } else if mentionsOutdoor && mentionsIndoor {
            if let current = currentRun {
                criteria.environment = (current.isIndoor ?? false) ? .outdoor : .indoor
            } else {
                criteria.environment = .outdoor
            }
        }

        // 2. Metric & Direction (Superlatives and Chronological Extremes)
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

        // 3. Date Components (Year, Month, Day)
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
            let yesterday = Date().addingTimeInterval(-86400)
            let comps = Calendar.current.dateComponents([.year, .month, .day], from: yesterday)
            criteria.targetYear = comps.year
            criteria.targetMonth = comps.month
            criteria.targetDay = comps.day
        }

        // 4. Modality
        let modalities = ["intervals", "tempo", "steady", "progression", "recovery", "fartlek", "long run", "pyramids", "hill repeats"]
        for mod in modalities where lower.contains(mod) {
            criteria.modality = mod
            break
        }

        return criteria
    }
}

/// Deterministic matching and mathematical comparison between the active workout and a historical workout.
/// Adheres strictly to the "Thick Client, Thin AI" architectural doctrine:
/// Swift performs the data extraction, date parsing, and delta math;
/// FoundationModels performs the semantic synthesis and conversational coaching.
@MainActor
struct HistoricalRunMatcher {

    struct TelemetryData: Sendable {
        let date: Date
        let formattedDate: String
        let weekday: String
        let classification: String
        let paceSecondsPerKm: Double
        let paceFormatted: String
        let cadenceSPM: Int
        let heartRateBPM: Int
        let distanceMeters: Double
        let durationSeconds: Double
        let isIndoor: Bool
        let efficiencyFactor: Double?
    }

    struct ComparisonTelemetry: Sendable {
        let current: TelemetryData
        let prior: TelemetryData

        // Deterministic deltas computed in Swift
        let paceDeltaSeconds: Int        // prior - current: positive = current is faster
        let cadenceDelta: Int            // current - prior: positive = current is higher
        let heartRateDelta: Int          // current - prior: positive = current is higher
        let distanceDeltaMeters: Double
        let durationDeltaSeconds: Double

        /// Structured mathematical and telemetry facts for FoundationModels tool injection.
        /// Zero canned coaching prose, narrative boilerplate, or simulated conversation.
        var structuredTelemetryFacts: String {
            let envCurrent = current.isIndoor ? "Indoor Treadmill" : "Outdoor"
            let envPrior = prior.isIndoor ? "Indoor Treadmill" : "Outdoor"

            let cal = Calendar.current
            let daysDiff = cal.dateComponents([.day], from: cal.startOfDay(for: prior.date), to: cal.startOfDay(for: current.date)).day ?? 0
            let recencyContrast: String
            if daysDiff > 0 {
                recencyContrast = "\(daysDiff) day\(daysDiff == 1 ? "" : "s") after prior"
            } else if daysDiff < 0 {
                recencyContrast = "\(abs(daysDiff)) day\(abs(daysDiff) == 1 ? "" : "s") before prior"
            } else {
                recencyContrast = "Same day"
            }

            let sameClassification = current.classification.caseInsensitiveCompare(prior.classification) == .orderedSame
            let classificationComparison = sameClassification ? "Matched (\(current.classification))" : "Different (\(current.classification) vs \(prior.classification))"

            // Unit precision with respect to readability: align displayed precision with delta math
            let currentDistKm = Double(String(format: "%.2f", current.distanceMeters / 1000.0)) ?? (current.distanceMeters / 1000.0)
            let priorDistKm = Double(String(format: "%.2f", prior.distanceMeters / 1000.0)) ?? (prior.distanceMeters / 1000.0)
            let distDiffKm = currentDistKm - priorDistKm
            let durDiffMin = Int((current.durationSeconds - prior.durationSeconds) / 60)
            let volumeComparison: String
            if abs(distDiffKm) < 0.2 && abs(durDiffMin) < 3 {
                volumeComparison = "Matched volume: both runs covered comparable distance (~\(String(format: "%.2f", currentDistKm)) km in ~\(Int(current.durationSeconds / 60)) min)."
            } else {
                let distDesc = distDiffKm > 0 ? "+\(String(format: "%.2f", distDiffKm)) km longer" : "\(String(format: "%.2f", abs(distDiffKm))) km shorter"
                let durDesc = durDiffMin > 0 ? "+\(durDiffMin) min longer" : "\(abs(durDiffMin)) min shorter"
                volumeComparison = "Volume difference: current run was \(distDesc) and \(durDesc) in duration."
            }

            let paceComparison: String
            if paceDeltaSeconds > 0 {
                paceComparison = "\(paceDeltaSeconds)s/km faster in current run (\(current.paceFormatted) in \(envCurrent) vs \(prior.paceFormatted) in \(envPrior))"
            } else if paceDeltaSeconds < 0 {
                paceComparison = "\(abs(paceDeltaSeconds))s/km slower in current run (\(current.paceFormatted) in \(envCurrent) vs \(prior.paceFormatted) in \(envPrior))"
            } else {
                paceComparison = "identical pace (\(current.paceFormatted))"
            }

            let cadComparison: String
            if cadenceDelta > 0 {
                cadComparison = "+\(cadenceDelta) SPM higher turnover in current run (\(current.cadenceSPM) SPM in \(envCurrent) vs \(prior.cadenceSPM) SPM in \(envPrior))"
            } else if cadenceDelta < 0 {
                cadComparison = "\(abs(cadenceDelta)) SPM lower turnover in current run (\(current.cadenceSPM) SPM in \(envCurrent) vs \(prior.cadenceSPM) SPM in \(envPrior))"
            } else {
                cadComparison = "matched turnover (\(current.cadenceSPM) SPM)"
            }

            let hrComparison: String
            if heartRateDelta > 0 {
                hrComparison = "+\(heartRateDelta) BPM higher cardiac cost in current run (\(current.heartRateBPM) BPM in \(envCurrent) vs \(prior.heartRateBPM) BPM in \(envPrior))"
            } else if heartRateDelta < 0 {
                hrComparison = "\(abs(heartRateDelta)) BPM lower cardiovascular demand in current run (\(current.heartRateBPM) BPM in \(envCurrent) vs \(prior.heartRateBPM) BPM in \(envPrior))"
            } else {
                hrComparison = "identical average heart rate (\(current.heartRateBPM) BPM)"
            }

            return """
            HISTORICAL WORKOUT COMPARISON TELEMETRY:
            Current Run:
            - Date: \(current.weekday), \(current.formattedDate)
            - Classification: \(current.classification)
            - Distance: \(String(format: "%.2f", currentDistKm)) km (\(Int(current.durationSeconds / 60)) min)
            - Working Pace: \(current.paceFormatted)
            - Working Cadence: \(current.cadenceSPM) SPM
            - Working Heart Rate: \(current.heartRateBPM) BPM
            - Environment: \(envCurrent)

            Prior Run:
            - Date: \(prior.weekday), \(prior.formattedDate)
            - Classification: \(prior.classification)
            - Distance: \(String(format: "%.2f", priorDistKm)) km (\(Int(prior.durationSeconds / 60)) min)
            - Working Pace: \(prior.paceFormatted)
            - Working Cadence: \(prior.cadenceSPM) SPM
            - Working Heart Rate: \(prior.heartRateBPM) BPM
            - Environment: \(envPrior)

            Comparative Context:
            - Recency: \(recencyContrast)
            - Classification: \(classificationComparison)
            - Volume: \(volumeComparison)
            - Environment: Current: \(envCurrent) vs Prior: \(envPrior)

            Mathematical Telemetry Deltas:
            - Pace: \(paceComparison)
            - Cadence: \(cadComparison)
            - Heart Rate: \(hrComparison)
            """
        }

        /// Natural language synthesized comparison for fallback and offline coaching contexts.
        var coachingComparisonSummary: String {
            let envCurrent = current.isIndoor ? "Indoor Treadmill" : "Outdoor"

            let cal = Calendar.current
            let daysDiff = cal.dateComponents([.day], from: cal.startOfDay(for: prior.date), to: cal.startOfDay(for: current.date)).day ?? 0
            let recencyNote = daysDiff > 0
                ? "Your \(current.classification) on \(current.formattedDate) took place **\(daysDiff) day\(daysDiff == 1 ? "" : "s") after** your \(prior.classification) on \(prior.formattedDate)."
                : "Workouts on \(current.formattedDate) and \(prior.formattedDate)."

            let currentDistKm = Double(String(format: "%.2f", current.distanceMeters / 1000.0)) ?? (current.distanceMeters / 1000.0)
            let priorDistKm = Double(String(format: "%.2f", prior.distanceMeters / 1000.0)) ?? (prior.distanceMeters / 1000.0)
            let distDiffKm = currentDistKm - priorDistKm
            let distComp = distDiffKm > 0 ? "+\(String(format: "%.2f", distDiffKm)) km longer" : "\(String(format: "%.2f", abs(distDiffKm))) km shorter"

            let paceComp = paceDeltaSeconds > 0 ? "\(paceDeltaSeconds)s/km faster" : (paceDeltaSeconds < 0 ? "\(abs(paceDeltaSeconds))s/km slower" : "identical pace")
            let cadComp = cadenceDelta > 0 ? "+\(cadenceDelta) SPM higher turnover in \(envCurrent)" : (cadenceDelta < 0 ? "\(abs(cadenceDelta)) SPM lower turnover in \(envCurrent)" : "matched turnover")
            let hrComp = heartRateDelta > 0 ? "+\(heartRateDelta) BPM higher cardiac cost in \(envCurrent)" : (heartRateDelta < 0 ? "\(abs(heartRateDelta)) BPM lower cardiovascular demand in \(envCurrent)" : "matched heart rate")

            var lines = [
                "Comparing your **\(current.weekday), \(current.formattedDate) \(current.classification)** to your **\(prior.weekday), \(prior.formattedDate) \(prior.classification)** (\(recencyNote)):",
                "",
                "• **Pace**: **\(current.paceFormatted)** vs **\(prior.paceFormatted)** (\(paceComp))",
                "• **Cadence**: **\(current.cadenceSPM) SPM** vs **\(prior.cadenceSPM) SPM** (\(cadComp))",
                "• **Heart Rate**: **\(current.heartRateBPM) BPM** vs **\(prior.heartRateBPM) BPM** (\(hrComp))",
                "• **Volume**: **\(String(format: "%.2f", currentDistKm)) km** (\(Int(current.durationSeconds / 60)) min) vs **\(String(format: "%.2f", priorDistKm)) km** (\(Int(prior.durationSeconds / 60)) min) (\(distComp))",
                ""
            ]

            let isCurrentInterval = current.classification.localizedCaseInsensitiveContains("interval")
            let isPriorInterval = prior.classification.localizedCaseInsensitiveContains("interval")

            if isCurrentInterval && !isPriorInterval {
                lines.append("Workout structure contrast: your current interval workout featured discrete work bouts separated by active recovery valleys, allowing your average heart rate to stay lower despite fast reps. The prior \(prior.classification) was a continuous sustained effort with constant cardiovascular load.")
            } else if paceDeltaSeconds > 0 && heartRateDelta <= 0 {
                lines.append("Positive aerobic progression: you held a faster pace while operating at lower cardiovascular cost and maintaining higher turnover.")
            } else if paceDeltaSeconds <= 0 && heartRateDelta < 0 {
                lines.append("Controlled aerobic containment: you operated at a more conservative pace, keeping your cardiovascular cost significantly lower.")
            } else {
                lines.append("Consistent pacing and cardiovascular engagement across both sessions.")
            }

            if current.isIndoor && !prior.isIndoor {
                lines.append("\nIndoor vs outdoor contrast: running on the treadmill eliminated wind resistance and road gradient variations, but required active turnover to keep pace with the moving belt.")
            }

            return lines.joined(separator: "\n")
        }
    }

    struct PerformanceArcAnalysis: Sendable {
        let totalRunsInPast30Days: Int
        let bestRun: TelemetryData?
        let worstRun: TelemetryData?
        let currentRun: TelemetryData?

        /// Structured mathematical and telemetry facts for FoundationModels tool injection.
        /// Zero canned coaching prose; purely factual telemetry.
        var structuredTelemetryFacts: String {
            guard let current = currentRun else {
                return "30-DAY PERFORMANCE ARC TELEMETRY:\nNo workouts recorded in the past 30 days."
            }
            guard let best = bestRun else {
                return """
                30-DAY PERFORMANCE ARC TELEMETRY:
                Only 1 workout recorded in the past 30 days (\(current.weekday), \(current.formattedDate)):
                - Type: \(current.classification) (\(current.isIndoor ? "Indoor Treadmill" : "Outdoor"))
                - Distance: \(String(format: "%.2f", current.distanceMeters / 1000.0)) km (\(Int(current.durationSeconds / 60)) min)
                - Working Pace: \(current.paceFormatted)
                - Working Cadence: \(current.cadenceSPM) SPM
                - Working Heart Rate: \(current.heartRateBPM) BPM
                - Efficiency Factor: \(current.efficiencyFactor.map { String(format: "%.2f m/beat", $0) } ?? "N/A")
                """
            }

            let worst = worstRun ?? current
            let paceDeltaSec = Int(worst.paceSecondsPerKm.rounded() - best.paceSecondsPerKm.rounded())
            let cadDelta = best.cadenceSPM - worst.cadenceSPM
            let hrDelta = worst.heartRateBPM - best.heartRateBPM
            let bestEFStr = best.efficiencyFactor.map { String(format: "%.2f m/beat", $0) } ?? "N/A"
            let worstEFStr = worst.efficiencyFactor.map { String(format: "%.2f m/beat", $0) } ?? "N/A"

            return """
            30-DAY PERFORMANCE ARC TELEMETRY (\(totalRunsInPast30Days) workouts recorded in the past 30 days):

            BEST PERFORMANCE WORKOUT:
            - Date: \(best.weekday), \(best.formattedDate)
            - Classification: \(best.classification) (\(best.isIndoor ? "Indoor Treadmill" : "Outdoor"))
            - Distance: \(String(format: "%.2f", best.distanceMeters / 1000.0)) km (\(Int(best.durationSeconds / 60)) min)
            - Working Pace: \(best.paceFormatted)
            - Working Cadence: \(best.cadenceSPM) SPM (turnover in steps per minute)
            - Working Heart Rate: \(best.heartRateBPM) BPM
            - Efficiency Factor: \(bestEFStr) (peak aerobic running economy)

            WORST / TOUGHEST WORKOUT:
            - Date: \(worst.weekday), \(worst.formattedDate)
            - Classification: \(worst.classification) (\(worst.isIndoor ? "Indoor Treadmill" : "Outdoor"))
            - Distance: \(String(format: "%.2f", worst.distanceMeters / 1000.0)) km (\(Int(worst.durationSeconds / 60)) min)
            - Working Pace: \(worst.paceFormatted) (\(abs(paceDeltaSec))s/km slower than best)
            - Working Cadence: \(worst.cadenceSPM) SPM (\(abs(cadDelta)) SPM lower turnover)
            - Working Heart Rate: \(worst.heartRateBPM) BPM (+\(max(0, hrDelta)) BPM higher cardiac load)
            - Efficiency Factor: \(worstEFStr) (lower running economy under fatigue)

            MATHEMATICAL PERFORMANCE DELTAS (Best vs Toughest):
            - Pace Gap: \(abs(paceDeltaSec))s/km difference
            - Cadence Gap: \(abs(cadDelta)) SPM difference (turnover strictly in SPM)
            - Heart Rate Gap: \(abs(hrDelta)) BPM cardiac spread
            """
        }

        /// Natural language synthesized coaching arc for fallback and offline coaching contexts.
        var coachingArcSummary: String {
            guard let current = currentRun else {
                return "In the past 30 days, you have no recorded workouts."
            }
            guard let best = bestRun else {
                return "In the past 30 days, you have 1 workout recorded: your **\(current.weekday), \(current.formattedDate) \(current.classification)** (**\(String(format: "%.2f", current.distanceMeters / 1000.0)) km** at **\(current.paceFormatted)** with **\(current.cadenceSPM) SPM** cadence)."
            }

            let worst = worstRun ?? current
            let paceDeltaSec = Int(worst.paceSecondsPerKm.rounded() - best.paceSecondsPerKm.rounded())
            let cadDelta = best.cadenceSPM - worst.cadenceSPM
            let bestEF = best.efficiencyFactor.map { String(format: "%.2f", $0) } ?? ""
            let worstEF = worst.efficiencyFactor.map { String(format: "%.2f", $0) } ?? ""

            let bestEFNote = !bestEF.isEmpty ? " and a **\(bestEF)** efficiency factor (reflecting high speed per heartbeat)" : ""
            let worstEFNote = !worstEF.isEmpty ? " The **\(worstEF)** efficiency factor and " : " The "
            let cadDiffNote = cadDelta > 0 ? "**\(cadDelta) SPM lower turnover**" : "matched turnover"

            let envNote = worst.isIndoor ? "particularly under the treadmill's static heat and braking shock" : "reflecting cumulative fatigue"

            return """
            Looking at your performance arc across the past 30 days (\(totalRunsInPast30Days) workouts recorded):

            Your **best performance** came on **\(best.weekday), \(best.formattedDate)** during a **\(String(format: "%.2f", best.distanceMeters / 1000.0)) km \(best.classification)**, where you sustained a **\(best.paceFormatted)** pace with **\(best.cadenceSPM) SPM** cadence\(bestEFNote)—demonstrating peak aerobic control and mechanical efficiency.

            Your **toughest session** was your **\(worst.weekday), \(worst.formattedDate) \(worst.classification)**. \(worstEFNote)\(cadDiffNote) showed cardiovascular decoupling creeping in, \(envNote). Compared to your best session, your pace was **\(abs(paceDeltaSec))s/km slower** at a heart rate of **\(worst.heartRateBPM) BPM**, showing how environmental conditions and recovery interplay.
            """
        }
    }

    /// Parses potential two-run comparison targets from a single query string.
    static func parseComparisonTargets(from query: String) -> (targetA: String, targetB: String)? {
        let lower = query.lowercased()

        // 1. Environment contrast detection: "indoor" and "outdoor"
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

        // 2. Phrasing splitters: " vs ", " vs. ", " versus ", " compared to ", " to "
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

    /// Compares two arbitrary workouts (e.g. last outdoor run vs last indoor run) from the stored database.
    static func compareRuns(
        queryA: String,
        queryB: String,
        relativeTo currentRun: RunRecord?,
        in context: ModelContext?
    ) -> ComparisonTelemetry? {
        guard let context = context else { return nil }
        let descriptor = FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        guard let allRuns = try? context.fetch(descriptor), !allRuns.isEmpty else { return nil }

        // Find runA
        guard let runA = findRun(matching: queryA, in: allRuns, relativeTo: nil) else { return nil }

        // Find runB from the remaining runs
        let remainingRuns = allRuns.filter { $0.id != runA.id }
        guard let runB = findRun(matching: queryB, in: remainingRuns, relativeTo: nil) else { return nil }

        // Order chronologically so the newer run is evaluated against the older run as baseline
        let newer: RunRecord
        let older: RunRecord
        if runA.date >= runB.date {
            newer = runA
            older = runB
        } else {
            newer = runB
            older = runA
        }

        return compare(current: newer, with: older)
    }

    /// Finds a historical run in the model context matching the user's natural language query.
    static func findRun(
        matching query: String,
        relativeTo currentRun: RunRecord? = nil,
        in context: ModelContext?
    ) -> RunRecord? {
        guard let context = context else { return nil }
        let descriptor = FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        guard let allRuns = try? context.fetch(descriptor) else { return nil }

        let pool = currentRun.map { cr in allRuns.filter { $0.id != cr.id } } ?? allRuns
        guard !pool.isEmpty else { return nil }

        return findRun(matching: query, in: pool, relativeTo: currentRun)
    }

    typealias HistoricalQueryCriteria = Runalyst.HistoricalQueryCriteria

    /// Finds a matching run within an explicit pool of runs using deterministic composable query criteria.
    static func findRun(
        matching criteria: HistoricalQueryCriteria,
        in pool: [RunRecord],
        relativeTo currentRun: RunRecord? = nil
    ) -> RunRecord? {
        guard !pool.isEmpty else { return nil }
        var candidates = pool

        // If filtering relative to current run when query explicitly demands a prior run:
        if criteria.requiresPriorToCurrentRun, let current = currentRun {
            let priorOnly = candidates.filter { $0.date < current.date }
            if !priorOnly.isEmpty {
                candidates = priorOnly
            }
        }

        // 1. Filter by environment
        switch criteria.environment {
        case .outdoor:
            candidates = candidates.filter { !($0.isIndoor ?? false) }
        case .indoor:
            candidates = candidates.filter { $0.isIndoor == true }
        case .all:
            break
        }

        // 2. Filter by date components
        if criteria.targetYear != nil || criteria.targetMonth != nil || criteria.targetDay != nil {
            let calendar = Calendar.current
            candidates = candidates.filter { run in
                let comps = calendar.dateComponents([.year, .month, .day], from: run.date)
                if let y = criteria.targetYear, comps.year != y { return false }
                if let m = criteria.targetMonth, comps.month != m { return false }
                if let d = criteria.targetDay, comps.day != d { return false }
                return true
            }
        }

        // 3. Filter by modality
        if let mod = criteria.modality {
            let filteredByMod = candidates.filter {
                $0.detectedTypeRaw.localizedCaseInsensitiveContains(mod) ||
                $0.normalizedClassification.localizedCaseInsensitiveContains(mod)
            }
            if !filteredByMod.isEmpty {
                candidates = filteredByMod
            }
        }

        guard !candidates.isEmpty else { return nil }

        // Helper for efficiency factor
        func efficiencyScore(for run: RunRecord) -> Double {
            if let ef = run.efficiencyFactor, ef > 0 { return ef }
            let pace = run.workingAvgPace > 0 ? run.workingAvgPace : run.rawAvgPace
            let hr = run.workingAvgHeartRate > 0 ? run.workingAvgHeartRate : run.rawAvgHeartRate
            guard pace > 0, hr > 0 else { return 0.0 }
            return (60_000.0 / pace) / hr
        }

        // Meaningful runs filter for pace / efficiency superlatives
        if criteria.metric == .efficiencyFactor || criteria.metric == .pace {
            let meaningful = candidates.filter { $0.totalDistanceMeters >= 500 && $0.duration >= 180 }
            if !meaningful.isEmpty {
                candidates = meaningful
            }
        }

        // 4. Sort by criteria metric & direction
        let sorted = candidates.sorted { r1, r2 in
            switch criteria.metric {
            case .date:
                return criteria.direction == .ascending ? r1.date < r2.date : r1.date > r2.date
            case .distance:
                return criteria.direction == .ascending ? r1.totalDistanceMeters < r2.totalDistanceMeters : r1.totalDistanceMeters > r2.totalDistanceMeters
            case .duration:
                return criteria.direction == .ascending ? r1.duration < r2.duration : r1.duration > r2.duration
            case .pace:
                let p1 = r1.workingAvgPace > 0 ? r1.workingAvgPace : r1.rawAvgPace
                let p2 = r2.workingAvgPace > 0 ? r2.workingAvgPace : r2.rawAvgPace
                return criteria.direction == .ascending ? p1 < p2 : p1 > p2
            case .cadence:
                let c1 = r1.workingAvgCadence > 0 ? r1.workingAvgCadence : r1.rawAvgCadence
                let c2 = r2.workingAvgCadence > 0 ? r2.workingAvgCadence : r2.rawAvgCadence
                return criteria.direction == .ascending ? c1 < c2 : c1 > c2
            case .heartRate:
                let h1 = r1.workingAvgHeartRate > 0 ? r1.workingAvgHeartRate : r1.rawAvgHeartRate
                let h2 = r2.workingAvgHeartRate > 0 ? r2.workingAvgHeartRate : r2.rawAvgHeartRate
                return criteria.direction == .ascending ? h1 < h2 : h1 > h2
            case .efficiencyFactor:
                let ef1 = efficiencyScore(for: r1)
                let ef2 = efficiencyScore(for: r2)
                if abs(ef1 - ef2) > 0.001 {
                    return criteria.direction == .ascending ? ef1 < ef2 : ef1 > ef2
                }
                let p1 = r1.workingAvgPace > 0 ? r1.workingAvgPace : r1.rawAvgPace
                let p2 = r2.workingAvgPace > 0 ? r2.workingAvgPace : r2.rawAvgPace
                return criteria.direction == .ascending ? p1 > p2 : p1 < p2
            }
        }

        return sorted.first
    }

    /// Finds a matching run within an explicit pool of runs.
    static func findRun(
        matching query: String,
        in pool: [RunRecord],
        relativeTo currentRun: RunRecord? = nil
    ) -> RunRecord? {
        let criteria = HistoricalQueryCriteria.parse(from: query, relativeTo: currentRun)
        return findRun(matching: criteria, in: pool, relativeTo: currentRun)
    }

    /// Extracts standardized telemetry data from a RunRecord.
    static func extractTelemetry(from run: RunRecord) -> TelemetryData {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "MMMM d, yyyy"

        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale(identifier: "en_US_POSIX")
        weekdayFormatter.dateFormat = "EEEE"

        let currentFormattedDate = dateFormatter.string(from: run.date)
        let currentWeekday = weekdayFormatter.string(from: run.date)

        let currentType = run.detectedTypeRaw.isEmpty ? run.normalizedClassification : run.detectedTypeRaw
        let currentPace = run.workingAvgPace > 0 ? run.workingAvgPace : run.rawAvgPace
        let currentCad = Int(round(run.workingAvgCadence > 0 ? run.workingAvgCadence : run.rawAvgCadence))
        let currentHR = Int(round(run.workingAvgHeartRate > 0 ? run.workingAvgHeartRate : run.rawAvgHeartRate))
        let currentPaceStr = PaceFormatter.formatPace(secondsPerKilometer: currentPace)

        return TelemetryData(
            date: run.date,
            formattedDate: currentFormattedDate,
            weekday: currentWeekday,
            classification: currentType,
            paceSecondsPerKm: currentPace,
            paceFormatted: currentPaceStr,
            cadenceSPM: currentCad,
            heartRateBPM: currentHR,
            distanceMeters: run.totalDistanceMeters,
            durationSeconds: run.duration,
            isIndoor: run.isIndoor ?? false,
            efficiencyFactor: run.efficiencyFactor
        )
    }

    /// Evaluates 30-day performance rankings, identifying the athlete's peak and toughest workouts.
    static func analyzePerformanceArc(
        relativeTo currentRun: RunRecord? = nil,
        in context: ModelContext?
    ) -> PerformanceArcAnalysis {
        guard let context = context else {
            if let current = currentRun {
                let currentTelemetry = extractTelemetry(from: current)
                return PerformanceArcAnalysis(
                    totalRunsInPast30Days: 1,
                    bestRun: currentTelemetry,
                    worstRun: nil,
                    currentRun: currentTelemetry
                )
            }
            return PerformanceArcAnalysis(
                totalRunsInPast30Days: 0,
                bestRun: nil,
                worstRun: nil,
                currentRun: nil
            )
        }

        let descriptor = FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        guard let allRuns = try? context.fetch(descriptor), !allRuns.isEmpty else {
            if let current = currentRun {
                let currentTelemetry = extractTelemetry(from: current)
                return PerformanceArcAnalysis(
                    totalRunsInPast30Days: 1,
                    bestRun: currentTelemetry,
                    worstRun: nil,
                    currentRun: currentTelemetry
                )
            }
            return PerformanceArcAnalysis(
                totalRunsInPast30Days: 0,
                bestRun: nil,
                worstRun: nil,
                currentRun: nil
            )
        }

        guard let referenceRun = currentRun ?? allRuns.first else {
            return PerformanceArcAnalysis(
                totalRunsInPast30Days: 0,
                bestRun: nil,
                worstRun: nil,
                currentRun: nil
            )
        }
        let currentTelemetry = extractTelemetry(from: referenceRun)

        let calendar = Calendar.current
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: referenceRun.date) ?? referenceRun.date.addingTimeInterval(-30 * 86400)
        let futureLimit = referenceRun.date.addingTimeInterval(3600)

        var past30DaysRuns = allRuns.filter { $0.date >= thirtyDaysAgo && $0.date <= futureLimit }
        if !past30DaysRuns.contains(where: { $0.id == referenceRun.id }) {
            past30DaysRuns.append(referenceRun)
        }

        guard past30DaysRuns.count >= 2 else {
            return PerformanceArcAnalysis(
                totalRunsInPast30Days: past30DaysRuns.count,
                bestRun: currentTelemetry,
                worstRun: nil,
                currentRun: currentTelemetry
            )
        }

        let meaningfulRuns = past30DaysRuns.filter { $0.totalDistanceMeters >= 500 && $0.duration >= 180 }
        let candidateRuns = meaningfulRuns.count >= 2 ? meaningfulRuns : past30DaysRuns

        func efficiencyScore(for run: RunRecord) -> Double {
            if let ef = run.efficiencyFactor, ef > 0 { return ef }
            let pace = run.workingAvgPace > 0 ? run.workingAvgPace : run.rawAvgPace
            let hr = run.workingAvgHeartRate > 0 ? run.workingAvgHeartRate : run.rawAvgHeartRate
            guard pace > 0, hr > 0 else { return 0.0 }
            return (60_000.0 / pace) / hr
        }

        let sorted = candidateRuns.sorted { r1, r2 in
            let ef1 = efficiencyScore(for: r1)
            let ef2 = efficiencyScore(for: r2)
            if abs(ef1 - ef2) > 0.001 {
                return ef1 > ef2
            }
            let p1 = r1.workingAvgPace > 0 ? r1.workingAvgPace : r1.rawAvgPace
            let p2 = r2.workingAvgPace > 0 ? r2.workingAvgPace : r2.rawAvgPace
            return p1 < p2
        }

        guard let bestRecord = sorted.first else {
            return PerformanceArcAnalysis(
                totalRunsInPast30Days: past30DaysRuns.count,
                bestRun: currentTelemetry,
                worstRun: nil,
                currentRun: currentTelemetry
            )
        }
        let worstRecord = sorted.count > 1 ? sorted.last : nil

        let bestTelemetry = extractTelemetry(from: bestRecord)
        let worstTelemetry = worstRecord.map { extractTelemetry(from: $0) }

        return PerformanceArcAnalysis(
            totalRunsInPast30Days: past30DaysRuns.count,
            bestRun: bestTelemetry,
            worstRun: worstTelemetry,
            currentRun: currentTelemetry
        )
    }

    /// Computes deterministic telemetry deltas between the current run and a prior run.
    static func compare(current: RunRecord, with prior: RunRecord) -> ComparisonTelemetry {
        let currentTelemetry = extractTelemetry(from: current)
        let priorTelemetry = extractTelemetry(from: prior)

        let paceDeltaSec = Int(priorTelemetry.paceSecondsPerKm.rounded() - currentTelemetry.paceSecondsPerKm.rounded())
        let cadDelta = currentTelemetry.cadenceSPM - priorTelemetry.cadenceSPM
        let hrDelta = currentTelemetry.heartRateBPM - priorTelemetry.heartRateBPM
        let distDelta = currentTelemetry.distanceMeters - priorTelemetry.distanceMeters
        let durDelta = currentTelemetry.durationSeconds - priorTelemetry.durationSeconds

        return ComparisonTelemetry(
            current: currentTelemetry,
            prior: priorTelemetry,
            paceDeltaSeconds: paceDeltaSec,
            cadenceDelta: cadDelta,
            heartRateDelta: hrDelta,
            distanceDeltaMeters: distDelta,
            durationDeltaSeconds: durDelta
        )
    }

    /// Formats a concise catalog of the athlete's recorded workouts for tool listing queries.
    static func listRecentRuns(
        relativeTo currentRun: RunRecord? = nil,
        in context: ModelContext?,
        limit: Int = 10
    ) -> String {
        guard let context = context else {
            if currentRun != nil {
                return "Only the current run is available in stored records."
            }
            return "No workouts found in stored records."
        }
        let descriptor = FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        guard let allRuns = try? context.fetch(descriptor), !allRuns.isEmpty else {
            return "No workouts found in stored records."
        }
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "EEEE, MMMM d, yyyy"

        let totalCount = allRuns.count
        let newestDateStr = allRuns.first.map { dateFormatter.string(from: $0.date) } ?? "N/A"
        let oldestDateStr = allRuns.last.map { dateFormatter.string(from: $0.date) } ?? "N/A"

        var lines = [
            "ATHLETE WORKOUT DATABASE (\(totalCount) total workouts recorded, spanning from \(oldestDateStr) to \(newestDateStr)):",
            "Showing \(min(limit, totalCount)) most recent workouts (newest to oldest):"
        ]
        for run in allRuns.prefix(limit) {
            let isCurrent = currentRun != nil && run.id == currentRun?.id
            let marker = isCurrent ? " [CURRENT WORKOUT]" : ""
            let env = (run.isIndoor ?? false) ? "Indoor Treadmill" : "Outdoor"
            let distKm = String(format: "%.2f km", run.totalDistanceMeters / 1000.0)
            let durMin = "\(Int(run.duration / 60)) min"
            let pace = run.workingAvgPace > 0 ? PaceFormatter.formatPace(secondsPerKilometer: run.workingAvgPace) : PaceFormatter.formatPace(secondsPerKilometer: run.rawAvgPace)
            let cad = Int(round(run.workingAvgCadence > 0 ? run.workingAvgCadence : run.rawAvgCadence))
            let hr = Int(round(run.workingAvgHeartRate > 0 ? run.workingAvgHeartRate : run.rawAvgHeartRate))
            let type = run.detectedTypeRaw.isEmpty ? run.normalizedClassification : run.detectedTypeRaw
            let dateStr = dateFormatter.string(from: run.date)
            lines.append("• \(dateStr) - \(type) (\(env))\(marker): \(distKm) in \(durMin) @ \(pace), \(cad) SPM, \(hr) BPM")
        }
        if totalCount > limit {
            let olderCount = totalCount - limit
            lines.append("(\(olderCount) older workouts recorded in athlete database down to first logged run on \(oldestDateStr))")
        }
        return lines.joined(separator: "\n")
    }

    /// Formats a standalone telemetry card for a historical workout without requiring comparison math.
    static func formatSingleRun(
        _ run: RunRecord,
        totalWorkoutsCount: Int? = nil,
        rankInHistory: Int? = nil
    ) -> String {
        let telemetry = extractTelemetry(from: run)
        let env = telemetry.isIndoor ? "Indoor Treadmill" : "Outdoor"
        let distKm = String(format: "%.2f km", telemetry.distanceMeters / 1000.0)
        let durMin = "\(Int(telemetry.durationSeconds / 60)) min"
        let rankNote: String
        if let rank = rankInHistory, let total = totalWorkoutsCount {
            if rank == 1 {
                rankNote = "\n- Database Context: Oldest recorded workout (#1 of \(total) total workouts)"
            } else if rank == total {
                rankNote = "\n- Database Context: Most recent workout (#\(total) of \(total) total workouts)"
            } else {
                rankNote = "\n- Database Context: Workout #\(rank) of \(total) total workouts in chronological order"
            }
        } else {
            rankNote = ""
        }

        return """
        HISTORICAL WORKOUT TELEMETRY:
        - Date: \(telemetry.weekday), \(telemetry.formattedDate)
        - Classification: \(telemetry.classification)
        - Environment: \(env)
        - Distance: \(distKm) (\(durMin))
        - Working Pace: \(telemetry.paceFormatted)
        - Working Cadence: \(telemetry.cadenceSPM) SPM
        - Working Heart Rate: \(telemetry.heartRateBPM) BPM\(rankNote)
        """
    }

    /// Looks up a specific historical run by query criteria and returns its deterministic telemetry.
    static func lookupRun(
        matching query: String,
        relativeTo currentRun: RunRecord?,
        in context: ModelContext?
    ) -> String {
        guard let context = context else {
            return "No workouts found in stored records."
        }
        let descriptor = FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        guard let allRuns = try? context.fetch(descriptor), !allRuns.isEmpty else {
            return "No workouts found in stored records."
        }
        guard let match = findRun(matching: query, in: allRuns, relativeTo: currentRun) else {
            return "{\"status\":\"no_matching_run\",\"query\":\"\(query)\"}"
        }
        let ascending = allRuns.sorted(by: { $0.date < $1.date })
        let rank = ascending.firstIndex(where: { $0.id == match.id }).map { $0 + 1 }
        return formatSingleRun(match, totalWorkoutsCount: allRuns.count, rankInHistory: rank)
    }
}

// MARK: - Workout Math Calculator

/// Definitive mathematical result returned to the LLM and UI for running metrics math.
public struct WorkoutMathResult: Codable, Sendable, Equatable {
    public let operation: String
    public let valueA: String
    public let valueB: String
    public let delta: String
    public let deltaNumeric: Double?
    public let percentageChange: String?
    public let summary: String

    public init(
        operation: String,
        valueA: String,
        valueB: String,
        delta: String,
        deltaNumeric: Double? = nil,
        percentageChange: String? = nil,
        summary: String
    ) {
        self.operation = operation
        self.valueA = valueA
        self.valueB = valueB
        self.delta = delta
        self.deltaNumeric = deltaNumeric
        self.percentageChange = percentageChange
        self.summary = summary
    }

    /// Structured mathematical facts for FoundationModels tool injection.
    public var structuredFacts: String {
        return """
        WORKOUT MATH CALCULATION:
        - Operation: \(operation)
        - Value A: \(valueA)
        - Value B: \(valueB)
        - Mathematical Delta: \(delta)
        - Percentage Change: \(percentageChange ?? "N/A")
        - Verified Conclusion: \(summary)
        """
    }
}

/// Deterministic calculator for running math.
/// Executes exact pace subtraction, distance deltas, heart rate and turnover changes, and percentage differences in Swift
/// so the LLM never performs mental arithmetic or hallucinates numbers.
public enum WorkoutMathCalculator {

    /// Performs running math based on operation and input strings.
    public static func calculate(
        operation: String,
        valueA: String,
        valueB: String,
        metricType: String? = nil
    ) -> WorkoutMathResult {
        let opLower = operation.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let typeLower = (metricType ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Pace operations
        if opLower.contains("pace") || typeLower.contains("pace") || isPaceString(valueA) || isPaceString(valueB) {
            return calculatePaceDelta(paceAString: valueA, paceBString: valueB)
        }

        // 2. Distance operations
        if opLower.contains("dist") || typeLower.contains("dist") || valueA.lowercased().contains("km") || valueA.lowercased().contains("mi") {
            return calculateDistanceDelta(distAString: valueA, distBString: valueB)
        }

        // 3. Heart rate operations
        if opLower.contains("heart") || opLower.contains("hr") || typeLower.contains("heart") || typeLower.contains("hr") || valueA.lowercased().contains("bpm") {
            return calculateHeartRateDelta(hrAString: valueA, hrBString: valueB)
        }

        // 4. Cadence operations
        if opLower.contains("cadence") || opLower.contains("spm") || opLower.contains("turnover") || typeLower.contains("cadence") || valueA.lowercased().contains("spm") {
            return calculateCadenceDelta(cadAString: valueA, cadBString: valueB)
        }

        // 5. Explicit percentage change
        if opLower.contains("percent") {
            guard let numA = parseNumericValue(from: valueA),
                  let numB = parseNumericValue(from: valueB) else {
                return fallbackErrorResult(operation: operation, valueA: valueA, valueB: valueB)
            }
            return calculatePercentageChange(valA: numA, valB: numB, rawA: valueA, rawB: valueB)
        }

        // 6. Generic difference
        guard let numA = parseNumericValue(from: valueA),
              let numB = parseNumericValue(from: valueB) else {
            return fallbackErrorResult(operation: operation, valueA: valueA, valueB: valueB)
        }

        let delta = numA - numB
        let deltaFormatted = delta >= 0 ? "+\(formatDouble(delta))" : "\(formatDouble(delta))"
        let pct = numB != 0 ? ((numA - numB) / abs(numB)) * 100.0 : 0.0
        let pctStr = pct >= 0 ? "+\(String(format: "%.1f", pct))%" : "\(String(format: "%.1f", pct))%"

        return WorkoutMathResult(
            operation: "difference",
            valueA: valueA,
            valueB: valueB,
            delta: deltaFormatted,
            deltaNumeric: delta,
            percentageChange: pctStr,
            summary: "Value A (\(valueA)) is \(deltaFormatted) compared to Value B (\(valueB)) (\(pctStr))."
        )
    }

    // MARK: - Specialized Metric Calculators

    public static func calculatePaceDelta(paceAString: String, paceBString: String) -> WorkoutMathResult {
        guard let secA = parsePaceSeconds(from: paceAString),
              let secB = parsePaceSeconds(from: paceBString) else {
            return fallbackErrorResult(operation: "pace_delta", valueA: paceAString, valueB: paceBString)
        }

        let paceFormattedA = formatPace(seconds: secA)
        let paceFormattedB = formatPace(seconds: secB)

        // Delta in seconds: secA - secB. Negative means paceA took fewer seconds (faster).
        let paceDiffSec = Int(secA.rounded() - secB.rounded())
        let absDiff = abs(paceDiffSec)

        let verdict: String
        let deltaStr: String
        if paceDiffSec < 0 {
            deltaStr = "-\(absDiff) s/km"
            verdict = "\(absDiff) seconds/km faster (Value A is faster than Value B)"
        } else if paceDiffSec > 0 {
            deltaStr = "+\(absDiff) s/km"
            verdict = "\(absDiff) seconds/km slower (Value A is slower than Value B)"
        } else {
            deltaStr = "0 s/km"
            verdict = "Identical pace across both values"
        }

        // Speed percentage difference: velocity is proportional to 1 / pace.
        let speedPct: String?
        if secA > 0 && secB > 0 {
            let speedA = 1000.0 / secA
            let speedB = 1000.0 / secB
            let change = ((speedA - speedB) / speedB) * 100.0
            speedPct = change >= 0 ? "+\(String(format: "%.1f", change))% faster speed" : "\(String(format: "%.1f", change))% slower speed"
        } else {
            speedPct = nil
        }

        let speedNote = speedPct.map { " [\($0)]" } ?? ""
        return WorkoutMathResult(
            operation: "pace_delta",
            valueA: paceFormattedA,
            valueB: paceFormattedB,
            delta: deltaStr,
            deltaNumeric: Double(paceDiffSec),
            percentageChange: speedPct,
            summary: "\(verdict)\(speedNote)."
        )
    }

    public static func calculateDistanceDelta(distAString: String, distBString: String) -> WorkoutMathResult {
        guard let distA = parseNumericValue(from: distAString),
              let distB = parseNumericValue(from: distBString) else {
            return fallbackErrorResult(operation: "distance_delta", valueA: distAString, valueB: distBString)
        }

        let diff = distA - distB
        let absDiff = abs(diff)
        let diffFormatted = diff >= 0 ? "+\(String(format: "%.2f", diff)) km" : "-\(String(format: "%.2f", absDiff)) km"

        let pct = distB > 0 ? ((distA - distB) / distB) * 100.0 : 0.0
        let pctStr = pct >= 0 ? "+\(String(format: "%.1f", pct))%" : "\(String(format: "%.1f", pct))%"

        let summary = diff >= 0
            ? "Value A (\(String(format: "%.2f", distA)) km) is \(diffFormatted) longer than Value B (\(String(format: "%.2f", distB)) km) (\(pctStr))."
            : "Value A (\(String(format: "%.2f", distA)) km) is \(String(format: "%.2f", absDiff)) km shorter than Value B (\(String(format: "%.2f", distB)) km) (\(pctStr))."

        return WorkoutMathResult(
            operation: "distance_delta",
            valueA: "\(String(format: "%.2f", distA)) km",
            valueB: "\(String(format: "%.2f", distB)) km",
            delta: diffFormatted,
            deltaNumeric: diff,
            percentageChange: pctStr,
            summary: summary
        )
    }

    public static func calculateHeartRateDelta(hrAString: String, hrBString: String) -> WorkoutMathResult {
        guard let hrA = parseNumericValue(from: hrAString),
              let hrB = parseNumericValue(from: hrBString) else {
            return fallbackErrorResult(operation: "heart_rate_delta", valueA: hrAString, valueB: hrBString)
        }

        let intA = Int(hrA.rounded())
        let intB = Int(hrB.rounded())
        let diff = intA - intB
        let absDiff = abs(diff)
        let diffFormatted = diff >= 0 ? "+\(diff) BPM" : "-\(absDiff) BPM"

        let pct = hrB > 0 ? ((hrA - hrB) / hrB) * 100.0 : 0.0
        let pctStr = pct >= 0 ? "+\(String(format: "%.1f", pct))%" : "\(String(format: "%.1f", pct))%"

        let summary: String
        if diff > 0 {
            summary = "Value A (\(intA) BPM) is +\(diff) BPM higher cardiac cost than Value B (\(intB) BPM) (\(pctStr))."
        } else if diff < 0 {
            summary = "Value A (\(intA) BPM) is \(absDiff) BPM lower cardiovascular demand than Value B (\(intB) BPM) (\(pctStr))."
        } else {
            summary = "Identical heart rate across both values (\(intA) BPM)."
        }

        return WorkoutMathResult(
            operation: "heart_rate_delta",
            valueA: "\(intA) BPM",
            valueB: "\(intB) BPM",
            delta: diffFormatted,
            deltaNumeric: Double(diff),
            percentageChange: pctStr,
            summary: summary
        )
    }

    public static func calculateCadenceDelta(cadAString: String, cadBString: String) -> WorkoutMathResult {
        guard let cadA = parseNumericValue(from: cadAString),
              let cadB = parseNumericValue(from: cadBString) else {
            return fallbackErrorResult(operation: "cadence_delta", valueA: cadAString, valueB: cadBString)
        }

        let intA = Int(cadA.rounded())
        let intB = Int(cadB.rounded())
        let diff = intA - intB
        let absDiff = abs(diff)
        let diffFormatted = diff >= 0 ? "+\(diff) SPM" : "-\(absDiff) SPM"

        let pct = cadB > 0 ? ((cadA - cadB) / cadB) * 100.0 : 0.0
        let pctStr = pct >= 0 ? "+\(String(format: "%.1f", pct))%" : "\(String(format: "%.1f", pct))%"

        let summary: String
        if diff > 0 {
            summary = "Value A (\(intA) SPM) has +\(diff) SPM higher turnover than Value B (\(intB) SPM) (\(pctStr))."
        } else if diff < 0 {
            summary = "Value A (\(intA) SPM) has \(absDiff) SPM lower turnover than Value B (\(intB) SPM) (\(pctStr))."
        } else {
            summary = "Matched cadence turnover across both values (\(intA) SPM)."
        }

        return WorkoutMathResult(
            operation: "cadence_delta",
            valueA: "\(intA) SPM",
            valueB: "\(intB) SPM",
            delta: diffFormatted,
            deltaNumeric: Double(diff),
            percentageChange: pctStr,
            summary: summary
        )
    }

    public static func calculatePercentageChange(valA: Double, valB: Double, rawA: String, rawB: String) -> WorkoutMathResult {
        guard valB != 0 else {
            return WorkoutMathResult(
                operation: "percentage_change",
                valueA: rawA,
                valueB: rawB,
                delta: "Undefined (division by zero)",
                deltaNumeric: nil,
                percentageChange: nil,
                summary: "Cannot compute percentage change when baseline (Value B) is zero."
            )
        }

        let diff = valA - valB
        let pct = (diff / abs(valB)) * 100.0
        let pctStr = pct >= 0 ? "+\(String(format: "%.1f", pct))%" : "\(String(format: "%.1f", pct))%"
        let diffStr = diff >= 0 ? "+\(formatDouble(diff))" : "\(formatDouble(diff))"

        return WorkoutMathResult(
            operation: "percentage_change",
            valueA: rawA,
            valueB: rawB,
            delta: diffStr,
            deltaNumeric: diff,
            percentageChange: pctStr,
            summary: "Value A is \(pctStr) relative to baseline Value B (delta of \(diffStr))."
        )
    }

    // MARK: - Parsing Helpers

    public static func parsePaceSeconds(from string: String) -> Double? {
        let clean = string.lowercased()
            .replacingOccurrences(of: "/km", with: "")
            .replacingOccurrences(of: "/mi", with: "")
            .replacingOccurrences(of: "min/km", with: "")
            .replacingOccurrences(of: "min/mi", with: "")
            .replacingOccurrences(of: "s/km", with: "")
            .replacingOccurrences(of: "sec", with: "")
            .replacingOccurrences(of: "s", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if formatted as "M:SS" or "MM:SS"
        if clean.contains(":") {
            let parts = clean.split(separator: ":")
            if parts.count == 2,
               let mins = Double(parts[0].trimmingCharacters(in: .whitespaces)),
               let secs = Double(parts[1].trimmingCharacters(in: .whitespaces)) {
                return mins * 60.0 + secs
            }
        }

        // Check if raw seconds (e.g. "362" or "374")
        if let totalSec = Double(clean), totalSec >= 120 && totalSec <= 1200 {
            return totalSec
        }

        return nil
    }

    public static func parseNumericValue(from string: String) -> Double? {
        let clean = string.lowercased()
            .replacingOccurrences(of: "km", with: "")
            .replacingOccurrences(of: "mi", with: "")
            .replacingOccurrences(of: "bpm", with: "")
            .replacingOccurrences(of: "spm", with: "")
            .replacingOccurrences(of: "min", with: "")
            .replacingOccurrences(of: "sec", with: "")
            .replacingOccurrences(of: "m", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return Double(clean)
    }

    public static func formatPace(seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d/km", mins, secs)
    }

    private static func isPaceString(_ string: String) -> Bool {
        let lower = string.lowercased()
        return lower.contains(":") || lower.contains("/km") || lower.contains("/mi")
    }

    private static func formatDouble(_ val: Double) -> String {
        if val.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(val))"
        }
        return String(format: "%.2f", val)
    }

    private static func fallbackErrorResult(operation: String, valueA: String, valueB: String) -> WorkoutMathResult {
        return WorkoutMathResult(
            operation: operation,
            valueA: valueA,
            valueB: valueB,
            delta: "Invalid input",
            deltaNumeric: nil,
            percentageChange: nil,
            summary: "Could not parse values '\(valueA)' and '\(valueB)' into valid numeric telemetry for operation '\(operation)'."
        )
    }
}
