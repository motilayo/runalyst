import Foundation
import HealthKit
import RunalystCore
#if canImport(WorkoutKit)
@preconcurrency import WorkoutKit
#endif

/// The recognized drill pattern signature and confidence metrics.
struct DrillPatternMatch: Sendable, Equatable {
    let drillId: PreRunDrillId
    let confidence: Double
    let detectedIntervalCount: Int
    let avgWorkCadence: Int
    let avgRecoveryCadence: Int
    let signatureDescription: String

    init(
        drillId: PreRunDrillId,
        confidence: Double,
        detectedIntervalCount: Int,
        avgWorkCadence: Int,
        avgRecoveryCadence: Int,
        signatureDescription: String
    ) {
        self.drillId = drillId
        self.confidence = confidence
        self.detectedIntervalCount = detectedIntervalCount
        self.avgWorkCadence = avgWorkCadence
        self.avgRecoveryCadence = avgRecoveryCadence
        self.signatureDescription = signatureDescription
    }

    init(core: DrillPatternMatchCore) {
        self.drillId = PreRunDrillId(rawValue: core.drillIdentifier) ?? .cadencePyramids
        self.confidence = core.confidence
        self.detectedIntervalCount = core.detectedIntervalCount
        self.avgWorkCadence = core.avgWorkCadence
        self.avgRecoveryCadence = core.avgRecoveryCadence
        self.signatureDescription = core.signatureDescription
    }
}

/// A deterministic pattern recognition engine that identifies structured drills
/// directly from HealthKit biomechanical time-series data, workout activities, and workout events.
enum DrillPatternRecognizer {

    // MARK: - Primary Time-Series Pattern Recognizer

    /// Evaluates 15-second BucketData time-series by delegating pure pattern recognition to `DrillPatternCore`.
    static func recognizeDrill(
        buckets: [BucketData],
        baselineCadence: Int = 155,
        workoutDuration: Double,
        zone4Threshold: Double = 161.5,
        zone2Threshold: Double = 142.0,
        zone1Threshold: Double = 125.0
    ) -> DrillPatternMatch? {
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

        guard let match = DrillPatternCore.recognizeDrill(
            buckets: coreBuckets,
            baselineCadence: baselineCadence,
            workoutDuration: workoutDuration,
            zone4Threshold: zone4Threshold,
            zone2Threshold: zone2Threshold,
            zone1Threshold: zone1Threshold
        ) else { return nil }

        return DrillPatternMatch(core: match)
    }

    // MARK: - Tier 2: HKWorkoutActivity Structural Extraction

