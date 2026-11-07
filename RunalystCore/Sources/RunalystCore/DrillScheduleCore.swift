import Foundation

// MARK: - Drill Phase Specification

/// Mathematical phase category for workout interval geometry.
public enum DrillPhaseKindCore: Sendable, Equatable {
    case warmup
    case work
    case recovery(isWalk: Bool)
    case steady
    case cooldown
}

/// A discrete structural phase of a prescribed workout.
public struct DrillPhaseSpec: Sendable, Equatable {
    public let id: String
    public let name: String
    public let durationSeconds: Int
    public let kind: DrillPhaseKindCore

    public init(id: String, name: String, durationSeconds: Int, kind: DrillPhaseKindCore) {
        self.id = id
        self.name = name
        self.durationSeconds = durationSeconds
        self.kind = kind
    }
}

// MARK: - Drill Schedule Specification

/// Canonical structural specification for a prescribed Runalyst corrective drill archetype.
public struct DrillScheduleCore: Sendable, Equatable {
    public let drillIdentifier: String
    public let durationMinutes: Int
    public let warmupSeconds: Double
    public let cooldownSeconds: Double
    public let iterations: Int
    public let workSeconds: Double
    public let recoverySeconds: Double
    public let isWalkRecovery: Bool
    public let readinessState: String
    public let phases: [DrillPhaseSpec]

    public var expectedTotalDuration: Double {
        warmupSeconds + Double(iterations) * (workSeconds + recoverySeconds) + cooldownSeconds
    }

    public var totalDurationSeconds: Int {
        if !phases.isEmpty {
            return phases.reduce(0) { $0 + $1.durationSeconds }
        }
        return Int(expectedTotalDuration)
    }

    public var formattedTotalDuration: String {
        let total = totalDurationSeconds
        let mins = total / 60
        let secs = total % 60
        if secs == 0 {
            return "\(mins) min"
        } else {
            return "\(mins)m \(secs)s"
        }
    }

    public init(
        drillIdentifier: String,
        durationMinutes: Int,
        warmupSeconds: Double,
        cooldownSeconds: Double,
        iterations: Int,
        workSeconds: Double,
        recoverySeconds: Double,
        isWalkRecovery: Bool? = nil,
        readinessState: String = "productive",
        phases: [DrillPhaseSpec]? = nil
    ) {
        self.drillIdentifier = drillIdentifier
        self.durationMinutes = durationMinutes
        self.warmupSeconds = warmupSeconds
        self.cooldownSeconds = cooldownSeconds
        self.iterations = iterations
        self.workSeconds = workSeconds
        self.recoverySeconds = recoverySeconds
        let isWalk = isWalkRecovery ?? Self.defaultIsWalkRecovery(for: drillIdentifier)
        self.isWalkRecovery = isWalk
        self.readinessState = readinessState
        if let providedPhases = phases {
            self.phases = providedPhases
        } else {
            self.phases = Self.buildPhases(
                drillIdentifier: drillIdentifier,
                durationMinutes: durationMinutes,
                warmupSeconds: warmupSeconds,
                cooldownSeconds: cooldownSeconds,
                iterations: iterations,
                workSeconds: workSeconds,
                recoverySeconds: recoverySeconds,
                isWalkRecovery: isWalk
            )
        }
    }

    /// Resolves an integer minute count to the closest canonical DrillDuration bucket [5, 10, 15, 20, 30, 35, 40, 50].
    /// Note: 7 and 8 minute prescriptions represent trimmed 10-minute drills, and map to 10.
    public static func canonicalTemplateMinutes(forRawMinutes raw: Int) -> Int {
        let canonical = [5, 10, 15, 20, 30, 35, 40, 50]
        if canonical.contains(raw) {
            return raw
        }
        if raw >= 7 && raw <= 8 {
            return 10
        }
        return canonical.min(by: { abs($0 - raw) < abs($1 - raw) }) ?? 30
    }

    /// Default recovery mode (walk vs jog) per drill archetype.
    public static func defaultIsWalkRecovery(for drillIdentifier: String) -> Bool {
        let normalized = normalizeDrillIdentifier(drillIdentifier)
        switch normalized {
        case "cadence_pyramids", "tempo_surges", "strides", "neuromuscular_primer", "hill_bounds":
            return true
        case "rhythm_intervals", "fartlek_primer", "aerobic_flush", "recovery_jog", "zone2_run":
            return false
        default:
            return true
        }
    }

