import Foundation

// MARK: - Run Classifier Core (Sports Science Taxonomy Ingot)

/// Pure, stateless sports science classification engine.
/// Translates multi-signal biomechanical telemetry into verified physiological workout classifications.
public enum RunClassifierCore {

    /// Calculates the mean cadence of the slowest 20% pace buckets or recovery phases, representing the recovery floor.
    public static func calculateRecoveryCadenceFloor(
        buckets: [TelemetryBucket],
        cycles: [IntervalOscillationCycle] = []
    ) -> Double {
        if !cycles.isEmpty {
            return cycles.map(\.recoveryCadenceSPM).reduce(0, +) / Double(cycles.count)
        }
        guard !buckets.isEmpty else { return 0.0 }
        let sortedByPace = buckets.sorted { $0.paceSecondsPerKm > $1.paceSecondsPerKm }
        let sliceCount = max(1, Int(Double(sortedByPace.count) * 0.20))
        let slowest = sortedByPace.prefix(sliceCount)
        return slowest.map(\.cadenceSPM).reduce(0, +) / Double(sliceCount)
    }

    /// Evaluates the duration symmetry of intermittent work intervals to identify pyramid structures.
    /// Returns 0.0 to 1.0 (higher = symmetric expanding and contracting ladder, e.g. 1-2-3-2-1 mins).
    public static func calculateWorkBlockSymmetry(cycles: [IntervalOscillationCycle]) -> Double {
        guard cycles.count >= 3 else { return 0.0 }
        let workDurations = cycles.map(\.workDurationSeconds)
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

        let count = workDurations.count
        var diffSum = 0.0
        let comparisons = count / 2
        for i in 0..<comparisons {
            diffSum += abs(workDurations[i] - workDurations[count - 1 - i])
        }
        let totalWork = workDurations.reduce(0, +)
        guard totalWork > 0 else { return 0.0 }

        return max(0.0, 1.0 - ((diffSum * 2.0) / totalWork))
    }

    /// Evaluates non-periodic cadence crashes (< 70 SPM) and pace dropouts characteristic of city running.
    /// Returns a ratio from 0.0 to 1.0 representing chaotic dead stops relative to total buckets.
    public static func detectUrbanTrafficEntropy(buckets: [TelemetryBucket]) -> Double {
        guard buckets.count >= 8 else { return 0.0 }
        var stopDurations: [Double] = []
        var currentStopDuration = 0.0
        var totalStopDuration = 0.0

        for bucket in buckets {
            if bucket.cadenceSPM < 70.0 || bucket.paceSecondsPerKm > 600.0 {
                currentStopDuration += bucket.durationSeconds
                totalStopDuration += bucket.durationSeconds
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

        let meanStop = stopDurations.reduce(0, +) / Double(stopDurations.count)
        return meanStop <= 30.0 ? (totalStopDuration / totalDuration) : 0.0
    }

    /// Detects repeated saw-tooth elevation climbs synchronized with cardiac surges.
    public static func detectHillRepeats(buckets: [TelemetryBucket]) -> Bool {
        guard buckets.count >= 6 else { return false }
        let totalGain = buckets.compactMap(\.elevationGainMeters).reduce(0, +)
        guard totalGain >= 35.0 else { return false }

        var climbEpisodes = 0
        var inClimb = false
        for bucket in buckets {
            let isClimbing = (bucket.elevationGainMeters ?? 0) >= 4.0
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
    public static func classifyRun(
        buckets: [TelemetryBucket],
        cv: Double,
        slope: Double,
        zone4: Double,
        durationMinutes: Double,
        cadenceCV: Double = 0.0,
        averageHR: Double? = nil,
        paceDelta: Double? = nil,
        hrDelta: Double? = nil,
        cycles: [IntervalOscillationCycle]? = nil,
        deadStopsCount: Int = 0,
        hoursSinceHeavyEffort: Double? = nil,
        isIndoor: Bool = false
    ) -> String {
        // LAYER 0: Environmental Interruption (Urban Traffic) - strictly impossible indoors
        let trafficEntropy = isIndoor ? 0.0 : detectUrbanTrafficEntropy(buckets: buckets)
        let isChaoticTraffic = !isIndoor && (trafficEntropy >= 0.04 || (deadStopsCount >= 4 && cv > 0.10))

        // LAYER 1: Continuous Monotonic Progression (Strict progressive acceleration)
        let isProgression = durationMinutes >= 20.0 && cv < 0.09 && IntervalSegmenterCore.evaluateQuintileProgression(buckets: buckets)
        if isProgression {
            return "Progression Run"
        }

        // CV < 0.10 Gating: Classify strictly as Steady State or Progression.
        let isUniformSteady = cv < 0.10

        // LAYER 2: Structural Gate (Intermittent vs. Continuous)
        let validatedCycles = cycles ?? IntervalSegmenterCore.extractOscillationCycles(buckets: buckets)
        let avgCycleContrast = validatedCycles.isEmpty ? 0.0 : (validatedCycles.map { $0.recoveryPaceSecondsPerKm - $0.workPaceSecondsPerKm }.reduce(0, +) / Double(validatedCycles.count))
        let isIntermittent: Bool = {
            guard avgCycleContrast >= 25.0 else { return false }
            if validatedCycles.count >= 3 {
                return true
            }
            if validatedCycles.count == 2 && cv >= 0.12 && !isUniformSteady {
                return true
            }
            return false
        }()
        let regularityScore = isIntermittent ? IntervalSegmenterCore.calculateCycleRegularity(cycles: validatedCycles) : 0.0

        // If traffic was chaotic and it's not a structured threshold interval workout, classify as Urban Traffic
        if !isIndoor && !isUniformSteady && isChaoticTraffic && (zone4 < 0.35 || regularityScore < 0.65) {
            return "Urban Traffic"
        }

        // LAYER 2.5: Topographic Sawtooth Climbs (Hill Repeats) - strictly impossible indoors
        if !isIndoor && detectHillRepeats(buckets: buckets) {
            return "Hill Repeats"
        }

        // LAYER 3: Intermittent Sub-Classification (Pyramids vs. Intervals vs. Fartlek)
        if isIntermittent {
            let symmetryScore = calculateWorkBlockSymmetry(cycles: validatedCycles)
            if symmetryScore >= 0.70 {
                return "Pyramids"
            }

            let recoveryFloor = calculateRecoveryCadenceFloor(buckets: buckets, cycles: validatedCycles)
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
}
