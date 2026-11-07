import Foundation

// MARK: - Phase Generation & Prose Breakdown

extension DrillScheduleCore {
    /// Builds structured workout phases for timeline visualization and Apple Watch WorkoutKit parity.
    public static func buildPhases(
        drillIdentifier: String,
        durationMinutes: Int,
        warmupSeconds: Double,
        cooldownSeconds: Double,
        iterations: Int,
        workSeconds: Double,
        recoverySeconds: Double,
        isWalkRecovery: Bool
    ) -> [DrillPhaseSpec] {
        let normalized = normalizeDrillIdentifier(drillIdentifier)
        var phases: [DrillPhaseSpec] = []

        if warmupSeconds > 0 && !(normalized == "zone2_run" && durationMinutes == 5) {
            phases.append(
                DrillPhaseSpec(
                    id: "warmup",
                    name: "Warm-up",
                    durationSeconds: Int(warmupSeconds),
                    kind: .warmup
                )
            )
        }

        if recoverySeconds > 0 {
            let workName = normalized == "strides" ? "Sprint" : "Work"
            let recName = isWalkRecovery ? "Walk" : "Jog"
            for idx in 0..<iterations {
                phases.append(
                    DrillPhaseSpec(
                        id: "work-\(idx)",
                        name: workName,
                        durationSeconds: Int(workSeconds),
                        kind: .work
                    )
                )
                phases.append(
                    DrillPhaseSpec(
                        id: "rec-\(idx)",
                        name: recName,
                        durationSeconds: Int(recoverySeconds),
                        kind: .recovery(isWalk: isWalkRecovery)
                    )
                )
            }
        } else {
            let steadyName: String
            let steadyKind: DrillPhaseKindCore
            if normalized == "zone2_run" {
                steadyName = durationMinutes == 5 ? "Activation" : "Zone 2 Steady"
                steadyKind = durationMinutes == 5 ? .warmup : .steady
            } else {
                steadyName = "Steady"
                steadyKind = .steady
            }
            phases.append(
                DrillPhaseSpec(
                    id: "steady",
                    name: steadyName,
                    durationSeconds: Int(workSeconds),
                    kind: steadyKind
                )
            )
        }

        if cooldownSeconds > 0 {
            phases.append(
                DrillPhaseSpec(
                    id: "cooldown",
                    name: "Cool-down",
                    durationSeconds: Int(cooldownSeconds),
                    kind: .cooldown
                )
            )
        }

        return phases
    }

    private static func formatPhaseMinutes(_ seconds: Int) -> String {
        let mins = seconds / 60
        let rem = seconds % 60
        if rem == 0 {
            return "\(mins)m"
        } else if rem == 30 {
            return "\(mins).5m"
        } else {
            return "\(mins)m \(rem)s"
        }
    }

    private static func formatWorkRecoveryInterval(_ seconds: Int) -> String {
        if seconds >= 60 && seconds % 60 == 0 {
            return "\(seconds / 60)m"
        }
        return "\(seconds)s"
    }

    /// Structured plain-English phase summary line with exact minute/sub-minute formatting.
    /// (e.g. "1.5m in • 2x (30s / 45s) • 3m out").
    public var preciseStructureSummary: String {
        let warmup = phases.first(where: { $0.kind == .warmup })?.durationSeconds ?? 0
        let cooldown = phases.first(where: { $0.kind == .cooldown })?.durationSeconds ?? 0
        let workReps = phases.filter { $0.kind == .work }
        let repCount = workReps.count
        let repWorkDuration = workReps.first?.durationSeconds ?? 0
        let repRecDuration = phases.first(where: {
            if case .recovery = $0.kind { return true } else { return false }
        })?.durationSeconds ?? 0

        var parts: [String] = []
        if warmup > 0 { parts.append("\(Self.formatPhaseMinutes(warmup)) in") }
        if repCount > 0 {
            let workStr = Self.formatWorkRecoveryInterval(repWorkDuration)
            if repRecDuration > 0 {
                let recStr = Self.formatWorkRecoveryInterval(repRecDuration)
                parts.append("\(repCount)x (\(workStr) / \(recStr))")
            } else {
                parts.append("\(repCount)x \(workStr)")
            }
        } else if let steadyPhase = phases.first(where: { $0.kind == .steady }) {
            let steadyMinutes = Self.formatPhaseMinutes(steadyPhase.durationSeconds)
            parts.append("\(steadyMinutes) steady")
        }
        if cooldown > 0 { parts.append("\(Self.formatPhaseMinutes(cooldown)) out") }
        return parts.joined(separator: " • ")
    }

    public static func adjectiveDuration(_ seconds: Int) -> String {
        if seconds >= 60 && seconds % 60 == 0 { return "\(seconds / 60)-minute" }
        if seconds > 60 && seconds % 30 == 0 { return "\(String(format: "%.1f", Double(seconds) / 60.0))-minute" }
        return "\(seconds)-second"
    }

    public static func nounDuration(_ seconds: Int) -> String {
        if seconds == 60 { return "1 minute" }
        if seconds >= 120 && seconds % 60 == 0 { return "\(seconds / 60) minutes" }
        return "\(seconds) seconds"
    }

