import Foundation

/// Canonical structural specification for a prescribed Runalyst corrective drill archetype.
/// Encapsulates exact iteration counts, work and recovery durations, warmup/cooldown bookends,
/// and deterministic matching logic.
struct DrillSchedule: Sendable, Equatable {
    let drillId: PreRunDrillId
    let durationCategory: DrillDuration
    let warmupSeconds: Double
    let cooldownSeconds: Double
    let iterations: Int
    let workSeconds: Double
    let recoverySeconds: Double

    var expectedTotalDuration: Double {
        warmupSeconds + Double(iterations) * (workSeconds + recoverySeconds) + cooldownSeconds
    }

    var warmup: Double { warmupSeconds }
    var workSec: Double { workSeconds }
    var recSec: Double { recoverySeconds }

    init(
        drillId: PreRunDrillId,
        durationCategory: DrillDuration,
        warmupSeconds: Double,
        cooldownSeconds: Double,
        iterations: Int,
        workSeconds: Double,
        recoverySeconds: Double
    ) {
        self.drillId = drillId
        self.durationCategory = durationCategory
        self.warmupSeconds = warmupSeconds
        self.cooldownSeconds = cooldownSeconds
        self.iterations = iterations
        self.workSeconds = workSeconds
        self.recoverySeconds = recoverySeconds
    }

    /// Evaluates whether an observed workout structure (iterations, work duration, recovery duration, total duration)
    /// matches this drill schedule within allowable tolerances.
    func matches(
        workoutDuration: Double,
        detectedIterations: Int,
        avgWorkDuration: Double,
        avgRecoveryDuration: Double
    ) -> Bool {
        // 1. Iteration count check: Allow exact match or +/- 1 tolerance for drills with >= 4 prescribed reps
        if iterations >= 4 {
            guard abs(detectedIterations - iterations) <= 1 else {
                return false
            }
        } else {
            guard detectedIterations == iterations else {
                return false
            }
        }

        // 2. Total duration category gate (workout duration must align with the duration category)
        let minDuration: Double
        let maxDuration: Double
        switch durationCategory {
        case .fiveMinutes:
            minDuration = 180.0  // 3 min
            maxDuration = 600.0  // 10 min
        case .tenMinutes:
            minDuration = 360.0  // 6 min
            maxDuration = drillId == .tempoSurges ? 1500.0 : 1200.0  // 20 min (up to 25 min for tempo surges)
        case .fifteenMinutes:
            minDuration = 600.0  // 10 min
            maxDuration = drillId == .tempoSurges ? 1800.0 : 1680.0 // 28 min (up to 30 min for tempo surges)
        case .thirtyMinutes:
            minDuration = 1200.0 // 20 min
            maxDuration = drillId == .tempoSurges ? 2700.0 : 2520.0 // 42 min (up to 45 min for tempo surges)
        }
        guard workoutDuration >= minDuration && workoutDuration <= maxDuration else {
            return false
        }

        // 3. Work duration tolerance (bucket quantization allowance)
        let workTolerance = max(18.0, workSeconds * 0.30)
        guard abs(avgWorkDuration - workSeconds) <= workTolerance else {
            return false
        }

        // 4. Recovery duration tolerance
        if recoverySeconds > 0 {
            if drillId == .tempoSurges {
                // Tempo Surges recovery is continuous aerobic base running (90s up to 4m tempo float)
                guard avgRecoveryDuration >= 45.0 && avgRecoveryDuration <= 270.0 else {
                    return false
                }
            } else {
                let recTolerance = max(20.0, recoverySeconds * 0.35)
                guard abs(avgRecoveryDuration - recoverySeconds) <= recTolerance else {
                    return false
                }
            }
        }

        return true
    }

    // MARK: - Canonical Schedules Catalog

