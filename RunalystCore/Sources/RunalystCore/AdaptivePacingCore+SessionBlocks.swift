import Foundation

// MARK: - Adaptive Block Types

/// Category of timed visual micro-block orchestrated on Apple Watch during an adaptive run.
public enum AdaptiveBlockKind: String, Sendable, Codable, Equatable {
    case none
    case cadenceReset
    case thresholdSurge
    case cooldownFloor
    case effortEase
}

/// Immutable snapshot of the currently active adaptive micro-block for hollow UI rendering.
public struct AdaptiveBlockState: Sendable, Codable, Equatable {
    public let kind: AdaptiveBlockKind
    public let remainingSeconds: Int
    public let blockTargetCadenceSPM: Int?
    public let blockTargetPaceSecondsPerKm: Int?
    public let displayBadgeText: String

    public static let none = AdaptiveBlockState(
        kind: .none,
        remainingSeconds: 0,
        blockTargetCadenceSPM: nil,
        blockTargetPaceSecondsPerKm: nil,
        displayBadgeText: ""
    )

    public init(
        kind: AdaptiveBlockKind,
        remainingSeconds: Int,
        blockTargetCadenceSPM: Int? = nil,
        blockTargetPaceSecondsPerKm: Int? = nil,
        displayBadgeText: String
    ) {
        self.kind = kind
        self.remainingSeconds = remainingSeconds
        self.blockTargetCadenceSPM = blockTargetCadenceSPM
        self.blockTargetPaceSecondsPerKm = blockTargetPaceSecondsPerKm
        self.displayBadgeText = displayBadgeText
    }

    /// Pre-formatted remaining countdown string (e.g. "2:45"), or `nil` when inactive.
    public var remainingFormatted: String? {
        guard kind != .none else { return nil }
        return AdaptivePacingCore.formatMinutesSeconds(remainingSeconds)
    }
}

/// Tracks physiological aborts, behavioral non-adoption dissolves, and per-run proposal caps.
public struct AdaptiveBlockBackoffTracker: Sendable, Equatable {
    public static let physiologicalAbortLockoutSeconds: TimeInterval = 480.0
    public static let behavioralNonAdoptionSeconds: TimeInterval = 60.0
    public static let initialProposalCooldownSeconds: TimeInterval = 300.0
    public static let doubledProposalCooldownSeconds: TimeInterval = 600.0
    public static let maxBackoffsPerRun: Int = 2

    public private(set) var backoffCount: Int = 0
    public private(set) var upwardLockoutRemainingSeconds: TimeInterval = 0.0
    public private(set) var currentProposalCooldownSeconds: TimeInterval = initialProposalCooldownSeconds

    public init() {}

    /// Whether the session has reached the maximum number of adaptive block backoffs.
    public var isUpwardBlocksExhausted: Bool {
        backoffCount >= Self.maxBackoffsPerRun
    }

    /// Whether a new upward adaptive block (`cadenceReset` or `thresholdSurge`) may be proposed.
    public var canProposeUpwardBlock: Bool {
        !isUpwardBlocksExhausted && upwardLockoutRemainingSeconds <= 0.0
    }

    /// Advances active lockout timers by 1 second.
    public mutating func tick() {
        if upwardLockoutRemainingSeconds > 0 {
            upwardLockoutRemainingSeconds = max(0.0, upwardLockoutRemainingSeconds - 1.0)
        }
    }

    /// Records a physiological mid-block abort (`480s` lockout and increments session backoff count).
    public mutating func recordPhysiologicalAbort() {
        backoffCount += 1
        upwardLockoutRemainingSeconds = max(
            upwardLockoutRemainingSeconds,
            Self.physiologicalAbortLockoutSeconds
        )
    }

    /// Records a 60s behavioral non-adoption dissolve (`300s -> 600s` doubled cooldown + backoff count).
    public mutating func recordBehavioralNonAdoption() {
        backoffCount += 1
        currentProposalCooldownSeconds = min(
            Self.doubledProposalCooldownSeconds,
            currentProposalCooldownSeconds * 2.0
        )
        upwardLockoutRemainingSeconds = max(
            upwardLockoutRemainingSeconds,
            currentProposalCooldownSeconds
        )
    }

