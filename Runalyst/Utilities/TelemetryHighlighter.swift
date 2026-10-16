import SwiftUI

/// Utility for rendering telemetry citations (SPM, BPM, pace, biomechanics) and markdown formatted text into rich text via AttributedString.
enum TelemetryHighlighter {

    /// Highlights numbers and biomechanical units with bold weight and accent styling, while rendering markdown elements as rich text formatting.
    static func highlight(_ text: String, accentColor: Color = Color(red: 0.0, green: 0.75, blue: 0.65)) -> AttributedString {
        let preprocessed = convertMarkdownToRichText(text)
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        var attributed = (try? AttributedString(markdown: preprocessed, options: options)) ?? AttributedString(text)

        let plainText = String(attributed.characters)

        // Subconscious Data Binding: Universally consistent Apple-native color tokens
        let hrPink = Color(red: 1.0, green: 0.18, blue: 0.55)      // Neon Pink for Heart Rate
        let paceBlue = Color(red: 0.0, green: 0.55, blue: 1.0)     // Electric Blue for Pace
        let cadGreen = Color(red: 0.18, green: 0.82, blue: 0.35)   // Vibrant Green for Cadence

        let typedPatterns: [(pattern: String, color: Color)] = [
            (#"\b\d{2,3}(?:\s*[-–—]\s*\d{2,3})?\s?(?:SPM|spm|steps per minute|steps/min)\b"#, cadGreen),
            (#"(?:[+-]?\b\d{2,3}(?:\s*[-–—]\s*\d{2,3})?\s?(?:BPM|bpm)\b)"#, hrPink),
            (#"\b\d{1,2}:\d{2}(?:\s*[-–—]\s*\d{1,2}:\d{2})?(?:\s?(?:/km|/mi|min/km|min/mi))?\b"#, paceBlue),
            (#"[+-]?\b\d{1,2}(?:s|sec)\s*/\s*(?:km|mi)\b"#, paceBlue),
            (#"\b\d+(?:\.\d+)?\s?(?:cm|m|km|mi|ms|%)\b"#, accentColor)
        ]

        for (pattern, color) in typedPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let nsString = plainText as NSString
            let matches = regex.matches(in: plainText, options: [], range: NSRange(location: 0, length: nsString.length))

            for match in matches {
                if let stringRange = Range(match.range, in: plainText),
                   let attrRange = Range(stringRange, in: attributed) {
                    attributed[attrRange].font = .system(size: 15, weight: .bold, design: .rounded).monospacedDigit()
                    attributed[attrRange].foregroundColor = color
                }
            }
        }

        return attributed
    }

    private static func convertMarkdownToRichText(_ text: String) -> String {
        let sanitized = sanitizeLatex(text)
        let lines = sanitized.components(separatedBy: "\n")
        var processedLines: [String] = []

        for line in lines {
            // Suppress table divider rows (e.g. |---|---|)
            if line.contains("-") && line.contains("|") && line.range(of: #"^\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)+\|?$"#, options: .regularExpression) != nil {
                continue
            }

            // Check for horizontal rules (---, ***, ___)
            if line.range(of: #"^[\-\*_]{3,}\s*$"#, options: .regularExpression) != nil {
                processedLines.append("")
                continue
            }

            // Check for markdown headers (# Title, ## Title, ### Title)
            if let match = line.range(of: #"^#{1,6}\s+(.+)$"#, options: .regularExpression) {
                var headerContent = line[match].replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
                headerContent = headerContent.replacingOccurrences(of: #"\s*#+$"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
                if headerContent.hasPrefix("**") && headerContent.hasSuffix("**") {
                    processedLines.append(headerContent)
                } else {
                    processedLines.append("**\(headerContent)**")
                }
                continue
            }

            // Check for unordered list bullets (-, *, +)
            if line.range(of: #"^(\s*)[\-\*\+]\s+(.+)$"#, options: .regularExpression) != nil {
                let indent = line.replacingOccurrences(of: #"^(\s*).*$"#, with: "$1", options: .regularExpression)
                let bulletContent = line.replacingOccurrences(of: #"^\s*[\-\*\+]\s+"#, with: "", options: .regularExpression)
                processedLines.append("\(indent)• \(bulletContent)")
                continue
            }

            // Check for blockquotes (> Quote)
            if line.range(of: #"^>\s+(.+)$"#, options: .regularExpression) != nil {
                let quoteContent = line.replacingOccurrences(of: #"^>\s+"#, with: "", options: .regularExpression)
                processedLines.append("*\(quoteContent)*")
                continue
            }

            processedLines.append(line)
        }

        return processedLines.joined(separator: "\n")
    }

    private static func sanitizeLatex(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(
            of: #"\$?(\\text\{VO\}_2\\text\{\s*max\}|VO_2\\text\{\s*max\}|\\text\{VO2max\}|\\text\{VO2 max\}|VO_2max)\$?"#,
            with: "VO2 Max",
            options: .regularExpression
        )
        result = result.replacingOccurrences(of: #"\$?\\times\$?"#, with: "×", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\$?\\approx\$?"#, with: "≈", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\${1,2}([^$]+)\${1,2}"#, with: "$1", options: .regularExpression)
        return result
    }
}
