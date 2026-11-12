import Foundation

// MARK: - Presentation Tokens & Feedback Specifications

/// Subconscious UI accent tokens bound to the causal pacing metric.
public enum PacingAccentToken: String, Sendable, Codable, CaseIterable, Equatable {
    /// Pace metric accent (Electric Blue).
    case electricBlue
    /// Surge / pace speedup accent.
    case surgeBlue
    /// Heart rate metric accent (Neon Pink).
    case neonPink
    /// Cadence & biomechanics metric accent (Vibrant Green).
    case vibrantGreen
    /// Recover / warning accent (Recover Orange).
    case recoverOrange
    /// Neutral / baseline accent.
    case neutral
    /// Zero-friction watch companion calibration edge aura.
    case calibratingBlue
    /// High-efficiency surge edge glow.
    case surgeTeal
    /// Cardiac drift / recovery protection edge glow.
    case recoverAmber
}

/// Abstract haptic semantic categories mapped to watchOS haptic playback.
public enum PacingHapticSemantic: String, Sendable, Codable, CaseIterable, Equatable {
    case directionUp
    case directionDown
    case retry
    case success
    case none
    case ascendingDoublePulse
    case threeQuickLightTaps
    case descendingDoublePulse
    case subtleConfirmation
}

/// Backward-compatible alias for deterministic pacing event feedback specification.
public typealias PacingFeedbackSpec = PacingEventFeedbackSpec

/// Deterministic multimodal feedback specification for a pacing event.
public struct PacingEventFeedbackSpec: Sendable, Equatable {
    public let haptic: PacingHapticSemantic
    public let voiceCueText: String?
    public let accentToken: PacingAccentToken

    public init(
        haptic: PacingHapticSemantic,
        voiceCueText: String?,
        accentToken: PacingAccentToken
    ) {
        self.haptic = haptic
        self.voiceCueText = voiceCueText
        self.accentToken = accentToken
    }

    public init(for event: PacingEvent, useMetricSystem: Bool = true) {
        switch event {
        case .calibrationStarted:
            self.init(
                haptic: .none,
                voiceCueText: "Find a comfortable rhythm. Reading your baseline.",
                accentToken: .calibratingBlue
            )
        case .calibrationComplete(let target, _):
            let paceStr: String
            let unitName: String
            if useMetricSystem {
                let mins = target / 60
                let secs = target % 60
                paceStr = String(format: "%d:%02d", mins, secs)
                unitName = "kilometer"
            } else {
                let targetMile = Int((Double(target) * 1.609344).rounded())
                let mins = targetMile / 60
                let secs = targetMile % 60
                paceStr = String(format: "%d:%02d", mins, secs)
                unitName = "mile"
            }
            self.init(
                haptic: .success,
                voiceCueText: "Baseline locked. Target pace: \(paceStr) per \(unitName). Let's roll.",
                accentToken: .electricBlue
            )
        case .surge(_, let newTarget):
            let paceStr: String
            if useMetricSystem {
                let mins = newTarget / 60
                let secs = newTarget % 60
                paceStr = String(format: "%d:%02d", mins, secs)
            } else {
                let targetMile = Int((Double(newTarget) * 1.609344).rounded())
                let mins = targetMile / 60
                let secs = targetMile % 60
                paceStr = String(format: "%d:%02d", mins, secs)
            }
            self.init(
                haptic: .ascendingDoublePulse,
                voiceCueText: "Efficiency is high—you've got reserves. Nudging target pace to \(paceStr).",
                accentToken: .surgeTeal
            )
        case .surgeLockedIn:
            self.init(
                haptic: .subtleConfirmation,
                voiceCueText: nil,
                accentToken: .surgeTeal
            )
        case .formCheck:
            self.init(
                haptic: .threeQuickLightTaps,
                voiceCueText: "Form check. Quick, light steps—bring your cadence up.",
                accentToken: .recoverAmber
            )
        case .recover(_, let newTarget, _):
            let paceStr: String
            if useMetricSystem {
                let mins = newTarget / 60
                let secs = newTarget % 60
                paceStr = String(format: "%d:%02d", mins, secs)
            } else {
                let targetMile = Int((Double(newTarget) * 1.609344).rounded())
                let mins = targetMile / 60
                let secs = targetMile % 60
                paceStr = String(format: "%d:%02d", mins, secs)
            }
            self.init(
                haptic: .descendingDoublePulse,
                voiceCueText: "Cardiac drift detected. Dialing target back to \(paceStr) to protect your aerobic zone.",
                accentToken: .recoverAmber
            )
        case .backOnTarget:
            self.init(
                haptic: .success,
                voiceCueText: nil,
                accentToken: .neutral
            )
        case .paceDrift(let deviation, _):
            switch deviation {
            case .tooSlow:
                self.init(
                    haptic: .directionUp,
                    voiceCueText: "Pace dropping. Pick up rhythm.",
                    accentToken: .surgeBlue
                )
            case .tooFast:
                self.init(
                    haptic: .directionDown,
                    voiceCueText: "Pace high. Ease into rhythm.",
                    accentToken: .recoverOrange
                )
            case .onTarget, .unknown:
                self.init(
                    haptic: .none,
                    voiceCueText: nil,
                    accentToken: .neutral
                )
            }
        case .cadenceDrift:
            self.init(
                haptic: .retry,
                voiceCueText: "Cadence dropping. Quicken your steps.",
                accentToken: .vibrantGreen
            )
        case .splitMilestone(let index, let pace):
            let mins = pace / 60
            let secs = pace % 60
            let paceText = String(format: "%d:%02d", mins, secs)
            let unitStr = useMetricSystem ? "Kilometer" : "Mile"
            self.init(
                haptic: .success,
                voiceCueText: "\(unitStr) \(index). \(paceText) pace.",
                accentToken: .electricBlue
            )
        }
    }

