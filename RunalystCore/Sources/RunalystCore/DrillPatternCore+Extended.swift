import Foundation

extension DrillPatternCore {
    /// Detects structured threshold surge workouts with continuous active walk/jog recoveries (e.g. 10K Threshold Surges: 4 x 3m).
    public static func detectThresholdSurgesWithWalkRecovery(
        buckets: [TelemetryBucket],
        workoutDuration: Double,
        zone4Threshold: Double
    ) -> DrillPatternMatchCore? {
        guard workoutDuration >= 600.0 else { return nil }

        // Must not contain stationary dead stops
        guard !buckets.contains(where: { $0.cadenceSPM < 95.0 || $0.speedMetersPerSecond < 0.8 }) else {
            return nil
        }

        var surgeRanges: [Range<Int>] = []
        var surgeStart: Int?

        for i in 0..<buckets.count {
            let b = buckets[i]
            // Threshold surge: HR in or near Zone 4, cadence >= 145 SPM, pace faster than steady aerobic
            let isSurge = b.heartRateBPM >= (zone4Threshold - 2.0) && b.cadenceSPM >= 145.0 && (b.paceSecondsPerKm > 0 && b.paceSecondsPerKm <= 400.0)
            if isSurge {
                if surgeStart == nil { surgeStart = i }
            } else if let start = surgeStart {
                let dur = buckets[start..<i].map(\.durationSeconds).reduce(0, +)
                if dur >= 60.0 && dur <= 300.0 {
                    surgeRanges.append(start..<i)
                }
                surgeStart = nil
            }
        }
        if let start = surgeStart {
            let dur = buckets[start..<buckets.count].map(\.durationSeconds).reduce(0, +)
            if dur >= 60.0 && dur <= 300.0 {
                surgeRanges.append(start..<buckets.count)
            }
        }

        guard surgeRanges.count == 3 || surgeRanges.count == 4 else { return nil }

        let surgeDurations = surgeRanges.map { r in
            buckets[r].map(\.durationSeconds).reduce(0, +)
        }
        let avgWorkDuration = surgeDurations.reduce(0, +) / Double(surgeDurations.count)

        var recDurations: [Double] = []
        var recBuckets: [TelemetryBucket] = []
        for idx in 0..<(surgeRanges.count - 1) {
            let recStart = surgeRanges[idx].upperBound
            let recEnd = surgeRanges[idx + 1].lowerBound
            if recEnd > recStart {
                let slice = buckets[recStart..<recEnd]
                let dur = slice.map(\.durationSeconds).reduce(0, +)
                recDurations.append(dur)
                recBuckets.append(contentsOf: slice)
            }
        }
        guard !recDurations.isEmpty && !recBuckets.isEmpty else { return nil }
        let avgRecDuration = recDurations.reduce(0, +) / Double(recDurations.count)

        guard let matchingSchedule = DrillScheduleCore.findMatchingSchedule(
            workoutDuration: workoutDuration,
            detectedIterations: surgeRanges.count,
            avgWorkDuration: avgWorkDuration,
            avgRecoveryDuration: avgRecDuration,
            candidateDrills: ["tempo_surges"]
        ) else {
            return nil
        }

        let allSurgeBuckets = surgeRanges.flatMap { buckets[$0] }
        let avgSurgeCadence = allSurgeBuckets.map(\.cadenceSPM).reduce(0, +) / Double(allSurgeBuckets.count)
        let avgRecCadence = recBuckets.map(\.cadenceSPM).reduce(0, +) / Double(recBuckets.count)

        guard avgSurgeCadence >= 145.0,
              (avgSurgeCadence - avgRecCadence) >= 15.0 || avgRecCadence <= 135.0 else {
            return nil
        }

        return DrillPatternMatchCore(
            drillIdentifier: "tempo_surges",
            confidence: 0.94,
            detectedIntervalCount: surgeRanges.count,
            avgWorkCadence: Int(round(avgSurgeCadence)),
            avgRecoveryCadence: Int(round(avgRecCadence)),
            signatureDescription: "Detected \(surgeRanges.count) threshold surge intervals (\(matchingSchedule.durationMinutes) min, avg \(Int(round(avgSurgeCadence))) SPM in Zone 4)."
        )
    }
}
