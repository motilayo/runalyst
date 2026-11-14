import Foundation

// MARK: - Watch Context & Session Configuration

/// Versioned payload transferred from iPhone to Apple Watch via `WCSession.updateApplicationContext`.
public struct WatchPacingContext: Sendable, Codable, Equatable {
    public static let currentSchemaVersion: Int = 1

    /// Schema version for forward-compatibility validation.
    public let schemaVersion: Int
    /// Athlete physiological calibration profile.
    public let profile: AthleteCalibrationProfile
    /// Today's synthesized training intent.
    public let intent: PacingSessionIntent
    /// Persisted environment preference from iOS app (indoor vs outdoor).
    public let isIndoorPreferred: Bool?
    /// Preferred unit system: metric (true) vs imperial (false).
    public let useMetricSystem: Bool?
    /// Whether spoken pacing audio cues are enabled on watch.
    public let watchVoiceCuesEnabled: Bool?

    public init(
        schemaVersion: Int = WatchPacingContext.currentSchemaVersion,
        profile: AthleteCalibrationProfile,
        intent: PacingSessionIntent,
        isIndoorPreferred: Bool? = nil,
        useMetricSystem: Bool? = nil,
        watchVoiceCuesEnabled: Bool? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.profile = profile
        self.intent = intent
        self.isIndoorPreferred = isIndoorPreferred
        self.useMetricSystem = useMetricSystem
        self.watchVoiceCuesEnabled = watchVoiceCuesEnabled
    }

    /// Whether the watch app's compiled runtime supports this schema version.
    public var isSupportedSchema: Bool {
        schemaVersion <= WatchPacingContext.currentSchemaVersion
    }
}

/// Discrete target pace selection option presented on Apple Watch.
public struct WatchTargetPaceOption: Identifiable, Sendable, Codable, Equatable, Hashable {
    public let id: String
    public let paceSecondsPerKm: Int?
    public let label: String

    public init(id: String, paceSecondsPerKm: Int?, label: String) {
        self.id = id
        self.paceSecondsPerKm = paceSecondsPerKm
        self.label = label
    }

    /// Returns a unit-aware formatted pace label in metric (`/km`) or imperial (`/mi`), falling back to `label` when unset.
    ///
    /// - Parameter useMetric: When `true`, formats in seconds per kilometer; when `false`, converts to seconds per mile.
    /// - Returns: A formatted string such as `"5:00 /km"`, `"8:03 /mi"`, or `"Just Run"`.
    public func label(useMetric: Bool) -> String {
        guard let seconds = paceSecondsPerKm, seconds > 0 else {
            return label
        }
        if useMetric {
            let minutes = seconds / 60
            let secs = seconds % 60
            return String(format: "%d:%02d /km", minutes, secs)
        } else {
            let displaySeconds = Int((Double(seconds) * 1.609344).rounded())
            let minutes = displaySeconds / 60
            let secs = displaySeconds % 60
            return String(format: "%d:%02d /mi", minutes, secs)
        }
    }

    /// Default option where no explicit pace is targeted, adapting around the athlete's natural baseline.
    public static let justRun = WatchTargetPaceOption(
        id: "just-run",
        paceSecondsPerKm: nil,
        label: "Just Run"
    )

    /// Standard presets ranging from 4:00 /km (240 s) to 8:00 /km (480 s) in 15-second steps.
    public static let allOptions: [WatchTargetPaceOption] = {
        var options: [WatchTargetPaceOption] = [.justRun]
        for pace in stride(from: 240, through: 480, by: 15) {
            let minutes = pace / 60
            let seconds = pace % 60
            let label = String(format: "%d:%02d /km", minutes, seconds)
            options.append(WatchTargetPaceOption(id: "\(pace)", paceSecondsPerKm: pace, label: label))
        }
        return options
    }()
}

/// Resolved runtime configuration for an Apple Watch workout session.
public struct WatchResolvedSessionConfig: Sendable, Equatable {
    public let profile: AthleteCalibrationProfile
    public let intent: PacingSessionIntent
    public let requiresTargetPacePicker: Bool
    public let isIndoorPreferred: Bool
    public let isPhoneSessionSynced: Bool

