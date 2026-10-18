import Foundation
import OSLog
import SwiftData
#if canImport(FoundationModels)
import FoundationModels
#endif

private let logger = Logger(subsystem: "com.runalyzer.Runalyzer", category: "RunAnalyzerActor")

@available(iOS 26.0, *)
@ModelActor

actor RunAnalyzerActor {
    func generateAnalysis(for runID: PersistentIdentifier, force: Bool = false) async {
        guard let run = modelContext.model(for: runID) as? RunRecord else { return }

        if !force && run.insight != nil { return } // Already analyzed

        // GUARDRAIL: A run must have at least cadence or heart rate sensor data.
        // Runs recorded without an Apple Watch have zero biomechanical metrics.
        // Generating form coaching on zero sensor data results in model hallucinations.
        guard run.workingAvgCadence > 0 || run.workingAvgHeartRate > 0 else {
            logger.info("Skipping AI insight for run \(run.date): insufficient biometric data (no cadence or HR).")
            if let oldInsight = run.insight {
                modelContext.delete(oldInsight)
                run.insight = nil
                try? modelContext.save()
            }
            return
        }

        let targetDate = run.date
        let targetID = run.id
        guard let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: targetDate) else {
            return
        }

        let descriptor = FetchDescriptor<RunRecord>(
            predicate: #Predicate { $0.date >= thirtyDaysAgo && $0.date < targetDate && $0.id != targetID }
        )
        let priorRuns = (try? modelContext.fetch(descriptor)) ?? []

        // Every run counts with classification-aware weighting
        // Steady, Easy, and Long runs provide primary aerobic anchor (1.0x).
        // Tempo, Progression, and Recovery runs provide secondary aerobic context (0.8x).
        // High-intensity interval drills contribute (0.3x) without distorting aerobic endurance baselines.
        let validRuns = priorRuns.filter { $0.workingAvgPace > 0 && $0.duration > 0 }

        func aerobicWeight(for r: RunRecord) -> Double {
            switch r.detectedTypeRaw {
            case "Steady Effort", "Easy Run", "Long Run":
                return 1.0 * r.duration
            case "Tempo Run", "Progression Run", "Recovery Run":
                return 0.8 * r.duration
            case "Intervals", "Pyramids", "Fartlek":
                return 0.3 * r.duration
            default:
                return 0.7 * r.duration
            }
        }

        var baseline: BaselineStats?
        if validRuns.count >= 3 {
            let totalWeight = validRuns.map { aerobicWeight(for: $0) }.reduce(0, +)
            if totalWeight > 0 {
                let weightedPace = validRuns.map { $0.workingAvgPace * aerobicWeight(for: $0) }.reduce(0, +) / totalWeight
                let weightedHR = validRuns.map { $0.workingAvgHeartRate * aerobicWeight(for: $0) }.reduce(0, +) / totalWeight
                let weightedCadence = validRuns.map { $0.workingAvgCadence * aerobicWeight(for: $0) }.reduce(0, +) / totalWeight
                let weightedOsc = validRuns.map { ($0.workingAvgVerticalOscillation ?? $0.rawAvgVerticalOscillation ?? 9.5) * aerobicWeight(for: $0) }.reduce(0, +) / totalWeight

                let strideRuns = validRuns.filter { ($0.workingAvgStrideLength ?? $0.rawAvgStrideLength ?? 0) > 0 }
                let totalStrideWeight = strideRuns.map { aerobicWeight(for: $0) }.reduce(0, +)
                let weightedStride: Double? = totalStrideWeight > 0
                    ? (strideRuns.map { ($0.workingAvgStrideLength ?? $0.rawAvgStrideLength ?? 0) * aerobicWeight(for: $0) }.reduce(0, +) / totalStrideWeight)
                    : nil

                baseline = BaselineStats(
                    avgPace: weightedPace,
                    avgCadence: weightedCadence,
                    avgHR: weightedHR,
                    avgOscillation: weightedOsc,
                    avgStrideLength: weightedStride
                )
            }
        }

        var directiveContext: String
        let paceContext: String
        let hrContext: String
        let cadenceContext: String
        let zone4Context = "\(Int(run.percentZone4 * 100))% of run spent in high aerobic/anaerobic zone."
        let cvContext = "Pace Variability (CV): \(String(format: "%.3f", run.paceCV))"
        let slopeContext = "Pace Slope: \(String(format: "%.3f", run.paceSlope))"

        if let base = baseline {
            let cadenceDelta = run.workingAvgCadence - base.avgCadence
            let isRecoveryRun = run.detectedTypeRaw == "Recovery Run" || (run.percentZone4 <= 0.02 && run.workingAvgHeartRate > 0 && run.workingAvgHeartRate <= 135)
            let effectiveFloor = isRecoveryRun ? 140.0 : 150.0
            let isSubFloor = run.workingAvgCadence < effectiveFloor
            let isCadenceImproved = (cadenceDelta >= 0 || run.workingAvgCadence >= 170) && !isSubFloor
            let cadenceSummary: String
            if isRecoveryRun {
                cadenceSummary = "Cadence averaged \(Int(run.workingAvgCadence)) SPM during this active recovery session. Effort and heart rate were kept low to flush fatigue without mechanical strain."
            } else if isSubFloor {
                cadenceSummary = "Cadence was \(Int(run.workingAvgCadence)) SPM (BELOW the 150 SPM floor). Turnover is slow with prolonged ground contact; DO NOT praise form or turnover precision."
            } else if isCadenceImproved {
                if run.workingAvgCadence >= 170 && cadenceDelta < 0 {
                    cadenceSummary = "Cadence averaged an optimal \(Int(run.workingAvgCadence)) SPM, maintaining strong turnover above the 170 SPM efficiency zone despite a slight drop."
                } else if cadenceDelta > 0 {
                    cadenceSummary = "Cadence increased by \(Int(cadenceDelta)) SPM, showing lighter foot turnover and reduced impact."
                } else {
                    cadenceSummary = "Cadence held steady at \(Int(run.workingAvgCadence)) SPM, matching baseline."
                }
            } else {
                cadenceSummary = "Cadence dropped by \(Int(abs(cadenceDelta))) SPM, indicating slower turnover or longer ground contact."
            }
            let currentVR = run.verticalRatio
            let currentStride = run.workingAvgStrideLength ?? run.rawAvgStrideLength
            let baseStride = base.avgStrideLength
            let strideDelta: Double = {
                if let current = currentStride, let base = baseStride {
                    return current - base
                }
                return 0.0
            }()
            let strideDeltaPercent: Double = {
                if let current = currentStride, let base = baseStride, base > 0 {
                    return (current - base) / base
                }
                return 0.0
            }()

            let currentOscVal = run.workingAvgVerticalOscillation ?? run.rawAvgVerticalOscillation
            var formTelemetry: [String] = []
            if let stride = currentStride {
                formTelemetry.append(String(format: "%.2fm stride", stride))
            }
            if let osc = currentOscVal {
                formTelemetry.append(String(format: "%.1fcm osc", osc))
            }
            if let vr = currentVR {
                formTelemetry.append(String(format: "(VR: %.1f%%)", vr))
            }
            let formSummary = formTelemetry.isEmpty ? "" : " Form: \(formTelemetry.joined(separator: ", "))."
            cadenceContext = "Current: \(Int(run.workingAvgCadence)) SPM, Baseline: \(Int(base.avgCadence)) SPM, Deltas: \(Int(cadenceDelta)). \(cadenceSummary)\(formSummary)"

            let runPace = PaceFormatter.formatPace(secondsPerKilometer: run.workingAvgPace)
            let basePace = PaceFormatter.formatPace(secondsPerKilometer: base.avgPace)
            let paceDiff = base.avgPace - run.workingAvgPace // positive diff means faster
            let paceSummary: String
            if paceDiff > 0 {
                paceSummary = "Pace was \(Int(abs(paceDiff))) sec faster than baseline, showing strong aerobic power."
            } else if paceDiff < 0 {
                paceSummary = "Pace was \(Int(abs(paceDiff))) sec slower than baseline, reflecting a controlled or fatiguing effort."
            } else {
                paceSummary = "Pace held consistent with baseline."
            }
            paceContext = "Current: \(runPace), Baseline: \(basePace), Deltas: \(Int(abs(paceDiff))) sec diff. \(paceSummary)"

            let hrDelta = run.workingAvgHeartRate - base.avgHR
            let hrSummary: String
            if hrDelta < 0 {
                hrSummary = "Heart rate was \(Int(abs(hrDelta))) BPM lower than baseline, indicating improved cardiovascular efficiency."
            } else if hrDelta > 0 {
                hrSummary = "Heart rate was \(Int(hrDelta)) BPM higher than baseline, reflecting cardiovascular strain or higher effort."
            } else {
                hrSummary = "Heart rate remained stable, matching baseline."
            }
            hrContext = "Current: \(Int(run.workingAvgHeartRate)) BPM, Baseline: \(Int(base.avgHR)) BPM, Deltas: \(Int(hrDelta)). \(hrSummary)"

            let trainingGoal = UserDefaults.standard.string(forKey: "trainingGoal") ?? "Base Building"
            let goalSuffix = " Runner goal: \(trainingGoal)."

            let isTrueOverstriding = (run.workingAvgCadence < 155 && (currentVR ?? 0) > 9.5) ||
                                     ((currentOscVal ?? 0) > 10.0 && strideDeltaPercent > 0.05)

            let isIndoorRun = run.isIndoor ?? false

            if isIndoorRun {
                // Treadmill Pace Strain vs Efficiency & Cardiac Drift Tolerance:
                // Belt locks pace. Do not praise pacing consistency. Evaluate biological cost.
                let indoorDriftTolerance = 8.0 // +8 BPM acceptable thermoregulatory drift without ambient breeze
                if cadenceDelta < -2 && hrDelta > indoorDriftTolerance {
                    directiveContext = "Indoor run: Cadence dropped while heart rate spiked. Caution the runner against overstriding or reaching forward to keep pace with the treadmill belt. Prescribe Cadence Pyramids to restore light turnover underneath hips." + goalSuffix
                } else if abs(cadenceDelta) <= 2 && hrDelta <= indoorDriftTolerance {
                    directiveContext = "Indoor run: The runner maintained smooth cadence rhythm and cardiovascular stability on the treadmill. Applaud mechanical turnover efficiency without attributing pacing consistency to outdoor effort." + goalSuffix
                } else if hrDelta > indoorDriftTolerance && abs(cadenceDelta) <= 2 {
                    directiveContext = "Indoor run: Heart rate drifted upward due to indoor thermoregulation while turnover held steady. Acknowledge thermal drift and prescribe an easy recovery or cadence flush drill." + goalSuffix
                } else {
                    directiveContext = "Indoor run: Evaluate treadmill running economy and turnover stability." + goalSuffix
                }
            } else if paceDiff < 0 && hrDelta > 0 {
                // GUARDRAIL: fatigue detected — Swift overrides goal with recovery priority
                directiveContext = "The runner was slower and had a higher heart rate than baseline, indicating fatigue. PRIORITY: prescribe Easy Aerobic Recovery and HR control. Recovery overrides any race goal."
            } else if abs(cadenceDelta) <= 2 && paceDiff < -15 && strideDeltaPercent < -0.08 {
                // Mechanical stride collapse: cadence held but stride compressed under fatigue
                directiveContext = "The runner shows mechanical stride collapse (stride compressed by \(Int(abs(strideDeltaPercent * 100)))% despite steady turnover). Prescribe a Form drill to reinforce hip extension and posture under fatigue." + goalSuffix
            } else if isTrueOverstriding {
                let vrText = currentVR.map { String(format: "%.1f", $0) } ?? "high"
                let subFloorNote = run.workingAvgCadence < 150 ? " (cadence is \(Int(run.workingAvgCadence)) SPM, below 150 SPM floor; DO NOT praise form precision)" : ""
                directiveContext = "The runner shows high vertical bounce relative to stride length (VR: \(vrText)%)\(subFloorNote), indicating overstriding and braking forces. Prescribe Cadence Pyramids or Rhythm Intervals to quicken turnover." + goalSuffix
            } else if paceDiff > 0 && hrDelta < 0 {
                let accelReason: String
                if cadenceDelta > 4 && strideDelta <= 0.03 {
                    accelReason = "Pace increase driven primarily by turnover frequency (+\(Int(cadenceDelta)) SPM)."
                } else if strideDelta > 0.05 && cadenceDelta <= 2 {
                    let cm = Int(round(strideDelta * 100))
                    accelReason = "Pace increase driven by stride extension (+\(cm) cm), maintaining steady rhythm."
                } else {
                    accelReason = "Balanced acceleration via both turnover and stride extension."
                }
                directiveContext = "The runner was faster with a lower heart rate, indicating strong fitness improvements (\(accelReason)). Praise performance and prescribe an optional Speed or Tempo drill." + goalSuffix
            } else {
                if run.workingAvgCadence < 150 {
                    directiveContext = "The runner's cadence of \(Int(run.workingAvgCadence)) SPM is below the 150 SPM floor. Caution against heavy ground impact and prescribe Cadence Pyramids or Rhythm Intervals to elevate turnover. DO NOT praise form." + goalSuffix
                } else {
                    directiveContext = "The runner is steady. Provide positive reinforcement and prescribe a general maintenance Rhythm drill." + goalSuffix
                }
            }
        } else {
            let isolatedType = !run.detectedTypeRaw.isEmpty ? run.detectedTypeRaw : "Steady Effort"
            let cadenceFloor = 150
            let isSubFloor = Int(run.workingAvgCadence) < cadenceFloor
            let subFloorWarning = isSubFloor ? " (cadence is below \(cadenceFloor) SPM floor; DO NOT praise form precision)" : ""
            directiveContext = "Evaluate this isolated \(isolatedType) and provide a basic introductory drill\(subFloorWarning)."
            let cadenceStatus = isSubFloor ? "BELOW the \(cadenceFloor) SPM floor (slow turnover; do not praise form)" : "ABOVE the \(cadenceFloor) SPM floor"
            cadenceContext = "\(Int(run.workingAvgCadence)) SPM (\(cadenceStatus). No baseline available)."
            paceContext = "\(PaceFormatter.formatPace(secondsPerKilometer: run.workingAvgPace)) (No baseline available)."
            hrContext = "\(Int(run.workingAvgHeartRate)) BPM (No baseline available)."
        }

        // Check for recognized drill or previously prescribed drill execution
        let isCurrentRunDrill = run.framboiseTags.contains("prescribedDrill")
        if isCurrentRunDrill {
            // Find drill ID from tags
            let tags = run.framboiseTags.split(separator: ",").map(String.init).map { $0.trimmingCharacters(in: .whitespaces) }
            let drillIdStr = tags.first(where: { $0.hasPrefix("drill:") })?.replacingOccurrences(of: "drill:", with: "")
            let drillTitle = PreRunDrillId(rawValue: drillIdStr ?? "")?.title ?? run.detectedTypeRaw

            let thirtyDayCadence = Int(baseline?.avgCadence ?? (run.workingAvgCadence > 0 ? run.workingAvgCadence : 155))
            let actualCadence = Int(run.workingAvgCadence)

            var targetCadenceStr = "Steady"
            var inTargetStr = "OFF_TARGET"
            if let drillId = PreRunDrillId(rawValue: drillIdStr ?? "") {
                let template = DrillTemplate.template(for: drillId)
                let targetCadence = template.calculateTargetCadence(thirtyDayCadence)
                let drillObj = PreRunDrill(id: drillId, previousCadence: thirtyDayCadence, targetCadence: targetCadence)
                if let computed = drillObj.computedCadence {
                    targetCadenceStr = computed
                    if let range = drillObj.effectiveTargetCadence {
                        if range.contains(actualCadence) {
                            inTargetStr = "IN_TARGET"
                        } else if actualCadence >= range.lowerBound - 2 && actualCadence <= range.upperBound + 2 {
                            inTargetStr = "IN_TARGET (Close)"
                        }
                    }
                }
            }

            let currentOsc = run.workingAvgVerticalOscillation ?? run.rawAvgVerticalOscillation ?? 9.5
            let baseOsc = baseline?.avgOscillation ?? 9.5
            let oscDelta = currentOsc - baseOsc
            let oscDeltaStr = String(format: "%+.1f", oscDelta)

            directiveContext = """
            DRILL_EVALUATION: The runner completed their prescribed \(drillTitle) drill.
            TARGET: \(targetCadenceStr) | ACTUAL: \(actualCadence) SPM (\(inTargetStr)).
            VERTICAL_FORM: \(oscDeltaStr) cm change.
            DIRECTIVE: Commend turnover discipline and form adherence. Speak directly to drill technique and rhythm stability.
            """
        } else if let lastRun = priorRuns.sorted(by: { $0.date > $1.date }).first,
           let lastInsight = lastRun.insight,
           let prescribedDrill = lastInsight.drillRecommendations?.sorted(by: { ($0.orderIndex ?? 0) < ($1.orderIndex ?? 0) }).first {
            if prescribedDrill.isCompleted {
                directiveContext += " Prior drill completed: \(prescribedDrill.drillTitle) (target: \(prescribedDrill.targetCadence ?? "steady"), actual: \(Int(run.workingAvgCadence)) SPM)."
            } else {
                directiveContext += " Prior drill prescribed: \(prescribedDrill.drillTitle) (pending execution)."
            }
        }

        // Target-specific weighting:
        // When determining interval drill targets, weight prior interval runs highest (1.0x), then tempo (0.6x), then steady (0.2x).
        let intervalCandidateRuns = priorRuns.filter { $0.workingAvgCadence > 0 }
        func intervalTargetWeight(for r: RunRecord) -> Double {
            switch r.detectedTypeRaw {
            case "Intervals", "Pyramids":
                return 1.0 * r.duration
            case "Tempo Run", "Progression Run":
                return 0.6 * r.duration
            case "Fartlek":
                return 0.5 * r.duration
            default:
                return 0.2 * r.duration
            }
        }

        let totalIntervalWeight = intervalCandidateRuns.map { intervalTargetWeight(for: $0) }.reduce(0, +)
        let intervalCadenceBase: Double
        if totalIntervalWeight > 0 {
            intervalCadenceBase = intervalCandidateRuns.map { $0.workingAvgCadence * intervalTargetWeight(for: $0) }.reduce(0, +) / totalIntervalWeight
        } else {
            intervalCadenceBase = baseline?.avgCadence ?? (run.workingAvgCadence > 0 ? run.workingAvgCadence : 155)
        }

        let thirtyDayCadence = Int(baseline?.avgCadence ?? (run.workingAvgCadence > 0 ? run.workingAvgCadence : 155))
        let defaultTemplate = DrillTemplate.template(for: .cadencePyramids)
        let intervalTarget = defaultTemplate.calculateTargetCadence(Int(intervalCadenceBase))
        let recoveryTarget = max(140, thirtyDayCadence)

        if run.isIndoor == nil {
            run.isIndoor = (run.dataSourceRaw == "gymkit") ? true : false
        }
        if run.detectedTypeRaw.isEmpty {
            run.detectedTypeRaw = "Steady Effort"
        }
        let workoutType = run.detectedTypeRaw
        let currentGoal = UserDefaults.standard.string(forKey: "trainingGoal") ?? "Base Building"

        do {
            let runData = RunDataForAI(
                workoutType: workoutType,
                runnerGoal: currentGoal,
                directiveContext: directiveContext,
                paceContext: paceContext,
                hrContext: hrContext,
                cadenceContext: cadenceContext,
                zone4Context: zone4Context,
                cvContext: cvContext,
                slopeContext: slopeContext,
                intervalCadence: "\(intervalTarget)",
                recoveryCadence: "\(recoveryTarget)",
                isIndoor: run.isIndoor ?? false
            )

            let payload = try await CoachingEngine.shared.generateInsight(for: runData)

            let insight = CoachingInsight(
                headline: payload.headline,
                longitudinalObservation: payload.observation
            )
            modelContext.insert(insight)

            let isOlderThan7Days = (Calendar.current.dateComponents([.day], from: targetDate, to: Date()).day ?? 0) > 7

            var drillRecs: [DrillRecommendation] = []
            if !isOlderThan7Days {
                for (index, suggestedDrill) in payload.drills.enumerated() {
                    let preRunId = PreRunDrillId(rawValue: suggestedDrill.preRunDrillId)
                        ?? PreRunDrillId.allCases.first(where: {
                            $0.rawValue.localizedCaseInsensitiveCompare(suggestedDrill.drillTitle) == .orderedSame ||
                            $0.title.localizedCaseInsensitiveCompare(suggestedDrill.drillTitle) == .orderedSame ||
                            $0.title.localizedCaseInsensitiveCompare(suggestedDrill.drillTitle.replacingOccurrences(of: "_", with: " ")) == .orderedSame
                        })
                        ?? .strides
                    let template = DrillTemplate.template(for: preRunId)
                    let cleanDrillTitle = PreRunDrillId.canonicalDrillTitle(for: suggestedDrill.drillTitle)
                        ?? template.title
                    let effectiveCadence = max(thirtyDayCadence, Int(run.workingAvgCadence))
                    let computedTarget = template.calculateTargetCadence(effectiveCadence)
                    let preRunDrill = PreRunDrill(id: preRunId, previousCadence: effectiveCadence, targetCadence: computedTarget)

                    let targetCadenceStr = preRunDrill.computedCadence.map { "\($0) SPM" }

                    // Prescriptive somatic cue (form, breathing, posture) without conflicting workout plan stats
                    let templateCue = template.generateInstructionalCue(computedTarget)
                    let drillCueText: String
                    if !suggestedDrill.drillCues.isEmpty && !suggestedDrill.drillCues.localizedCaseInsensitiveContains("spm") {
                        drillCueText = suggestedDrill.drillCues
                    } else {
                        drillCueText = templateCue
                    }

                    let drill = DrillRecommendation(
                        drillTitle: cleanDrillTitle,
                        preRunDrillId: preRunId.rawValue,
                        drillPurpose: suggestedDrill.drillPurpose.isEmpty ? template.defaultPurpose : suggestedDrill.drillPurpose,
                        drillWork: preRunDrill.defaultWorkString,
                        drillCues: drillCueText,
                        drillEffort: preRunDrill.defaultEffortString,
                        drillRecovery: preRunDrill.defaultRecoveryString,
                        targetCadence: targetCadenceStr,
                        previousCadence: preRunDrill.previousCadence,
                        isCompleted: false,
                        orderIndex: index
                    )
                    modelContext.insert(drill)
                    drillRecs.append(drill)
                }
            }
            insight.drillRecommendations = drillRecs

            run.insight = insight
            try modelContext.save()

        } catch {
            print("AI Generation Failed: \(error)")
        }
    }
}