    /// Retrieves the exact canonical schedule for a given drill and duration category.
    static func schedule(for drillId: PreRunDrillId, duration: DrillDuration) -> DrillSchedule {
        switch drillId {
        case .cadencePyramids:
            switch duration {
            case .fiveMinutes:
                return DrillSchedule(drillId: drillId, durationCategory: duration, warmupSeconds: 60, cooldownSeconds: 30, iterations: 3, workSeconds: 20, recoverySeconds: 30)
            case .tenMinutes:
                return DrillSchedule(drillId: drillId, durationCategory: duration, warmupSeconds: 120, cooldownSeconds: 60, iterations: 4, workSeconds: 30, recoverySeconds: 45)
            case .fifteenMinutes:
                return DrillSchedule(drillId: drillId, durationCategory: duration, warmupSeconds: 180, cooldownSeconds: 120, iterations: 4, workSeconds: 60, recoverySeconds: 90)
            case .thirtyMinutes:
                return DrillSchedule(drillId: drillId, durationCategory: duration, warmupSeconds: 240, cooldownSeconds: 180, iterations: 6, workSeconds: 90, recoverySeconds: 120)
            }

        case .rhythmIntervals:
            switch duration {
            case .fiveMinutes:
                return DrillSchedule(drillId: drillId, durationCategory: duration, warmupSeconds: 60, cooldownSeconds: 30, iterations: 3, workSeconds: 20, recoverySeconds: 30)
            case .tenMinutes:
                return DrillSchedule(drillId: drillId, durationCategory: duration, warmupSeconds: 120, cooldownSeconds: 60, iterations: 4, workSeconds: 30, recoverySeconds: 45)
            case .fifteenMinutes:
                return DrillSchedule(drillId: drillId, durationCategory: duration, warmupSeconds: 180, cooldownSeconds: 120, iterations: 5, workSeconds: 45, recoverySeconds: 75)
            case .thirtyMinutes:
                return DrillSchedule(drillId: drillId, durationCategory: duration, warmupSeconds: 240, cooldownSeconds: 180, iterations: 6, workSeconds: 90, recoverySeconds: 120)
            }

        case .tempoSurges:
            switch duration {
            case .fiveMinutes:
                return DrillSchedule(drillId: drillId, durationCategory: duration, warmupSeconds: 60, cooldownSeconds: 30, iterations: 3, workSeconds: 30, recoverySeconds: 45)
            case .tenMinutes:
                return DrillSchedule(drillId: drillId, durationCategory: duration, warmupSeconds: 120, cooldownSeconds: 60, iterations: 3, workSeconds: 60, recoverySeconds: 90)
            case .fifteenMinutes:
                return DrillSchedule(drillId: drillId, durationCategory: duration, warmupSeconds: 180, cooldownSeconds: 120, iterations: 3, workSeconds: 120, recoverySeconds: 120)
            case .thirtyMinutes:
                return DrillSchedule(drillId: drillId, durationCategory: duration, warmupSeconds: 240, cooldownSeconds: 180, iterations: 4, workSeconds: 180, recoverySeconds: 180)
            }

        case .strides:
            switch duration {
            case .fiveMinutes:
                return DrillSchedule(drillId: drillId, durationCategory: duration, warmupSeconds: 60, cooldownSeconds: 30, iterations: 4, workSeconds: 15, recoverySeconds: 45)
            case .tenMinutes:
                return DrillSchedule(drillId: drillId, durationCategory: duration, warmupSeconds: 120, cooldownSeconds: 60, iterations: 4, workSeconds: 15, recoverySeconds: 45)
            case .fifteenMinutes:
                return DrillSchedule(drillId: drillId, durationCategory: duration, warmupSeconds: 180, cooldownSeconds: 120, iterations: 6, workSeconds: 20, recoverySeconds: 60)
            case .thirtyMinutes:
                return DrillSchedule(drillId: drillId, durationCategory: duration, warmupSeconds: 240, cooldownSeconds: 180, iterations: 8, workSeconds: 30, recoverySeconds: 90)
            }

        case .neuromuscularPrimer:
            switch duration {
            case .fiveMinutes:
                return DrillSchedule(drillId: drillId, durationCategory: duration, warmupSeconds: 60, cooldownSeconds: 30, iterations: 3, workSeconds: 15, recoverySeconds: 30)
            case .tenMinutes:
                return DrillSchedule(drillId: drillId, durationCategory: duration, warmupSeconds: 120, cooldownSeconds: 60, iterations: 4, workSeconds: 20, recoverySeconds: 40)
            case .fifteenMinutes:
                return DrillSchedule(drillId: drillId, durationCategory: duration, warmupSeconds: 180, cooldownSeconds: 120, iterations: 5, workSeconds: 30, recoverySeconds: 60)
            case .thirtyMinutes:
                return DrillSchedule(drillId: drillId, durationCategory: duration, warmupSeconds: 240, cooldownSeconds: 180, iterations: 6, workSeconds: 45, recoverySeconds: 90)
            }

        case .fartlekPrimer:
            switch duration {
            case .fiveMinutes:
                return DrillSchedule(drillId: drillId, durationCategory: duration, warmupSeconds: 60, cooldownSeconds: 30, iterations: 3, workSeconds: 30, recoverySeconds: 30)
            case .tenMinutes:
                return DrillSchedule(drillId: drillId, durationCategory: duration, warmupSeconds: 120, cooldownSeconds: 60, iterations: 4, workSeconds: 45, recoverySeconds: 45)
            case .fifteenMinutes:
                return DrillSchedule(drillId: drillId, durationCategory: duration, warmupSeconds: 180, cooldownSeconds: 120, iterations: 5, workSeconds: 60, recoverySeconds: 60)
            case .thirtyMinutes:
                return DrillSchedule(drillId: drillId, durationCategory: duration, warmupSeconds: 240, cooldownSeconds: 180, iterations: 6, workSeconds: 120, recoverySeconds: 120)
            }

        case .hillBounds:
            switch duration {
            case .fiveMinutes:
                return DrillSchedule(drillId: drillId, durationCategory: duration, warmupSeconds: 60, cooldownSeconds: 30, iterations: 3, workSeconds: 15, recoverySeconds: 30)
            case .tenMinutes:
                return DrillSchedule(drillId: drillId, durationCategory: duration, warmupSeconds: 120, cooldownSeconds: 60, iterations: 4, workSeconds: 20, recoverySeconds: 40)
            case .fifteenMinutes:
                return DrillSchedule(drillId: drillId, durationCategory: duration, warmupSeconds: 180, cooldownSeconds: 120, iterations: 5, workSeconds: 30, recoverySeconds: 60)
            case .thirtyMinutes:
                return DrillSchedule(drillId: drillId, durationCategory: duration, warmupSeconds: 240, cooldownSeconds: 180, iterations: 6, workSeconds: 45, recoverySeconds: 90)
            }

        case .aerobicFlush, .recoveryJog, .zone2Run:
            return DrillSchedule(drillId: drillId, durationCategory: duration, warmupSeconds: 0, cooldownSeconds: 0, iterations: 1, workSeconds: Double(duration.rawValue * 60), recoverySeconds: 0)
        }
    }

