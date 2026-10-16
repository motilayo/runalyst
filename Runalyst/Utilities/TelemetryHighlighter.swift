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

        var i = 0
        while i < lines.count {
            let line = lines[i]

            // Check if this line starts a markdown table (header followed by divider row)
            if isTableRow(line), i + 1 < lines.count, isTableDivider(lines[i + 1]) {
                let headerCells = parseTableCells(line)
                i += 2 // skip header and divider

                // Collect and format all subsequent table data rows into clean rich text bullets
                while i < lines.count && isTableRow(lines[i]) {
                    let dataCells = parseTableCells(lines[i])
                    if !dataCells.isEmpty {
                        let formattedRow = formatTableRowAsRichText(cells: dataCells, headers: headerCells)
                        processedLines.append(formattedRow)
                    }
                    i += 1
                }
                continue
            }

            // Check for stray table divider row (skip)
            if isTableDivider(line) {
                i += 1
                continue
            }

            // Check for horizontal rules (---, ***, ___)
            if line.range(of: #"^[\-\*_]{3,}\s*$"#, options: .regularExpression) != nil {
                processedLines.append("")
                i += 1
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
                i += 1
                continue
            }

            // Check for unordered list bullets (-, *, +)
            if line.range(of: #"^(\s*)[\-\*\+]\s+(.+)$"#, options: .regularExpression) != nil {
                let indent = line.replacingOccurrences(of: #"^(\s*).*$"#, with: "$1", options: .regularExpression)
                let bulletContent = line.replacingOccurrences(of: #"^\s*[\-\*\+]\s+"#, with: "", options: .regularExpression)
                processedLines.append("\(indent)• \(bulletContent)")
                i += 1
                continue
            }

            // Check for blockquotes (> Quote)
            if line.range(of: #"^>\s+(.+)$"#, options: .regularExpression) != nil {
                let quoteContent = line.replacingOccurrences(of: #"^>\s+"#, with: "", options: .regularExpression)
                processedLines.append("*\(quoteContent)*")
                i += 1
                continue
            }

            // Check for stray standalone table row without preceding divider
            if isTableRow(line) {
                let dataCells = parseTableCells(line)
                if dataCells.count >= 2 {
                    let formattedRow = formatTableRowAsRichText(cells: dataCells, headers: [])
                    processedLines.append(formattedRow)
                    i += 1
                    continue
                }
            }

            processedLines.append(line)
            i += 1
        }

        return processedLines.joined(separator: "\n")
    }

    private static func isTableRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return false }
        let pipeCount = trimmed.filter { $0 == "|" }.count
        return (trimmed.hasPrefix("|") && trimmed.hasSuffix("|")) || pipeCount >= 2
    }

    private static func isTableDivider(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") && trimmed.contains("-") else { return false }
        return trimmed.range(of: #"^\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)+\|?$"#, options: .regularExpression) != nil
    }

    private static func parseTableCells(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") {
            trimmed.removeFirst()
        }
        if trimmed.hasSuffix("|") {
            trimmed.removeLast()
        }
        return trimmed.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func formatTableRowAsRichText(cells: [String], headers: [String]) -> String {
        guard !cells.isEmpty else { return "" }

        var label = cells[0]
        if let firstHeader = headers.first?.lowercased() {
            if firstHeader.contains("rep") && !label.lowercased().contains("rep") {
                label = "Rep \(label)"
            } else if firstHeader.contains("split") && !label.lowercased().contains("split") {
                label = "Split \(label)"
            }
        }

        // Clean any existing markdown bolding from label to avoid nesting
        if label.hasPrefix("**") && label.hasSuffix("**") && label.count >= 4 {
            label = String(label.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces)
        }

        if cells.count == 1 {
            return "• **\(label)**"
        } else if cells.count == 2 {
            return "• **\(label)**: \(cells[1])"
        } else if cells.count == 3 {
            var gradeOrSub = cells[1]
            if gradeOrSub.hasPrefix("**") && gradeOrSub.hasSuffix("**") && gradeOrSub.count >= 4 {
                gradeOrSub = String(gradeOrSub.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces)
            }
            return "• **\(label) (\(gradeOrSub))**: \(cells[2])"
        } else {
            let details = cells[2...].joined(separator: " • ")
            return "• **\(label) (\(cells[1]))**: \(details)"
        }
    }

    private static func sanitizeLatex(_ text: String) -> String {
        var result = text
        // VO2 Max LaTeX variants
        result = result.replacingOccurrences(
            of: #"\$?(\\text\{VO\}_2\\text\{\s*max\}|VO_2\\text\{\s*max\}|\\text\{VO2max\}|\\text\{VO2 max\}|VO_2max)\$?"#,
            with: "VO2 Max",
            options: .regularExpression
        )
        // Common math operators
        result = result.replacingOccurrences(of: #"\$?\\times\$?"#, with: "×", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\$?\\approx\$?"#, with: "≈", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\$?\\le(q)?\$?"#, with: "≤", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\$?\\ge(q)?\$?"#, with: "≥", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\$?\\pm\$?"#, with: "±", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\$?\\cdot\$?"#, with: "·", options: .regularExpression)
        // \frac{a}{b} -> a/b
        result = result.replacingOccurrences(of: #"\\frac\{([^}]+)\}\{([^}]+)\}"#, with: "$1/$2", options: .regularExpression)
        // \textbf{...} or \mathbf{...} -> **...**
        result = result.replacingOccurrences(of: #"\\mathbf\{([^}]+)\}"#, with: "**$1**", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\\textbf\{([^}]+)\}"#, with: "**$1**", options: .regularExpression)
        // \text{...} -> ...
        result = result.replacingOccurrences(of: #"\\text\{([^}]+)\}"#, with: "$1", options: .regularExpression)
        // Strip leftover $ or $$
        result = result.replacingOccurrences(of: #"\${1,2}([^$]+)\${1,2}"#, with: "$1", options: .regularExpression)
        return result
    }
}