    /// Sets a standard post-block cooldown without penalizing the session backoff cap.
    public mutating func setPostBlockCooldown(_ seconds: TimeInterval) {
        upwardLockoutRemainingSeconds = max(upwardLockoutRemainingSeconds, seconds)
    }
}

/// Internal runtime context for evaluating active micro-block engagement and badges.
internal struct AdaptiveBlockRuntimeContext: Sendable, Equatable {
    var openingCadenceSPM: Int?
    var badgeTitle: String?
    var baselineSpeedMPS: Double?
    var baselinePowerWatts: Double?
    var baselineHR: Double?
    var nonAdoptionSeconds: TimeInterval = 0.0
    var recoveryCeilingExceededSeconds: TimeInterval = 0.0
}

// MARK: - Session Block Orchestration

extension AdaptivePacingCore {
    internal static let cadenceResetDurationSeconds: Int = 180
    internal static let thresholdSurgeDurationSeconds: Int = 240
    internal static let cooldownFloorDurationSeconds: Int = 120
    internal static let effortEaseDurationSeconds: Int = 120
    internal static let postCadenceResetSettleSeconds: TimeInterval = 60.0
    internal static let postThresholdCooldownSeconds: TimeInterval = 300.0
    internal static let recoveryEffortCeilingFraction: Double = 0.78
    internal static let recoveryEffortCeilingDurationSeconds: TimeInterval = 20.0
    internal static let thresholdBlockHRCeilingFraction: Double = 0.88

    /// Pre-arms the short-burst tactile entrainer for an explicit Watch workout phase transition
    /// (e.g., `Cadence Pyramids` work rep or `Tempo Surges` cooldown floor), bypassing cooldowns.
    @discardableResult
    public mutating func preArmEntrainerForPhaseTransition(
        targetCadenceSPM: Int? = nil,
        cueMode: TactileCueMode = .cadenceMetronome
    ) -> ActiveTactileCue? {
        let currentCadence = resolvedCurrentCadenceSPM() ?? targetCadenceSPM ?? currentTargetCadenceSPM ?? configuration.cadenceFloorSPM
        switch cueMode {
        case .cadenceMetronome:
            let goal = targetCadenceSPM ?? currentTargetCadenceSPM ?? configuration.cadenceFloorSPM
            if let targetCadenceSPM {
                currentTargetCadenceSPM = targetCadenceSPM
            }
            return metronomeRamp.startCadenceBurst(
                currentSPM: currentCadence,
                goalSPM: goal,
                bypassCooldown: true
            )
        case .effortDown, .effortUp:
            return metronomeRamp.startEffortBurst(mode: cueMode, bypassCooldown: true)
        }
    }

    /// Evaluates initial adaptive block selection or drill pre-arming upon calibration completion.
    internal mutating func evaluateBlocksAtCalibrationComplete(
        observedCadenceSPM: Int?,
        hrEstimate: Double?,
        emittedEvents: inout [PacingEvent]
    ) {
        if intent.prescribedDrillTitle != nil {
            if let goal = currentTargetCadenceSPM ?? intent.targetCadenceSPM {
                let current = observedCadenceSPM ?? goal
                _ = metronomeRamp.startCadenceBurst(
                    currentSPM: current,
                    goalSPM: goal,
                    bypassCooldown: true
                )
            }
            return
        }

        guard adjustmentsEnabled,
              intent.intent != .recovery,
              !intent.subjectiveDistress,
              intent.intent != .intervals else {
            return
        }

        if let opened = tryOpenCadenceResetBlock(
            currentCadenceSPM: observedCadenceSPM,
            hrEstimate: hrEstimate
        ) {
            emittedEvents.append(.adaptiveBlockChanged(opened))
            return
        }

        let allowImmediateThreshold = (intent.readinessHint != nil) || (intent.intent == .tempo)
        if allowImmediateThreshold,
           let opened = tryOpenThresholdSurgeBlock(
            currentCadenceSPM: observedCadenceSPM,
            hrEstimate: hrEstimate
           ) {
            emittedEvents.append(.adaptiveBlockChanged(opened))
        }
    }

