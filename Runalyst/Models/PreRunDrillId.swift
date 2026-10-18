import Foundation
import SwiftUI

/// Duration categories for prescribed corrective drills.
public enum DrillDuration: Int, CaseIterable, Sendable, Codable {
    case fiveMinutes = 5
    case tenMinutes = 10
    case fifteenMinutes = 15
    case thirtyMinutes = 30

    public var title: String {
        "\(rawValue) min"
    }
}

/// Haptic pacing cue mode for drills on Apple Watch.
public enum HapticFeedbackMode: String, CaseIterable, Sendable, Codable {
    case off = "Off"
    case on = "On"
}

/// A lightweight, Sendable Data Transfer Object used to pass AI recommendations
/// into the deterministic WorkoutKit builder.
struct DrillPrescriptionDTO: Sendable, Codable {
    let title: String
    let preRunDrillId: String?
    let purpose: String
    let targetCadence: String?
    let previousCadence: Int?
    var durationMinutes: Int? = 15
    var hapticMode: String? = "On"
    /// `ReadinessState.rawValue` when the prescription was modulated by acute readiness (nil = productive).
    var readinessState: String?
}

/// Represents an active or recent intent to execute a prescribed drill on Apple Watch.
public struct ScheduledDrillIntent: Codable, Sendable, Equatable {
    public let drillTitle: String
    public let preRunDrillId: String?
    public let scheduledDate: Date
    public let durationMinutes: Int
    public let targetCadence: String?
    public var matchedWorkoutID: UUID?

    public init(
        drillTitle: String,
        preRunDrillId: String? = nil,
        scheduledDate: Date = Date(),
        durationMinutes: Int = 15,
        targetCadence: String? = nil,
        matchedWorkoutID: UUID? = nil
    ) {
        let cleanTitle = PreRunDrillId.canonicalDrillTitle(for: drillTitle)
            ?? preRunDrillId.flatMap { PreRunDrillId(rawValue: $0)?.title }
            ?? drillTitle.replacingOccurrences(of: "_", with: " ").capitalized
        self.drillTitle = cleanTitle
        self.preRunDrillId = preRunDrillId
        self.scheduledDate = scheduledDate
        self.durationMinutes = durationMinutes
        self.targetCadence = targetCadence
        self.matchedWorkoutID = matchedWorkoutID
    }
}

/// The core domain enum identifying every pre-run corrective drill in Runalyst.
enum PreRunDrillId: String, CaseIterable, Codable, Sendable {
    case cadencePyramids = "cadence_pyramids"
    case rhythmIntervals = "rhythm_intervals"
    case tempoSurges = "tempo_surges"
    case strides = "strides"
    case neuromuscularPrimer = "neuromuscular_primer"
    case aerobicFlush = "aerobic_flush"
    case fartlekPrimer = "fartlek_primer"
    case hillBounds = "hill_bounds"
    case recoveryJog = "recovery_jog"
    case zone2Run = "zone_2_run"

    init?(rawValue: String) {
        switch rawValue {
        case "cadence_pyramids": self = .cadencePyramids
        case "rhythm_intervals": self = .rhythmIntervals
        case "tempo_surges", "posture_check": self = .tempoSurges
        case "strides": self = .strides
        case "neuromuscular_primer": self = .neuromuscularPrimer
        case "aerobic_flush", "zone_1_recovery_flush", "zone_1_active_recovery_flush", "recovery_flush": self = .aerobicFlush
        case "fartlek_primer": self = .fartlekPrimer
        case "hill_bounds": self = .hillBounds
        case "recovery_jog": self = .recoveryJog
        case "zone_2_run", "zone_2_easy_aerobic_base", "zone_2_easy_aerobic_maintenance", "aerobic_base_builder", "dynamic_activation": self = .zone2Run
        default: return nil
        }
    }

