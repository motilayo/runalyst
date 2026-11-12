import Foundation

// MARK: - Raw Ingestion Tick

/// A single 1 Hz snapshot of raw device and motion telemetry for adaptive pacing.
///
/// Designed to execute strictly sans-I/O with pure `Foundation` types.
public struct TelemetryTick: Sendable, Equatable {
    /// Time in seconds elapsed since session start (monotonically non-decreasing).
    public let elapsedSeconds: TimeInterval
    /// Instantaneous heart rate in beats per minute.
    public let heartRateBPM: Double?
    /// Instantaneous running speed in meters per second.
    public let speedMetersPerSecond: Double?
    /// Running power in Watts.
    public let powerWatts: Double?
    /// Cadence in steps per minute reported by footpod or watch sensor.
    public let cadenceSPM: Double?
    /// Cadence in steps per minute derived from the watch IMU / pedometer.
    public let imuCadenceSPM: Double?
    /// Ground contact time in milliseconds.
    public let groundContactTimeMs: Double?
    /// Torso vertical oscillation in centimeters.
    public let verticalOscillationCm: Double?
    /// Stride length in meters.
    public let strideLengthMeters: Double?
    /// Incline fraction (e.g. 0.04 for +4% grade), or `nil` if unavailable.
    public let gradeFraction: Double?
    /// Cumulative distance in meters from session start, if available.
    public let totalDistanceMeters: Double?

    public init(
        elapsedSeconds: TimeInterval,
        heartRateBPM: Double? = nil,
        speedMetersPerSecond: Double? = nil,
        powerWatts: Double? = nil,
        cadenceSPM: Double? = nil,
        imuCadenceSPM: Double? = nil,
        groundContactTimeMs: Double? = nil,
        verticalOscillationCm: Double? = nil,
        strideLengthMeters: Double? = nil,
        gradeFraction: Double? = nil,
        totalDistanceMeters: Double? = nil
    ) {
        self.elapsedSeconds = elapsedSeconds
        self.heartRateBPM = heartRateBPM
        self.speedMetersPerSecond = speedMetersPerSecond
        self.powerWatts = powerWatts
        self.cadenceSPM = cadenceSPM
        self.imuCadenceSPM = imuCadenceSPM
        self.groundContactTimeMs = groundContactTimeMs
        self.verticalOscillationCm = verticalOscillationCm
        self.strideLengthMeters = strideLengthMeters
        self.gradeFraction = gradeFraction
        self.totalDistanceMeters = totalDistanceMeters
    }

    /// Effective cadence, preferring the primary sensor over IMU fallback.
    public var effectiveCadenceSPM: Double? {
        cadenceSPM ?? imuCadenceSPM
    }
}

// MARK: - 1D Kalman Filter

/// Scalar random-walk Kalman filter for real-time sensor conditioning.
///
/// Handles dropout-aware prediction and direct measurement seeding without ramp from 0.
public struct KalmanFilter1D: Sendable {
    /// Process noise variance (Q).
    public let processNoise: Double
    /// Measurement noise variance (R).
    public let measurementNoise: Double
    /// Physiologically plausible measurement range.
    public let validRange: ClosedRange<Double>

    private var estimate: Double?
    private var errorCovariance: Double

    public init(
        processNoise: Double,
        measurementNoise: Double,
        validRange: ClosedRange<Double>
    ) {
        self.processNoise = processNoise
        self.measurementNoise = measurementNoise
        self.validRange = validRange
        self.estimate = nil
        self.errorCovariance = measurementNoise
    }

    /// Default parameters for heart rate: Q=0.1, R=4.0, range 30...230 BPM.
    public static let standardHeartRate = KalmanFilter1D(
        processNoise: 0.1,
        measurementNoise: 4.0,
        validRange: 30.0...230.0
    )

    /// Default parameters for running speed: Q=0.02, R=0.25, range 0...12 m/s.
    public static let standardSpeed = KalmanFilter1D(
        processNoise: 0.02,
        measurementNoise: 0.25,
        validRange: 0.0...12.0
    )

    /// Current filter estimate, if seeded.
    public var currentEstimate: Double? {
        estimate
    }

    /// Steps the filter forward with an optional measurement.
    ///
    /// - Parameter measurement: Raw sensor sample, or `nil` if missing.
    /// - Returns: A tuple containing the updated estimate (or previous estimate during dropout)
    ///   and a flag indicating whether the measurement was physiologically valid.
    public mutating func step(_ measurement: Double?) -> (estimate: Double?, isValid: Bool) {
        guard let measurement, validRange.contains(measurement) else {
            // Missing or physiologically invalid measurement -> predict-only step
            if estimate != nil {
                errorCovariance += processNoise
                return (estimate: estimate, isValid: false)
            } else {
                return (estimate: nil, isValid: false)
            }
        }

        guard let currentEstimate = estimate else {
            // First valid measurement seeds estimate directly (no ramp from zero)
            estimate = measurement
            errorCovariance = measurementNoise
            return (estimate: measurement, isValid: true)
        }

        // 1. Predict
        let predictedP = errorCovariance + processNoise

        // 2. Update
        let kalmanGain = predictedP / (predictedP + measurementNoise)
        let updatedEstimate = currentEstimate + kalmanGain * (measurement - currentEstimate)
        let updatedP = (1.0 - kalmanGain) * predictedP

        self.estimate = updatedEstimate
        self.errorCovariance = updatedP

        return (estimate: updatedEstimate, isValid: true)
    }

