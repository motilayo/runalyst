import Foundation
import SwiftUI

/// Represents a discrete phase of a pre-run workout/drill for visual timeline mapping.
struct WorkoutPhase: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let durationSeconds: Int
    let kind: Kind

    enum Kind: Sendable, Equatable {
        case warmup
        case work
        case recovery(isWalk: Bool)
        case cooldown
        case steady

        /// Canonical unified color palette across all workout phase views.
        /// Carefully tuned for high-contrast visibility in both light mode and dark mode.
        var color: Color {
            switch self {
            case .warmup:
                // Mint Green - matches Apple Health and high contrast in dark/light mode
                return Color(red: 0.0, green: 0.80, blue: 0.65)
            case .work:
                // Vivid Orange - high energy effort intervals
                return Color(red: 1.0, green: 0.58, blue: 0.0)
            case .recovery:
                // Sky Cyan - bright, fresh, high contrast, replaces washed-out gray
                return Color(red: 0.20, green: 0.72, blue: 0.92)
            case .steady:
                // Electric Blue - canonical Apple pace / Zone 2 aerobic steady running
                return Color(red: 0.0, green: 0.55, blue: 1.0)
            case .cooldown:
                // Royal Purple - cooling down / flush
                return Color(red: 0.68, green: 0.35, blue: 0.90)
            }
        }
    }

    var formattedDuration: String {
        if durationSeconds >= 60 {
            let minutes = durationSeconds / 60
            let seconds = durationSeconds % 60
            if seconds == 0 {
                return "\(minutes)m"
            } else {
                return "\(minutes)m \(seconds)s"
            }
        } else {
            return "\(durationSeconds)s"
        }
    }
}

/// The repeating interval geometry of a drill (reps × work / recovery).
struct IntervalSpec: Sendable, Equatable {
    let iterations: Int
    let workSeconds: Int
    let recoverySeconds: Int?
    let isWalk: Bool
}
