import SwiftUI

/// Centralized canonical iconography and subconscious color tokens for Runalyst.
/// Adheres strictly to the Runalyst Design System:
/// - Heart Rate: Neon Pink
/// - Pace: Electric Blue
/// - Cadence: Vibrant Green
/// - Indoor Environment: Treadmill (figure.run.treadmill)
/// - Outdoor Environment: Open Road (road.lanes)
public enum RunalystIcon {
    // Environments
    public static let indoor = "figure.run.treadmill"
    public static let outdoor = "road.lanes"

    // Biometrics
    public static let heartRate = "heart.fill"
    public static let pace = "speedometer"
    public static let cadence = "metronome.fill"
    public static let verticalOscillation = "arrow.up.and.down"
    public static let groundContactTime = "timer"
    public static let strideLength = "arrow.left.and.right"
    public static let efficiencyFactor = "chart.line.uptrend.xyaxis"
    public static let vo2Max = "lungs.fill"

    // Workouts & Drills
    public static let strides = "bolt.horizontal.fill"
    public static let cadencePyramids = "pyramid.fill"
    public static let rhythmIntervals = "clock.arrow.circlepath"
    public static let tempoSurges = "flame.fill"
    public static let aerobicFlush = "lungs.fill"
    public static let recoveryJog = "lungs.fill"
    public static let neuromuscularPrimer = "sparkles"
    public static let fartlekPrimer = "waveform.path.ecg"
    public static let hillBounds = "mountain.2.fill"
    public static let zone2Run = "heart.fill"

    // Navigation & Coaching
    public static let coach = "bubble.left.and.bubble.right.fill"
    public static let glassBoxInfo = "info.circle"

    /// Returns the canonical icon for any workout classification string.
    public static func forClassification(_ classification: String, isIndoor: Bool = false) -> String {
        if isIndoor { return indoor }
        switch classification {
        case "Easy Run", "Steady Effort":
            return outdoor
        case "Tempo Run":
            return tempoSurges
        case "Intervals":
            return rhythmIntervals
        case "Long Run":
            return outdoor
        case "Progression Run":
            return efficiencyFactor
        case "Recovery Run":
            return aerobicFlush
        case "Hill Repeats":
            return hillBounds
        case "Fartlek":
            return fartlekPrimer
        default:
            return outdoor
        }
    }
}

public enum RunalystColor {
    // Subconscious Data-Binding Color Tokens
    public static let heartRate = Color(red: 1.0, green: 0.18, blue: 0.33) // Neon Pink #FF2D55
    public static let pace = Color(red: 0.0, green: 0.48, blue: 1.0)       // Electric Blue #007AFF
    public static let cadence = Color(red: 0.20, green: 0.78, blue: 0.35)  // Vibrant Green #34C759
    public static let coach = Color(red: 0.69, green: 0.32, blue: 0.87)    // Violet #AF52DE
    public static let indoor = Color(red: 0.0, green: 0.48, blue: 1.0)     // Electric Blue
    public static let outdoor = Color(red: 0.20, green: 0.78, blue: 0.35)   // Vibrant Green
    public static let warning = Color.orange
    public static let hills = Color(red: 0.64, green: 0.52, blue: 0.37)    // Brown

    /// Returns the canonical color for any workout classification string.
    public static func forClassification(_ classification: String, isIndoor: Bool = false) -> Color {
        if isIndoor { return indoor }
        switch classification {
        case "Easy Run":
            return Color(red: 0.0, green: 0.72, blue: 0.55)
        case "Steady Effort":
            return pace
        case "Tempo Run":
            return warning
        case "Intervals":
            return coach
        case "Long Run":
            return Color.indigo
        case "Progression Run":
            return Color.teal
        case "Recovery Run":
            return Color.mint
        case "Hill Repeats":
            return hills
        case "Fartlek":
            return Color.pink
        default:
            return pace
        }
    }
}
