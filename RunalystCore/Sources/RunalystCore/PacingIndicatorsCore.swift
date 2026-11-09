import Foundation

// MARK: - Efficiency Factor Source

/// Primary telemetry stream used to derive the runner's real-time Efficiency Factor.
public enum EFSource: String, Sendable, Codable {
    case power
    case speed
}

// MARK: - Efficiency Drift Tracker

/// Tracks cardiovascular efficiency drift relative to a locked calibration baseline.
///
/// Implements power-preferred EF with speed fallback, source-consistency guards,
/// and grade suspension per sports science design D4.
public struct EfficiencyDriftTracker: Sendable {
    public let location: PacingLocation
    private(set) public var ef0: Double?
    private(set) public var efSource: EFSource?

    public init(location: PacingLocation) {
        self.location = location
        self.ef0 = nil
        self.efSource = nil
    }

    /// Locks baseline Efficiency Factor and source.
    public mutating func lockBaseline(ef: Double, source: EFSource) {
        self.ef0 = ef
        self.efSource = source
    }

    /// Derives baseline EF from the ring buffer over a specified baseline interval.
    public mutating func lockBaseline(
        from ringBuffer: TelemetryRingBuffer,
        in interval: ClosedRange<TimeInterval>,
        minCoverage: Double = 0.80
    ) -> Bool {
        guard let hrStats = ringBuffer.stats(for: .filteredHeartRate, in: interval, minCoverage: minCoverage),
              hrStats.mean > 0 else {
            return false
        }

        // 1. Try power
        if let powerStats = ringBuffer.stats(for: .power, in: interval, minCoverage: minCoverage) {
            let ef = powerStats.mean / hrStats.mean
            lockBaseline(ef: ef, source: .power)
            return true
        }

        // 2. Speed fallback (outdoor only)
        if location == .outdoor,
           let speedStats = ringBuffer.stats(for: .filteredSpeed, in: interval, minCoverage: minCoverage) {
            let ef = speedStats.mean / hrStats.mean
            lockBaseline(ef: ef, source: .speed)
            return true
        }

        return false
    }

    /// Computes the current 180 s long-window Efficiency Factor.
    public func currentEF(
        from ringBuffer: TelemetryRingBuffer,
        minCoverage: Double = 0.80
    ) -> (ef: Double, source: EFSource)? {
        guard let hrStats = ringBuffer.longWindowStats(for: .filteredHeartRate),
              hrStats.coverage >= minCoverage,
              hrStats.mean > 0 else {
            return nil
        }

        // Prefer power when coverage >= 80%
        if let powerStats = ringBuffer.longWindowStats(for: .power),
           powerStats.coverage >= minCoverage {
            return (ef: powerStats.mean / hrStats.mean, source: .power)
        }

        // Fall back to speed only when outdoor
        guard location == .outdoor else {
            return nil
        }

        if let speedStats = ringBuffer.longWindowStats(for: .filteredSpeed),
           speedStats.coverage >= minCoverage {
            return (ef: speedStats.mean / hrStats.mean, source: .speed)
        }

        return nil
    }

    /// Computes fractional drift relative to baseline: `(EF_t - EF_0) / EF_0`.
    ///
    /// Returns `nil` when:
    /// - Baseline is not yet locked
    /// - Current EF source does not match locked baseline source
    /// - Speed-based EF encounters a grade exceeding 1.5% in magnitude
    /// - Sensor coverage is below the 80% threshold
    public func deltaEF(
        from ringBuffer: TelemetryRingBuffer,
        gradeGuardFraction: Double = 0.015,
        minCoverage: Double = 0.80
    ) -> Double? {
        guard let ef0, let efSource, ef0 > 0 else {
            return nil
        }

        guard let (current, source) = currentEF(from: ringBuffer, minCoverage: minCoverage) else {
            return nil
        }

        // Source-consistency rule: never compare speed against power baseline
        guard source == efSource else {
            return nil
        }

        // Grade guard for speed-based EF: suspend when short-window |grade| > 1.5%
        if efSource == .speed,
           let gradeStats = ringBuffer.shortWindowStats(for: .grade),
           abs(gradeStats.mean) > gradeGuardFraction {
            return nil
        }

        return (current - ef0) / ef0
    }
}

