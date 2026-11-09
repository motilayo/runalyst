import Foundation

// MARK: - Presentation Tokens & Feedback Specifications

/// Subconscious UI accent tokens bound to the causal pacing metric.
public enum PacingAccentToken: String, Sendable, Codable, CaseIterable, Equatable {
    /// Pace metric accent (Electric Blue).
    case electricBlue
    /// Heart rate metric accent (Neon Pink).
    case neonPink
    /// Cadence & biomechanics metric accent (Vibrant Green).
    case vibrantGreen
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
        }
    }
}

extension PacingEvent {
    /// Deterministic feedback specification (haptic, voice cue, accent token) for this event.
    public var feedbackSpec: PacingEventFeedbackSpec {
        PacingEventFeedbackSpec(for: self)
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
