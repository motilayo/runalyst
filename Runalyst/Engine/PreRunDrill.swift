import Foundation
import SwiftUI
import HealthKit

/// Represents an instantiated pre-run drill with user-specific cadence targets,
/// duration, and native WorkoutKit plan compilation capabilities.
struct PreRunDrill: Sendable {
    let id: PreRunDrillId
    let previousCadence: Int?
    let targetCadence: String?
    let duration: DrillDuration
    let hapticMode: HapticFeedbackMode
    /// Acute readiness modulation (ACWR). `.productive` leaves the standard prescription untouched.
    let readinessState: ReadinessState

    init(
        id: PreRunDrillId,
        previousCadence: Int? = nil,
        targetCadence: String? = nil,
        duration: DrillDuration? = nil,
        hapticMode: HapticFeedbackMode = .on,
        readinessState: ReadinessState = .productive
    ) {
        self.id = id
        self.previousCadence = previousCadence
        self.targetCadence = targetCadence
        self.duration = duration ?? id.defaultDuration
        self.hapticMode = hapticMode
        self.readinessState = readinessState
    }

    // Mathematical variables for constraints
    private let safeMaxCadence = 185
    private let safeMinCadence = 140

    var effectiveTargetCadence: ClosedRange<Int>? {
        // Recovery / flush / base builder drills do not use cadence turnover alerts
        switch id {
        case .aerobicFlush, .recoveryJog, .zone2Run:
            return nil
        default:
            break
        }

        if let target = targetCadence, target.contains("-") {
            let parts = target.components(separatedBy: "-")
            if parts.count == 2,
               let lower = Int(parts[0].trimmingCharacters(in: .whitespaces)),
               let upper = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
                let safeLower = min(safeMaxCadence, max(safeMinCadence, lower))
                let safeUpper = min(safeMaxCadence, max(safeMinCadence, upper))
                return min(safeLower, safeUpper)...max(safeLower, safeUpper)
            }
        } else if let target = targetCadence,
                  let targetInt = Int(target.replacingOccurrences(of: " SPM", with: "").trimmingCharacters(in: .whitespaces)) {
            let safeTarget = min(safeMaxCadence, max(safeMinCadence, targetInt))
            return max(safeMinCadence, safeTarget - 3)...min(safeMaxCadence, safeTarget + 3)
        }