    public init(for event: PacingEvent) {
        self.init(for: event, useMetricSystem: true)
    }
}

extension PacingEvent {
    /// Deterministic unit-aware feedback specification (haptic, voice cue, accent token) for this event.
    public func feedbackSpec(useMetricSystem: Bool) -> PacingEventFeedbackSpec {
        PacingEventFeedbackSpec(for: self, useMetricSystem: useMetricSystem)
    }

    /// Deterministic feedback specification (haptic, voice cue, accent token) for this event.
    public var feedbackSpec: PacingEventFeedbackSpec {
        feedbackSpec(useMetricSystem: true)
    }
}

// MARK: - Display State

/// Pure, pre-rendered snapshot for hollow watchOS and iOS views.
///
/// Contains all formatted strings and presentation tokens so views perform zero inline arithmetic.
public struct PacingDisplayState: Sendable, Equatable {
    public let state: PacingState
    public let targetPaceSecondsPerKm: Int?
    public let filteredPaceSecondsPerKm: Int?
    public let filteredHeartRateBPM: Int?
    public let deviation: PaceDeviation
    public let refractorySecondsRemaining: Int
    public let lastReason: PacingReason?
    public let adjustmentsEnabled: Bool

    // Cadence
    public let filteredCadenceSPM: Int?
    public let filteredCadenceFormatted: String
    public let targetCadenceSPM: Int?
    public let targetCadenceFormatted: String

    // Precomputed presentation helpers (Zero leaked view math)
    public let targetPaceFormatted: String
    public let filteredPaceFormatted: String
    public let filteredHeartRateFormatted: String
    public let deviationTitle: String
    public let calibrationProgress: Double?
    public let calibrationProgressFormatted: String
    public let refractoryProgress: Double

    // Watch Companion Dynamic Gauge & Biometrics
    public let isCalibrating: Bool
    public let elapsedTimeFormatted: String
    public let paceGaugeNormalizedPosition: Double
    public let targetBandLowerNormalized: Double
    public let targetBandUpperNormalized: Double
    public let biometricStatusToken: PacingAccentToken
    public let biometricStatusLabel: String

