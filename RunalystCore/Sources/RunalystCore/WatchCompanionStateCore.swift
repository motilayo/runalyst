import Foundation

// MARK: - Watch Companion Phase

/// Biomechanical execution phase of an active or completed Apple Watch workout session.
public enum WatchCompanionPhase: String, Sendable, Codable, Equatable, CaseIterable {
    case idle
    case calibrating
    case running
    case surge
    case recover
    case paused
    case completed

    /// Whether this phase indicates an active, in-progress, or paused workout session.
    public var isActiveWorkout: Bool {
        switch self {
        case .calibrating, .running, .surge, .recover, .paused:
            return true
        case .idle, .completed:
            return false
        }
    }
}

// MARK: - Remote Companion Commands

/// Bidirectional control command transmitted between paired iPhone and Apple Watch companion sessions.
public enum WatchRemoteCommand: String, Sendable, Codable, Equatable, CaseIterable {
    case pauseWorkout
    case resumeWorkout
    case endWorkout
    case toggleVoiceCues
    case requestContextSync

    /// User-facing descriptive title for companion buttons and remote action indicators.
    public var title: String {
        switch self {
        case .pauseWorkout:
            return "Pause Workout"
        case .resumeWorkout:
            return "Resume Workout"
        case .endWorkout:
            return "End Workout"
        case .toggleVoiceCues:
            return "Toggle Voice Cues"
        case .requestContextSync:
            return "Request Context Sync"
        }
    }
}

// MARK: - Location Presentation Extension

extension PacingLocation {
    /// Human-readable title for workout environment display.
    public var title: String {
        switch self {
        case .outdoor:
            return "Outdoor"
        case .indoor:
            return "Indoor"
        }
    }
}

// MARK: - Watch Live Run Snapshot

/// Pure, serializable snapshot of live Apple Watch workout telemetry and hollow presentation states.
public struct WatchLiveRunSnapshot: Sendable, Codable, Equatable {
    public static let currentSchemaVersion: Int = 1

    /// Schema version for payload forward compatibility.
    public let schemaVersion: Int
    /// Biomechanical phase of the workout session.
    public let phase: WatchCompanionPhase
    /// Workout operating environment (indoor treadmill vs outdoor GPS).
    public let location: PacingLocation
    /// Athlete high-level running intent.
    public let runIntent: WatchRunIntent
    /// Prescribed drill title if the session was seeded from an iPhone prescription.
    public let prescribedDrillTitle: String?
    /// User-facing descriptive state title (e.g. "Calibrating", "Adaptive Pacing", "Paused").
    public let stateTitle: String
    /// Empathetic biometric coaching label (e.g. "Cadence & HR Nominal").
    public let biometricStatusLabel: String
    /// Accent color token bound to the current pacing state and telemetry signals.
    public let biometricStatusToken: PacingAccentToken
    /// Pre-formatted current filtered pace string (e.g. "5:12 /km").
    public let filteredPaceFormatted: String
    /// Pre-formatted target pace band string (e.g. "5:15 /km").
    public let targetPaceFormatted: String
    /// Pre-formatted heart rate string (e.g. "148 BPM").
    public let filteredHeartRateFormatted: String
    /// Pre-formatted cadence string (e.g. "172 SPM").
    public let filteredCadenceFormatted: String
    /// Pre-formatted workout elapsed time string (e.g. "14:28").
    public let elapsedTimeFormatted: String
    /// Concise pace deviation label (e.g. "+3 s/km fast" or "On Target").
    public let deviationTitle: String
    /// Normalized gauge needle position along the 0.0...1.0 dial arc.
    public let paceGaugeNormalizedPosition: Double
    /// Lower bound of the target pace green band on the normalized dial (0.0...1.0).
    public let targetBandLowerNormalized: Double
    /// Upper bound of the target pace green band on the normalized dial (0.0...1.0).
    public let targetBandUpperNormalized: Double
    /// Calibration phase progress (0.0...1.0), or `nil` once calibration is complete.
    public let calibrationProgress: Double?
    /// Post-run 3-bullet takeaway summary populated upon session completion.
    public let completedDebrief: WatchRunDebrief?
    /// Epoch timestamp (in seconds) when this snapshot was captured on Apple Watch.
    public let updatedAtEpochSeconds: TimeInterval

