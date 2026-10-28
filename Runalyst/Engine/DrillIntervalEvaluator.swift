import Foundation
import HealthKit
import RunalystCore

/// Extension to map DrillAdherenceTier with DrillAdherenceTierCore.
extension DrillAdherenceTier {
    init(core: DrillAdherenceTierCore) {
        switch core {
        case .exceeded: self = .exceeded
        case .met: self = .met
        case .partiallyMet: self = .partiallyMet
        case .notMet: self = .notMet
        }
    }

    var toCore: DrillAdherenceTierCore {
        switch self {
        case .exceeded: return .exceeded
        case .met: return .met
        case .partiallyMet: return .partiallyMet
        case .notMet: return .notMet
        }
    }
}

/// Represents the evaluated performance of an individual drill work rep.
struct DrillIntervalRep: Sendable, Equatable {
    let repIndex: Int
    let workCadence: Int
    let workHeartRate: Int
    let recoveryCadence: Int
    let recoveryHeartRate: Int
    let isMet: Bool
    var durationSeconds: Double?
    var workPaceSecondsPerKm: Double?
    var recoveryPaceSecondsPerKm: Double?

    var recoveryHeartRateDrop: Int? {
        guard workHeartRate > 0, recoveryHeartRate > 0 else { return nil }
        return workHeartRate - recoveryHeartRate
    }

    init(
        repIndex: Int,
        workCadence: Int,
        workHeartRate: Int,
        recoveryCadence: Int,
        recoveryHeartRate: Int,
        isMet: Bool,
        durationSeconds: Double? = nil,
        workPaceSecondsPerKm: Double? = nil,
        recoveryPaceSecondsPerKm: Double? = nil
    ) {
        self.repIndex = repIndex
        self.workCadence = workCadence
        self.workHeartRate = workHeartRate
        self.recoveryCadence = recoveryCadence
        self.recoveryHeartRate = recoveryHeartRate
        self.isMet = isMet
        self.durationSeconds = durationSeconds
        self.workPaceSecondsPerKm = workPaceSecondsPerKm
        self.recoveryPaceSecondsPerKm = recoveryPaceSecondsPerKm
    }

    init(core: DrillIntervalRepCore) {
        self.repIndex = core.repIndex
        self.workCadence = core.workCadence
        self.workHeartRate = core.workHeartRate
        self.recoveryCadence = core.recoveryCadence
        self.recoveryHeartRate = core.recoveryHeartRate
        self.isMet = core.isMet
        self.durationSeconds = core.durationSeconds
        self.workPaceSecondsPerKm = core.workPaceSecondsPerKm
        self.recoveryPaceSecondsPerKm = core.recoveryPaceSecondsPerKm
    }

    var toCore: DrillIntervalRepCore {
        DrillIntervalRepCore(
            repIndex: repIndex,
            workCadence: workCadence,
            workHeartRate: workHeartRate,
            recoveryCadence: recoveryCadence,
            recoveryHeartRate: recoveryHeartRate,
            isMet: isMet,
            durationSeconds: durationSeconds,
            workPaceSecondsPerKm: workPaceSecondsPerKm,
            recoveryPaceSecondsPerKm: recoveryPaceSecondsPerKm
        )
    }
}

/// The complete interval-by-interval performance scorecard for a prescribed drill.
struct DrillIntervalSummary: Sendable, Equatable {
    let drillId: PreRunDrillId
    let intervalsMet: Int
    let totalIntervals: Int
    let workCadenceAvg: Int
    let recoveryCadenceAvg: Int
    let reps: [DrillIntervalRep]
    let tier: DrillAdherenceTier
    let verdict: String

    var adherencePercentage: Int {
        guard totalIntervals > 0 else { return 0 }
        return Int(round(Double(intervalsMet) / Double(totalIntervals) * 100.0))
    }

    var framboiseTags: [String] {
        toCore.framboiseTags
    }

    var toCore: DrillIntervalSummaryCore {
        DrillIntervalSummaryCore(
            drillIdentifier: drillId.rawValue,
            intervalsMet: intervalsMet,
            totalIntervals: totalIntervals,
            workCadenceAvg: workCadenceAvg,
            recoveryCadenceAvg: recoveryCadenceAvg,
            reps: reps.map(\.toCore),
            tier: tier.toCore,
            verdict: verdict
        )
    }

