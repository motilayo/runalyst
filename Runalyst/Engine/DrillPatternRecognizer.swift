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

        var segments: [DrillPatternCore.SegmentStatsCore] = []
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
            segments.append(DrillPatternCore.SegmentStatsCore(avgCadence: avgC, avgHR: avgH, durationSeconds: act.duration))
        }

        guard let match = DrillPatternCore.recognizeFromSegments(
            segments: segments,
            baselineCadence: baselineCadence,
            sourceLabel: "Structured workout activities"
        ) else { return nil }

        return DrillPatternMatch(core: match)
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

        var segments: [DrillPatternCore.SegmentStatsCore] = []
        for evt in intervalEvents {
            let start = evt.dateInterval.start
            let end = evt.dateInterval.end
            let lapBuckets = buckets.filter {
                $0.startTime >= start && $0.startTime < end
            }
            guard !lapBuckets.isEmpty else { continue }
            let avgC = lapBuckets.map(\.meanCadence).reduce(0, +) / Double(lapBuckets.count)
            let validHRs = lapBuckets.map(\.meanHR).filter { $0 > 0 }
            let avgH = validHRs.isEmpty ? 0.0 : (validHRs.reduce(0, +) / Double(validHRs.count))
            segments.append(DrillPatternCore.SegmentStatsCore(avgCadence: avgC, avgHR: avgH, durationSeconds: evt.dateInterval.duration))
        }

        guard let match = DrillPatternCore.recognizeFromSegments(
            segments: segments,
            baselineCadence: baselineCadence,
            sourceLabel: "Event lap markers"
        ) else { return nil }

        return DrillPatternMatch(core: match)
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
