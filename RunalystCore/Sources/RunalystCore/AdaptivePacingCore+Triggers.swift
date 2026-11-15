import Foundation

// MARK: - Adaptive Pacing Triggers & Damping Logic

extension AdaptivePacingCore {

    /// Advances the tactile entrainer by 1 second and syncs quiet checkpoint cooldowns.
    internal mutating func tickMetronomeRamp(hrEstimate: Double?, currentCadenceSPM: Int?) {
        let wasActive = (metronomeRamp.activeCue != nil)
        if !wasActive {
            if metronomeRamp.cooldownRemainingSeconds > 0 {
                _ = metronomeRamp.tick(currentSPM: currentCadenceSPM, isEffortOnTarget: false)
            }
            return
        }
        let isEffortOnTarget = evaluateEffortOnTargetForEntrainer(hrEstimate: hrEstimate)
        let updatedCue = metronomeRamp.tick(
            currentSPM: currentCadenceSPM,
            isEffortOnTarget: isEffortOnTarget
        )

        if wasActive && updatedCue == nil {
            let rampCooldown = Int(metronomeRamp.cooldownRemainingSeconds)
            if configuration.cadenceDriftCooldownSeconds >= 240.0 {
                cadenceDriftCooldownRemainingSeconds = max(cadenceDriftCooldownRemainingSeconds, rampCooldown)
            }
            if configuration.paceDriftCooldownSeconds >= 240.0 {
                paceDriftCooldownRemainingSeconds = max(paceDriftCooldownRemainingSeconds, rampCooldown)
            }
        }
    }

    private func evaluateEffortOnTargetForEntrainer(hrEstimate: Double?) -> Bool {
        guard let cue = metronomeRamp.activeCue else { return false }
        let ceilingBPM: Double = (intent.intent == .recovery || intent.subjectiveDistress)
            ? 0.78 * profile.maxHR
            : configuration.hrCeilingFraction * profile.maxHR

        switch cue.mode {
        case .effortDown:
            let hrSafe = hrEstimate.map { $0 < ceilingBPM } ?? false
            return hrSafe && paceDriftDeviation != .tooFast
        case .effortUp:
            if activeBlock.kind == .thresholdSurge,
               let speed = ringBuffer.latestTick?.speedMetersPerSecond,
               let baseSpeed = blockRuntime.baselineSpeedMPS,
               baseSpeed > 0 {
                return speed >= baseSpeed * 1.015
            }
            return paceDriftDeviation == .onTarget || paceDriftDeviation == .tooFast
        case .cadenceMetronome:
            return false
        }
    }

    private func isIndoorEffortAndCadenceHealthy(resolvedCadenceSPM: Int?) -> Bool {
        let ceilingBPM: Double = (intent.intent == .recovery || intent.subjectiveDistress)
            ? 0.78 * profile.maxHR
            : configuration.hrCeilingFraction * profile.maxHR
        guard let hr = kalmanHR.currentEstimate ?? ringBuffer.latestTick?.heartRateBPM,
              hr < ceilingBPM else {
            return false
        }
        guard let cadence = resolvedCadenceSPM,
              cadence >= configuration.cadenceFloorSPM else {
            return false
        }
        if let targetCadence = currentTargetCadenceSPM {
            return Double(cadence) >= Double(targetCadence) - configuration.cadenceDriftThresholdSPM
        }
        return true
    }

    /// Evaluates RECOVER and SURGE triggers on the 10 s evaluation cycle.
    internal mutating func evaluateAdjustmentTriggers(
        filteredHR: Double?,
        resolvedCadenceSPM: Int?
    ) -> PacingEvent? {
        guard refractorySecondsRemaining == 0 else {
            return nil
        }

        // 1. Protection Mandate: Evaluate RECOVER first (never gated by intent or fallback profile)
        if let recoverEvent = evaluateRecover(filteredHR: filteredHR, resolvedCadenceSPM: resolvedCadenceSPM) {
            return recoverEvent
        }

        // 2. Progression Mandate: Evaluate SURGE if all conditions and gates hold
        if let surgeEvent = evaluateSurge(filteredHR: filteredHR) {
            return surgeEvent
        }

        return nil
    }