// MARK: - Biomechanical Degradation Assessment

/// Result of evaluating short-window form degradation against calibrated baseline.
public struct BiomechanicalAssessment: Sendable, Equatable {
    /// Relative Biomechanical Degradation Index: `(GCT_t / GCT_0) * (Cadence_0 / Cadence_t) - 1.0`.
    public let bdi: Double
    /// Relative Ground Contact Time change: `(GCT_t - GCT_0) / GCT_0`.
    public let gctDeltaFraction: Double
    /// Cadence drop in steps per minute: `Cadence_0 - Cadence_t`.
    public let cadenceDropSPM: Double
    /// Whether acute form breakdown is active (GCT delta > 7% AND cadence drop > 4 SPM).
    public let formBreakdown: Bool

    public init(
        bdi: Double,
        gctDeltaFraction: Double,
        cadenceDropSPM: Double,
        formBreakdown: Bool
    ) {
        self.bdi = bdi
        self.gctDeltaFraction = gctDeltaFraction
        self.cadenceDropSPM = cadenceDropSPM
        self.formBreakdown = formBreakdown
    }
}

// MARK: - Biomechanical Degradation Index Tracker

/// Tracks kinematic breakdown (elongated ground contact time paired with cadence fade).
public struct BiomechanicalDegradationIndex: Sendable {
    private(set) public var gct0: Double?
    private(set) public var cadence0: Double?

    public init(gct0: Double? = nil, cadence0: Double? = nil) {
        self.gct0 = gct0
        self.cadence0 = cadence0
    }

    /// Locks baseline kinematics.
    public mutating func lockBaseline(gct: Double, cadence: Double) {
        self.gct0 = gct
        self.cadence0 = cadence
    }

    /// Derives baseline kinematics from ring buffer over a specified baseline interval.
    public mutating func lockBaseline(
        from ringBuffer: TelemetryRingBuffer,
        in interval: ClosedRange<TimeInterval>,
        minCoverage: Double = 0.80
    ) -> Bool {
        guard let gctStats = ringBuffer.stats(for: .groundContactTime, in: interval, minCoverage: minCoverage),
              let cadenceStats = ringBuffer.stats(for: .cadence, in: interval, minCoverage: minCoverage),
              gctStats.mean > 0,
              cadenceStats.mean > 0 else {
            return false
        }

        lockBaseline(gct: gctStats.mean, cadence: cadenceStats.mean)
        return true
    }

    /// Evaluates 30 s short-window biomechanics against calibrated baseline.
    ///
    /// Returns `nil` when baseline is unlocked or footpod/sensor metrics are missing.
    public func evaluate(
        from ringBuffer: TelemetryRingBuffer,
        gctDeltaThreshold: Double = 0.07,
        cadenceDropThreshold: Double = 4.0,
        minCoverage: Double = 0.80
    ) -> BiomechanicalAssessment? {
        guard let gct0, let cadence0, gct0 > 0, cadence0 > 0 else {
            return nil
        }

        guard let gctStats = ringBuffer.shortWindowStats(for: .groundContactTime),
              let cadenceStats = ringBuffer.shortWindowStats(for: .cadence),
              gctStats.coverage >= minCoverage,
              cadenceStats.coverage >= minCoverage,
              cadenceStats.mean > 0 else {
            return nil
        }

        let shortGCT = gctStats.mean
        let shortCadence = cadenceStats.mean

        let gctDeltaFraction = (shortGCT - gct0) / gct0
        let cadenceDropSPM = cadence0 - shortCadence
        let bdi = (shortGCT / gct0) * (cadence0 / shortCadence) - 1.0
        let formBreakdown = (gctDeltaFraction > gctDeltaThreshold) && (cadenceDropSPM > cadenceDropThreshold)

        return BiomechanicalAssessment(
            bdi: bdi,
            gctDeltaFraction: gctDeltaFraction,
            cadenceDropSPM: cadenceDropSPM,
            formBreakdown: formBreakdown
        )
    }
}