    init(
        drillId: PreRunDrillId,
        intervalsMet: Int,
        totalIntervals: Int,
        workCadenceAvg: Int,
        recoveryCadenceAvg: Int,
        reps: [DrillIntervalRep],
        tier: DrillAdherenceTier,
        verdict: String
    ) {
        self.drillId = drillId
        self.intervalsMet = intervalsMet
        self.totalIntervals = totalIntervals
        self.workCadenceAvg = workCadenceAvg
        self.recoveryCadenceAvg = recoveryCadenceAvg
        self.reps = reps
        self.tier = tier
        self.verdict = verdict
    }

    init(core: DrillIntervalSummaryCore, drillId: PreRunDrillId) {
        self.drillId = drillId
        self.intervalsMet = core.intervalsMet
        self.totalIntervals = core.totalIntervals
        self.workCadenceAvg = core.workCadenceAvg
        self.recoveryCadenceAvg = core.recoveryCadenceAvg
        self.reps = core.reps.map(DrillIntervalRep.init(core:))
        self.tier = DrillAdherenceTier(core: core.tier)
        self.verdict = core.verdict
    }

    static func from(tags: [String], drillId: PreRunDrillId) -> DrillIntervalSummary? {
        guard let core = DrillIntervalSummaryCore.from(tags: tags, drillIdentifier: drillId.rawValue) else { return nil }
        return DrillIntervalSummary(core: core, drillId: drillId)
    }
}

/// Evaluates interval workouts rep-by-rep against prescribed target cadence and durations.
enum DrillIntervalEvaluator {

    struct Context: Sendable {
        let drillId: PreRunDrillId
        let effectiveRange: ClosedRange<Int>?
        let baselineCadence: Int
        let oscDelta: Double
        let durationCategory: DrillDuration

        init(
            drillId: PreRunDrillId,
            effectiveRange: ClosedRange<Int>?,
            baselineCadence: Int,
            oscDelta: Double = 0.0,
            durationCategory: DrillDuration = .fifteenMinutes
        ) {
            self.drillId = drillId
            self.effectiveRange = effectiveRange
            self.baselineCadence = baselineCadence
            self.oscDelta = oscDelta
            self.durationCategory = durationCategory
        }

        var toCore: DrillEvaluationContextCore {
            DrillEvaluationContextCore(
                drillIdentifier: drillId.rawValue,
                effectiveTargetMin: effectiveRange?.lowerBound,
                effectiveTargetMax: effectiveRange?.upperBound,
                baselineCadence: baselineCadence,
                oscDelta: oscDelta,
                isAerobicContinuous: drillId.isAerobicContinuous
            )
        }
    }

    struct DrillSegment: Sendable {
        let avgCadence: Double
        let avgHR: Double
        let duration: TimeInterval
        let isWorkHint: Bool?
        var avgPace: Double?

        init(
            avgCadence: Double,
            avgHR: Double,
            duration: TimeInterval,
            isWorkHint: Bool? = nil,
            avgPace: Double? = nil
        ) {
            self.avgCadence = avgCadence
            self.avgHR = avgHR
            self.duration = duration
            self.isWorkHint = isWorkHint
            self.avgPace = avgPace
        }

        var toCore: DrillEvaluationSegmentCore {
            DrillEvaluationSegmentCore(
                avgCadence: avgCadence,
                avgHR: avgHR,
                duration: duration,
                isWorkHint: isWorkHint,
                avgPace: avgPace
            )
        }
    }

    static func checkIsMet(
        workCadence: Int,
        workHeartRate: Int = 0,
        context: Context
    ) -> Bool {
        DrillEvaluationCore.checkIsMet(
            workCadence: workCadence,
            workHeartRate: workHeartRate,
            context: context.toCore
        )
    }

    static func evaluateSegments(
        _ segments: [DrillSegment],
        context: Context
    ) -> DrillIntervalSummary? {
        let schedule = DrillSchedule.schedule(for: context.drillId, duration: context.durationCategory)
        guard let coreSummary = DrillEvaluationCore.evaluateSegments(
            segments.map(\.toCore),
            context: context.toCore,
            expectedIterations: schedule.iterations,
            warmupSeconds: schedule.warmup,
            workSeconds: schedule.workSec
        ) else { return nil }
        return DrillIntervalSummary(core: coreSummary, drillId: context.drillId)
    }

