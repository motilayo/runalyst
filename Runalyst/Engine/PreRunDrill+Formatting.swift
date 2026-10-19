import Foundation
import SwiftUI

extension PreRunDrill {
    static func iconName(for drillId: String?, title: String? = nil) -> String {
        if let idStr = drillId, let matched = PreRunDrillId(rawValue: idStr) {
            return matched.iconName
        }
        let lower = (title ?? drillId ?? "").lowercased()
        if lower.contains("cadence") {
            return "shoeprints.fill"
        } else if lower.contains("interval") || lower.contains("rhythm") || lower.contains("clock") {
            return "clock.fill"
        } else if lower.contains("surge") || lower.contains("tempo") {
            return "bolt.fill"
        } else if lower.contains("stride") {
            return "figure.run"
        } else if lower.contains("hill") || lower.contains("bound") {
            return "mountain.2.fill"
        } else if lower.contains("flush") || lower.contains("aerobic") {
            return "lungs.fill"
        } else if lower.contains("zone 2") || lower.contains("zone2") || lower.contains("base builder") {
            return "heart.fill"
        } else if lower.contains("recovery") || lower.contains("jog") || lower.contains("shakeout") {
            return "figure.walk"
        } else if lower.contains("fartlek") {
            return "waveform.path.ecg"
        } else if lower.contains("neuro") {
            return "brain.head.profile"
        }
        return "shoeprints.fill"
    }

    static func iconColor(for drillId: String?, title: String? = nil) -> Color {
        if let idStr = drillId, let matched = PreRunDrillId(rawValue: idStr) {
            return matched.iconColor
        }
        let lower = (title ?? drillId ?? "").lowercased()
        if lower.contains("cadence") {
            return .blue
        } else if lower.contains("interval") || lower.contains("rhythm") {
            return .purple
        } else if lower.contains("surge") || lower.contains("tempo") {
            return .orange
        } else if lower.contains("stride") {
            return .green
        } else if lower.contains("hill") || lower.contains("bound") {
            return .brown
        } else if lower.contains("flush") {
            return .teal
        } else if lower.contains("zone 2") || lower.contains("zone2") || lower.contains("base builder") {
            return .red
        } else if lower.contains("recovery") || lower.contains("jog") || lower.contains("shakeout") {
            return .mint
        } else if lower.contains("fartlek") {
            return .pink
        } else if lower.contains("neuro") {
            return .indigo
        }
        return .orange
    }

    func workString(for customDuration: DrillDuration) -> String {
        switch id {
        case .cadencePyramids:
            switch customDuration {
            case .fiveMinutes: return "3 x 20 sec work"
            case .tenMinutes: return "4 x 30 sec work"
            case .fifteenMinutes: return "4 x 1 min work"
            case .thirtyMinutes, .fortyMinutes, .fiftyMinutes: return "6 x 90 sec work"
            }
        case .rhythmIntervals:
            switch customDuration {
            case .fiveMinutes: return "3 x 20 sec work"
            case .tenMinutes: return "4 x 30 sec work"
            case .fifteenMinutes: return "5 x 45 sec work"
            case .thirtyMinutes, .fortyMinutes, .fiftyMinutes: return "6 x 90 sec work"
            }
        case .tempoSurges:
            switch customDuration {
            case .fiveMinutes: return "3 x 30 sec work"
            case .tenMinutes: return "5 x 30 sec work"
            case .fifteenMinutes: return "3 x 2 min work"
            case .thirtyMinutes, .fortyMinutes, .fiftyMinutes: return "4 x 3 min work"
            }
        case .strides:
            switch customDuration {
            case .fiveMinutes: return "4 x 15 sec strides"
            case .tenMinutes: return "4 x 15 sec strides"
            case .fifteenMinutes: return "6 x 20 sec strides"
            case .thirtyMinutes, .fortyMinutes, .fiftyMinutes: return "8 x 30 sec strides"
            }
        case .neuromuscularPrimer:
            switch customDuration {
            case .fiveMinutes: return "3 x 15 sec work"
            case .tenMinutes: return "4 x 20 sec work"
            case .fifteenMinutes: return "5 x 30 sec work"
            case .thirtyMinutes, .fortyMinutes, .fiftyMinutes: return "6 x 45 sec work"
            }
        case .aerobicFlush:
            return "\(customDuration.rawValue) min steady"
        case .fartlekPrimer:
            switch customDuration {
            case .fiveMinutes: return "3 x 30 sec work"
            case .tenMinutes: return "4 x 45 sec work"
            case .fifteenMinutes: return "5 x 1 min work"
            case .thirtyMinutes, .fortyMinutes, .fiftyMinutes: return "6 x 2 min work"
            }
        case .hillBounds:
            switch customDuration {
            case .fiveMinutes: return "3 x 15 sec work"
            case .tenMinutes: return "4 x 20 sec work"
            case .fifteenMinutes: return "5 x 30 sec work"
            case .thirtyMinutes, .fortyMinutes, .fiftyMinutes: return "6 x 45 sec work"
            }
        case .recoveryJog:
            return "\(customDuration.rawValue) min easy"
        case .zone2Run:
            return "\(customDuration.rawValue) min Zone 2 steady"
        }
    }