    /// Resolves a drill identifier from natural language or snake_case query string.
    static func resolve(from string: String) -> PreRunDrillId? {
        let clean = string.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
        if let direct = PreRunDrillId(rawValue: clean) {
            return direct
        }
        if clean.contains("recovery_flush") || clean.contains("aerobic_flush") {
            return .aerobicFlush
        }
        if clean.contains("zone_2") || clean.contains("zone2") || clean.contains("aerobic_base") {
            return .zone2Run
        }
        if clean.contains("recovery_jog") {
            return .recoveryJog
        }
        if clean.contains("cadence_pyramid") || clean.contains("pyramid") {
            return .cadencePyramids
        }
        if clean.contains("rhythm") {
            return .rhythmIntervals
        }
        if clean.contains("tempo_surge") || clean.contains("surge") {
            return .tempoSurges
        }
        if clean.contains("stride") {
            return .strides
        }
        if clean.contains("hill_bound") {
            return .hillBounds
        }
        if clean.contains("neuromuscular") || clean.contains("form_primer") {
            return .neuromuscularPrimer
        }
        for drill in PreRunDrillId.allCases {
            if drill.rawValue == clean || drill.title.lowercased() == string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                return drill
            }
        }
        return nil
    }

    var title: String {
        switch self {
        case .cadencePyramids: return "Cadence Pyramids"
        case .rhythmIntervals: return "Rhythm Intervals"
        case .tempoSurges: return "Tempo Surges"
        case .strides: return "Strides"
        case .neuromuscularPrimer: return "Form Primer"
        case .aerobicFlush: return "Aerobic Flush"
        case .fartlekPrimer: return "Fartlek Primer"
        case .hillBounds: return "Hill Bounds"
        case .recoveryJog: return "Recovery Jog"
        case .zone2Run: return "Zone 2 Run"
        }
    }

    /// Default canonical duration for this drill when prescribed or activated
    public var defaultDuration: DrillDuration {
        switch self {
        case .zone2Run, .aerobicFlush, .recoveryJog:
            return .thirtyMinutes
        case .strides:
            return .fifteenMinutes
        case .tempoSurges, .cadencePyramids, .rhythmIntervals, .neuromuscularPrimer, .hillBounds, .fartlekPrimer:
            return .tenMinutes
        }
    }

    /// The standard run classification this drill belongs to.
    var correspondingClassification: String {
        switch self {
        case .rhythmIntervals, .cadencePyramids, .strides:
            return "Intervals"
        case .tempoSurges:
            return "Tempo Run"
        case .recoveryJog, .aerobicFlush:
            return "Recovery Run"
        case .fartlekPrimer:
            return "Fartlek"
        case .hillBounds:
            return "Hill Repeats"
        case .zone2Run:
            return "Easy Run"
        case .neuromuscularPrimer:
            return "Intervals"
        }
    }

    /// Whether this drill's primary coaching target is heart rate zone rather than cadence
    var isHeartRateTargeted: Bool {
        self == .zone2Run || self == .aerobicFlush || self == .recoveryJog
    }

    /// Whether this drill is a continuous single-block aerobic run (not intermittent intervals)
    var isAerobicContinuous: Bool {
        self == .zone2Run || self == .aerobicFlush || self == .recoveryJog
    }

    /// Subtitle describing the intended recovery effort between work intervals.
    var recoveryLabel: String {
        switch self {
        case .tempoSurges:
            return "Tempo Base / Float"
        case .strides, .hillBounds:
            return "Walk / Easy Jog"
        case .cadencePyramids, .rhythmIntervals, .neuromuscularPrimer, .fartlekPrimer:
            return "Easy Jog / Float"
        case .zone2Run, .recoveryJog, .aerobicFlush:
            return "Steady Aerobic"
        }
    }

    /// The target heart rate zone (e.g. Zone 1 or Zone 2)
    var targetHeartRateZone: Int? {
        switch self {
        case .zone2Run:
            return 2
        case .aerobicFlush, .recoveryJog:
            return 1
        default:
            return nil
        }
    }

    /// User-facing name for the target heart rate zone
    var targetHeartRateZoneName: String? {
        switch self {
        case .zone2Run:
            return "Zone 2 (Aerobic)"
        case .aerobicFlush, .recoveryJog:
            return "Zone 1 (Recovery)"
        default:
            return nil
        }
    }

    /// Resolves a specific drill name or raw identifier into an existing standard run classification.
    /// Standard run classifications (e.g. "Intervals", "Tempo Run") return nil because they are classifications, not drills.
    static func correspondingClassification(for drillNameOrId: String) -> String? {
        let clean = drillNameOrId.trimmingCharacters(in: .whitespacesAndNewlines)
        let standardClassifications: Set<String> = [
            "Intervals", "Pyramids", "Tempo Run", "Progression Run", "Recovery Run",
            "Steady Effort", "Easy Run", "Long Run", "Fartlek", "Hill Repeats",
            "Urban Traffic"
        ]
        if standardClassifications.contains(where: { $0.localizedCaseInsensitiveCompare(clean) == .orderedSame }) {
            return nil
        }

        if clean.localizedCaseInsensitiveCompare("posture_check") == .orderedSame ||
           clean.localizedCaseInsensitiveCompare("Posture Check") == .orderedSame {
            return PreRunDrillId.tempoSurges.correspondingClassification
        }
        if clean.localizedCaseInsensitiveCompare("dynamic_activation") == .orderedSame ||
           clean.localizedCaseInsensitiveCompare("Dynamic Activation") == .orderedSame {
            return PreRunDrillId.zone2Run.correspondingClassification
        }

        if let resolved = PreRunDrillId.resolve(from: clean) {
            return resolved.correspondingClassification
        }

        for drill in PreRunDrillId.allCases {
            if drill.rawValue.localizedCaseInsensitiveCompare(clean) == .orderedSame ||
               drill.title.localizedCaseInsensitiveCompare(clean) == .orderedSame {
                return drill.correspondingClassification
            }
        }
        if clean.localizedCaseInsensitiveCompare("aerobic_base_builder") == .orderedSame ||
           clean.localizedCaseInsensitiveCompare("Aerobic Base Builder") == .orderedSame {
            return PreRunDrillId.zone2Run.correspondingClassification
        }
        return nil
    }

    /// Normalizes a specific drill identifier or title into its canonical user-facing drill title (e.g. "rhythm_intervals" -> "Rhythm Intervals").
    /// Standard run classifications return nil.
    static func canonicalDrillTitle(for drillNameOrId: String) -> String? {
        let clean = drillNameOrId.trimmingCharacters(in: .whitespacesAndNewlines)
        let standardClassifications: Set<String> = [
            "Intervals", "Pyramids", "Tempo Run", "Progression Run", "Recovery Run",
            "Steady Effort", "Easy Run", "Long Run", "Fartlek", "Hill Repeats",
            "Urban Traffic"
        ]
        if standardClassifications.contains(where: { $0.localizedCaseInsensitiveCompare(clean) == .orderedSame }) {
            return nil
        }

        if clean.localizedCaseInsensitiveCompare("posture_check") == .orderedSame ||
           clean.localizedCaseInsensitiveCompare("Posture Check") == .orderedSame {
            return "Posture Check"
        }
        if clean.localizedCaseInsensitiveCompare("dynamic_activation") == .orderedSame ||
           clean.localizedCaseInsensitiveCompare("Dynamic Activation") == .orderedSame {
            return "Dynamic Activation"
        }

        if clean.localizedCaseInsensitiveCompare("zone_1_active_recovery_flush") == .orderedSame ||
           clean.localizedCaseInsensitiveCompare("Zone 1 Active Recovery Flush") == .orderedSame ||
           clean.localizedCaseInsensitiveCompare("zone_1_recovery_flush") == .orderedSame ||
           clean.localizedCaseInsensitiveCompare("Zone 1 Recovery Flush") == .orderedSame {
            return "Zone 1 Recovery Flush"
        }
        if clean.localizedCaseInsensitiveCompare("zone_2_easy_aerobic_base") == .orderedSame ||
           clean.localizedCaseInsensitiveCompare("Zone 2 Easy Aerobic Base") == .orderedSame ||
           clean.localizedCaseInsensitiveCompare("zone_2_easy_aerobic_maintenance") == .orderedSame ||
           clean.localizedCaseInsensitiveCompare("Zone 2 Easy Aerobic Maintenance") == .orderedSame {
            return "Zone 2 Run"
        }

        if let resolved = PreRunDrillId.resolve(from: clean) {
            return resolved.title
        }

        for drill in PreRunDrillId.allCases {
            if drill.rawValue.localizedCaseInsensitiveCompare(clean) == .orderedSame ||
               drill.title.localizedCaseInsensitiveCompare(clean) == .orderedSame {
                return drill.title
            }
        }
        if clean.localizedCaseInsensitiveCompare("aerobic_base_builder") == .orderedSame ||
           clean.localizedCaseInsensitiveCompare("Aerobic Base Builder") == .orderedSame {
            return PreRunDrillId.zone2Run.title
        }
        return nil
    }

    var iconName: String {
        switch self {
        case .cadencePyramids:
            return "shoeprints.fill"
        case .rhythmIntervals:
            return "clock.fill"
        case .tempoSurges:
            return "bolt.fill"
        case .strides:
            return "figure.run"
        case .neuromuscularPrimer:
            return "sparkles"
        case .aerobicFlush, .recoveryJog:
            return "lungs.fill"
        case .fartlekPrimer:
            return "waveform.path.ecg"
        case .hillBounds:
            return "mountain.2.fill"
        case .zone2Run:
            return "heart.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .cadencePyramids:
            return .blue
        case .rhythmIntervals:
            return .purple
        case .tempoSurges:
            return .orange
        case .strides:
            return .green
        case .neuromuscularPrimer:
            return .indigo
        case .aerobicFlush:
            return .teal
        case .fartlekPrimer:
            return .pink
        case .hillBounds:
            return .brown
        case .recoveryJog:
            return .mint
        case .zone2Run:
            return .red
        }
    }
}
