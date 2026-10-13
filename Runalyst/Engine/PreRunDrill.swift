import Foundation
import SwiftUI
import HealthKit
#if canImport(WorkoutKit)
@preconcurrency import WorkoutKit
#endif

extension PreRunDrill {
    static func iconName(for drillId: String?, title: String? = nil) -> String {
        if let idStr = drillId, let matched = PreRunDrillId(rawValue: idStr) {
            return matched.iconName
        }
        let lower = (title ?? drillId ?? "").lowercased()
        if lower.contains("cadence") {
            return "shoeprints.fill"
        } else if lower.contains("interval") || lower.contains("rhythm") || lower.contains("clock") {
            return "clock.fill"
        } else if lower.contains("surge") || lower.contains("tempo") {
            return "bolt.fill"
        } else if lower.contains("stride") {
            return "figure.run"
        } else if lower.contains("hill") || lower.contains("bound") {
            return "mountain.2.fill"
        } else if lower.contains("flush") || lower.contains("aerobic") {
            return "lungs.fill"
        } else if lower.contains("zone 2") || lower.contains("zone2") || lower.contains("base builder") {
            return "heart.fill"
        } else if lower.contains("recovery") || lower.contains("jog") || lower.contains("shakeout") {
            return "figure.walk"
        } else if lower.contains("fartlek") {
            return "waveform.path.ecg"
        } else if lower.contains("neuro") {
            return "brain.head.profile"
        }
        return "shoeprints.fill"
    }