    public init(
        state: PacingState,
        targetPaceSecondsPerKm: Int?,
        filteredPaceSecondsPerKm: Int?,
        filteredHeartRateBPM: Int?,
        deviation: PaceDeviation,
        refractorySecondsRemaining: Int,
        lastReason: PacingReason?,
        adjustmentsEnabled: Bool,
        targetPaceFormatted: String,
        filteredPaceFormatted: String,
        filteredHeartRateFormatted: String,
        deviationTitle: String,
        calibrationProgress: Double?,
        calibrationProgressFormatted: String,
        refractoryProgress: Double,
        filteredCadenceSPM: Int? = nil,
        filteredCadenceFormatted: String = "--",
        targetCadenceSPM: Int? = nil,
        targetCadenceFormatted: String = "--",
        isCalibrating: Bool = false,
        elapsedTimeFormatted: String = "0:00",
        paceGaugeNormalizedPosition: Double = 0.5,
        targetBandLowerNormalized: Double = 0.42,
        targetBandUpperNormalized: Double = 0.58,
        biometricStatusToken: PacingAccentToken = .neutral,
        biometricStatusLabel: String = ""
    ) {
        self.state = state
        self.targetPaceSecondsPerKm = targetPaceSecondsPerKm
        self.filteredPaceSecondsPerKm = filteredPaceSecondsPerKm
        self.filteredHeartRateBPM = filteredHeartRateBPM
        self.deviation = deviation
        self.refractorySecondsRemaining = refractorySecondsRemaining
        self.lastReason = lastReason
        self.adjustmentsEnabled = adjustmentsEnabled
        self.targetPaceFormatted = targetPaceFormatted
        self.filteredPaceFormatted = filteredPaceFormatted
        self.filteredHeartRateFormatted = filteredHeartRateFormatted
        self.deviationTitle = deviationTitle
        self.calibrationProgress = calibrationProgress
        self.calibrationProgressFormatted = calibrationProgressFormatted
        self.refractoryProgress = refractoryProgress
        self.filteredCadenceSPM = filteredCadenceSPM
        self.filteredCadenceFormatted = filteredCadenceFormatted
        self.targetCadenceSPM = targetCadenceSPM
        self.targetCadenceFormatted = targetCadenceFormatted
        self.isCalibrating = isCalibrating
        self.elapsedTimeFormatted = elapsedTimeFormatted
        self.paceGaugeNormalizedPosition = paceGaugeNormalizedPosition
        self.targetBandLowerNormalized = targetBandLowerNormalized
        self.targetBandUpperNormalized = targetBandUpperNormalized
        self.biometricStatusToken = biometricStatusToken
        self.biometricStatusLabel = biometricStatusLabel
    }
}

// MARK: - PacingDisplayState Presentation Extensions

extension PacingDisplayState {
    /// User-facing descriptive state title.
    public var stateTitle: String {
        switch state {
        case .calibrating:
            return "Calibrating"
        case .tracking:
            return adjustmentsEnabled ? "Adaptive Pacing" : "Monitor Only"
        case .surge:
            return "Surge"
        case .recover:
            return "Recover"
        }
    }