    /// All schedules across all interval drill archetypes and durations.
    static var allIntervalSchedules: [DrillSchedule] {
        var list: [DrillSchedule] = []
        let intervalDrills: [PreRunDrillId] = [
            .tempoSurges, .cadencePyramids, .rhythmIntervals, .strides,
            .neuromuscularPrimer, .fartlekPrimer, .hillBounds
        ]
        for drill in intervalDrills {
            for dur in DrillDuration.allCases {
                list.append(schedule(for: drill, duration: dur))
            }
        }
        return list
    }

    /// Finds the closest matching interval schedule for given session metrics.
    static func findMatchingSchedule(
        workoutDuration: Double,
        detectedIterations: Int,
        avgWorkDuration: Double,
        avgRecoveryDuration: Double,
        candidateDrills: [PreRunDrillId]? = nil
    ) -> DrillSchedule? {
        let schedules = candidateDrills?.flatMap { drill in
            DrillDuration.allCases.map { schedule(for: drill, duration: $0) }
        } ?? allIntervalSchedules

        return schedules.first { sched in
            sched.matches(
                workoutDuration: workoutDuration,
                detectedIterations: detectedIterations,
                avgWorkDuration: avgWorkDuration,
                avgRecoveryDuration: avgRecoveryDuration
            )
        }
    }
}