    /// Evaluates the 30 s short-window filtered pace to confirm alignment with adjusted target.
    internal mutating func evaluateBackOnTarget(shortSpeedMean: Double?) -> PacingEvent? {
        guard pendingBackOnTarget, let target = currentTargetPaceSecondsPerKm else {
            return nil
        }

        guard let speedMean = shortSpeedMean, speedMean > 0 else {
            return nil
        }

        let filteredPace = Int((1000.0 / speedMean).rounded())
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

    /// Evaluates whether filtered pace has entered .onTarget for a pending surge target pace.
    internal mutating func evaluateSurgeLockIn(shortSpeedMean: Double?) -> PacingEvent? {
        guard let target = awaitingSurgeLockInTargetSecondsPerKm else {
            return nil
        }

        let filteredPace: Int? = {
            if let speedMean = shortSpeedMean, speedMean > 0 {
                return Int((1000.0 / speedMean).rounded())
            }
            if let latestSpeed = ringBuffer.latestTick?.speedMetersPerSecond, latestSpeed > 0 {
                return Int((1000.0 / latestSpeed).rounded())
            }
            return nil
        }()

        let deviation = evaluateDeviation(target: target, current: filteredPace)
        if deviation == .onTarget {
            awaitingSurgeLockInTargetSecondsPerKm = nil
            return .surgeLockedIn(targetPaceSecondsPerKm: target)
        }

        return nil
    }

    /// Evaluates real-time pace drift alerts based on short-window filtered speed deviation.
    ///
    /// Emits a `.paceDrift` event when the runner continuously deviates from target pace for >= 12 seconds,
    /// followed by a 30-second refractory cooldown period. This alert is non-destructive and does NOT mutate
    /// `currentTargetPaceSecondsPerKm` or `originalTargetPaceSecondsPerKm`.
    internal mutating func evaluatePaceDriftAlert(
        shortSpeedMean: Double?,
        resolvedCadenceSPM: Int?
    ) -> PacingEvent? {
        // 1. Tick down cooldown if active
        paceDriftCooldownRemainingSeconds = max(0, paceDriftCooldownRemainingSeconds - 1)

        // Indoor reliability: suppress outdoor-offset pace drift nudges when HR and IMU cadence are healthy
        if location == .indoor, isIndoorEffortAndCadenceHealthy(resolvedCadenceSPM: resolvedCadenceSPM) {
            paceDriftContinuousSeconds = 0.0
            paceDriftDeviation = .onTarget
            return nil
        }

        // 2. Resolve short-window filtered pace
        let filteredPace: Int? = {
            if let speedMean = shortSpeedMean, speedMean > 0 {
                return Int((1000.0 / speedMean).rounded())
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
                if currentDeviation == .tooFast {
                    _ = metronomeRamp.startEffortBurst(mode: .effortDown)
                } else {
                    _ = metronomeRamp.startEffortBurst(mode: .effortUp)
                }
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

    /// Evaluates real-time cadence drop alerts based on short-window cadence statistics.
    ///
    /// Emits a `.cadenceDrift` event when the runner continuously runs below target cadence by >= 6 SPM
    /// (or below the absolute 150 SPM floor) for >= 12 seconds, followed by a 30-second refractory cooldown period.
    /// Non-destructive: does NOT mutate target paces or triggers.
    internal mutating func evaluateCadenceDriftAlert(resolvedCadenceSPM: Int?) -> PacingEvent? {
        // 1. Decrement cooldown if active
        cadenceDriftCooldownRemainingSeconds = max(0, cadenceDriftCooldownRemainingSeconds - 1)

        // 2. Check short-window cadence stats
        guard let currentCadence = resolvedCadenceSPM, let targetCadence = currentTargetCadenceSPM else {
            cadenceDriftContinuousSeconds = 0.0
            return nil
        }

        // 3. Evaluate threshold or floor violation
        let isBelowThreshold = Double(currentCadence) < Double(targetCadence) - configuration.cadenceDriftThresholdSPM
        let isBelowFloor = currentCadence < configuration.cadenceFloorSPM

        if isBelowThreshold || isBelowFloor {
            cadenceDriftContinuousSeconds += 1.0
            healthyCadenceContinuousSeconds = 0.0

            if hasEstablishedSolidCadence && solidCadenceUntilDistanceMeters == nil {
                if cadenceDriftContinuousSeconds >= configuration.cadenceDriftDebounceDurationSeconds {
                    solidCadenceUntilDistanceMeters = latestTotalDistanceMeters
                }
            }

            if cadenceDriftContinuousSeconds >= configuration.cadenceDriftDebounceDurationSeconds && cadenceDriftCooldownRemainingSeconds == 0 {
                cadenceDriftCooldownRemainingSeconds = Int(configuration.cadenceDriftCooldownSeconds)
                cadenceDriftContinuousSeconds = 0.0
                let delta = max(0, targetCadence - currentCadence)
                _ = metronomeRamp.startCadenceBurst(currentSPM: currentCadence, goalSPM: targetCadence)
                return .cadenceDrift(
                    currentCadenceSPM: currentCadence,
                    targetCadenceSPM: targetCadence,
                    deltaSPM: delta
                )
            }
        } else {
            // Cadence is healthy / within target
            cadenceDriftContinuousSeconds = 0.0
            healthyCadenceContinuousSeconds += 1.0
            if healthyCadenceContinuousSeconds >= 30.0 {
                hasEstablishedSolidCadence = true
            }
        }

        return nil
    }

    // MARK: - Private Trigger Implementations

    private mutating func evaluateRecover(
        filteredHR: Double?,
        resolvedCadenceSPM: Int?
    ) -> PacingEvent? {
        let deltaEF = efficiencyTracker.deltaEF(
            from: ringBuffer,
            gradeGuardFraction: configuration.gradeGuardFraction,
            minCoverage: configuration.minCoverageFraction
        )
        let triggerEF = deltaEF.map { $0 <= configuration.recoverEfficiencyDriftThreshold } ?? false
        let triggerHR = (hrCeilingExceededContinuousSeconds > configuration.hrCeilingDurationSeconds)

        if (triggerEF || triggerHR) && firstDriftElapsedSeconds == nil {
            firstDriftElapsedSeconds = ringBuffer.latestTick?.elapsedSeconds
        }

        let bdiAssessment = bdiTracker.evaluate(
            from: ringBuffer,
            gctDeltaThreshold: configuration.formGCTDeltaFractionThreshold,
            cadenceDropThreshold: configuration.formCadenceDropSPMThreshold,
            minCoverage: configuration.minCoverageFraction
        )
        if let bdiAssessment, bdiAssessment.formBreakdown {
            consecutiveFormBreakdowns += 1
            if hasEstablishedSolidCadence && solidCadenceUntilDistanceMeters == nil && consecutiveFormBreakdowns >= 2 {
                solidCadenceUntilDistanceMeters = latestTotalDistanceMeters
            }
        } else {
            consecutiveFormBreakdowns = 0
        }
        let triggerForm = consecutiveFormBreakdowns >= 2

        var activeReasons: [PacingReason] = []
        if triggerEF { activeReasons.append(.efficiencyDrift) }
        if triggerHR { activeReasons.append(.heartRateCeiling) }
        if triggerForm { activeReasons.append(.formBreakdown) }

        if activeReasons.isEmpty {
            // First-tier non-destructive form check nudge on first degradation without dial-back
            if consecutiveFormBreakdowns == 1 {
                let currentCadence = resolvedCadenceSPM ?? currentTargetCadenceSPM ?? 160
                let goalSPM = currentTargetCadenceSPM ?? max(configuration.cadenceFloorSPM, currentCadence + 3)
                _ = metronomeRamp.startCadenceBurst(currentSPM: currentCadence, goalSPM: goalSPM)
                return .formCheck(currentCadenceSPM: currentCadence, targetCadenceSPM: currentTargetCadenceSPM)
            }
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

        recoveryAdjustmentCount += 1
        _ = metronomeRamp.startEffortBurst(mode: .effortDown, bypassCooldown: true)

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
        awaitingSurgeLockInTargetSecondsPerKm = newTarget

        surgeCount += 1
        peakSurgeDeltaSecondsPerKm = max(peakSurgeDeltaSecondsPerKm, stepDelta)
        _ = metronomeRamp.startEffortBurst(mode: .effortUp, bypassCooldown: true)

        return .surge(deltaSecondsPerKm: -stepDelta, newTargetSecondsPerKm: newTarget)
    }
}
