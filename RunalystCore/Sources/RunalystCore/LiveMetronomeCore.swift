import Foundation

/// Distinct haptic cue modes so cadence entrainment never conflates with pace/effort regulation.
public enum TactileCueMode: String, Sendable, Codable, Equatable {
    case cadenceMetronome
    case effortDown
    case effortUp
}

/// Active tactile cue snapshot emitted by `SteppedMetronomeRamp` for Watch haptic playback and display.
public struct ActiveTactileCue: Sendable, Codable, Equatable {
    public let mode: TactileCueMode
    public let targetBPM: Int?
    public let pulseIntervalSeconds: TimeInterval?
    public let remainingSeconds: Int
    public let stepLabel: String?

    public init(
        mode: TactileCueMode,
        targetBPM: Int?,
        pulseIntervalSeconds: TimeInterval?,
        remainingSeconds: Int,
        stepLabel: String?
    ) {
        self.mode = mode
        self.targetBPM = targetBPM
        self.pulseIntervalSeconds = pulseIntervalSeconds
        self.remainingSeconds = remainingSeconds
        self.stepLabel = stepLabel
    }
}

/// Pure deterministic state machine for short-burst, stepped cadence entrainment and effort pulses.
public struct SteppedMetronomeRamp: Sendable, Equatable {
    public static let stepIncrementSPM: Int = 3
    public static let stepHoldSeconds: TimeInterval = 10.0
    public static let lockToleranceSPM: Int = 2
    public static let burstMaxDurationSeconds: TimeInterval = 20.0
    public static let earlyLockExitSeconds: TimeInterval = 5.0
    public static let checkpointCooldownSeconds: TimeInterval = 240.0
    public static let effortPulseIntervalSeconds: TimeInterval = 3.5

    public private(set) var activeCue: ActiveTactileCue?
    public private(set) var steppedTargetSPM: Int?
    public private(set) var goalTargetSPM: Int?
    public private(set) var cooldownRemainingSeconds: TimeInterval
    public private(set) var burstElapsedSeconds: TimeInterval
    public private(set) var lockedSeconds: TimeInterval
    public private(set) var stepHeldSeconds: TimeInterval

    public init() {
        self.activeCue = nil
        self.steppedTargetSPM = nil
        self.goalTargetSPM = nil
        self.cooldownRemainingSeconds = 0
        self.burstElapsedSeconds = 0
        self.lockedSeconds = 0
        self.stepHeldSeconds = 0
    }

    /// Starts a short-burst stepped cadence metronome cue, never lowering BPM below current cadence.
    @discardableResult
    public mutating func startCadenceBurst(
        currentSPM: Int,
        goalSPM: Int,
        bypassCooldown: Bool = false
    ) -> ActiveTactileCue? {
        guard goalSPM > 0 else { return nil }
        guard bypassCooldown || cooldownRemainingSeconds <= 0 else { return nil }
        if !bypassCooldown,
           let existing = activeCue,
           existing.mode == .cadenceMetronome,
           goalTargetSPM == goalSPM {
            return existing
        }

        let initialStepSPM: Int
        if currentSPM < goalSPM - Self.lockToleranceSPM {
            initialStepSPM = min(goalSPM, currentSPM + Self.stepIncrementSPM)
        } else {
            initialStepSPM = max(currentSPM, goalSPM)
        }

        let effectiveGoalSPM = max(goalSPM, initialStepSPM)
        steppedTargetSPM = initialStepSPM
        goalTargetSPM = effectiveGoalSPM
        cooldownRemainingSeconds = 0
        burstElapsedSeconds = 0
        lockedSeconds = 0
        stepHeldSeconds = 0

        let cue = makeCadenceCue(
            steppedSPM: initialStepSPM,
            goalSPM: effectiveGoalSPM,
            remainingSeconds: Int(Self.burstMaxDurationSeconds)
        )
        activeCue = cue
        return cue
    }

    /// Starts a spaced double-pulse effort cue (`.effortDown` or `.effortUp`) without altering metronome BPM.
    @discardableResult
    public mutating func startEffortBurst(
        mode: TactileCueMode,
        bypassCooldown: Bool = false
    ) -> ActiveTactileCue? {
        guard mode == .effortDown || mode == .effortUp else { return nil }
        guard bypassCooldown || cooldownRemainingSeconds <= 0 else { return nil }
        if !bypassCooldown,
           let existing = activeCue,
           existing.mode == mode {
            return existing
        }

        steppedTargetSPM = nil
        goalTargetSPM = nil
        cooldownRemainingSeconds = 0
        burstElapsedSeconds = 0
        lockedSeconds = 0
        stepHeldSeconds = 0

        let cue = ActiveTactileCue(
            mode: mode,
            targetBPM: nil,
            pulseIntervalSeconds: Self.effortPulseIntervalSeconds,
            remainingSeconds: Int(Self.burstMaxDurationSeconds),
            stepLabel: Self.effortStepLabel(for: mode)
        )
        activeCue = cue
        return cue
    }