    func recoveryString(for customDuration: DrillDuration) -> String {
        switch id {
        case .cadencePyramids:
            switch customDuration {
            case .fiveMinutes: return "30 sec walk recovery"
            case .tenMinutes: return "45 sec walk recovery"
            case .fifteenMinutes: return "90 sec walk recovery"
            case .thirtyMinutes, .fortyMinutes, .fiftyMinutes: return "2 min walk recovery"
            }
        case .rhythmIntervals:
            switch customDuration {
            case .fiveMinutes: return "30 sec easy jog recovery"
            case .tenMinutes: return "45 sec easy jog recovery"
            case .fifteenMinutes: return "75 sec easy jog recovery"
            case .thirtyMinutes, .fortyMinutes, .fiftyMinutes: return "2 min easy jog recovery"
            }
        case .tempoSurges:
            switch customDuration {
            case .fiveMinutes: return "45 sec walk recovery"
            case .tenMinutes: return "60 sec walk recovery"
            case .fifteenMinutes: return "2 min walk recovery"
            case .thirtyMinutes, .fortyMinutes, .fiftyMinutes: return "3 min walk recovery"
            }
        case .strides:
            switch customDuration {
            case .fiveMinutes: return "45 sec walk recovery"
            case .tenMinutes: return "45 sec walk recovery"
            case .fifteenMinutes: return "60 sec walk recovery"
            case .thirtyMinutes, .fortyMinutes, .fiftyMinutes: return "90 sec walk recovery"
            }
        case .neuromuscularPrimer:
            switch customDuration {
            case .fiveMinutes: return "30 sec walk recovery"
            case .tenMinutes: return "40 sec walk recovery"
            case .fifteenMinutes: return "60 sec walk recovery"
            case .thirtyMinutes, .fortyMinutes, .fiftyMinutes: return "90 sec walk recovery"
            }
        case .aerobicFlush:
            return "No intervals"
        case .fartlekPrimer:
            switch customDuration {
            case .fiveMinutes: return "30 sec easy recovery"
            case .tenMinutes: return "45 sec easy recovery"
            case .fifteenMinutes: return "1 min easy recovery"
            case .thirtyMinutes, .fortyMinutes, .fiftyMinutes: return "2 min easy recovery"
            }
        case .hillBounds:
            switch customDuration {
            case .fiveMinutes: return "30 sec walk recovery"
            case .tenMinutes: return "40 sec walk recovery"
            case .fifteenMinutes: return "60 sec walk recovery"
            case .thirtyMinutes, .fortyMinutes, .fiftyMinutes: return "90 sec walk recovery"
            }
        case .recoveryJog:
            return "No intervals"
        case .zone2Run:
            return "No intervals"
        }
    }

    var defaultWorkString: String {
        let base = workString(for: duration)
        guard let adapted = readinessAdjustedIntervalSpec else { return base }
        let suffix = base.split(separator: " ").dropFirst(4).joined(separator: " ")
        return "\(adapted.iterations) x \(Self.formatShortDuration(adapted.workSeconds)) \(suffix)"
    }

    var defaultRecoveryString: String {
        let base = recoveryString(for: duration)
        guard let adapted = readinessAdjustedIntervalSpec, let recovery = adapted.recoverySeconds else { return base }
        let suffix = base.split(separator: " ").dropFirst(2).joined(separator: " ")
        return "\(Self.formatShortDuration(recovery)) \(suffix)"
    }

    static func formatShortDuration(_ seconds: Int) -> String {
        if seconds >= 120 && seconds % 60 == 0 {
            return "\(seconds / 60) min"
        }
        return "\(seconds) sec"
    }

    var defaultEffortString: String {
        switch id {
        case .recoveryJog, .aerobicFlush: return "Zone 1 Active Recovery"
        case .zone2Run: return "Zone 2 Aerobic"
        case .cadencePyramids, .rhythmIntervals: return "Moderate / Zone 3"
        case .tempoSurges, .fartlekPrimer: return "Hard / Zone 4"
        case .strides, .neuromuscularPrimer, .hillBounds: return "Sprint / Zone 5"
        }
    }
}
