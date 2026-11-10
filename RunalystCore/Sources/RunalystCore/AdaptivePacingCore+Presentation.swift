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
}

/// Abstract haptic semantic categories mapped to watchOS haptic playback.
public enum PacingHapticSemantic: String, Sendable, Codable, CaseIterable, Equatable {
    case directionUp
    case directionDown
    case retry
    case success
    case none
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

    public init(for event: PacingEvent) {
        switch event {
        case .surge:
            self.init(
                haptic: .directionUp,
                voiceCueText: "Target pace up. Quicken your steps.",
                accentToken: .electricBlue
            )
        case .recover(_, _, let reason):
            switch reason {
            case .formBreakdown:
                self.init(
                    haptic: .retry,
                    voiceCueText: "Cadence dropping. Short, quick steps.",
                    accentToken: .vibrantGreen
                )
            case .efficiencyDrift, .heartRateCeiling, .compound, .reservesAvailable:
                self.init(
                    haptic: .directionDown,
                    voiceCueText: "Heart rate drifting. Ease the pace.",
                    accentToken: .neonPink
                )
            }
        case .backOnTarget:
            self.init(
                haptic: .success,
                voiceCueText: nil,
                accentToken: .neutral
            )
        case .calibrationComplete:
            self.init(
                haptic: .none,
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
        }
    }
}

extension PacingEvent {
    /// Deterministic feedback specification (haptic, voice cue, accent token) for this event.
    public var feedbackSpec: PacingEventFeedbackSpec {
        PacingEventFeedbackSpec(for: self)
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

    // Precomputed presentation helpers (Zero leaked view math)
    public let targetPaceFormatted: String
    public let filteredPaceFormatted: String
    public let filteredHeartRateFormatted: String
    public let deviationTitle: String
    public let calibrationProgress: Double?
    public let calibrationProgressFormatted: String
    public let refractoryProgress: Double

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
        refractoryProgress: Double
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
        adjustmentsEnabled: Bool = true
    ) -> PacingDisplayState {
        let targetFormatted: String = {
            guard let seconds = targetPaceSecondsPerKm, seconds > 0 else { return "--:--" }
            let mins = seconds / 60
            let secs = seconds % 60
            return String(format: "%d:%02d /km", mins, secs)
        }()

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
            refractoryProgress: 0.0
        )
    }
}
