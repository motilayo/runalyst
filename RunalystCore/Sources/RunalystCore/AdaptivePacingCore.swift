import Foundation

// MARK: - Location & Configuration

/// Operating environment for the adaptive pacing engine.
public enum PacingLocation: String, Sendable, Codable {
    case outdoor
    case indoor
}

/// Configuration parameters for adaptive pacing state transitions and damping.
public struct AdaptivePacingConfiguration: Sendable, Equatable {
    public var warmupDurationSeconds: TimeInterval
    public var baselineDurationSeconds: TimeInterval
    public var maxCalibrationDurationSeconds: TimeInterval
    public var calibrationExtensionStepSeconds: TimeInterval
    public var evaluationIntervalSeconds: TimeInterval
    public var refractoryDurationSeconds: TimeInterval
    public var stepLimitSecondsPerKm: Int
    public var cumulativeCapFraction: Double
    public var hrCeilingFraction: Double
    public var hrCeilingDurationSeconds: TimeInterval
    public var hrSurgeCeilingFraction: Double
    public var recoverEfficiencyDriftThreshold: Double
    public var surgeEfficiencyDriftThreshold: Double
    public var formGCTDeltaFractionThreshold: Double
    public var formCadenceDropSPMThreshold: Double
    public var surgeCadenceStdDevThreshold: Double
    public var recoverSingleMagnitudeFraction: Double
    public var recoverHRCeilingMagnitudeFraction: Double
    public var recoverCompoundMagnitudeFraction: Double
    public var surgeMagnitudeFraction: Double
    public var gradeGuardFraction: Double
    public var minCoverageFraction: Double
    public var backOnTargetMinToleranceSecondsPerKm: Int
    public var backOnTargetToleranceFraction: Double
    public var paceDriftDebounceDurationSeconds: TimeInterval
    public var paceDriftCooldownSeconds: TimeInterval

    public init(
        warmupDurationSeconds: TimeInterval = 300.0,
        baselineDurationSeconds: TimeInterval = 300.0,
        maxCalibrationDurationSeconds: TimeInterval = 900.0,
        calibrationExtensionStepSeconds: TimeInterval = 60.0,
        evaluationIntervalSeconds: TimeInterval = 10.0,
        refractoryDurationSeconds: TimeInterval = 90.0,
        stepLimitSecondsPerKm: Int = 10,
        cumulativeCapFraction: Double = 0.12,
        hrCeilingFraction: Double = 0.94,
        hrCeilingDurationSeconds: TimeInterval = 30.0,
        hrSurgeCeilingFraction: Double = 0.82,
        recoverEfficiencyDriftThreshold: Double = -0.06,
        surgeEfficiencyDriftThreshold: Double = -0.01,
        formGCTDeltaFractionThreshold: Double = 0.07,
        formCadenceDropSPMThreshold: Double = 4.0,
        surgeCadenceStdDevThreshold: Double = 2.0,
        recoverSingleMagnitudeFraction: Double = 0.03,
        recoverHRCeilingMagnitudeFraction: Double = 0.05,
        recoverCompoundMagnitudeFraction: Double = 0.08,
        surgeMagnitudeFraction: Double = 0.02,
        gradeGuardFraction: Double = 0.015,
        minCoverageFraction: Double = 0.80,
        backOnTargetMinToleranceSecondsPerKm: Int = 5,
        backOnTargetToleranceFraction: Double = 0.02,
        paceDriftDebounceDurationSeconds: TimeInterval = 12.0,
        paceDriftCooldownSeconds: TimeInterval = 30.0
    ) {
        self.warmupDurationSeconds = warmupDurationSeconds
        self.baselineDurationSeconds = baselineDurationSeconds
        self.maxCalibrationDurationSeconds = maxCalibrationDurationSeconds
        self.calibrationExtensionStepSeconds = calibrationExtensionStepSeconds
        self.evaluationIntervalSeconds = evaluationIntervalSeconds
        self.refractoryDurationSeconds = refractoryDurationSeconds
        self.stepLimitSecondsPerKm = stepLimitSecondsPerKm
        self.cumulativeCapFraction = cumulativeCapFraction
        self.hrCeilingFraction = hrCeilingFraction
        self.hrCeilingDurationSeconds = hrCeilingDurationSeconds
        self.hrSurgeCeilingFraction = hrSurgeCeilingFraction
        self.recoverEfficiencyDriftThreshold = recoverEfficiencyDriftThreshold
        self.surgeEfficiencyDriftThreshold = surgeEfficiencyDriftThreshold
        self.formGCTDeltaFractionThreshold = formGCTDeltaFractionThreshold
        self.formCadenceDropSPMThreshold = formCadenceDropSPMThreshold
        self.surgeCadenceStdDevThreshold = surgeCadenceStdDevThreshold
        self.recoverSingleMagnitudeFraction = recoverSingleMagnitudeFraction
        self.recoverHRCeilingMagnitudeFraction = recoverHRCeilingMagnitudeFraction
        self.recoverCompoundMagnitudeFraction = recoverCompoundMagnitudeFraction
        self.surgeMagnitudeFraction = surgeMagnitudeFraction
        self.gradeGuardFraction = gradeGuardFraction
        self.minCoverageFraction = minCoverageFraction
        self.backOnTargetMinToleranceSecondsPerKm = backOnTargetMinToleranceSecondsPerKm
        self.backOnTargetToleranceFraction = backOnTargetToleranceFraction
        self.paceDriftDebounceDurationSeconds = paceDriftDebounceDurationSeconds
        self.paceDriftCooldownSeconds = paceDriftCooldownSeconds
    }

