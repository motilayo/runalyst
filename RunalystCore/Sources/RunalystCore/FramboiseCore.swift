import Foundation

// MARK: - Framboise Core (Pure Biomechanical Ingot)

/// Deterministic mathematical engine extracting true working metrics and scrubbing dead stops.
/// Operates exclusively on pure telemetry slices without platform dependencies or side effects.
public enum FramboiseCore {

    // MARK: - Dead Stop & Walking Filter

    /// Filters out stationary time, traffic stops, and walking breaks.
    /// Strictly filters to KEEP samples where speed is greater than the walking threshold.
    /// When step cadence is present, enforces a biomechanical running floor (>= 125 SPM)
    /// so arm-swing during walking breaks cannot bleed false running speed.
    public static func filterRunningSamples(buckets: [TelemetryBucket]) -> [TelemetryBucket] {
        buckets.filter { bucket in
            let speedMetersPerSecond = bucket.speedMetersPerSecond
            if bucket.cadenceSPM > 0 {
                if bucket.cadenceSPM >= 130.0 {
                    return true
                } else if bucket.cadenceSPM >= 125.0 {
                    return speedMetersPerSecond > 1.65
                } else {
                    return false
                }
            } else {
                return speedMetersPerSecond > 1.5
            }
        }
    }

    /// Alias for filterRunningSamples to maintain ergonomic terminology.
    public static func trimDeadStops(buckets: [TelemetryBucket]) -> [TelemetryBucket] {
        filterRunningSamples(buckets: buckets)
    }

    // MARK: - Working Averages & Aggregate Pace

    /// Calculates true working averages by strictly summing the filtered running samples.
    /// - Strictly sums the duration of only the kept/filtered samples.
    /// - Enforces hard safety constraint: workingDuration <= rawWorkoutDuration.
    /// - Calculates pace using pure aggregate ratios (workingDuration / workingDistanceKm) to eliminate harmonic distortion.
    public static func calculateWorkingAverages(
        trimmed: [TelemetryBucket],
        rawWorkoutDuration: TimeInterval? = nil,
        rawWorkoutDistance: Double? = nil,
        originalBucketCount: Int? = nil,
        rawAvgStrideLength: Double? = nil,
        rawAvgGroundContactTime: Double? = nil
    ) -> (
        workingPace: Double,
        workingCadence: Double,
        workingHR: Double,
        workingOscillation: Double?,
        workingDistance: Double,
        workingDuration: TimeInterval,
        workingStrideLength: Double?,
        workingGroundContactTime: Double?
    ) {
        guard !trimmed.isEmpty else {
            return (0, 0, 0, nil, 0, 0, nil, nil)
        }

        var totalDistanceMeters: Double = 0
        var totalCadence: Double = 0
        var totalHR: Double = 0
        var totalOscillation: Double = 0
        var totalStrideLength: Double = 0
        var totalGCT: Double = 0
        var oscillationBucketCount: Int = 0
        var validHRBucketCount: Int = 0
        var strideBucketCount: Int = 0
        var gctBucketCount: Int = 0

        for bucket in trimmed {
            totalDistanceMeters += bucket.distanceMeters
            totalCadence += bucket.cadenceSPM

            if bucket.heartRateBPM >= 40 {
                totalHR += bucket.heartRateBPM
                validHRBucketCount += 1
            }

            if let osc = bucket.verticalOscillationCm, osc > 0 {
                totalOscillation += osc
                oscillationBucketCount += 1
            }

            if let stride = bucket.strideLengthMeters, stride > 0 {
                totalStrideLength += stride
                strideBucketCount += 1
            }

            if let gct = bucket.groundContactTimeMs, gct > 0 {
                totalGCT += gct
                gctBucketCount += 1
            }
        }

        // If no buckets were trimmed (no dead stops), Working stats MUST perfectly equal Raw stats
        let isFullyActive = (originalBucketCount != nil) && (trimmed.count == originalBucketCount)

        // Strictly sum the duration of only the kept/filtered samples
        let trimmedDuration = trimmed.reduce(0.0) { $0 + $1.durationSeconds }
        var workingDuration = isFullyActive ? (rawWorkoutDuration ?? trimmedDuration) : trimmedDuration

        // Hard safety constraint: workingDuration must be <= rawWorkout.duration
        if !isFullyActive, let rawDuration = rawWorkoutDuration, rawDuration > 0 {
            workingDuration = min(workingDuration, rawDuration)
        }

        // Pure aggregate ratio: Divide newly calculated workingDuration (in seconds) by workingDistance (in kilometers)
        let workingDistanceMetersFinal = isFullyActive ? (rawWorkoutDistance ?? totalDistanceMeters) : totalDistanceMeters
        let workingDistanceKm = workingDistanceMetersFinal / 1000.0
        let workingPace = workingDistanceKm > 0 ? (workingDuration / workingDistanceKm) : 0.0

        let workingCadence = totalCadence / Double(trimmed.count)
        let workingHR = validHRBucketCount > 0 ? (totalHR / Double(validHRBucketCount)) : 0.0
        let workingOscillation: Double? = {
            if oscillationBucketCount > 0 {
                return totalOscillation / Double(oscillationBucketCount)
            }
            return nil
        }()

        let workingStrideLength: Double? = {
            if isFullyActive, let rawStride = rawAvgStrideLength, rawStride > 0 {
                return rawStride
            }
            if strideBucketCount > 0 {
                return totalStrideLength / Double(strideBucketCount)
            }
            return rawAvgStrideLength
        }()

        let workingGroundContactTime: Double? = {
            if isFullyActive, let rawGCT = rawAvgGroundContactTime, rawGCT > 0 {
                return rawGCT
            }
            if gctBucketCount > 0 {
                return totalGCT / Double(gctBucketCount)
            }
            return rawAvgGroundContactTime
        }()

        return (
            workingPace,
            workingCadence,
            workingHR,
            workingOscillation,
            workingDistanceMetersFinal,
            workingDuration,
            workingStrideLength,
            workingGroundContactTime
        )
    }

