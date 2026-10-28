import Foundation

// MARK: - Workout Math Result

public struct WorkoutMathResultCore: Codable, Sendable, Equatable {
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

// MARK: - Workout Math Calculator Core

public enum WorkoutMathCalculatorCore {

    public static func calculate(
        operation: String,
        valueA: String,
        valueB: String,
        metricType: String? = nil
    ) -> WorkoutMathResultCore {
        let opLower = operation.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let typeLower = (metricType ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if opLower.contains("pace") || typeLower.contains("pace") || isPaceString(valueA) || isPaceString(valueB) {
            return calculatePaceDelta(paceAString: valueA, paceBString: valueB)
        }

        if opLower.contains("dist") || typeLower.contains("dist") || valueA.lowercased().contains("km") || valueA.lowercased().contains("mi") {
            return calculateDistanceDelta(distAString: valueA, distBString: valueB)
        }

        if opLower.contains("heart") || opLower.contains("hr") || typeLower.contains("heart") || typeLower.contains("hr") || valueA.lowercased().contains("bpm") {
            return calculateHeartRateDelta(hrAString: valueA, hrBString: valueB)
        }

        if opLower.contains("cadence") || opLower.contains("spm") || opLower.contains("turnover") || typeLower.contains("cadence") || valueA.lowercased().contains("spm") {
            return calculateCadenceDelta(cadAString: valueA, cadBString: valueB)
        }

        if opLower.contains("percent") {
            guard let numA = parseNumericValue(from: valueA),
                  let numB = parseNumericValue(from: valueB) else {
                return fallbackErrorResult(operation: operation, valueA: valueA, valueB: valueB)
            }
            return calculatePercentageChange(valA: numA, valB: numB, rawA: valueA, rawB: valueB)
        }

        guard let numA = parseNumericValue(from: valueA),
              let numB = parseNumericValue(from: valueB) else {
            return fallbackErrorResult(operation: operation, valueA: valueA, valueB: valueB)
        }

        let delta = numA - numB
        let deltaFormatted = delta >= 0 ? "+\(formatDouble(delta))" : "\(formatDouble(delta))"
        let pct = numB != 0 ? ((numA - numB) / abs(numB)) * 100.0 : 0.0
        let pctStr = pct >= 0 ? "+\(String(format: "%.1f", pct))%" : "\(String(format: "%.1f", pct))%"

        return WorkoutMathResultCore(
            operation: "difference",
            valueA: valueA,
            valueB: valueB,
            delta: deltaFormatted,
            deltaNumeric: delta,
            percentageChange: pctStr,
            summary: "Value A (\(valueA)) is \(deltaFormatted) compared to Value B (\(valueB)) (\(pctStr))."
        )
    }

    public static func calculatePaceDelta(paceAString: String, paceBString: String) -> WorkoutMathResultCore {
        guard let secA = parsePaceSeconds(from: paceAString),
              let secB = parsePaceSeconds(from: paceBString) else {
            return fallbackErrorResult(operation: "pace_delta", valueA: paceAString, valueB: paceBString)
        }

        let paceFormattedA = formatPace(seconds: secA)
        let paceFormattedB = formatPace(seconds: secB)
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
        return WorkoutMathResultCore(
            operation: "pace_delta",
            valueA: paceFormattedA,
            valueB: paceFormattedB,
            delta: deltaStr,
            deltaNumeric: Double(paceDiffSec),
            percentageChange: speedPct,
            summary: "\(verdict)\(speedNote)."
        )
    }

    public static func calculateDistanceDelta(distAString: String, distBString: String) -> WorkoutMathResultCore {
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

        return WorkoutMathResultCore(
            operation: "distance_delta",
            valueA: "\(String(format: "%.2f", distA)) km",
            valueB: "\(String(format: "%.2f", distB)) km",
            delta: diffFormatted,
            deltaNumeric: diff,
            percentageChange: pctStr,
            summary: summary
        )
    }

    public static func calculateHeartRateDelta(hrAString: String, hrBString: String) -> WorkoutMathResultCore {
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

        return WorkoutMathResultCore(
            operation: "heart_rate_delta",
            valueA: "\(intA) BPM",
            valueB: "\(intB) BPM",
            delta: diffFormatted,
            deltaNumeric: Double(diff),
            percentageChange: pctStr,
            summary: summary
        )
    }

    public static func calculateCadenceDelta(cadAString: String, cadBString: String) -> WorkoutMathResultCore {
        guard let cadA = parseNumericValue(from: cadAString),
              let cadB = parseNumericValue(from: cadBString) else {
            return fallbackErrorResult(operation: "cadence_delta", valueA: cadAString, valueB: cadBString)
        }

        let intA = Int(cadA.rounded())
        let intB = Int(cadB.rounded())
        guard intA > 0 && intB > 0 else {
            return fallbackErrorResult(operation: "cadence_delta", valueA: cadAString, valueB: cadBString)
        }
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

        return WorkoutMathResultCore(
            operation: "cadence_delta",
            valueA: "\(intA) SPM",
            valueB: "\(intB) SPM",
            delta: diffFormatted,
            deltaNumeric: Double(diff),
            percentageChange: pctStr,
            summary: summary
        )
    }

    public static func calculatePercentageChange(valA: Double, valB: Double, rawA: String, rawB: String) -> WorkoutMathResultCore {
        guard valB != 0 else {
            return WorkoutMathResultCore(
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

        return WorkoutMathResultCore(
            operation: "percentage_change",
            valueA: rawA,
            valueB: rawB,
            delta: diffStr,
            deltaNumeric: diff,
            percentageChange: pctStr,
            summary: "Value A is \(pctStr) relative to baseline Value B (delta of \(diffStr))."
        )
    }

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

        if clean.contains(":") {
            let parts = clean.split(separator: ":")
            if parts.count == 2,
               let mins = Double(parts[0].trimmingCharacters(in: .whitespaces)),
               let secs = Double(parts[1].trimmingCharacters(in: .whitespaces)) {
                return mins * 60.0 + secs
            }
        }

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
        guard seconds > 0 && !seconds.isNaN && !seconds.isInfinite else { return "0:00/km" }
        let totalSeconds = Int(seconds.rounded())
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%d:%02d/km", minutes, remainingSeconds)
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

    private static func fallbackErrorResult(operation: String, valueA: String, valueB: String) -> WorkoutMathResultCore {
        return WorkoutMathResultCore(
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