    /// Advances active session blocks, enforces physiological/behavioral backoffs, and proposes blocks.
    internal mutating func evaluateSessionBlocks(
        hrEstimate: Double?,
        currentCadenceSPM: Int?,
        emittedEvents: inout [PacingEvent]
    ) {
        blockBackoffTracker.tick()

        let currentCadence = currentCadenceSPM

        // 1. Protection Mandate for Recovery / Subjective Distress: never surge, guard 0.78 maxHR
        if intent.intent == .recovery || intent.subjectiveDistress {
            let recCeiling = Self.recoveryEffortCeilingFraction * profile.maxHR
            if let hr = hrEstimate, hr > recCeiling {
                blockRuntime.recoveryCeilingExceededSeconds += 1.0
            } else {
                blockRuntime.recoveryCeilingExceededSeconds = 0.0
            }

            if blockRuntime.recoveryCeilingExceededSeconds >= Self.recoveryEffortCeilingDurationSeconds,
               activeBlock.kind != .effortEase {
                let easeBlock = transitionToEffortEaseBlock(triggerEffortDownBurst: true)
                emittedEvents.append(.adaptiveBlockChanged(easeBlock))
            }
        } else {
            blockRuntime.recoveryCeilingExceededSeconds = 0.0
        }

        // 2. If a block is active, check aborts, non-adoption, or tick down remaining time
        if activeBlock.kind != .none {
            let didRecoverThisTick = emittedEvents.contains {
                if case .recover = $0 { return true }
                return false
            }

            if activeBlock.kind != .effortEase,
               shouldAbortBlockPhysiologically(
                hrEstimate: hrEstimate,
                didRecoverThisTick: didRecoverThisTick
               ) {
                blockBackoffTracker.recordPhysiologicalAbort()
                blockBackoffCount += 1
                let easeBlock = transitionToEffortEaseBlock(triggerEffortDownBurst: true)
                emittedEvents.append(.adaptiveBlockChanged(easeBlock))
                return
            }

            if shouldDissolveForBehavioralNonAdoption(
                currentCadenceSPM: currentCadence,
                hrEstimate: hrEstimate
            ) {
                blockBackoffTracker.recordBehavioralNonAdoption()
                blockBackoffCount += 1
                dissolveActiveBlockSilently(emittedEvents: &emittedEvents)
                return
            }

            advanceActiveBlockTimer(
                currentCadenceSPM: currentCadence,
                emittedEvents: &emittedEvents
            )
            return
        }

        // 3. No active block: if .recover fired this tick, enter .effortEase visual protection
        let didRecoverThisTick = emittedEvents.contains {
            if case .recover = $0 { return true }
            return false
        }
        if didRecoverThisTick {
            let easeBlock = transitionToEffortEaseBlock(triggerEffortDownBurst: true)
            emittedEvents.append(.adaptiveBlockChanged(easeBlock))
            return
        }

        // 4. Propose a new upward block if eligible and cooldown has elapsed
        guard adjustmentsEnabled,
              intent.prescribedDrillTitle == nil,
              intent.intent != .recovery,
              !intent.subjectiveDistress,
              intent.intent != .intervals,
              blockBackoffTracker.canProposeUpwardBlock else {
            return
        }

        if cadenceResetCount == 0,
           let opened = tryOpenCadenceResetBlock(
            currentCadenceSPM: currentCadence,
            hrEstimate: hrEstimate
           ) {
            emittedEvents.append(.adaptiveBlockChanged(opened))
            return
        }

        let elapsed = ringBuffer.latestTick?.elapsedSeconds ?? 0.0
        let canProposeUnpromptedSteady = (intent.readinessHint != nil)
            || (intent.intent == .tempo)
            || (cadenceResetCount > 0)
            || (elapsed >= calibrationTargetSeconds + AdaptiveBlockBackoffTracker.initialProposalCooldownSeconds)
        if canProposeUnpromptedSteady,
           let opened = tryOpenThresholdSurgeBlock(
            currentCadenceSPM: currentCadence,
            hrEstimate: hrEstimate
           ) {
            emittedEvents.append(.adaptiveBlockChanged(opened))
        }
    }

