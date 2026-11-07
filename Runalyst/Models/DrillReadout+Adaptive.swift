import Foundation
import WorkoutKit
import RunalystCore

// MARK: - Readiness-Adaptive Prescription

extension ActiveDrillReadoutItem {
    /// Builds the readout, Apple Watch plan, and DTO from a single readiness-adapted `PreRunDrill`,
    /// guaranteeing the half-sheet, the visual timeline, and the WorkoutKit session all agree.
    static func adaptive(
        dto standardDTO: DrillPrescriptionDTO,
        readiness: ReadinessAssessment,
        customCoachingTip: String? = nil
    ) -> ActiveDrillReadoutItem {
        let drillId = standardDTO.preRunDrillId.flatMap(PreRunDrillId.init(rawValue:)) ?? .strides
        let duration: DrillDuration = {
            if let raw = standardDTO.durationMinutes {
                return DrillDuration.canonical(forRawMinutes: raw)
            }
            return drillId.defaultDuration
        }()
        let haptic = HapticFeedbackMode(rawValue: standardDTO.hapticMode ?? "") ?? .on

        let adaptedDTO = ReadinessModifier.adaptedDTO(standardDTO, readiness: readiness)
        let state = ReadinessState(rawValue: adaptedDTO.readinessState ?? "") ?? .productive
        let isIndoor = adaptedDTO.isIndoor ?? UserDefaults.standard.bool(forKey: "preferredWorkoutIsIndoor")
        let target = ReadinessModifier.adaptTarget(
            standardDTO.targetCadence,
            baselineCadence: standardDTO.previousCadence,
            drillId: drillId,
            state: state
        )

        let standardDrill = PreRunDrill(
            id: drillId,
            previousCadence: standardDTO.previousCadence,
            targetCadence: target.standardTargetCadence ?? standardDTO.targetCadence,
            duration: duration,
            hapticMode: haptic,
            isIndoor: isIndoor,
            customDisplayName: standardDTO.title
        )
        let adaptedDrill = PreRunDrill(
            id: drillId,
            previousCadence: adaptedDTO.previousCadence,
            targetCadence: adaptedDTO.targetCadence,
            duration: duration,
            hapticMode: haptic,
            readinessState: state,
            isIndoor: isIndoor,
            customDisplayName: standardDTO.title
        )

        var readout = DrillReadout.readout(
            for: drillId,
            customTitle: standardDTO.title,
            targetCadence: adaptedDTO.targetCadence,
            previousCadence: adaptedDTO.previousCadence,
            customDuration: duration,
            customCoachingTip: customCoachingTip
        )

        if state != .productive {
            let effectiveAssessment: ReadinessAssessment = {
                if readiness.state == state {
                    return readiness
                }
                return ReadinessAssessment(
                    state: state,
                    triggers: readiness.triggers.isEmpty ? [.cardiacDrift] : readiness.triggers,
                    acuteLoad: readiness.acuteLoad,
                    chronicWeeklyLoad: readiness.chronicWeeklyLoad,
                    acwr: readiness.acwr,
                    mileageDropFraction: readiness.mileageDropFraction
                )
            }()
            readout = readout.applyingReadiness(
                assessment: effectiveAssessment,
                target: target,
                standardDrill: standardDrill,
                adaptedDrill: adaptedDrill
            )
        }

        return ActiveDrillReadoutItem(
            readout: readout,
            plan: adaptedDrill.buildWorkoutPlan(),
            dto: adaptedDTO
        )
    }

    /// Builds an ActiveDrillReadoutItem directly from a synthesized session prescription.
    /// Preserves the exact target cadence, duration, and structure determined by SessionSynthesisEngine
    /// without running a second competing post-hoc mutation pass.
    static func fromPrescription(
        dto: DrillPrescriptionDTO,
        customCoachingTip: String? = nil
    ) -> ActiveDrillReadoutItem {
        let drillId = dto.preRunDrillId.flatMap(PreRunDrillId.init(rawValue:)) ?? .strides
        let duration: DrillDuration = {
            if let raw = dto.durationMinutes {
                return DrillDuration.canonical(forRawMinutes: raw)
            }
            return drillId.defaultDuration
        }()
        let haptic = HapticFeedbackMode(rawValue: dto.hapticMode ?? "") ?? .on
        let state = ReadinessState(rawValue: dto.readinessState ?? "") ?? .productive
        let isIndoor = dto.isIndoor ?? UserDefaults.standard.bool(forKey: "preferredWorkoutIsIndoor")

        let drill = PreRunDrill(
            id: drillId,
            previousCadence: dto.previousCadence,
            targetCadence: dto.targetCadence,
            duration: duration,
            hapticMode: haptic,
            readinessState: state,
            isIndoor: isIndoor,
            customDisplayName: dto.title
        )

        var readout = DrillReadout.readout(
            for: drillId,
            customTitle: dto.title,
            targetCadence: dto.targetCadence,
            previousCadence: dto.previousCadence,
            customDuration: duration,
            customCoachingTip: customCoachingTip ?? dto.purpose
        )

        if drill.readinessAdjustedIntervalSpec != nil {
            let adaptedPhases = drill.generatePhases()
            let totalSeconds = adaptedPhases.map(\.durationSeconds).reduce(0, +)
            let formattedTotal: String = {
                let mins = totalSeconds / 60
                let secs = totalSeconds % 60
                if secs == 0 {
                    return "\(mins) min"
                } else {
                    return "\(mins)m \(secs)s"
                }
            }()
            let standardDrill = PreRunDrill(
                id: drillId,
                previousCadence: dto.previousCadence,
                targetCadence: dto.targetCadence,
                duration: duration,
                hapticMode: haptic,
                readinessState: .productive,
                isIndoor: isIndoor,
                customDisplayName: dto.title
            )
            readout = DrillReadout(
                drillId: drillId,
                title: dto.title.isEmpty ? readout.title : dto.title,
                subtitle: readout.subtitle.replacingOccurrences(of: "\(readout.durationMinutes) min", with: formattedTotal),
                overview: readout.overview,
                breakdown: DrillReadout.readinessBreakdown(phases: adaptedPhases, drillId: drillId),
                coachingTip: readout.coachingTip,
                phases: adaptedPhases,
                durationMinutes: readout.durationMinutes,
                targetCadence: dto.targetCadence ?? readout.targetCadence,
                targetZone: readout.targetZone,
                readinessState: state,
                standardTargetCadence: standardDrill.computedCadence ?? readout.targetCadence,
                standardWork: standardDrill.defaultWorkString,
                adaptedWork: drill.defaultWorkString,
                standardRecovery: standardDrill.defaultRecoveryString,
                adaptedRecovery: drill.defaultRecoveryString,
                readinessContext: customCoachingTip ?? dto.purpose
            )
        }

        return ActiveDrillReadoutItem(
            readout: readout,
            plan: drill.buildWorkoutPlan(),
            dto: dto
        )
    }
}