    /// Standard production configuration with sports science parameters.
    public static let standard = AdaptivePacingConfiguration()
}

// MARK: - State Machine Types

/// Top-level operating state of the adaptive pacing engine.
public enum PacingState: Sendable, Equatable {
    case calibrating(progress: Double)
    case tracking
    case surge
    case recover
}

/// Underlying physiological or mechanical cause for a pacing adjustment.
public enum PacingReason: String, Sendable, Codable {
    case efficiencyDrift
    case heartRateCeiling
    case formBreakdown
    case compound
    case reservesAvailable
}

/// Discrete event emitted to the Foundry layer when pacing state shifts.
public enum PacingEvent: Sendable, Equatable {
    case calibrationComplete(originalTargetSecondsPerKm: Int, adjustmentsEnabled: Bool)
    case surge(deltaSecondsPerKm: Int, newTargetSecondsPerKm: Int)
    case recover(deltaSecondsPerKm: Int, newTargetSecondsPerKm: Int, reason: PacingReason)
    case backOnTarget
    case paceDrift(deviation: PaceDeviation, deltaSecondsPerKm: Int)
}

/// Real-time deviation category of current pace against target.
public enum PaceDeviation: String, Sendable, Codable {
    case onTarget
    case tooFast
    case tooSlow
    case unknown
}

// MARK: - Adaptive Pacing Core State Machine

/// Deterministic, real-time closed-loop state machine for watchOS pacing adjustments.
public struct AdaptivePacingCore: Sendable {
    public let profile: AthleteCalibrationProfile
    public let intent: PacingSessionIntent
    public let location: PacingLocation
    public let configuration: AdaptivePacingConfiguration

    // Internal condition trackers
    internal var kalmanHR: KalmanFilter1D
    internal var kalmanSpeed: KalmanFilter1D
    internal var ringBuffer: TelemetryRingBuffer
    internal var efficiencyTracker: EfficiencyDriftTracker
    internal var bdiTracker: BiomechanicalDegradationIndex

    // State machine dynamics
    internal var state: PacingState
    internal var calibrationTargetSeconds: TimeInterval
    internal var adjustmentsEnabled: Bool
    internal var currentTargetPaceSecondsPerKm: Int?
    internal var originalTargetPaceSecondsPerKm: Int?
    internal var lastReason: PacingReason?
    internal var refractorySecondsRemaining: Int
    internal var refractoryState: PacingState?
    internal var hrCeilingExceededContinuousSeconds: TimeInterval
    internal var consecutiveFormBreakdowns: Int
    internal var lastEvaluationElapsedSeconds: TimeInterval
    internal var pendingBackOnTarget: Bool
    internal var paceDriftDeviation: PaceDeviation = .onTarget
    internal var paceDriftContinuousSeconds: Double = 0.0
    internal var paceDriftCooldownRemainingSeconds: Int = 0

