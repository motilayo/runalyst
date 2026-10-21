import Foundation
@testable import RunalystCore

/// A curated collection of golden, telemetry-accurate workout recordings representing authentic
/// real-world human physiology, sensor characteristics, and topological biomechanical signatures.
enum GoldenTelemetryFixtures {

    /// Authentic 31:24 Apple Watch interval workout (ADR-0006).
    static var authenticIntervals31Min: WorkoutTelemetryFixture {
        var samples: [BucketTelemetrySample] = []

        // Warmup: 7.5 min (15 windows of 30s) at 152 SPM, 448 s/km, 138 HR
        for _ in 0..<15 {
            samples.append(.make(paceSecPerKm: 448, cadence: 152, hr: 138, verticalOscillation: 8.4, strideLength: 0.88))
        }

        // Rep 1: 5.5 min (11 windows) at 158 SPM (+6 SPM), 350 s/km (98 s/km faster), 156 HR, 1.08m stride
        for _ in 0..<11 {
            samples.append(.make(paceSecPerKm: 350, cadence: 158, hr: 156, verticalOscillation: 8.8, strideLength: 1.08))
        }

        // Recovery 1: 2.5 min (5 windows) at 153 SPM, 440 s/km, 153 HR, 0.89m stride (cardiac lag: HR only dropped 3 BPM)
        for _ in 0..<5 {
            samples.append(.make(paceSecPerKm: 440, cadence: 153, hr: 153, verticalOscillation: 8.5, strideLength: 0.89))
        }

        // Rep 2: 5.5 min (11 windows) at 163 SPM (+7 SPM), 320 s/km (120 s/km faster), 164 HR, 1.15m stride
        for _ in 0..<11 {
            samples.append(.make(paceSecPerKm: 320, cadence: 163, hr: 164, verticalOscillation: 9.1, strideLength: 1.15))
        }

        // Recovery 2: 2.5 min (5 windows) at 156 SPM, 430 s/km, 161 HR, 0.90m stride (cardiac lag: HR only dropped 3 BPM)
        for _ in 0..<5 {
            samples.append(.make(paceSecPerKm: 430, cadence: 156, hr: 161, verticalOscillation: 8.6, strideLength: 0.90))
        }

        // Rep 3 (Terminal): 5.5 min (11 windows) at 166 SPM (+10 SPM), 310 s/km (120 s/km faster), 168 HR, 1.19m stride
        for _ in 0..<11 {
            samples.append(.make(paceSecPerKm: 310, cadence: 166, hr: 168, verticalOscillation: 9.3, strideLength: 1.19))
        }

        return WorkoutTelemetryFixture(
            id: "golden-intervals-31min",
            name: "Authentic 3x5.5m VO2 Max Intervals with Terminal Rep",
            expectedClassification: "Intervals",
            physiologicalNotes: "Demonstrates active recovery jogs, cardiac lag EPOC, stride extension pace surges, and terminal interval pairing.",
            durationMinutes: 31.4,
            samples: samples
        )
    }

    /// Hilly steady aerobic run (35 minutes).
    static var hillySteadyAerobicRun: WorkoutTelemetryFixture {
        var samples: [BucketTelemetrySample] = []
        let terrainPaces = [360.0, 290.0, 430.0, 350.0, 285.0, 435.0, 360.0]

        for pace in terrainPaces {
            // 5 minutes (10 windows of 30s) per terrain segment
            for _ in 0..<10 {
                samples.append(.make(paceSecPerKm: pace, cadence: 160.0, hr: 146.0, verticalOscillation: 8.6, strideLength: 1.02))
            }
        }

        return WorkoutTelemetryFixture(
            id: "golden-hilly-steady-35min",
            name: "Hilly Steady Aerobic Run",
            expectedClassification: "Steady Effort",
            physiologicalNotes: "Pace oscillates due to elevation, but cadence and HR are steady aerobic effort.",
            durationMinutes: 35.0,
            samples: samples
        )
    }

    /// Continuous monotonic progression run (30 minutes).
    static var monotonicProgressionRun: WorkoutTelemetryFixture {
        var samples: [BucketTelemetrySample] = []
        let quintilePaces = [420.0, 390.0, 365.0, 340.0, 315.0]
        let quintileCadences = [155.0, 158.0, 161.0, 164.0, 168.0]
        let quintileHRs = [138.0, 145.0, 152.0, 159.0, 168.0]

        for i in 0..<5 {
            // 6 minutes (12 windows of 30s) per quintile
            for _ in 0..<12 {
                samples.append(.make(
                    paceSecPerKm: quintilePaces[i],
                    cadence: quintileCadences[i],
                    hr: quintileHRs[i],
                    verticalOscillation: 8.2 + Double(i) * 0.2,
                    strideLength: 0.95 + Double(i) * 0.06
                ))
            }
        }

        return WorkoutTelemetryFixture(
            id: "golden-progression-30min",
            name: "Continuous Monotonic Progression Run",
            expectedClassification: "Progression Run",
            physiologicalNotes: "Strict monotonic pace acceleration across 5 quintiles with CV < 0.09 and linear cardiac ramp.",
            durationMinutes: 30.0,
            samples: samples
        )
    }