    // MARK: - Mathematical Features

    /// Calculates the Coefficient of Variation (CV = sigma / mu) for pace across buckets.
    public static func calculatePaceCV(bucketPaces: [Double]) -> Double {
        calculateCV(values: bucketPaces, floor: 0.0)
    }

    /// Calculates the Coefficient of Variation (CV = sigma / mu) for cadence across buckets.
    public static func calculateCadenceCV(bucketCadences: [Double]) -> Double {
        calculateCV(values: bucketCadences, floor: 0.0)
    }

    /// Calculates the Coefficient of Variation (CV = sigma / mu) for heart rate across buckets.
    public static func calculateHRCV(bucketHRs: [Double]) -> Double {
        calculateCV(values: bucketHRs, floor: 40.0)
    }

    private static func calculateCV(values: [Double], floor: Double) -> Double {
        guard values.count > 1 else { return 0.0 }
        let valid = values.filter { $0 > floor && $0.isFinite }
        guard valid.count > 1 else { return 0.0 }

        let mu = valid.reduce(0.0, +) / Double(valid.count)
        guard mu > 0 else { return 0.0 }

        let sumSquaredDiff = valid.reduce(0.0) { $0 + pow($1 - mu, 2) }
        let variance = sumSquaredDiff / Double(valid.count - 1)
        let sigma = sqrt(variance)

        return sigma / mu
    }

    /// Calculates the linear regression slope of pace over time (least-squares).
    /// Negative slope = speeding up (progression). Positive slope = slowing down (fatigue).
    public static func calculatePaceSlope(bucketPaces: [Double]) -> Double {
        calculateLinearSlope(values: bucketPaces, floor: 0.0)
    }

    /// Calculates the linear regression slope of cadence over time (least-squares).
    public static func calculateCadenceSlope(bucketCadences: [Double]) -> Double {
        calculateLinearSlope(values: bucketCadences, floor: 0.0)
    }