    /// Advances the entrainer state machine by 1 second and returns the updated cue (or `nil` when silent).
    @discardableResult
    public mutating func tick(currentSPM: Int?, isEffortOnTarget: Bool) -> ActiveTactileCue? {
        if cooldownRemainingSeconds > 0 {
            cooldownRemainingSeconds = max(0, cooldownRemainingSeconds - 1.0)
        }

        guard let cue = activeCue else {
            return nil
        }

        burstElapsedSeconds += 1.0

        switch cue.mode {
        case .cadenceMetronome:
            let goal = goalTargetSPM ?? cue.targetBPM ?? 0
            let stepped = steppedTargetSPM ?? goal

            if let spm = currentSPM {
                if abs(spm - goal) <= Self.lockToleranceSPM {
                    lockedSeconds += 1.0
                } else {
                    lockedSeconds = 0
                }

                if lockedSeconds >= Self.earlyLockExitSeconds {
                    endBurstAndStartCooldown()
                    return nil
                }

                if stepped < goal {
                    if abs(spm - stepped) <= Self.lockToleranceSPM {
                        stepHeldSeconds += 1.0
                        if stepHeldSeconds >= Self.stepHoldSeconds {
                            steppedTargetSPM = min(goal, stepped + Self.stepIncrementSPM)
                            stepHeldSeconds = 0
                        }
                    } else {
                        stepHeldSeconds = 0
                    }
                }
            } else {
                lockedSeconds = 0
                stepHeldSeconds = 0
            }

        case .effortDown, .effortUp:
            if isEffortOnTarget {
                lockedSeconds += 1.0
            } else {
                lockedSeconds = 0
            }

            if lockedSeconds >= Self.earlyLockExitSeconds {
                endBurstAndStartCooldown()
                return nil
            }
        }

        if burstElapsedSeconds >= Self.burstMaxDurationSeconds {
            endBurstAndStartCooldown()
            return nil
        }

        let remaining = max(0, Int((Self.burstMaxDurationSeconds - burstElapsedSeconds).rounded()))
        let updatedCue: ActiveTactileCue
        switch cue.mode {
        case .cadenceMetronome:
            let currentStep = steppedTargetSPM ?? cue.targetBPM ?? 0
            let goal = goalTargetSPM ?? currentStep
            updatedCue = makeCadenceCue(
                steppedSPM: currentStep,
                goalSPM: goal,
                remainingSeconds: remaining
            )
        case .effortDown, .effortUp:
            updatedCue = ActiveTactileCue(
                mode: cue.mode,
                targetBPM: nil,
                pulseIntervalSeconds: Self.effortPulseIntervalSeconds,
                remainingSeconds: remaining,
                stepLabel: Self.effortStepLabel(for: cue.mode)
            )
        }

        activeCue = updatedCue
        return updatedCue
    }

    /// Immediately silences any active tactile cue (e.g., on workout pause or end).
    public mutating func silenceBurst(startCooldown: Bool = false) {
        activeCue = nil
        steppedTargetSPM = nil
        goalTargetSPM = nil
        burstElapsedSeconds = 0
        lockedSeconds = 0
        stepHeldSeconds = 0
        if startCooldown {
            cooldownRemainingSeconds = Self.checkpointCooldownSeconds
        }
    }

    private mutating func endBurstAndStartCooldown() {
        silenceBurst(startCooldown: true)
    }

    private func makeCadenceCue(
        steppedSPM: Int,
        goalSPM: Int,
        remainingSeconds: Int
    ) -> ActiveTactileCue {
        let label = steppedSPM < goalSPM
            ? "\(steppedSPM) -> \(goalSPM) SPM"
            : "\(steppedSPM) SPM"
        return ActiveTactileCue(
            mode: .cadenceMetronome,
            targetBPM: steppedSPM,
            pulseIntervalSeconds: LiveMetronomeCore.beatIntervalSeconds(forTargetSPM: steppedSPM),
            remainingSeconds: remainingSeconds,
            stepLabel: label
        )
    }

    private static func effortStepLabel(for mode: TactileCueMode) -> String {
        switch mode {
        case .effortDown:
            return "Ease Effort"
        case .effortUp:
            return "Lift Effort"
        case .cadenceMetronome:
            return "Cadence"
        }
    }
}

/// Pure sports science model representing a parsed interval prescription.
public struct ParsedIntervalPrescription: Sendable, Equatable {
    public let iterations: Int
    public let distanceMeters: Double
    public let cadenceLowerBound: Double
    public let cadenceUpperBound: Double

    public var cadenceRange: ClosedRange<Double> {
        cadenceLowerBound...cadenceUpperBound
    }

