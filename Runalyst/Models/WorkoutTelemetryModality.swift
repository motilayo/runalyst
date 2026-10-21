import Foundation

/// Defines the primary telemetry visualization modality for a workout.
enum WorkoutTelemetryModality: String, CaseIterable, Identifiable, Sendable {
    case heartRate = "Heart Rate"
    case cadence = "Cadence Rhythm"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .heartRate: return "heart.fill"
        case .cadence: return "metronome.fill"
        }
    }
}

/// Deterministically resolves the primary visualization modality based on workout classification,
/// linked drill intent, and biological sensor confidence.
enum WorkoutTelemetryModalityResolver {
    /// Determines the default hero visualization for a given run record.
    ///
    /// - Aerobic Workouts (Zone 2, Easy Runs, Long Runs, Recovery Runs, Steady Effort, or continuous aerobic drills)
    ///   route primarily to `.heartRate` to highlight Zone 2/3 thresholds and cardiac stability.
    /// - Technique Drills & Intervals (Cadence Pyramids, Rhythm Intervals, Fartlek, Tempo Surges, Strides, Intervals)
    ///   route primarily to `.cadence` to highlight interval spikes, turnover discipline, and cadence floor defense.
    /// - Graceful Fallback: If heart rate data is unavailable (or marked low sensor confidence), falls back to `.cadence`.
    static func defaultModality(for run: RunRecord) -> WorkoutTelemetryModality {
        // Fallback: If heart rate data is absent or sensor confidence is low, fall back to Cadence
        guard run.workingAvgHeartRate > 0 && !run.isHeartRateSensorLowConfidence else {
            return .cadence
        }

        // If explicitly linked to a non-continuous technique drill (like Cadence Pyramids or Strides), cadence is hero
        if let drillName = run.prescribedDrillName,
           let drillId = PreRunDrillId.resolve(from: drillName),
           !drillId.isAerobicContinuous {
            return .cadence
        }

        // Check if detected type or drill tag is aerobic continuous
        let type = run.detectedTypeRaw
        let isAerobicType = type == "Recovery Run"
            || type == "Easy Run"
            || type == "Steady Effort"
            || type == "Zone 2"
            || type == "Long Run"
            || (PreRunDrillId.resolve(from: type)?.isAerobicContinuous == true)

        if isAerobicType {
            return .heartRate
        }

        // Check tags for continuous aerobic drills (e.g. "drill:Zone 2 Run")
        if let drillTag = run.framboiseTags.first(where: { $0.hasPrefix("drill:") }) {
            let drillCandidate = String(drillTag.dropFirst(6))
            if let drillId = PreRunDrillId.resolve(from: drillCandidate), drillId.isAerobicContinuous {
                return .heartRate
            }
        }

        return .cadence
    }
}
