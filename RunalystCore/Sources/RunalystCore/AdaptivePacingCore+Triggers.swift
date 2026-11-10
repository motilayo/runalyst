import Foundation

// MARK: - Adaptive Pacing Triggers & Damping Logic

extension AdaptivePacingCore {

    /// Evaluates RECOVER and SURGE triggers on the 10 s evaluation cycle.
    internal mutating func evaluateAdjustmentTriggers(filteredHR: Double?) -> PacingEvent? {
        guard refractorySecondsRemaining == 0 else {
            return nil
        }

        // 1. Protection Mandate: Evaluate RECOVER first (never gated by intent or fallback profile)
        if let recoverEvent = evaluateRecover(filteredHR: filteredHR) {
            return recoverEvent
        }

        // 2. Progression Mandate: Evaluate SURGE if all conditions and gates hold
        if let surgeEvent = evaluateSurge(filteredHR: filteredHR) {
            return surgeEvent
        }

        return nil
    }

    /// Evaluates the 30 s short-window filtered pace to confirm alignment with adjusted target.
    internal mutating func evaluateBackOnTarget() -> PacingEvent? {
        guard pendingBackOnTarget, let target = currentTargetPaceSecondsPerKm else {
            return nil
        }

        guard let speedStats = ringBuffer.shortWindowStats(for: .filteredSpeed), speedStats.mean > 0 else {
            return nil
        }

        let filteredPace = Int((1000.0 / speedStats.mean).rounded())
        let tolerance = max(
            configuration.backOnTargetMinToleranceSecondsPerKm,
            Int((Double(target) * configuration.backOnTargetToleranceFraction).rounded())
        )
        let band = (target - tolerance)...(target + tolerance)

        if band.contains(filteredPace) {
            pendingBackOnTarget = false
            return .backOnTarget
        }

        return nil
    }

    /// Evaluates real-time pace drift alerts based on short-window filtered speed deviation.
    ///
    /// Emits a `.paceDrift` event when the runner continuously deviates from target pace for >= 12 seconds,
    /// followed by a 30-second refractory cooldown period. This alert is non-destructive and does NOT mutate
    /// `currentTargetPaceSecondsPerKm` or `originalTargetPaceSecondsPerKm`.
    internal mutating func evaluatePaceDriftAlert() -> PacingEvent? {
        // 1. Tick down cooldown if active
        paceDriftCooldownRemainingSeconds = max(0, paceDriftCooldownRemainingSeconds - 1)

        // 2. Resolve short-window filtered pace
        let filteredPace: Int? = {
            if let speedStats = ringBuffer.shortWindowStats(for: .filteredSpeed), speedStats.mean > 0 {
                return Int((1000.0 / speedStats.mean).rounded())
            }
            if let latestSpeed = ringBuffer.latestTick?.speedMetersPerSecond, latestSpeed > 0 {
                return Int((1000.0 / latestSpeed).rounded())
            }
            return nil
        }()

        // 3. Evaluate deviation against current target pace
        let currentDeviation = evaluateDeviation(target: currentTargetPaceSecondsPerKm, current: filteredPace)

        switch currentDeviation {
        case .tooSlow, .tooFast:
            if currentDeviation == paceDriftDeviation {
                paceDriftContinuousSeconds += 1.0
            } else {
                paceDriftDeviation = currentDeviation
                paceDriftContinuousSeconds = 1.0
            }

            if paceDriftContinuousSeconds >= configuration.paceDriftDebounceDurationSeconds && paceDriftCooldownRemainingSeconds == 0 {
                paceDriftCooldownRemainingSeconds = Int(configuration.paceDriftCooldownSeconds)
                paceDriftContinuousSeconds = 0.0
                let target = currentTargetPaceSecondsPerKm ?? 0
                let pace = filteredPace ?? 0
                let delta = abs(pace - target)
                return .paceDrift(deviation: currentDeviation, deltaSecondsPerKm: delta)
            }

        case .onTarget:
            paceDriftContinuousSeconds = 0.0
            paceDriftDeviation = .onTarget

        case .unknown:
            paceDriftContinuousSeconds = 0.0
            paceDriftDeviation = .unknown
        }

        return nil
    }

    // MARK: - Private Trigger Implementations

