import Foundation

// MARK: - Telemetry Ingot (Raw Ingestion Shape)

/// Represents a raw temporal slice of telemetry recorded during a running session.
/// Extracted directly from device sensors without platform lock-in.
public struct TelemetryBucket: Sendable, Codable, Equatable {
    /// Timestamp marking the start of this telemetry bucket.
    public let timestamp: Date
    /// Duration of the slice in seconds (nominally 30s or 60s).
    public let durationSeconds: TimeInterval
    /// Total distance covered during this slice in meters.
    public let distanceMeters: Double
    /// Instantaneous or mean pace in seconds per kilometer.
    public let paceSecondsPerKm: Double
    /// Mean cadence in steps per minute (SPM).
    public let cadenceSPM: Double
    /// Mean heart rate in beats per minute (BPM).
    public let heartRateBPM: Double
    /// Ground contact time in milliseconds, if available from a footpod or watch sensor.
    public let groundContactTimeMs: Double?
    /// Vertical oscillation of the torso in centimeters.
    public let verticalOscillationCm: Double?
    /// Mean stride length in meters.
    public let strideLengthMeters: Double?
    /// Cumulative elevation gain in meters.
    public let elevationGainMeters: Double?

    public init(
        timestamp: Date,
        durationSeconds: TimeInterval = 60.0,
        distanceMeters: Double,
        paceSecondsPerKm: Double,
        cadenceSPM: Double,
        heartRateBPM: Double,
        groundContactTimeMs: Double? = nil,
        verticalOscillationCm: Double? = nil,
        strideLengthMeters: Double? = nil,
        elevationGainMeters: Double? = nil
    ) {
        self.timestamp = timestamp
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.paceSecondsPerKm = paceSecondsPerKm
        self.cadenceSPM = cadenceSPM
        self.heartRateBPM = heartRateBPM
        self.groundContactTimeMs = groundContactTimeMs
        self.verticalOscillationCm = verticalOscillationCm
        self.strideLengthMeters = strideLengthMeters
        self.elevationGainMeters = elevationGainMeters
    }

    /// Speed in meters per second for this slice.
    public var speedMetersPerSecond: Double {
        durationSeconds > 0 ? (distanceMeters / durationSeconds) : 0.0
    }

    // MARK: - Compatibility Accessors
    public var startTime: Date { timestamp }
    public var meanPaceSecPerKm: Double { paceSecondsPerKm }
    public var meanCadence: Double { cadenceSPM }
    public var meanHR: Double { heartRateBPM }
    public var meanVerticalOscillation: Double { verticalOscillationCm ?? 0.0 }
    public var meanStrideLength: Double { strideLengthMeters ?? 0.0 }
}

// MARK: - Working Stats Ingot (Filtered Biomechanical Output)

/// Pure mathematical representation of a run's true working output.
/// Stationary pauses, traffic stops, and walking intervals are scrubbed to isolate
/// true mechanical and cardiovascular adaptation.
public struct WorkingStats: Sendable, Codable, Equatable {
    // True working metrics (dead stops trimmed)
    public let workingDistanceMeters: Double
    public let workingDurationSeconds: TimeInterval
    public let workingAvgPaceSecondsPerKm: Double
    public let workingAvgCadenceSPM: Double
    public let workingAvgHeartRateBPM: Double
    public let workingAvgVerticalOscillationCm: Double?
    public let workingAvgStrideLengthMeters: Double?
    public let workingAvgGroundContactTimeMs: Double?

    // Raw unscrubbed aggregates for provenance and audit
    public let rawTotalDistanceMeters: Double
    public let rawTotalDurationSeconds: TimeInterval
    public let rawAvgPaceSecondsPerKm: Double
    public let rawAvgCadenceSPM: Double
    public let rawAvgHeartRateBPM: Double
    public let rawAvgVerticalOscillationCm: Double?
    public let rawAvgStrideLengthMeters: Double?

    // Mathematical features
    public let paceCV: Double
    public let paceSlope: Double
    public let hrCV: Double?
    public let cadenceSlope: Double?
    public let percentZone4: Double
    public let deadStopsCount: Int
    public let isIndoor: Bool
    public let needsInclineReview: Bool
    public let detectedClassification: String
    public let framboiseTags: [String]