    /// Resets the filter to unseeded state.
    public mutating func reset() {
        estimate = nil
        errorCovariance = measurementNoise
    }
}

// MARK: - Conditioned Telemetry Tick

/// Telemetry tick with Kalman-conditioned state and validity flags.
public struct ConditionedTelemetryTick: Sendable, Equatable {
    public let elapsedSeconds: TimeInterval
    public let heartRateBPM: Double?
    public let isHeartRateValid: Bool
    public let speedMetersPerSecond: Double?
    public let isSpeedValid: Bool
    public let cadenceSPM: Double?
    public let powerWatts: Double?
    public let groundContactTimeMs: Double?
    public let verticalOscillationCm: Double?
    public let strideLengthMeters: Double?
    public let gradeFraction: Double?

    public init(
        elapsedSeconds: TimeInterval,
        heartRateBPM: Double?,
        isHeartRateValid: Bool,
        speedMetersPerSecond: Double?,
        isSpeedValid: Bool,
        cadenceSPM: Double?,
        powerWatts: Double?,
        groundContactTimeMs: Double?,
        verticalOscillationCm: Double?,
        strideLengthMeters: Double?,
        gradeFraction: Double?
    ) {
        self.elapsedSeconds = elapsedSeconds
        self.heartRateBPM = heartRateBPM
        self.isHeartRateValid = isHeartRateValid
        self.speedMetersPerSecond = speedMetersPerSecond
        self.isSpeedValid = isSpeedValid
        self.cadenceSPM = cadenceSPM
        self.powerWatts = powerWatts
        self.groundContactTimeMs = groundContactTimeMs
        self.verticalOscillationCm = verticalOscillationCm
        self.strideLengthMeters = strideLengthMeters
        self.gradeFraction = gradeFraction
    }
}

// MARK: - Pacing Metrics & Rolling Window Statistics

/// Domain metric selector for rolling window calculations.
public enum PacingMetric: String, Sendable, CaseIterable {
    case filteredHeartRate
    case filteredSpeed
    case cadence
    case power
    case groundContactTime
    case verticalOscillation
    case grade
    case strideLength
}

/// Rolling statistical summary over a specified temporal window.
public struct RollingWindowStats: Sendable, Equatable {
    public let mean: Double
    public let standardDeviation: Double
    public let coverage: Double
    public let sampleCount: Int

    public init(
        mean: Double,
        standardDeviation: Double,
        coverage: Double,
        sampleCount: Int
    ) {
        self.mean = mean
        self.standardDeviation = standardDeviation
        self.coverage = coverage
        self.sampleCount = sampleCount
    }
}

// MARK: - Fixed-Capacity Ring Buffer

/// A flat, non-allocating circular buffer storing conditioned telemetry ticks.
public struct TelemetryRingBuffer: Sendable {
    public static let defaultCapacity: Int = 900

    public let capacity: Int
    private var storage: [ConditionedTelemetryTick?]
    private var writeIndex: Int = 0
    private var currentCount: Int = 0

    public init(capacity: Int = TelemetryRingBuffer.defaultCapacity) {
        self.capacity = capacity
        self.storage = Array(repeating: nil, count: capacity)
        self.writeIndex = 0
        self.currentCount = 0
    }

    /// Number of ticks currently held in the buffer.
    public var count: Int {
        currentCount
    }

    /// Whether the ring buffer has reached its fixed maximum capacity.
    public var isFull: Bool {
        currentCount == capacity
    }

    /// Appends a new tick with O(1) complexity and zero heap growth after reaching capacity.
    public mutating func append(_ tick: ConditionedTelemetryTick) {
        storage[writeIndex] = tick
        writeIndex = (writeIndex + 1) % capacity
        if currentCount < capacity {
            currentCount += 1
        }
    }

    /// Most recently appended tick.
    public var latestTick: ConditionedTelemetryTick? {
        guard currentCount > 0 else { return nil }
        let idx = (writeIndex - 1 + capacity) % capacity
        return storage[idx]
    }

