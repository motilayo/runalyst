import Foundation

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
