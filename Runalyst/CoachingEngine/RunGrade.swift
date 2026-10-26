import Foundation
import RunalystCore

public typealias RunGradeInput = RunalystCore.RunGradeInput
public typealias RunGradeReport = RunalystCore.RunGradeReport

/// Deterministic performance grade built from the run's own telemetry.
enum RunGrade {
    static func evaluate(_ input: RunGradeInput) -> RunGradeReport {
        RunGradeCore.evaluate(input)
    }

    static func letter(for score: Int) -> String {
        RunGradeCore.letter(for: score)
    }
}