extension DrillReadout {
    /// Returns a copy of this readout reflecting a readiness-adapted prescription.
    func applyingReadiness(
        assessment: ReadinessAssessment,
        target: AdaptiveDrillTarget,
        standardDrill: PreRunDrill,
        adaptedDrill: PreRunDrill
    ) -> DrillReadout {
        var copy = self
        let adaptedSpec = adaptedDrill.readinessAdjustedIntervalSpec
        let phases = adaptedDrill.generatePhases()

        copy.readinessState = adaptedDrill.readinessState
        copy.standardTargetCadence = target.standardTargetCadence.map { $0.contains("SPM") ? $0 : "\($0) SPM" }
        copy.standardWork = standardDrill.defaultWorkString
        copy.adaptedWork = adaptedDrill.defaultWorkString
        copy.standardRecovery = standardDrill.defaultRecoveryString
        copy.adaptedRecovery = adaptedDrill.defaultRecoveryString
        copy.readinessContext = ReadinessModifier.coachContext(
            assessment: assessment,
            target: target,
            baselineCadence: adaptedDrill.previousCadence,
            standardSpec: adaptedSpec == nil ? nil : standardDrill.standardIntervalSpec,
            adaptedSpec: adaptedSpec
        )

        if adaptedSpec != nil {
            let totalSeconds = phases.map(\.durationSeconds).reduce(0, +)
            let formattedTotal: String = {
                let mins = totalSeconds / 60
                let secs = totalSeconds % 60
                if secs == 0 {
                    return "\(mins) min"
                } else {
                    return "\(mins)m \(secs)s"
                }
            }()
            copy = DrillReadout(
                drillId: drillId,
                title: title,
                subtitle: subtitle.replacingOccurrences(of: "\(durationMinutes) min", with: formattedTotal),
                overview: overview,
                breakdown: Self.readinessBreakdown(phases: phases, drillId: drillId),
                coachingTip: coachingTip,
                phases: phases,
                durationMinutes: durationMinutes,
                targetCadence: targetCadence,
                targetZone: targetZone,
                readinessState: copy.readinessState,
                standardTargetCadence: copy.standardTargetCadence,
                standardWork: copy.standardWork,
                adaptedWork: copy.adaptedWork,
                standardRecovery: copy.standardRecovery,
                adaptedRecovery: copy.adaptedRecovery,
                readinessContext: copy.readinessContext
            )
        }
        return copy
    }

    /// Plain-English breakdown generated from the adapted phase geometry so text and timeline never diverge.
    static func readinessBreakdown(phases: [WorkoutPhase], drillId: PreRunDrillId) -> String {
        var sentences: [String] = []
        if let warmup = phases.first(where: { $0.kind == .warmup }) {
            sentences.append("You’ll start with a \(DrillScheduleCore.adjectiveDuration(warmup.durationSeconds)) easy warm-up jog.")
        }
        let work = phases.filter { $0.kind == .work }
        let recovery = phases.first { if case .recovery = $0.kind { return true } else { return false } }
        if let firstWork = work.first {
            let label: String = {
                switch drillId {
                case .strides: return "strides"
                case .hillBounds: return "uphill bounds"
                case .fartlekPrimer: return "pick-ups"
                default: return "intervals"
                }
            }()
            var sentence = "This is followed by \(work.count) sets of \(DrillScheduleCore.adjectiveDuration(firstWork.durationSeconds)) \(label)"
            if let recovery, case .recovery(let isWalk) = recovery.kind {
                sentence += ", each paired with \(DrillScheduleCore.nounDuration(recovery.durationSeconds)) of \(isWalk ? "walk" : "easy jog") recovery"
            }
            sentences.append(sentence + ".")
        }
        if let cooldown = phases.first(where: { $0.kind == .cooldown }) {
            sentences.append("You’ll finish with a \(DrillScheduleCore.adjectiveDuration(cooldown.durationSeconds)) cool-down.")
        }
        return sentences.joined(separator: " ")
    }
}
