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
    public var cadenceDriftDebounceDurationSeconds: TimeInterval
    public var cadenceDriftCooldownSeconds: TimeInterval
    public var cadenceDriftThresholdSPM: Double
    public var cadenceFloorSPM: Int

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
        paceDriftCooldownSeconds: TimeInterval = 30.0,
        cadenceDriftDebounceDurationSeconds: TimeInterval = 12.0,
        cadenceDriftCooldownSeconds: TimeInterval = 30.0,
        cadenceDriftThresholdSPM: Double = 6.0,
        cadenceFloorSPM: Int = 150
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
        self.cadenceDriftDebounceDurationSeconds = cadenceDriftDebounceDurationSeconds
        self.cadenceDriftCooldownSeconds = cadenceDriftCooldownSeconds
        self.cadenceDriftThresholdSPM = cadenceDriftThresholdSPM
        self.cadenceFloorSPM = cadenceFloorSPM
    }

    /// Standard production configuration with sports science parameters.
    public static let standard = AdaptivePacingConfiguration()

    /// Watch companion configuration tuned for zero-friction runs with 5-minute calibration lock-in.
    public static func forWatchCompanion(
        intent: WatchRunIntent,
        cadenceFloorSPM: Int? = nil
    ) -> AdaptivePacingConfiguration {
        var config = AdaptivePacingConfiguration(
            warmupDurationSeconds: 120.0,
            baselineDurationSeconds: 180.0,
            maxCalibrationDurationSeconds: 420.0,
            refractoryDurationSeconds: 90.0
        )
        if let cadenceFloorSPM, cadenceFloorSPM > 0 {
            config.cadenceFloorSPM = cadenceFloorSPM
        }
        switch intent {
        case .adaptiveBase:
            config.hrCeilingFraction = 0.92
            config.hrSurgeCeilingFraction = 0.82
            config.recoverEfficiencyDriftThreshold = -0.06
        case .pushPerformance:
            config.hrCeilingFraction = 0.95
            config.hrSurgeCeilingFraction = 0.88
            config.recoverEfficiencyDriftThreshold = -0.08
            config.surgeMagnitudeFraction = 0.04
        case .recovery:
            config.hrCeilingFraction = 0.78
            config.hrCeilingDurationSeconds = 20.0
            config.recoverEfficiencyDriftThreshold = -0.04
        }
        return config
    }
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
    case calibrationStarted
    case calibrationComplete(originalTargetSecondsPerKm: Int, adjustmentsEnabled: Bool)
    case surge(deltaSecondsPerKm: Int, newTargetSecondsPerKm: Int)
    case surgeLockedIn(targetPaceSecondsPerKm: Int)
    case recover(deltaSecondsPerKm: Int, newTargetSecondsPerKm: Int, reason: PacingReason)
    case formCheck(currentCadenceSPM: Int, targetCadenceSPM: Int?)
    case backOnTarget
    case paceDrift(deviation: PaceDeviation, deltaSecondsPerKm: Int)
    case cadenceDrift(currentCadenceSPM: Int, targetCadenceSPM: Int, deltaSPM: Int)
    case splitMilestone(splitIndex: Int, splitPaceSecondsPerKm: Int)
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
    public var currentState: PacingState { state }
    public var isCalibrating: Bool {
        if case .calibrating = state { return true }
        return false
    }
    internal var calibrationTargetSeconds: TimeInterval
    internal var adjustmentsEnabled: Bool
    internal var currentTargetPaceSecondsPerKm: Int?
    internal var originalTargetPaceSecondsPerKm: Int?
    public internal(set) var currentTargetCadenceSPM: Int?
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
    internal var cadenceDriftContinuousSeconds: Double = 0.0
    internal var cadenceDriftCooldownRemainingSeconds: Int = 0

    // Lifecycle & Surge Lock-in
    private var hasEmittedCalibrationStart: Bool = false
    public internal(set) var awaitingSurgeLockInTargetSecondsPerKm: Int?

    // Debrief Accumulators
    public internal(set) var surgeCount: Int = 0
    public internal(set) var peakSurgeDeltaSecondsPerKm: Int = 0
    public internal(set) var recoveryAdjustmentCount: Int = 0
    public internal(set) var firstDriftElapsedSeconds: TimeInterval?
    public internal(set) var cadenceBaselineSPM: Int?
    public internal(set) var solidCadenceUntilDistanceMeters: Double?
    public internal(set) var hasEstablishedSolidCadence: Bool = false
    internal var healthyCadenceContinuousSeconds: Double = 0.0
    public internal(set) var latestTotalDistanceMeters: Double?
    public internal(set) var totalPaceSumSecondsPerKm: Double = 0.0
    public internal(set) var paceSampleCount: Int = 0
    public internal(set) var totalHRSum: Double = 0.0
    public internal(set) var hrSampleCount: Int = 0
    public internal(set) var totalCadenceSum: Double = 0.0
    public internal(set) var cadenceSampleCount: Int = 0

    public init(
        profile: AthleteCalibrationProfile,
        intent: PacingSessionIntent,
        location: PacingLocation,
        configuration: AdaptivePacingConfiguration = .standard
    ) {
        self.profile = profile
        self.intent = intent
        self.location = location
        var resolvedConfig = configuration
        if let targetCadence = intent.targetCadenceSPM, targetCadence > 0, resolvedConfig.cadenceFloorSPM == 150 {
            resolvedConfig.cadenceFloorSPM = targetCadence
        }
        self.configuration = resolvedConfig

        self.kalmanHR = .standardHeartRate
        self.kalmanSpeed = .standardSpeed
        self.ringBuffer = TelemetryRingBuffer(capacity: TelemetryRingBuffer.defaultCapacity)
        self.efficiencyTracker = EfficiencyDriftTracker(location: location)
        self.bdiTracker = BiomechanicalDegradationIndex()

        self.state = .calibrating(progress: 0.0)
        self.calibrationTargetSeconds = resolvedConfig.warmupDurationSeconds + resolvedConfig.baselineDurationSeconds
        self.adjustmentsEnabled = true
        self.currentTargetPaceSecondsPerKm = intent.targetPaceSecondsPerKm
        self.originalTargetPaceSecondsPerKm = intent.targetPaceSecondsPerKm
        self.currentTargetCadenceSPM = intent.targetCadenceSPM
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
        self.cadenceDriftContinuousSeconds = 0.0
        self.cadenceDriftCooldownRemainingSeconds = 0

        self.hasEmittedCalibrationStart = false
        self.awaitingSurgeLockInTargetSecondsPerKm = nil
        self.surgeCount = 0
        self.peakSurgeDeltaSecondsPerKm = 0
        self.recoveryAdjustmentCount = 0
        self.firstDriftElapsedSeconds = nil
        self.cadenceBaselineSPM = nil
        self.solidCadenceUntilDistanceMeters = nil
        self.hasEstablishedSolidCadence = false
        self.healthyCadenceContinuousSeconds = 0.0
        self.latestTotalDistanceMeters = nil
        self.totalPaceSumSecondsPerKm = 0.0
        self.paceSampleCount = 0
        self.totalHRSum = 0.0
        self.hrSampleCount = 0
        self.totalCadenceSum = 0.0
        self.cadenceSampleCount = 0
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
        self.currentTargetCadenceSPM = intent.targetCadenceSPM
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
        self.cadenceDriftContinuousSeconds = 0.0
        self.cadenceDriftCooldownRemainingSeconds = 0

        self.hasEmittedCalibrationStart = false
        self.awaitingSurgeLockInTargetSecondsPerKm = nil
        self.surgeCount = 0
        self.peakSurgeDeltaSecondsPerKm = 0
        self.recoveryAdjustmentCount = 0
        self.firstDriftElapsedSeconds = nil
        self.cadenceBaselineSPM = nil
        self.solidCadenceUntilDistanceMeters = nil
        self.hasEstablishedSolidCadence = false
        self.healthyCadenceContinuousSeconds = 0.0
        self.latestTotalDistanceMeters = nil
        self.totalPaceSumSecondsPerKm = 0.0
        self.paceSampleCount = 0
        self.totalHRSum = 0.0
        self.hrSampleCount = 0
        self.totalCadenceSum = 0.0
        self.cadenceSampleCount = 0
    }

    /// Ingests a 1 Hz telemetry tick and advances the closed-loop state machine.
    public mutating func ingest(
        _ tick: TelemetryTick,
        totalDistanceMeters: Double? = nil
    ) -> (events: [PacingEvent], display: PacingDisplayState) {
        if let dist = totalDistanceMeters ?? tick.totalDistanceMeters {
            latestTotalDistanceMeters = dist
        }

        // 1. Condition sensor inputs via Kalman filters
        let hrResult = kalmanHR.step(tick.heartRateBPM)
        let speedResult = kalmanSpeed.step(tick.speedMetersPerSecond)

        // Rolling sums for average metrics
        if let speed = speedResult.estimate, speed > 0.5 {
            let pace = 1000.0 / speed
            totalPaceSumSecondsPerKm += pace
            paceSampleCount += 1
        }
        if let hr = hrResult.estimate, hr > 0 {
            totalHRSum += hr
            hrSampleCount += 1
        }
        if let cadence = tick.effectiveCadenceSPM, cadence >= 80 {
            totalCadenceSum += cadence
            cadenceSampleCount += 1
        }

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
        if !hasEmittedCalibrationStart {
            hasEmittedCalibrationStart = true
            emittedEvents.append(.calibrationStarted)
        }

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

                if let explicitCadence = intent.targetCadenceSPM {
                    currentTargetCadenceSPM = explicitCadence
                } else if let cadenceStats = ringBuffer.stats(
                    for: .cadence,
                    in: baselineInterval,
                    minCoverage: configuration.minCoverageFraction
                ), cadenceStats.mean > 0 {
                    currentTargetCadenceSPM = max(configuration.cadenceFloorSPM, Int(cadenceStats.mean.rounded()))
                }

                originalTargetPaceSecondsPerKm = target
                currentTargetPaceSecondsPerKm = target
                cadenceBaselineSPM = currentTargetCadenceSPM
                adjustmentsEnabled = (intent.intent != .intervals)
                state = .tracking
                hasEstablishedSolidCadence = false
                healthyCadenceContinuousSeconds = 0.0
                cadenceDriftContinuousSeconds = 0.0
                solidCadenceUntilDistanceMeters = nil
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

        // Surge lock-in check evaluated on every tick
        if let lockInEvent = evaluateSurgeLockIn() {
            emittedEvents.append(lockInEvent)
        }

        // Real-time pace drift alert evaluated on every tick
        if let driftEvent = evaluatePaceDriftAlert() {
            emittedEvents.append(driftEvent)
        }

        // Real-time cadence drift alert evaluated on every tick
        if let cadenceEvent = evaluateCadenceDriftAlert() {
            emittedEvents.append(cadenceEvent)
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

    // MARK: - Deviation Evaluation

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
}