    /// Slices workouts into individual work and recovery intervals using a 4-tier evaluation hierarchy:
    /// 1. Native `HKWorkoutActivity` intervals (WorkoutKit / Apple Watch intervals, iOS 16+)
    /// 2. Native `HKWorkoutEvent` lap/segment intervals (iOS 8+)
    /// 3. Dynamic cadence waveform segmentation from 15-second `BucketData`
    /// 4. Fallback theoretical schedule (only if buckets are empty or continuous)
    static func evaluate(
        workout: HKWorkout? = nil,
        buckets: [BucketData],
        drillId: PreRunDrillId,
        baselineCadence: Int,
        workoutDuration: Double,
        oscDelta: Double = 0.0,
        targetCadenceOverride: String? = nil
    ) -> DrillIntervalSummary {
        let durationCategory: DrillDuration
        if workoutDuration <= 720 { // <= 12 min
            durationCategory = .tenMinutes
        } else if workoutDuration >= 1500 { // >= 25 min
            durationCategory = .thirtyMinutes
        } else {
            durationCategory = .fifteenMinutes
        }

        let template = DrillTemplate.template(for: drillId)
        let targetCadenceStr = targetCadenceOverride ?? template.calculateTargetCadence(baselineCadence)
        let preRunDrill = PreRunDrill(
            id: drillId,
            previousCadence: baselineCadence,
            targetCadence: targetCadenceStr,
            duration: durationCategory
        )

        let context = Context(
            drillId: drillId,
            effectiveRange: preRunDrill.effectiveTargetCadence,
            baselineCadence: baselineCadence,
            oscDelta: oscDelta,
            durationCategory: durationCategory
        )

        let coreBuckets = buckets.map {
            TelemetryBucket(
                timestamp: $0.startTime,
                durationSeconds: $0.durationSeconds,
                distanceMeters: $0.distanceMeters,
                paceSecondsPerKm: $0.meanPaceSecPerKm,
                cadenceSPM: $0.meanCadence,
                heartRateBPM: $0.meanHR,
                verticalOscillationCm: $0.meanVerticalOscillation > 0 ? $0.meanVerticalOscillation : nil,
                strideLengthMeters: $0.meanStrideLength > 0 ? $0.meanStrideLength : nil,
                elevationGainMeters: $0.elevationGainMeters
            )
        }

        // Continuous drills (Zone 2, Recovery Jog, Aerobic Flush)
        if drillId.isAerobicContinuous {
            let coreSummary = DrillEvaluationCore.evaluateContinuous(buckets: coreBuckets, context: context.toCore)
            return DrillIntervalSummary(core: coreSummary, drillId: drillId)
        }

        let schedule = DrillSchedule.schedule(for: drillId, duration: durationCategory)

        // MARK: - Tier 1: Native HKWorkoutActivity Extraction (Apple Watch WorkoutKit)
        if let workout = workout, workout.workoutActivities.count >= 2 {
            if let summary = evaluateFromActivities(
                activities: workout.workoutActivities,
                buckets: buckets,
                context: context
            ) {
                return summary
            }
        }

        // MARK: - Tier 2: Native HKWorkoutEvent Lap/Segment Extraction
        if let workout = workout, let events = workout.workoutEvents,
           events.filter({ $0.type == .lap || $0.type == .segment }).count >= 4 {
            if let summary = evaluateFromEvents(
                events: events,
                buckets: buckets,
                context: context
            ) {
                return summary
            }
        }

        // MARK: - Tier 3: Dynamic Cadence Waveform Peak/Valley Segmentation
        if !coreBuckets.isEmpty {
            if let coreSummary = DrillEvaluationCore.evaluateFromWaveform(
                buckets: coreBuckets,
                context: context.toCore
            ) {
                return DrillIntervalSummary(core: coreSummary, drillId: drillId)
            }
        }

        // MARK: - Tier 4: Fallback Theoretical Schedule (when buckets are empty)
        let coreSummary = DrillEvaluationCore.evaluateFromSchedule(
            buckets: coreBuckets,
            schedule: schedule.core,
            context: context.toCore
        )
        return DrillIntervalSummary(core: coreSummary, drillId: drillId)
    }