    private mutating func evaluateRecover(filteredHR: Double?) -> PacingEvent? {
        let deltaEF = efficiencyTracker.deltaEF(
            from: ringBuffer,
            gradeGuardFraction: configuration.gradeGuardFraction,
            minCoverage: configuration.minCoverageFraction
        )
        let triggerEF = deltaEF.map { $0 <= configuration.recoverEfficiencyDriftThreshold } ?? false
        let triggerHR = (hrCeilingExceededContinuousSeconds > configuration.hrCeilingDurationSeconds)

        let bdiAssessment = bdiTracker.evaluate(
            from: ringBuffer,
            gctDeltaThreshold: configuration.formGCTDeltaFractionThreshold,
            cadenceDropThreshold: configuration.formCadenceDropSPMThreshold,
            minCoverage: configuration.minCoverageFraction
        )
        if let bdiAssessment, bdiAssessment.formBreakdown {
            consecutiveFormBreakdowns += 1
        } else {
            consecutiveFormBreakdowns = 0
        }
        let triggerForm = consecutiveFormBreakdowns >= 2

        var activeReasons: [PacingReason] = []
        if triggerEF { activeReasons.append(.efficiencyDrift) }
        if triggerHR { activeReasons.append(.heartRateCeiling) }
        if triggerForm { activeReasons.append(.formBreakdown) }

        guard !activeReasons.isEmpty else {
            return nil
        }

        let reason: PacingReason
        let magnitudeFraction: Double

        if activeReasons.count >= 2 {
            reason = .compound
            magnitudeFraction = configuration.recoverCompoundMagnitudeFraction
        } else if triggerHR {
            reason = .heartRateCeiling
            magnitudeFraction = configuration.recoverHRCeilingMagnitudeFraction
        } else if triggerEF {
            reason = .efficiencyDrift
            magnitudeFraction = configuration.recoverSingleMagnitudeFraction
        } else {
            reason = .formBreakdown
            magnitudeFraction = configuration.recoverSingleMagnitudeFraction
        }

        guard let currentTarget = currentTargetPaceSecondsPerKm,
              let originalTarget = originalTargetPaceSecondsPerKm else {
            return nil
        }

        let uncappedDelta = Int((Double(currentTarget) * magnitudeFraction).rounded())
        var stepDelta = min(uncappedDelta, configuration.stepLimitSecondsPerKm)

        // Cumulative cap: originalTarget * (1 + 0.12)
        let maxAllowedTarget = Int((Double(originalTarget) * (1.0 + configuration.cumulativeCapFraction)).rounded())
        if currentTarget + stepDelta > maxAllowedTarget {
            stepDelta = maxAllowedTarget - currentTarget
        }

        guard stepDelta > 0 else {
            return nil
        }

        let newTarget = currentTarget + stepDelta
        currentTargetPaceSecondsPerKm = newTarget
        lastReason = reason
        state = .recover
        refractoryState = .recover
        refractorySecondsRemaining = Int(configuration.refractoryDurationSeconds)
        pendingBackOnTarget = true
        consecutiveFormBreakdowns = 0
        hrCeilingExceededContinuousSeconds = 0.0

        return .recover(deltaSecondsPerKm: stepDelta, newTargetSecondsPerKm: newTarget, reason: reason)
    }

    private mutating func evaluateSurge(filteredHR: Double?) -> PacingEvent? {
        // Gate 1: Non-fallback profile required
        guard !profile.isFallback else { return nil }

        // Gate 2: No subjective distress override
        guard !intent.subjectiveDistress else { return nil }

        // Gate 3: Intent must be steady, tempo, or progression
        guard intent.intent == .steady || intent.intent == .tempo || intent.intent == .progression else {
            return nil
        }

        // Condition 1: Filtered HR < 0.82 * maxHR
        guard let currentHR = filteredHR,
              currentHR < configuration.hrSurgeCeilingFraction * profile.maxHR else {
            return nil
        }

        // Condition 2: deltaEF >= -0.01 (requires deltaEF != nil)
        let deltaEF = efficiencyTracker.deltaEF(
            from: ringBuffer,
            gradeGuardFraction: configuration.gradeGuardFraction,
            minCoverage: configuration.minCoverageFraction
        )
        guard let deltaEF, deltaEF >= configuration.surgeEfficiencyDriftThreshold else {
            return nil
        }

        // Condition 3: 30 s cadence standard deviation < 2.0 SPM
        guard let cadenceStats = ringBuffer.shortWindowStats(for: .cadence),
              cadenceStats.standardDeviation < configuration.surgeCadenceStdDevThreshold else {
            return nil
        }

        // Condition 4: Long-window power / HR >= profile.powerToHRTopQuartile
        guard let topQuartile = profile.powerToHRTopQuartile else {
            return nil
        }
        guard let powerStats = ringBuffer.longWindowStats(for: .power),
              let hrStats = ringBuffer.longWindowStats(for: .filteredHeartRate),
              hrStats.mean > 0 else {
            return nil
        }
        let currentPowerToHR = powerStats.mean / hrStats.mean
        guard currentPowerToHR >= topQuartile else {
            return nil
        }

        guard let currentTarget = currentTargetPaceSecondsPerKm,
              let originalTarget = originalTargetPaceSecondsPerKm else {
            return nil
        }

        let uncappedDelta = Int((Double(currentTarget) * configuration.surgeMagnitudeFraction).rounded())
        var stepDelta = min(uncappedDelta, configuration.stepLimitSecondsPerKm)

        // Cumulative cap: originalTarget * (1 - 0.12)
        let minAllowedTarget = Int((Double(originalTarget) * (1.0 - configuration.cumulativeCapFraction)).rounded())
        if currentTarget - stepDelta < minAllowedTarget {
            stepDelta = currentTarget - minAllowedTarget
        }

        guard stepDelta > 0 else {
            return nil
        }

        let newTarget = currentTarget - stepDelta
        currentTargetPaceSecondsPerKm = newTarget
        lastReason = .reservesAvailable
        state = .surge
        refractoryState = .surge
        refractorySecondsRemaining = Int(configuration.refractoryDurationSeconds)
        pendingBackOnTarget = true

        return .surge(deltaSecondsPerKm: -stepDelta, newTargetSecondsPerKm: newTarget)
    }
}
