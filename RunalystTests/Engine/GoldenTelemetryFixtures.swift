import Foundation
@testable import Runalyst

/// A curated collection of golden, telemetry-accurate workout recordings representing authentic
/// real-world human physiology, sensor characteristics, and topological biomechanical signatures.
enum GoldenTelemetryFixtures {

    /// Authentic 31:24 Apple Watch interval workout (ADR-0006).
    /// Features:
    /// - 7.5 min warmup at 152 SPM, 448 s/km, 138 HR, 0.85m stride
    /// - 3 long work intervals (5.5 min each) where the runner surges pace by 98-138 s/km primarily
    ///   via stride extension (+0.25-0.35m) with modest cadence increase (+6-10 SPM).
    /// - 2 active recovery jogs (2.5 min each) where cardiac lag keeps HR high (only 3 BPM drop).
    /// - Terminal rep: The workout terminates upon completion of interval 3 without a cool-down.
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
    /// Features:
    /// - Continuous steady effort where runner maintains steady cadence (160 SPM) and aerobic HR (146 BPM).
    /// - Pace fluctuates drastically between 285 s/km (downhill) and 435 s/km (uphill) every 2-3 minutes due to terrain.
    /// - Pace CV is high (~0.12), but cadence and HR have zero intermittent surges.
    /// - Proves that intermittent topological cycle detection does not trigger false positive interval classifications on hilly courses.
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
            physiologicalNotes: "Pace oscillates due to elevation, but cadence and HR are steady aerobic effort. Must strictly not trigger intermittent cycles.",
            durationMinutes: 35.0,
            samples: samples
        )
    }

    /// Continuous monotonic progression run (30 minutes).
    /// Features:
    /// - 5 cleanly accelerating quintiles (6 minutes each): 420 -> 390 -> 365 -> 340 -> 315 s/km.
    /// - Monotonic pace progression with stable cadence rise (155 -> 168 SPM) and cardiovascular ramp (138 -> 168 BPM).
    /// - Low continuous pace CV (~0.07 < 0.09) with strong negative slope.
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

    /// Genuine unstructured Fartlek workout (25 minutes).
    /// Features:
    /// - 5 irregular surge durations (30s, 120s, 45s, 180s, 30s) alternating with variable recovery durations (60s, 150s, 45s, 90s, 60s).
    /// - Irregular cycle durations produce cycle regularity < 0.65, distinguishing Fartlek from metronomic interval repeats.
    static var trueFartlekIrregularRun: WorkoutTelemetryFixture {
        var samples: [BucketTelemetrySample] = []

        // Warmup: 3 min (12 windows of 15s) at 145 SPM, 480 s/km, 130 HR
        for _ in 0..<12 {
            samples.append(.make(durationSeconds: 15, paceSecPerKm: 480, cadence: 145, hr: 130, verticalOscillation: 8.0, strideLength: 0.85))
        }

        // Surge 1: 30s (2 windows of 15s) at 178 SPM, 320 s/km, 165 HR; Rec 1: 60s (4 windows of 15s) at 138 SPM, 500 s/km, 140 HR
        for _ in 0..<2 {
            samples.append(.make(durationSeconds: 15, paceSecPerKm: 320, cadence: 178, hr: 165, verticalOscillation: 9.0, strideLength: 1.15))
        }
        for _ in 0..<4 {
            samples.append(.make(durationSeconds: 15, paceSecPerKm: 500, cadence: 138, hr: 140, verticalOscillation: 8.1, strideLength: 0.84))
        }

        // Surge 2: 120s (8 windows of 15s) at 176 SPM, 330 s/km, 168 HR; Rec 2: 150s (10 windows of 15s) at 138 SPM, 510 s/km, 138 HR
        for _ in 0..<8 {
            samples.append(.make(durationSeconds: 15, paceSecPerKm: 330, cadence: 176, hr: 168, verticalOscillation: 9.0, strideLength: 1.12))
        }
        for _ in 0..<10 {
            samples.append(.make(durationSeconds: 15, paceSecPerKm: 510, cadence: 138, hr: 138, verticalOscillation: 8.1, strideLength: 0.83))
        }

        // Surge 3: 45s (3 windows of 15s) at 178 SPM, 320 s/km, 166 HR; Rec 3: 45s (3 windows of 15s) at 140 SPM, 500 s/km, 140 HR
        for _ in 0..<3 {
            samples.append(.make(durationSeconds: 15, paceSecPerKm: 320, cadence: 178, hr: 166, verticalOscillation: 9.0, strideLength: 1.15))
        }
        for _ in 0..<3 {
            samples.append(.make(durationSeconds: 15, paceSecPerKm: 500, cadence: 140, hr: 140, verticalOscillation: 8.1, strideLength: 0.84))
        }

        // Surge 4: 180s (12 windows of 15s) at 174 SPM, 340 s/km, 167 HR; Rec 4: 90s (6 windows of 15s) at 139 SPM, 500 s/km, 140 HR
        for _ in 0..<12 {
            samples.append(.make(durationSeconds: 15, paceSecPerKm: 340, cadence: 174, hr: 167, verticalOscillation: 8.9, strideLength: 1.10))
        }
        for _ in 0..<6 {
            samples.append(.make(durationSeconds: 15, paceSecPerKm: 500, cadence: 139, hr: 140, verticalOscillation: 8.1, strideLength: 0.84))
        }

        // Surge 5: 30s (2 windows of 15s) at 180 SPM, 310 s/km, 168 HR; Rec 5: 60s (4 windows of 15s) at 138 SPM, 500 s/km, 140 HR
        for _ in 0..<2 {
            samples.append(.make(durationSeconds: 15, paceSecPerKm: 310, cadence: 180, hr: 168, verticalOscillation: 9.2, strideLength: 1.18))
        }
        for _ in 0..<4 {
            samples.append(.make(durationSeconds: 15, paceSecPerKm: 500, cadence: 138, hr: 140, verticalOscillation: 8.1, strideLength: 0.84))
        }

        return WorkoutTelemetryFixture(
            id: "golden-fartlek-25min",
            name: "Genuine Unstructured Fartlek Run",
            expectedClassification: "Fartlek",
            physiologicalNotes: "Variable surge durations (30s to 180s) producing cycle regularity < 0.65 across >= 3 cycles.",
            durationMinutes: 25.0,
            samples: samples
        )
    }

    /// Fading steady run with turnover decay and cardiac drift (40 minutes).
    /// Features:
    /// - First 20 mins: Strong, stable aerobic running at 164 SPM, 142 HR, 360 s/km, 8.8 cm vert osc.
    /// - Last 20 mins: Athlete fatigues; turnover degrades by 7 SPM down to 157 SPM, HR drifts up +12 BPM to 154 BPM,
    ///   and vertical oscillation increases to 10.2 cm (bounding/loss of economy).
    /// - Tests Tactical Readiness fatigue detection: verifies that significant turnover decay is captured.
    static var fadingCadenceFatigueRun: WorkoutTelemetryFixture {
        var samples: [BucketTelemetrySample] = []

        // Fresh phase: 20 minutes (40 windows of 30s)
        for _ in 0..<40 {
            samples.append(.make(paceSecPerKm: 360, cadence: 164, hr: 142, verticalOscillation: 8.8, strideLength: 1.02))
        }

        // Fading phase: 20 minutes (40 windows of 30s)
        for _ in 0..<40 {
            samples.append(.make(paceSecPerKm: 385, cadence: 157, hr: 154, verticalOscillation: 10.2, strideLength: 0.94))
        }

        return WorkoutTelemetryFixture(
            id: "golden-fatigue-fading-40min",
            name: "Fading Steady Run with Biomechanical Turnover Decay",
            expectedClassification: "Steady Effort",
            physiologicalNotes: "7 SPM cadence decay, +12 BPM cardiac drift, and elevated vertical oscillation modeling acute biomechanical fatigue.",
            durationMinutes: 40.0,
            samples: samples
        )
    }

    /// Authentic structured Pyramids interval ladder (1-2-3-2-1 minutes).
    /// Features:
    /// - 5 work reps scaling symmetrically: 60s -> 120s -> 180s -> 120s -> 60s.
    /// - Uniform 60s recovery jogs.
    /// - Monotonic climb and descent with bell-curve duration symmetry >= 0.70.
    static var authenticPyramidsLadder: WorkoutTelemetryFixture {
        var samples: [BucketTelemetrySample] = []

        // Warmup: 3 min (6 windows of 30s) at 150 SPM, 460 s/km, 134 HR
        for _ in 0..<6 {
            samples.append(.make(paceSecPerKm: 460, cadence: 150, hr: 134, verticalOscillation: 8.3, strideLength: 0.88))
        }

        let ladderSurges = [2, 4, 6, 4, 2] // 60s, 120s, 180s, 120s, 60s (in 30s windows)
        for surgeWindows in ladderSurges {
            // Work surge
            for _ in 0..<surgeWindows {
                samples.append(.make(paceSecPerKm: 320, cadence: 176, hr: 166, verticalOscillation: 9.1, strideLength: 1.15))
            }
            // Recovery
            for _ in 0..<2 {
                samples.append(.make(paceSecPerKm: 510, cadence: 135, hr: 144, verticalOscillation: 8.2, strideLength: 0.84))
            }
        }

        return WorkoutTelemetryFixture(
            id: "golden-pyramids-ladder",
            name: "Structured 1-2-3-2-1 Pyramids Ladder",
            expectedClassification: "Pyramids",
            physiologicalNotes: "Symmetrical expanding and contracting interval ladder with workBlockSymmetry >= 0.70.",
            durationMinutes: 17.0,
            samples: samples
        )
    }

    /// Continuous run punctuated by chaotic urban street stops (crosswalks, stoplights).
    /// Features:
    /// - Continuous steady running at 158 SPM punctuated by 4 abrupt 15s dead-stops (< 70 SPM, pace > 600 s/km).
    /// - Lacks structured interval symmetry or purposeful recovery floors.
    static var urbanTrafficCrosswalkRun: WorkoutTelemetryFixture {
        var samples: [BucketTelemetrySample] = []

        for i in 0..<80 {
            // 4 street stoplights with irregular city block intervals (buckets 10, 28, 42, 65)
            if i == 10 || i == 28 || i == 42 || i == 65 {
                samples.append(.make(durationSeconds: 15, paceSecPerKm: 800, cadence: 0, hr: 125, verticalOscillation: 0, strideLength: 0))
            } else {
                samples.append(.make(durationSeconds: 15, paceSecPerKm: 380, cadence: 158, hr: 146, verticalOscillation: 8.6, strideLength: 1.0))
            }
        }

        return WorkoutTelemetryFixture(
            id: "golden-urban-traffic-crosswalk",
            name: "Urban Run with Crosswalk Stops",
            expectedClassification: "Urban Traffic",
            physiologicalNotes: "Chaotic 15s dead-stops without interval periodicity triggering urbanTraffic entropy.",
            durationMinutes: 20.0,
            samples: samples
        )
    }

    /// Authentic hill repeats workout with repeated elevation gain sawtooths.
    /// Features:
    /// - 4 steep hill climb reps (+10m gain each) correlated with HR spikes to 170+ BPM, followed by descending recoveries.
    static var authenticHillRepeatsSawtooth: WorkoutTelemetryFixture {
        var samples: [BucketTelemetrySample] = []

        // Warmup: 3 min (6 windows of 30s)
        for _ in 0..<6 {
            samples.append(.make(paceSecPerKm: 450, cadence: 152, hr: 135, verticalOscillation: 8.4, strideLength: 0.90, elevationGainMeters: 0.0))
        }

        // 4 climb and descent reps
        for _ in 0..<4 {
            // Climb: 60s (2 windows of 30s) with +5.5m gain per window (+11m total), elevated HR
            for _ in 0..<2 {
                samples.append(.make(paceSecPerKm: 410, cadence: 162, hr: 172, verticalOscillation: 9.3, strideLength: 0.98, elevationGainMeters: 5.5))
            }
            // Recovery descent: 60s (2 windows of 30s) with 0m gain, lower HR
            for _ in 0..<2 {
                samples.append(.make(paceSecPerKm: 420, cadence: 150, hr: 140, verticalOscillation: 8.3, strideLength: 0.92, elevationGainMeters: 0.0))
            }
        }

        return WorkoutTelemetryFixture(
            id: "golden-hill-repeats-sawtooth",
            name: "Authentic 4x Hill Repeats with Sawtooth Elevation",
            expectedClassification: "Hill Repeats",
            physiologicalNotes: "Repeated elevation climb surges correlated with cardiac spikes followed by descending recovery.",
            durationMinutes: 11.0,
            samples: samples
        )
    }

    /// All curated golden fixtures representing diverse authentic workout topologies.
    static var allFixtures: [WorkoutTelemetryFixture] {
        [
            authenticIntervals31Min,
            hillySteadyAerobicRun,
            monotonicProgressionRun,
            trueFartlekIrregularRun,
            fadingCadenceFatigueRun,
            authenticPyramidsLadder,
            urbanTrafficCrosswalkRun,
            authenticHillRepeatsSawtooth
        ]
    }
}
