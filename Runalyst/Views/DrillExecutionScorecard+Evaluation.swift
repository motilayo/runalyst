import SwiftUI
import RunalystCore

enum DrillAdherenceTier {
    case exceeded
    case met
    case partiallyMet
    case notMet

    var badgeText: String {
        switch self {
        case .exceeded: return "Exceeded"
        case .met: return "Met"
        case .partiallyMet: return "Partially Met"
        case .notMet: return "Not Met"
        }
    }

    func badgeText(for drillId: PreRunDrillId) -> String {
        if drillId.isHeartRateTargeted {
            switch self {
            case .exceeded: return "Optimal"
            case .met: return "Target Met"
            case .partiallyMet: return "Partially Met"
            case .notMet: return "Not Met"
            }
        }
        return badgeText
    }

    var badgeIcon: String {
        switch self {
        case .exceeded: return "star.fill"
        case .met: return "checkmark"
        case .partiallyMet: return "minus"
        case .notMet: return "xmark"
        }
    }

    func badgeIcon(for drillId: PreRunDrillId) -> String {
        if drillId.isHeartRateTargeted {
            switch self {
            case .exceeded: return "checkmark.seal.fill"
            case .met: return "checkmark"
            case .partiallyMet: return "minus"
            case .notMet: return "xmark"
            }
        }
        return badgeIcon
    }

    var tintColor: Color {
        switch self {
        case .exceeded: return Color(red: 0.0, green: 0.75, blue: 0.65)
        case .met: return .green
        case .partiallyMet: return .orange
        case .notMet: return .red
        }
    }
}

struct DrillDisplayRep: Identifiable, Sendable {
    var id: Int { repIndex }
    let repIndex: Int
    let durationSeconds: Double?
    let isFastest: Bool
    let workPaceFormatted: String?
    let workCadence: Int
    let workHeartRate: Int
    let recoveryPaceFormatted: String?
    let recoveryCadence: Int
    let recoveryHeartRate: Int
    let recoveryHeartRateDrop: Int?
    let paceDeltaVsAverageWorkSec: Int?
    let isMet: Bool
    let observation: String?
}

struct DrillAdherenceCalculation {
    let metCount: Int
    let totalCount: Int
    let targetCadence: String
    let targetCadenceStr: String
    let displayReps: [DrillDisplayRep]
    let isIntervalDrill: Bool
    let tier: DrillAdherenceTier
    let tierDescription: String
    let actualCadence: Int
    let actualHR: Int
    let thirtyDayCadence: Int
    let effectiveCadenceFloor: Int
    let oscDelta: Double
    let isHRTarget: Bool
    let isDualTarget: Bool
    let drillObj: PreRunDrill
    let intervalSummary: DrillIntervalSummary?
}

