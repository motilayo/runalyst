import Foundation
import HealthKit

/// The deterministic math engine for Runalyst V2.
/// Responsible for transforming raw HealthKit continuous streams into structured,
/// noise-filtered metrics (working averages, CV, linear regression, and rule-based classification).
actor FramboiseEngine {

    // MARK: - Dead Stop & Walking Filter

    /// Filters out stationary time, traffic stops, and walking breaks.
    /// Strictly filters to KEEP samples where speed is greater than the walking threshold
    /// (e.g., speed > 1.5 m/s or cadence > 130 SPM). Drops everything else.
    func filterRunningSamples(buckets: [BucketData]) -> [BucketData] {
        return buckets.filter { bucket in
            let speedMetersPerSecond = bucket.durationSeconds > 0 ? (bucket.distanceMeters / bucket.durationSeconds) : 0
            let isRunning = speedMetersPerSecond > 1.5 || bucket.meanCadence > 130.0
            return isRunning
        }
    }

    /// Alias for filterRunningSamples to maintain backward compatibility with callers.
    func trimDeadStops(buckets: [BucketData]) -> [BucketData] {
        return filterRunningSamples(buckets: buckets)
    }

    // MARK: - Working Averages & Aggregate Pace

    /// Calculates true working averages by strictly summing the filtered running samples.
    /// - Strictly sums the duration of only the kept/filtered samples.
    /// - Enforces hard safety constraint: workingDuration <= rawWorkoutDuration.
    /// - Calculates pace using pure aggregate ratios (workingDuration / workingDistanceKm) to eliminate harmonic distortion.
    func calculateWorkingAverages(
        trimmed: [BucketData],
        rawWorkoutDuration: Double? = nil,
        rawWorkoutDistance: Double? = nil,
        originalBucketCount: Int? = nil,
        rawAvgStrideLength: Double? = nil
    ) -> (workingPace: Double, workingCadence: Double, workingHR: Double, workingOscillation: Double, workingDistance: Double, workingDuration: Double, workingStrideLength: Double?) {
        guard !trimmed.isEmpty else { return (0, 0, 0, 0, 0, 0, nil) }

        var totalDistanceMeters: Double = 0
        var totalCadence: Double = 0
        var totalHR: Double = 0
        var totalOscillation: Double = 0
        var totalStrideLength: Double = 0
        var oscillationBucketCount: Int = 0
        var validHRBucketCount: Int = 0
        var strideBucketCount: Int = 0

        for bucket in trimmed {
            totalDistanceMeters += bucket.distanceMeters
            totalCadence += bucket.meanCadence

            if bucket.meanHR >= 40 {
                totalHR += bucket.meanHR
                validHRBucketCount += 1
            }

            if bucket.meanVerticalOscillation > 0 {
                totalOscillation += bucket.meanVerticalOscillation
                oscillationBucketCount += 1
            }

            if bucket.meanStrideLength > 0 {
                totalStrideLength += bucket.meanStrideLength
                strideBucketCount += 1
            }
        }

        // If no buckets were trimmed (no dead stops), Working stats MUST perfectly equal Raw stats
        let isFullyActive = (originalBucketCount != nil) && (trimmed.count == originalBucketCount)

        // Strictly sum the duration of only the kept/filtered samples
        let trimmedDuration = trimmed.reduce(0) { $0 + $1.durationSeconds }
        var workingDuration = isFullyActive ? (rawWorkoutDuration ?? trimmedDuration) : trimmedDuration

        // Hard safety constraint: workingDuration must be <= rawWorkout.duration
        if !isFullyActive, let rawDuration = rawWorkoutDuration, rawDuration > 0 {
            workingDuration = min(workingDuration, rawDuration)
        }

        // Pure aggregate ratio: Divide newly calculated workingDuration (in seconds) by workingDistance (in kilometers)
        let workingDistanceKm = isFullyActive ? ((rawWorkoutDistance ?? totalDistanceMeters) / 1000.0) : (totalDistanceMeters / 1000.0)
        let workingDistanceMetersFinal = isFullyActive ? (rawWorkoutDistance ?? totalDistanceMeters) : totalDistanceMeters
        let workingPace = workingDistanceKm > 0 ? (workingDuration / workingDistanceKm) : 0.0

        let workingCadence = totalCadence / Double(trimmed.count)
        let workingHR = validHRBucketCount > 0 ? (totalHR / Double(validHRBucketCount)) : 0.0
        let workingOscillation = oscillationBucketCount > 0 ? (totalOscillation / Double(oscillationBucketCount)) : 0.0

        let workingStrideLength: Double? = {
            if isFullyActive, let rawStride = rawAvgStrideLength, rawStride > 0 {
                return rawStride
            }
            if strideBucketCount > 0 {
                return totalStrideLength / Double(strideBucketCount)
            }
            return rawAvgStrideLength
        }()

        return (workingPace, workingCadence, workingHR, workingOscillation, workingDistanceMetersFinal, workingDuration, workingStrideLength)
    }

    // MARK: - Mathematical Features

    /// Calculates the Coefficient of Variation (CV = sigma / mu) for pace across buckets.
    func calculatePaceCV(bucketPaces: [Double]) -> Double {
        guard bucketPaces.count > 1 else { return 0 }
        let validPaces = bucketPaces.filter { $0 > 0 && $0.isFinite }
        guard validPaces.count > 1 else { return 0 }

        let mu = validPaces.reduce(0, +) / Double(validPaces.count)
        guard mu > 0 else { return 0 }

        let sumSquaredDiff = validPaces.reduce(0) { $0 + pow($1 - mu, 2) }
        let variance = sumSquaredDiff / Double(validPaces.count - 1)
        let sigma = sqrt(variance)

        return sigma / mu
    }

    /// Calculates the Coefficient of Variation (CV = sigma / mu) for cadence across buckets.
    func calculateCadenceCV(bucketCadences: [Double]) -> Double {
        guard bucketCadences.count > 1 else { return 0 }
        let validCadences = bucketCadences.filter { $0 > 0 && $0.isFinite }
        guard validCadences.count > 1 else { return 0 }

        let mu = validCadences.reduce(0, +) / Double(validCadences.count)
        guard mu > 0 else { return 0 }

        let sumSquaredDiff = validCadences.reduce(0) { $0 + pow($1 - mu, 2) }
        let variance = sumSquaredDiff / Double(validCadences.count - 1)
        let sigma = sqrt(variance)

        return sigma / mu
    }

    /// Calculates the linear regression slope of pace over time (least-squares).
    /// Negative slope = speeding up (progression). Positive slope = slowing down (fatigue).
    func calculatePaceSlope(bucketPaces: [Double]) -> Double {
        guard bucketPaces.count > 1 else { return 0 }
        let validPaces = bucketPaces.filter { $0 > 0 && $0.isFinite }
        let n = Double(validPaces.count)
        guard n > 1 else { return 0 }

        var sumX: Double = 0
        var sumY: Double = 0
        var sumXY: Double = 0
        var sumX2: Double = 0

        for (i, y) in validPaces.enumerated() {
            let x = Double(i)
            sumX += x
            sumY += y
            sumXY += x * y
            sumX2 += x * x
        }

        let denominator = (n * sumX2) - (sumX * sumX)
        guard denominator != 0 else { return 0 }

        let slope = ((n * sumXY) - (sumX * sumY)) / denominator
        return slope
    }

    /// Calculates the linear regression slope of cadence over time (least-squares).
    func calculateCadenceSlope(bucketCadences: [Double]) -> Double {
        guard bucketCadences.count > 1 else { return 0 }
        let validCadences = bucketCadences.filter { $0 > 0 && $0.isFinite }
        let n = Double(validCadences.count)
        guard n > 1 else { return 0 }

        var sumX: Double = 0
        var sumY: Double = 0
        var sumXY: Double = 0
        var sumX2: Double = 0

        for (i, y) in validCadences.enumerated() {
            let x = Double(i)
            sumX += x
            sumY += y
            sumXY += x * y
            sumX2 += x * x
        }

        let denominator = (n * sumX2) - (sumX * sumX)
        guard denominator != 0 else { return 0 }

        return ((n * sumXY) - (sumX * sumY)) / denominator
    }

    /// Calculates the Coefficient of Variation (CV = sigma / mu) for heart rate across buckets.
    func calculateHRCV(bucketHRs: [Double]) -> Double {
        guard bucketHRs.count > 1 else { return 0 }
        let validHRs = bucketHRs.filter { $0 >= 40 && $0.isFinite }
        guard validHRs.count > 1 else { return 0 }

        let mu = validHRs.reduce(0, +) / Double(validHRs.count)
        guard mu > 0 else { return 0 }

        let sumSquaredDiff = validHRs.reduce(0) { $0 + pow($1 - mu, 2) }
        let variance = sumSquaredDiff / Double(validHRs.count - 1)
        let sigma = sqrt(variance)

        return sigma / mu
    }

    /// Defensive treadmill heuristics for wrist accelerometer guesswork:
    /// Applies rolling median filtering to pace and clamps wild outlier spikes (> 25% away from median).
    func applyIndoorWristPaceSmoothing(buckets: [BucketData]) -> [BucketData] {
        guard buckets.count >= 3 else { return buckets }
        let validPaces = buckets.map(\.meanPaceSecPerKm).filter { $0 > 0 }.sorted()
        guard !validPaces.isEmpty else { return buckets }
        let overallMedianPace = validPaces[validPaces.count / 2]

        let minAllowedPace = overallMedianPace * 0.75
        let maxAllowedPace = overallMedianPace * 1.25

        var smoothedBuckets: [BucketData] = []
        smoothedBuckets.reserveCapacity(buckets.count)

        for i in 0..<buckets.count {
            let start = max(0, i - 1)
            let end = min(buckets.count - 1, i + 1)
            let window = Array(buckets[start...end])
            let windowPaces = window.map(\.meanPaceSecPerKm).sorted()
            var medianWindowPace = windowPaces[windowPaces.count / 2]

            // Clamp outliers exceeding 25% from overall median
            if medianWindowPace < minAllowedPace {
                medianWindowPace = minAllowedPace
            } else if medianWindowPace > maxAllowedPace {
                medianWindowPace = maxAllowedPace
            }

            let original = buckets[i]
            smoothedBuckets.append(BucketData(
                startTime: original.startTime,
                distanceMeters: original.distanceMeters,
                durationSeconds: original.durationSeconds,
                meanPaceSecPerKm: medianWindowPace,
                meanCadence: original.meanCadence,
                meanHR: original.meanHR,
                meanVerticalOscillation: original.meanVerticalOscillation,
                meanStrideLength: original.meanStrideLength,
                elevationGainMeters: original.elevationGainMeters
            ))
        }

        return smoothedBuckets
    }

    /// Segments continuous buckets into Work, Recovery, Steady, or Walking windows for the Variance Map and Interval Card.
    func generatePhaseSegments(from buckets: [BucketData], cadenceFloor: Double = 150.0) -> [PhaseSegment] {
        guard !buckets.isEmpty else { return [] }

        let moving = buckets.filter { $0.meanCadence >= 135 }
        let medCad = moving.isEmpty ? 160.0 : moving.map(\.meanCadence).sorted()[moving.count / 2]
        let validPaces = moving.map(\.meanPaceSecPerKm).filter { $0 > 0 }.sorted()
        let medPace = validPaces.isEmpty ? 300.0 : validPaces[validPaces.count / 2]
        let p20 = validPaces.isEmpty ? medPace : validPaces[validPaces.count / 5]
        let paceCV = calculatePaceCV(bucketPaces: validPaces)
        let hasLargePaceRange = (medPace - p20) >= 30.0

        // If pace variability across moving buckets is minimal (CV < 0.10 and pace spread < 20s),
        // this is deterministically a uniform/steady run. Do not segment into fake work/recovery bouts.
        let isUniformSteady = paceCV < 0.10 && (medPace - p20) < 20.0
        let surgePaceThreshold = hasLargePaceRange ? min(medPace - 30.0, p20 + 20.0) : (medPace - 20.0)

        var raw: [PhaseSegment] = []
        var curKind = ""
        var segStart: Double = 0
        var pSum = 0.0, cSum = 0.0, hrSum = 0.0, count = 0.0, elapsed = 0.0

        for (index, b) in buckets.enumerated() {
            // 20-bucket rolling centered window (as mandated by AGENTS.md ADR-0006/0007)
            let windowSize = 20
            let windowStart = max(0, index - windowSize / 2)
            let windowEnd = min(buckets.count - 1, index + windowSize / 2)
            let localWindow = buckets[windowStart...windowEnd].filter { $0.meanCadence >= 135 }

            let localMedCad: Double = {
                guard !localWindow.isEmpty else { return medCad }
                let sorted = localWindow.map(\.meanCadence).sorted()
                return sorted[sorted.count / 2]
            }()
            let localPaces = localWindow.map(\.meanPaceSecPerKm).filter { $0 > 0 }.sorted()
            let localMedPace: Double = {
                guard !localPaces.isEmpty else { return medPace }
                return localPaces[localPaces.count / 2]
            }()

            let isSurge = !isUniformSteady && (
                (b.meanPaceSecPerKm > 0 && b.meanPaceSecPerKm <= (localMedPace - 15.0) && b.meanCadence >= localMedCad - 1.0)
                || (b.meanCadence >= (localMedCad + 2.0) && b.meanPaceSecPerKm > 0 && b.meanPaceSecPerKm <= localMedPace)
                || (b.meanPaceSecPerKm > 0 && b.meanPaceSecPerKm <= surgePaceThreshold && b.meanCadence >= cadenceFloor)
            )

            let isRec = !isUniformSteady && (
                b.meanPaceSecPerKm >= (localMedPace + 15.0)
                || (b.meanCadence <= localMedCad - 2.0)
                || (b.meanCadence < cadenceFloor)
            )

            let kind = (b.meanCadence < cadenceFloor && b.meanCadence < 135.0) ? "walking" : (isSurge ? "work" : (isRec ? "recovery" : "steady"))

            if curKind.isEmpty {
                curKind = kind
                segStart = elapsed
            } else if curKind != kind {
                raw.append(PhaseSegment(
                    startSeconds: segStart,
                    endSeconds: elapsed,
                    kind: curKind,
                    avgPace: count > 0 ? pSum / count : 0,
                    avgCadence: count > 0 ? cSum / count : 0,
                    avgHR: count > 0 ? hrSum / count : 0
                ))
                curKind = kind
                segStart = elapsed
                pSum = 0; cSum = 0; hrSum = 0; count = 0
            }

            pSum += b.meanPaceSecPerKm
            cSum += b.meanCadence
            if b.meanHR > 0 { hrSum += b.meanHR }
            count += 1.0
            elapsed += b.durationSeconds
        }

        if !curKind.isEmpty && elapsed > segStart {
            raw.append(PhaseSegment(
                startSeconds: segStart,
                endSeconds: elapsed,
                kind: curKind,
                avgPace: count > 0 ? pSum / count : 0,
                avgCadence: count > 0 ? cSum / count : 0,
                avgHR: count > 0 ? hrSum / count : 0
            ))
        }

        var consolidated = Self.consolidatePhaseSegments(raw)

        // Minimum Repetition Gate:
        // True interval classification requires workRepCount >= 2
        // (at least two distinct work surges separated by a recovery/steady trough).
        // A single speed-up or a warm-up followed by steady running is NEVER an interval session.
        let workSegmentsCount = consolidated.filter { $0.kind == "work" }.count
        if workSegmentsCount < 2 {
            consolidated = consolidated.map { seg in
                if seg.kind == "work" || seg.kind == "recovery" {
                    return PhaseSegment(
                        startSeconds: seg.startSeconds,
                        endSeconds: seg.endSeconds,
                        kind: "steady",
                        avgPace: seg.avgPace,
                        avgCadence: seg.avgCadence,
                        avgHR: seg.avgHR
                    )
                }
                return seg
            }

            var coalesced: [PhaseSegment] = []
            for seg in consolidated {
                if let last = coalesced.last, last.kind == seg.kind {
                    coalesced[coalesced.count - 1] = Self.mergeSegments(last, seg)
                } else {
                    coalesced.append(seg)
                }
            }
            consolidated = coalesced
        }

        return consolidated
    }

    /// Merges fragmented work segments separated by brief dips and filters out stray warmup/cooldown surges.
    static func consolidatePhaseSegments(_ segments: [PhaseSegment]) -> [PhaseSegment] {
        guard !segments.isEmpty else { return [] }

        // Step 1: Gap bridging: merge work segments separated by brief momentary flutter (<= 15s any) or steady compound transitions (<= 75s steady without recovery drop)
        var bridged: [PhaseSegment] = []
        for seg in segments {
            if let last = bridged.last, last.kind == "work" && seg.kind == "work" {
                bridged[bridged.count - 1] = mergeSegments(last, seg)
            } else if bridged.count >= 2,
                      seg.kind == "work",
                      let gap = bridged.last,
                      gap.kind != "work",
                      gap.durationSeconds <= 15.0 || (gap.kind == "steady" && gap.durationSeconds <= 75.0),
                      bridged[bridged.count - 2].kind == "work" {
                _ = bridged.removeLast()
                let prev = bridged.removeLast()
                bridged.append(mergeSegments(prev, seg))
            } else {
                bridged.append(seg)
            }
        }

        // Step 2: Outlier rejection: remove stray pickups vastly slower or shorter than true work reps
        let workPaces = bridged.filter { $0.kind == "work" && $0.avgPace > 0 }.map(\.avgPace).sorted()
        var filtered = bridged
        if workPaces.count >= 4 {
            let medWork = workPaces[workPaces.count / 2]

            filtered = bridged.map { seg in
                if seg.kind == "work" {
                    let isVastlySlower = (seg.avgPace > medWork + 45.0 && seg.avgCadence < 162.0)
                    let isMicroGlitch = seg.durationSeconds <= 20.0 && seg.avgPace > medWork + 20.0
                    let isTooBrief = seg.durationSeconds < 14.0

                    if isVastlySlower || isMicroGlitch || isTooBrief {
                        return PhaseSegment(startSeconds: seg.startSeconds, endSeconds: seg.endSeconds, kind: "steady", avgPace: seg.avgPace, avgCadence: seg.avgCadence, avgHR: seg.avgHR)
                    }
                }
                return seg
            }
        }

        // Step 3: Isolated Warmup / Cooldown Strides (separated by >= 240s-300s from clustered work set)
        let workIdxs = filtered.enumerated().filter { $0.element.kind == "work" }.map(\.offset)
        if workIdxs.count >= 4 {
            let workDurs = workIdxs.map { filtered[$0].durationSeconds }
            let medWorkDur = workDurs.sorted()[workDurs.count / 2]

            // Check warmup stride: must be separated by >= 240s steady gap AND be significantly shorter than set reps
            let firstWork = workIdxs[0], secondWork = workIdxs[1]
            let gapBeforeSet = filtered[secondWork].startSeconds - filtered[firstWork].endSeconds
            var gaps: [Double] = []
            for i in 1..<(workIdxs.count - 1) {
                gaps.append(filtered[workIdxs[i + 1]].startSeconds - filtered[workIdxs[i]].endSeconds)
            }
            let medGap = gaps.isEmpty ? 90.0 : gaps.sorted()[gaps.count / 2]
            if gapBeforeSet >= 240.0 && medGap <= 150.0 && filtered[firstWork].durationSeconds <= medWorkDur * 0.65 {
                let w = filtered[firstWork]
                filtered[firstWork] = PhaseSegment(startSeconds: w.startSeconds, endSeconds: w.endSeconds, kind: "steady", avgPace: w.avgPace, avgCadence: w.avgCadence, avgHR: w.avgHR)
            }
            // Check cooldown surge: must be separated by >= 300s steady gap AND be significantly shorter than set reps
            let lastWork = workIdxs[workIdxs.count - 1], penWork = workIdxs[workIdxs.count - 2]
            let gapAfterSet = filtered[lastWork].startSeconds - filtered[penWork].endSeconds
            if gapAfterSet >= 300.0 && medGap <= 150.0 && filtered[lastWork].durationSeconds <= medWorkDur * 0.65 {
                let w = filtered[lastWork]
                filtered[lastWork] = PhaseSegment(startSeconds: w.startSeconds, endSeconds: w.endSeconds, kind: "steady", avgPace: w.avgPace, avgCadence: w.avgCadence, avgHR: w.avgHR)
            }
        }

        // Step 4: Speed Contrast Validation between candidate work and recovery
        let candidateWorks = filtered.filter { $0.kind == "work" && $0.avgPace > 0 }
        let candidateRecs = filtered.filter { $0.kind == "recovery" && $0.avgPace > 0 }
        if !candidateWorks.isEmpty && !candidateRecs.isEmpty {
            let avgWorkPace = candidateWorks.map(\.avgPace).reduce(0, +) / Double(candidateWorks.count)
            let avgRecPace = candidateRecs.map(\.avgPace).reduce(0, +) / Double(candidateRecs.count)
            let contrast = avgRecPace - avgWorkPace
            // If work bouts are not at least 20 s/km faster than recovery, these are not genuine interval reps
            if contrast < 20.0 {
                filtered = filtered.map { seg in
                    if seg.kind == "work" || seg.kind == "recovery" {
                        return PhaseSegment(startSeconds: seg.startSeconds, endSeconds: seg.endSeconds, kind: "steady", avgPace: seg.avgPace, avgCadence: seg.avgCadence, avgHR: seg.avgHR)
                    }
                    return seg
                }
            }
        }

        // Step 5: Coalesce adjacent identical kinds
        var finalSegments: [PhaseSegment] = []
        for seg in filtered {
            if let last = finalSegments.last, last.kind == seg.kind {
                finalSegments[finalSegments.count - 1] = mergeSegments(last, seg)
            } else {
                finalSegments.append(seg)
            }
        }

        return finalSegments
    }

    static func mergeSegments(_ a: PhaseSegment, _ b: PhaseSegment) -> PhaseSegment {
        let durA = a.durationSeconds
        let durB = b.durationSeconds
        let activeDur = durA + durB
        return PhaseSegment(
            startSeconds: a.startSeconds,
            endSeconds: b.endSeconds,
            kind: a.kind,
            avgPace: activeDur > 0 ? (a.avgPace * durA + b.avgPace * durB) / activeDur : a.avgPace,
            avgCadence: activeDur > 0 ? (a.avgCadence * durA + b.avgCadence * durB) / activeDur : a.avgCadence,
            avgHR: activeDur > 0 ? (a.avgHR * durA + b.avgHR * durB) / activeDur : a.avgHR
        )
    }

    /// Calculates the fraction of time spent in Zone 4 (or higher).
    func calculatePercentZone4(bucketHRs: [Double], maxHR: Double) -> Double {
        guard maxHR > 0, !bucketHRs.isEmpty else { return 0 }
        // Zone 4 typically starts around 80-85% of max HR. Let's use 85%.
        let zone4Threshold = maxHR * 0.85
        let zone4Count = bucketHRs.filter { $0 >= zone4Threshold }.count
        return Double(zone4Count) / Double(bucketHRs.count)
    }

    // MARK: - Classification (Topological Signature & Physiological Weighted Engine)

    /// Smooths the cadence time series using a 2-bucket (30-second) sliding window average.
    func smoothCadences(buckets: [BucketData]) -> [Double] {
        guard !buckets.isEmpty else { return [] }
        var smoothed: [Double] = []
        smoothed.reserveCapacity(buckets.count)
        for index in 0..<buckets.count {
            let start = max(0, index - 1)
            let end = min(buckets.count, index + 2)
            let slice = buckets[start..<end]
            let avg = slice.map(\.meanCadence).reduce(0, +) / Double(slice.count)
            smoothed.append(avg)
        }
        return smoothed
    }

    /// Extracts corroborated surge-and-recovery oscillation cycles from the bucket time series.
    func extractOscillationCycles(buckets: [BucketData]) -> [SurgeRecoveryCycle] {
        guard buckets.count >= 4 else { return [] }

        let smoothed = smoothCadences(buckets: buckets)

        struct CandidatePhase {
            let isSurge: Bool
            var duration: Double
            var buckets: [BucketData]

            var avgCadence: Double {
                buckets.isEmpty ? 0 : (buckets.map(\.meanCadence).reduce(0, +) / Double(buckets.count))
            }
            var avgPace: Double {
                buckets.isEmpty ? 0 : (buckets.map(\.meanPaceSecPerKm).reduce(0, +) / Double(buckets.count))
            }
            var avgHR: Double {
                let validHRs = buckets.map(\.meanHR).filter { $0 > 0 }
                return validHRs.isEmpty ? 0 : (validHRs.reduce(0, +) / Double(validHRs.count))
            }
        }

        var phases: [CandidatePhase] = []
        var currentIsSurge = false
        var currentBuckets: [BucketData] = []

        for index in 0..<buckets.count {
            let windowSize = 20
            let windowStart = max(0, index - windowSize / 2)
            let windowEnd = min(buckets.count - 1, index + windowSize / 2)
            let window = buckets[windowStart...windowEnd]
            let localMeanCadence = window.map(\.meanCadence).reduce(0, +) / Double(window.count)
            let isSurge = smoothed[index] >= localMeanCadence

            if index == 0 {
                currentIsSurge = isSurge
                currentBuckets.append(buckets[index])
            } else if isSurge == currentIsSurge {
                currentBuckets.append(buckets[index])
            } else {
                let dur = currentBuckets.map(\.durationSeconds).reduce(0, +)
                phases.append(CandidatePhase(isSurge: currentIsSurge, duration: dur, buckets: currentBuckets))
                currentIsSurge = isSurge
                currentBuckets = [buckets[index]]
            }
        }
        if !currentBuckets.isEmpty {
            let dur = currentBuckets.map(\.durationSeconds).reduce(0, +)
            phases.append(CandidatePhase(isSurge: currentIsSurge, duration: dur, buckets: currentBuckets))
        }

        // Debounce: Merge brief glitch phases (< 20 seconds) into surrounding contiguous phase of the same type
        var debouncedPhases: [CandidatePhase] = []
        for phase in phases {
            if let last = debouncedPhases.last, last.isSurge == phase.isSurge {
                debouncedPhases[debouncedPhases.count - 1].buckets.append(contentsOf: phase.buckets)
                debouncedPhases[debouncedPhases.count - 1].duration += phase.duration
            } else if debouncedPhases.count >= 2,
                      phase.isSurge,
                      let prev = debouncedPhases.last,
                      !prev.isSurge,
                      prev.duration < 20.0,
                      debouncedPhases[debouncedPhases.count - 2].isSurge {
                let glitch = debouncedPhases.removeLast()
                debouncedPhases[debouncedPhases.count - 1].buckets.append(contentsOf: glitch.buckets)
                debouncedPhases[debouncedPhases.count - 1].buckets.append(contentsOf: phase.buckets)
                debouncedPhases[debouncedPhases.count - 1].duration += (glitch.duration + phase.duration)
            } else {
                debouncedPhases.append(phase)
            }
        }
        phases = debouncedPhases

        var cycles: [SurgeRecoveryCycle] = []
        var usedRecoveryIndices: Set<Int> = []

        for index in 0..<phases.count where phases[index].isSurge {
            let surge = phases[index]

            var recoveryIndex: Int?
            if index + 1 < phases.count,
               !phases[index + 1].isSurge,
               !usedRecoveryIndices.contains(index + 1),
               phases[index + 1].duration >= 20.0,
               phases[index + 1].avgPace > surge.avgPace + 5.0 {
                recoveryIndex = index + 1
            } else if index > 0 && !phases[index - 1].isSurge && !usedRecoveryIndices.contains(index - 1) {
                recoveryIndex = index - 1
            } else if index > 0 && !phases[index - 1].isSurge {
                // Terminal surge fallback: If no valid succeeding recovery exists,
                // allow pairing with the immediate preceding recovery interval even if already used.
                recoveryIndex = index - 1
            }

            guard let recIdx = recoveryIndex else { continue }
            let recovery = phases[recIdx]

            // Minimum duration guards: Surge >= 15s, Recovery >= 20s
            guard surge.duration >= 15.0, recovery.duration >= 20.0 else { continue }

            // Multi-signal corroboration:
            // 1. Cadence: Surge >= Recovery + 5 SPM (realistic turnover increase)
            let cadenceDiff = surge.avgCadence - recovery.avgCadence
            let cadenceCorroborated = cadenceDiff >= 5.0

            // 2. Pace: Surge >= 15 sec/km faster than Recovery
            let paceDiff = recovery.avgPace - surge.avgPace
            let paceCorroborated = paceDiff >= 15.0

            // 3. Heart Rate: Surge >= Recovery + 3 BPM (accounting for cardiac lag / EPOC in recovery jogs)
            let hrDiff = (surge.avgHR > 0 && recovery.avgHR > 0) ? (surge.avgHR - recovery.avgHR) : 0.0
            let hrCorroborated = hrDiff >= 3.0

            let corroborationScore = (cadenceCorroborated ? 1 : 0) + (paceCorroborated ? 1 : 0) + (hrCorroborated ? 1 : 0)

            // Dominant Pace Surge: A substantial pace surge (>= 30 s/km) with supporting biometric signal
            // (>= 3 SPM cadence increase or >= 2 BPM HR increase), or >= 45 s/km sheer pace differential.
            let isDominantPaceSurge = (paceDiff >= 30.0 && (cadenceDiff >= 3.0 || hrDiff >= 2.0)) || (paceDiff >= 45.0)

            // Valid interval cycle requires either:
            // 1. Dominant pace surge (>= 30-45 s/km)
            // 2. Corroborated biometric & velocity surge (corroborationScore >= 2 AND work is faster than recovery: paceDiff >= 5.0 s/km)
            let isCorroboratedCycle = (corroborationScore >= 2 && paceDiff >= 5.0) || isDominantPaceSurge

            if isCorroboratedCycle {
                usedRecoveryIndices.insert(recIdx)
                cycles.append(SurgeRecoveryCycle(
                    workDuration: surge.duration,
                    recoveryDuration: recovery.duration,
                    workCadence: surge.avgCadence,
                    recoveryCadence: recovery.avgCadence,
                    workPace: surge.avgPace,
                    recoveryPace: recovery.avgPace,
                    workHR: surge.avgHR,
                    recoveryHR: recovery.avgHR,
                    isCorroborated: true
                ))
            }
        }

        return cycles
    }

    /// Evaluates the regularity of work and recovery durations across validated oscillation cycles.
    /// Returns 0.0 to 1.0 (higher = more metronomic/regular).
    func calculateCycleRegularity(cycles: [SurgeRecoveryCycle]) -> Double {
        guard cycles.count >= 2 else { return 0.0 }
        let workDurations = cycles.map(\.workDuration)
        let recDurations = cycles.map(\.recoveryDuration)

        let meanWork = workDurations.reduce(0, +) / Double(workDurations.count)
        let meanRec = recDurations.reduce(0, +) / Double(recDurations.count)

        guard meanWork > 0, meanRec > 0 else { return 0.0 }

        let workVariance = workDurations.map { pow($0 - meanWork, 2) }.reduce(0, +) / Double(workDurations.count)
        let workCV = sqrt(workVariance) / meanWork

        let recVariance = recDurations.map { pow($0 - meanRec, 2) }.reduce(0, +) / Double(recDurations.count)
        let recCV = sqrt(recVariance) / meanRec

        let score = 1.0 - ((workCV + recCV) / 2.0)
        return max(0.0, min(1.0, score))
    }

    /// Evaluates whether the run exhibits monotonic quintile progression (accelerating pace across the run).
    func evaluateQuintileProgression(buckets: [BucketData]) -> Bool {
        guard buckets.count >= 5 else { return false }
        let quintileSize = buckets.count / 5
        var quintilePaces: [Double] = []
        for index in 0..<5 {
            let start = index * quintileSize
            let end = (index == 4) ? buckets.count : (index + 1) * quintileSize
            let slice = buckets[start..<end]
            guard !slice.isEmpty else { return false }
            let avgPace = slice.map(\.meanPaceSecPerKm).reduce(0, +) / Double(slice.count)
            quintilePaces.append(avgPace)
        }

        var fasterTransitions = 0
        var slowerTransitions = 0
        for index in 0..<4 {
            if quintilePaces[index + 1] < quintilePaces[index] - 2.0 {
                fasterTransitions += 1
            } else if quintilePaces[index + 1] > quintilePaces[index] + 2.0 {
                slowerTransitions += 1
            }
        }

        let minPace = quintilePaces.min() ?? Double.infinity
        let q5IsFastest = (quintilePaces[4] <= minPace + 0.5)

        return fasterTransitions >= 3 && slowerTransitions == 0 && q5IsFastest
    }

    // MARK: - Extended Taxonomic Classifiers (ADR-0008)

    /// Calculates the mean cadence of the slowest 20% pace buckets or recovery phases, representing the recovery floor.
    func calculateRecoveryCadenceFloor(buckets: [BucketData], cycles: [SurgeRecoveryCycle] = []) -> Double {
        if !cycles.isEmpty {
            return cycles.map(\.recoveryCadence).reduce(0, +) / Double(cycles.count)
        }
        guard !buckets.isEmpty else { return 0.0 }
        let sortedByPace = buckets.sorted { $0.meanPaceSecPerKm > $1.meanPaceSecPerKm }
        let sliceCount = max(1, Int(Double(sortedByPace.count) * 0.20))
        let slowest = sortedByPace.prefix(sliceCount)
        return slowest.map(\.meanCadence).reduce(0, +) / Double(sliceCount)
    }

    /// Evaluates the duration symmetry of intermittent work intervals to identify pyramid structures.
    /// Returns 0.0 to 1.0 (higher = symmetric expanding and contracting ladder, e.g. 1-2-3-2-1 mins).
    func calculateWorkBlockSymmetry(cycles: [SurgeRecoveryCycle]) -> Double {
        guard cycles.count >= 3 else { return 0.0 }
        let workDurations = cycles.map(\.workDuration)
        guard let maxVal = workDurations.max(),
              let maxIdx = workDurations.firstIndex(of: maxVal) else { return 0.0 }

        // In a true pyramid, peak must be an interior rep (not start or finish)
        guard maxIdx > 0 && maxIdx < workDurations.count - 1 else { return 0.0 }

        // Monotonic climb up to peak: each step must be >= previous step (with 5s tolerance)
        for i in 0..<maxIdx where workDurations[i + 1] < workDurations[i] - 5.0 {
            return 0.0
        }

        // Monotonic descent down from peak: each step must be <= previous step (with 5s tolerance)
        for i in maxIdx..<workDurations.count - 1 where workDurations[i + 1] > workDurations[i] + 5.0 {
            return 0.0
        }

        // Peak must expand substantially above the base (at least 25% longer)
        guard let firstWork = workDurations.first,
              let lastWork = workDurations.last,
              maxVal >= firstWork * 1.25 && maxVal >= lastWork * 1.25 else { return 0.0 }

        let n = workDurations.count
        var diffSum = 0.0
        let comparisons = n / 2
        for i in 0..<comparisons {
            diffSum += abs(workDurations[i] - workDurations[n - 1 - i])
        }
        let totalWork = workDurations.reduce(0, +)
        guard totalWork > 0 else { return 0.0 }

        let symmetry = max(0.0, 1.0 - ((diffSum * 2.0) / totalWork))
        return symmetry
    }

    /// Evaluates non-periodic cadence crashes (< 70 SPM) and pace dropouts characteristic of city running (stoplights, crosswalks).
    /// Returns a ratio from 0.0 to 1.0 representing chaotic dead stops relative to total buckets.
    func detectUrbanTrafficEntropy(buckets: [BucketData]) -> Double {
        guard buckets.count >= 8 else { return 0.0 }
        var stopDurations: [Double] = []
        var currentStopDuration = 0.0
        var totalStopDuration = 0.0

        for b in buckets {
            if b.meanCadence < 70.0 || b.meanPaceSecPerKm > 600.0 {
                currentStopDuration += b.durationSeconds
                totalStopDuration += b.durationSeconds
            } else if currentStopDuration > 0 {
                stopDurations.append(currentStopDuration)
                currentStopDuration = 0.0
            }
        }
        if currentStopDuration > 0 {
            stopDurations.append(currentStopDuration)
        }

        guard stopDurations.count >= 3 else { return 0.0 }
        let totalDuration = buckets.map(\.durationSeconds).reduce(0, +)
        guard totalDuration > 0 else { return 0.0 }

        // Check for brief, chaotic durations (predominantly 5s - 30s)
        let meanStop = stopDurations.reduce(0, +) / Double(stopDurations.count)

        if meanStop <= 30.0 {
            return totalStopDuration / totalDuration
        }
        return 0.0
    }

    /// Detects repeated saw-tooth elevation climbs synchronized with cardiac surges.
    func detectHillRepeats(buckets: [BucketData]) -> Bool {
        guard buckets.count >= 6 else { return false }
        let totalGain = buckets.map(\.elevationGainMeters).reduce(0, +)
        guard totalGain >= 35.0 else { return false }

        var climbEpisodes = 0
        var inClimb = false
        for b in buckets {
            let isClimbing = b.elevationGainMeters >= 4.0
            if isClimbing && !inClimb {
                inClimb = true
                climbEpisodes += 1
            } else if !isClimbing && inClimb {
                inClimb = false
            }
        }
        return climbEpisodes >= 3
    }

    /// Multi-delta weighted classification engine enforcing turnover stability,
    /// topological oscillation signatures, cardiac strain guardrails, and pacing trends.
    func classifyRun(
        buckets: [BucketData],
        cv: Double,
        slope: Double,
        zone4: Double,
        durationMinutes: Double,
        cadenceCV: Double = 0.0,
        averageHR: Double? = nil,
        paceDelta: Double? = nil,
        hrDelta: Double? = nil,
        cycles: [SurgeRecoveryCycle]? = nil,
        deadStopsCount: Int = 0,
        hoursSinceHeavyEffort: Double? = nil
    ) -> String {
        // LAYER 0: Environmental Interruption (Urban Traffic)
        let trafficEntropy = detectUrbanTrafficEntropy(buckets: buckets)
        let isChaoticTraffic = (trafficEntropy >= 0.04 || (deadStopsCount >= 4 && cv > 0.10))

        // LAYER 1: Continuous Monotonic Progression (Strict low-variance progressive acceleration)
        let isProgression = durationMinutes >= 20.0 && cv < 0.09 && evaluateQuintileProgression(buckets: buckets)
        if isProgression {
            return "Progression Run"
        }

        // CV < 0.10 Gating: Classify strictly as Steady State or Progression.
        // If CV < 0.10, bypass intermittent and traffic layers to enforce continuous steady classifications.
        let isUniformSteady = cv < 0.10

        // LAYER 2: Structural Gate (Intermittent vs. Continuous)
        // Interval classification strictly requires calculatePaceCV >= 0.12, workRepCount >= 2 cycles,
        // and minimum speed contrast delta of workPace <= recoveryPace - 25.0 s/km.
        let cycles = cycles ?? extractOscillationCycles(buckets: buckets)
        let avgCycleContrast = cycles.isEmpty ? 0.0 : (cycles.map { $0.recoveryPace - $0.workPace }.reduce(0, +) / Double(cycles.count))
        let isIntermittent = !isUniformSteady && cv >= 0.12 && cycles.count >= 2 && avgCycleContrast >= 25.0
        let regularityScore = isIntermittent ? calculateCycleRegularity(cycles: cycles) : 0.0

        // If traffic was chaotic and it's not a structured threshold interval workout, classify as Urban Traffic
        if !isUniformSteady && isChaoticTraffic && (zone4 < 0.35 || regularityScore < 0.65) {
            return "Urban Traffic"
        }

        // LAYER 2.5: Topographic Sawtooth Climbs (Hill Repeats)
        if detectHillRepeats(buckets: buckets) {
            return "Hill Repeats"
        }

        // LAYER 3: Intermittent Sub-Classification (Pyramids vs. Intervals vs. Fartlek)
        if isIntermittent {
            let symmetryScore = calculateWorkBlockSymmetry(cycles: cycles)
            if symmetryScore >= 0.70 {
                return "Pyramids"
            }

            let recoveryFloor = calculateRecoveryCadenceFloor(buckets: buckets, cycles: cycles)
            return (recoveryFloor < 120.0 || regularityScore >= 0.65) ? "Intervals" : "Fartlek"
        }

        // LAYER 4: Continuous Structural Archetypes (Volume & Fatigue)
        if durationMinutes >= 68.0 && slope > -0.20 && zone4 < 0.45 {
            return "Long Run"
        }

        // LAYER 5: Continuous Intensity Matrix (Zone 4 + HR Strain + Pace Delta)
        let z4Score = min(100.0, zone4 * 125.0)

        let hrScore: Double = {
            if let hr = averageHR {
                if hr >= 170 { return min(100.0, 85.0 + (hr - 170.0) * 1.5) }
                if hr >= 160 { return 70.0 + (hr - 160.0) * 1.5 }
                if hr >= 145 { return 45.0 + (hr - 145.0) * 1.6 }
                if hr >= 130 { return 25.0 + (hr - 130.0) * 1.3 }
                return max(10.0, hr - 110.0)
            } else if let delta = hrDelta {
                if delta >= 15 { return min(100.0, 85.0 + (delta - 15.0) * 1.5) }
                if delta >= 5 { return 65.0 + (delta - 5.0) * 2.0 }
                if delta >= -5 { return 45.0 + (delta + 5.0) * 2.0 }
                return max(10.0, 30.0 + delta)
            }
            return z4Score
        }()

        let paceScore: Double = {
            guard let pDelta = paceDelta else { return hrScore }
            if pDelta <= -30 { return 90.0 }
            if pDelta <= -10 { return 70.0 }
            if pDelta <= 10 { return 50.0 }
            return max(15.0, 30.0 - (pDelta - 10.0))
        }()

        // Weighted combination: 45% Zone 4, 35% HR Strain, 20% Pace Effort
        let totalIntensity = (0.45 * z4Score) + (0.35 * hrScore) + (0.20 * paceScore)

        if totalIntensity < 22.0 && zone4 <= 0.03 && durationMinutes < 40.0 {
            return "Recovery Run"
        } else if totalIntensity < 48.0 && zone4 <= 0.20 {
            return "Easy Run"
        } else if totalIntensity >= 72.0 && zone4 >= 0.50 && durationMinutes >= 20.0 && (paceDelta.map { $0 <= -15.0 } ?? true) {
            return "Tempo Run"
        } else {
            return "Steady Effort"
        }
    }

    // MARK: - Tags

    func generateFramboiseTags(cv: Double, slope: Double, deadStopsCount: Int, buckets: [BucketData] = []) -> [String] {
        var tags = [String]()

        if deadStopsCount > 5 {
            tags.append("urbanTraffic")
        }
        if slope > 0.225 {
            tags.append("fatigueDrift")
        }
        if slope < -0.375 {
            tags.append("progressiveFinish")
        }
        if cv > 0.18 && deadStopsCount <= 2 {
            tags.append("highVolatility")
        }

        // Biomechanical telemetry readiness markers
        if detectCadenceFade(buckets: buckets) {
            tags.append("cadenceFade")
        }
        if detectCardiacDrift(buckets: buckets, paceSlope: slope) {
            tags.append("cardiacDrift")
        }

        return tags
    }

    /// Detects progressive cadence turnover decay (>= 4 SPM drop in the final third of a run).
    func detectCadenceFade(buckets: [BucketData]) -> Bool {
        let running = buckets.filter { $0.meanCadence >= 135.0 && $0.meanPaceSecPerKm > 0 }
        guard running.count >= 8 else { return false }
        let splitIndex = (running.count * 2) / 3
        let firstTwoThirds = running[0..<splitIndex]
        let finalThird = running[splitIndex...]
        guard !firstTwoThirds.isEmpty && !finalThird.isEmpty else { return false }

        let earlyCadence = firstTwoThirds.map(\.meanCadence).reduce(0, +) / Double(firstTwoThirds.count)
        let lateCadence = finalThird.map(\.meanCadence).reduce(0, +) / Double(finalThird.count)

        return (earlyCadence - lateCadence) >= 4.0
    }

    /// Detects cardiac drift (HR upward decoupling at steady pace or high positive pace/HR drift).
    func detectCardiacDrift(buckets: [BucketData], paceSlope: Double) -> Bool {
        if paceSlope > 0.225 {
            return true
        }
        let running = buckets.filter { $0.meanHR > 60.0 && $0.meanPaceSecPerKm > 0 }
        guard running.count >= 8 else { return false }
        let splitIndex = running.count / 3
        let firstThird = running[0..<splitIndex]
        let lastThird = running[(running.count - splitIndex)...]
        guard !firstThird.isEmpty && !lastThird.isEmpty else { return false }

        let earlyHR = firstThird.map(\.meanHR).reduce(0, +) / Double(firstThird.count)
        let lateHR = lastThird.map(\.meanHR).reduce(0, +) / Double(lastThird.count)
        let earlyPace = firstThird.map(\.meanPaceSecPerKm).reduce(0, +) / Double(firstThird.count)
        let latePace = lastThird.map(\.meanPaceSecPerKm).reduce(0, +) / Double(lastThird.count)

        let paceRatio = earlyPace > 0 ? (latePace / earlyPace) : 1.0
        // HR increased by >= 6 BPM while pace stayed roughly steady (within 8%)
        return (lateHR - earlyHR) >= 6.0 && paceRatio >= 0.92 && paceRatio <= 1.08
    }

    /// Computes authentic distance splits (e.g. 1-kilometer splits) from continuous time-series buckets.
    func calculateSplits(from buckets: [BucketData], splitDistanceMeters: Double = 1000.0) -> [RunSplit] {
        guard !buckets.isEmpty, splitDistanceMeters > 0 else { return [] }

        var splits: [RunSplit] = []
        var currentSplitIndex = 1

        var accumulatedDistance = 0.0, accumulatedDuration = 0.0
        var accumulatedWeightedHR = 0.0, accumulatedWeightedCadence = 0.0, accumulatedElevation = 0.0

        func flushSplit() {
            guard accumulatedDistance > 0 else { return }
            let pace = accumulatedDuration / (accumulatedDistance / 1000.0)
            let hr = accumulatedDuration > 0 ? (accumulatedWeightedHR / accumulatedDuration) : 0.0
            let cad = accumulatedDuration > 0 ? (accumulatedWeightedCadence / accumulatedDuration) : 0.0
            splits.append(RunSplit(
                index: currentSplitIndex,
                distanceMeters: accumulatedDistance,
                durationSeconds: accumulatedDuration,
                paceSecondsPerKm: pace,
                avgHeartRate: hr,
                avgCadence: cad,
                elevationGainMeters: accumulatedElevation
            ))
            currentSplitIndex += 1
            accumulatedDistance = 0; accumulatedDuration = 0
            accumulatedWeightedHR = 0; accumulatedWeightedCadence = 0; accumulatedElevation = 0
        }

        for bucket in buckets {
            var bucketDistance = bucket.distanceMeters
            var bucketDuration = bucket.durationSeconds
            guard bucketDistance > 0 || bucketDuration > 0 else { continue }
            let bucketHR = bucket.meanHR, bucketCadence = bucket.meanCadence
            var bucketElevation = bucket.elevationGainMeters

            while bucketDistance > 0 {
                let distanceNeeded = splitDistanceMeters - accumulatedDistance
                if bucketDistance <= distanceNeeded {
                    accumulatedDistance += bucketDistance
                    accumulatedDuration += bucketDuration
                    accumulatedWeightedHR += bucketHR * bucketDuration
                    accumulatedWeightedCadence += bucketCadence * bucketDuration
                    accumulatedElevation += bucketElevation
                    if accumulatedDistance >= splitDistanceMeters { flushSplit() }
                    break
                } else {
                    let fraction = distanceNeeded / bucketDistance
                    let splitDurationPart = bucketDuration * fraction
                    let splitElevationPart = bucketElevation * fraction

                    accumulatedDistance += distanceNeeded
                    accumulatedDuration += splitDurationPart
                    accumulatedWeightedHR += bucketHR * splitDurationPart
                    accumulatedWeightedCadence += bucketCadence * splitDurationPart
                    accumulatedElevation += splitElevationPart
                    flushSplit()

                    bucketDistance -= distanceNeeded
                    bucketDuration -= splitDurationPart
                    bucketElevation -= splitElevationPart
                }
            }
        }

        if accumulatedDistance >= 100.0 { flushSplit() }
        return splits
    }
}
