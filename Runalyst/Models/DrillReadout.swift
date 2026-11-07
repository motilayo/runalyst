import Foundation
import SwiftUI
import WorkoutKit
import RunalystCore

/// Structured, human-readable readout bridging the gap between the static dashboard
/// and the active WorkoutKit session on Apple Watch.
///
/// Provides mental preparation for the runner before the Apple Watch takes over their wrist
/// with haptic taps and timers, translating complex WorkoutKit phase data into plain English
/// and visual geometry across three conversational pillars:
/// 1. The Overview
/// 2. The Breakdown (accompanied by the visual geometry timeline)
/// 3. The Coaching Tip
struct DrillReadout: Sendable, Identifiable {
    var id: String { "\(drillId.rawValue)-\(durationMinutes)" }
    let drillId: PreRunDrillId
    let title: String
    let subtitle: String
    let overview: String
    let breakdown: String
    let coachingTip: String
    let phases: [WorkoutPhase]
    let durationMinutes: Int
    let targetCadence: String?
    let targetZone: String?

    // MARK: Readiness Modifier (ACWR)
    /// Acute readiness state applied to this prescription.
    var readinessState: ReadinessState = .productive
    /// The standard 30-day personalized target before readiness modulation.
    var standardTargetCadence: String?
    /// Standard vs adapted work/recovery labels (e.g. "6 x 20 sec strides" -> "3 x 20 sec strides").
    var standardWork: String?
    var adaptedWork: String?
    var standardRecovery: String?
    var adaptedRecovery: String?
    /// Deterministic coach explanation of why today's drill was adapted.
    var readinessContext: String?

    var isReadinessAdjusted: Bool {
        readinessState != .productive && readinessContext != nil
    }

    var totalDurationSeconds: Int {
        phases.map(\.durationSeconds).reduce(0, +)
    }

    var formattedDuration: String {
        let total = totalDurationSeconds
        let mins = total / 60
        let secs = total % 60
        if secs == 0 {
            return "\(mins) min"
        } else {
            return "\(mins)m \(secs)s"
        }
    }