    public init(
        workingDistanceMeters: Double,
        workingDurationSeconds: TimeInterval,
        workingAvgPaceSecondsPerKm: Double,
        workingAvgCadenceSPM: Double,
        workingAvgHeartRateBPM: Double,
        workingAvgVerticalOscillationCm: Double? = nil,
        workingAvgStrideLengthMeters: Double? = nil,
        workingAvgGroundContactTimeMs: Double? = nil,
        rawTotalDistanceMeters: Double,
        rawTotalDurationSeconds: TimeInterval,
        rawAvgPaceSecondsPerKm: Double,
        rawAvgCadenceSPM: Double,
        rawAvgHeartRateBPM: Double,
        rawAvgVerticalOscillationCm: Double? = nil,
        rawAvgStrideLengthMeters: Double? = nil,
        paceCV: Double,
        paceSlope: Double,
        hrCV: Double? = nil,
        cadenceSlope: Double? = nil,
        percentZone4: Double,
        deadStopsCount: Int = 0,
        isIndoor: Bool = false,
        needsInclineReview: Bool = false,
        detectedClassification: String = "Steady Effort",
        framboiseTags: [String] = []
    ) {
        self.workingDistanceMeters = workingDistanceMeters
        self.workingDurationSeconds = workingDurationSeconds
        self.workingAvgPaceSecondsPerKm = workingAvgPaceSecondsPerKm
        self.workingAvgCadenceSPM = workingAvgCadenceSPM
        self.workingAvgHeartRateBPM = workingAvgHeartRateBPM
        self.workingAvgVerticalOscillationCm = workingAvgVerticalOscillationCm
        self.workingAvgStrideLengthMeters = workingAvgStrideLengthMeters
        self.workingAvgGroundContactTimeMs = workingAvgGroundContactTimeMs
        self.rawTotalDistanceMeters = rawTotalDistanceMeters
        self.rawTotalDurationSeconds = rawTotalDurationSeconds
        self.rawAvgPaceSecondsPerKm = rawAvgPaceSecondsPerKm
        self.rawAvgCadenceSPM = rawAvgCadenceSPM
        self.rawAvgHeartRateBPM = rawAvgHeartRateBPM
        self.rawAvgVerticalOscillationCm = rawAvgVerticalOscillationCm
        self.rawAvgStrideLengthMeters = rawAvgStrideLengthMeters
        self.paceCV = paceCV
        self.paceSlope = paceSlope
        self.hrCV = hrCV
        self.cadenceSlope = cadenceSlope
        self.percentZone4 = percentZone4
        self.deadStopsCount = deadStopsCount
        self.isIndoor = isIndoor
        self.needsInclineReview = needsInclineReview
        self.detectedClassification = detectedClassification
        self.framboiseTags = framboiseTags
    }

    /// Speed in meters per minute (derived from working average pace).
    public var speedMetersPerMinute: Double? {
        guard workingAvgPaceSecondsPerKm > 0 else { return nil }
        return 60_000.0 / workingAvgPaceSecondsPerKm
    }

    /// Efficiency Factor: Speed (meters/minute) divided by Heart Rate (BPM).
    /// Represents running economy: distance in meters traveled per heartbeat.
    public var efficiencyFactor: Double? {
        guard workingAvgHeartRateBPM > 0, let speed = speedMetersPerMinute else { return nil }
        return speed / workingAvgHeartRateBPM
    }

    /// Computed Vertical Ratio (percentage of vertical bounce relative to forward stride).
    public var verticalRatio: Double? {
        guard let stride = workingAvgStrideLengthMeters ?? rawAvgStrideLengthMeters, stride >= 0.3,
              let osc = workingAvgVerticalOscillationCm ?? rawAvgVerticalOscillationCm, osc > 0 else {
            return nil
        }
        return osc / stride
    }

    /// Evaluates whether active running heart rate is implausibly low (< 85 BPM during active running > 5 min).
    public var isHeartRateSensorLowConfidence: Bool {
        guard workingDurationSeconds >= 300.0,
              workingAvgPaceSecondsPerKm > 0,
              workingAvgPaceSecondsPerKm <= 540.0 else { return false }
        return workingAvgHeartRateBPM > 0 && workingAvgHeartRateBPM < 85.0
    }
}

// MARK: - Interval Segmentation Ingot (Topological & Multi-Signal Shapes)

