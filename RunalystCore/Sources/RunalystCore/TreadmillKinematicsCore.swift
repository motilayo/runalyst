import Foundation

// MARK: - Treadmill Kinematics Domain Result

/// Result of processing indoor treadmill telemetry, including belt pace smoothing,
/// calibration mutation reconciliation, and incline review detection.
public struct TreadmillKinematicsResult: Sendable, Codable, Equatable {
    public let smoothedBuckets: [TelemetryBucket]
    public let needsInclineReview: Bool
    public let isCalibrationMutated: Bool
    public let distanceDeltaMeters: Double
    public let effectiveCV: Double
    public let effectiveSlope: Double

    public init(
        smoothedBuckets: [TelemetryBucket],
        needsInclineReview: Bool,
        isCalibrationMutated: Bool,
        distanceDeltaMeters: Double,
        effectiveCV: Double,
        effectiveSlope: Double
    ) {
        self.smoothedBuckets = smoothedBuckets
        self.needsInclineReview = needsInclineReview
        self.isCalibrationMutated = isCalibrationMutated
        self.distanceDeltaMeters = distanceDeltaMeters
        self.effectiveCV = effectiveCV
        self.effectiveSlope = effectiveSlope
    }
}

// MARK: - Treadmill Kinematics Core

/// Pure sports science engine for indoor treadmill kinematics, wrist accelerometer
/// filtering, post-workout calibration reconciliation, and incline decoupling inference.
public enum TreadmillKinematicsCore {

    /// Applies rolling median pace filtering with a strict 25% outlier clamping window
    /// to handle sudden treadmill speed jumps, sensor lag, or wrist artifact spikes.
    public static func applyWristPaceSmoothing(
        buckets: [TelemetryBucket],
        outlierClampPercentage: Double = 0.25
    ) -> [TelemetryBucket] {
        guard buckets.count >= 3 else { return buckets }

        let validPaces = buckets.map(\.paceSecondsPerKm).filter { $0 > 0 && $0.isFinite }.sorted()
        guard !validPaces.isEmpty else { return buckets }

        let overallMedianPace = validPaces[validPaces.count / 2]
        let minAllowedPace = overallMedianPace * (1.0 - outlierClampPercentage)
        let maxAllowedPace = overallMedianPace * (1.0 + outlierClampPercentage)

        var smoothedBuckets: [TelemetryBucket] = []
        smoothedBuckets.reserveCapacity(buckets.count)

        for i in 0..<buckets.count {
            let start = max(0, i - 1)
            let end = min(buckets.count - 1, i + 1)
            let window = Array(buckets[start...end])
            let windowPaces = window.map(\.paceSecondsPerKm).sorted()
            var medianWindowPace = windowPaces[windowPaces.count / 2]

            // Clamp outliers exceeding the configured percentage from overall median
            if medianWindowPace < minAllowedPace {
                medianWindowPace = minAllowedPace
            } else if medianWindowPace > maxAllowedPace {
                medianWindowPace = maxAllowedPace
            }

            let original = buckets[i]
            smoothedBuckets.append(TelemetryBucket(
                timestamp: original.timestamp,
                durationSeconds: original.durationSeconds,
                distanceMeters: original.distanceMeters,
                paceSecondsPerKm: medianWindowPace,
                cadenceSPM: original.cadenceSPM,
                heartRateBPM: original.heartRateBPM,
                groundContactTimeMs: original.groundContactTimeMs,
                verticalOscillationCm: original.verticalOscillationCm,
                strideLengthMeters: original.strideLengthMeters,
                elevationGainMeters: original.elevationGainMeters
            ))
        }

        return smoothedBuckets
    }

    /// Detects post-workout distance or duration calibration mutations.
    /// Returns true when user calibration differs from reported telemetry by more than the threshold.
    public static func detectCalibrationMutation(
        reportedDistanceMeters: Double,
        authenticDistanceMeters: Double,
        reportedDurationSeconds: Double,
        authenticDurationSeconds: Double,
        distanceThresholdMeters: Double = 5.0,
        durationThresholdSeconds: Double = 2.0
    ) -> (isMutated: Bool, distanceDeltaMeters: Double, durationDeltaSeconds: Double) {
        let distDelta = abs(authenticDistanceMeters - reportedDistanceMeters)
        let durDelta = abs(authenticDurationSeconds - reportedDurationSeconds)
        let isMutated = distDelta > distanceThresholdMeters || durDelta > durationThresholdSeconds
        return (isMutated, distDelta, durDelta)
    }