    /// Formatted refractory countdown string (e.g. "1:30", or empty if not in refractory).
    public var refractoryCountdownFormatted: String {
        guard refractorySecondsRemaining > 0 else { return "" }
        let minutes = refractorySecondsRemaining / 60
        let seconds = refractorySecondsRemaining % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Active presentation accent token bound to the current pacing state and causal reason.
    public var accentToken: PacingAccentToken {
        switch state {
        case .calibrating, .tracking:
            return .neutral
        case .surge:
            return .electricBlue
        case .recover:
            switch lastReason {
            case .formBreakdown:
                return .vibrantGreen
            case .efficiencyDrift, .heartRateCeiling, .compound, .reservesAvailable, .none:
                return .neonPink
            }
        }
    }

    /// Creates an initial ready-to-render display state prior to receiving any telemetry ticks.
    public static func initial(
        targetPaceSecondsPerKm: Int? = nil,
        adjustmentsEnabled: Bool = true,
        targetCadenceSPM: Int? = nil
    ) -> PacingDisplayState {
        let targetFormatted: String = {
            guard let seconds = targetPaceSecondsPerKm, seconds > 0 else { return "--:--" }
            let mins = seconds / 60
            let secs = seconds % 60
            return String(format: "%d:%02d /km", mins, secs)
        }()

        let targetCadFormatted = targetCadenceSPM.map { "\($0) SPM" } ?? "--"

        return PacingDisplayState(
            state: .calibrating(progress: 0.0),
            targetPaceSecondsPerKm: targetPaceSecondsPerKm,
            filteredPaceSecondsPerKm: nil,
            filteredHeartRateBPM: nil,
            deviation: .unknown,
            refractorySecondsRemaining: 0,
            lastReason: nil,
            adjustmentsEnabled: adjustmentsEnabled,
            targetPaceFormatted: targetFormatted,
            filteredPaceFormatted: "--:--",
            filteredHeartRateFormatted: "--",
            deviationTitle: "--",
            calibrationProgress: 0.0,
            calibrationProgressFormatted: "0%",
            refractoryProgress: 0.0,
            filteredCadenceSPM: nil,
            filteredCadenceFormatted: "--",
            targetCadenceSPM: targetCadenceSPM,
            targetCadenceFormatted: targetCadFormatted,
            isCalibrating: true,
            elapsedTimeFormatted: "0:00",
            paceGaugeNormalizedPosition: 0.5,
            targetBandLowerNormalized: 0.42,
            targetBandUpperNormalized: 0.58,
            biometricStatusToken: .calibratingBlue,
            biometricStatusLabel: "Calibrating"
        )
    }
}

// MARK: - AdaptivePacingCore Display State Builder Extension

extension AdaptivePacingCore {
    internal func buildDisplayState(speedEstimate: Double?, hrEstimate: Double?) -> PacingDisplayState {
        let filteredPace: Int? = {
            if let shortSpeed = ringBuffer.shortWindowStats(for: .filteredSpeed)?.mean, shortSpeed > 0 {
                return Int((1000.0 / shortSpeed).rounded())
            }
            if let current = speedEstimate, current > 0 {
                return Int((1000.0 / current).rounded())
            }
            return nil
        }()

        let filteredCadence: Int? = {
            if let shortCadence = ringBuffer.shortWindowStats(for: .cadence)?.mean, shortCadence > 0 {
                return Int(shortCadence.rounded())
            }
            if let current = ringBuffer.latestTick?.cadenceSPM, current > 0 {
                return Int(current.rounded())
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

        let filteredCadFormatted: String = filteredCadence.map { "\($0) SPM" } ?? "--"
        let targetCadFormatted: String = currentTargetCadenceSPM.map { "\($0) SPM" } ?? "--"

        let isCalibrating: Bool = {
            if case .calibrating = state { return true }
            return false
        }()

        let elapsedSecs = ringBuffer.latestTick?.elapsedSeconds ?? 0.0
        let totalElapsedSeconds = Int(elapsedSecs.rounded())
        let elapsedMinutes = totalElapsedSeconds / 60
        let elapsedRemainingSeconds = totalElapsedSeconds % 60
        let elapsedHours = elapsedMinutes / 60
        let elapsedTimeFormatted = (elapsedHours > 0)
            ? String(format: "%d:%02d:%02d", elapsedHours, elapsedMinutes % 60, elapsedRemainingSeconds)
            : String(format: "%d:%02d", elapsedMinutes, elapsedRemainingSeconds)

        let gaugePosition: Double = {
            guard let target = currentTargetPaceSecondsPerKm, target > 0,
                  let current = filteredPace, current > 0 else {
                return 0.5
            }
            let delta = Double(target - current)
            let halfSpan = Double(target) * 0.25
            let normalized = 0.5 + (delta / (halfSpan * 2.0))
            return min(1.0, max(0.0, normalized))
        }()

        let (lowerBand, upperBand): (Double, Double) = {
            guard let target = currentTargetPaceSecondsPerKm, target > 0 else {
                return (0.42, 0.58)
            }
            let tolerance = max(
                configuration.backOnTargetMinToleranceSecondsPerKm,
                Int((Double(target) * configuration.backOnTargetToleranceFraction).rounded())
            )
            let halfSpan = Double(target) * 0.25
            let offset = min(0.40, Double(tolerance) / (halfSpan * 2.0))
            return (0.5 - offset, 0.5 + offset)
        }()

        let bioToken: PacingAccentToken = {
            switch state {
            case .calibrating:
                return .calibratingBlue
            case .tracking:
                return .electricBlue
            case .surge:
                return .surgeTeal
            case .recover:
                return .recoverAmber
            }
        }()

        let bioLabel: String = {
            switch state {
            case .calibrating:
                return "Calibrating"
            case .tracking:
                return "Locked In"
            case .surge:
                return "Surge Zone"
            case .recover:
                return "Protecting Zone"
            }
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
            refractoryProgress: refractoryProg,
            filteredCadenceSPM: filteredCadence,
            filteredCadenceFormatted: filteredCadFormatted,
            targetCadenceSPM: currentTargetCadenceSPM,
            targetCadenceFormatted: targetCadFormatted,
            isCalibrating: isCalibrating,
            elapsedTimeFormatted: elapsedTimeFormatted,
            paceGaugeNormalizedPosition: gaugePosition,
            targetBandLowerNormalized: lowerBand,
            targetBandUpperNormalized: upperBand,
            biometricStatusToken: bioToken,
            biometricStatusLabel: bioLabel
        )
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
