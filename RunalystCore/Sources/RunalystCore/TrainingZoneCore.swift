import Foundation

/// Tri-state daily training intent resolving semantic ambiguity between full recovery, active recovery flush, and structured progression.
public enum DailySessionIntent: String, Sendable, Codable, Equatable, CaseIterable {
    /// Zero running prescribed. Complete structural rest, passive recovery, mobility, or walking only.
    case fullRest = "fullRest"
    /// Short 15–20 minute Zone 1 active recovery flush to clear metabolic fatigue.
    case recoveryFlush = "recoveryFlush"
    /// Normal structured microcycle progression according to the runner's training phase.
    case train = "train"
}

/// Pure mathematical model for 5-zone cardiovascular and mechanical pacing targets.
///
/// Designed to execute with zero I/O and zero framework dependencies.
public struct PaceRange: Sendable, Equatable {
    public let lowSecPerKm: Double
    public let highSecPerKm: Double

    public init(lowSecPerKm: Double, highSecPerKm: Double) {
        self.lowSecPerKm = lowSecPerKm
        self.highSecPerKm = highSecPerKm
    }

    /// Formats the pace range string in either min/km or min/mi.
    public func formatted(useMetric: Bool) -> String {
        let low = Int(lowSecPerKm.rounded())
        let high = Int(highSecPerKm.rounded())
        let p1M = low / 60
        let p1S = low % 60
        let p2M = high / 60
        let p2S = high % 60

        if useMetric {
            return String(format: "%d:%02d–%d:%02d/km", p1M, p1S, p2M, p2S)
        } else {
            let lowMi = Int((lowSecPerKm * 1.609344).rounded())
            let highMi = Int((highSecPerKm * 1.609344).rounded())
            let mi1M = lowMi / 60
            let mi1S = lowMi % 60
            let mi2M = highMi / 60
            let mi2S = highMi % 60
            return String(format: "%d:%02d–%d:%02d/mi", mi1M, mi1S, mi2M, mi2S)
        }
    }
}

/// The definitive 5-zone pacing matrix computed deterministically from an anchor pace.
public struct TrainingZoneMatrix: Sendable, Equatable {
    public let zone1Recovery: PaceRange
    public let zone2AerobicBase: PaceRange
    public let zone3Steady: PaceRange
    public let zone4Threshold: PaceRange
    public let zone5Interval: PaceRange

    public init(
        zone1Recovery: PaceRange,
        zone2AerobicBase: PaceRange,
        zone3Steady: PaceRange,
        zone4Threshold: PaceRange,
        zone5Interval: PaceRange
    ) {
        self.zone1Recovery = zone1Recovery
        self.zone2AerobicBase = zone2AerobicBase
        self.zone3Steady = zone3Steady
        self.zone4Threshold = zone4Threshold
        self.zone5Interval = zone5Interval
    }
}

/// Stateless biomechanical calculation engine for physiological pacing zones.
public enum TrainingZoneCore {

    /// Computes full 5-zone pacing matrix from an anchor pace (in seconds per kilometer).
    public static func calculateZones(anchorPaceSecPerKm: Double, activeGoal: String) -> TrainingZoneMatrix {
        let z1 = PaceRange(
            lowSecPerKm: anchorPaceSecPerKm + 60.0,
            highSecPerKm: anchorPaceSecPerKm + 90.0
        )
        let z2 = PaceRange(
            lowSecPerKm: anchorPaceSecPerKm + 30.0,
            highSecPerKm: anchorPaceSecPerKm + 50.0
        )
        let z3 = PaceRange(
            lowSecPerKm: anchorPaceSecPerKm + 10.0,
            highSecPerKm: anchorPaceSecPerKm + 25.0
        )
        let z4 = PaceRange(
            lowSecPerKm: max(180.0, anchorPaceSecPerKm - 10.0),
            highSecPerKm: anchorPaceSecPerKm + 5.0
        )

        // Goal-specific Zone 5 neuromuscular offset
        let z5Low: Double
        let z5High: Double
        if activeGoal.contains("5K") {
            z5Low = max(150.0, anchorPaceSecPerKm - 30.0)
            z5High = max(160.0, anchorPaceSecPerKm - 20.0)
        } else if activeGoal.contains("10K") {
            z5Low = max(160.0, anchorPaceSecPerKm - 20.0)
            z5High = max(170.0, anchorPaceSecPerKm - 10.0)
        } else if activeGoal.contains("Half") {
            z5Low = max(170.0, anchorPaceSecPerKm - 10.0)
            z5High = anchorPaceSecPerKm
        } else {
            z5Low = max(180.0, anchorPaceSecPerKm - 5.0)
            z5High = anchorPaceSecPerKm + 10.0
        }

        let z5 = PaceRange(lowSecPerKm: z5Low, highSecPerKm: z5High)

        return TrainingZoneMatrix(
            zone1Recovery: z1,
            zone2AerobicBase: z2,
            zone3Steady: z3,
            zone4Threshold: z4,
            zone5Interval: z5
        )
    }

    /// Provides cold-start baseline anchor paces by athletic tier.
    public static func defaultPaceForExperience(_ level: String) -> Double {
        if level.contains("Elite") {
            return 255.0 // ~4:15/km
        } else if level.contains("Advanced") || level.contains("Veteran") {
            return 290.0 // ~4:50/km
        } else if level.contains("Intermediate") || level.contains("Enthusiast") {
            return 340.0 // ~5:40/km
        } else {
            return 400.0 // ~6:40/km (Novice)
        }
    }

    /// Direct formatting utility for arbitrary pace ranges.
    public static func formatRange(lowSec: Double, highSec: Double, useMetric: Bool) -> String {
        PaceRange(lowSecPerKm: lowSec, highSecPerKm: highSec).formatted(useMetric: useMetric)
    }
}