    static func evaluateFromActivities(
        activities: [HKWorkoutActivity],
        buckets: [BucketData],
        context: Context
    ) -> DrillIntervalSummary? {
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)
        let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate)
        let distType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)

        let sortedActivities = activities.sorted { $0.startDate < $1.startDate }
        var segments: [DrillSegment] = []

        for act in sortedActivities {
            guard act.duration > 0 else { continue }
            let steps = stepType.flatMap { act.allStatistics[$0]?.sumQuantity()?.doubleValue(for: .count()) } ?? 0
            let hrVal = hrType.flatMap {
                act.allStatistics[$0]?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            } ?? 0
            let distM = distType.flatMap { act.allStatistics[$0]?.sumQuantity()?.doubleValue(for: .meter()) } ?? 0

            let avgC: Double
            let avgH: Double
            let avgP: Double?

            if steps > 0 {
                avgC = steps / (act.duration / 60.0)
                avgH = hrVal
                avgP = distM > 0 ? (act.duration / (distM / 1000.0)) : nil
            } else {
                let actEnd = act.endDate ?? act.startDate.addingTimeInterval(act.duration)
                let actBuckets = buckets.filter { $0.startTime >= act.startDate && $0.startTime < actEnd }
                if !actBuckets.isEmpty {
                    let validCadences = actBuckets.map(\.meanCadence).filter { $0 > 0 }
                    avgC = validCadences.isEmpty ? 0 : (validCadences.reduce(0, +) / Double(validCadences.count))
                    let validHRs = actBuckets.map(\.meanHR).filter { $0 > 0 }
                    avgH = validHRs.isEmpty ? 0 : (validHRs.reduce(0, +) / Double(validHRs.count))
                    let validPaces = actBuckets.map(\.meanPaceSecPerKm).filter { $0 > 0 }
                    avgP = validPaces.isEmpty ? nil : (validPaces.reduce(0, +) / Double(validPaces.count))
                } else {
                    avgC = 0
                    avgH = hrVal
                    avgP = nil
                }
            }

            var hint: Bool?
            if let metadata = act.metadata {
                for (_, v) in metadata {
                    let valStr = String(describing: v).lowercased()
                    if valStr.contains("work") || valStr.contains("interval") {
                        hint = true
                        break
                    } else if valStr.contains("recovery") || valStr.contains("rest") {
                        hint = false
                        break
                    }
                }
            }

            segments.append(DrillSegment(
                avgCadence: avgC,
                avgHR: avgH,
                duration: act.duration,
                isWorkHint: hint,
                avgPace: avgP
            ))
        }

        return evaluateSegments(segments, context: context)
    }

    static func evaluateFromEvents(
        events: [HKWorkoutEvent],
        buckets: [BucketData],
        context: Context
    ) -> DrillIntervalSummary? {
        let intervalEvents = events.filter { $0.type == .lap || $0.type == .segment }
        guard intervalEvents.count >= 2 else { return nil }

        let sortedEvents = intervalEvents.sorted { $0.dateInterval.start < $1.dateInterval.start }
        var segments: [DrillSegment] = []
        for evt in sortedEvents {
            guard evt.dateInterval.duration > 0 else { continue }
            let start = evt.dateInterval.start
            let end = evt.dateInterval.end
            let duration = evt.dateInterval.duration
            let segBuckets = buckets.filter { $0.startTime >= start && $0.startTime < end }
            let avgC = segBuckets.isEmpty ? 0.0 : (segBuckets.map(\.meanCadence).reduce(0, +) / Double(segBuckets.count))
            let validHRs = segBuckets.map(\.meanHR).filter { $0 > 0 }
            let avgH = validHRs.isEmpty ? 0.0 : (validHRs.reduce(0, +) / Double(validHRs.count))

            var hint: Bool?
            if let metadata = evt.metadata {
                for (_, v) in metadata {
                    let valStr = String(describing: v).lowercased()
                    if valStr.contains("work") || valStr.contains("interval") {
                        hint = true
                        break
                    } else if valStr.contains("recovery") || valStr.contains("rest") {
                        hint = false
                        break
                    }
                }
            }

            segments.append(DrillSegment(
                avgCadence: avgC,
                avgHR: avgH,
                duration: duration,
                isWorkHint: hint
            ))
        }

        return evaluateSegments(segments, context: context)
    }
}
