import Foundation
#if canImport(WorkoutKit)
@preconcurrency import WorkoutKit

@available(iOS 17.0, *)
extension PreRunDrill {
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
}
#endif