    public init(
        profile: AthleteCalibrationProfile,
        intent: PacingSessionIntent,
        location: PacingLocation,
        configuration: AdaptivePacingConfiguration = .standard
    ) {
        self.profile = profile
        self.intent = intent
        self.location = location
        self.configuration = configuration

        self.kalmanHR = .standardHeartRate
        self.kalmanSpeed = .standardSpeed
        self.ringBuffer = TelemetryRingBuffer(capacity: TelemetryRingBuffer.defaultCapacity)
        self.efficiencyTracker = EfficiencyDriftTracker(location: location)
        self.bdiTracker = BiomechanicalDegradationIndex()

        self.state = .calibrating(progress: 0.0)
        self.calibrationTargetSeconds = configuration.warmupDurationSeconds + configuration.baselineDurationSeconds
        self.adjustmentsEnabled = true
        self.currentTargetPaceSecondsPerKm = intent.targetPaceSecondsPerKm
        self.originalTargetPaceSecondsPerKm = intent.targetPaceSecondsPerKm
        self.lastReason = nil
        self.refractorySecondsRemaining = 0
        self.refractoryState = nil
        self.hrCeilingExceededContinuousSeconds = 0.0
        self.consecutiveFormBreakdowns = 0
        self.lastEvaluationElapsedSeconds = 0.0
        self.pendingBackOnTarget = false
        self.paceDriftDeviation = .onTarget
        self.paceDriftContinuousSeconds = 0.0
        self.paceDriftCooldownRemainingSeconds = 0
    }

    /// Resets runtime state for a new session or calibration restart.
    public mutating func reset() {
        self.kalmanHR = .standardHeartRate
        self.kalmanSpeed = .standardSpeed
        self.ringBuffer = TelemetryRingBuffer(capacity: TelemetryRingBuffer.defaultCapacity)
        self.efficiencyTracker = EfficiencyDriftTracker(location: location)
        self.bdiTracker = BiomechanicalDegradationIndex()

        self.state = .calibrating(progress: 0.0)
        self.calibrationTargetSeconds = configuration.warmupDurationSeconds + configuration.baselineDurationSeconds
        self.adjustmentsEnabled = true
        self.currentTargetPaceSecondsPerKm = intent.targetPaceSecondsPerKm
        self.originalTargetPaceSecondsPerKm = intent.targetPaceSecondsPerKm
        self.lastReason = nil
        self.refractorySecondsRemaining = 0
        self.refractoryState = nil
        self.hrCeilingExceededContinuousSeconds = 0.0
        self.consecutiveFormBreakdowns = 0
        self.lastEvaluationElapsedSeconds = 0.0
        self.pendingBackOnTarget = false
        self.paceDriftDeviation = .onTarget
        self.paceDriftContinuousSeconds = 0.0
        self.paceDriftCooldownRemainingSeconds = 0
    }

