import Foundation

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

    public var expectedTotalDuration: Double {
        warmupSeconds + Double(iterations) * (workSeconds + recoverySeconds) + cooldownSeconds
    }

    public init(
        drillIdentifier: String,
        durationMinutes: Int,
        warmupSeconds: Double,
        cooldownSeconds: Double,
        iterations: Int,
        workSeconds: Double,
        recoverySeconds: Double
    ) {
        self.drillIdentifier = drillIdentifier
        self.durationMinutes = durationMinutes
        self.warmupSeconds = warmupSeconds
        self.cooldownSeconds = cooldownSeconds
        self.iterations = iterations
        self.workSeconds = workSeconds
        self.recoverySeconds = recoverySeconds
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
        switch drillIdentifier {
        case "cadence_pyramids":
            if durationMinutes <= 7 {
                return DrillScheduleCore(drillIdentifier: drillIdentifier, durationMinutes: 5, warmupSeconds: 60, cooldownSeconds: 30, iterations: 3, workSeconds: 20, recoverySeconds: 30)
            } else if durationMinutes <= 12 {
                return DrillScheduleCore(drillIdentifier: drillIdentifier, durationMinutes: 10, warmupSeconds: 120, cooldownSeconds: 60, iterations: 4, workSeconds: 30, recoverySeconds: 45)
            } else if durationMinutes <= 20 {
                return DrillScheduleCore(drillIdentifier: drillIdentifier, durationMinutes: 15, warmupSeconds: 180, cooldownSeconds: 120, iterations: 4, workSeconds: 60, recoverySeconds: 90)
            } else {
                return DrillScheduleCore(drillIdentifier: drillIdentifier, durationMinutes: 30, warmupSeconds: 240, cooldownSeconds: 180, iterations: 6, workSeconds: 90, recoverySeconds: 120)
            }
        case "rhythm_intervals":
            if durationMinutes <= 7 {
                return DrillScheduleCore(drillIdentifier: drillIdentifier, durationMinutes: 5, warmupSeconds: 60, cooldownSeconds: 30, iterations: 3, workSeconds: 20, recoverySeconds: 30)
            } else if durationMinutes <= 12 {
                return DrillScheduleCore(drillIdentifier: drillIdentifier, durationMinutes: 10, warmupSeconds: 120, cooldownSeconds: 60, iterations: 4, workSeconds: 30, recoverySeconds: 45)
            } else if durationMinutes <= 20 {
                return DrillScheduleCore(drillIdentifier: drillIdentifier, durationMinutes: 15, warmupSeconds: 180, cooldownSeconds: 120, iterations: 5, workSeconds: 45, recoverySeconds: 75)
            } else {
                return DrillScheduleCore(drillIdentifier: drillIdentifier, durationMinutes: 30, warmupSeconds: 240, cooldownSeconds: 180, iterations: 6, workSeconds: 90, recoverySeconds: 120)
            }
        case "tempo_surges":
            if durationMinutes <= 7 {
                return DrillScheduleCore(drillIdentifier: drillIdentifier, durationMinutes: 5, warmupSeconds: 60, cooldownSeconds: 30, iterations: 3, workSeconds: 30, recoverySeconds: 45)
            } else if durationMinutes <= 12 {
                return DrillScheduleCore(drillIdentifier: drillIdentifier, durationMinutes: 10, warmupSeconds: 120, cooldownSeconds: 60, iterations: 3, workSeconds: 60, recoverySeconds: 90)
            } else if durationMinutes <= 20 {
                return DrillScheduleCore(drillIdentifier: drillIdentifier, durationMinutes: 15, warmupSeconds: 180, cooldownSeconds: 120, iterations: 3, workSeconds: 120, recoverySeconds: 120)
            } else {
                return DrillScheduleCore(drillIdentifier: drillIdentifier, durationMinutes: 30, warmupSeconds: 240, cooldownSeconds: 180, iterations: 4, workSeconds: 180, recoverySeconds: 180)
            }
        case "neuromuscular_primer", "hill_bounds":
            if durationMinutes <= 7 {
                return DrillScheduleCore(drillIdentifier: drillIdentifier, durationMinutes: 5, warmupSeconds: 60, cooldownSeconds: 30, iterations: 3, workSeconds: 15, recoverySeconds: 30)
            } else if durationMinutes <= 12 {
                return DrillScheduleCore(drillIdentifier: drillIdentifier, durationMinutes: 10, warmupSeconds: 120, cooldownSeconds: 60, iterations: 4, workSeconds: 20, recoverySeconds: 40)
            } else if durationMinutes <= 20 {
                return DrillScheduleCore(drillIdentifier: drillIdentifier, durationMinutes: 15, warmupSeconds: 180, cooldownSeconds: 120, iterations: 5, workSeconds: 30, recoverySeconds: 60)
            } else {
                return DrillScheduleCore(drillIdentifier: drillIdentifier, durationMinutes: 30, warmupSeconds: 240, cooldownSeconds: 180, iterations: 6, workSeconds: 45, recoverySeconds: 90)
            }
        case "fartlek_primer":
            if durationMinutes <= 7 {
                return DrillScheduleCore(drillIdentifier: drillIdentifier, durationMinutes: 5, warmupSeconds: 60, cooldownSeconds: 30, iterations: 3, workSeconds: 30, recoverySeconds: 30)
            } else if durationMinutes <= 12 {
                return DrillScheduleCore(drillIdentifier: drillIdentifier, durationMinutes: 10, warmupSeconds: 120, cooldownSeconds: 60, iterations: 4, workSeconds: 45, recoverySeconds: 45)
            } else if durationMinutes <= 20 {
                return DrillScheduleCore(drillIdentifier: drillIdentifier, durationMinutes: 15, warmupSeconds: 180, cooldownSeconds: 120, iterations: 5, workSeconds: 60, recoverySeconds: 60)
            } else {
                return DrillScheduleCore(drillIdentifier: drillIdentifier, durationMinutes: 30, warmupSeconds: 240, cooldownSeconds: 180, iterations: 6, workSeconds: 120, recoverySeconds: 120)
            }
        case "aerobic_flush", "recovery_jog", "zone2_run":
            return DrillScheduleCore(drillIdentifier: drillIdentifier, durationMinutes: durationMinutes, warmupSeconds: 0, cooldownSeconds: 0, iterations: 1, workSeconds: Double(durationMinutes * 60), recoverySeconds: 0)
        default: // strides
            if durationMinutes <= 7 {
                return DrillScheduleCore(drillIdentifier: drillIdentifier, durationMinutes: 5, warmupSeconds: 60, cooldownSeconds: 30, iterations: 4, workSeconds: 15, recoverySeconds: 45)
            } else if durationMinutes <= 12 {
                return DrillScheduleCore(drillIdentifier: drillIdentifier, durationMinutes: 10, warmupSeconds: 120, cooldownSeconds: 60, iterations: 4, workSeconds: 15, recoverySeconds: 45)
            } else if durationMinutes <= 20 {
                return DrillScheduleCore(drillIdentifier: drillIdentifier, durationMinutes: 15, warmupSeconds: 180, cooldownSeconds: 120, iterations: 6, workSeconds: 20, recoverySeconds: 60)
            } else {
                return DrillScheduleCore(drillIdentifier: drillIdentifier, durationMinutes: 30, warmupSeconds: 240, cooldownSeconds: 180, iterations: 8, workSeconds: 30, recoverySeconds: 90)
            }
        }
    }

    public static func findMatchingSchedule(
        workoutDuration: Double,
        detectedIterations: Int,
        avgWorkDuration: Double,
        avgRecoveryDuration: Double,
        candidateDrills: [String]
    ) -> DrillScheduleCore? {
        let durations = [5, 10, 15, 30]
        for drill in candidateDrills {
            for dur in durations {
                let sched = schedule(for: drill, durationMinutes: dur)
                if sched.matches(
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