    /// Generates a standardized, conversational readout for any pre-run drill.
    static func readout(
        for drillId: PreRunDrillId,
        customTitle: String? = nil,
        targetCadence: String? = nil,
        previousCadence: Int? = nil,
        customDuration: DrillDuration? = nil,
        customCoachingTip: String? = nil
    ) -> DrillReadout {
        switch drillId {
        case .tempoSurges:
            let duration = customDuration ?? drillId.defaultDuration
            let resolvedTitle = customTitle ?? (drillId == .tempoSurges && duration == .tenMinutes ? "Posture Check" : drillId.title)
            let targetStr = targetCadence.map { $0.contains("SPM") ? $0 : "\($0) SPM" } ?? "160 SPM"

            let drill = PreRunDrill(
                id: .tempoSurges,
                previousCadence: previousCadence,
                targetCadence: targetStr,
                duration: duration
            )
            let phases = drill.generatePhases()

            let overviewText: String
            switch duration {
            case .fiveMinutes, .tenMinutes:
                overviewText = "In this drill, you will complete a mechanical reset before your main run."
            case .fifteenMinutes, .twentyMinutes:
                overviewText = "In this session, you will complete a tempo surge workout to build speed endurance."
            case .thirtyMinutes, .thirtyFiveMinutes, .fortyMinutes, .fiftyMinutes:
                overviewText = "In this session, you will complete a tempo surge workout to build sustained speed and aerobic power."
            }
            let breakdownText = drill.coreSchedule.generateStructureBreakdownProse()

            let coachingTip = customCoachingTip ?? DrillTemplate.template(for: .tempoSurges).generateInstructionalCue(targetStr)

            let isMainRun = duration.rawValue >= 20 || (customTitle?.contains("Main Run") ?? false) || (customTitle?.contains("Threshold") ?? false)
            let subtitlePrefix = isMainRun ? "Tempo Main Run" : "Tempo Pre-Run"

            return DrillReadout(
                drillId: .tempoSurges,
                title: resolvedTitle,
                subtitle: "\(subtitlePrefix) • \(duration.rawValue) min",
                overview: overviewText,
                breakdown: breakdownText,
                coachingTip: coachingTip,
                phases: phases,
                durationMinutes: duration.rawValue,
                targetCadence: targetStr,
                targetZone: nil
            )

        case .strides:
            let resolvedTitle = customTitle ?? "Strides"
            let duration = customDuration ?? drillId.defaultDuration
            let targetStr = targetCadence.map { $0.contains("SPM") ? $0 : "\($0) SPM" }

            let drill = PreRunDrill(
                id: .strides,
                previousCadence: previousCadence,
                targetCadence: targetStr,
                duration: duration
            )
            let phases = drill.generatePhases()

            let overviewText: String
            switch duration {
            case .fiveMinutes, .tenMinutes, .fifteenMinutes:
                overviewText = "In this drill, you will wake up your leg turnover and find a quick, springy rhythm before your run."
            case .twentyMinutes, .thirtyMinutes, .thirtyFiveMinutes, .fortyMinutes, .fiftyMinutes:
                overviewText = "In this session, you will build leg speed with relaxed accelerations to prime your turnover."
            }
            let breakdownText = drill.coreSchedule.generateStructureBreakdownProse()

            let coachingTip = customCoachingTip ?? DrillTemplate.template(for: .strides).generateInstructionalCue(targetStr)

            return DrillReadout(
                drillId: .strides,
                title: resolvedTitle,
                subtitle: "Interval Pre-Run • \(duration.rawValue) min",
                overview: overviewText,
                breakdown: breakdownText,
                coachingTip: coachingTip,
                phases: phases,
                durationMinutes: duration.rawValue,
                targetCadence: targetStr,
                targetZone: nil
            )

        case .zone2Run:
            let duration = customDuration ?? .fiveMinutes
            let isPreRunWarmup = duration.rawValue <= 10
            let resolvedTitle = customTitle ?? (isPreRunWarmup ? "Dynamic Activation" : "Zone 2 Run")

            let drill = PreRunDrill(
                id: .zone2Run,
                previousCadence: previousCadence,
                targetCadence: nil,
                duration: duration
            )
            let phases = drill.generatePhases()

            let coachingTip = customCoachingTip ?? DrillTemplate.template(for: .zone2Run).generateInstructionalCue(nil)

            let subtitle = isPreRunWarmup
                ? (customTitle.map { "\($0) • \(duration.rawValue) min" } ?? "Long Run / Zone 2 Pre-Run • \(duration.rawValue) min")
                : (customTitle.map { "\($0) • \(duration.rawValue) min" } ?? "Zone 2 Aerobic Base • \(duration.rawValue) min")
            let overview = isPreRunWarmup
                ? "In this drill, you will complete a continuous warm-up to lubricate your joints without burning vital glycogen."
                : "In this session, you will build aerobic base and cardiovascular efficiency through continuous, conversational running."
            let breakdown = drill.coreSchedule.generateStructureBreakdownProse()

            return DrillReadout(
                drillId: .zone2Run,
                title: resolvedTitle,
                subtitle: subtitle,
                overview: overview,
                breakdown: breakdown,
                coachingTip: coachingTip,
                phases: phases,
                durationMinutes: duration.rawValue,
                targetCadence: nil,
                targetZone: "Zone 2 (Aerobic)"
            )

        case .cadencePyramids:
            let resolvedTitle = customTitle ?? "Cadence Pyramids"
            let duration = customDuration ?? drillId.defaultDuration
            let targetStr = targetCadence.map { $0.contains("SPM") ? $0 : "\($0) SPM" } ?? "165 SPM"

            let drill = PreRunDrill(
                id: .cadencePyramids,
                previousCadence: previousCadence,
                targetCadence: targetStr,
                duration: duration
            )
            let phases = drill.generatePhases()

            let breakdownText = drill.coreSchedule.generateStructureBreakdownProse()

            let coachingTip = customCoachingTip ?? DrillTemplate.template(for: .cadencePyramids).generateInstructionalCue(targetStr)

            return DrillReadout(
                drillId: .cadencePyramids,
                title: resolvedTitle,
                subtitle: "Cadence & Form Pre-Run • \(duration.rawValue) min",
                overview: "In this drill, you will complete a cadence progression to eliminate overstriding and protect your knees.",
                breakdown: breakdownText,
                coachingTip: coachingTip,
                phases: phases,
                durationMinutes: duration.rawValue,
                targetCadence: targetStr,
                targetZone: nil
            )

        case .rhythmIntervals:
            let resolvedTitle = customTitle ?? "Rhythm Intervals"
            let duration = customDuration ?? drillId.defaultDuration
            let targetStr = targetCadence.map { $0.contains("SPM") ? $0 : "\($0) SPM" } ?? "162 SPM"

            let drill = PreRunDrill(
                id: .rhythmIntervals,
                previousCadence: previousCadence,
                targetCadence: targetStr,
                duration: duration
            )
            let phases = drill.generatePhases()

            let overviewText = "In this drill, you will complete a rhythmic tempo tune-up to establish a consistent, economical cadence."
            let breakdownText = drill.coreSchedule.generateStructureBreakdownProse()

            let coachingTip = customCoachingTip ?? DrillTemplate.template(for: .rhythmIntervals).generateInstructionalCue(targetStr)

            return DrillReadout(
                drillId: .rhythmIntervals,
                title: resolvedTitle,
                subtitle: "Cadence & Rhythm Pre-Run • \(duration.rawValue) min",
                overview: overviewText,
                breakdown: breakdownText,
                coachingTip: coachingTip,
                phases: phases,
                durationMinutes: duration.rawValue,
                targetCadence: targetStr,
                targetZone: nil
            )

        case .neuromuscularPrimer:
            let resolvedTitle = customTitle ?? "Form Primer"
            let duration = customDuration ?? drillId.defaultDuration
            let targetStr = targetCadence.map { $0.contains("SPM") ? $0 : "\($0) SPM" } ?? "170 SPM"

            let drill = PreRunDrill(
                id: .neuromuscularPrimer,
                previousCadence: previousCadence,
                targetCadence: targetStr,
                duration: duration
            )
            let phases = drill.generatePhases()

            let overviewText = "In this drill, you will complete quick-step bursts to wake up fast turnover and keep your stride springy and light."
            let breakdownText = drill.coreSchedule.generateStructureBreakdownProse()

            let coachingTip = customCoachingTip ?? DrillTemplate.template(for: .neuromuscularPrimer).generateInstructionalCue(targetStr)

            return DrillReadout(
                drillId: .neuromuscularPrimer,
                title: resolvedTitle,
                subtitle: "Form Primer • \(duration.rawValue) min",
                overview: overviewText,
                breakdown: breakdownText,
                coachingTip: coachingTip,
                phases: phases,
                durationMinutes: duration.rawValue,
                targetCadence: targetStr,
                targetZone: nil
            )

        case .hillBounds:
            let resolvedTitle = customTitle ?? "Hill Bounds"
            let duration = customDuration ?? drillId.defaultDuration

            let drill = PreRunDrill(
                id: .hillBounds,
                previousCadence: previousCadence,
                targetCadence: targetCadence,
                duration: duration
            )
            let phases = drill.generatePhases()
            let breakdownText = drill.coreSchedule.generateStructureBreakdownProse()

            let coachingTip = customCoachingTip ?? DrillTemplate.template(for: .hillBounds).generateInstructionalCue(targetCadence)

            return DrillReadout(
                drillId: .hillBounds,
                title: resolvedTitle,
                subtitle: "Power & Stride Length Pre-Run • \(duration.rawValue) min",
                overview: "In this drill, you will complete an explosive uphill prep to build push-off power and glute drive.",
                breakdown: breakdownText,
                coachingTip: coachingTip,
                phases: phases,
                durationMinutes: duration.rawValue,
                targetCadence: targetCadence,
                targetZone: nil
            )

        case .recoveryJog:
            let resolvedTitle = customTitle ?? "Recovery Jog"
            let duration = customDuration ?? drillId.defaultDuration

            let drill = PreRunDrill(
                id: .recoveryJog,
                previousCadence: previousCadence,
                targetCadence: nil,
                duration: duration
            )
            let phases = drill.generatePhases()

            let coachingTip = customCoachingTip ?? DrillTemplate.template(for: .recoveryJog).generateInstructionalCue(nil)

            let isShortShakeout = duration.rawValue <= 10
            let subtitle = isShortShakeout
                ? "Zone 1 Shakeout • \(duration.rawValue) min"
                : "Zone 1 Active Recovery • \(duration.rawValue) min"
            let overview = isShortShakeout
                ? "In this warm-up, you will complete a gentle flush to stimulate blood flow and release muscular tension."
                : "In this session, you will clear metabolic waste and restore muscle tissue through effortless, low-heart-rate running."

            return DrillReadout(
                drillId: .recoveryJog,
                title: resolvedTitle,
                subtitle: subtitle,
                overview: overview,
                breakdown: drill.coreSchedule.generateStructureBreakdownProse(),
                coachingTip: coachingTip,
                phases: phases,
                durationMinutes: duration.rawValue,
                targetCadence: nil,
                targetZone: "Zone 1 (Recovery)"
            )

        case .aerobicFlush:
            let resolvedTitle = customTitle ?? "Aerobic Flush"
            let duration = customDuration ?? drillId.defaultDuration

            let drill = PreRunDrill(
                id: .aerobicFlush,
                previousCadence: previousCadence,
                targetCadence: nil,
                duration: duration
            )
            let phases = drill.generatePhases()

            let coachingTip = customCoachingTip ?? DrillTemplate.template(for: .aerobicFlush).generateInstructionalCue(nil)

            let isShortShakeout = duration.rawValue <= 10
            let subtitle = isShortShakeout
                ? "Active Recovery Shakeout • \(duration.rawValue) min"
                : "Active Recovery Flush • \(duration.rawValue) min"
            let overview = isShortShakeout
                ? "In this warm-up, you will complete a recovery flush to clear metabolic fatigue."
                : "In this session, you will clear residual fatigue and promote muscle recovery with easy, conversational running."

            return DrillReadout(
                drillId: .aerobicFlush,
                title: resolvedTitle,
                subtitle: subtitle,
                overview: overview,
                breakdown: drill.coreSchedule.generateStructureBreakdownProse(),
                coachingTip: coachingTip,
                phases: phases,
                durationMinutes: duration.rawValue,
                targetCadence: nil,
                targetZone: "Zone 1 (Recovery)"
            )

        case .fartlekPrimer:
            let resolvedTitle = customTitle ?? "Fartlek Primer"
            let duration = customDuration ?? drillId.defaultDuration
            let targetStr = targetCadence.map { $0.contains("SPM") ? $0 : "\($0) SPM" } ?? "165 SPM"

            let drill = PreRunDrill(
                id: .fartlekPrimer,
                previousCadence: previousCadence,
                targetCadence: targetStr,
                duration: duration
            )
            let phases = drill.generatePhases()
            let breakdownText = drill.coreSchedule.generateStructureBreakdownProse()

            let coachingTip = customCoachingTip ?? DrillTemplate.template(for: .fartlekPrimer).generateInstructionalCue(targetStr)

            let isLongWorkout = duration == .twentyMinutes || duration == .thirtyMinutes || duration == .thirtyFiveMinutes || duration == .fortyMinutes || duration == .fiftyMinutes
            let overview = isLongWorkout
                ? "In this session, you will practice shifting gears with continuous aerobic pickups to build versatility."
                : "In this drill, you will practice shifting gears with quick surges to dial in your rhythm."
            let subtitle = isLongWorkout
                ? "Fartlek Continuous Run • \(duration.rawValue) min"
                : "Gear-Shifting Pre-Run • \(duration.rawValue) min"

            return DrillReadout(
                drillId: .fartlekPrimer,
                title: resolvedTitle,
                subtitle: subtitle,
                overview: overview,
                breakdown: breakdownText,
                coachingTip: coachingTip,
                phases: phases,
                durationMinutes: duration.rawValue,
                targetCadence: targetStr,
                targetZone: nil
            )
        }
    }
}

/// An item wrapper for presenting a DrillReadout in a sheet modal.
struct ActiveDrillReadoutItem: Identifiable, Sendable {
    var id: String { readout.id }
    let readout: DrillReadout
    let plan: WorkoutPlan
    let dto: DrillPrescriptionDTO
}
