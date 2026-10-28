import Foundation
import RunalystCore

/// Canonical structural specification for a prescribed Runalyst corrective drill archetype.
/// Adapts `DrillScheduleCore` from `RunalystCore` to app types `PreRunDrillId` and `DrillDuration`.
struct DrillSchedule: Sendable, Equatable {
    let drillId: PreRunDrillId
    let durationCategory: DrillDuration
    let core: DrillScheduleCore

    var warmupSeconds: Double { core.warmupSeconds }
    var cooldownSeconds: Double { core.cooldownSeconds }
    var iterations: Int { core.iterations }
    var workSeconds: Double { core.workSeconds }
    var recoverySeconds: Double { core.recoverySeconds }
    var expectedTotalDuration: Double { core.expectedTotalDuration }
    var warmup: Double { core.warmupSeconds }
    var workSec: Double { core.workSeconds }
    var recSec: Double { core.recoverySeconds }

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
        self.core = DrillScheduleCore(
            drillIdentifier: drillId.rawValue,
            durationMinutes: durationCategory.rawValue,
            warmupSeconds: warmupSeconds,
            cooldownSeconds: cooldownSeconds,
            iterations: iterations,
            workSeconds: workSeconds,
            recoverySeconds: recoverySeconds
        )
    }

    init(drillId: PreRunDrillId, durationCategory: DrillDuration, core: DrillScheduleCore) {
        self.drillId = drillId
        self.durationCategory = durationCategory
        self.core = core
    }

    func matches(
        workoutDuration: Double,
        detectedIterations: Int,
        avgWorkDuration: Double,
        avgRecoveryDuration: Double
    ) -> Bool {
        core.matches(
            workoutDuration: workoutDuration,
            detectedIterations: detectedIterations,
            avgWorkDuration: avgWorkDuration,
            avgRecoveryDuration: avgRecoveryDuration
        )
    }

    static func schedule(for drillId: PreRunDrillId, duration: DrillDuration) -> DrillSchedule {
        let core = DrillScheduleCore.schedule(for: drillId.rawValue, durationMinutes: duration.rawValue)
        return DrillSchedule(drillId: drillId, durationCategory: duration, core: core)
    }

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