    /// Ingests a 1 Hz telemetry tick and advances the closed-loop state machine.
    public mutating func ingest(_ tick: TelemetryTick) -> (events: [PacingEvent], display: PacingDisplayState) {
        // 1. Condition sensor inputs via Kalman filters
        let hrResult = kalmanHR.step(tick.heartRateBPM)
        let speedResult = kalmanSpeed.step(tick.speedMetersPerSecond)

        let conditioned = ConditionedTelemetryTick(
            elapsedSeconds: tick.elapsedSeconds,
            heartRateBPM: hrResult.estimate,
            isHeartRateValid: hrResult.isValid,
            speedMetersPerSecond: speedResult.estimate,
            isSpeedValid: speedResult.isValid,
            cadenceSPM: tick.effectiveCadenceSPM,
            powerWatts: tick.powerWatts,
            groundContactTimeMs: tick.groundContactTimeMs,
            verticalOscillationCm: tick.verticalOscillationCm,
            strideLengthMeters: tick.strideLengthMeters,
            gradeFraction: tick.gradeFraction
        )
        ringBuffer.append(conditioned)

        var emittedEvents: [PacingEvent] = []

        // 2. Decrement refractory period if active
        if refractorySecondsRemaining > 0 {
            refractorySecondsRemaining -= 1
            if refractorySecondsRemaining == 0 {
                state = .tracking
                refractoryState = nil
            }
        }

        // 3. Track continuous HR ceiling violations
        let ceilingBPM = configuration.hrCeilingFraction * profile.maxHR
        if let hr = hrResult.estimate, hr > ceilingBPM {
            hrCeilingExceededContinuousSeconds += 1.0
        } else {
            hrCeilingExceededContinuousSeconds = 0.0
        }

        // 4. State-specific processing
        switch state {
        case .calibrating:
            handleCalibration(tick: tick, speedEstimate: speedResult.estimate, emittedEvents: &emittedEvents)

        case .tracking, .surge, .recover:
            handleTracking(hrEstimate: hrResult.estimate, emittedEvents: &emittedEvents)
        }

        // 5. Build hollow display state
        let display = buildDisplayState(speedEstimate: speedResult.estimate, hrEstimate: hrResult.estimate)
        return (events: emittedEvents, display: display)
    }

    // MARK: - Calibration Logic

    private mutating func handleCalibration(
        tick: TelemetryTick,
        speedEstimate: Double?,
        emittedEvents: inout [PacingEvent]
    ) {
        if tick.elapsedSeconds >= calibrationTargetSeconds {
            let baselineStart = calibrationTargetSeconds - configuration.baselineDurationSeconds
            let baselineInterval = baselineStart...calibrationTargetSeconds

            let hrStats = ringBuffer.stats(
                for: .filteredHeartRate,
                in: baselineInterval,
                minCoverage: configuration.minCoverageFraction
            )
            let speedStats = ringBuffer.stats(
                for: .filteredSpeed,
                in: baselineInterval,
                minCoverage: configuration.minCoverageFraction
            )

            if let hrStats, let speedStats, hrStats.mean > 0, speedStats.mean > 0 {
                // Calibration succeeded: lock baselines
                _ = efficiencyTracker.lockBaseline(
                    from: ringBuffer,
                    in: baselineInterval,
                    minCoverage: configuration.minCoverageFraction
                )
                _ = bdiTracker.lockBaseline(
                    from: ringBuffer,
                    in: baselineInterval,
                    minCoverage: configuration.minCoverageFraction
                )

                let target: Int
                if let explicitTarget = intent.targetPaceSecondsPerKm {
                    target = explicitTarget
                } else {
                    target = Int((1000.0 / speedStats.mean).rounded())
                }

                originalTargetPaceSecondsPerKm = target
                currentTargetPaceSecondsPerKm = target
                adjustmentsEnabled = (intent.intent != .intervals)
                state = .tracking
                lastEvaluationElapsedSeconds = tick.elapsedSeconds

                emittedEvents.append(.calibrationComplete(
                    originalTargetSecondsPerKm: target,
                    adjustmentsEnabled: adjustmentsEnabled
                ))
            } else if calibrationTargetSeconds + configuration.calibrationExtensionStepSeconds <= configuration.maxCalibrationDurationSeconds {
                // Extend calibration by 60 s
                calibrationTargetSeconds += configuration.calibrationExtensionStepSeconds
                let progress = min(1.0, max(0.0, tick.elapsedSeconds / calibrationTargetSeconds))
                state = .calibrating(progress: progress)
            } else {
                // Persistent sensor failure at 900 s -> monitor-only tracking
                let target = intent.targetPaceSecondsPerKm ?? 300
                originalTargetPaceSecondsPerKm = target
                currentTargetPaceSecondsPerKm = target
                adjustmentsEnabled = false
                state = .tracking
                lastEvaluationElapsedSeconds = tick.elapsedSeconds

                emittedEvents.append(.calibrationComplete(
                    originalTargetSecondsPerKm: target,
                    adjustmentsEnabled: false
                ))
            }
        } else {
            let progress = min(1.0, max(0.0, tick.elapsedSeconds / calibrationTargetSeconds))
            state = .calibrating(progress: progress)
        }
    }