    private static func calculateLinearSlope(values: [Double], floor: Double) -> Double {
        guard values.count > 1 else { return 0.0 }
        let valid = values.filter { $0 > floor && $0.isFinite }
        let n = Double(valid.count)
        guard n > 1 else { return 0.0 }

        var sumX: Double = 0
        var sumY: Double = 0
        var sumXY: Double = 0
        var sumX2: Double = 0

        for (i, y) in valid.enumerated() {
            let x = Double(i)
            sumX += x
            sumY += y
            sumXY += x * y
            sumX2 += x * x
        }

        let denominator = (n * sumX2) - (sumX * sumX)
        guard denominator != 0 else { return 0.0 }

        return ((n * sumXY) - (sumX * sumY)) / denominator
    }

    /// Calculates the fraction of time spent in Zone 4 (or higher).
    public static func calculatePercentZone4(bucketHRs: [Double], maxHR: Double) -> Double {
        guard maxHR > 0, !bucketHRs.isEmpty else { return 0.0 }
        let zone4Threshold = maxHR * 0.85
        let zone4Count = bucketHRs.filter { $0 >= zone4Threshold }.count
        return Double(zone4Count) / Double(bucketHRs.count)
    }

    /// Detects progressive cadence turnover decay (>= 4 SPM drop in the final third of a run).
    public static func detectCadenceFade(buckets: [TelemetryBucket]) -> Bool {
        let running = buckets.filter { $0.cadenceSPM >= 135.0 && $0.paceSecondsPerKm > 0 }
        guard running.count >= 8 else { return false }
        let splitIndex = (running.count * 2) / 3
        let firstTwoThirds = running[0..<splitIndex]
        let finalThird = running[splitIndex...]
        guard !firstTwoThirds.isEmpty && !finalThird.isEmpty else { return false }

        let earlyCadence = firstTwoThirds.map(\.cadenceSPM).reduce(0.0, +) / Double(firstTwoThirds.count)
        let lateCadence = finalThird.map(\.cadenceSPM).reduce(0.0, +) / Double(finalThird.count)

        return (earlyCadence - lateCadence) >= 4.0
    }

    /// Detects cardiac drift (HR upward decoupling at steady pace or high positive pace/HR drift).
    public static func detectCardiacDrift(buckets: [TelemetryBucket], paceSlope: Double) -> Bool {
        if paceSlope > 0.225 {
            return true
        }
        let running = buckets.filter { $0.heartRateBPM > 60.0 && $0.paceSecondsPerKm > 0 }
        guard running.count >= 8 else { return false }
        let splitIndex = running.count / 3
        let firstThird = running[0..<splitIndex]
        let lastThird = running[(running.count - splitIndex)...]
        guard !firstThird.isEmpty && !lastThird.isEmpty else { return false }

        let earlyHR = firstThird.map(\.heartRateBPM).reduce(0.0, +) / Double(firstThird.count)
        let lateHR = lastThird.map(\.heartRateBPM).reduce(0.0, +) / Double(lastThird.count)
        let earlyPace = firstThird.map(\.paceSecondsPerKm).reduce(0.0, +) / Double(firstThird.count)
        let latePace = lastThird.map(\.paceSecondsPerKm).reduce(0.0, +) / Double(lastThird.count)

        let paceRatio = earlyPace > 0 ? (latePace / earlyPace) : 1.0
        // HR increased by >= 6 BPM while pace stayed roughly steady (within 8%)
        return (lateHR - earlyHR) >= 6.0 && paceRatio >= 0.92 && paceRatio <= 1.08
    }

