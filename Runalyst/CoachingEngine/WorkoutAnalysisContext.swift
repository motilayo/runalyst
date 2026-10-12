import Foundation
import SwiftData

/// Structured dynamic evaluation for an individual kilometer split.
struct SplitEvaluation: Sendable, Equatable {
    let index: Int
    let paceSecondsPerKm: Double
    let paceFormatted: String
    let cadence: Int
    let heartRate: Int
    let isFastest: Bool
    let isSlowest: Bool
    let paceDeltaVsRunSec: Int
    let cadenceDeltaVsRun: Int
    let hrDeltaVsPrevious: Int?
    let observation: String
    let letterGrade: String
}

/// Comprehensive, data-grounded running analysis derived from stored workout telemetry.
/// Translates raw stored data into rich physiological, biomechanical, and pacing findings.
@MainActor
struct WorkoutAnalysisContext {
    let runRecord: RunRecord
    let splits: [RunSplit]
    let phaseSegments: [PhaseSegment]
    let baselineStats: BaselineStats?
    let recoveryTimeline: RecoveryTimeline
    let macroProfile: MacroProfile?

    // Derived Core Metrics
    let workingPaceSec: Double
    let workingPaceFormatted: String
    let workingCadence: Int
    let workingHR: Int
    let percentZone4: Int
    let isIndoor: Bool
    let detectedType: String

    // Pacing Profile
    let fastestSplit: RunSplit?
    let slowestSplit: RunSplit?
    let splitEvaluations: [SplitEvaluation]
    let pacingTrendDescription: String
    let firstHalfPaceSec: Double
    let secondHalfPaceSec: Double

    // Biomechanical & Physiological Markers
    let isSubFloorCadence: Bool
    let hasCardiacDrift: Bool
    let cardiacDriftMagnitudeBPM: Int
    let verticalOscillationCM: Double?
    let strideLengthM: Double?

    // Interval Specific Findings
    let workSegments: [PhaseSegment]
    let recoverySegments: [PhaseSegment]
    let fastestWorkRep: PhaseSegment?
    let slowestWorkRep: PhaseSegment?
    let workRepPaceSpreadSec: Double

    // Longitudinal Contrast
    let baselinePaceDeltaSec: Int?
    let baselineHRDelta: Int?
    let baselineCadenceDelta: Int?
    let longitudinalDiagnosis: String?

    // Overall Grade
    let overallGradeReport: RunGradeReport

