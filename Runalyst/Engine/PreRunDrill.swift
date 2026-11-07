import Foundation
import SwiftUI
import HealthKit
import RunalystCore

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
    /// Whether the custom workout is configured for Indoor (Treadmill) or Outdoor execution.
    let isIndoor: Bool
    /// Optional custom display name for the WorkoutKit plan (e.g. "Easy Aerobic Base Run").
    let customDisplayName: String?

    init(
        id: PreRunDrillId,
        previousCadence: Int? = nil,
        targetCadence: String? = nil,
        duration: DrillDuration? = nil,
        hapticMode: HapticFeedbackMode = .on,
        readinessState: ReadinessState = .productive,
        isIndoor: Bool = false,
        customDisplayName: String? = nil
    ) {
        self.id = id
        self.previousCadence = previousCadence
        self.targetCadence = targetCadence
        self.duration = duration ?? id.defaultDuration
        self.hapticMode = hapticMode
        self.readinessState = readinessState
        self.isIndoor = isIndoor
        self.customDisplayName = customDisplayName
    }

    // Mathematical variables for constraints
    private let safeMaxCadence = 185
    private let safeMinCadence = 140

    /// Normalizes cadence target strings such as "155–161 SPM (Adapted)" into a clean "155-161" format.
    static func normalizeCadenceTargetString(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "(Adapted)", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Adapted", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "SPM", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var effectiveTargetCadence: ClosedRange<Int>? {
        // Recovery / flush / base builder drills do not use cadence turnover alerts
        switch id {
        case .aerobicFlush, .recoveryJog, .zone2Run:
            return nil
        default:
            break
        }

        if let rawTarget = targetCadence {
            let cleanTarget = Self.normalizeCadenceTargetString(rawTarget)
            if cleanTarget.contains("-") {
                let parts = cleanTarget.components(separatedBy: "-")
                if parts.count == 2,
                   let lower = Int(parts[0].trimmingCharacters(in: .whitespaces)),
                   let upper = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
                    let safeLower = min(safeMaxCadence, max(safeMinCadence, lower))
                    let safeUpper = min(safeMaxCadence, max(safeMinCadence, upper))
                    return min(safeLower, safeUpper)...max(safeLower, safeUpper)
                }
            } else if let targetInt = Int(cleanTarget) {
                let safeTarget = min(safeMaxCadence, max(safeMinCadence, targetInt))
                return max(safeMinCadence, safeTarget - 3)...min(safeMaxCadence, safeTarget + 3)
            }
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

    // MARK: - Core Schedule

    var coreSchedule: DrillScheduleCore {
        DrillScheduleCore.schedule(
            for: id.rawValue,
            durationMinutes: duration.rawValue,
            readinessState: readinessState.rawValue
        )
    }

    var standardCoreSchedule: DrillScheduleCore {
        DrillScheduleCore.schedule(
            for: id.rawValue,
            durationMinutes: duration.rawValue,
            readinessState: "productive"
        )
    }

    // MARK: - Interval Geometry

    /// Warm-up length used by the visual timeline.
    var warmUpDurationMinutes: Double {
        coreSchedule.warmupSeconds / 60.0
    }

    /// The standard (30-day baseline) interval geometry before any readiness modulation.
    var standardIntervalSpec: IntervalSpec {
        IntervalSpec(
            iterations: standardCoreSchedule.iterations,
            workSeconds: Int(standardCoreSchedule.workSeconds),
            recoverySeconds: standardCoreSchedule.recoverySeconds > 0 ? Int(standardCoreSchedule.recoverySeconds) : nil,
            isWalk: standardCoreSchedule.isWalkRecovery
        )
    }

    /// The interval geometry actually prescribed today, after readiness modulation.
    var intervalSpec: IntervalSpec {
        readinessAdjustedIntervalSpec ?? standardIntervalSpec
    }

    /// Non-nil only when readiness modulation changes the interval geometry.
    /// Volume is scaled (min 2 reps) and recovery is scaled and rounded to the nearest 5 s.
    var readinessAdjustedIntervalSpec: IntervalSpec? {
        guard readinessState.applies(to: id) else { return nil }
        guard coreSchedule.iterations != standardCoreSchedule.iterations ||
            coreSchedule.workSeconds != standardCoreSchedule.workSeconds ||
            coreSchedule.recoverySeconds != standardCoreSchedule.recoverySeconds else {
            return nil
        }
        return IntervalSpec(
            iterations: coreSchedule.iterations,
            workSeconds: Int(coreSchedule.workSeconds),
            recoverySeconds: coreSchedule.recoverySeconds > 0 ? Int(coreSchedule.recoverySeconds) : nil,
            isWalk: coreSchedule.isWalkRecovery
        )
    }

    /// Cool-down length in minutes, shared between the visual timeline and the Apple Watch WorkoutPlan.
    var coolDownDurationMinutes: Double {
        coreSchedule.cooldownSeconds / 60.0
    }

    /// Generates structured workout phases for timeline visualization.
    func generatePhases() -> [WorkoutPhase] {
        coreSchedule.phases.map { phase in
            WorkoutPhase(
                id: phase.id,
                name: phase.name,
                durationSeconds: phase.durationSeconds,
                kind: WorkoutPhase.PhaseKind(core: phase.kind)
            )
        }
    }

    /// Total duration in seconds calculated from all generated phases (warm-up, work/recovery reps, cool-down).
    var totalPhasesDurationSeconds: Int {
        coreSchedule.totalDurationSeconds
    }

    /// Formatted total duration based strictly on generated phases (e.g. "4m 10s" or "5 min").
    var formattedPhasesDuration: String {
        coreSchedule.formattedTotalDuration
    }

    /// Structured plain-English phase summary line with exact minute/sub-minute formatting
    /// (e.g. "1m in • 2x (20s / 30s) • 1.5m out").
    var preciseStructureSummary: String {
        coreSchedule.preciseStructureSummary
    }

    /// Formatted duration string for card headers (e.g. "7m drill (Trimmed from 10 min)" or "10 min drill").
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