    // MARK: - Block Entry Helpers

    private mutating func tryOpenCadenceResetBlock(
        currentCadenceSPM: Int?,
        hrEstimate: Double?
    ) -> AdaptiveBlockState? {
        guard blockBackoffTracker.canProposeUpwardBlock,
              let currentCadence = currentCadenceSPM,
              currentCadence > 0 else {
            return nil
        }

        let floorSPM = max(
            configuration.cadenceFloorSPM,
            intent.readinessHint?.calibratedCadenceFloorSPM ?? configuration.cadenceFloorSPM
        )
        let hasStiffSignal = (intent.readinessHint?.daysSinceLastRun ?? 0) >= 2
            || (intent.readinessHint?.hadRecentCadenceFade == true)
        guard hasStiffSignal, currentCadence < floorSPM else {
            return nil
        }

        let hrLimit = 0.85 * profile.maxHR
        if let hr = hrEstimate, hr >= hrLimit {
            return nil
        }

        let targetSPM = min(max(currentCadence + 4, floorSPM), currentCadence + 6)
        let title = "CADENCE \(currentCadence)->\(targetSPM)"
        let remaining = Self.cadenceResetDurationSeconds

        blockRuntime.openingCadenceSPM = currentCadence
        blockRuntime.badgeTitle = title
        blockRuntime.baselineSpeedMPS = nil
        blockRuntime.baselinePowerWatts = nil
        blockRuntime.baselineHR = hrEstimate
        blockRuntime.nonAdoptionSeconds = 0.0

        let block = makeBlockState(
            kind: .cadenceReset,
            remainingSeconds: remaining,
            targetCadenceSPM: targetSPM,
            targetPaceSecondsPerKm: nil,
            badgeTitle: title
        )
        activeBlock = block
        cadenceResetCount += 1

        _ = metronomeRamp.startCadenceBurst(
            currentSPM: currentCadence,
            goalSPM: targetSPM,
            bypassCooldown: true
        )
        return block
    }

