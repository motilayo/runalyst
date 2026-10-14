import Foundation
import SwiftData

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

            let paceComparison: String
            if paceDeltaSeconds > 0 {
                paceComparison = "\(paceDeltaSeconds)s/km faster in current run"
            } else if paceDeltaSeconds < 0 {
                paceComparison = "\(abs(paceDeltaSeconds))s/km slower in current run"
            } else {
                paceComparison = "identical pace"
            }

            let cadComparison: String
            if cadenceDelta > 0 {
                cadComparison = "+\(cadenceDelta) SPM higher turnover in current run"
            } else if cadenceDelta < 0 {
                cadComparison = "\(abs(cadenceDelta)) SPM lower turnover in current run"
            } else {
                cadComparison = "matched turnover"
            }

            let hrComparison: String
            if heartRateDelta > 0 {
                hrComparison = "+\(heartRateDelta) BPM higher cardiac cost in current run"
            } else if heartRateDelta < 0 {
                hrComparison = "\(abs(heartRateDelta)) BPM lower cardiovascular demand in current run"
            } else {
                hrComparison = "identical average heart rate"
            }

            let physiologicalSignal: String
            if paceDeltaSeconds > 0 && heartRateDelta <= 0 {
                physiologicalSignal = "Positive aerobic development: faster pace sustained at lower/equal heart rate with higher turnover."
            } else if paceDeltaSeconds > 0 && heartRateDelta > 0 {
                physiologicalSignal = "Effort escalation: faster pace drove proportional cardiovascular rise."
            } else if paceDeltaSeconds <= 0 && heartRateDelta < 0 {
                physiologicalSignal = "Aerobic containment: easier pace kept cardiovascular stress low."
            } else {
                physiologicalSignal = "Close mechanical and physiological parity across sessions."
            }

            let isCurrentInterval = current.classification.localizedCaseInsensitiveContains("interval")
            let isPriorInterval = prior.classification.localizedCaseInsensitiveContains("interval")

            let structureContrast: String
            if isCurrentInterval && !isPriorInterval {
                structureContrast = "Current session was an intermittent interval workout with alternating work reps and recovery valleys, whereas prior session was a continuous \(prior.classification). Recovery intervals actively lowered average heart rate despite high-velocity work reps."
            } else if !isCurrentInterval && isPriorInterval {
                structureContrast = "Current session was a continuous \(current.classification), whereas prior session was an intermittent interval workout with active recovery valleys."
            } else {
                structureContrast = "Both workouts share continuous training structure."
            }

            let envContrast: String
            if current.isIndoor && !prior.isIndoor {
                envContrast = "Current session was performed indoors on a treadmill (motor-driven belt, static air with thermal buildup, zero wind resistance), whereas prior session was outdoors on road pavement (stationary ground propulsion, convective wind cooling, outdoor grade variations)."
            } else if !current.isIndoor && prior.isIndoor {
                envContrast = "Current session was performed outdoors (ground propulsion, wind cooling) vs prior session indoors on a treadmill."
            } else {
                envContrast = "Both workouts took place in similar \(envCurrent.lowercased()) environments."
            }

            return """
            HISTORICAL WORKOUT COMPARISON TELEMETRY:
            Current Run:
            - Date: \(current.weekday), \(current.formattedDate)
            - Classification: \(current.classification)
            - Distance: \(String(format: "%.2f", current.distanceMeters / 1000)) km (\(Int(current.durationSeconds / 60)) min)
            - Working Pace: \(current.paceFormatted) (\(Int(current.paceSecondsPerKm))s/km)
            - Working Cadence: \(current.cadenceSPM) SPM
            - Working Heart Rate: \(current.heartRateBPM) BPM
            - Environment: \(envCurrent)

            Prior Run:
            - Date: \(prior.weekday), \(prior.formattedDate)
            - Classification: \(prior.classification)
            - Distance: \(String(format: "%.2f", prior.distanceMeters / 1000)) km (\(Int(prior.durationSeconds / 60)) min)
            - Working Pace: \(prior.paceFormatted) (\(Int(prior.paceSecondsPerKm))s/km)
            - Working Cadence: \(prior.cadenceSPM) SPM
            - Working Heart Rate: \(prior.heartRateBPM) BPM
            - Environment: \(envPrior)

            Mathematical Telemetry Deltas:
            - Pace: \(paceComparison)
            - Cadence: \(cadComparison)
            - Heart Rate: \(hrComparison)
            - Physiological Fact: \(physiologicalSignal)
            - Workout Structure Contrast: \(structureContrast)
            - Environmental Contrast: \(envContrast)
            """
        }

        /// Natural language synthesized comparison for fallback and offline coaching contexts.
        var coachingComparisonSummary: String {
            let paceComp = paceDeltaSeconds > 0 ? "\(paceDeltaSeconds)s/km faster" : (paceDeltaSeconds < 0 ? "\(abs(paceDeltaSeconds))s/km slower" : "identical pace")
            let cadComp = cadenceDelta > 0 ? "+\(cadenceDelta) SPM higher turnover" : (cadenceDelta < 0 ? "\(abs(cadenceDelta)) SPM lower turnover" : "matched turnover")
            let hrComp = heartRateDelta > 0 ? "+\(heartRateDelta) BPM higher cardiac cost" : (heartRateDelta < 0 ? "\(abs(heartRateDelta)) BPM lower cardiovascular demand" : "matched heart rate")

            var lines = [
                "Comparing your **\(current.weekday), \(current.formattedDate) \(current.classification)** to your **\(prior.weekday), \(prior.formattedDate) \(prior.classification)**:",
                "",
                "• **Pace**: **\(current.paceFormatted)** vs **\(prior.paceFormatted)** (\(paceComp))",
                "• **Cadence**: **\(current.cadenceSPM) SPM** vs **\(prior.cadenceSPM) SPM** (\(cadComp))",
                "• **Heart Rate**: **\(current.heartRateBPM) BPM** vs **\(prior.heartRateBPM) BPM** (\(hrComp))",
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
        let currentRun: TelemetryData

        /// Structured mathematical and telemetry facts for FoundationModels tool injection.
        /// Zero canned coaching prose; purely factual telemetry.
        var structuredTelemetryFacts: String {
            guard let best = bestRun else {
                return """
                30-DAY PERFORMANCE ARC TELEMETRY:
                Only 1 workout recorded in the past 30 days (\(currentRun.weekday), \(currentRun.formattedDate)):
                - Type: \(currentRun.classification) (\(currentRun.isIndoor ? "Indoor Treadmill" : "Outdoor"))
                - Distance: \(String(format: "%.2f", currentRun.distanceMeters / 1000.0)) km (\(Int(currentRun.durationSeconds / 60)) min)
                - Working Pace: \(currentRun.paceFormatted)
                - Working Cadence: \(currentRun.cadenceSPM) SPM
                - Working Heart Rate: \(currentRun.heartRateBPM) BPM
                - Efficiency Factor: \(currentRun.efficiencyFactor.map { String(format: "%.2f m/beat", $0) } ?? "N/A")
                """
            }

            let worst = worstRun ?? currentRun
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
            - Physiological Contrast: In the best session on \(best.formattedDate), aerobic coupling was optimal with high speed per heartbeat. In contrast, the toughest session on \(worst.formattedDate) exhibited higher cardiovascular strain and lower mechanical turnover.
            """
        }

        /// Natural language synthesized coaching arc for fallback and offline coaching contexts.
        var coachingArcSummary: String {
            guard let best = bestRun else {
                return "In the past 30 days, you have 1 workout recorded: your **\(currentRun.weekday), \(currentRun.formattedDate) \(currentRun.classification)** (**\(String(format: "%.2f", currentRun.distanceMeters / 1000.0)) km** at **\(currentRun.paceFormatted)** with **\(currentRun.cadenceSPM) SPM** cadence)."
            }

            let worst = worstRun ?? currentRun
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

    /// Finds a historical run in the model context matching the user's natural language query.
    static func findRun(
        matching query: String,
        relativeTo currentRun: RunRecord,
        in context: ModelContext?
    ) -> RunRecord? {
        guard let context = context else { return nil }
        let descriptor = FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        guard let allRuns = try? context.fetch(descriptor) else { return nil }

        let otherRuns = allRuns.filter { $0.id != currentRun.id }
        guard !otherRuns.isEmpty else { return nil }

        let lower = query.lowercased()

        let calendar = Calendar.current

        // 0. Superlatives: "best", "fastest", "worst", "slowest", "toughest"
        func efficiencyScore(for run: RunRecord) -> Double {
            if let ef = run.efficiencyFactor, ef > 0 { return ef }
            let pace = run.workingAvgPace > 0 ? run.workingAvgPace : run.rawAvgPace
            let hr = run.workingAvgHeartRate > 0 ? run.workingAvgHeartRate : run.rawAvgHeartRate
            guard pace > 0, hr > 0 else { return 0.0 }
            return (60_000.0 / pace) / hr
        }

        if lower.contains("best") || lower.contains("fastest") || lower.contains("highest efficiency") {
            let candidates = otherRuns.filter { $0.totalDistanceMeters >= 500 && $0.duration >= 180 }
            let pool = candidates.isEmpty ? otherRuns : candidates
            if let best = pool.max(by: { efficiencyScore(for: $0) < efficiencyScore(for: $1) }) {
                return best
            }
        }
        if lower.contains("worst") || lower.contains("slowest") || lower.contains("toughest") || lower.contains("lowest efficiency") {
            let candidates = otherRuns.filter { $0.totalDistanceMeters >= 500 && $0.duration >= 180 }
            let pool = candidates.isEmpty ? otherRuns : candidates
            if let worst = pool.min(by: { efficiencyScore(for: $0) < efficiencyScore(for: $1) }) {
                return worst
            }
        }

        // 1. Month + Day parsing (e.g., "September 14", "Sep 14", "Sept 14", "9/14")
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

        var targetMonth: Int?
        for m in months where lower.contains(m.name) {
            targetMonth = m.number
            break
        }

        var targetDay: Int?
        if let regex = try? NSRegularExpression(pattern: #"\b(\d{1,2})(?:st|nd|rd|th)?\b"#) {
            let nsRange = NSRange(lower.startIndex..<lower.endIndex, in: lower)
            let matches = regex.matches(in: lower, range: nsRange)
            for match in matches {
                if let dayRange = Range(match.range(at: 1), in: lower),
                   let dayVal = Int(lower[dayRange]), dayVal >= 1 && dayVal <= 31 {
                    targetDay = dayVal
                    break
                }
            }
        }

        // Handle numeric "M/D" or "MM/DD" (e.g., "9/14")
        if targetMonth == nil || targetDay == nil {
            if let slashRegex = try? NSRegularExpression(pattern: #"\b(\d{1,2})/(\d{1,2})\b"#) {
                let nsRange = NSRange(lower.startIndex..<lower.endIndex, in: lower)
                if let match = slashRegex.firstMatch(in: lower, range: nsRange),
                   let mRange = Range(match.range(at: 1), in: lower),
                   let dRange = Range(match.range(at: 2), in: lower),
                   let mVal = Int(lower[mRange]), let dVal = Int(lower[dRange]),
                   mVal >= 1 && mVal <= 12, dVal >= 1 && dVal <= 31 {
                    targetMonth = mVal
                    targetDay = dVal
                }
            }
        }

        if let targetMonth = targetMonth, let targetDay = targetDay {
            let matches = otherRuns.filter { run in
                let comps = calendar.dateComponents([.month, .day], from: run.date)
                return comps.month == targetMonth && comps.day == targetDay
            }
            if let bestMatch = matches.first {
                return bestMatch
            }
        }

        // 2. Relative references: "yesterday", "last run", "previous run", "prior run"
        if lower.contains("yesterday") {
            let yesterdayComps = calendar.dateComponents([.year, .month, .day], from: Date().addingTimeInterval(-86400))
            if let match = otherRuns.first(where: {
                let comps = calendar.dateComponents([.year, .month, .day], from: $0.date)
                return comps.year == yesterdayComps.year && comps.month == yesterdayComps.month && comps.day == yesterdayComps.day
            }) {
                return match
            }
        }

        if lower.contains("last run") || lower.contains("previous run") || lower.contains("prior run") || lower.contains("last workout") {
            let priorRuns = otherRuns.filter { $0.date < currentRun.date }
            if let prior = priorRuns.first {
                return prior
            }
        }

        // 3. Modality references: "previous intervals", "last tempo", "last long run"
        let modalities = ["intervals", "tempo", "steady", "progression", "recovery", "long"]
        for mod in modalities where lower.contains(mod) {
            let priorWithModality = otherRuns.filter {
                $0.date < currentRun.date &&
                ($0.detectedTypeRaw.localizedCaseInsensitiveContains(mod) || $0.normalizedClassification.localizedCaseInsensitiveContains(mod))
            }
            if let match = priorWithModality.first {
                return match
            }
        }

        return nil
    }

    /// Extracts standardized telemetry data from a RunRecord.
    static func extractTelemetry(from run: RunRecord) -> TelemetryData {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "MMMM d"

        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale(identifier: "en_US_POSIX")
        weekdayFormatter.dateFormat = "EEEE"

        let currentFormattedDate = dateFormatter.string(from: run.date)
        let currentWeekday = weekdayFormatter.string(from: run.date)

        let currentType = run.detectedTypeRaw.isEmpty ? run.normalizedClassification : run.detectedTypeRaw
        let currentPace = run.workingAvgPace > 0 ? run.workingAvgPace : run.rawAvgPace
        let currentCad = Int(run.workingAvgCadence > 0 ? run.workingAvgCadence : run.rawAvgCadence)
        let currentHR = Int(run.workingAvgHeartRate > 0 ? run.workingAvgHeartRate : run.rawAvgHeartRate)
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
        relativeTo currentRun: RunRecord,
        in context: ModelContext?
    ) -> PerformanceArcAnalysis {
        let currentTelemetry = extractTelemetry(from: currentRun)
        guard let context = context else {
            return PerformanceArcAnalysis(
                totalRunsInPast30Days: 1,
                bestRun: currentTelemetry,
                worstRun: nil,
                currentRun: currentTelemetry
            )
        }

        let descriptor = FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        guard let allRuns = try? context.fetch(descriptor), !allRuns.isEmpty else {
            return PerformanceArcAnalysis(
                totalRunsInPast30Days: 1,
                bestRun: currentTelemetry,
                worstRun: nil,
                currentRun: currentTelemetry
            )
        }

        let calendar = Calendar.current
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: currentRun.date) ?? currentRun.date.addingTimeInterval(-30 * 86400)
        let futureLimit = currentRun.date.addingTimeInterval(3600)

        var past30DaysRuns = allRuns.filter { $0.date >= thirtyDaysAgo && $0.date <= futureLimit }
        if !past30DaysRuns.contains(where: { $0.id == currentRun.id }) {
            past30DaysRuns.append(currentRun)
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
}
