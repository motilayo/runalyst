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
            resolvedSplits = RunSplit.synthesize(from: self.phaseSegments)
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
}