/// Classification of a segmented interval phase.
public enum IntervalPhaseKind: String, Sendable, Codable, Equatable, CaseIterable {
    case work
    case recovery
    case steady
    case walking
}

/// A discrete continuous temporal phase within a running session.
public struct IntervalPhaseSegment: Sendable, Codable, Equatable {
    public let startSeconds: Double
    public let endSeconds: Double
    public let kind: IntervalPhaseKind
    public let avgPaceSecondsPerKm: Double
    public let avgCadenceSPM: Double
    public let avgHeartRateBPM: Double

    public var durationSeconds: Double {
        max(0.0, endSeconds - startSeconds)
    }

    public init(
        startSeconds: Double,
        endSeconds: Double,
        kind: IntervalPhaseKind,
        avgPaceSecondsPerKm: Double,
        avgCadenceSPM: Double,
        avgHeartRateBPM: Double
    ) {
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.kind = kind
        self.avgPaceSecondsPerKm = avgPaceSecondsPerKm
        self.avgCadenceSPM = avgCadenceSPM
        self.avgHeartRateBPM = avgHeartRateBPM
    }
}

/// A corroborated surge-and-recovery oscillation cycle extracted from telemetry.
public struct IntervalOscillationCycle: Sendable, Codable, Equatable {
    public let workDurationSeconds: Double
    public let recoveryDurationSeconds: Double
    public let workCadenceSPM: Double
    public let recoveryCadenceSPM: Double
    public let workPaceSecondsPerKm: Double
    public let recoveryPaceSecondsPerKm: Double
    public let workHeartRateBPM: Double
    public let recoveryHeartRateBPM: Double
    public let isCorroborated: Bool
    public let isDominantPaceSurge: Bool
    public let corroborationScore: Int

    public init(
        workDurationSeconds: Double,
        recoveryDurationSeconds: Double,
        workCadenceSPM: Double,
        recoveryCadenceSPM: Double,
        workPaceSecondsPerKm: Double,
        recoveryPaceSecondsPerKm: Double,
        workHeartRateBPM: Double,
        recoveryHeartRateBPM: Double,
        isCorroborated: Bool,
        isDominantPaceSurge: Bool = false,
        corroborationScore: Int = 0
    ) {
        self.workDurationSeconds = workDurationSeconds
        self.recoveryDurationSeconds = recoveryDurationSeconds
        self.workCadenceSPM = workCadenceSPM
        self.recoveryCadenceSPM = recoveryCadenceSPM
        self.workPaceSecondsPerKm = workPaceSecondsPerKm
        self.recoveryPaceSecondsPerKm = recoveryPaceSecondsPerKm
        self.workHeartRateBPM = workHeartRateBPM
        self.recoveryHeartRateBPM = recoveryHeartRateBPM
        self.isCorroborated = isCorroborated
        self.isDominantPaceSurge = isDominantPaceSurge
        self.corroborationScore = corroborationScore
    }
}

/// The synthesized result of biomechanical interval and progression segmentation.
public struct IntervalSegmentationReport: Sendable, Codable, Equatable {
    public let phases: [IntervalPhaseSegment]
    public let cycles: [IntervalOscillationCycle]
    public let workRepsCount: Int
    public let cycleRegularityScore: Double
    public let isMonotonicProgression: Bool
    public let isIntermittentWorkout: Bool

    public init(
        phases: [IntervalPhaseSegment],
        cycles: [IntervalOscillationCycle],
        workRepsCount: Int,
        cycleRegularityScore: Double,
        isMonotonicProgression: Bool,
        isIntermittentWorkout: Bool
    ) {
        self.phases = phases
        self.cycles = cycles
        self.workRepsCount = workRepsCount
        self.cycleRegularityScore = cycleRegularityScore
        self.isMonotonicProgression = isMonotonicProgression
        self.isIntermittentWorkout = isIntermittentWorkout
    }
}

// MARK: - Subjective Distress Signal (User Override States)

/// Signals representing user overrides, reported physical fatigue, soreness,
/// or external biological constraints that supersede pure algorithmic recommendations.
public enum SubjectiveDistressSignal: String, Sendable, Codable, Equatable, CaseIterable {
    /// Heavy systemic exhaustion or autonomic fatigue.
    case acuteFatigue
    /// Muscular soreness or delayed onset muscle soreness (DOMS).
    case muscleSoreness
    /// Mechanical breakdown, joint pain, or localized discomfort.
    case jointPain
    /// Sub-floor turnover collapse under fatigue.
    case mechanicalBreakdown
    /// Indoor thermoregulatory cardiac drift or overheating.
    case thermalExhaustion
    /// Elevated perceived exertion exceeding the prescribed workout intensity.
    case heavyExertion
    /// Illness, recovery from cold, or planned physical deload.
    case illnessDeload