    static func iconColor(for drillId: String?, title: String? = nil) -> Color {
        if let idStr = drillId, let matched = PreRunDrillId(rawValue: idStr) {
            return matched.iconColor
        }
        let lower = (title ?? drillId ?? "").lowercased()
        if lower.contains("cadence") {
            return .blue
        } else if lower.contains("interval") || lower.contains("rhythm") {
            return .purple
        } else if lower.contains("surge") || lower.contains("tempo") {
            return .orange
        } else if lower.contains("stride") {
            return .green
        } else if lower.contains("hill") || lower.contains("bound") {
            return .brown
        } else if lower.contains("flush") {
            return .teal
        } else if lower.contains("zone 2") || lower.contains("zone2") || lower.contains("base builder") {
            return .red
        } else if lower.contains("recovery") || lower.contains("jog") || lower.contains("shakeout") {
            return .mint
        } else if lower.contains("fartlek") {
            return .pink
        } else if lower.contains("neuro") {
            return .indigo
        }
        return .orange
    }
}

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

    func workString(for customDuration: DrillDuration) -> String {
        switch id {
        case .cadencePyramids:
            switch customDuration {
            case .fiveMinutes: return "3 x 20 sec work"
            case .tenMinutes: return "4 x 30 sec work"
            case .fifteenMinutes: return "4 x 1 min work"
            case .thirtyMinutes: return "6 x 90 sec work"
            }
        case .rhythmIntervals:
            switch customDuration {
            case .fiveMinutes: return "3 x 20 sec work"
            case .tenMinutes: return "4 x 30 sec work"
            case .fifteenMinutes: return "5 x 45 sec work"
            case .thirtyMinutes: return "6 x 90 sec work"
            }
        case .tempoSurges:
            switch customDuration {
            case .fiveMinutes: return "3 x 30 sec work"
            case .tenMinutes: return "5 x 30 sec work"
            case .fifteenMinutes: return "3 x 2 min work"
            case .thirtyMinutes: return "4 x 3 min work"
            }
        case .strides:
            switch customDuration {
            case .fiveMinutes: return "4 x 15 sec strides"
            case .tenMinutes: return "4 x 15 sec strides"
            case .fifteenMinutes: return "6 x 20 sec strides"
            case .thirtyMinutes: return "8 x 30 sec strides"
            }
        case .neuromuscularPrimer:
            switch customDuration {
            case .fiveMinutes: return "3 x 15 sec work"
            case .tenMinutes: return "4 x 20 sec work"
            case .fifteenMinutes: return "5 x 30 sec work"
            case .thirtyMinutes: return "6 x 45 sec work"
            }
        case .aerobicFlush:
            return "\(customDuration.rawValue) min steady"
        case .fartlekPrimer:
            switch customDuration {
            case .fiveMinutes: return "3 x 30 sec work"
            case .tenMinutes: return "4 x 45 sec work"
            case .fifteenMinutes: return "5 x 1 min work"
            case .thirtyMinutes: return "6 x 2 min work"
            }
        case .hillBounds:
            switch customDuration {
            case .fiveMinutes: return "3 x 15 sec work"
            case .tenMinutes: return "4 x 20 sec work"
            case .fifteenMinutes: return "5 x 30 sec work"
            case .thirtyMinutes: return "6 x 45 sec work"
            }
        case .recoveryJog:
            return "\(customDuration.rawValue) min easy"
        case .zone2Run:
            return "\(customDuration.rawValue) min Zone 2 steady"
        }
    }

    func recoveryString(for customDuration: DrillDuration) -> String {
        switch id {
        case .cadencePyramids:
            switch customDuration {
            case .fiveMinutes: return "30 sec walk recovery"
            case .tenMinutes: return "45 sec walk recovery"
            case .fifteenMinutes: return "90 sec walk recovery"
            case .thirtyMinutes: return "2 min walk recovery"
            }
        case .rhythmIntervals:
            switch customDuration {
            case .fiveMinutes: return "30 sec easy jog recovery"
            case .tenMinutes: return "45 sec easy jog recovery"
            case .fifteenMinutes: return "75 sec easy jog recovery"
            case .thirtyMinutes: return "2 min easy jog recovery"
            }
        case .tempoSurges:
            switch customDuration {
            case .fiveMinutes: return "45 sec walk recovery"
            case .tenMinutes: return "60 sec walk recovery"
            case .fifteenMinutes: return "2 min walk recovery"
            case .thirtyMinutes: return "3 min walk recovery"
            }
        case .strides:
            switch customDuration {
            case .fiveMinutes: return "45 sec walk recovery"
            case .tenMinutes: return "45 sec walk recovery"
            case .fifteenMinutes: return "60 sec walk recovery"
            case .thirtyMinutes: return "90 sec walk recovery"
            }
        case .neuromuscularPrimer:
            switch customDuration {
            case .fiveMinutes: return "30 sec walk recovery"
            case .tenMinutes: return "40 sec walk recovery"
            case .fifteenMinutes: return "60 sec walk recovery"
            case .thirtyMinutes: return "90 sec walk recovery"
            }
        case .aerobicFlush:
            return "No intervals"
        case .fartlekPrimer:
            switch customDuration {
            case .fiveMinutes: return "30 sec easy recovery"
            case .tenMinutes: return "45 sec easy recovery"
            case .fifteenMinutes: return "1 min easy recovery"
            case .thirtyMinutes: return "2 min easy recovery"
            }
        case .hillBounds:
            switch customDuration {
            case .fiveMinutes: return "30 sec walk recovery"
            case .tenMinutes: return "40 sec walk recovery"
            case .fifteenMinutes: return "60 sec walk recovery"
            case .thirtyMinutes: return "90 sec walk recovery"
            }
        case .recoveryJog:
            return "No intervals"
        case .zone2Run:
            return "No intervals"
        }
    }

    var defaultWorkString: String {
        let base = workString(for: duration)
        guard let adapted = readinessAdjustedIntervalSpec else { return base }
        // "6 x 20 sec strides" -> suffix "strides"
        let suffix = base.split(separator: " ").dropFirst(4).joined(separator: " ")
        return "\(adapted.iterations) x \(Self.formatShortDuration(adapted.workSeconds)) \(suffix)"
    }

    var defaultRecoveryString: String {
        let base = recoveryString(for: duration)
        guard let adapted = readinessAdjustedIntervalSpec, let recovery = adapted.recoverySeconds else { return base }
        // "60 sec walk recovery" -> suffix "walk recovery"
        let suffix = base.split(separator: " ").dropFirst(2).joined(separator: " ")
        return "\(Self.formatShortDuration(recovery)) \(suffix)"
    }

    static func formatShortDuration(_ seconds: Int) -> String {
        if seconds >= 120 && seconds % 60 == 0 {
            return "\(seconds / 60) min"
        }
        return "\(seconds) sec"
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

    var defaultEffortString: String {
        switch id {
        case .recoveryJog, .aerobicFlush: return "Zone 1 Active Recovery"
        case .zone2Run: return "Zone 2 Aerobic"
        case .cadencePyramids, .rhythmIntervals: return "Moderate / Zone 3"
        case .tempoSurges, .fartlekPrimer: return "Hard / Zone 4"
        case .strides, .neuromuscularPrimer, .hillBounds: return "Sprint / Zone 5"
        }
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

    #if canImport(WorkoutKit)
    @available(iOS 17.0, *)
    func buildWorkoutPlan() -> WorkoutPlan {
        var workout = CustomWorkout(activity: .running, location: .outdoor, displayName: id.title)

        let warmUpDuration: Double
        let coolDownDuration: Double

        if id == .zone2Run {
            warmUpDuration = duration == .fiveMinutes ? 0.0 : (duration == .tenMinutes ? 2.0 : (duration == .thirtyMinutes ? 5.0 : 3.0))
            coolDownDuration = duration == .fiveMinutes ? 0.0 : (duration == .tenMinutes ? 2.0 : (duration == .thirtyMinutes ? 5.0 : 2.0))
        } else if id == .tempoSurges && duration == .tenMinutes {
            warmUpDuration = 2.5
            coolDownDuration = 0.0
        } else if id == .strides && duration == .fifteenMinutes {
            warmUpDuration = 5.0
            coolDownDuration = 2.0
        } else if id == .aerobicFlush || id == .recoveryJog {
            warmUpDuration = 0.0
            coolDownDuration = 0.0
        } else {
            warmUpDuration = duration == .fiveMinutes ? 1.0 : (duration == .tenMinutes ? 2.0 : (duration == .thirtyMinutes ? 4.0 : 3.0))
            coolDownDuration = duration == .fiveMinutes ? 0.5 : (duration == .tenMinutes ? 1.0 : (duration == .thirtyMinutes ? 3.0 : 2.0))
        }

        let warmUp = warmUpDuration > 0 ? WorkoutStep(goal: .time(warmUpDuration, .minutes)) : nil
        let coolDown = coolDownDuration > 0 ? WorkoutStep(goal: .time(coolDownDuration, .minutes)) : nil

        var alert: (any WorkoutAlert)?
        if let target = effectiveTargetCadence {
            alert = CadenceRangeAlert.cadence(Double(target.lowerBound)...Double(target.upperBound))
        } else if id == .aerobicFlush || id == .recoveryJog {
            alert = HeartRateZoneAlert(zone: 1)
        } else if id == .zone2Run {
            alert = HeartRateZoneAlert(zone: 2)
        }

        var iterations = 1
        var workGoal = WorkoutGoal.open
        var recoveryGoal: WorkoutGoal?

        switch id {
        case .cadencePyramids:
            switch duration {
            case .fiveMinutes:
                iterations = 3
                workGoal = .time(20, .seconds)
                recoveryGoal = .time(30, .seconds)
            case .tenMinutes:
                iterations = 4
                workGoal = .time(30, .seconds)
                recoveryGoal = .time(45, .seconds)
            case .fifteenMinutes:
                iterations = 4
                workGoal = .time(1, .minutes)
                recoveryGoal = .time(90, .seconds)
            case .thirtyMinutes:
                iterations = 6
                workGoal = .time(90, .seconds)
                recoveryGoal = .time(2, .minutes)
            }
        case .rhythmIntervals:
            switch duration {
            case .fiveMinutes:
                iterations = 3
                workGoal = .time(20, .seconds)
                recoveryGoal = .time(30, .seconds)
            case .tenMinutes:
                iterations = 4
                workGoal = .time(30, .seconds)
                recoveryGoal = .time(45, .seconds)
            case .fifteenMinutes:
                iterations = 5
                workGoal = .time(45, .seconds)
                recoveryGoal = .time(75, .seconds)
            case .thirtyMinutes:
                iterations = 6
                workGoal = .time(90, .seconds)
                recoveryGoal = .time(2, .minutes)
            }
        case .tempoSurges:
            switch duration {
            case .fiveMinutes:
                iterations = 3
                workGoal = .time(30, .seconds)
                recoveryGoal = .time(45, .seconds)
            case .tenMinutes:
                iterations = 5
                workGoal = .time(30, .seconds)
                recoveryGoal = .time(60, .seconds)
            case .fifteenMinutes:
                iterations = 3
                workGoal = .time(2, .minutes)
                recoveryGoal = .time(2, .minutes)
            case .thirtyMinutes:
                iterations = 4
                workGoal = .time(3, .minutes)
                recoveryGoal = .time(3, .minutes)
            }
        case .strides:
            switch duration {
            case .fiveMinutes:
                iterations = 4
                workGoal = .time(15, .seconds)
                recoveryGoal = .time(45, .seconds)
            case .tenMinutes:
                iterations = 4
                workGoal = .time(15, .seconds)
                recoveryGoal = .time(45, .seconds)
            case .fifteenMinutes:
                iterations = 6
                workGoal = .time(20, .seconds)
                recoveryGoal = .time(60, .seconds)
            case .thirtyMinutes:
                iterations = 8
                workGoal = .time(30, .seconds)
                recoveryGoal = .time(90, .seconds)
            }
        case .neuromuscularPrimer:
            switch duration {
            case .fiveMinutes:
                iterations = 3
                workGoal = .time(15, .seconds)
                recoveryGoal = .time(30, .seconds)
            case .tenMinutes:
                iterations = 4
                workGoal = .time(20, .seconds)
                recoveryGoal = .time(40, .seconds)
            case .fifteenMinutes:
                iterations = 5
                workGoal = .time(30, .seconds)
                recoveryGoal = .time(60, .seconds)
            case .thirtyMinutes:
                iterations = 6
                workGoal = .time(45, .seconds)
                recoveryGoal = .time(90, .seconds)
            }
        case .aerobicFlush:
            iterations = 1
            workGoal = .time(Double(duration.rawValue), .minutes)
            recoveryGoal = nil
        case .fartlekPrimer:
            switch duration {
            case .fiveMinutes:
                iterations = 3
                workGoal = .time(30, .seconds)
                recoveryGoal = .time(30, .seconds)
            case .tenMinutes:
                iterations = 4
                workGoal = .time(45, .seconds)
                recoveryGoal = .time(45, .seconds)
            case .fifteenMinutes:
                iterations = 5
                workGoal = .time(1, .minutes)
                recoveryGoal = .time(1, .minutes)
            case .thirtyMinutes:
                iterations = 6
                workGoal = .time(2, .minutes)
                recoveryGoal = .time(2, .minutes)
            }
        case .hillBounds:
            switch duration {
            case .fiveMinutes:
                iterations = 3
                workGoal = .time(15, .seconds)
                recoveryGoal = .time(30, .seconds)
            case .tenMinutes:
                iterations = 4
                workGoal = .time(20, .seconds)
                recoveryGoal = .time(40, .seconds)
            case .fifteenMinutes:
                iterations = 5
                workGoal = .time(30, .seconds)
                recoveryGoal = .time(60, .seconds)
            case .thirtyMinutes:
                iterations = 6
                workGoal = .time(45, .seconds)
                recoveryGoal = .time(90, .seconds)
            }
        case .recoveryJog:
            iterations = 1
            workGoal = .time(Double(duration.rawValue), .minutes)
            recoveryGoal = nil
        case .zone2Run:
            iterations = 1
            workGoal = .time(Double(duration.rawValue), .minutes)
            recoveryGoal = nil
        }

        // Readiness modulation (acute fatigue / deload): override volume and recovery so the
        // Apple Watch session matches the readout timeline exactly.
        if let adapted = readinessAdjustedIntervalSpec {
            iterations = adapted.iterations
            workGoal = .time(Double(adapted.workSeconds), .seconds)
            recoveryGoal = adapted.recoverySeconds.map { .time(Double($0), .seconds) }
        }

        let workStep = WorkoutStep(goal: workGoal, alert: alert)

        if let rec = recoveryGoal {
            let recStep = WorkoutStep(goal: rec)
            workout.blocks = [IntervalBlock(steps: [IntervalStep(.work, step: workStep), IntervalStep(.recovery, step: recStep)], iterations: iterations)]
        } else {
            workout.blocks = [IntervalBlock(steps: [IntervalStep(.work, step: workStep)], iterations: iterations)]
        }

        workout.warmup = warmUp
        workout.cooldown = coolDown

        return WorkoutPlan(.custom(workout))
    }
    #endif
}