    /// Inspects native Apple Watch workout interval activities (iOS 16+) to match drill patterns.
    static func recognizeFromActivities(
        activities: [HKWorkoutActivity],
        buckets: [BucketData],
        baselineCadence: Int
    ) -> DrillPatternMatch? {
        guard activities.count >= 4 else { return nil }

        struct ActivityStats {
            let activity: HKWorkoutActivity
            let avgCadence: Double
            let avgHR: Double
            let duration: TimeInterval
        }

        var activityStats: [ActivityStats] = []
        for act in activities {
            let actEnd = act.endDate ?? act.startDate.addingTimeInterval(act.duration)
            let actBuckets = buckets.filter { $0.startTime >= act.startDate && $0.startTime < actEnd }
            let avgC: Double
            let avgH: Double
            if !actBuckets.isEmpty {
                avgC = actBuckets.map { $0.meanCadence }.reduce(0, +) / Double(actBuckets.count)
                let validHRs = actBuckets.map { $0.meanHR }.filter { $0 > 0 }
                avgH = validHRs.isEmpty ? 0.0 : (validHRs.reduce(0, +) / Double(validHRs.count))
            } else {
                let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)
                let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate)
                let steps = stepType.flatMap { act.allStatistics[$0]?.sumQuantity()?.doubleValue(for: .count()) } ?? 0
                let hrVal = hrType.flatMap { act.allStatistics[$0]?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) } ?? 0
                avgC = act.duration > 0 ? (steps / (act.duration / 60.0)) : 0
                avgH = hrVal
            }
            activityStats.append(ActivityStats(activity: act, avgCadence: avgC, avgHR: avgH, duration: act.duration))
        }

        guard let minC = activityStats.map({ $0.avgCadence }).min(),
              let maxC = activityStats.map({ $0.avgCadence }).max(),
              (maxC - minC) >= 10.0 else {
            return nil
        }

        let threshold = (minC + maxC) / 2.0
        let workActs = activityStats.filter { $0.avgCadence >= threshold && $0.duration >= 15.0 }
        let recActs = activityStats.filter { $0.avgCadence < threshold }

        guard workActs.count >= 3 else { return nil }

        let workCadences = workActs.map { $0.avgCadence }
        let wMean = workCadences.reduce(0, +) / Double(workCadences.count)
        let wVariance = workCadences.map { pow($0 - wMean, 2) }.reduce(0, +) / Double(workCadences.count)
        let wStd = sqrt(wVariance)
        let avgRecC = recActs.isEmpty ? 0.0 : (recActs.map { $0.avgCadence }.reduce(0, +) / Double(recActs.count))

        let totalActDuration = activityStats.map(\.duration).reduce(0, +)
        let avgWorkDur = workActs.map(\.duration).reduce(0, +) / Double(workActs.count)
        let avgRecDur = recActs.isEmpty ? 0.0 : (recActs.map(\.duration).reduce(0, +) / Double(recActs.count))

        // Strides check
        if let sched = DrillSchedule.findMatchingSchedule(
            workoutDuration: totalActDuration,
            detectedIterations: workActs.count,
            avgWorkDuration: avgWorkDur,
            avgRecoveryDuration: avgRecDur,
            candidateDrills: [.strides]
        ), workActs.allSatisfy({ $0.duration <= 45.0 }) && (wMean >= 174.0 || wMean >= Double(baselineCadence) + 16.0) {
            return DrillPatternMatch(
                drillId: .strides,
                confidence: 0.95,
                detectedIntervalCount: workActs.count,
                avgWorkCadence: Int(round(wMean)),
                avgRecoveryCadence: Int(round(avgRecC)),
                signatureDescription: "Structured workout activities: \(workActs.count) short stride sprints (\(sched.durationCategory.title)) at \(Int(round(wMean))) SPM."
            )
        }

        // Pyramids check
        let isMonotonicUp: Bool = {
            for i in 0..<(workCadences.count - 1) where (workCadences[i + 1] - workCadences[i]) < 2.0 {
                return false
            }
            return true
        }()
        let spread = (workCadences.max() ?? 0) - (workCadences.min() ?? 0)
        if let sched = DrillSchedule.findMatchingSchedule(
            workoutDuration: totalActDuration,
            detectedIterations: workActs.count,
            avgWorkDuration: avgWorkDur,
            avgRecoveryDuration: avgRecDur,
            candidateDrills: [.cadencePyramids]
        ), isMonotonicUp && spread >= 5.0 {
            return DrillPatternMatch(
                drillId: .cadencePyramids,
                confidence: 0.96,
                detectedIntervalCount: workActs.count,
                avgWorkCadence: Int(round(wMean)),
                avgRecoveryCadence: Int(round(avgRecC)),
                signatureDescription: "Structured workout activities: \(workActs.count) progressive pyramid reps (\(sched.durationCategory.title), \(Int(round(workCadences.min() ?? 0)))–\(Int(round(workCadences.max() ?? 0))) SPM)."
            )
        }

        // Rhythm intervals check
        if let sched = DrillSchedule.findMatchingSchedule(
            workoutDuration: totalActDuration,
            detectedIterations: workActs.count,
            avgWorkDuration: avgWorkDur,
            avgRecoveryDuration: avgRecDur,
            candidateDrills: [.rhythmIntervals]
        ), wStd <= 3.8 {
            return DrillPatternMatch(
                drillId: .rhythmIntervals,
                confidence: 0.95,
                detectedIntervalCount: workActs.count,
                avgWorkCadence: Int(round(wMean)),
                avgRecoveryCadence: Int(round(avgRecC)),
                signatureDescription: "Structured workout activities: \(workActs.count) interval reps (\(sched.durationCategory.title)) dialed to \(Int(round(wMean))) SPM."
            )
        }

        // Tempo surges check
        if let sched = DrillSchedule.findMatchingSchedule(
            workoutDuration: totalActDuration,
            detectedIterations: workActs.count,
            avgWorkDuration: avgWorkDur,
            avgRecoveryDuration: avgRecDur,
            candidateDrills: [.tempoSurges]
        ), wMean >= Double(baselineCadence) + 5.0 {
            return DrillPatternMatch(
                drillId: .tempoSurges,
                confidence: 0.95,
                detectedIntervalCount: workActs.count,
                avgWorkCadence: Int(round(wMean)),
                avgRecoveryCadence: Int(round(avgRecC)),
                signatureDescription: "Structured workout activities: \(workActs.count) tempo surge reps (\(sched.durationCategory.title)) at \(Int(round(wMean))) SPM."
            )
        }

        return nil
    }

    // MARK: - Tier 2: HKWorkoutEvent Lap/Segment Structural Extraction

    /// Inspects native lap/segment HKWorkoutEvents to match interval patterns.
    static func recognizeFromEvents(
        events: [HKWorkoutEvent],
        buckets: [BucketData],
        baselineCadence: Int
    ) -> DrillPatternMatch? {
        let intervalEvents = events.filter { $0.type == .lap || $0.type == .segment }
        guard intervalEvents.count >= 4 else { return nil }

        struct LapStats {
            let start: Date
            let end: Date
            let avgCadence: Double
            let duration: TimeInterval
        }

        var lapStats: [LapStats] = []
        for evt in intervalEvents {
            let start = evt.dateInterval.start
            let end = evt.dateInterval.end
            let lapBuckets = buckets.filter {
                $0.startTime >= start && $0.startTime < end
            }
            guard !lapBuckets.isEmpty else { continue }
            let avgC = lapBuckets.map(\.meanCadence).reduce(0, +) / Double(lapBuckets.count)
            lapStats.append(LapStats(start: start, end: end, avgCadence: avgC, duration: evt.dateInterval.duration))
        }

        guard lapStats.count >= 4 else { return nil }
        guard let minC = lapStats.map({ $0.avgCadence }).min(),
              let maxC = lapStats.map({ $0.avgCadence }).max(),
              (maxC - minC) >= 10.0 else {
            return nil
        }

        let threshold = (minC + maxC) / 2.0
        let workLaps = lapStats.filter { $0.avgCadence >= threshold }
        let recLaps = lapStats.filter { $0.avgCadence < threshold }

        guard workLaps.count >= 3 else { return nil }

        let workCadences = workLaps.map { $0.avgCadence }
        let wMean = workCadences.reduce(0, +) / Double(workCadences.count)
        let wVariance = workCadences.map { pow($0 - wMean, 2) }.reduce(0, +) / Double(workCadences.count)
        let wStd = sqrt(wVariance)
        let avgRecC = recLaps.isEmpty ? 0.0 : (recLaps.map { $0.avgCadence }.reduce(0, +) / Double(recLaps.count))

        let totalEvtDuration = lapStats.map(\.duration).reduce(0, +)
        let avgWorkDur = workLaps.map(\.duration).reduce(0, +) / Double(workLaps.count)
        let avgRecDur = recLaps.isEmpty ? 0.0 : (recLaps.map(\.duration).reduce(0, +) / Double(recLaps.count))

        // Check Pyramids
        let isMonotonicUp: Bool = {
            for i in 0..<(workCadences.count - 1) where (workCadences[i + 1] - workCadences[i]) < 2.0 {
                return false
            }
            return true
        }()
        let spread = (workCadences.max() ?? 0) - (workCadences.min() ?? 0)
        if let sched = DrillSchedule.findMatchingSchedule(
            workoutDuration: totalEvtDuration,
            detectedIterations: workLaps.count,
            avgWorkDuration: avgWorkDur,
            avgRecoveryDuration: avgRecDur,
            candidateDrills: [.cadencePyramids]
        ), isMonotonicUp && spread >= 5.0 {
            return DrillPatternMatch(
                drillId: .cadencePyramids,
                confidence: 0.94,
                detectedIntervalCount: workLaps.count,
                avgWorkCadence: Int(round(wMean)),
                avgRecoveryCadence: Int(round(avgRecC)),
                signatureDescription: "Event lap markers: \(workLaps.count) progressive cadence pyramid laps (\(sched.durationCategory.title))."
            )
        }

        // Check Rhythm Intervals
        if let sched = DrillSchedule.findMatchingSchedule(
            workoutDuration: totalEvtDuration,
            detectedIterations: workLaps.count,
            avgWorkDuration: avgWorkDur,
            avgRecoveryDuration: avgRecDur,
            candidateDrills: [.rhythmIntervals]
        ), wStd <= 3.8 {
            return DrillPatternMatch(
                drillId: .rhythmIntervals,
                confidence: 0.93,
                detectedIntervalCount: workLaps.count,
                avgWorkCadence: Int(round(wMean)),
                avgRecoveryCadence: Int(round(avgRecC)),
                signatureDescription: "Event lap markers: \(workLaps.count) steady rhythm interval laps (\(sched.durationCategory.title)) at \(Int(round(wMean))) SPM."
            )
        }

        return nil
    }

    // MARK: - Dynamic Zone Thresholds Extraction

    #if canImport(HealthKit)
    static func extractZoneThresholds(from config: Any) -> (zone1Max: Double?, zone2Max: Double?, zone4Min: Double?) {
        let bpmUnit = HKUnit(from: "count/min")
        var z1Max: Double?
        var z2Max: Double?
        var z4Min: Double?

        guard let configObj = config as? NSObject,
              let zones = configObj.value(forKey: "zones") as? [NSObject] else {
            return (nil, nil, nil)
        }

        for (idx, zone) in zones.enumerated() {
            let zoneIndex = (zone.value(forKey: "index") as? Int) ?? (idx + 1)
            let maxQty = zone.value(forKey: "maximum") as? HKQuantity
            let minQty = zone.value(forKey: "minimum") as? HKQuantity

            if zoneIndex == 1 || (zoneIndex == 0 && zones.count >= 5) {
                z1Max = maxQty?.doubleValue(for: bpmUnit)
            } else if zoneIndex == 2 || (zoneIndex == 1 && zones.count >= 5) {
                z2Max = maxQty?.doubleValue(for: bpmUnit)
            } else if zoneIndex == 4 || (zoneIndex == 3 && zones.count >= 5) {
                z4Min = minQty?.doubleValue(for: bpmUnit)
            }
        }

        if z4Min == nil && zones.count >= 4 {
            let minQty = zones[3].value(forKey: "minimum") as? HKQuantity
            z4Min = minQty?.doubleValue(for: bpmUnit)
        }
        if z2Max == nil && zones.count >= 2 {
            let maxQty = zones[1].value(forKey: "maximum") as? HKQuantity
            z2Max = maxQty?.doubleValue(for: bpmUnit)
        }
        if z1Max == nil && !zones.isEmpty {
            let maxQty = zones[0].value(forKey: "maximum") as? HKQuantity
            z1Max = maxQty?.doubleValue(for: bpmUnit)
        }

        return (z1Max, z2Max, z4Min)
    }
    #endif
}
