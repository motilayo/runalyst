import Foundation

extension RunSplit {
    /// Synthesizes 1,000-meter splits from phase segments if physical splits were not persisted.
    static func synthesize(from segments: [PhaseSegment], splitDistanceMeters: Double = 1000.0) -> [RunSplit] {
        guard !segments.isEmpty else { return [] }
        var splits: [RunSplit] = []
        var currentSplitIndex = 1
        var accumulatedDist: Double = 0
        var splitDuration: Double = 0
        var splitHRSum: Double = 0
        var splitCadenceSum: Double = 0
        var splitWeight: Double = 0

        for seg in segments where seg.avgPace > 0 && seg.durationSeconds > 0 {
            let segDist = (seg.durationSeconds / seg.avgPace) * 1000.0
            var remainingDist = segDist

            while remainingDist > 0 {
                let needed = splitDistanceMeters - accumulatedDist
                let takeDist = min(remainingDist, needed)
                let fraction = takeDist / segDist
                let takeDur = fraction * seg.durationSeconds

                accumulatedDist += takeDist
                splitDuration += takeDur
                splitHRSum += seg.avgHR * takeDur
                splitCadenceSum += seg.avgCadence * takeDur
                splitWeight += takeDur

                remainingDist -= takeDist

                if accumulatedDist >= splitDistanceMeters {
                    let avgPace = (splitDuration / splitDistanceMeters) * 1000.0
                    let avgHR = splitWeight > 0 ? (splitHRSum / splitWeight) : seg.avgHR
                    let avgCad = splitWeight > 0 ? (splitCadenceSum / splitWeight) : seg.avgCadence

                    splits.append(RunSplit(
                        index: currentSplitIndex,
                        distanceMeters: splitDistanceMeters,
                        durationSeconds: splitDuration,
                        paceSecondsPerKm: avgPace,
                        avgHeartRate: avgHR,
                        avgCadence: avgCad,
                        elevationGainMeters: 0
                    ))

                    currentSplitIndex += 1
                    accumulatedDist = 0
                    splitDuration = 0
                    splitHRSum = 0
                    splitCadenceSum = 0
                    splitWeight = 0
                }
            }
        }

        if accumulatedDist >= 500.0 {
            let avgPace = (splitDuration / accumulatedDist) * 1000.0
            let avgHR = splitWeight > 0 ? (splitHRSum / splitWeight) : 0
            let avgCad = splitWeight > 0 ? (splitCadenceSum / splitWeight) : 0
            splits.append(RunSplit(
                index: currentSplitIndex,
                distanceMeters: accumulatedDist,
                durationSeconds: splitDuration,
                paceSecondsPerKm: avgPace,
                avgHeartRate: avgHR,
                avgCadence: avgCad,
                elevationGainMeters: 0
            ))
        }

        return splits
    }
}