    private mutating func tryOpenThresholdSurgeBlock(
        currentCadenceSPM: Int?,
        hrEstimate: Double?
    ) -> AdaptiveBlockState? {
        guard blockBackoffTracker.canProposeUpwardBlock else { return nil }
        guard intent.intent == .steady || intent.intent == .tempo || intent.intent == .progression else {
            return nil
        }
        guard intent.readinessHint?.isClearedForQuality ?? true else {
            return nil
        }

        let needsPowerToHRCheck = (intent.readinessHint == nil && intent.intent != .tempo)
        if needsPowerToHRCheck {
            guard !profile.isFallback, profile.powerToHRTopQuartile != nil else {
                return nil
            }
        }

        let floorSPM = max(
            configuration.cadenceFloorSPM,
            intent.readinessHint?.calibratedCadenceFloorSPM ?? configuration.cadenceFloorSPM
        )
        if let currentCadence = currentCadenceSPM, currentCadence < floorSPM {
            return nil
        }

        guard let hr = hrEstimate, hr < configuration.hrSurgeCeilingFraction * profile.maxHR else {
            return nil
        }

        guard let efMeans = ringBuffer.longWindowEFMeans(includeSpeed: location == .outdoor) else {
            return nil
        }

        if needsPowerToHRCheck, let topQuartile = profile.powerToHRTopQuartile {
            guard efMeans.powerCoverage >= 0.80,
                  efMeans.hrCoverage >= 0.80,
                  let powerMean = efMeans.powerMean,
                  let hrMean = efMeans.hrMean,
                  hrMean > 0,
                  (powerMean / hrMean) >= topQuartile else {
                return nil
            }
        }

        let deltaEF = efficiencyTracker.deltaEF(
            from: ringBuffer,
            efMeans: efMeans,
            gradeGuardFraction: configuration.gradeGuardFraction,
            minCoverage: configuration.minCoverageFraction
        )
        if let deltaEF {
            guard deltaEF >= configuration.surgeEfficiencyDriftThreshold else {
                return nil
            }
        } else if location != .indoor {
            return nil
        }

        let basePace = currentTargetPaceSecondsPerKm ?? originalTargetPaceSecondsPerKm
        let blockTargetPace: Int? = basePace.map { pace in
            let delta = min(
                configuration.stepLimitSecondsPerKm,
                max(5, Int((Double(pace) * 0.04).rounded()))
            )
            return max(120, pace - delta)
        }
        let title = blockTargetPace.map { "THRESHOLD \(formatCompactPace($0))" } ?? "THRESHOLD BLOCK"
        let remaining = Self.thresholdSurgeDurationSeconds

        blockRuntime.openingCadenceSPM = currentCadenceSPM
        blockRuntime.badgeTitle = title
        blockRuntime.baselineSpeedMPS = ringBuffer.shortWindowStats(for: .filteredSpeed)?.mean
            ?? ringBuffer.latestTick?.speedMetersPerSecond
        blockRuntime.baselinePowerWatts = ringBuffer.shortWindowStats(for: .power)?.mean
            ?? ringBuffer.latestTick?.powerWatts
        blockRuntime.baselineHR = hr
        blockRuntime.nonAdoptionSeconds = 0.0

        let block = makeBlockState(
            kind: .thresholdSurge,
            remainingSeconds: remaining,
            targetCadenceSPM: currentTargetCadenceSPM,
            targetPaceSecondsPerKm: blockTargetPace,
            badgeTitle: title
        )
        activeBlock = block
        thresholdBlockCount += 1

        _ = metronomeRamp.startEffortBurst(mode: .effortUp, bypassCooldown: true)
        return block
    }

    private mutating func transitionToCooldownFloorBlock(currentCadenceSPM: Int?) -> AdaptiveBlockState {
        let floorSPM = max(
            configuration.cadenceFloorSPM,
            currentTargetCadenceSPM ?? intent.readinessHint?.calibratedCadenceFloorSPM ?? configuration.cadenceFloorSPM
        )
        let title = "COOLDOWN \(floorSPM) SPM"
        let remaining = Self.cooldownFloorDurationSeconds

        blockRuntime.openingCadenceSPM = currentCadenceSPM
        blockRuntime.badgeTitle = title
        blockRuntime.baselineSpeedMPS = nil
        blockRuntime.baselinePowerWatts = nil
        blockRuntime.baselineHR = nil
        blockRuntime.nonAdoptionSeconds = 0.0

        let block = makeBlockState(
            kind: .cooldownFloor,
            remainingSeconds: remaining,
            targetCadenceSPM: floorSPM,
            targetPaceSecondsPerKm: originalTargetPaceSecondsPerKm ?? currentTargetPaceSecondsPerKm,
            badgeTitle: title
        )
        activeBlock = block

        let currentSPM = currentCadenceSPM ?? floorSPM
        _ = metronomeRamp.startCadenceBurst(
            currentSPM: currentSPM,
            goalSPM: floorSPM,
            bypassCooldown: true
        )
        return block
    }

