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

    // Athlete Profile & Terrain
    let runnerProfile: RunnerProfile
    let elevationGainMeters: Double
    let environmentalModifier: EnvironmentalModifier?
    let environmentModifier: String?
    let verticalRatio: Double?
    let efficiencyFactor: Double?
    let baselineEfficiencyFactor: Double?
    let efficiencyFactorDeltaPercent: Double?
    let strideArchetype: String

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

    // Date & Temporal Awareness
    let currentDate: Date
    let currentDateFormatted: String
    let currentWeekday: String
    let workoutDate: Date
    let workoutDateFormatted: String
    let workoutWeekday: String
    let daysSinceWorkout: Int
    let hoursSinceWorkout: Double
    let isWorkoutToday: Bool
    let isWorkoutYesterday: Bool
    let hasRunToday: Bool
    let hasRunYesterday: Bool

    // Overall Grade
    let overallGradeReport: RunGradeReport

    // Swift Deterministic Diagnostic Verdicts
    let physiologicalVerdicts: PhysiologicalVerdicts

    // Locked Training Prescription
    let lockedPrescription: LockedTrainingPrescription

    init(
        runRecord: RunRecord,
        runSignature: RunSignature?,
        macroProfile: MacroProfile?,
        recoveryTimeline: RecoveryTimeline,
        baselineStats: (avgPace: Double, avgCadence: Double, avgHR: Double)? = nil,
        runnerProfile: RunnerProfile? = nil,
        isSubjectiveDistress: Bool = false,
        totalHistoricalRunsCount: Int = 1
    ) {
        self.runRecord = runRecord
        self.macroProfile = macroProfile
        self.recoveryTimeline = recoveryTimeline
        self.runnerProfile = runnerProfile ?? RunnerProfile.compute(from: [runRecord], now: recoveryTimeline.now)

        let now = recoveryTimeline.now
        let cal = Calendar.current
        self.currentDate = now
        self.workoutDate = runRecord.date

        self.isWorkoutToday = cal.isDateInToday(runRecord.date)
        self.isWorkoutYesterday = cal.isDateInYesterday(runRecord.date)
        let daysDiff = cal.dateComponents([.day], from: cal.startOfDay(for: runRecord.date), to: cal.startOfDay(for: now)).day ?? 0
        self.daysSinceWorkout = max(0, daysDiff)
        self.hoursSinceWorkout = max(0, now.timeIntervalSince(runRecord.date) / 3600.0)

        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale(identifier: "en_US_POSIX")
        weekdayFormatter.dateFormat = "EEEE"
        self.currentWeekday = weekdayFormatter.string(from: now)
        self.workoutWeekday = weekdayFormatter.string(from: runRecord.date)

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "MMM d, yyyy"
        self.currentDateFormatted = dateFormatter.string(from: now)
        self.workoutDateFormatted = dateFormatter.string(from: runRecord.date)

        var todayRuns = 0
        var yesterdayRuns = 0
        if let context = runRecord.modelContext {
            let startOfYesterday = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: now)) ?? now
            let desc = FetchDescriptor<RunRecord>(predicate: #Predicate<RunRecord> { $0.date >= startOfYesterday })
            if let fetched = try? context.fetch(desc) {
                todayRuns = fetched.filter { cal.isDateInToday($0.date) }.count
                yesterdayRuns = fetched.filter { cal.isDateInYesterday($0.date) }.count
            }
        } else {
            if self.isWorkoutToday { todayRuns = 1 }
            if self.isWorkoutYesterday { yesterdayRuns = 1 }
        }
        self.hasRunToday = todayRuns > 0
        self.hasRunYesterday = yesterdayRuns > 0

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

        // Biomechanics & Height Calibration
        self.isSubFloorCadence = self.workingCadence < self.runnerProfile.heightAdjustedCadenceFloor
        self.verticalOscillationCM = runRecord.workingAvgVerticalOscillation
        self.strideLengthM = runRecord.workingAvgStrideLength
        self.verticalRatio = runRecord.verticalRatio

        // Environmental & Terrain Modifiers
        let splitElevation = self.splits.reduce(0.0) { $0 + $1.elevationGainMeters }
        self.elevationGainMeters = splitElevation
        let ambientTemp = runRecord.ambientTemperatureCelsius
        let ambientHum = runRecord.ambientHumidity
        let envMod = WeatherProxyEngine.evaluateEnvironmentalModifier(
            temperatureCelsius: ambientTemp,
            humidity: ambientHum,
            isIndoor: self.isIndoor,
            elevationGainMeters: self.elevationGainMeters
        )
        self.environmentalModifier = envMod

        if self.elevationGainMeters >= 40.0 {
            self.environmentModifier = "High Elevation Gain (+\(Int(self.elevationGainMeters)) m) — cardiac drift expected from hill climbs"
        } else if self.isIndoor {
            self.environmentModifier = "Indoor Treadmill — flat deck pacing with zero wind resistance"
        } else if envMod == .highHeat {
            let tempDesc = ambientTemp.map { String(format: "%.0f°C", $0) } ?? "≥22°C"
            let humDesc = ambientHum.map { "\($0 <= 1.0 ? Int($0 * 100) : Int($0))%" } ?? "≥75%"
            self.environmentModifier = "High Heat & Humidity (\(tempDesc), \(humDesc)) — elevated thermal strain and reduced convective cooling"
        } else {
            self.environmentModifier = nil
        }

        // Efficiency Factor (Speed in m/min / HR in BPM)
        self.efficiencyFactor = runRecord.efficiencyFactor
        if let base = self.baselineStats, base.avgPace > 0 && base.avgHR > 0 {
            let baseSpeed = 60_000.0 / base.avgPace
            let baseEF = baseSpeed / base.avgHR
            self.baselineEfficiencyFactor = baseEF
            if let ef = self.efficiencyFactor, baseEF > 0 {
                self.efficiencyFactorDeltaPercent = ((ef - baseEF) / baseEF) * 100.0
            } else {
                self.efficiencyFactorDeltaPercent = nil
            }
        } else {
            self.baselineEfficiencyFactor = nil
            self.efficiencyFactorDeltaPercent = nil
        }

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

        // Stride Archetype Evaluation (Outdoor 3D vs Indoor 2D Fallback)
        let scale = self.runnerProfile.heightScaleFactor
        let floor = Double(self.runnerProfile.heightAdjustedCadenceFloor)
        let highCadence = Double(self.runnerProfile.heightAdjustedHighCadenceThreshold)
        let maxOsc = self.runnerProfile.heightAdjustedMaxOscillationCM

        if !self.isIndoor, let osc = self.verticalOscillationCM, let stride = self.strideLengthM, stride > 0 {
            let cad = Double(self.workingCadence)
            if cad >= highCadence && osc <= 8.2 * scale {
                self.strideArchetype = "Compact High-Turnover (Economical)"
            } else if cad < floor && osc >= maxOsc {
                self.strideArchetype = "High-Bounce Overstrider (Elevated Impact Shock)"
            } else {
                self.strideArchetype = "Balanced Stride (Sustainable Rhythm)"
            }
        } else {
            // Indoor / Treadmill 2D Fallback
            let cad = Double(self.workingCadence)
            if cad >= floor && !self.hasCardiacDrift {
                self.strideArchetype = "High-Cadence Sustained (Treadmill Rhythm)"
            } else if cad < floor && self.hasCardiacDrift {
                self.strideArchetype = "Low-Cadence Straining (Treadmill Deck Braking)"
            } else {
                self.strideArchetype = "Balanced Treadmill Cruising"
            }
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

        // Swift Physics Causal Verdicts
        let physInput = PhysiologicalInput(
            workingCadence: self.workingCadence,
            heightAdjustedCadenceFloor: self.runnerProfile.heightAdjustedCadenceFloor,
            splits: resolvedSplits,
            elevationGainMeters: self.elevationGainMeters,
            hasCardiacDrift: self.hasCardiacDrift,
            cardiacDriftMagnitudeBPM: self.cardiacDriftMagnitudeBPM,
            durationSeconds: runRecord.duration,
            verticalRatio: self.verticalRatio,
            verticalOscillationCM: self.verticalOscillationCM,
            isIndoor: self.isIndoor,
            firstHalfPaceSec: self.firstHalfPaceSec,
            secondHalfPaceSec: self.secondHalfPaceSec,
            fastestSplit: self.fastestSplit,
            slowestSplit: self.slowestSplit,
            avgHeartRate: self.workingHR,
            ambientTemperatureC: ambientTemp,
            ambientHumidity: ambientHum,
            environmentalModifier: envMod
        )
        self.physiologicalVerdicts = PhysiologicalDiagnosisEngine.evaluate(physInput)

        // Swift Locked Training Prescription
        let useMetric = UserDefaults.standard.bool(forKey: "useMetricSystem")
        let tzInput = TrainingZoneInput(
            baselinePaceSec: self.baselineStats?.avgPace,
            workoutPaceSec: self.workingPaceSec,
            activeGoal: self.runnerProfile.trainingGoal,
            experienceLevel: self.runnerProfile.experienceLevel,
            readyForHard: self.recoveryTimeline.readyForHard,
            daysSinceWorkout: self.daysSinceWorkout,
            heightAdjustedCadenceFloor: self.runnerProfile.heightAdjustedCadenceFloor,
            useMetricSystem: useMetric,
            isSubjectiveDistress: isSubjectiveDistress,
            totalHistoricalRunsCount: totalHistoricalRunsCount
        )
        self.lockedPrescription = TrainingZoneEngine.computePrescription(tzInput)
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
    func groundedPromptSummary(turnContext: ManagedTurnContext? = nil) -> String {
        if let tc = turnContext, tc.stripWorkoutPayload {
            var lines = ["ATHLETE IDENTITY & CURRENT LOAD:"]
            lines.append("- Athletic Experience Level: \(runnerProfile.experienceLevel)")
            lines.append("- Active Training Goal: \(runnerProfile.trainingGoal)")
            lines.append("- Current Date (Today): \(currentWeekday), \(currentDateFormatted)")
            lines.append("")
            lines.append(tc.promptHeader)
            return lines.joined(separator: "\n")
        }

        if let tc = turnContext, tc.turnDomain == .futureSessionPlanning || tc.prunePhysiologicalVerdicts {
            var lines = ["ATHLETE IDENTITY & CURRENT LOAD:"]
            lines.append("- Athletic Experience Level: \(runnerProfile.experienceLevel)")
            lines.append("- Active Training Goal: \(runnerProfile.trainingGoal)")
            lines.append("- Current 30-Day Training Load: \(runnerProfile.loadSummary)")
            lines.append("- Runner Height: \(Int(runnerProfile.userHeightCm)) cm (Height-calibrated cadence floor: \(runnerProfile.heightAdjustedCadenceFloor) SPM)")
            lines.append("")
            lines.append("CALENDAR & TEMPORAL CONTEXT:")
            lines.append("- Current Date (Today): \(currentWeekday), \(currentDateFormatted)")
            let elapsedNote: String = {
                if isWorkoutToday { return "logged earlier today" }
                if isWorkoutYesterday { return "logged yesterday" }
                return "\(daysSinceWorkout) days ago on \(workoutWeekday), \(workoutDateFormatted)"
            }()
            lines.append("- Workout Date: \(workoutWeekday), \(workoutDateFormatted) (\(elapsedNote))")
            if isWorkoutToday {
                lines.append("- Activity Status: This workout took place today.")
            } else {
                let todayStatus = hasRunToday ? "Logged another run today." : "Did NOT run today."
                let yesterdayStatus = hasRunYesterday ? "Logged a run yesterday." : "Did NOT run yesterday."
                let restNote = daysSinceWorkout > 1 ? "\(daysSinceWorkout) days of rest since this session (fully rested and fresh)." : "1 day of rest since this session."
                lines.append("- Recent Activity: \(todayStatus) \(yesterdayStatus) (\(restNote))")
            }
            let durationMin = max(1, Int((runRecord.duration / 60.0).rounded()))
            let distKm = String(format: "%.1f km", runRecord.totalDistanceMeters / 1000.0)
            lines.append("")
            lines.append("RECENT SESSION CONTEXT (Brief reference for last logged session):")
            lines.append("- Last Session (\(workoutWeekday)): \(detectedType) (\(isIndoor ? "Treadmill" : "Outdoors")), \(distKm) in \(durationMin) min, Working Pace: \(workingPaceFormatted), Working HR: \(workingHR) BPM")
            lines.append("")
            lines.append("FUTURE TRAINING & READINESS:")
            lines.append("- Current Readiness: \(recoveryTimeline.state.rawValue)")
            if recoveryTimeline.readyForHard {
                lines.append("- Recovery Status: FULLY RECOVERED and fresh. Cleared for any workout including speed, tempo, or intervals (last hard session was \(Int(hoursSinceWorkout))h ago; required was only \(Int(recoveryTimeline.requiredHours))h). Zero residual fatigue remains.")
            } else if let cap = recoveryTimeline.easyCap {
                lines.append("- Recovery Status: In active recovery window until \(recoveryTimeline.earliestHardPhrase). Keep next run easy (cap: \(cap.lowerBound)–\(cap.upperBound) min).")
            }
            lines.append("")
            lines.append(lockedPrescription.promptDescription)
            if let drill = runRecord.insight?.drillRecommendations?.first ?? runRecord.insight?.drillRecommendation {
                lines.append("- Pre-Run Technique Drill Option: \(drill.drillTitle) (warm-up turnover prep, not mandatory rehab)")
            }
            lines.append("")
            lines.append(tc.promptHeader)
            return lines.joined(separator: "\n")
        }

        var lines: [String] = []

        // Athlete Identity & Current Load
        lines.append("ATHLETE IDENTITY & CURRENT LOAD:")
        lines.append("- Athletic Experience Level: \(runnerProfile.experienceLevel)")
        lines.append("- Active Training Goal: \(runnerProfile.trainingGoal)")
        lines.append("- Current 30-Day Training Load: \(runnerProfile.loadSummary)")
        lines.append("- Runner Height: \(Int(runnerProfile.userHeightCm)) cm (Height-calibrated cadence floor: \(runnerProfile.heightAdjustedCadenceFloor) SPM)")
        lines.append("")

        // Calendar & Temporal Grounding
        lines.append("CALENDAR & TEMPORAL CONTEXT:")
        lines.append("- Current Date (Today): \(currentWeekday), \(currentDateFormatted)")
        let elapsedNote: String = {
            if isWorkoutToday { return "logged earlier today" }
            if isWorkoutYesterday { return "logged yesterday" }
            return "\(daysSinceWorkout) days ago on \(workoutWeekday), \(workoutDateFormatted)"
        }()
        lines.append("- Workout Date: \(workoutWeekday), \(workoutDateFormatted) (\(elapsedNote))")
        if isWorkoutToday {
            lines.append("- Activity Status: This workout took place today.")
        } else {
            let todayStatus = hasRunToday ? "Logged another run today." : "Did NOT run today."
            let yesterdayStatus = hasRunYesterday ? "Logged a run yesterday." : "Did NOT run yesterday."
            let restNote = daysSinceWorkout > 1 ? "\(daysSinceWorkout) days of rest since this session (fully rested and fresh)." : "1 day of rest since this session."
            lines.append("- Recent Activity: \(todayStatus) \(yesterdayStatus) (\(restNote))")
        }

        let durationMin = max(1, Int((runRecord.duration / 60.0).rounded()))
        let distKm = String(format: "%.1f km", runRecord.totalDistanceMeters / 1000.0)

        lines.append("")
        lines.append("WORKOUT PROFILE (\(workoutWeekday), \(workoutDateFormatted)):")
        lines.append("- Type: \(detectedType) (\(isIndoor ? "Treadmill" : "Outdoors"))")
        lines.append("- Volume: \(distKm) in \(durationMin) min (Working Pace: \(workingPaceFormatted))")
        let floorStr = runnerProfile.heightAdjustedCadenceFloor == 150 ? "150 floor" : "\(runnerProfile.heightAdjustedCadenceFloor) floor (height-adjusted)"
        lines.append("- Biomechanics: Cadence \(workingCadence) SPM (\(isSubFloorCadence ? "BELOW \(floorStr)" : "healthy turnover above floor"))")
        if let osc = verticalOscillationCM {
            lines.append("- Vertical Oscillation: \(String(format: "%.1f", osc)) cm")
        }
        if let str = strideLengthM {
            lines.append("- Stride Length: \(String(format: "%.2f", str)) m")
        }
        if let vr = verticalRatio {
            lines.append("- Vertical Ratio: \(String(format: "%.1f", vr))% (vertical bounce relative to stride length; ideal: 6–8%)")
        }
        lines.append("- Stride Archetype: \(strideArchetype)")
        if let ef = efficiencyFactor {
            var efDeltaText = ""
            if let delta = efficiencyFactorDeltaPercent {
                let sign = delta >= 0 ? "+" : ""
                efDeltaText = String(format: " (%@%.1f%% vs 30-day baseline)", sign, delta)
            }
            lines.append("- Aerobic Efficiency Factor: \(String(format: "%.2f", ef)) m/heartbeat\(efDeltaText)")
        }
        if let env = environmentModifier {
            lines.append("- Terrain & Environment Modifier: \(env)")
        }
        lines.append("- Cardiovascular Strain: Working HR \(workingHR) BPM; \(percentZone4)% in Zone 4 (Threshold)")

        // Physiological Deterministic Causal Verdicts
        lines.append("")
        lines.append("PHYSIOLOGICAL & BIOMECHANICAL VERDICTS (ROOT-CAUSE DIAGNOSIS):")
        lines.append(physiologicalVerdicts.promptDescription)

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
                lines.append("- Physiological Decoupling: Cardiac drift detected (+\(cardiacDriftMagnitudeBPM) BPM HR rise in second half despite steady/fading pace; indicates fatigue or thermal drift, not acceleration)")
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
                lines.append("- Rep Repeatability: Wide pace spread (\(Int(workRepPaceSpreadSec))s/km difference between fastest and slowest reps; indicates pacing inconsistency or late-rep fatigue)")
            }
        }

        // Baseline Context
        if let diag = longitudinalDiagnosis {
            lines.append("")
            lines.append("30-DAY BASELINE CONTRAST:")
            lines.append("- \(diag)")
        }

        // Future Training & Recovery (Included only when runner asks about upcoming runs or readiness)
        let isFutureTurn = turnContext?.turnDomain == .futureSessionPlanning || turnContext?.turnDomain == .compositeWorkoutAndPlanning
        if isFutureTurn || turnContext == nil {
            lines.append("")
            lines.append("[FUTURE TRAINING & READINESS]:")
            lines.append("- Current Readiness: \(recoveryTimeline.state.rawValue)")
            if recoveryTimeline.readyForHard {
                lines.append("- Recovery Status: FULLY RECOVERED and fresh. Cleared for any workout including speed, tempo, or intervals (last hard session was \(Int(hoursSinceWorkout))h ago; required was only \(Int(recoveryTimeline.requiredHours))h). Zero residual fatigue remains.")
            } else if let cap = recoveryTimeline.easyCap {
                lines.append("- Recovery Status: In active recovery window until \(recoveryTimeline.earliestHardPhrase). Keep next run easy (cap: \(cap.lowerBound)–\(cap.upperBound) min).")
            }
            lines.append("")
            lines.append(lockedPrescription.promptDescription)

            if let drill = runRecord.insight?.drillRecommendations?.first ?? runRecord.insight?.drillRecommendation {
                lines.append("- Pre-Run Technique Drill Option: \(drill.drillTitle) (warm-up turnover prep, not mandatory rehab)")
            }
        }

        if let tc = turnContext {
            lines.append("")
            lines.append(tc.promptHeader)
        }

        return lines.joined(separator: "\n")
    }
}