    /// Returns rolling statistics for the specified metric over the trailing `windowSeconds`.
    ///
    /// Returns `nil` when valid sample coverage over the expected ticks is below `minCoverage`.
    public func stats(
        for metric: PacingMetric,
        windowSeconds: TimeInterval,
        minCoverage: Double = 0.80
    ) -> RollingWindowStats? {
        guard let latest = latestTick else { return nil }
        let expectedTicks = Int(windowSeconds.rounded())
        guard expectedTicks > 0 else { return nil }

        let windowEnd = latest.elapsedSeconds
        var validValues: [Double] = []
        validValues.reserveCapacity(expectedTicks)

        var inspectedTicks = 0
        while inspectedTicks < currentCount {
            let idx = (writeIndex - 1 - inspectedTicks + capacity * 2) % capacity
            guard let tick = storage[idx] else { break }

            let delta = windowEnd - tick.elapsedSeconds
            if delta >= windowSeconds {
                break
            }

            if let value = extractValue(for: metric, from: tick) {
                validValues.append(value)
            }

            inspectedTicks += 1
        }

        let coverage = Double(validValues.count) / Double(expectedTicks)
        guard coverage >= minCoverage, !validValues.isEmpty else {
            return nil
        }

        let countDbl = Double(validValues.count)
        let mean = validValues.reduce(0.0, +) / countDbl
        let sumSquaredDiff = validValues.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) }
        let variance = validValues.count > 1 ? sumSquaredDiff / Double(validValues.count - 1) : 0.0
        let stdDev = sqrt(max(0.0, variance))

        return RollingWindowStats(
            mean: mean,
            standardDeviation: stdDev,
            coverage: coverage,
            sampleCount: validValues.count
        )
    }

    /// 30-second short window statistics for a metric.
    public func shortWindowStats(for metric: PacingMetric) -> RollingWindowStats? {
        stats(for: metric, windowSeconds: 30.0)
    }

    /// 180-second long window statistics for a metric.
    public func longWindowStats(for metric: PacingMetric) -> RollingWindowStats? {
        stats(for: metric, windowSeconds: 180.0)
    }

    /// Computes statistics over a historical elapsed time interval (e.g. 300...600 s calibration window).
    public func stats(
        for metric: PacingMetric,
        in interval: ClosedRange<TimeInterval>,
        minCoverage: Double = 0.80
    ) -> RollingWindowStats? {
        let expectedTicks = max(1, Int((interval.upperBound - interval.lowerBound).rounded()))
        var validValues: [Double] = []
        validValues.reserveCapacity(expectedTicks)

        for i in 0..<currentCount {
            let idx = (writeIndex - currentCount + i + capacity * 2) % capacity
            guard let tick = storage[idx] else { continue }
            guard interval.contains(tick.elapsedSeconds) else { continue }

            if let value = extractValue(for: metric, from: tick) {
                validValues.append(value)
            }
        }

        let coverage = Double(validValues.count) / Double(expectedTicks)
        guard coverage >= minCoverage, !validValues.isEmpty else {
            return nil
        }

        let countDbl = Double(validValues.count)
        let mean = validValues.reduce(0.0, +) / countDbl
        let sumSquaredDiff = validValues.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) }
        let variance = validValues.count > 1 ? sumSquaredDiff / Double(validValues.count - 1) : 0.0
        let stdDev = sqrt(max(0.0, variance))

        return RollingWindowStats(
            mean: mean,
            standardDeviation: stdDev,
            coverage: coverage,
            sampleCount: validValues.count
        )
    }

    // MARK: - Private Helpers

    private func extractValue(for metric: PacingMetric, from tick: ConditionedTelemetryTick) -> Double? {
        switch metric {
        case .filteredHeartRate:
            return tick.isHeartRateValid ? tick.heartRateBPM : nil
        case .filteredSpeed:
            return tick.isSpeedValid ? tick.speedMetersPerSecond : nil
        case .cadence:
            return tick.cadenceSPM
        case .power:
            return tick.powerWatts
        case .groundContactTime:
            return tick.groundContactTimeMs
        case .verticalOscillation:
            return tick.verticalOscillationCm
        case .grade:
            return tick.gradeFraction
        case .strideLength:
            return tick.strideLengthMeters
        }
    }
}

// MARK: - Telemetry Staleness Policy & Kinematic Helpers

/// Pure deterministic staleness policy and kinematic calculations for watchOS sensor ingestion.
public enum TelemetryStalenessPolicy {
    /// Default maximum age (5.0 s) before a sensor sample is considered stale and emitted as `nil`.
    public static let defaultMaxSampleAgeSeconds: TimeInterval = 5.0

    /// Returns the metric value if it exists and was sampled within `maxAgeSeconds` of `currentElapsed`.
    /// Returns `nil` if the sample is missing, `sampleTimestamp` is missing, or the sample is older than `maxAgeSeconds`.
    public static func validValue(
        _ value: Double?,
        sampleTimestamp: TimeInterval?,
        currentElapsed: TimeInterval,
        maxAgeSeconds: TimeInterval = defaultMaxSampleAgeSeconds
    ) -> Double? {
        guard let value, let sampleTimestamp else { return nil }
        guard (currentElapsed - sampleTimestamp) <= maxAgeSeconds else { return nil }
        return value
    }

    /// Computes the incline grade fraction (slope) given altitude and horizontal distance deltas.
    ///
    /// Returns `nil` if distance delta is insufficient (<= 0.5 m) for stable estimation.
    public static func computeGradeFraction(
        altitudeDeltaMeters: Double,
        distanceDeltaMeters: Double
    ) -> Double? {
        guard distanceDeltaMeters > 0.5 else { return nil }
        return altitudeDeltaMeters / distanceDeltaMeters
    }
}