    public init(
        iterations: Int,
        distanceMeters: Double,
        cadenceLowerBound: Double,
        cadenceUpperBound: Double
    ) {
        self.iterations = iterations
        self.distanceMeters = distanceMeters
        self.cadenceLowerBound = cadenceLowerBound
        self.cadenceUpperBound = cadenceUpperBound
    }
}

/// Pure domain calculations for live metronome pacing and duty-cycled haptics.
public enum LiveMetronomeCore {

    /// Initial lock-in window where metronome pulses continuously to entrain rhythm.
    public static let initialLockInWindowSeconds: TimeInterval = 20.0

    /// Tolerance in SPM below target cadence before duty-cycled haptic cues fire.
    public static let dutyCycledDriftToleranceSPM: Int = 2

    /// Half-width in SPM around the target cadence to establish the alert band (+/- 5 SPM).
    public static let cadenceBandHalfWidthSPM: Int = 5

    /// Parses an AI drill prescription string (e.g. "4x400m intervals") into interval components
    /// and calculates the cadence alert boundaries around target SPM.
    public static func parsePrescription(_ prescription: String, targetSPM: Int) -> ParsedIntervalPrescription? {
        let pattern = #"(\d+)x(\d+)m"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(
                in: prescription,
                options: [],
                range: NSRange(location: 0, length: prescription.utf16.count)
              ),
              let iterRange = Range(match.range(at: 1), in: prescription),
              let distRange = Range(match.range(at: 2), in: prescription),
              let iterations = Int(prescription[iterRange]),
              let distance = Double(prescription[distRange]),
              iterations > 0,
              distance > 0 else {
            return nil
        }

        let lowerBound = Double(max(0, targetSPM - cadenceBandHalfWidthSPM))
        let upperBound = Double(max(Int(lowerBound), targetSPM + cadenceBandHalfWidthSPM))

        return ParsedIntervalPrescription(
            iterations: iterations,
            distanceMeters: distance,
            cadenceLowerBound: lowerBound,
            cadenceUpperBound: upperBound
        )
    }

    /// Deterministically extracts target cadence midpoint in SPM from AI drill prescription or target strings
    /// (e.g. "153-159 SPM", "160–166 SPM (Adapted)", "170 SPM").
    ///
    /// Extracts all integers in the valid running cadence range 100...240 SPM.
    /// Returns nil if empty or no valid cadence integers are found,
    /// the single cadence if 1 integer is found,
    /// or the integer midpoint `(first + last) / 2` if multiple integers are found.
    public static func midpointSPM(fromTargetString target: String?) -> Int? {
        guard let target = target?.trimmingCharacters(in: .whitespacesAndNewlines),
              !target.isEmpty else {
            return nil
        }

        let pattern = #"\d+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(location: 0, length: target.utf16.count)
        let matches = regex.matches(in: target, options: [], range: range)

        var validCadences: [Int] = []
        for match in matches {
            guard let matchRange = Range(match.range, in: target),
                  let value = Int(target[matchRange]),
                  (100...240).contains(value) else {
                continue
            }
            validCadences.append(value)
        }

        guard !validCadences.isEmpty else {
            return nil
        }

        if validCadences.count == 1 {
            return validCadences[0]
        }

        guard let first = validCadences.first, let last = validCadences.last else {
            return nil
        }

        return (first + last) / 2
    }

    /// Calculates the beat interval in seconds corresponding to a target SPM.
    /// Returns nil if targetSPM is non-positive.
    public static func beatIntervalSeconds(forTargetSPM targetSPM: Int) -> TimeInterval? {
        guard targetSPM > 0 else { return nil }
        return 60.0 / Double(targetSPM)
    }

    /// Determines if a corrective haptic cue should trigger based on falling below target cadence.
    public static func shouldTriggerCorrectiveHaptic(currentSPM: Int, targetSPM: Int) -> Bool {
        currentSPM < targetSPM
    }

    /// Evaluates if haptic feedback should be delivered according to duty-cycling rules.
    /// Fires during the initial lock-in window or when cadence drifts below tolerance.
    public static func shouldTriggerDutyCycledHaptic(
        isEnabled: Bool,
        currentSPM: Int,
        targetSPM: Int,
        intervalElapsedSeconds: TimeInterval
    ) -> Bool {
        guard isEnabled else { return false }
        return intervalElapsedSeconds <= initialLockInWindowSeconds
            || currentSPM < (targetSPM - dutyCycledDriftToleranceSPM)
    }

    /// Alias for `shouldTriggerDutyCycledHaptic` conforming to the haptic trigger protocol.
    public static func shouldTriggerHaptic(
        isEnabled: Bool,
        currentSPM: Int,
        targetSPM: Int,
        intervalElapsedSeconds: TimeInterval
    ) -> Bool {
        shouldTriggerDutyCycledHaptic(
            isEnabled: isEnabled,
            currentSPM: currentSPM,
            targetSPM: targetSPM,
            intervalElapsedSeconds: intervalElapsedSeconds
        )
    }
}