    public init(
        schemaVersion: Int = WatchLiveRunSnapshot.currentSchemaVersion,
        phase: WatchCompanionPhase,
        location: PacingLocation,
        runIntent: WatchRunIntent,
        prescribedDrillTitle: String? = nil,
        stateTitle: String,
        biometricStatusLabel: String,
        biometricStatusToken: PacingAccentToken,
        filteredPaceFormatted: String,
        targetPaceFormatted: String,
        filteredHeartRateFormatted: String,
        filteredCadenceFormatted: String,
        elapsedTimeFormatted: String,
        deviationTitle: String,
        paceGaugeNormalizedPosition: Double,
        targetBandLowerNormalized: Double,
        targetBandUpperNormalized: Double,
        calibrationProgress: Double? = nil,
        completedDebrief: WatchRunDebrief? = nil,
        updatedAtEpochSeconds: TimeInterval
    ) {
        self.schemaVersion = schemaVersion
        self.phase = phase
        self.location = location
        self.runIntent = runIntent
        self.prescribedDrillTitle = prescribedDrillTitle
        self.stateTitle = stateTitle
        self.biometricStatusLabel = biometricStatusLabel
        self.biometricStatusToken = biometricStatusToken
        self.filteredPaceFormatted = filteredPaceFormatted
        self.targetPaceFormatted = targetPaceFormatted
        self.filteredHeartRateFormatted = filteredHeartRateFormatted
        self.filteredCadenceFormatted = filteredCadenceFormatted
        self.elapsedTimeFormatted = elapsedTimeFormatted
        self.deviationTitle = deviationTitle
        self.paceGaugeNormalizedPosition = paceGaugeNormalizedPosition
        self.targetBandLowerNormalized = targetBandLowerNormalized
        self.targetBandUpperNormalized = targetBandUpperNormalized
        self.calibrationProgress = calibrationProgress
        self.completedDebrief = completedDebrief
        self.updatedAtEpochSeconds = updatedAtEpochSeconds
    }

    /// Whether this snapshot schema version is supported by the compiled runtime.
    public var isSupportedSchema: Bool {
        schemaVersion <= WatchLiveRunSnapshot.currentSchemaVersion
    }

    /// Whether the watch is currently in an active or paused workout state.
    public var isActiveWorkout: Bool {
        phase.isActiveWorkout
    }

    /// Whether the watch workout is currently in a paused state.
    public var isPaused: Bool {
        phase == .paused
    }

    /// Determines whether the snapshot telemetry has become stale based on elapsed seconds.
    /// Completed or paused sessions are never considered stale.
    public func isStale(at nowEpochSeconds: TimeInterval, maxAgeSeconds: TimeInterval = 45.0) -> Bool {
        guard phase != .completed, !isPaused else { return false }
        return (nowEpochSeconds - updatedAtEpochSeconds) > maxAgeSeconds
    }

    /// High-level presentation header title (Coach's Takeaway on completion, paused notice, prescribed drill if present, or run intent).
    public var headerTitle: String {
        if phase == .completed {
            return "Coach's Takeaway"
        }
        if phase == .paused {
            return "Apple Watch Paused"
        }
        if let prescribed = prescribedDrillTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !prescribed.isEmpty {
            return prescribed
        }
        return runIntent.title
    }

    /// Pre-computed subtitle combining run intent and environment (e.g. "Adaptive Base • Outdoor").
    public var intentAndLocationSubtitle: String {
        "\(runIntent.title) • \(location.title)"
    }