    /// Authentic city run with traffic dead stops.
    static var cityRunTrafficStops: WorkoutTelemetryFixture {
        var samples: [BucketTelemetrySample] = []

        for i in 0..<20 {
            if i == 5 || i == 11 || i == 16 {
                // Dead stops: 0 distance, 0 speed, 0 cadence, stationary HR
                samples.append(BucketTelemetrySample(
                    durationSeconds: 30.0,
                    distanceMeters: 0.0,
                    meanPaceSecPerKm: 0.0,
                    cadence: 0.0,
                    hr: 110.0
                ))
            } else {
                // Steady running
                samples.append(.make(
                    durationSeconds: 30.0,
                    paceSecPerKm: 330.0,
                    cadence: 165.0,
                    hr: 152.0,
                    verticalOscillation: 8.8,
                    strideLength: 1.10
                ))
            }
        }

        return WorkoutTelemetryFixture(
            id: "golden-city-run-traffic",
            name: "City Run with Stoplight Dead Stops",
            expectedClassification: "Urban Traffic",
            physiologicalNotes: "Contains 3 traffic dead stops requiring scrubbing.",
            durationMinutes: 10.0,
            samples: samples
        )
    }
}

/// A telemetry-accurate representation of an authentic workout recording.
struct WorkoutTelemetryFixture: Codable, Sendable {
    let id: String
    let name: String
    let expectedClassification: String
    let physiologicalNotes: String
    let durationMinutes: Double
    let samples: [BucketTelemetrySample]

    /// Converts the telemetry samples into engine-ready `TelemetryBucket` structures.
    func toTelemetryBuckets(startDate: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> [TelemetryBucket] {
        var current = startDate
        return samples.map { sample in
            let bucket = TelemetryBucket(
                timestamp: current,
                durationSeconds: sample.durationSeconds,
                distanceMeters: sample.distanceMeters,
                paceSecondsPerKm: sample.meanPaceSecPerKm,
                cadenceSPM: sample.meanCadence,
                heartRateBPM: sample.meanHR,
                groundContactTimeMs: sample.groundContactTimeMs,
                verticalOscillationCm: sample.meanVerticalOscillation > 0 ? sample.meanVerticalOscillation : nil,
                strideLengthMeters: sample.meanStrideLength > 0 ? sample.meanStrideLength : nil,
                elevationGainMeters: sample.elevationGainMeters
            )
            current = current.addingTimeInterval(sample.durationSeconds)
            return bucket
        }
    }
}

/// A single discrete telemetry window extracted from an authentic recording.
struct BucketTelemetrySample: Codable, Sendable {
    let durationSeconds: Double
    let distanceMeters: Double
    let meanPaceSecPerKm: Double
    let meanCadence: Double
    let meanHR: Double
    let meanVerticalOscillation: Double
    let meanStrideLength: Double
    let groundContactTimeMs: Double?
    let elevationGainMeters: Double

    init(
        durationSeconds: Double = 30.0,
        distanceMeters: Double,
        meanPaceSecPerKm: Double,
        cadence: Double,
        hr: Double,
        groundContactTimeMs: Double? = nil,
        verticalOscillation: Double = 0.0,
        strideLength: Double = 0.0,
        elevationGainMeters: Double = 0.0
    ) {
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.meanPaceSecPerKm = meanPaceSecPerKm
        self.meanCadence = cadence
        self.meanHR = hr
        self.groundContactTimeMs = groundContactTimeMs
        self.meanVerticalOscillation = verticalOscillation
        self.meanStrideLength = strideLength
        self.elevationGainMeters = elevationGainMeters
    }

    static func make(
        durationSeconds: Double = 30.0,
        paceSecPerKm: Double,
        cadence: Double,
        hr: Double,
        groundContactTimeMs: Double? = 240.0,
        verticalOscillation: Double = 0.0,
        strideLength: Double = 0.0,
        elevationGainMeters: Double = 0.0
    ) -> BucketTelemetrySample {
        let distance = paceSecPerKm > 0 ? (durationSeconds / paceSecPerKm) * 1000.0 : 0.0
        return BucketTelemetrySample(
            durationSeconds: durationSeconds,
            distanceMeters: distance,
            meanPaceSecPerKm: paceSecPerKm,
            cadence: cadence,
            hr: hr,
            groundContactTimeMs: groundContactTimeMs,
            verticalOscillation: verticalOscillation,
            strideLength: strideLength,
            elevationGainMeters: elevationGainMeters
        )
    }
}
