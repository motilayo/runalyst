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

    public init(
        schemaVersion: Int = WatchPacingContext.currentSchemaVersion,
        profile: AthleteCalibrationProfile,
        intent: PacingSessionIntent,
        isIndoorPreferred: Bool? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.profile = profile
        self.intent = intent
        self.isIndoorPreferred = isIndoorPreferred
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
        requiresTargetPacePicker: Bool,
        isIndoorPreferred: Bool = false
    ) {
        self.profile = profile
        self.intent = intent
        self.requiresTargetPacePicker = requiresTargetPacePicker
        self.isIndoorPreferred = isIndoorPreferred
    }
}