    /// Normalizes varied casing and historical raw string representations of drill archetypes.
    public static func normalizeDrillIdentifier(_ identifier: String) -> String {
        switch identifier {
        case "zone_2_run", "zone2_run", "zone2Run":
            return "zone2_run"
        case "posture_check", "tempoSurges":
            return "tempo_surges"
        case "cadencePyramids":
            return "cadence_pyramids"
        case "rhythmIntervals":
            return "rhythm_intervals"
        case "neuromuscularPrimer":
            return "neuromuscular_primer"
        case "fartlekPrimer":
            return "fartlek_primer"
        case "hillBounds":
            return "hill_bounds"
        case "recoveryJog":
            return "recovery_jog"
        case "aerobicFlush", "zone_1_recovery_flush", "zone_1_active_recovery_flush", "recovery_flush":
            return "aerobic_flush"
        default:
            return identifier
        }
    }

    public func matches(
        workoutDuration: Double,
        detectedIterations: Int,
        avgWorkDuration: Double,
        avgRecoveryDuration: Double
    ) -> Bool {
        if iterations >= 4 {
            guard abs(detectedIterations - iterations) <= 1 else { return false }
        } else {
            guard detectedIterations == iterations else { return false }
        }

        let minDuration: Double
        let maxDuration: Double
        switch durationMinutes {
        case ..<10:
            minDuration = 180.0
            maxDuration = 600.0
        case 10..<15:
            minDuration = 360.0
            maxDuration = drillIdentifier == "tempo_surges" ? 1500.0 : 1200.0
        case 15..<25:
            minDuration = 600.0
            maxDuration = drillIdentifier == "tempo_surges" ? 1800.0 : 1680.0
        default:
            minDuration = 1200.0
            maxDuration = drillIdentifier == "tempo_surges" ? Double(durationMinutes * 60) * 1.5 : Double(durationMinutes * 60) * 1.4
        }
        guard workoutDuration >= minDuration && workoutDuration <= maxDuration else { return false }

        let workTolerance = max(18.0, workSeconds * 0.30)
        guard abs(avgWorkDuration - workSeconds) <= workTolerance else { return false }

        if recoverySeconds > 0 {
            if drillIdentifier == "tempo_surges" {
                guard avgRecoveryDuration >= 45.0 && avgRecoveryDuration <= 270.0 else { return false }
            } else {
                let recTolerance = max(20.0, recoverySeconds * 0.35)
                guard abs(avgRecoveryDuration - recoverySeconds) <= recTolerance else { return false }
            }
        }
        return true
    }

    public static func schedule(for drillIdentifier: String, durationMinutes: Int) -> DrillScheduleCore {
        schedule(for: drillIdentifier, durationMinutes: durationMinutes, readinessState: "productive")
    }

