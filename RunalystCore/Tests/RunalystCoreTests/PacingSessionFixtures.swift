import Foundation
@testable import RunalystCore

/// Deterministic synthetic telemetry generators for pacing state machine crucible tests.
public struct PacingSessionFixtures: Sendable {

    /// Deterministic pseudo-random number generator (64-bit Linear Congruential Generator).
    public struct DeterministicRNG {
        private var state: UInt64

        public init(seed: UInt64 = 42) {
            self.state = seed != 0 ? seed : 0xDEADBEEFCAFE
        }

        public mutating func nextDouble(in range: ClosedRange<Double>) -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let normalized = Double(state >> 11) / Double(1 << 53)
            return range.lowerBound + normalized * (range.upperBound - range.lowerBound)
        }
    }

    /// Injects deterministic sensor noise into a sequence of ticks:
    /// - Heart Rate: +/- 1.5 BPM
    /// - Cadence: +/- 1.2 SPM
    /// - Speed: +/- 0.08 m/s
    public static func injectNoise(
        to ticks: [TelemetryTick],
        hrNoiseRange: ClosedRange<Double> = -1.5...1.5,
        cadenceNoiseRange: ClosedRange<Double> = -1.2...1.2,
        speedNoiseRange: ClosedRange<Double> = -0.08...0.08,
        seed: UInt64 = 42
    ) -> [TelemetryTick] {
        var rng = DeterministicRNG(seed: seed)

        return ticks.map { tick in
            let hrJitter = rng.nextDouble(in: hrNoiseRange)
            let cadJitter = rng.nextDouble(in: cadenceNoiseRange)
            let speedJitter = rng.nextDouble(in: speedNoiseRange)

            let noisyHR = tick.heartRateBPM.map { max(35.0, $0 + hrJitter) }
            let noisyCad = tick.cadenceSPM.map { max(0.0, $0 + cadJitter) }
            let noisySpeed = tick.speedMetersPerSecond.map { max(0.0, $0 + speedJitter) }

            return TelemetryTick(
                elapsedSeconds: tick.elapsedSeconds,
                heartRateBPM: noisyHR,
                speedMetersPerSecond: noisySpeed,
                powerWatts: tick.powerWatts,
                cadenceSPM: noisyCad,
                imuCadenceSPM: tick.imuCadenceSPM,
                groundContactTimeMs: tick.groundContactTimeMs,
                verticalOscillationCm: tick.verticalOscillationCm,
                strideLengthMeters: tick.strideLengthMeters,
                gradeFraction: tick.gradeFraction
            )
        }
    }

    // MARK: - Scenario 1: Steady Easy Run

    /// Steady easy run with stable cardiovascular and biomechanical metrics.
    public static func makeSteadyEasyRun(
        durationSeconds: Int = 1800,
        targetPaceSecPerKm: Int = 300,
        heartRate: Double = 145.0,
        cadence: Double = 168.0,
        gct: Double = 240.0,
        power: Double = 220.0,
        seedNoise: UInt64? = nil
    ) -> [TelemetryTick] {
        let speed = 1000.0 / Double(targetPaceSecPerKm)
        var ticks: [TelemetryTick] = []
        ticks.reserveCapacity(durationSeconds)

        for s in 1...durationSeconds {
            ticks.append(TelemetryTick(
                elapsedSeconds: TimeInterval(s),
                heartRateBPM: heartRate,
                speedMetersPerSecond: speed,
                powerWatts: power,
                cadenceSPM: cadence,
                groundContactTimeMs: gct,
                verticalOscillationCm: 8.5,
                strideLengthMeters: 1.18,
                gradeFraction: 0.0
            ))
        }

        if let seed = seedNoise {
            return injectNoise(to: ticks, seed: seed)
        }
        return ticks
    }

    // MARK: - Scenario 2: Progressive Heat Drift

    /// Steady pace and power with progressive cardiac drift after calibration.
    public static func makeProgressiveHeatDrift(
        durationSeconds: Int = 1800,
        baselineHR: Double = 145.0,
        driftBPM: Double = 16.0,
        targetPaceSecPerKm: Int = 300,
        power: Double = 220.0,
        seedNoise: UInt64? = nil
    ) -> [TelemetryTick] {
        let speed = 1000.0 / Double(targetPaceSecPerKm)
        var ticks: [TelemetryTick] = []
        ticks.reserveCapacity(durationSeconds)

        for s in 1...durationSeconds {
            let hr: Double
            if s <= 600 {
                hr = baselineHR
            } else {
                // Drift linearly from 145 BPM to 145 + driftBPM over the remaining duration
                let progress = Double(s - 600) / Double(durationSeconds - 600)
                hr = baselineHR + progress * driftBPM
            }

            ticks.append(TelemetryTick(
                elapsedSeconds: TimeInterval(s),
                heartRateBPM: hr,
                speedMetersPerSecond: speed,
                powerWatts: power,
                cadenceSPM: 168.0,
                groundContactTimeMs: 240.0,
                verticalOscillationCm: 8.5,
                gradeFraction: 0.0
            ))
        }

        if let seed = seedNoise {
            return injectNoise(to: ticks, seed: seed)
        }
        return ticks
    }

    // MARK: - Scenario 3: Outdoor Hill Climb

    /// An outdoor run with a 4% hill climb, with or without running power.
    public static func makeOutdoorHillClimb(
        durationSeconds: Int = 1800,
        hillStart: Int = 900,
        hillDuration: Int = 180,
        grade: Double = 0.04,
        withPower: Bool = true,
        seedNoise: UInt64? = nil
    ) -> [TelemetryTick] {
        var ticks: [TelemetryTick] = []
        ticks.reserveCapacity(durationSeconds)

        let baseSpeed = 3.33 // ~300 s/km
        let hillSpeed = 2.85 // slows on climb

        for s in 1...durationSeconds {
            let onHill = (s >= hillStart && s < hillStart + hillDuration)
            let currentGrade: Double? = onHill ? grade : 0.0
            let currentSpeed = onHill ? hillSpeed : baseSpeed
            let currentHR = onHill ? 165.0 : 148.0
            let currentPower: Double? = {
                guard withPower else { return nil }
                return onHill ? 260.0 : 220.0
            }()

            ticks.append(TelemetryTick(
                elapsedSeconds: TimeInterval(s),
                heartRateBPM: currentHR,
                speedMetersPerSecond: currentSpeed,
                powerWatts: currentPower,
                cadenceSPM: 168.0,
                groundContactTimeMs: 240.0,
                verticalOscillationCm: 8.5,
                gradeFraction: currentGrade
            ))
        }

        if let seed = seedNoise {
            return injectNoise(to: ticks, seed: seed)
        }
        return ticks
    }

    // MARK: - Scenario 4: Heart Rate Ceiling Spikes (35 s vs 25 s)

    /// Heart rate spikes above 0.94 * maxHR (e.g. 182 BPM for maxHR 190) for specified duration.
    public static func makeHeartRateCeilingSpike(
        durationSeconds: Int = 1200,
        spikeStart: Int = 700,
        spikeDuration: Int = 35,
        baselineHR: Double = 150.0,
        spikeHR: Double = 182.0,
        targetPaceSecPerKm: Int = 300,
        seedNoise: UInt64? = nil
    ) -> [TelemetryTick] {
        let speed = 1000.0 / Double(targetPaceSecPerKm)
        var ticks: [TelemetryTick] = []
        ticks.reserveCapacity(durationSeconds)

        for s in 1...durationSeconds {
            let inSpike = (s >= spikeStart && s < spikeStart + spikeDuration)
            let hr = inSpike ? spikeHR : baselineHR

            ticks.append(TelemetryTick(
                elapsedSeconds: TimeInterval(s),
                heartRateBPM: hr,
                speedMetersPerSecond: speed,
                powerWatts: 220.0,
                cadenceSPM: 168.0,
                groundContactTimeMs: 240.0,
                verticalOscillationCm: 8.5,
                gradeFraction: 0.0
            ))
        }

        if let seed = seedNoise {
            return injectNoise(to: ticks, seed: seed)
        }
        return ticks
    }

    // MARK: - Scenario 5: Form Collapse at Minute 40

    /// Form collapse starting at elapsed 2400 s (GCT increases > 7%, cadence drops > 4 SPM).
    public static func makeFormCollapse(
        durationSeconds: Int = 2700,
        collapseStart: Int = 2400,
        seedNoise: UInt64? = nil
    ) -> [TelemetryTick] {
        var ticks: [TelemetryTick] = []
        ticks.reserveCapacity(durationSeconds)

        for s in 1...durationSeconds {
            let collapsed = s >= collapseStart
            let gct = collapsed ? 262.0 : 240.0 // +9.1% GCT delta
            let cad = collapsed ? 162.0 : 168.0 // -6 SPM cadence drop

            ticks.append(TelemetryTick(
                elapsedSeconds: TimeInterval(s),
                heartRateBPM: 152.0,
                speedMetersPerSecond: 3.33,
                powerWatts: 220.0,
                cadenceSPM: cad,
                groundContactTimeMs: gct,
                verticalOscillationCm: 9.0,
                gradeFraction: 0.0
            ))
        }

        if let seed = seedNoise {
            return injectNoise(to: ticks, seed: seed)
        }
        return ticks
    }

    // MARK: - Scenario 6: Sensor Dropout During Calibration

    /// High dropout rate (50%) during calibration baseline window (300...900 s).
    public static func makeSensorDropout(
        durationSeconds: Int = 1200,
        dropoutStart: Int = 300,
        dropoutEnd: Int = 900,
        dropoutProbability: Double = 0.50,
        seed: UInt64 = 99
    ) -> [TelemetryTick] {
        var rng = DeterministicRNG(seed: seed)
        var ticks: [TelemetryTick] = []
        ticks.reserveCapacity(durationSeconds)

        for s in 1...durationSeconds {
            let inDropoutWindow = (s >= dropoutStart && s <= dropoutEnd)
            let isDropped = inDropoutWindow && (rng.nextDouble(in: 0.0...1.0) < dropoutProbability)

            let hr: Double? = isDropped ? nil : 148.0
            ticks.append(TelemetryTick(
                elapsedSeconds: TimeInterval(s),
                heartRateBPM: hr,
                speedMetersPerSecond: 3.33,
                powerWatts: 220.0,
                cadenceSPM: 168.0,
                groundContactTimeMs: 240.0,
                verticalOscillationCm: 8.5,
                gradeFraction: 0.0
            ))
        }

        return ticks
    }

    // MARK: - Scenario 7: 2-Hour Long Run (7,200 Ticks)

    /// Full 7,200-tick (2 hours) endurance session for memory stability and crucible performance.
    public static func makeLongRun(
        tickCount: Int = 7200,
        targetPaceSecPerKm: Int = 320,
        heartRate: Double = 142.0,
        seedNoise: UInt64? = nil
    ) -> [TelemetryTick] {
        let speed = 1000.0 / Double(targetPaceSecPerKm)
        var ticks: [TelemetryTick] = []
        ticks.reserveCapacity(tickCount)

        for s in 1...tickCount {
            ticks.append(TelemetryTick(
                elapsedSeconds: TimeInterval(s),
                heartRateBPM: heartRate,
                speedMetersPerSecond: speed,
                powerWatts: 210.0,
                cadenceSPM: 166.0,
                groundContactTimeMs: 245.0,
                verticalOscillationCm: 8.8,
                gradeFraction: 0.0
            ))
        }

        if let seed = seedNoise {
            return injectNoise(to: ticks, seed: seed)
        }
        return ticks
    }
}
