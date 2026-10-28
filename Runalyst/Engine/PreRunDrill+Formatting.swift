import Foundation
import SwiftUI

extension PreRunDrill {
    static func iconName(for drillId: String?, title: String? = nil) -> String {
        if let idStr = drillId, let matched = PreRunDrillId(rawValue: idStr) {
            return matched.iconName
        }
        let lower = (title ?? drillId ?? "").lowercased()
        if lower.contains("cadence") || lower.contains("pyramid") {
            return RunalystIcon.cadencePyramids
        } else if lower.contains("interval") || lower.contains("rhythm") || lower.contains("clock") {
            return "clock.arrow.circlepath"
        } else if lower.contains("surge") || lower.contains("tempo") {
            return "flame.fill"
        } else if lower.contains("stride") {
            return "bolt.horizontal.fill"
        } else if lower.contains("hill") || lower.contains("bound") {
            return "mountain.2.fill"
        } else if lower.contains("flush") || lower.contains("aerobic") {
            return "lungs.fill"
        } else if lower.contains("zone 2") || lower.contains("zone2") || lower.contains("base builder") {
            return "heart.fill"
        } else if lower.contains("recovery") || lower.contains("jog") || lower.contains("shakeout") {
            return "lungs.fill"
        } else if lower.contains("fartlek") {
            return "waveform.path.ecg"
        } else if lower.contains("neuro") {
            return "sparkles"
        }
        return RunalystIcon.cadencePyramids
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
            case .twentyMinutes: return "4 x 90 sec work"
            case .thirtyMinutes, .thirtyFiveMinutes, .fortyMinutes, .fiftyMinutes: return "6 x 90 sec work"
            }
        case .rhythmIntervals:
            switch customDuration {
            case .fiveMinutes: return "3 x 20 sec work"
            case .tenMinutes: return "4 x 30 sec work"
            case .fifteenMinutes: return "5 x 45 sec work"
            case .twentyMinutes: return "6 x 45 sec work"
            case .thirtyMinutes, .thirtyFiveMinutes, .fortyMinutes, .fiftyMinutes: return "6 x 90 sec work"
            }
        case .tempoSurges:
            switch customDuration {
            case .fiveMinutes: return "3 x 30 sec work"
            case .tenMinutes: return "5 x 30 sec work"
            case .fifteenMinutes: return "3 x 2 min work"
            case .twentyMinutes: return "4 x 90 sec work"
            case .thirtyMinutes, .thirtyFiveMinutes, .fortyMinutes, .fiftyMinutes: return "4 x 3 min work"
            }
        case .strides:
            switch customDuration {
            case .fiveMinutes: return "4 x 15 sec strides"
            case .tenMinutes: return "4 x 15 sec strides"
            case .fifteenMinutes: return "6 x 20 sec strides"
            case .twentyMinutes, .thirtyMinutes, .thirtyFiveMinutes, .fortyMinutes, .fiftyMinutes: return "8 x 30 sec strides"
            }
        case .neuromuscularPrimer:
            switch customDuration {
            case .fiveMinutes: return "3 x 15 sec work"
            case .tenMinutes: return "4 x 20 sec work"
            case .fifteenMinutes: return "5 x 30 sec work"
            case .twentyMinutes, .thirtyMinutes, .thirtyFiveMinutes, .fortyMinutes, .fiftyMinutes: return "6 x 45 sec work"
            }
        case .aerobicFlush:
            return "\(customDuration.rawValue) min steady"
        case .fartlekPrimer:
            switch customDuration {
            case .fiveMinutes: return "3 x 30 sec work"
            case .tenMinutes: return "4 x 45 sec work"
            case .fifteenMinutes: return "5 x 1 min work"
            case .twentyMinutes: return "6 x 1 min work"
            case .thirtyMinutes, .thirtyFiveMinutes, .fortyMinutes, .fiftyMinutes: return "6 x 2 min work"
            }
        case .hillBounds:
            switch customDuration {
            case .fiveMinutes: return "3 x 15 sec work"
            case .tenMinutes: return "4 x 20 sec work"
            case .fifteenMinutes: return "5 x 30 sec work"
            case .twentyMinutes, .thirtyMinutes, .thirtyFiveMinutes, .fortyMinutes, .fiftyMinutes: return "6 x 45 sec work"
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
            case .twentyMinutes: return "90 sec walk recovery"
            case .thirtyMinutes, .thirtyFiveMinutes, .fortyMinutes, .fiftyMinutes: return "2 min walk recovery"
            }
        case .rhythmIntervals:
            switch customDuration {
            case .fiveMinutes: return "30 sec easy jog recovery"
            case .tenMinutes: return "45 sec easy jog recovery"
            case .fifteenMinutes: return "75 sec easy jog recovery"
            case .twentyMinutes: return "75 sec easy jog recovery"
            case .thirtyMinutes, .thirtyFiveMinutes, .fortyMinutes, .fiftyMinutes: return "2 min easy jog recovery"
            }
        case .tempoSurges:
            switch customDuration {
            case .fiveMinutes: return "45 sec walk recovery"
            case .tenMinutes: return "60 sec walk recovery"
            case .fifteenMinutes: return "2 min walk recovery"
            case .twentyMinutes: return "2 min walk recovery"
            case .thirtyMinutes, .thirtyFiveMinutes, .fortyMinutes, .fiftyMinutes: return "3 min walk recovery"
            }
        case .strides:
            switch customDuration {
            case .fiveMinutes: return "45 sec walk recovery"
            case .tenMinutes: return "45 sec walk recovery"
            case .fifteenMinutes: return "60 sec walk recovery"
            case .twentyMinutes, .thirtyMinutes, .thirtyFiveMinutes, .fortyMinutes, .fiftyMinutes: return "90 sec walk recovery"
            }
        case .neuromuscularPrimer:
            switch customDuration {
            case .fiveMinutes: return "30 sec walk recovery"
            case .tenMinutes: return "40 sec walk recovery"
            case .fifteenMinutes: return "60 sec walk recovery"
            case .twentyMinutes, .thirtyMinutes, .thirtyFiveMinutes, .fortyMinutes, .fiftyMinutes: return "90 sec walk recovery"
            }
        case .aerobicFlush:
            return "No intervals"
        case .fartlekPrimer:
            switch customDuration {
            case .fiveMinutes: return "30 sec easy recovery"
            case .tenMinutes: return "45 sec easy recovery"
            case .fifteenMinutes: return "1 min easy recovery"
            case .twentyMinutes: return "1 min easy recovery"
            case .thirtyMinutes, .thirtyFiveMinutes, .fortyMinutes, .fiftyMinutes: return "2 min easy recovery"
            }
        case .hillBounds:
            switch customDuration {
            case .fiveMinutes: return "30 sec walk recovery"
            case .tenMinutes: return "40 sec walk recovery"
            case .fifteenMinutes: return "60 sec walk recovery"
            case .twentyMinutes, .thirtyMinutes, .thirtyFiveMinutes, .fortyMinutes, .fiftyMinutes: return "90 sec walk recovery"
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

    /// Structured plain-English phase summary line (e.g. "5m in • 20m steady • 5m out" or "2m in • 4x (30s / 45s) • 3m out").
    var structureSummary: String {
        let phases = generatePhases()
        let warmup = phases.first(where: { $0.kind == .warmup })?.durationSeconds ?? 0
        let cooldown = phases.first(where: { $0.kind == .cooldown })?.durationSeconds ?? 0
        let workReps = phases.filter { $0.kind == .work }
        let repCount = workReps.count
        let repWorkDuration = workReps.first?.durationSeconds ?? 0
        let repRecDuration = phases.first(where: { if case .recovery = $0.kind { return true } else { return false } })?.durationSeconds ?? 0

        var parts: [String] = []
        if warmup > 0 { parts.append("\(warmup / 60)m in") }
        if repCount > 0 {
            if repRecDuration > 0 {
                parts.append("\(repCount)x (\(repWorkDuration)s / \(repRecDuration)s)")
            } else {
                parts.append("\(repCount)x \(repWorkDuration)s")
            }
        } else if let steadyPhase = phases.first(where: { $0.kind == .steady }) {
            let steadyMinutes = steadyPhase.durationSeconds / 60
            parts.append("\(steadyMinutes)m steady")
        }
        if cooldown > 0 { parts.append("\(cooldown / 60)m out") }
        return parts.joined(separator: " • ")
    }

    /// Punchy work representation suitable for compact 2x2 metric cells (e.g. "4x 30s", "Zone 2 Base").
    var shortWorkSummary: String {
        let spec = intervalSpec
        if spec.iterations > 1 {
            return "\(spec.iterations)x \(spec.workSeconds)s"
        } else {
            if id == .zone2Run {
                return "Zone 2 Base"
            } else if id == .aerobicFlush || id == .recoveryJog {
                return "Zone 1 Flush"
            }
            return "\(spec.workSeconds / 60)m steady"
        }
    }

    /// Punchy recovery representation suitable for compact 2x2 metric cells (e.g. "45s Jog", "45s Walk", "Continuous").
    var shortRecoverySummary: String {
        let spec = intervalSpec
        if let rec = spec.recoverySeconds {
            return "\(rec)s \(spec.isWalk ? "Walk" : "Jog")"
        } else {
            return "Continuous"
        }
    }
}