    public static func schedule(
        for drillIdentifier: String,
        durationMinutes: Int,
        readinessState: String = "productive"
    ) -> DrillScheduleCore {
        let normalized = normalizeDrillIdentifier(drillIdentifier)
        let canonicalMins = canonicalTemplateMinutes(forRawMinutes: durationMinutes)
        let isAcuteFatigue = readinessState.lowercased() == "acutefatigue" || readinessState.lowercased() == "acute_fatigue"

        if normalized == "aerobic_flush" || normalized == "recovery_jog" {
            return DrillScheduleCore(
                drillIdentifier: drillIdentifier,
                durationMinutes: canonicalMins,
                warmupSeconds: 0,
                cooldownSeconds: 0,
                iterations: 1,
                workSeconds: Double(canonicalMins * 60),
                recoverySeconds: 0,
                isWalkRecovery: false,
                readinessState: readinessState
            )
        }

        if normalized == "zone2_run" {
            let warmup: Double
            let cooldown: Double
            if canonicalMins == 5 {
                warmup = 300.0
                cooldown = 0.0
            } else if canonicalMins == 10 {
                warmup = 120.0
                cooldown = 120.0
            } else if canonicalMins >= 30 {
                warmup = 300.0
                cooldown = 300.0
            } else {
                warmup = 180.0
                cooldown = 120.0
            }
            let steadySeconds: Double
            if canonicalMins == 5 {
                steadySeconds = 300.0
            } else {
                steadySeconds = max(60.0, Double(canonicalMins * 60) - warmup - cooldown)
            }
            return DrillScheduleCore(
                drillIdentifier: drillIdentifier,
                durationMinutes: canonicalMins,
                warmupSeconds: warmup,
                cooldownSeconds: cooldown,
                iterations: 1,
                workSeconds: steadySeconds,
                recoverySeconds: 0,
                isWalkRecovery: false,
                readinessState: readinessState
            )
        }

        if isAcuteFatigue && (normalized == "cadence_pyramids" || normalized == "rhythm_intervals") && canonicalMins == 10 {
            let isWalk = defaultIsWalkRecovery(for: normalized)
            return DrillScheduleCore(
                drillIdentifier: drillIdentifier,
                durationMinutes: canonicalMins,
                warmupSeconds: 90,
                cooldownSeconds: 180,
                iterations: 2,
                workSeconds: 30,
                recoverySeconds: 45,
                isWalkRecovery: isWalk,
                readinessState: readinessState
            )
        }

        let warmupSeconds: Double
        if normalized == "tempo_surges" && canonicalMins == 10 {
            warmupSeconds = 150.0
        } else if normalized == "strides" && canonicalMins == 15 {
            warmupSeconds = 300.0
        } else if canonicalMins == 5 {
            warmupSeconds = 60.0
        } else if canonicalMins == 10 {
            warmupSeconds = 120.0
        } else if canonicalMins >= 30 {
            warmupSeconds = 240.0
        } else {
            warmupSeconds = 180.0
        }

        let standardIterations: Int
        let standardWorkSeconds: Double
        let standardRecoverySeconds: Double
        let isWalk = defaultIsWalkRecovery(for: normalized)

        switch normalized {
        case "cadence_pyramids":
            switch canonicalMins {
            case ..<10:
                standardIterations = 3; standardWorkSeconds = 20; standardRecoverySeconds = 30
            case 10:
                standardIterations = 4; standardWorkSeconds = 30; standardRecoverySeconds = 45
            case 15:
                standardIterations = 4; standardWorkSeconds = 60; standardRecoverySeconds = 90
            case 20:
                standardIterations = 4; standardWorkSeconds = 90; standardRecoverySeconds = 90
            default:
                standardIterations = 6; standardWorkSeconds = 90; standardRecoverySeconds = 120
            }
        case "rhythm_intervals":
            switch canonicalMins {
            case ..<10:
                standardIterations = 3; standardWorkSeconds = 20; standardRecoverySeconds = 30
            case 10:
                standardIterations = 4; standardWorkSeconds = 30; standardRecoverySeconds = 45
            case 15:
                standardIterations = 5; standardWorkSeconds = 45; standardRecoverySeconds = 75
            case 20:
                standardIterations = 6; standardWorkSeconds = 45; standardRecoverySeconds = 75
            default:
                standardIterations = 6; standardWorkSeconds = 90; standardRecoverySeconds = 120
            }
        case "tempo_surges":
            switch canonicalMins {
            case ..<10:
                standardIterations = 3; standardWorkSeconds = 30; standardRecoverySeconds = 45
            case 10:
                standardIterations = 5; standardWorkSeconds = 30; standardRecoverySeconds = 60
            case 15:
                standardIterations = 3; standardWorkSeconds = 120; standardRecoverySeconds = 120
            case 20:
                standardIterations = 4; standardWorkSeconds = 90; standardRecoverySeconds = 120
            default:
                standardIterations = 4; standardWorkSeconds = 180; standardRecoverySeconds = 180
            }
        case "strides":
            switch canonicalMins {
            case ..<10:
                standardIterations = 4; standardWorkSeconds = 15; standardRecoverySeconds = 45
            case 10:
                standardIterations = 4; standardWorkSeconds = 15; standardRecoverySeconds = 45
            case 15:
                standardIterations = 6; standardWorkSeconds = 20; standardRecoverySeconds = 60
            default:
                standardIterations = 8; standardWorkSeconds = 30; standardRecoverySeconds = 90
            }
        case "neuromuscular_primer", "hill_bounds":
            switch canonicalMins {
            case ..<10:
                standardIterations = 3; standardWorkSeconds = 15; standardRecoverySeconds = 30
            case 10:
                standardIterations = 4; standardWorkSeconds = 20; standardRecoverySeconds = 40
            case 15:
                standardIterations = 5; standardWorkSeconds = 30; standardRecoverySeconds = 60
            default:
                standardIterations = 6; standardWorkSeconds = 45; standardRecoverySeconds = 90
            }
        case "fartlek_primer":
            switch canonicalMins {
            case ..<10:
                standardIterations = 3; standardWorkSeconds = 30; standardRecoverySeconds = 30
            case 10:
                standardIterations = 4; standardWorkSeconds = 45; standardRecoverySeconds = 45
            case 15:
                standardIterations = 5; standardWorkSeconds = 60; standardRecoverySeconds = 60
            case 20:
                standardIterations = 6; standardWorkSeconds = 60; standardRecoverySeconds = 60
            default:
                standardIterations = 6; standardWorkSeconds = 120; standardRecoverySeconds = 120
            }
        default:
            switch canonicalMins {
            case ..<10:
                standardIterations = 4; standardWorkSeconds = 15; standardRecoverySeconds = 45
            case 10:
                standardIterations = 4; standardWorkSeconds = 15; standardRecoverySeconds = 45
            case 15:
                standardIterations = 6; standardWorkSeconds = 20; standardRecoverySeconds = 60
            default:
                standardIterations = 8; standardWorkSeconds = 30; standardRecoverySeconds = 90
            }
        }

        let standardIntervalSeconds = Double(standardIterations) * (standardWorkSeconds + standardRecoverySeconds)
        let targetTotalSeconds = Double(canonicalMins * 60)
        let standardCooldownSeconds = max(0.0, targetTotalSeconds - warmupSeconds - standardIntervalSeconds)

        let isModulated: Bool
        let volumeScale: Double
        let recoveryScale: Double

        switch readinessState.lowercased() {
        case "productive":
            isModulated = false
            volumeScale = 1.0
            recoveryScale = 1.0
        case "deload":
            isModulated = true
            volumeScale = 0.5
            recoveryScale = 1.5
        case "acutefatigue", "acute_fatigue", "accumulatedfatigue", "accumulated_fatigue", "illnessorpain", "illness_or_pain", "detraining":
            isModulated = true
            volumeScale = 0.5
            recoveryScale = 1.0
        default:
            isModulated = false
            volumeScale = 1.0
            recoveryScale = 1.0
        }

        let finalIterations: Int
        let finalWorkSeconds: Double
        let finalRecoverySeconds: Double

        if isModulated {
            finalIterations = max(2, Int((Double(standardIterations) * volumeScale).rounded()))
            finalRecoverySeconds = Double(Int((standardRecoverySeconds * recoveryScale / 5.0).rounded()) * 5)
            finalWorkSeconds = standardWorkSeconds
        } else {
            finalIterations = standardIterations
            finalWorkSeconds = standardWorkSeconds
            finalRecoverySeconds = standardRecoverySeconds
        }

        return DrillScheduleCore(
            drillIdentifier: drillIdentifier,
            durationMinutes: canonicalMins,
            warmupSeconds: warmupSeconds,
            cooldownSeconds: standardCooldownSeconds,
            iterations: finalIterations,
            workSeconds: finalWorkSeconds,
            recoverySeconds: finalRecoverySeconds,
            isWalkRecovery: isWalk,
            readinessState: readinessState
        )
    }

    public static func findMatchingSchedule(
        workoutDuration: Double,
        detectedIterations: Int,
        avgWorkDuration: Double,
        avgRecoveryDuration: Double,
        candidateDrills: [String]
    ) -> DrillScheduleCore? {
        let durations = [5, 10, 15, 20, 30, 35, 40, 50]
        for drill in candidateDrills {
            for dur in durations {
                var candidates = [schedule(for: drill, durationMinutes: dur, readinessState: "productive")]
                if normalizeDrillIdentifier(drill) == "tempo_surges" && dur == 10 {
                    candidates.append(
                        DrillScheduleCore(
                            drillIdentifier: drill,
                            durationMinutes: 10,
                            warmupSeconds: 120,
                            cooldownSeconds: 60,
                            iterations: 3,
                            workSeconds: 60,
                            recoverySeconds: 90
                        )
                    )
                }
                for sched in candidates where sched.matches(
                    workoutDuration: workoutDuration,
                    detectedIterations: detectedIterations,
                    avgWorkDuration: avgWorkDuration,
                    avgRecoveryDuration: avgRecoveryDuration
                ) {
                    return sched
                }
            }
        }
        return nil
    }
}