    // MARK: - Tracking Logic

    private mutating func handleTracking(
        hrEstimate: Double?,
        emittedEvents: inout [PacingEvent]
    ) {
        // Back-on-target check evaluated on every tick
        if let backEvent = evaluateBackOnTarget() {
            emittedEvents.append(backEvent)
        }

        // Real-time pace drift alert evaluated on every tick
        if let driftEvent = evaluatePaceDriftAlert() {
            emittedEvents.append(driftEvent)
        }

        // Periodic 10 s evaluation
        guard let latestTick = ringBuffer.latestTick else { return }
        if adjustmentsEnabled && (latestTick.elapsedSeconds - lastEvaluationElapsedSeconds >= configuration.evaluationIntervalSeconds) {
            lastEvaluationElapsedSeconds = latestTick.elapsedSeconds
            if let adjustmentEvent = evaluateAdjustmentTriggers(filteredHR: hrEstimate) {
                emittedEvents.append(adjustmentEvent)
            }
        }
    }

    // MARK: - Display State Builder

    private func buildDisplayState(speedEstimate: Double?, hrEstimate: Double?) -> PacingDisplayState {
        let filteredPace: Int? = {
            if let shortSpeed = ringBuffer.shortWindowStats(for: .filteredSpeed)?.mean, shortSpeed > 0 {
                return Int((1000.0 / shortSpeed).rounded())
            }
            if let current = speedEstimate, current > 0 {
                return Int((1000.0 / current).rounded())
            }
            return nil
        }()

        let filteredHR: Int? = hrEstimate.map { Int($0.rounded()) }
        let deviation = evaluateDeviation(target: currentTargetPaceSecondsPerKm, current: filteredPace)

        let calProgress: Double? = {
            if case .calibrating(let p) = state { return p }
            return nil
        }()

        let calProgressStr: String = {
            if let p = calProgress {
                return "\(Int((p * 100.0).rounded()))%"
            }
            return "--"
        }()

        let refractoryProg: Double = {
            guard configuration.refractoryDurationSeconds > 0 else { return 0.0 }
            return Double(refractorySecondsRemaining) / configuration.refractoryDurationSeconds
        }()

        return PacingDisplayState(
            state: state,
            targetPaceSecondsPerKm: currentTargetPaceSecondsPerKm,
            filteredPaceSecondsPerKm: filteredPace,
            filteredHeartRateBPM: filteredHR,
            deviation: deviation,
            refractorySecondsRemaining: refractorySecondsRemaining,
            lastReason: lastReason,
            adjustmentsEnabled: adjustmentsEnabled,
            targetPaceFormatted: formatPace(secondsPerKm: currentTargetPaceSecondsPerKm),
            filteredPaceFormatted: formatPace(secondsPerKm: filteredPace),
            filteredHeartRateFormatted: filteredHR.map { "\($0) BPM" } ?? "--",
            deviationTitle: deviationTitle(for: deviation),
            calibrationProgress: calProgress,
            calibrationProgressFormatted: calProgressStr,
            refractoryProgress: refractoryProg
        )
    }

    internal func evaluateDeviation(target: Int?, current: Int?) -> PaceDeviation {
        guard let target, let current else { return .unknown }
        let tolerance = max(configuration.backOnTargetMinToleranceSecondsPerKm, Int((Double(target) * configuration.backOnTargetToleranceFraction).rounded()))
        if current < target - tolerance {
            return .tooFast
        } else if current > target + tolerance {
            return .tooSlow
        } else {
            return .onTarget
        }
    }

    private func formatPace(secondsPerKm: Int?) -> String {
        guard let seconds = secondsPerKm, seconds > 0 else { return "--:--" }
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d /km", mins, secs)
    }

    private func deviationTitle(for deviation: PaceDeviation) -> String {
        switch deviation {
        case .onTarget: return "On Target"
        case .tooFast: return "Too Fast"
        case .tooSlow: return "Too Slow"
        case .unknown: return "--"
        }
    }
}