    private mutating func transitionToEffortEaseBlock(triggerEffortDownBurst: Bool) -> AdaptiveBlockState {
        let title = "EASE EFFORT"
        let remaining = Self.effortEaseDurationSeconds

        blockRuntime.openingCadenceSPM = nil
        blockRuntime.badgeTitle = title
        blockRuntime.baselineSpeedMPS = nil
        blockRuntime.baselinePowerWatts = nil
        blockRuntime.baselineHR = nil
        blockRuntime.nonAdoptionSeconds = 0.0

        let block = makeBlockState(
            kind: .effortEase,
            remainingSeconds: remaining,
            targetCadenceSPM: nil,
            targetPaceSecondsPerKm: currentTargetPaceSecondsPerKm,
            badgeTitle: title
        )
        activeBlock = block
        effortEaseCount += 1

        if triggerEffortDownBurst {
            _ = metronomeRamp.startEffortBurst(mode: .effortDown, bypassCooldown: true)
        }
        return block
    }

    // MARK: - Mid-Block Aborts, Non-Adoption & Progression

    private func shouldAbortBlockPhysiologically(
        hrEstimate: Double?,
        didRecoverThisTick: Bool
    ) -> Bool {
        let blockHRCeiling: Double = {
            if activeBlock.kind == .thresholdSurge {
                return min(Self.thresholdBlockHRCeilingFraction, configuration.hrCeilingFraction) * profile.maxHR
            }
            return configuration.hrCeilingFraction * profile.maxHR
        }()
        let hrBreached = hrEstimate.map { $0 > blockHRCeiling } ?? false

        let deltaEF = efficiencyTracker.deltaEF(
            from: ringBuffer,
            gradeGuardFraction: configuration.gradeGuardFraction,
            minCoverage: configuration.minCoverageFraction
        )
        let efBreached = deltaEF.map { $0 <= configuration.recoverEfficiencyDriftThreshold } ?? false
        let formBreached = (consecutiveFormBreakdowns >= 2) || didRecoverThisTick

        return hrBreached || efBreached || formBreached
    }

    private mutating func shouldDissolveForBehavioralNonAdoption(
        currentCadenceSPM: Int?,
        hrEstimate: Double?
    ) -> Bool {
        guard activeBlock.kind == .cadenceReset || activeBlock.kind == .thresholdSurge else {
            return false
        }

        let isEngaged: Bool
        switch activeBlock.kind {
        case .cadenceReset:
            if let current = currentCadenceSPM,
               let target = activeBlock.blockTargetCadenceSPM {
                let opening = blockRuntime.openingCadenceSPM ?? current
                isEngaged = (current >= target - 2) || (current - opening >= 2)
            } else {
                isEngaged = true
            }

        case .thresholdSurge:
            let speed = ringBuffer.latestTick?.speedMetersPerSecond
            let speedEngaged: Bool = {
                guard let speed, let baseSpeed = blockRuntime.baselineSpeedMPS, baseSpeed > 0 else {
                    return false
                }
                return speed >= baseSpeed * 1.015
            }()
            let powerEngaged: Bool = {
                guard let power = ringBuffer.latestTick?.powerWatts,
                      let basePower = blockRuntime.baselinePowerWatts,
                      basePower > 0 else {
                    return false
                }
                return power >= basePower * 1.03
            }()
            let hrEngaged: Bool = {
                guard let hr = hrEstimate, let baseHR = blockRuntime.baselineHR else {
                    return false
                }
                return hr >= baseHR + 4.0
            }()
            isEngaged = speedEngaged || powerEngaged || hrEngaged

        case .cooldownFloor, .effortEase, .none:
            isEngaged = true
        }

        if isEngaged {
            blockRuntime.nonAdoptionSeconds = 0.0
            return false
        }

        blockRuntime.nonAdoptionSeconds += 1.0
        return blockRuntime.nonAdoptionSeconds >= AdaptiveBlockBackoffTracker.behavioralNonAdoptionSeconds
    }

    private mutating func dissolveActiveBlockSilently(emittedEvents: inout [PacingEvent]) {
        activeBlock = .none
        blockRuntime.openingCadenceSPM = nil
        blockRuntime.badgeTitle = nil
        blockRuntime.baselineSpeedMPS = nil
        blockRuntime.baselinePowerWatts = nil
        blockRuntime.baselineHR = nil
        blockRuntime.nonAdoptionSeconds = 0.0
        metronomeRamp.silenceBurst(startCooldown: true)
        emittedEvents.append(.adaptiveBlockChanged(.none))
    }