extension DrillExecutionScorecard {
    /// Deterministically computes the adherence score (met count, total intervals, and target cadence)
    /// across the scorecard, ensuring perfect mathematical parity between scorecard meters, hero subtitles,
    /// and AI coaching narrative text.
    @MainActor
    static func calculateAdherence(
        runRecord: RunRecord,
        drillId: PreRunDrillId,
        baselineCadence: Double?,
        baselineOscillation: Double? = nil
    ) -> DrillAdherenceCalculation {
        let template = DrillTemplate.template(for: drillId)
        let thirtyDayCadence = Int(baselineCadence ?? (runRecord.computeHistoricalBaselineCadence() ?? (runRecord.workingAvgCadence > 0 ? runRecord.workingAvgCadence : 155)))
        let targetCadence = runRecord.effectivePrescribedTargetCadence(drillId: drillId, baselineCadence: thirtyDayCadence)
            ?? template.calculateTargetCadence(thirtyDayCadence)
        let drillObj = PreRunDrill(id: drillId, previousCadence: thirtyDayCadence, targetCadence: targetCadence)
        let actualCadence = Int(round(runRecord.workingAvgCadence))
        let actualHR = Int(round(runRecord.workingAvgHeartRate))

        let isHRTarget = drillId.isHeartRateTargeted
        let isDualTarget = (drillId == .tempoSurges)
        let targetCadenceStr = drillObj.computedCadence ?? "Steady"

        let currentOsc = runRecord.workingAvgVerticalOscillation ?? runRecord.rawAvgVerticalOscillation ?? 9.5
        let baseOsc = baselineOscillation ?? 9.5
        let oscDelta = currentOsc - baseOsc

        let intervalSummary: DrillIntervalSummary? = {
            if let parsed = DrillIntervalSummary.from(tags: runRecord.framboiseTags, drillId: drillId) {
                return parsed
            }
            if !isHRTarget && !drillId.isAerobicContinuous {
                return DrillIntervalEvaluator.evaluate(
                    buckets: [],
                    drillId: drillId,
                    baselineCadence: thirtyDayCadence,
                    workoutDuration: runRecord.duration,
                    oscDelta: oscDelta,
                    targetCadenceOverride: targetCadence
                )
            }
            return nil
        }()

        let analysisContext = WorkoutAnalysisContext(
            runRecord: runRecord,
            runSignature: runRecord.signature,
            macroProfile: nil,
            recoveryTimeline: RecoveryTimeline(
                now: Date(),
                lastHard: nil,
                hardSessionsLast72h: 0,
                requiredHours: 48,
                state: .productive
            ),
            baselineStats: baselineCadence.map { (avgPace: runRecord.workingAvgPace, avgCadence: $0, avgHR: runRecord.workingAvgHeartRate) }
        )
        let intervalEvals = analysisContext.intervalEvaluations

        let displayReps: [DrillDisplayRep] = {
            if let summary = intervalSummary, summary.totalIntervals > 1, !summary.reps.isEmpty {
                let durationCategory: DrillDuration = {
                    if runRecord.duration <= 720 { return .tenMinutes }
                    if runRecord.duration >= 1500 { return .thirtyMinutes }
                    return .fifteenMinutes
                }()
                let sched = DrillSchedule.schedule(for: drillId, duration: durationCategory)

                let fallbackDuration: Double? = {
                    if drillObj.intervalSpec.workSeconds > 0 {
                        return Double(drillObj.intervalSpec.workSeconds)
                    }
                    return sched.workSeconds > 0 ? Double(sched.workSeconds) : nil
                }()

                return summary.reps.map { rep in
                    let matchedEval = intervalEvals.first(where: { $0.repIndex == rep.repIndex })
                        ?? (rep.repIndex - 1 >= 0 && rep.repIndex - 1 < intervalEvals.count ? intervalEvals[rep.repIndex - 1] : nil)

                    let evalWorkCad = matchedEval?.workCadence ?? 0
                    let workCadence = evalWorkCad > 0
                        ? evalWorkCad
                        : (rep.workCadence > 0 ? rep.workCadence : actualCadence)
                    let workHR = (matchedEval?.workHeartRate ?? 0) > 0
                        ? (matchedEval?.workHeartRate ?? 0)
                        : (rep.workHeartRate > 0 ? rep.workHeartRate : actualHR)
                    let evalRecCad = matchedEval?.recoveryCadence ?? 0
                    let recCadence = evalRecCad > 0
                        ? evalRecCad
                        : (rep.recoveryCadence > 0 ? rep.recoveryCadence : 0)
                    let recHR = (matchedEval?.recoveryHeartRate ?? 0) > 0
                        ? (matchedEval?.recoveryHeartRate ?? 0)
                        : (rep.recoveryHeartRate > 0 ? rep.recoveryHeartRate : 0)
                    let hrDrop: Int? = {
                        if let drop = matchedEval?.recoveryHeartRateDrop { return drop }
                        if let drop = rep.recoveryHeartRateDrop { return drop }
                        if workHR > 0 && recHR > 0 { return workHR - recHR }
                        return nil
                    }()

                    let fallbackWorkPace: String? = {
                        if runRecord.workingAvgPace > 0 {
                            return PaceFormatter.formatPace(secondsPerKilometer: runRecord.workingAvgPace)
                        }
                        return nil
                    }()

                    let workPaceFormatted = matchedEval?.workPaceFormatted
                        ?? rep.workPaceSecondsPerKm.map { PaceFormatter.formatPace(secondsPerKilometer: $0) }
                        ?? fallbackWorkPace

                    let recoveryPaceFormatted = matchedEval?.recoveryPaceFormatted
                        ?? rep.recoveryPaceSecondsPerKm.map { PaceFormatter.formatPace(secondsPerKilometer: $0) }

                    let repDuration = matchedEval?.durationSeconds
                        ?? rep.durationSeconds
                        ?? fallbackDuration

                    let evaluatedIsMet: Bool = {
                        if let range = drillObj.effectiveTargetCadence, workCadence > 0 {
                            let upperLimit = (drillId == .strides || drillId == .tempoSurges) ? 195 : (range.upperBound + 8)
                            return rep.isMet || (workCadence >= (range.lowerBound - 2) && workCadence <= upperLimit)
                        }
                        return rep.isMet
                    }()

                    return DrillDisplayRep(
                        repIndex: rep.repIndex,
                        durationSeconds: repDuration,
                        isFastest: matchedEval?.observation.starts(with: "Fastest") ?? false,
                        workPaceFormatted: workPaceFormatted,
                        workCadence: workCadence,
                        workHeartRate: workHR,
                        recoveryPaceFormatted: recoveryPaceFormatted,
                        recoveryCadence: recCadence,
                        recoveryHeartRate: recHR,
                        recoveryHeartRateDrop: hrDrop,
                        paceDeltaVsAverageWorkSec: matchedEval?.paceDeltaVsAverageWorkSec,
                        isMet: evaluatedIsMet,
                        observation: matchedEval?.observation
                    )
                }
            } else if intervalEvals.count > 1 && !drillId.isAerobicContinuous {
                return intervalEvals.map { eval in
                    let isMet: Bool = {
                        if let range = drillObj.effectiveTargetCadence {
                            return eval.workCadence >= (range.lowerBound - 2) && eval.workCadence <= (range.upperBound + 8)
                        }
                        return eval.workCadence >= thirtyDayCadence
                    }()
                    return DrillDisplayRep(
                        repIndex: eval.repIndex,
                        durationSeconds: eval.durationSeconds,
                        isFastest: eval.observation.starts(with: "Fastest"),
                        workPaceFormatted: eval.workPaceFormatted,
                        workCadence: eval.workCadence,
                        workHeartRate: eval.workHeartRate,
                        recoveryPaceFormatted: eval.recoveryPaceFormatted,
                        recoveryCadence: eval.recoveryCadence ?? 0,
                        recoveryHeartRate: eval.recoveryHeartRate ?? 0,
                        recoveryHeartRateDrop: eval.recoveryHeartRateDrop,
                        paceDeltaVsAverageWorkSec: eval.paceDeltaVsAverageWorkSec,
                        isMet: isMet,
                        observation: eval.observation
                    )
                }
            }
            return []
        }()

        let heightFloor = analysisContext.runnerProfile.heightAdjustedCadenceFloor
        let isRecovery = drillId == .aerobicFlush || runRecord.detectedTypeRaw == "Recovery Run" || (runRecord.percentZone4 <= 0.02 && actualHR > 0 && actualHR <= 135)
        let effectiveFloor = isRecovery ? max(138, heightFloor - 10) : heightFloor

        let adherenceInput = DrillAdherenceInputCore(
            drillIdentifier: drillId.rawValue,
            actualCadence: actualCadence,
            actualHeartRate: actualHR,
            baselineCadence: thirtyDayCadence,
            heightAdjustedCadenceFloor: effectiveFloor,
            targetCadenceLower: drillObj.effectiveTargetCadence?.lowerBound,
            targetCadenceUpper: drillObj.effectiveTargetCadence?.upperBound,
            targetCadenceString: targetCadenceStr,
            targetHeartRateZone: drillId.targetHeartRateZone,
            percentZone4: runRecord.percentZone4,
            oscDelta: oscDelta,
            isHeartRateTargeted: isHRTarget,
            isAerobicContinuous: drillId.isAerobicContinuous,
            isDualTarget: isDualTarget,
            intervalSummaryMetCount: intervalSummary?.intervalsMet,
            intervalSummaryTotalCount: intervalSummary?.totalIntervals,
            intervalSummaryTier: intervalSummary?.toCore.tier,
            intervalSummaryVerdict: intervalSummary?.verdict,
            repsTotalCount: displayReps.count,
            repsMetCount: displayReps.filter(\.isMet).count
        )
        let adherenceResult = DrillAdherenceCore.evaluateAdherence(input: adherenceInput)
        let effectiveMetCount = adherenceResult.effectiveMetCount
        let effectiveTotalCount = adherenceResult.effectiveTotalCount
        let isIntervalDrill = adherenceResult.isIntervalDrill
        let tier = DrillAdherenceTier(core: adherenceResult.tier)
        let tierDescription = adherenceResult.tierDescription

        return DrillAdherenceCalculation(
            metCount: effectiveMetCount,
            totalCount: effectiveTotalCount,
            targetCadence: targetCadence,
            targetCadenceStr: targetCadenceStr,
            displayReps: displayReps,
            isIntervalDrill: isIntervalDrill,
            tier: tier,
            tierDescription: tierDescription,
            actualCadence: actualCadence,
            actualHR: actualHR,
            thirtyDayCadence: thirtyDayCadence,
            effectiveCadenceFloor: effectiveFloor,
            oscDelta: oscDelta,
            isHRTarget: isHRTarget,
            isDualTarget: isDualTarget,
            drillObj: drillObj,
            intervalSummary: intervalSummary
        )
    }

    @MainActor
    static func evaluateDrillAdherence(
        runRecord: RunRecord,
        drillId: PreRunDrillId,
        baselineCadence: Double?
    ) -> (metCount: Int, totalCount: Int, targetCadence: String) {
        let calc = calculateAdherence(
            runRecord: runRecord,
            drillId: drillId,
            baselineCadence: baselineCadence,
            baselineOscillation: nil
        )
        return (metCount: calc.metCount, totalCount: calc.totalCount, targetCadence: calc.targetCadence)
    }
}