    /// Proportionally reconciles bucket distances and paces to match post-workout manual treadmill calibration.
    public static func reconcileBucketDistances(
        buckets: [TelemetryBucket],
        authenticTotalDistanceMeters: Double
    ) -> [TelemetryBucket] {
        guard !buckets.isEmpty, authenticTotalDistanceMeters > 0 else { return buckets }

        let currentSum = buckets.map(\.distanceMeters).reduce(0.0, +)
        guard currentSum > 0 else { return buckets }

        let scale = authenticTotalDistanceMeters / currentSum

        return buckets.map { b in
            let newDist = b.distanceMeters * scale
            let newPace = (newDist > 0 && b.durationSeconds > 0)
                ? (b.durationSeconds / newDist) * 1000.0
                : b.paceSecondsPerKm

            return TelemetryBucket(
                timestamp: b.timestamp,
                durationSeconds: b.durationSeconds,
                distanceMeters: newDist,
                paceSecondsPerKm: newPace,
                cadenceSPM: b.cadenceSPM,
                heartRateBPM: b.heartRateBPM,
                groundContactTimeMs: b.groundContactTimeMs,
                verticalOscillationCm: b.verticalOscillationCm,
                strideLengthMeters: b.strideLengthMeters,
                elevationGainMeters: b.elevationGainMeters
            )
        }
    }

    /// Pure deterministic rule evaluating whether heart rate strain decoupled from flat pace on indoor runs.
    /// Flags for user review to confirm whether manual treadmill incline was applied.
    public static func shouldFlagForInclineReview(
        isIndoor: Bool,
        isGymKit: Bool = false,
        hrCV: Double,
        paceCV: Double,
        cadenceSlope: Double,
        cadenceDelta: Double = 0.0
    ) -> Bool {
        guard isIndoor && !isGymKit else { return false }
        return hrCV > 0.075 && paceCV < 0.045 && (cadenceSlope < -0.005 || cadenceDelta < -2.0)
    }

    /// Calculates effective variance and slope for indoor treadmill running.
    /// When running indoors without GymKit, the motorized belt artificially locks speed and wrist sensors
    /// introduce noise, requiring effective attenuation of pace CV and slope.
    public static func effectiveIndoorPacingMetrics(
        isIndoor: Bool,
        isGymKit: Bool = false,
        rawPaceCV: Double,
        rawPaceSlope: Double
    ) -> (effectiveCV: Double, effectiveSlope: Double) {
        if isIndoor && !isGymKit {
            return (0.035, 0.0)
        }
        return (rawPaceCV, rawPaceSlope)
    }

    /// End-to-end processing of indoor treadmill telemetry.
    public static func processIndoorRun(
        buckets: [TelemetryBucket],
        isIndoor: Bool,
        isGymKit: Bool = false,
        authenticTotalDistanceMeters: Double? = nil,
        authenticDurationSeconds: Double? = nil,
        rawPaceCV: Double,
        rawPaceSlope: Double,
        hrCV: Double,
        cadenceSlope: Double,
        cadenceDelta: Double = 0.0
    ) -> TreadmillKinematicsResult {
        var processedBuckets = buckets

        var isCalibrationMutated = false
        var distanceDelta = 0.0

        if let authDist = authenticTotalDistanceMeters {
            let currentDist = buckets.map(\.distanceMeters).reduce(0.0, +)
            let currentDur = buckets.map(\.durationSeconds).reduce(0.0, +)
            let authDur = authenticDurationSeconds ?? currentDur

            let (mutated, dDelta, _) = detectCalibrationMutation(
                reportedDistanceMeters: currentDist,
                authenticDistanceMeters: authDist,
                reportedDurationSeconds: currentDur,
                authenticDurationSeconds: authDur
            )

            isCalibrationMutated = mutated
            distanceDelta = dDelta

            if mutated {
                processedBuckets = reconcileBucketDistances(
                    buckets: processedBuckets,
                    authenticTotalDistanceMeters: authDist
                )
            }
        }

        if isIndoor && !isGymKit {
            processedBuckets = applyWristPaceSmoothing(buckets: processedBuckets)
        }

        let needsReview = shouldFlagForInclineReview(
            isIndoor: isIndoor,
            isGymKit: isGymKit,
            hrCV: hrCV,
            paceCV: rawPaceCV,
            cadenceSlope: cadenceSlope,
            cadenceDelta: cadenceDelta
        )

        let (effCV, effSlope) = effectiveIndoorPacingMetrics(
            isIndoor: isIndoor,
            isGymKit: isGymKit,
            rawPaceCV: rawPaceCV,
            rawPaceSlope: rawPaceSlope
        )

        return TreadmillKinematicsResult(
            smoothedBuckets: processedBuckets,
            needsInclineReview: needsReview,
            isCalibrationMutated: isCalibrationMutated,
            distanceDeltaMeters: distanceDelta,
            effectiveCV: effCV,
            effectiveSlope: effSlope
        )
    }
}