        if let prev = previousCadence, prev > 0 {
            let baseTarget = Int(Double(prev) * 1.05)
            let safeTarget = min(safeMaxCadence, max(prev, baseTarget))
            return max(safeMinCadence, safeTarget - 3)...min(safeMaxCadence, safeTarget + 3)
        }
        return nil
    }

    var computedCadence: String? {
        guard let range = effectiveTargetCadence else { return nil }
        return "\(range.lowerBound)-\(range.upperBound)"
    }

    // MARK: - Interval Geometry

    /// Warm-up length used by the visual timeline.
    var warmUpDurationMinutes: Double {
        if id == .zone2Run {
            return duration == .fiveMinutes ? 5.0 : (duration == .tenMinutes ? 2.0 : (duration == .thirtyMinutes ? 5.0 : 3.0))
        } else if id == .tempoSurges && duration == .tenMinutes {
            return 2.5
        } else if id == .strides && duration == .fifteenMinutes {
            return 5.0
        } else if id == .aerobicFlush || id == .recoveryJog {
            return 0.0
        } else {
            return duration == .fiveMinutes ? 1.0 : (duration == .tenMinutes ? 2.0 : (duration == .thirtyMinutes ? 4.0 : 3.0))
        }
    }

    /// The standard (30-day baseline) interval geometry before any readiness modulation.
    var standardIntervalSpec: IntervalSpec {
        switch id {
        case .cadencePyramids:
            switch duration {
            case .fiveMinutes: return IntervalSpec(iterations: 3, workSeconds: 20, recoverySeconds: 30, isWalk: true)
            case .tenMinutes: return IntervalSpec(iterations: 4, workSeconds: 30, recoverySeconds: 45, isWalk: true)
            case .fifteenMinutes: return IntervalSpec(iterations: 4, workSeconds: 60, recoverySeconds: 90, isWalk: true)
            case .thirtyMinutes: return IntervalSpec(iterations: 6, workSeconds: 90, recoverySeconds: 120, isWalk: true)
            }
        case .rhythmIntervals:
            switch duration {
            case .fiveMinutes: return IntervalSpec(iterations: 3, workSeconds: 20, recoverySeconds: 30, isWalk: false)
            case .tenMinutes: return IntervalSpec(iterations: 4, workSeconds: 30, recoverySeconds: 45, isWalk: false)
            case .fifteenMinutes: return IntervalSpec(iterations: 5, workSeconds: 45, recoverySeconds: 75, isWalk: false)
            case .thirtyMinutes: return IntervalSpec(iterations: 6, workSeconds: 90, recoverySeconds: 120, isWalk: false)
            }
        case .tempoSurges:
            switch duration {
            case .fiveMinutes: return IntervalSpec(iterations: 3, workSeconds: 30, recoverySeconds: 45, isWalk: true)
            case .tenMinutes: return IntervalSpec(iterations: 5, workSeconds: 30, recoverySeconds: 60, isWalk: true)
            case .fifteenMinutes: return IntervalSpec(iterations: 3, workSeconds: 120, recoverySeconds: 120, isWalk: true)
            case .thirtyMinutes: return IntervalSpec(iterations: 4, workSeconds: 180, recoverySeconds: 180, isWalk: true)
            }
        case .strides:
            switch duration {
            case .fiveMinutes: return IntervalSpec(iterations: 4, workSeconds: 15, recoverySeconds: 45, isWalk: true)
            case .tenMinutes: return IntervalSpec(iterations: 4, workSeconds: 15, recoverySeconds: 45, isWalk: true)
            case .fifteenMinutes: return IntervalSpec(iterations: 6, workSeconds: 20, recoverySeconds: 60, isWalk: true)
            case .thirtyMinutes: return IntervalSpec(iterations: 8, workSeconds: 30, recoverySeconds: 90, isWalk: true)
            }
        case .neuromuscularPrimer:
            switch duration {
            case .fiveMinutes: return IntervalSpec(iterations: 3, workSeconds: 15, recoverySeconds: 30, isWalk: true)
            case .tenMinutes: return IntervalSpec(iterations: 4, workSeconds: 20, recoverySeconds: 40, isWalk: true)
            case .fifteenMinutes: return IntervalSpec(iterations: 5, workSeconds: 30, recoverySeconds: 60, isWalk: true)
            case .thirtyMinutes: return IntervalSpec(iterations: 6, workSeconds: 45, recoverySeconds: 90, isWalk: true)
            }
        case .fartlekPrimer:
            switch duration {
            case .fiveMinutes: return IntervalSpec(iterations: 3, workSeconds: 30, recoverySeconds: 30, isWalk: false)
            case .tenMinutes: return IntervalSpec(iterations: 4, workSeconds: 45, recoverySeconds: 45, isWalk: false)
            case .fifteenMinutes: return IntervalSpec(iterations: 5, workSeconds: 60, recoverySeconds: 60, isWalk: false)
            case .thirtyMinutes: return IntervalSpec(iterations: 6, workSeconds: 120, recoverySeconds: 120, isWalk: false)
            }
        case .hillBounds:
            switch duration {
            case .fiveMinutes: return IntervalSpec(iterations: 3, workSeconds: 15, recoverySeconds: 30, isWalk: true)
            case .tenMinutes: return IntervalSpec(iterations: 4, workSeconds: 20, recoverySeconds: 40, isWalk: true)
            case .fifteenMinutes: return IntervalSpec(iterations: 5, workSeconds: 30, recoverySeconds: 60, isWalk: true)
            case .thirtyMinutes: return IntervalSpec(iterations: 6, workSeconds: 45, recoverySeconds: 90, isWalk: true)
            }
        case .aerobicFlush, .recoveryJog:
            return IntervalSpec(iterations: 1, workSeconds: duration.rawValue * 60, recoverySeconds: nil, isWalk: false)
        case .zone2Run:
            if duration == .fiveMinutes {
                return IntervalSpec(iterations: 1, workSeconds: 300, recoverySeconds: nil, isWalk: false)
            }
            let zone2CoolDown = duration == .tenMinutes ? 2.0 : (duration == .thirtyMinutes ? 5.0 : 2.0)
            let steadySeconds = Int((Double(duration.rawValue) - warmUpDurationMinutes - zone2CoolDown) * 60)
            return IntervalSpec(iterations: 1, workSeconds: max(60, steadySeconds), recoverySeconds: nil, isWalk: false)
        }
    }

    /// The interval geometry actually prescribed today, after readiness modulation.
    var intervalSpec: IntervalSpec {
        readinessAdjustedIntervalSpec ?? standardIntervalSpec
    }

    /// Non-nil only when readiness modulation changes the interval geometry.
    /// Volume is scaled (min 2 reps) and recovery is scaled and rounded to the nearest 5 s.
    var readinessAdjustedIntervalSpec: IntervalSpec? {
        guard readinessState.applies(to: id) else { return nil }
        let standard = standardIntervalSpec
        guard let recovery = standard.recoverySeconds else { return nil }
        let reps = max(2, Int((Double(standard.iterations) * readinessState.volumeScale).rounded()))
        let scaledRecovery = Int((Double(recovery) * readinessState.recoveryScale / 5.0).rounded()) * 5
        let adapted = IntervalSpec(
            iterations: reps,
            workSeconds: standard.workSeconds,
            recoverySeconds: scaledRecovery,
            isWalk: standard.isWalk
        )
        return adapted == standard ? nil : adapted
    }

    /// Generates structured workout phases for timeline visualization.
    func generatePhases() -> [WorkoutPhase] {
        var phases: [WorkoutPhase] = []

        let warmUpDurationMinutes = self.warmUpDurationMinutes

        if warmUpDurationMinutes > 0 && !(id == .zone2Run && duration == .fiveMinutes) {
            phases.append(
                WorkoutPhase(
                    id: "warmup",
                    name: "Warm-up",
                    durationSeconds: Int(warmUpDurationMinutes * 60),
                    kind: .warmup
                )
            )
        }

        let spec = intervalSpec
        let iterations = spec.iterations
        let workSeconds = spec.workSeconds
        let recoverySeconds = spec.recoverySeconds
        let isWalk = spec.isWalk

        if let recSec = recoverySeconds {
            for idx in 0..<iterations {
                phases.append(
                    WorkoutPhase(
                        id: "work-\(idx)",
                        name: id == .strides ? "Sprint" : "Work",
                        durationSeconds: workSeconds,
                        kind: .work
                    )
                )
                phases.append(
                    WorkoutPhase(
                        id: "rec-\(idx)",
                        name: isWalk ? "Walk" : "Jog",
                        durationSeconds: recSec,
                        kind: .recovery(isWalk: isWalk)
                    )
                )
            }
        } else {
            phases.append(
                WorkoutPhase(
                    id: "steady",
                    name: id == .zone2Run ? (duration == .fiveMinutes ? "Activation" : "Zone 2 Steady") : "Steady",
                    durationSeconds: workSeconds,
                    kind: duration == .fiveMinutes && id == .zone2Run ? .warmup : .steady
                )
            )
        }

        let coolDownDurationMinutes: Double
        if id == .aerobicFlush || id == .recoveryJog {
            coolDownDurationMinutes = 0.0
        } else if id == .zone2Run {
            coolDownDurationMinutes = duration == .fiveMinutes ? 0.0 : (duration == .tenMinutes ? 2.0 : (duration == .thirtyMinutes ? 5.0 : 2.0))
        } else {
            // Cool-down is anchored to the standard geometry so a readiness-reduced session
            // becomes shorter instead of padding an oversized cool-down.
            let standard = standardIntervalSpec
            let intervalSeconds = standard.iterations * (standard.workSeconds + (standard.recoverySeconds ?? 0))
            let targetTotalSeconds = duration.rawValue * 60
            let remainingSeconds = targetTotalSeconds - Int(warmUpDurationMinutes * 60) - intervalSeconds
            coolDownDurationMinutes = max(0.0, Double(remainingSeconds) / 60.0)
        }

        if coolDownDurationMinutes > 0 {
            phases.append(
                WorkoutPhase(
                    id: "cooldown",
                    name: "Cool-down",
                    durationSeconds: Int(coolDownDurationMinutes * 60),
                    kind: .cooldown
                )
            )
        }

        return phases
    }

    /// Total duration in seconds calculated from all generated phases (warm-up, work/recovery reps, cool-down).
    var totalPhasesDurationSeconds: Int {
        generatePhases().reduce(0) { $0 + $1.durationSeconds }
    }

    /// Formatted duration string for card headers (e.g. "7m 30s drill (Trimmed from 10 min)" or "10 min drill").
    var dynamicDurationTitle: String {
        let totalSec = totalPhasesDurationSeconds
        let minutes = totalSec / 60
        let seconds = totalSec % 60
        let formattedDuration: String
        if seconds > 0 {
            formattedDuration = "\(minutes)m \(seconds)s"
        } else {
            formattedDuration = "\(minutes)m"
        }

        let standardSec = duration.rawValue * 60
        if totalSec < standardSec {
            return "\(formattedDuration) drill (Trimmed from \(duration.title))"
        } else {
            return "\(formattedDuration) drill"
        }
    }
}
