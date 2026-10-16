import Foundation

/// Input metrics for deterministic performance grading.
struct RunGradeInput {
    let type: String
    let isHard: Bool
    let percentZone4: Double
    let cadence: Int
    let workPaces: [Double]
    let paceDeltaVsBaseline: Double?
    let hrDeltaVsBaseline: Double?
    let cadenceFade: Bool
    let cardiacDrift: Bool
}

/// Formatted report card from deterministic grading.
struct RunGradeReport {
    let grade: String
    let strengths: [String]
    let focus: String?
    let type: String

    var sentence: String {
        var text = "Overall, this \(type.lowercased()) workout earns a Grade \(grade)."
        if !strengths.isEmpty {
            text += " The highlights: \(strengths.prefix(2).joined(separator: ", and "))."
        }
        if let focus {
            text += " The primary focus area: \(focus)."
        } else {
            text += " There's no obvious weak spot here—keep doing what you're doing."
        }
        return text
    }
}

/// Deterministic performance grade built from the run's own telemetry.
enum RunGrade {
    static func evaluate(_ input: RunGradeInput) -> RunGradeReport {
        var score = 95
        var strengths: [String] = []
        var focuses: [String] = []
        if input.cadence < 150 {
            score -= 10
            focuses.append("your foot turnover was on the slower side—aim for quicker, lighter steps")
        } else if input.cadence >= 165 {
            strengths.append("quick, efficient foot turnover")
        } else {
            strengths.append("a solid, consistent cadence baseline")
        }

        if input.isHard {
            if input.percentZone4 >= 0.5 {
                strengths.insert("you committed fully to the hard work intervals", at: 0)
            }
            if input.workPaces.count >= 2, let first = input.workPaces.first, let last = input.workPaces.last, first > 0 {
                let fade = (last - first) / first
                let paces = input.workPaces
                let spread = ((paces.max() ?? first) - (paces.min() ?? first)) / first
                if fade > 0.05 {
                    score -= 10
                    focuses.append("your last rep faded noticeably—start the early reps a little more controlled")
                } else if spread < 0.03 {
                    strengths.append("evenly paced reps from first to last")
                }
            }
        } else if input.percentZone4 > 0.25 && ["Easy Run", "Recovery Run", "Recovery Jog"].contains(input.type) {
            score -= 10
            focuses.append("too much of this easy run crept into threshold intensity—slow down to keep easy days truly easy")
        }

        if input.cadenceFade {
            score -= 6
            focuses.append("your cadence faded late in the run")
        }
        if input.cardiacDrift && !input.isHard {
            score -= 6
            focuses.append("your heart rate drifted up while your pace held steady, a sign of fatigue or heat")
        }

        if let paceDelta = input.paceDeltaVsBaseline, let hrDelta = input.hrDeltaVsBaseline {
            if paceDelta > 5 && hrDelta <= 2 && !input.cardiacDrift {
                score += 3
                strengths.insert("you ran faster than your 30-day average without raising your heart rate", at: 0)
            } else if paceDelta > 5 && (hrDelta <= 2 || input.cardiacDrift) {
                strengths.insert("you ran faster than your 30-day average pace", at: 0)
            } else if paceDelta < -5 && hrDelta > 5 {
                score -= 6
                focuses.append("you were slower than your 30-day average at a higher heart rate, pointing to accumulated fatigue")
            }
        }

        return RunGradeReport(grade: letter(for: min(100, score)), strengths: strengths, focus: focuses.first, type: input.type)
    }

    static func letter(for score: Int) -> String {
        switch score {
        case 93...: return "A"
        case 88..<93: return "A-"
        case 83..<88: return "B+"
        case 78..<83: return "B"
        case 73..<78: return "B-"
        default: return "C+"
        }
    }
}
