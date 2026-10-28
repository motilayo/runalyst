import Foundation
import HealthKit
#if canImport(WorkoutKit)
@preconcurrency import WorkoutKit

@available(iOS 17.0, *)
extension PreRunDrill {
    func buildWorkoutPlan() -> WorkoutPlan {
        let location: HKWorkoutSessionLocationType = isIndoor ? .indoor : .outdoor
        let baseDisplayName = customDisplayName ?? id.title
        let resolvedDisplayName: String = {
            guard isIndoor, let target = effectiveTargetCadence else { return baseDisplayName }
            let band = target.lowerBound == target.upperBound
                ? "\(target.lowerBound) SPM"
                : "\(target.lowerBound)-\(target.upperBound) SPM"
            if baseDisplayName.localizedCaseInsensitiveContains("spm") {
                return baseDisplayName
            }
            return "\(baseDisplayName) (\(band))"
        }()

        var workout = CustomWorkout(
            activity: .running,
            location: location,
            displayName: resolvedDisplayName
        )

        let warmUpDuration: Double = (id == .zone2Run && duration == .fiveMinutes) ? 0.0 : self.warmUpDurationMinutes
        let coolDownDuration: Double = self.coolDownDurationMinutes

        let warmUp = warmUpDuration > 0 ? WorkoutStep(goal: .time(warmUpDuration, .minutes)) : nil
        let coolDown = coolDownDuration > 0 ? WorkoutStep(goal: .time(coolDownDuration, .minutes)) : nil

        var alert: (any WorkoutAlert)?
        if let target = effectiveTargetCadence {
            let rangeAlert = CadenceRangeAlert.cadence(Double(target.lowerBound)...Double(target.upperBound))
            if CustomWorkout.supportsAlert(rangeAlert, activity: .running, location: location) {
                alert = rangeAlert
            } else {
                let thresholdAlert = CadenceThresholdAlert.cadence(Double(target.lowerBound))
                if CustomWorkout.supportsAlert(thresholdAlert, activity: .running, location: location) {
                    alert = thresholdAlert
                }
            }
        } else if id == .aerobicFlush || id == .recoveryJog {
            let zone1Alert = HeartRateZoneAlert(zone: 1)
            if CustomWorkout.supportsAlert(zone1Alert, activity: .running, location: location) {
                alert = zone1Alert
            }
        } else if id == .zone2Run {
            let zone2Alert = HeartRateZoneAlert(zone: 2)
            if CustomWorkout.supportsAlert(zone2Alert, activity: .running, location: location) {
                alert = zone2Alert
            }
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
            case .twentyMinutes:
                iterations = 4
                workGoal = .time(90, .seconds)
                recoveryGoal = .time(90, .seconds)
            case .thirtyMinutes, .thirtyFiveMinutes, .fortyMinutes, .fiftyMinutes:
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
            case .twentyMinutes:
                iterations = 6
                workGoal = .time(45, .seconds)
                recoveryGoal = .time(75, .seconds)
            case .thirtyMinutes, .thirtyFiveMinutes, .fortyMinutes, .fiftyMinutes:
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
            case .twentyMinutes:
                iterations = 4
                workGoal = .time(90, .seconds)
                recoveryGoal = .time(2, .minutes)
            case .thirtyMinutes, .thirtyFiveMinutes, .fortyMinutes, .fiftyMinutes:
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
            case .twentyMinutes, .thirtyMinutes, .thirtyFiveMinutes, .fortyMinutes, .fiftyMinutes:
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
            case .twentyMinutes, .thirtyMinutes, .thirtyFiveMinutes, .fortyMinutes, .fiftyMinutes:
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
            case .twentyMinutes:
                iterations = 6
                workGoal = .time(1, .minutes)
                recoveryGoal = .time(1, .minutes)
            case .thirtyMinutes, .thirtyFiveMinutes, .fortyMinutes, .fiftyMinutes:
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
            case .twentyMinutes, .thirtyMinutes, .thirtyFiveMinutes, .fortyMinutes, .fiftyMinutes:
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
            let steadySeconds = standardIntervalSpec.workSeconds
            workGoal = .time(Double(steadySeconds), .seconds)
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