    /// Factory mapping an active `PacingDisplayState` and context to a pure `WatchLiveRunSnapshot`.
    public static func from(
        displayState: PacingDisplayState,
        location: PacingLocation,
        runIntent: WatchRunIntent,
        prescribedDrillTitle: String? = nil,
        isPaused: Bool = false,
        isCompleted: Bool = false,
        completedDebrief: WatchRunDebrief? = nil,
        updatedAtEpochSeconds: TimeInterval
    ) -> WatchLiveRunSnapshot {
        let phase: WatchCompanionPhase = {
            if isCompleted {
                return .completed
            }
            if isPaused {
                return .paused
            }
            switch displayState.state {
            case .calibrating:
                return .calibrating
            case .tracking:
                return .running
            case .surge:
                return .surge
            case .recover:
                return .recover
            }
        }()

        let stateTitle: String = {
            if isCompleted {
                return "Completed"
            }
            if isPaused {
                return "Paused"
            }
            return displayState.stateTitle
        }()

        return WatchLiveRunSnapshot(
            schemaVersion: currentSchemaVersion,
            phase: phase,
            location: location,
            runIntent: runIntent,
            prescribedDrillTitle: prescribedDrillTitle,
            stateTitle: stateTitle,
            biometricStatusLabel: displayState.biometricStatusLabel,
            biometricStatusToken: displayState.biometricStatusToken,
            filteredPaceFormatted: displayState.filteredPaceFormatted,
            targetPaceFormatted: displayState.targetPaceFormatted,
            filteredHeartRateFormatted: displayState.filteredHeartRateFormatted,
            filteredCadenceFormatted: displayState.filteredCadenceFormatted,
            elapsedTimeFormatted: displayState.elapsedTimeFormatted,
            deviationTitle: displayState.deviationTitle,
            paceGaugeNormalizedPosition: displayState.paceGaugeNormalizedPosition,
            targetBandLowerNormalized: displayState.targetBandLowerNormalized,
            targetBandUpperNormalized: displayState.targetBandUpperNormalized,
            calibrationProgress: displayState.calibrationProgress,
            completedDebrief: completedDebrief,
            updatedAtEpochSeconds: updatedAtEpochSeconds
        )
    }

    /// Factory creating an idle placeholder snapshot when no active session is running on Apple Watch.
    public static func idle(
        location: PacingLocation = .outdoor,
        runIntent: WatchRunIntent = .adaptiveBase,
        updatedAtEpochSeconds: TimeInterval = 0
    ) -> WatchLiveRunSnapshot {
        WatchLiveRunSnapshot(
            schemaVersion: currentSchemaVersion,
            phase: .idle,
            location: location,
            runIntent: runIntent,
            prescribedDrillTitle: nil,
            stateTitle: "Ready",
            biometricStatusLabel: "",
            biometricStatusToken: .neutral,
            filteredPaceFormatted: "--",
            targetPaceFormatted: "--",
            filteredHeartRateFormatted: "--",
            filteredCadenceFormatted: "--",
            elapsedTimeFormatted: "0:00",
            deviationTitle: "",
            paceGaugeNormalizedPosition: 0.5,
            targetBandLowerNormalized: 0.42,
            targetBandUpperNormalized: 0.58,
            calibrationProgress: nil,
            completedDebrief: nil,
            updatedAtEpochSeconds: updatedAtEpochSeconds
        )
    }
}

// MARK: - PacingDisplayState Live Snapshot Extension

extension PacingDisplayState {
    /// Maps this active display state into a pure `WatchLiveRunSnapshot` for companion broadcast.
    public func makeLiveSnapshot(
        location: PacingLocation,
        runIntent: WatchRunIntent,
        prescribedDrillTitle: String? = nil,
        isPaused: Bool = false,
        isCompleted: Bool = false,
        completedDebrief: WatchRunDebrief? = nil,
        updatedAtEpochSeconds: TimeInterval
    ) -> WatchLiveRunSnapshot {
        WatchLiveRunSnapshot.from(
            displayState: self,
            location: location,
            runIntent: runIntent,
            prescribedDrillTitle: prescribedDrillTitle,
            isPaused: isPaused,
            isCompleted: isCompleted,
            completedDebrief: completedDebrief,
            updatedAtEpochSeconds: updatedAtEpochSeconds
        )
    }
}