    public var hasPrescribedDrill: Bool {
        intent.prescribedDrillTitle != nil
    }

    public var prescribedDrillTitle: String? {
        intent.prescribedDrillTitle
    }

    public var targetCadenceFormatted: String? {
        guard let spm = intent.targetCadenceSPM else { return nil }
        return "\(spm) SPM"
    }

    public var durationFormatted: String? {
        guard let mins = intent.prescribedDurationMinutes else { return nil }
        return "\(mins) Min"
    }

    public init(
        profile: AthleteCalibrationProfile,
        intent: PacingSessionIntent,
        requiresTargetPacePicker: Bool? = nil,
        isIndoorPreferred: Bool = false,
        isPhoneSessionSynced: Bool = false
    ) {
        self.profile = profile
        self.intent = intent
        self.requiresTargetPacePicker = requiresTargetPacePicker ?? false
        self.isIndoorPreferred = isIndoorPreferred
        self.isPhoneSessionSynced = isPhoneSessionSynced
    }

    /// Derives a session configuration tailored to a user-selected running intent.
    ///
    /// Prescribed drills take precedence and remain intact; non-drill sessions adopt
    /// the intent's pacing category and clear the target pace picker requirement.
    public func applying(runIntent: WatchRunIntent) -> WatchResolvedSessionConfig {
        guard !hasPrescribedDrill else { return self }
        let modifiedIntent = PacingSessionIntent(
            targetPaceSecondsPerKm: intent.targetPaceSecondsPerKm,
            intent: runIntent.pacingIntentKind,
            subjectiveDistress: intent.subjectiveDistress,
            validForDay: intent.validForDay,
            prescribedDrillTitle: intent.prescribedDrillTitle,
            prescribedDrillId: intent.prescribedDrillId,
            targetCadenceSPM: intent.targetCadenceSPM,
            prescribedDurationMinutes: intent.prescribedDurationMinutes
        )
        return WatchResolvedSessionConfig(
            profile: profile,
            intent: modifiedIntent,
            requiresTargetPacePicker: false,
            isIndoorPreferred: isIndoorPreferred,
            isPhoneSessionSynced: isPhoneSessionSynced
        )
    }
}

// MARK: - Watch Run Intent

/// High-level zero-friction running intent selected on Apple Watch.
public enum WatchRunIntent: String, Sendable, Codable, CaseIterable, Identifiable, Equatable {
    case adaptiveBase
    case pushPerformance
    case recovery

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .adaptiveBase:
            return "Adaptive Base"
        case .pushPerformance:
            return "Push / Performance"
        case .recovery:
            return "Recovery"
        }
    }

    public var subtitle: String {
        switch self {
        case .adaptiveBase:
            return "Balanced aerobic run"
        case .pushPerformance:
            return "Find my ceiling today"
        case .recovery:
            return "Keep me honest and easy"
        }
    }

    public var pacingIntentKind: PacingIntentKind {
        switch self {
        case .adaptiveBase:
            return .steady
        case .pushPerformance:
            return .tempo
        case .recovery:
            return .recovery
        }
    }
}

// MARK: - Watch Voice Delivery Target

/// Destination target for synthesized pacing audio cues initiated on Apple Watch.
public enum WatchVoiceDeliveryTarget: String, Sendable, Equatable {
    case watchLocal
    case companionRelayWithLocalFallback

    /// Resolves whether a voice cue should speak directly through Apple Watch audio hardware
    /// or be routed through the paired iPhone companion session (e.g. runner's AirPods are connected to phone).
    public static func resolve(
        watchHasBluetoothHeadphoneRoute: Bool,
        isCompanionReachable: Bool
    ) -> WatchVoiceDeliveryTarget {
        if watchHasBluetoothHeadphoneRoute {
            return .watchLocal
        } else if isCompanionReachable {
            return .companionRelayWithLocalFallback
        } else {
            return .watchLocal
        }
    }
}
