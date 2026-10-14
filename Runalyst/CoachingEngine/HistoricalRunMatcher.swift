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

        let calendar = Calendar.current
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

    /// Computes deterministic telemetry deltas between the current run and a prior run.
    static func compare(current: RunRecord, with prior: RunRecord) -> ComparisonTelemetry {
        let calendar = Calendar.current
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "MMMM d"

        let currentFormattedDate = dateFormatter.string(from: current.date)
        let priorFormattedDate = dateFormatter.string(from: prior.date)

        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale(identifier: "en_US_POSIX")
        weekdayFormatter.dateFormat = "EEEE"

        let currentWeekday = weekdayFormatter.string(from: current.date)
        let priorWeekday = weekdayFormatter.string(from: prior.date)

        let currentType = current.detectedTypeRaw.isEmpty ? current.normalizedClassification : current.detectedTypeRaw
        let priorType = prior.detectedTypeRaw.isEmpty ? prior.normalizedClassification : prior.detectedTypeRaw

        let currentPace = current.workingAvgPace > 0 ? current.workingAvgPace : current.rawAvgPace
        let priorPace = prior.workingAvgPace > 0 ? prior.workingAvgPace : prior.rawAvgPace

        let currentCad = Int(current.workingAvgCadence > 0 ? current.workingAvgCadence : current.rawAvgCadence)
        let priorCad = Int(prior.workingAvgCadence > 0 ? prior.workingAvgCadence : prior.rawAvgCadence)

        let currentHR = Int(current.workingAvgHeartRate > 0 ? current.workingAvgHeartRate : current.rawAvgHeartRate)
        let priorHR = Int(prior.workingAvgHeartRate > 0 ? prior.workingAvgHeartRate : prior.rawAvgHeartRate)

        let currentPaceStr = PaceFormatter.formatPace(secondsPerKilometer: currentPace)
        let priorPaceStr = PaceFormatter.formatPace(secondsPerKilometer: priorPace)

        let currentTelemetry = TelemetryData(
            date: current.date,
            formattedDate: currentFormattedDate,
            weekday: currentWeekday,
            classification: currentType,
            paceSecondsPerKm: currentPace,
            paceFormatted: currentPaceStr,
            cadenceSPM: currentCad,
            heartRateBPM: currentHR,
            distanceMeters: current.totalDistanceMeters,
            durationSeconds: current.duration,
            isIndoor: current.isIndoor ?? false
        )

        let priorTelemetry = TelemetryData(
            date: prior.date,
            formattedDate: priorFormattedDate,
            weekday: priorWeekday,
            classification: priorType,
            paceSecondsPerKm: priorPace,
            paceFormatted: priorPaceStr,
            cadenceSPM: priorCad,
            heartRateBPM: priorHR,
            distanceMeters: prior.totalDistanceMeters,
            durationSeconds: prior.duration,
            isIndoor: prior.isIndoor ?? false
        )

        // Deltas
        let paceDeltaSec = Int(priorPace.rounded() - currentPace.rounded())
        let cadDelta = currentCad - priorCad
        let hrDelta = currentHR - priorHR
        let distDelta = current.totalDistanceMeters - prior.totalDistanceMeters
        let durDelta = current.duration - prior.duration

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