    init(
        runRecord: RunRecord,
        runSignature: RunSignature?,
        macroProfile: MacroProfile?,
        recoveryTimeline: RecoveryTimeline,
        baselineStats: (avgPace: Double, avgCadence: Double, avgHR: Double)? = nil
    ) {
        self.runRecord = runRecord
        self.macroProfile = macroProfile
        self.recoveryTimeline = recoveryTimeline
        if let base = baselineStats {
            self.baselineStats = BaselineStats(avgPace: base.avgPace, avgCadence: base.avgCadence, avgHR: base.avgHR, avgOscillation: 0)
        } else if let pace = macroProfile?.baselinePace,
                  let hr = macroProfile?.baselineHR,
                  let cad = macroProfile?.baselineCadence {
            self.baselineStats = BaselineStats(avgPace: pace, avgCadence: cad, avgHR: hr, avgOscillation: 0)
        } else {
            self.baselineStats = nil
        }

        let sig = runSignature ?? runRecord.signature
        self.phaseSegments = sig?.phaseSegments ?? []

        // Resolve Splits
        var resolvedSplits = sig?.splits ?? []
        if resolvedSplits.isEmpty && !self.phaseSegments.isEmpty {
            resolvedSplits = AnalystChatEngine.synthesizeSplitsFromSegments(self.phaseSegments)
        }
        self.splits = resolvedSplits

        self.workingPaceSec = runRecord.workingAvgPace
        self.workingPaceFormatted = PaceFormatter.formatPace(secondsPerKilometer: runRecord.workingAvgPace)
        self.workingCadence = Int(runRecord.workingAvgCadence)
        self.workingHR = Int(runRecord.workingAvgHeartRate)
        self.percentZone4 = Int((runRecord.percentZone4 * 100).rounded())
        self.isIndoor = runRecord.isIndoor ?? false
        self.detectedType = runRecord.detectedTypeRaw.isEmpty ? "Run" : runRecord.detectedTypeRaw

        // Biomechanics
        self.isSubFloorCadence = self.workingCadence < 150
        self.verticalOscillationCM = runRecord.workingAvgVerticalOscillation
        self.strideLengthM = runRecord.workingAvgStrideLength

        // Interval Segments
        let work = self.phaseSegments.filter { $0.kind == "work" && $0.avgPace > 0 }
        let rec = self.phaseSegments.filter { $0.kind == "recovery" }
        self.workSegments = work
        self.recoverySegments = rec
        self.fastestWorkRep = work.min(by: { $0.avgPace < $1.avgPace })
        self.slowestWorkRep = work.max(by: { $0.avgPace < $1.avgPace })
        if let f = self.fastestWorkRep, let s = self.slowestWorkRep {
            self.workRepPaceSpreadSec = s.avgPace - f.avgPace
        } else {
            self.workRepPaceSpreadSec = 0
        }

        // Split Extremes & Half Paces
        let fastest = resolvedSplits.min(by: { $0.paceSecondsPerKm < $1.paceSecondsPerKm })
        let slowest = resolvedSplits.max(by: { $0.paceSecondsPerKm < $1.paceSecondsPerKm })
        self.fastestSplit = fastest
        self.slowestSplit = slowest

        let count = resolvedSplits.count
        if count >= 2 {
            let mid = count / 2
            let firstHalf = resolvedSplits.prefix(mid)
            let secondHalf = resolvedSplits.suffix(count - mid)
            self.firstHalfPaceSec = firstHalf.reduce(0.0) { $0 + $1.paceSecondsPerKm } / Double(firstHalf.count)
            self.secondHalfPaceSec = secondHalf.reduce(0.0) { $0 + $1.paceSecondsPerKm } / Double(secondHalf.count)

            let diff = self.firstHalfPaceSec - self.secondHalfPaceSec // positive = 2nd half faster
            if diff >= 6.0 {
                let secStr = Int(diff.rounded())
                self.pacingTrendDescription = "Negative split execution (\(secStr)s/km faster in the second half)"
            } else if diff <= -6.0 {
                let secStr = abs(Int(diff.rounded()))
                self.pacingTrendDescription = "Positive split fade (\(secStr)s/km slower in the second half)"
            } else {
                self.pacingTrendDescription = "Even, metronomic pacing discipline throughout"
            }
        } else {
            self.firstHalfPaceSec = self.workingPaceSec
            self.secondHalfPaceSec = self.workingPaceSec
            self.pacingTrendDescription = "Consistent single-segment effort"
        }

        // Cardiac Drift Detection
        if resolvedSplits.count >= 4 {
            let lateSplits = resolvedSplits.suffix(resolvedSplits.count / 2)
            let earlySplits = resolvedSplits.prefix(resolvedSplits.count / 2)
            let earlyHR = earlySplits.reduce(0.0) { $0 + $1.avgHeartRate } / Double(earlySplits.count)
            let lateHR = lateSplits.reduce(0.0) { $0 + $1.avgHeartRate } / Double(lateSplits.count)
            let hrRise = Int((lateHR - earlyHR).rounded())
            let paceDiff = (lateSplits.reduce(0.0) { $0 + $1.paceSecondsPerKm } / Double(lateSplits.count)) -
                           (earlySplits.reduce(0.0) { $0 + $1.paceSecondsPerKm } / Double(earlySplits.count))
            // Drift if HR climbed >= 5 BPM while pace was flat or slower (paceDiff >= -2)
            if hrRise >= 5 && paceDiff >= -2.0 {
                self.hasCardiacDrift = true
                self.cardiacDriftMagnitudeBPM = hrRise
            } else {
                self.hasCardiacDrift = false
                self.cardiacDriftMagnitudeBPM = 0
            }
        } else {
            self.hasCardiacDrift = false
            self.cardiacDriftMagnitudeBPM = 0
        }

        // Longitudinal Contrast
        if let base = self.baselineStats {
            let pDelta = Int(base.avgPace - self.workingPaceSec)
            let hDelta = self.workingHR - Int(base.avgHR)
            let cDelta = self.workingCadence - Int(base.avgCadence)
            self.baselinePaceDeltaSec = pDelta
            self.baselineHRDelta = hDelta
            self.baselineCadenceDelta = cDelta

            if pDelta >= 5 && hDelta <= 2 {
                self.longitudinalDiagnosis = "Faster than 30-day baseline (\(pDelta)s/km faster) at stable heart rate, indicating aerobic efficiency progression."
            } else if pDelta <= -5 && hDelta >= 4 {
                self.longitudinalDiagnosis = "Slower than 30-day baseline (\(abs(pDelta))s/km slower) with elevated heart rate (+\(hDelta) BPM), suggesting acute fatigue or recovery debt."
            } else {
                self.longitudinalDiagnosis = "In line with your 30-day rolling baseline averages."
            }
        } else {
            self.baselinePaceDeltaSec = nil
            self.baselineHRDelta = nil
            self.baselineCadenceDelta = nil
            self.longitudinalDiagnosis = nil
        }

        // Synthesize Dynamic Split Evaluations
        var evals: [SplitEvaluation] = []
        for (i, s) in resolvedSplits.enumerated() {
            let pFormatted = PaceFormatter.formatPace(secondsPerKilometer: s.paceSecondsPerKm)
            let isFast = (fastest != nil && s.paceSecondsPerKm == fastest?.paceSecondsPerKm)
            let isSlow = (slowest != nil && s.paceSecondsPerKm == slowest?.paceSecondsPerKm)
            let paceDelta = Int(self.workingPaceSec - s.paceSecondsPerKm)
            let cadDelta = Int(s.avgCadence) - self.workingCadence
            let priorSplit = i > 0 ? resolvedSplits[i - 1] : nil
            let hrDeltaVsPrior = priorSplit.map { Int(s.avgHeartRate - $0.avgHeartRate) }

            // Dynamic Assessment Narrative
            let note: String
            let grade: String

            if isFast && resolvedSplits.count > 1 {
                grade = "A"
                if cadDelta >= 3 {
                    note = "fastest split with sharp \(cadDelta) SPM cadence surge and decisive pace control"
                } else {
                    note = "fastest split of the run with strong pace discipline"
                }
            } else if isSlow && resolvedSplits.count > 1 {
                grade = "B"
                if i == 0 {
                    note = "opening kilometer, controlled pace as you settled into your stride"
                } else {
                    note = "slowest split, pacing eased back while maintaining turnover"
                }
            } else if s.avgCadence < 150 {
                grade = "B-"
                note = "cadence dipped to \(Int(s.avgCadence)) SPM below the 150 SPM floor"
            } else if let hrDelta = hrDeltaVsPrior, hrDelta >= 7 && paceDelta <= -3 {
                grade = "B"
                note = "aerobic decoupling with heart rate climbing +\(hrDelta) BPM despite slower pace"
            } else if paceDelta >= 5 {
                grade = "A-"
                note = "strong sustained surge (\(paceDelta)s/km faster than run average)"
            } else if paceDelta <= -5 {
                grade = "B"
                note = "pacing eased back by \(abs(paceDelta))s/km to manage cardiovascular effort"
            } else {
                grade = "A-"
                note = "even metronomic pacing at \(pFormatted) with steady \(Int(s.avgCadence)) SPM turnover"
            }

            evals.append(SplitEvaluation(
                index: s.index,
                paceSecondsPerKm: s.paceSecondsPerKm,
                paceFormatted: pFormatted,
                cadence: Int(s.avgCadence),
                heartRate: Int(s.avgHeartRate),
                isFastest: isFast,
                isSlowest: isSlow,
                paceDeltaVsRunSec: paceDelta,
                cadenceDeltaVsRun: cadDelta,
                hrDeltaVsPrevious: hrDeltaVsPrior,
                observation: note,
                letterGrade: grade
            ))
        }
        self.splitEvaluations = evals

        // Overall Grade Report
        let gradeInput = RunGradeInput(
            type: self.detectedType,
            isHard: ReadinessRunSnapshot(run: runRecord).isHardSession,
            percentZone4: runRecord.percentZone4,
            cadence: self.workingCadence,
            workPaces: work.map(\.avgPace),
            paceDeltaVsBaseline: self.baselinePaceDeltaSec.map(Double.init),
            hrDeltaVsBaseline: self.baselineHRDelta.map(Double.init),
            cadenceFade: self.hasCardiacDrift || (evals.last?.cadence ?? self.workingCadence) < self.workingCadence - 4,
            cardiacDrift: self.hasCardiacDrift
        )
        self.overallGradeReport = RunGrade.evaluate(gradeInput)
    }