    /// Generates structured plain-English breakdown prose dynamically from phase geometry.
    public func generateStructureBreakdownProse() -> String {
        let normalized = Self.normalizeDrillIdentifier(drillIdentifier)

        if readinessState.lowercased() != "productive" {
            var sentences: [String] = []
            if let warmup = phases.first(where: { $0.kind == .warmup }) {
                sentences.append("You’ll start with a \(Self.adjectiveDuration(warmup.durationSeconds)) easy warm-up jog.")
            }
            let work = phases.filter { $0.kind == .work }
            let recovery = phases.first { if case .recovery = $0.kind { return true } else { return false } }
            if let firstWork = work.first {
                let label: String = {
                    switch normalized {
                    case "strides": return "strides"
                    case "hill_bounds": return "uphill bounds"
                    case "fartlek_primer": return "pick-ups"
                    default: return "intervals"
                    }
                }()
                var sentence = "This is followed by \(work.count) sets of \(Self.adjectiveDuration(firstWork.durationSeconds)) \(label)"
                if let rec = recovery, case .recovery(let isWalk) = rec.kind {
                    sentence += ", each paired with \(Self.nounDuration(rec.durationSeconds)) of \(isWalk ? "walk" : "easy jog") recovery"
                }
                sentences.append(sentence + ".")
            }
            if let cooldown = phases.first(where: { $0.kind == .cooldown }) {
                sentences.append("You’ll finish with a \(Self.adjectiveDuration(cooldown.durationSeconds)) cool-down.")
            }
            return sentences.joined(separator: " ")
        }

        switch normalized {
        case "zone2_run":
            if durationMinutes <= 10 {
                return "You’ll execute a single, continuous \(durationMinutes)-minute block of low-intensity movement. There are no sprints or intervals—just a steady, progressive effort to elevate your core temperature before your long miles."
            } else {
                return "You’ll maintain a continuous, conversational pace in Zone 2 for \(durationMinutes) minutes. Keep effort strictly aerobic with relaxed turnover and controlled breathing."
            }
        case "recovery_jog":
            return "You’ll execute a continuous \(durationMinutes)-minute easy shakeout in Zone 1. No intervals or surges—just effortless, smooth steps to release stiffness."
        case "aerobic_flush":
            return "You’ll execute a continuous \(durationMinutes)-minute low-intensity aerobic block. There are no high-intensity spikes—just a steady, relaxed shakeout."
        case "cadence_pyramids":
            switch durationMinutes {
            case 5:
                return "You’ll start with a 1-minute easy warm-up jog. This is followed by 3 sets of 20-second high cadence intervals, paired with 30 seconds of walk recovery."
            case 10:
                return "You’ll start with a 2-minute easy jog warm-up. This is followed by 4 sets of intervals where you run at high cadence for 30 seconds, followed by 45 seconds of walk recovery to reset. You’ll finish with a 3-minute cool-down."
            case 15:
                return "You’ll start with a 3-minute easy jog warm-up. This is followed by 4 sets of 1-minute high cadence intervals, paired with 90 seconds of walk recovery."
            case 20:
                return "You’ll start with a 3-minute easy jog warm-up. This is followed by 4 sets of 90-second high cadence intervals, paired with 90 seconds of walk recovery."
            default:
                let cdMins = Int(cooldownSeconds / 60)
                let cdPhrase = cdMins > 0 ? ", finishing with a \(cdMins)-minute cool-down." : "."
                return "You’ll start with a 4-minute easy jog warm-up. This is followed by 6 sets of 90-second high cadence intervals, paired with 2 minutes of walk recovery\(cdPhrase)"
            }
        case "rhythm_intervals":
            switch durationMinutes {
            case 5:
                return "You’ll start with a 1-minute easy warm-up jog. This is followed by 3 sets of rhythm intervals for 20 seconds, paired with 30 seconds of relaxed recovery jog."
            case 10:
                return "You’ll start with a 2-minute easy warm-up jog. This is followed by 4 sets of rhythm intervals for 30 seconds, paired with 45 seconds of relaxed recovery jog."
            case 15:
                return "You’ll start with a 3-minute easy warm-up jog. This is followed by 5 sets of rhythm intervals for 45 seconds, paired with 75 seconds of relaxed recovery jog."
            case 20:
                return "You’ll start with a 3-minute easy warm-up jog. This is followed by 6 sets of rhythm intervals for 45 seconds, paired with 75 seconds of relaxed recovery jog."
            default:
                let cdMins = Int(cooldownSeconds / 60)
                let cdPhrase = cdMins > 0 ? ", finishing with a \(cdMins)-minute cool-down." : "."
                return "You’ll start with a 4-minute easy warm-up jog. This is followed by 6 sets of rhythm intervals for 90 seconds, paired with 2 minutes of relaxed recovery jog\(cdPhrase)"
            }
        case "tempo_surges":
            switch durationMinutes {
            case 5:
                return "You’ll start with a 1-minute easy warm-up jog. This is followed by 3 sets of brisk intervals for 30 seconds, followed by 45 seconds of walk recovery."
            case 10:
                return "You’ll start with a 2.5-minute easy warm-up jog. This is followed by 5 sets of intervals where you will run at a high, brisk cadence for 30 seconds, followed by a strict 60-second walk to catch your breath."
            case 15:
                return "You’ll start with a 3-minute easy warm-up jog. This is followed by 3 sets of 2-minute tempo surges, paired with 2 minutes of walk recovery."
            case 20:
                return "You’ll start with a 3-minute easy warm-up jog. This is followed by 4 sets of brisk surges for 90 seconds, paired with 2 minutes of walk recovery."
            default:
                let cdMins = Int(cooldownSeconds / 60)
                let cdPhrase = cdMins > 0 ? ", finishing with a \(cdMins)-minute cool-down." : "."
                return "You’ll start with a 4-minute easy warm-up jog. This is followed by 4 sets of 3-minute tempo surges, paired with 3 minutes of walk recovery\(cdPhrase)"
            }
        case "strides":
            switch durationMinutes {
            case 5:
                return "You’ll start with a 1-minute easy jog, followed by 4 short interval sets of 15-second strides and 45-second walks."
            case 10:
                return "You’ll start with a 2-minute easy jog, followed by 4 short interval sets of 15-second strides and 45-second walks."
            case 15:
                return "You’ll start with a 5-minute easy jog to warm up the joints, followed by 6 short interval sets. In each interval, you’ll accelerate into a 20-second sprint, followed immediately by a 60-second walk to let your heart rate drop completely."
            default:
                let cdMins = Int(cooldownSeconds / 60)
                let cdPhrase = cdMins > 0 ? ", finishing with a \(cdMins)-minute cool-down." : "."
                return "You’ll start with a 5-minute easy jog, followed by 8 sets of 30-second strides and 90-second walks\(cdPhrase)"
            }
        case "neuromuscular_primer":
            switch durationMinutes {
            case 5:
                return "You’ll start with a 1-minute easy warm-up jog. This is followed by 3 sets of 15-second fast-feet bursts, paired with 30 seconds of walk recovery."
            case 10:
                return "You’ll start with a 2-minute easy warm-up jog. This is followed by 4 sets of 20-second fast-feet bursts, paired with 40 seconds of walk recovery."
            case 15:
                return "You’ll start with a 3-minute easy warm-up jog. This is followed by 5 sets of 30-second fast-feet bursts, paired with 60 seconds of walk recovery."
            default:
                let cdMins = Int(cooldownSeconds / 60)
                let cdPhrase = cdMins > 0 ? ", finishing with a \(cdMins)-minute cool-down." : "."
                return "You’ll start with a 4-minute easy warm-up jog. This is followed by 6 sets of 45-second fast-feet bursts, paired with 90 seconds of walk recovery\(cdPhrase)"
            }
        case "hill_bounds":
            switch durationMinutes {
            case 5:
                return "You’ll start with a 1-minute warm-up jog. This is followed by 3 sets of 15-second uphill bounds, followed by 30 seconds of walk recovery."
            case 10:
                return "You’ll start with a 2-minute warm-up jog. This is followed by 4 sets of 20-second uphill bounds, followed by 40 seconds of walk recovery."
            case 15:
                return "You’ll start with a 3-minute warm-up jog. This is followed by 5 sets of 30-second uphill bounds, followed by 60 seconds of walk recovery."
            default:
                let cdMins = Int(cooldownSeconds / 60)
                let cdPhrase = cdMins > 0 ? ", finishing with a \(cdMins)-minute cool-down." : "."
                return "You’ll start with a 4-minute warm-up jog. This is followed by 6 sets of 45-second uphill bounds, followed by 90 seconds of walk recovery\(cdPhrase)"
            }
        case "fartlek_primer":
            switch durationMinutes {
            case 5:
                return "You’ll start with a 1-minute warm-up jog. This is followed by 3 sets of 30-second pick-ups, alternating with 30 seconds of relaxed recovery."
            case 10:
                return "You’ll start with a 2-minute warm-up jog. This is followed by 4 sets of 45-second pick-ups, alternating with 45 seconds of relaxed recovery."
            case 15:
                return "You’ll start with a 3-minute warm-up jog. This is followed by 5 sets of 1-minute pick-ups, alternating with 1 minute of relaxed recovery."
            case 20:
                return "You’ll start with a 3-minute warm-up jog. This is followed by 6 sets of 1-minute pick-ups, alternating with 1 minute of relaxed recovery."
            default:
                let cdMins = Int(cooldownSeconds / 60)
                let cdPhrase = cdMins > 0 ? ", finishing with a \(cdMins)-minute cool-down." : "."
                return "You’ll start with a 4-minute warm-up jog. This is followed by 6 sets of 2-minute pick-ups, alternating with 2 minutes of relaxed recovery\(cdPhrase)"
            }
        default:
            return "You’ll execute a structured \(durationMinutes)-minute running session."
        }
    }
}