    /// Generates diagnostic telemetry tags based on biomechanical and physiological markers.
    public static func generateFramboiseTags(
        cv: Double,
        slope: Double,
        deadStopsCount: Int,
        buckets: [TelemetryBucket] = [],
        isIndoor: Bool = false
    ) -> [String] {
        var tags: [String] = []

        if deadStopsCount > 5 && !isIndoor {
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

    // MARK: - Distance Splits Engine

    /// Computes authentic distance splits (e.g. 1-kilometer splits) from continuous time-series buckets.
    public static func calculateSplits(
        from buckets: [TelemetryBucket],
        splitDistanceMeters: Double = 1000.0
    ) -> [TelemetrySplit] {
        guard !buckets.isEmpty, splitDistanceMeters > 0 else { return [] }

        var splits: [TelemetrySplit] = []
        var currentSplitIndex = 1

        var accumulatedDistance = 0.0, accumulatedDuration = 0.0
        var accumulatedWeightedHR = 0.0, accumulatedHRDuration = 0.0
        var accumulatedWeightedCadence = 0.0, accumulatedCadenceDuration = 0.0
        var accumulatedElevation = 0.0

        func flushSplit() {
            guard accumulatedDistance > 0 else { return }
            let pace = accumulatedDuration / (accumulatedDistance / 1000.0)
            let hr = accumulatedHRDuration > 0 ? (accumulatedWeightedHR / accumulatedHRDuration) : 0.0
            let cad = accumulatedCadenceDuration > 0 ? (accumulatedWeightedCadence / accumulatedCadenceDuration) : 0.0
            splits.append(TelemetrySplit(
                index: currentSplitIndex,
                distanceMeters: accumulatedDistance,
                durationSeconds: accumulatedDuration,
                paceSecondsPerKm: pace,
                avgHeartRateBPM: hr,
                avgCadenceSPM: cad,
                elevationGainMeters: accumulatedElevation
            ))
            currentSplitIndex += 1
            accumulatedDistance = 0
            accumulatedDuration = 0
            accumulatedWeightedHR = 0
            accumulatedHRDuration = 0
            accumulatedWeightedCadence = 0
            accumulatedCadenceDuration = 0
            accumulatedElevation = 0
        }

        for bucket in buckets {
            var bucketDistance = bucket.distanceMeters
            var bucketDuration = bucket.durationSeconds
            guard bucketDistance > 0 || bucketDuration > 0 else { continue }
            let bucketHR = bucket.heartRateBPM
            let bucketCadence = bucket.cadenceSPM
            var bucketElevation = bucket.elevationGainMeters ?? 0.0

            while bucketDistance > 0 {
                let distanceNeeded = splitDistanceMeters - accumulatedDistance
                if bucketDistance <= distanceNeeded {
                    accumulatedDistance += bucketDistance
                    accumulatedDuration += bucketDuration
                    if bucketHR >= 40.0 {
                        accumulatedWeightedHR += bucketHR * bucketDuration
                        accumulatedHRDuration += bucketDuration
                    }
                    if bucketCadence > 0.0 {
                        accumulatedWeightedCadence += bucketCadence * bucketDuration
                        accumulatedCadenceDuration += bucketDuration
                    }
                    accumulatedElevation += bucketElevation
                    if accumulatedDistance >= splitDistanceMeters { flushSplit() }
                    break
                } else {
                    let fraction = distanceNeeded / bucketDistance
                    let splitDurationPart = bucketDuration * fraction
                    let splitElevationPart = bucketElevation * fraction

                    accumulatedDistance += distanceNeeded
                    accumulatedDuration += splitDurationPart
                    if bucketHR >= 40.0 {
                        accumulatedWeightedHR += bucketHR * splitDurationPart
                        accumulatedHRDuration += splitDurationPart
                    }
                    if bucketCadence > 0.0 {
                        accumulatedWeightedCadence += bucketCadence * splitDurationPart
                        accumulatedCadenceDuration += splitDurationPart
                    }
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

    // MARK: - Ingot Primary Orchestrator

    /// Computes complete WorkingStats from raw telemetry buckets.
    public static func computeWorkingStats(
        buckets: [TelemetryBucket],
        rawWorkoutDuration: TimeInterval? = nil,
        rawWorkoutDistance: Double? = nil,
        rawAvgPace: Double? = nil,
        rawAvgCadence: Double? = nil,
        rawAvgHR: Double? = nil,
        rawAvgOscillation: Double? = nil,
        rawAvgStrideLength: Double? = nil,
        isIndoor: Bool = false,
        needsInclineReview: Bool = false,
        maxHR: Double = 190.0,
        detectedClassification: String = "Steady Effort"
    ) -> WorkingStats {
        let trimmed = trimDeadStops(buckets: buckets)
        let deadStopsCount = max(0, buckets.count - trimmed.count)

        let rawDuration = rawWorkoutDuration ?? buckets.reduce(0.0) { $0 + $1.durationSeconds }
        let rawDistance = rawWorkoutDistance ?? buckets.reduce(0.0) { $0 + $1.distanceMeters }
        let rawKm = rawDistance / 1000.0
        let computedRawPace = rawKm > 0 ? (rawDuration / rawKm) : 0.0

        let validRawHRBuckets = buckets.filter { $0.heartRateBPM >= 40.0 }
        let computedRawHR = validRawHRBuckets.isEmpty ? 0.0 : (validRawHRBuckets.map(\.heartRateBPM).reduce(0.0, +) / Double(validRawHRBuckets.count))
        let computedRawCadence = buckets.isEmpty ? 0.0 : (buckets.map(\.cadenceSPM).reduce(0.0, +) / Double(buckets.count))

        let rawOscBuckets = buckets.compactMap(\.verticalOscillationCm).filter { $0 > 0 }
        let computedRawOsc = rawOscBuckets.isEmpty ? nil : (rawOscBuckets.reduce(0.0, +) / Double(rawOscBuckets.count))

        let rawStrideBuckets = buckets.compactMap(\.strideLengthMeters).filter { $0 > 0 }
        let computedRawStride = rawStrideBuckets.isEmpty ? nil : (rawStrideBuckets.reduce(0.0, +) / Double(rawStrideBuckets.count))

        let averages = calculateWorkingAverages(
            trimmed: trimmed,
            rawWorkoutDuration: rawDuration,
            rawWorkoutDistance: rawDistance,
            originalBucketCount: buckets.count,
            rawAvgStrideLength: rawAvgStrideLength ?? computedRawStride
        )

        let trimmedPaces = trimmed.map(\.paceSecondsPerKm).filter { $0 > 0 }
        let trimmedCadences = trimmed.map(\.cadenceSPM).filter { $0 > 0 }
        let trimmedHRs = trimmed.map(\.heartRateBPM).filter { $0 >= 40.0 }

        let paceCV = calculatePaceCV(bucketPaces: trimmedPaces)
        let paceSlope = calculatePaceSlope(bucketPaces: trimmedPaces)
        let hrCV = trimmedHRs.count > 1 ? calculateHRCV(bucketHRs: trimmedHRs) : nil
        let cadenceSlope = trimmedCadences.count > 1 ? calculateCadenceSlope(bucketCadences: trimmedCadences) : nil
        let percentZone4 = calculatePercentZone4(bucketHRs: trimmedHRs, maxHR: maxHR)

        let tags = generateFramboiseTags(
            cv: paceCV,
            slope: paceSlope,
            deadStopsCount: deadStopsCount,
            buckets: trimmed,
            isIndoor: isIndoor
        )

        return WorkingStats(
            workingDistanceMeters: averages.workingDistance,
            workingDurationSeconds: averages.workingDuration,
            workingAvgPaceSecondsPerKm: averages.workingPace,
            workingAvgCadenceSPM: averages.workingCadence,
            workingAvgHeartRateBPM: averages.workingHR,
            workingAvgVerticalOscillationCm: averages.workingOscillation ?? rawAvgOscillation ?? computedRawOsc,
            workingAvgStrideLengthMeters: averages.workingStrideLength,
            workingAvgGroundContactTimeMs: averages.workingGroundContactTime,
            rawTotalDistanceMeters: rawDistance,
            rawTotalDurationSeconds: rawDuration,
            rawAvgPaceSecondsPerKm: rawAvgPace ?? computedRawPace,
            rawAvgCadenceSPM: rawAvgCadence ?? computedRawCadence,
            rawAvgHeartRateBPM: rawAvgHR ?? computedRawHR,
            rawAvgVerticalOscillationCm: rawAvgOscillation ?? computedRawOsc,
            rawAvgStrideLengthMeters: rawAvgStrideLength ?? computedRawStride,
            paceCV: paceCV,
            paceSlope: paceSlope,
            hrCV: hrCV,
            cadenceSlope: cadenceSlope,
            percentZone4: percentZone4,
            deadStopsCount: deadStopsCount,
            isIndoor: isIndoor,
            needsInclineReview: needsInclineReview,
            detectedClassification: detectedClassification,
            framboiseTags: tags
        )
    }
}