    // MARK: - Formatted Dynamic Text Presentations

    /// Builds a rich-text split-by-split report with zero canned boilerplate.
    func formatSplitReport() -> String {
        guard !splitEvaluations.isEmpty else {
            return overallGradeReport.sentence
        }

        var lines = ["Here is the breakdown of your splits:"]
        for s in splitEvaluations.prefix(8) {
            lines.append("• km \(s.index) (\(s.paceFormatted), \(s.cadence) SPM, \(s.heartRate) BPM): \(s.letterGrade) — \(s.observation)")
        }

        if let f = fastestSplit, let s = slowestSplit, splitEvaluations.count >= 2 {
            var fStartSec: Double = 0
            for split in splits.prefix(while: { $0.index < f.index }) {
                fStartSec += split.durationSeconds
            }
            let fMinStart = Int(fStartSec / 60)
            let fMinEnd = Int((fStartSec + f.durationSeconds) / 60)

            var sStartSec: Double = 0
            for split in splits.prefix(while: { $0.index < s.index }) {
                sStartSec += split.durationSeconds
            }
            let sMinStart = Int(sStartSec / 60)
            let sMinEnd = Int((sStartSec + s.durationSeconds) / 60)

            let fPace = PaceFormatter.formatPace(secondsPerKilometer: f.paceSecondsPerKm)
            let sPace = PaceFormatter.formatPace(secondsPerKilometer: s.paceSecondsPerKm)
            lines.append("")
            lines.append("Overall split execution: \(overallGradeReport.grade). \(pacingTrendDescription). Fastest split was km \(f.index) (min \(fMinStart)–\(fMinEnd)) at \(fPace); slowest was km \(s.index) (min \(sMinStart)–\(sMinEnd)) at \(sPace).")
        }

        if let fRep = fastestWorkRep, let sRep = slowestWorkRep, workSegments.count >= 2 {
            let fIdx = (workSegments.firstIndex(where: { $0.id == fRep.id }) ?? 0) + 1
            let sIdx = (workSegments.firstIndex(where: { $0.id == sRep.id }) ?? 0) + 1
            let fRepPace = PaceFormatter.formatPace(secondsPerKilometer: fRep.avgPace)
            let sRepPace = PaceFormatter.formatPace(secondsPerKilometer: sRep.avgPace)
            let fRepStart = Int(fRep.startSeconds / 60)
            let fRepEnd = Int(fRep.endSeconds / 60)
            let sRepStart = Int(sRep.startSeconds / 60)
            let sRepEnd = Int(sRep.endSeconds / 60)
            lines.append("For your intervals, fastest work rep was Rep \(fIdx) (min \(fRepStart)–\(fRepEnd)) at \(fRepPace); slowest was Rep \(sIdx) (min \(sRepStart)–\(sRepEnd)) at \(sRepPace).")
        }

        return lines.joined(separator: "\n")
    }

