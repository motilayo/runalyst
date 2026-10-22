import Foundation
@testable import Runalyst

/// Injects deterministic biomechanical and sensor noise into ideal workout telemetry to simulate
/// real-world Apple Watch accelerometer jitter, GPS pace fluctuations, and heart rate sensor noise.
struct TelemetryNoiseInjector: Sendable {

    /// Deterministic pseudo-random number generator (Linear Congruential Generator)
    /// to guarantee repeatable test runs without flaky behavior.
    private struct DeterministicRNG {
        private var state: UInt64

        init(seed: UInt64) {
            self.state = seed != 0 ? seed : 0xDEADBEEFCAFE
        }

        mutating func nextDouble(in range: ClosedRange<Double>) -> Double {
            // Standard 64-bit LCG
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let normalized = Double(state >> 11) / Double(1 << 53)
            return range.lowerBound + normalized * (range.upperBound - range.lowerBound)
        }
    }

    /// Adds realistic sensor jitter to a sequence of `BucketData`:
    /// - Cadence: default ±1.5 SPM (natural biological micro-variance)
    /// - Heart Rate: default ±1.5 BPM (optical sensor reading fluctuation)
    /// - Pace: default ±3.0 s/km (GPS multipath / watch filtering noise)
    static func injectSensorJitter(
        to buckets: [BucketData],
        cadenceNoiseRange: ClosedRange<Double> = -1.5...1.5,
        hrNoiseRange: ClosedRange<Double> = -1.5...1.5,
        paceNoiseRange: ClosedRange<Double> = -3.0...3.0,
        seed: UInt64 = 42
    ) -> [BucketData] {
        var rng = DeterministicRNG(seed: seed)

        return buckets.map { bucket in
            let cadenceJitter = rng.nextDouble(in: cadenceNoiseRange)
            let hrJitter = rng.nextDouble(in: hrNoiseRange)
            let paceJitter = rng.nextDouble(in: paceNoiseRange)

            let noisyCadence = max(0, bucket.meanCadence + cadenceJitter)
            let noisyHR = max(40, bucket.meanHR + hrJitter)
            let noisyPace = max(180, bucket.meanPaceSecPerKm + paceJitter)

            // Recalculate distance based on noisy pace if moving
            let noisyDistance = noisyPace > 0 ? (bucket.durationSeconds / noisyPace) * 1000.0 : 0.0

            return BucketData(
                startTime: bucket.startTime,
                distanceMeters: noisyDistance,
                durationSeconds: bucket.durationSeconds,
                meanPaceSecPerKm: noisyPace,
                meanCadence: noisyCadence,
                meanHR: noisyHR,
                meanVerticalOscillation: bucket.meanVerticalOscillation,
                meanStrideLength: bucket.meanStrideLength
            )
        }
    }

    /// Injects chaotic adversarial noise (+/- 1.5 SPM, +/- 2.0 BPM, +/- 4.0 s/km pace jitter)
    /// to stress-test data ingestion pipelines and bit-for-bit equivalence.
    static func injectChaos(
        into buckets: [BucketData],
        seed: UInt64 = 42
    ) -> [BucketData] {
        injectSensorJitter(
            to: buckets,
            cadenceNoiseRange: -1.5...1.5,
            hrNoiseRange: -2.0...2.0,
            paceNoiseRange: -4.0...4.0,
            seed: seed
        )
    }
}