    private mutating func advanceActiveBlockTimer(
        currentCadenceSPM: Int?,
        emittedEvents: inout [PacingEvent]
    ) {
        let nextRemaining = activeBlock.remainingSeconds - 1
        if nextRemaining > 0 {
            let title = blockRuntime.badgeTitle ?? defaultBadgeTitle(for: activeBlock.kind)
            activeBlock = makeBlockState(
                kind: activeBlock.kind,
                remainingSeconds: nextRemaining,
                targetCadenceSPM: activeBlock.blockTargetCadenceSPM,
                targetPaceSecondsPerKm: activeBlock.blockTargetPaceSecondsPerKm,
                badgeTitle: title
            )
            return
        }

        let completedKind = activeBlock.kind
        switch completedKind {
        case .thresholdSurge:
            let cooldownBlock = transitionToCooldownFloorBlock(currentCadenceSPM: currentCadenceSPM)
            emittedEvents.append(.adaptiveBlockChanged(cooldownBlock))
        case .cadenceReset:
            activeBlock = .none
            blockRuntime.badgeTitle = nil
            blockRuntime.nonAdoptionSeconds = 0.0
            blockBackoffTracker.setPostBlockCooldown(Self.postCadenceResetSettleSeconds)
            emittedEvents.append(.adaptiveBlockChanged(.none))
        case .cooldownFloor:
            activeBlock = .none
            blockRuntime.badgeTitle = nil
            blockRuntime.nonAdoptionSeconds = 0.0
            blockBackoffTracker.setPostBlockCooldown(Self.postThresholdCooldownSeconds)
            emittedEvents.append(.adaptiveBlockChanged(.none))
        case .effortEase, .none:
            activeBlock = .none
            blockRuntime.badgeTitle = nil
            blockRuntime.nonAdoptionSeconds = 0.0
            emittedEvents.append(.adaptiveBlockChanged(.none))
        }
    }

    // MARK: - Formatting & Sensor Helpers

    internal func resolvedCurrentCadenceSPM() -> Int? {
        if let shortCadence = ringBuffer.shortWindowStats(for: .cadence), shortCadence.mean > 0 {
            return Int(shortCadence.mean.rounded())
        }
        if let latestCadence = ringBuffer.latestTick?.cadenceSPM, latestCadence > 0 {
            return Int(latestCadence.rounded())
        }
        return nil
    }

    internal var activeBlockBadgeTitle: String? {
        guard activeBlock.kind != .none else { return nil }
        return blockRuntime.badgeTitle ?? defaultBadgeTitle(for: activeBlock.kind)
    }

    private func makeBlockState(
        kind: AdaptiveBlockKind,
        remainingSeconds: Int,
        targetCadenceSPM: Int?,
        targetPaceSecondsPerKm: Int?,
        badgeTitle: String
    ) -> AdaptiveBlockState {
        let clamped = max(0, remainingSeconds)
        let countdown = AdaptivePacingCore.formatMinutesSeconds(clamped)
        return AdaptiveBlockState(
            kind: kind,
            remainingSeconds: clamped,
            blockTargetCadenceSPM: targetCadenceSPM,
            blockTargetPaceSecondsPerKm: targetPaceSecondsPerKm,
            displayBadgeText: "\(badgeTitle) • \(countdown)"
        )
    }

    private func defaultBadgeTitle(for kind: AdaptiveBlockKind) -> String {
        switch kind {
        case .none:
            return ""
        case .cadenceReset:
            return "CADENCE RESET"
        case .thresholdSurge:
            return "THRESHOLD"
        case .cooldownFloor:
            return "COOLDOWN FLOOR"
        case .effortEase:
            return "EASE EFFORT"
        }
    }

    private func formatCompactPace(_ secondsPerKm: Int) -> String {
        AdaptivePacingCore.formatMinutesSeconds(secondsPerKm)
    }
}