    /// Formats precomputed analytical findings into a compact context block for the on-device language model.
    func groundedPromptSummary() -> String {
        var lines: [String] = []

        let durationMin = max(1, Int((runRecord.duration / 60.0).rounded()))
        let distKm = String(format: "%.1f km", runRecord.totalDistanceMeters / 1000.0)

        lines.append("WORKOUT PROFILE:")
        lines.append("- Type: \(detectedType) (\(isIndoor ? "Treadmill" : "Outdoors"))")
        lines.append("- Volume: \(distKm) in \(durationMin) min (Working Pace: \(workingPaceFormatted))")
        lines.append("- Biomechanics: Cadence \(workingCadence) SPM (\(isSubFloorCadence ? "BELOW 150 floor" : "healthy turnover above floor"))")
        if let osc = verticalOscillationCM {
            lines.append("- Vertical Oscillation: \(String(format: "%.1f", osc)) cm")
        }
        if let str = strideLengthM {
            lines.append("- Stride Length: \(String(format: "%.2f", str)) m")
        }
        lines.append("- Cardiovascular Strain: Working HR \(workingHR) BPM; \(percentZone4)% in Zone 4 (Threshold)")

        // Pacing & Splits
        if !splitEvaluations.isEmpty {
            lines.append("")
            lines.append("PACING & SPLIT FINDINGS (\(splitEvaluations.count) splits):")
            lines.append("- Trend: \(pacingTrendDescription)")
            if let f = fastestSplit {
                lines.append("- Fastest Split: km \(f.index) at \(PaceFormatter.formatPace(secondsPerKilometer: f.paceSecondsPerKm)) (\(Int(f.avgCadence)) SPM, \(Int(f.avgHeartRate)) BPM)")
            }
            if let s = slowestSplit {
                lines.append("- Slowest Split: km \(s.index) at \(PaceFormatter.formatPace(secondsPerKilometer: s.paceSecondsPerKm)) (\(Int(s.avgCadence)) SPM, \(Int(s.avgHeartRate)) BPM)")
            }
            if hasCardiacDrift {
                lines.append("- Physiological Decoupling: Cardiac drift detected (+\(cardiacDriftMagnitudeBPM) BPM HR rise in second half)")
            }
            lines.append("Split Details:")
            for s in splitEvaluations.prefix(8) {
                lines.append("  • km \(s.index): \(s.paceFormatted), \(s.cadence) SPM, \(s.heartRate) BPM — \(s.observation)")
            }
        }

        // Interval Work Reps
        if !workSegments.isEmpty {
            lines.append("")
            lines.append("INTERVAL EXECUTION (\(workSegments.count) work reps):")
            if let f = fastestWorkRep, let s = slowestWorkRep {
                lines.append("- Rep Pace Range: \(PaceFormatter.formatPace(secondsPerKilometer: f.avgPace)) to \(PaceFormatter.formatPace(secondsPerKilometer: s.avgPace)) (spread: \(Int(workRepPaceSpreadSec))s/km)")
            }
            if workRepPaceSpreadSec <= 8.0 {
                lines.append("- Rep Repeatability: Disciplined, tightly controlled interval pacing")
            } else {
                lines.append("- Rep Repeatability: High pace spread between reps; fatigue decay on late reps")
            }
        }

        // Baseline Context
        if let diag = longitudinalDiagnosis {
            lines.append("")
            lines.append("30-DAY BASELINE CONTRAST:")
            lines.append("- \(diag)")
        }

        // Future Training & Recovery
        lines.append("")
        lines.append("[FUTURE TRAINING & RECOVERY - Reference ONLY if asked about next run, readiness, recovery, or drills]:")
        lines.append("- Readiness: \(recoveryTimeline.state.rawValue)")
        if recoveryTimeline.readyForHard {
            lines.append("- Recovery Clearance: Cleared for hard efforts")
        } else if let cap = recoveryTimeline.easyCap {
            lines.append("- Recovery Clearance: Hard efforts cleared \(recoveryTimeline.earliestHardPhrase). Active recovery cap: \(cap.lowerBound)–\(cap.upperBound) min")
        }
        if let drill = runRecord.insight?.drillRecommendations?.first ?? runRecord.insight?.drillRecommendation {
            lines.append("- Recommended Technique Drill: \(drill.drillTitle)")
        }

        return lines.joined(separator: "\n")
    }
}