    /// Indicates whether this subjective distress signal forces a deterministic recovery override.
    public var requiresSafetyOverride: Bool {
        switch self {
        case .acuteFatigue, .jointPain, .illnessDeload, .mechanicalBreakdown:
            return true
        case .muscleSoreness, .thermalExhaustion, .heavyExertion:
            return false
        }
    }
}

/// Explicit state capture for manual user overrides applied to a run record.
public enum UserOverrideState: Sendable, Codable, Equatable {
    /// User corrected the AI-classified workout type.
    case classification(original: String, corrected: String)
    /// User manually toggled indoor vs outdoor modality.
    case indoorModality(isIndoor: Bool)
    /// User manually linked or unlinked a prescribed technique drill.
    case drillLinkage(drillId: String, isLinked: Bool)
    /// User reported subjective physical distress.
    case distress(signal: SubjectiveDistressSignal)
    /// User reported Borg CR-10 perceived exertion (1 to 10).
    case ratingOfPerceivedExertion(score: Int)
}

// MARK: - Run Directive (Pacing, Duration, & Safety Bands)

/// Pacing intensity zones governing prescribed workouts.
public enum PacingBand: String, Sendable, Codable, Equatable, CaseIterable {
    /// Active recovery, conversational warmup, or cooldown (Zone 1).
    case zone1Recovery
    /// Aerobic endurance base building, effortless rhythm (Zone 2).
    case zone2AerobicBase
    /// Aerobic progression or marathon tempo surges (Zone 3).
    case zone3TempoSurge
    /// Lactate threshold, sustained hard effort (Zone 4).
    case zone4LactateThreshold
    /// Neuromuscular strides, maximal sprint power (Zone 5).
    case zone5Neuromuscular
}

/// Deterministic pacing, duration, and cadence band directives emitted by the core engine.
/// Fed directly into AI engines as structured domain facts, eliminating hallucinated targets.
public enum RunDirective: Sendable, Codable, Equatable {
    /// Biological safety override: slow pace, low HR cap, priority recovery.
    case easyAerobicRecovery(pacingBand: PacingBand, maxDurationMinutes: Double)
    /// Cadence elevation drill to quicken turnover frequency above 150 SPM or alleviate overstriding.
    case cadencePyramids(targetFloorSPM: Int, targetCeilingSPM: Int, durationMinutes: Double)
    /// Aerobic stability metronome intervals to establish rhythmic turnover.
    case rhythmIntervals(targetSPM: Int, durationMinutes: Double)
    /// Controlled threshold surges for runners with low cardiovascular strain.
    case tempoSurges(pacingBand: PacingBand, durationMinutes: Double)
    /// Short neuromuscular acceleration repetitions reinforcing hip extension and posture.
    case strides(repetitions: Int, targetSPM: Int)
    /// Indoor treadmill turnover adjustment against moving belt friction.
    case treadmillTurnoverCorrection(indoorCadenceFloor: Int)
    /// General aerobic maintenance when telemetry is well-calibrated to baseline.
    case steadyAerobicMaintenance(targetSPM: Int)
    /// Complete rest day or gentle mobility walk following acute cumulative overload.
    case acuteFatigueRestDay

    /// Whether this directive is a deterministic safety override that strips user race goals.
    public var priorityOverridesGoal: Bool {
        switch self {
        case .easyAerobicRecovery, .acuteFatigueRestDay:
            return true
        default:
            return false
        }
    }

    /// The canonical technique drill title associated with this directive, if any.
    public var associatedDrillTitle: String? {
        switch self {
        case .cadencePyramids:
            return "Cadence Pyramids"
        case .rhythmIntervals:
            return "Rhythm Intervals"
        case .tempoSurges:
            return "Tempo Surges"
        case .strides:
            return "Strides"
        case .easyAerobicRecovery, .treadmillTurnoverCorrection, .steadyAerobicMaintenance, .acuteFatigueRestDay:
            return nil
        }
    }
}
