import Foundation
import SwiftData

/// Represents a day in the weekly microcycle lookahead horizon.
struct MicrocycleDay: Identifiable, Sendable, Equatable {
    let id: String
    let dayLabel: String       // e.g. "Tomorrow", "Thu", "Fri", "Sat", "Sun"
    let sessionTitle: String   // e.g. "4x800m Threshold", "6 mi Easy Run", "Rest Day", "10x1 min Hill Repeats", "Long Run 13 mi"
    let iconName: String       // e.g. "flag.fill", "tree.fill", "bed.double.fill", "mountain.2.fill", "figure.run"
    let isRestDay: Bool
}

/// Structured multi-part prescribed session synthesized deterministically.
struct PrescribedDailySession: Sendable, Equatable {
    let targetGoal: String
    let sessionTitle: String
    let durationBand: String
    let paceBand: String
    let hrCap: String
    let cadenceFloor: Int
    let groundedRationale: String
    let readinessStateText: String
    let readinessTriggerLead: String?
    let primerDrillId: PreRunDrillId
    let primerDrillTitle: String
    let primerTargetCadence: String
    let primerWorkDescription: String
    let primerPhasesDuration: String
    let isTrimmed: Bool
    let microcycle: [MicrocycleDay]
    var mainRunDrillId: PreRunDrillId = .zone2Run
    var mainRunDurationMinutes: Int = 30
    var completedPrimerRun: RunRecordSnapshot?
}

/// Lightweight snapshot of today's completed run for thread safety and fast rendering.
struct RunRecordSnapshot: Identifiable, Sendable, Equatable {
    let id: UUID
    let date: Date
    let workoutType: String
    let durationFormatted: String
    let distanceFormatted: String
    let letterGrade: String
    let isIndoor: Bool
    var isPrimerDrill: Bool = false
    var additionalCompletedRuns: [RunRecordSnapshot] = []

    /// All workouts completed today in chronological order (e.g. Pre-Run Primer followed by Main Run).
    var allCompletedRunsToday: [RunRecordSnapshot] {
        guard !additionalCompletedRuns.isEmpty else { return [self] }
        var combined = [self]
        combined.removeAll()
        var strippedSelf = self
        strippedSelf.additionalCompletedRuns = []
        return ([strippedSelf] + additionalCompletedRuns).sorted { $0.date < $1.date }
    }
}

/// The runner's daily session state machine.
enum DailyTrainingState: Sendable, Equatable {
    case preRun(session: PrescribedDailySession)
    case completedToday(
        completedRun: RunRecordSnapshot,
        tomorrowSession: PrescribedDailySession
    )
}

/// Swift Deterministic Session Synthesis Engine.
/// Single source of truth powering the dedicated Workouts tab, Dashboard Directive card, and AI Coach state.
enum SessionSynthesisEngine {

    /// Determines whether a workout recorded today is strictly a short pre-run primer drill
    /// rather than the day's main aerobic or quality run.
    @MainActor
    static func isShortPrimerWorkout(_ run: RunRecord) -> Bool {
        guard run.duration <= 1200 else { return false } // <= 20 min
        if let drillName = run.prescribedDrillName,
           let drillId = PreRunDrillId.resolve(from: drillName),
           !drillId.isAerobicContinuous {
            return true
        }
        return run.duration <= 960 && run.totalDistanceMeters < 2500
    }

    /// Synthesizes the athlete's daily state machine deterministically.
    @MainActor
    static func evaluateDailyState(
        runRecords: [RunRecord],
        activeGoal: String = "Base Building",
        experienceLevel: String = "Intermediate",
        useMetric: Bool = true,
        now: Date = Date()
    ) -> DailyTrainingState {
        let calendar = Calendar.current
        let todayRuns = runRecords
            .filter { calendar.isDate($0.date, inSameDayAs: now) && !$0.isDeleted }
            .sorted { $0.date < $1.date }

        // 1. If the runner ONLY completed the short Pre-Run Primer today (and not the Main Run yet),
        // keep Today's Session in .preRun with completedPrimerRun attached so they can start the Main Run!
        if todayRuns.count == 1, let onlyRun = todayRuns.first, isShortPrimerWorkout(onlyRun) {
            let priorRuns = runRecords.filter { !calendar.isDate($0.date, inSameDayAs: now) && !$0.isDeleted }
            var todaySession = synthesizePreRunPrescription(
                runRecords: priorRuns,
                activeGoal: activeGoal,
                experienceLevel: experienceLevel,
                useMetric: useMetric,
                now: now
            )
            todaySession.completedPrimerRun = buildSnapshot(from: onlyRun, useMetric: useMetric)
            return .preRun(session: todaySession)
        }

        // 2. If the runner completed their Main Run (or both Primer + Main Run) today, transition to .completedToday
        if let primaryRun = todayRuns.max(by: { $0.duration < $1.duration }) ?? todayRuns.last {
            var primarySnapshot = buildSnapshot(from: primaryRun, useMetric: useMetric)
            let otherSnapshots = todayRuns
                .filter { $0.id != primaryRun.id }
                .map { buildSnapshot(from: $0, useMetric: useMetric) }
            primarySnapshot.additionalCompletedRuns = otherSnapshots

            let context = SynthesisContext(
                activeGoal: activeGoal,
                experienceLevel: experienceLevel,
                useMetric: useMetric,
                now: now
            )
            let tomorrowSession = synthesizeTomorrowPrescription(
                todayRun: primaryRun,
                runRecords: runRecords,
                context: context
            )
            return .completedToday(completedRun: primarySnapshot, tomorrowSession: tomorrowSession)
        }

        // 3. Pre-Run State: Synthesize today's primary prescription
        let todaySession = synthesizePreRunPrescription(
            runRecords: runRecords,
            activeGoal: activeGoal,
            experienceLevel: experienceLevel,
            useMetric: useMetric,
            now: now
        )
        return .preRun(session: todaySession)
    }

    // MARK: - Pre-Run Synthesis

    @MainActor
    private static func synthesizePreRunPrescription(
        runRecords: [RunRecord],
        activeGoal: String,
        experienceLevel: String,
        useMetric: Bool,
        now: Date
    ) -> PrescribedDailySession {
        let readiness = ReadinessEvaluator.assess(runRecords: runRecords, now: now)
        let baselineRuns = runRecords.filter { $0.workingAvgPace > 0 && $0.date < now }
        let basePace = baselineRuns.isEmpty ? 340.0 : (baselineRuns.prefix(10).map(\.workingAvgPace).reduce(0, +) / Double(min(10, baselineRuns.count)))
        let baseCadence = baselineRuns.isEmpty ? 155 : Int(baselineRuns.prefix(10).map(\.workingAvgCadence).reduce(0, +) / Double(min(10, baselineRuns.count)))

        let recentRun = runRecords.first(where: { !$0.isDeleted && $0.date < now })
        var hadCardiacDrift = readiness.triggers.contains(.cardiacDrift)
        var driftBPM = 18
        if let recent = recentRun {
            if recent.framboiseTags.contains("cardiacDrift") || recent.framboiseTags.contains("fatigueDrift") {
                hadCardiacDrift = true
            }
            let analysisContext = WorkoutAnalysisContext(
                runRecord: recent,
                runSignature: recent.signature,
                macroProfile: nil,
                recoveryTimeline: RecoveryTimeline(now: now, lastHard: nil, hardSessionsLast72h: 0, requiredHours: 24, state: .productive)
            )
            if analysisContext.hasCardiacDrift {
                hadCardiacDrift = true
                driftBPM = analysisContext.cardiacDriftMagnitudeBPM > 0 ? analysisContext.cardiacDriftMagnitudeBPM : 18
            }
        }

        let sessionTitle: String
        let durationBand: String
        let paceBand: String
        let hrCap: String
        let cadenceFloor: Int
        let rationale: String
        let readinessStatus: String
        let primerDrillId: PreRunDrillId
        let primerTitle: String
        let primerTarget: String
        let primerWork: String
        let primerDuration: String
        let isTrimmed: Bool

        if readiness.state == .acuteFatigue || hadCardiacDrift {
            readinessStatus = hadCardiacDrift
                ? "Active Recovery Window (Post-\(recentRun?.detectedTypeRaw ?? "Workout") Drift)"
                : "Active Recovery Window (Acute Fatigue)"

            sessionTitle = "Easy Aerobic Base Run"
            durationBand = "25 Min"
            let lowPace = basePace + 40.0
            let highPace = basePace + 65.0
            paceBand = formatPaceRange(lowSec: lowPace, highSec: highPace, useMetric: useMetric)
            hrCap = "HR: < 145 BPM"
            cadenceFloor = max(150, baseCadence - 4)

            let recentName = recentRun?.detectedTypeRaw ?? "workout"
            let recentRef = relativeWorkoutReference(for: recentRun?.date, relativeTo: now, workoutType: recentName)
            let goalPhrasing: String = {
                if activeGoal.localizedCaseInsensitiveContains("Base") {
                    return "develops your aerobic foundation at an easy, conversational pace"
                } else if activeGoal.localizedCaseInsensitiveContains("5K") {
                    return "builds your aerobic base for your 5K"
                } else {
                    return "builds your aerobic base for your \(activeGoal) progression"
                }
            }()
            rationale = hadCardiacDrift
                ? "\(recentRef) banked your speed work for the week, but drove +\(driftBPM) BPM cardiac drift. Today \(goalPhrasing) while keeping your heart rate strictly capped."
                : "Recent high-load training requires active recovery to consolidate neuromuscular adaptations while protecting your mechanics."

            primerDrillId = .cadencePyramids
            primerTitle = "Cadence Pyramids"
            primerTarget = "\(baseCadence - 1)–\(baseCadence + 5) SPM (Adapted)"
            primerWork = "2 x 30 sec work • 45 sec walk • Moderate / Zone 3"
            primerDuration = "7m 30s drill (Trimmed from 10 min)"
            isTrimmed = true
        } else if readiness.state == .deload {
            readinessStatus = "Deload Week (Consolidation)"
            sessionTitle = "Zone 2 Easy Aerobic Maintenance"
            durationBand = "30 Min"
            let lowPace = basePace + 30.0
            let highPace = basePace + 50.0
            paceBand = formatPaceRange(lowSec: lowPace, highSec: highPace, useMetric: useMetric)
            hrCap = "HR: < 150 BPM"
            cadenceFloor = baseCadence

            rationale = "Deload phase in progress. Mileage is reduced to clear accumulated fatigue while maintaining sharp leg turnover."

            primerDrillId = .strides
            primerTitle = "Strides"
            primerTarget = "\(baseCadence + 10)–\(baseCadence + 18) SPM (Adapted)"
            primerWork = "3 x 20 sec strides • 90 sec walk"
            primerDuration = "7m 30s drill (Trimmed from 15 min)"
            isTrimmed = true
        } else {
            readinessStatus = "Productive Training (Ready for Quality)"
            if activeGoal.localizedCaseInsensitiveContains("5K") {
                sessionTitle = "5K Rhythm Intervals"
                durationBand = "30 Min"
                let lowPace = basePace - 15.0
                let highPace = basePace + 5.0
                paceBand = formatPaceRange(lowSec: lowPace, highSec: highPace, useMetric: useMetric)
                hrCap = "HR: < 168 BPM"
                cadenceFloor = max(160, baseCadence)

                rationale = "Cleared for quality work. Today targets your 5K race pace turnover with crisp aerobic interval reps."

                primerDrillId = .rhythmIntervals
                primerTitle = "Rhythm Intervals"
                primerTarget = "\(baseCadence + 8)–\(baseCadence + 14) SPM"
                primerWork = "4 x 30 sec work • 45 sec jog float"
                primerDuration = "10 min drill"
                isTrimmed = false
            } else {
                sessionTitle = "Zone 2 Easy Aerobic Base"
                durationBand = "30 Min"
                let lowPace = basePace + 20.0
                let highPace = basePace + 45.0
                paceBand = formatPaceRange(lowSec: lowPace, highSec: highPace, useMetric: useMetric)
                hrCap = "HR: < 152 BPM"
                cadenceFloor = max(150, baseCadence)

                rationale = "Aerobic foundation primed. Build continuous capillary density and fat oxidation capacity toward \(activeGoal)."

                primerDrillId = .cadencePyramids
                primerTitle = "Cadence Pyramids"
                primerTarget = "\(baseCadence + 4)–\(baseCadence + 10) SPM"
                primerWork = "4 x 30 sec work • 45 sec walk"
                primerDuration = "10 min drill"
                isTrimmed = false
            }
        }

        let isRecovery = (readiness.state == .acuteFatigue || hadCardiacDrift)
        let mainRunDrillId: PreRunDrillId = {
            if isRecovery || readiness.state == .deload {
                return .zone2Run
            }
            if activeGoal.localizedCaseInsensitiveContains("5K") {
                return .rhythmIntervals
            }
            return .zone2Run
        }()
        let microcycle = generateMicrocycle(
            activeGoal: activeGoal,
            now: now,
            useMetric: useMetric,
            isRecoveryWindow: isRecovery
        )

        return PrescribedDailySession(
            targetGoal: activeGoal,
            sessionTitle: sessionTitle,
            durationBand: durationBand,
            paceBand: paceBand,
            hrCap: hrCap,
            cadenceFloor: cadenceFloor,
            groundedRationale: rationale,
            readinessStateText: readinessStatus,
            readinessTriggerLead: hadCardiacDrift
                ? "\(relativeWorkoutReference(for: recentRun?.date, relativeTo: now, workoutType: "run")) exhibited +\(driftBPM) BPM cardiac drift."
                : nil,
            primerDrillId: primerDrillId,
            primerDrillTitle: primerTitle,
            primerTargetCadence: primerTarget,
            primerWorkDescription: primerWork,
            primerPhasesDuration: primerDuration,
            isTrimmed: isTrimmed,
            microcycle: microcycle,
            mainRunDrillId: mainRunDrillId,
            mainRunDurationMinutes: 30,
            completedPrimerRun: nil
        )
    }

    public struct SynthesisContext: Sendable {
        public let activeGoal: String
        public let experienceLevel: String
        public let useMetric: Bool
        public let now: Date

        public init(activeGoal: String, experienceLevel: String, useMetric: Bool, now: Date = Date()) {
            self.activeGoal = activeGoal
            self.experienceLevel = experienceLevel
            self.useMetric = useMetric
            self.now = now
        }
    }

    // MARK: - Tomorrow's Synthesis (Post-Run State)

    @MainActor
    private static func synthesizeTomorrowPrescription(
        todayRun: RunRecord,
        runRecords: [RunRecord],
        context: SynthesisContext
    ) -> PrescribedDailySession {
        let baselineRuns = runRecords.filter { $0.workingAvgPace > 0 && $0.date <= todayRun.date }
        let rollingBasePace = baselineRuns.isEmpty ? 340.0 : (baselineRuns.prefix(10).map(\.workingAvgPace).reduce(0, +) / Double(min(10, baselineRuns.count)))
        let rollingBaseCadence = baselineRuns.isEmpty ? 155 : Int(baselineRuns.prefix(10).map(\.workingAvgCadence).reduce(0, +) / Double(min(10, baselineRuns.count)))

        let basePace = todayRun.workingAvgPace > 0 ? todayRun.workingAvgPace : rollingBasePace
        let baseCadence = todayRun.workingAvgCadence > 0 ? Int(todayRun.workingAvgCadence) : rollingBaseCadence
        let wasHardSession = todayRun.percentZone4 >= 0.20 || todayRun.detectedTypeRaw == "Intervals" || todayRun.detectedTypeRaw == "Fartlek" || todayRun.detectedTypeRaw == "Tempo Run"

        let tomorrowTitle = wasHardSession ? "Zone 1 Active Recovery Flush" : "Zone 2 Easy Aerobic Base"
        let durationBand = wasHardSession ? "25 Min" : "30 Min"

        let isTodayEasyOrRecovery = todayRun.detectedTypeRaw == "Easy Run" || todayRun.detectedTypeRaw == "Recovery Run" || todayRun.detectedTypeRaw == "Zone 2" || todayRun.detectedTypeRaw == "Steady Effort"

        let lowPace: Double
        let highPace: Double
        if wasHardSession {
            lowPace = basePace + 40.0
            highPace = basePace + 70.0
        } else if isTodayEasyOrRecovery {
            lowPace = max(240.0, basePace - 15.0)
            highPace = basePace + 15.0
        } else {
            lowPace = basePace + 20.0
            highPace = basePace + 40.0
        }

        let paceBand = formatPaceRange(lowSec: lowPace, highSec: highPace, useMetric: context.useMetric)
        let hrCap = wasHardSession ? "HR: < 135 BPM" : "HR: < 150 BPM"
        let cadenceFloor = max(150, baseCadence - 6)

        let rationale = wasHardSession
            ? "Today's \(todayRun.detectedTypeRaw) workout banked heavy neuromuscular stimuli. Tomorrow automatically shifts to an active recovery flush to clear metabolic waste and protect your legs."
            : "Building continuous consistency toward \(context.activeGoal). Tomorrow keeps aerobic volume progressing at conversational intensity."

        let primerDrillId: PreRunDrillId = wasHardSession ? .cadencePyramids : .rhythmIntervals
        let primerTitle = wasHardSession ? "Cadence Pyramids" : "Rhythm Intervals"
        let primerTarget = "\(baseCadence - 2)–\(baseCadence + 4) SPM (Adapted)"
        let primerWork = wasHardSession ? "2 x 30 sec work • 45 sec walk • Gentle" : "3 x 30 sec work • 45 sec jog"
        let primerDuration = wasHardSession ? "7m 30s drill (Trimmed from 10 min)" : "10 min drill"

        let tomorrowDate = Calendar.current.date(byAdding: .day, value: 1, to: context.now) ?? context.now
        let microcycle = generateMicrocycle(
            activeGoal: context.activeGoal,
            now: tomorrowDate,
            useMetric: context.useMetric,
            isRecoveryWindow: wasHardSession,
            startsAfterTomorrow: true
        )

        return PrescribedDailySession(
            targetGoal: context.activeGoal,
            sessionTitle: tomorrowTitle,
            durationBand: durationBand,
            paceBand: paceBand,
            hrCap: hrCap,
            cadenceFloor: cadenceFloor,
            groundedRationale: rationale,
            readinessStateText: wasHardSession ? "Scheduled Active Recovery Window" : "Aerobic Progression",
            readinessTriggerLead: wasHardSession ? "Today's \(todayRun.detectedTypeRaw) generated substantial training load." : nil,
            primerDrillId: primerDrillId,
            primerDrillTitle: primerTitle,
            primerTargetCadence: primerTarget,
            primerWorkDescription: primerWork,
            primerPhasesDuration: primerDuration,
            isTrimmed: wasHardSession,
            microcycle: microcycle,
            mainRunDrillId: wasHardSession ? .aerobicFlush : .zone2Run,
            mainRunDurationMinutes: wasHardSession ? 25 : 30,
            completedPrimerRun: nil
        )
    }

    // MARK: - Snapshot & Utilities

    @MainActor
    private static func buildSnapshot(from run: RunRecord, useMetric: Bool) -> RunRecordSnapshot {
        let durMin = Int(run.duration) / 60
        let durSec = Int(run.duration) % 60
        let durStr = String(format: "%d:%02d", durMin, durSec)

        let distMeters = run.totalDistanceMeters > 0 ? run.totalDistanceMeters : run.effectiveWorkingDistanceMeters
        let distStr: String
        if useMetric {
            distStr = String(format: "%.2f km", distMeters / 1000.0)
        } else {
            distStr = String(format: "%.2f mi", distMeters / 1609.344)
        }

        let context = WorkoutAnalysisContext(
            runRecord: run,
            runSignature: run.signature,
            macroProfile: nil,
            recoveryTimeline: RecoveryTimeline(now: Date(), lastHard: nil, hardSessionsLast72h: 0, requiredHours: 24, state: .productive)
        )
        let grade = context.overallGradeReport.grade

        let prefix = (run.isIndoor == true) ? "Indoor " : ""
        let isPrimer = isShortPrimerWorkout(run)
        let displayType: String = {
            if let drillName = run.prescribedDrillName {
                if isPrimer || drillName.localizedCaseInsensitiveCompare(run.normalizedClassification) == .orderedSame {
                    return "\(prefix)\(drillName)"
                } else {
                    return "\(prefix)\(drillName) (\(run.normalizedClassification))"
                }
            }
            return "\(prefix)\(run.normalizedClassification)"
        }()

        return RunRecordSnapshot(
            id: run.id,
            date: run.date,
            workoutType: displayType,
            durationFormatted: durStr,
            distanceFormatted: distStr,
            letterGrade: grade,
            isIndoor: run.isIndoor ?? false,
            isPrimerDrill: isPrimer,
            additionalCompletedRuns: []
        )
    }

    static func generateMicrocycle(
        activeGoal: String,
        now: Date,
        useMetric: Bool = true,
        isRecoveryWindow: Bool = false,
        startsAfterTomorrow: Bool = false
    ) -> [MicrocycleDay] {
        let calendar = Calendar.current
        var days: [MicrocycleDay] = []
        let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

        for offset in 1...5 {
            guard let targetDate = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            let weekday = calendar.component(.weekday, from: targetDate)
            let dayLabel = (offset == 1 && !startsAfterTomorrow) ? "Tomorrow" : dayNames[weekday - 1]

            let sessionTitle: String
            let iconName: String
            let isRest: Bool

            if activeGoal.localizedCaseInsensitiveContains("5K") {
                switch offset {
                case 1:
                    if isRecoveryWindow {
                        sessionTitle = useMetric ? "Zone 1 Recovery Flush (4 km)" : "Zone 1 Recovery Flush (2.5 mi)"
                        iconName = "leaf.fill"
                        isRest = false
                    } else {
                        sessionTitle = "4x800m 5K Rhythm Intervals (35m)"
                        iconName = "flag.fill"
                        isRest = false
                    }
                case 2:
                    sessionTitle = useMetric ? "5 km Easy Aerobic Run" : "3 mi Easy Aerobic Run"
                    iconName = "figure.run"
                    isRest = false
                case 3:
                    sessionTitle = "Rest Day"
                    iconName = "bed.double.fill"
                    isRest = true
                case 4:
                    sessionTitle = "8x1 min Hill Surges (30m)"
                    iconName = "mountain.2.fill"
                    isRest = false
                case 5:
                    sessionTitle = useMetric ? "Long Run 7 km" : "Long Run 4.5 mi"
                    iconName = "point.topleft.down.to.point.bottomright.curvepath.fill"
                    isRest = false
                default:
                    sessionTitle = useMetric ? "Easy Aerobic Run (5 km)" : "Easy Aerobic Run (3 mi)"
                    iconName = "figure.run"
                    isRest = false
                }
            } else if activeGoal.localizedCaseInsensitiveContains("10K") {
                switch offset {
                case 1:
                    if isRecoveryWindow {
                        sessionTitle = useMetric ? "Zone 1 Recovery Flush (5 km)" : "Zone 1 Recovery Flush (3 mi)"
                        iconName = "leaf.fill"
                        isRest = false
                    } else {
                        sessionTitle = "5x1 km Threshold Intervals (40m)"
                        iconName = "flag.fill"
                        isRest = false
                    }
                case 2:
                    sessionTitle = useMetric ? "6 km Easy Aerobic Run" : "3.5 mi Easy Aerobic Run"
                    iconName = "figure.run"
                    isRest = false
                case 3:
                    sessionTitle = "Rest Day"
                    iconName = "bed.double.fill"
                    isRest = true
                case 4:
                    sessionTitle = "Tempo Progression (35m)"
                    iconName = "bolt.fill"
                    isRest = false
                case 5:
                    sessionTitle = useMetric ? "Long Run 10 km" : "Long Run 6 mi"
                    iconName = "point.topleft.down.to.point.bottomright.curvepath.fill"
                    isRest = false
                default:
                    sessionTitle = useMetric ? "Easy Aerobic Run (6 km)" : "Easy Aerobic Run (3.5 mi)"
                    iconName = "figure.run"
                    isRest = false
                }
            } else if activeGoal.localizedCaseInsensitiveContains("Half") {
                switch offset {
                case 1:
                    if isRecoveryWindow {
                        sessionTitle = useMetric ? "Zone 1 Recovery Flush (40m)" : "Zone 1 Recovery Flush (40m)"
                        iconName = "leaf.fill"
                        isRest = false
                    } else {
                        sessionTitle = "Zone 2 Steady 45m"
                        iconName = "figure.run"
                        isRest = false
                    }
                case 2:
                    sessionTitle = "Tempo Surges (35m)"
                    iconName = "bolt.fill"
                    isRest = false
                case 3:
                    sessionTitle = "Rest Day"
                    iconName = "bed.double.fill"
                    isRest = true
                case 4:
                    sessionTitle = useMetric ? "Half Marathon Progress (8 km)" : "Half Marathon Progress (5 mi)"
                    iconName = "waveform.path.ecg"
                    isRest = false
                case 5:
                    sessionTitle = useMetric ? "Long Run 14 km" : "Long Run 8.5 mi"
                    iconName = "point.topleft.down.to.point.bottomright.curvepath.fill"
                    isRest = false
                default:
                    sessionTitle = "Easy Aerobic Run"
                    iconName = "figure.run"
                    isRest = false
                }
            } else if activeGoal.localizedCaseInsensitiveContains("Marathon") {
                switch offset {
                case 1:
                    if isRecoveryWindow {
                        sessionTitle = useMetric ? "Zone 1 Recovery Flush (40m)" : "Zone 1 Recovery Flush (40m)"
                        iconName = "leaf.fill"
                        isRest = false
                    } else {
                        sessionTitle = "Zone 2 Steady 45m"
                        iconName = "figure.run"
                        isRest = false
                    }
                case 2:
                    sessionTitle = "Tempo Surges 30m"
                    iconName = "bolt.fill"
                    isRest = false
                case 3:
                    sessionTitle = "Rest Day"
                    iconName = "bed.double.fill"
                    isRest = true
                case 4:
                    sessionTitle = useMetric ? "Marathon Pace Progress (8 km)" : "Marathon Pace Progress (5 mi)"
                    iconName = "waveform.path.ecg"
                    isRest = false
                case 5:
                    sessionTitle = useMetric ? "Long Run 16 km" : "Long Run 10 mi"
                    iconName = "point.topleft.down.to.point.bottomright.curvepath.fill"
                    isRest = false
                default:
                    sessionTitle = "Easy Aerobic Run"
                    iconName = "figure.run"
                    isRest = false
                }
            } else if activeGoal.localizedCaseInsensitiveContains("Recovery") || activeGoal.localizedCaseInsensitiveContains("Injury") {
                switch offset {
                case 1:
                    sessionTitle = "Zone 1 Recovery Flush (25m)"
                    iconName = "leaf.fill"
                    isRest = false
                case 2:
                    sessionTitle = "Rest & Mobility Day"
                    iconName = "bed.double.fill"
                    isRest = true
                case 3:
                    sessionTitle = "Walk-Jog Progression (20m)"
                    iconName = "figure.walk"
                    isRest = false
                case 4:
                    sessionTitle = "Rest Day"
                    iconName = "bed.double.fill"
                    isRest = true
                case 5:
                    sessionTitle = "Zone 1 Easy Aerobic (30m)"
                    iconName = "figure.run"
                    isRest = false
                default:
                    sessionTitle = "Recovery Flush (20m)"
                    iconName = "leaf.fill"
                    isRest = false
                }
            } else {
                // Base Building / Just for Fun (Aerobic Foundation)
                switch offset {
                case 1:
                    if isRecoveryWindow {
                        sessionTitle = useMetric ? "Zone 1 Recovery Flush (40m)" : "Zone 1 Recovery Flush (40m)"
                        iconName = "leaf.fill"
                        isRest = false
                    } else {
                        sessionTitle = "Zone 2 Steady (40m)"
                        iconName = "figure.run"
                        isRest = false
                    }
                case 2:
                    sessionTitle = "Easy Aerobic Base (30m)"
                    iconName = "figure.run"
                    isRest = false
                case 3:
                    sessionTitle = "Rest Day"
                    iconName = "bed.double.fill"
                    isRest = true
                case 4:
                    sessionTitle = "Aerobic Consistency Run (35m)"
                    iconName = "waveform.path"
                    isRest = false
                case 5:
                    sessionTitle = useMetric ? "Aerobic Long Run (8 km)" : "Aerobic Long Run (5 mi)"
                    iconName = "point.topleft.down.to.point.bottomright.curvepath.fill"
                    isRest = false
                default:
                    sessionTitle = useMetric ? "Easy Aerobic Run (5 km)" : "Easy Aerobic Run (3 mi)"
                    iconName = "figure.run"
                    isRest = false
                }
            }

            days.append(MicrocycleDay(
                id: "day-\(offset)",
                dayLabel: dayLabel,
                sessionTitle: sessionTitle,
                iconName: iconName,
                isRestDay: isRest
            ))
        }

        return days
    }

    /// Generates human coaching relative references (e.g. "Thursday's Fartlek", "Yesterday's Tempo Run", "Today's Intervals", "Recent Fartlek").
    static func relativeWorkoutReference(for date: Date?, relativeTo now: Date, workoutType: String) -> String {
        guard let date else {
            return "Your recent \(workoutType)"
        }
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) {
            return "Today's \(workoutType)"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday's \(workoutType)"
        }

        let startOfRun = calendar.startOfDay(for: date)
        let startOfNow = calendar.startOfDay(for: now)
        let daysAgo = calendar.dateComponents([.day], from: startOfRun, to: startOfNow).day ?? 0
        if daysAgo >= 2 && daysAgo <= 6 {
            let weekdayFormatter = DateFormatter()
            weekdayFormatter.locale = Locale(identifier: "en_US_POSIX")
            weekdayFormatter.dateFormat = "EEEE"
            let weekday = weekdayFormatter.string(from: date)
            return "\(weekday)'s \(workoutType)"
        }
        return "Recent \(workoutType)"
    }

    private static func formatPaceRange(lowSec: Double, highSec: Double, useMetric: Bool) -> String {
        let low = Int(lowSec.rounded())
        let high = Int(highSec.rounded())
        let p1M = low / 60
        let p1S = low % 60
        let p2M = high / 60
        let p2S = high % 60
        if useMetric {
            return String(format: "%d:%02d–%d:%02d/km", p1M, p1S, p2M, p2S)
        } else {
            let lowMi = Int((lowSec * 1.609344).rounded())
            let highMi = Int((highSec * 1.609344).rounded())
            let mi1M = lowMi / 60
            let mi1S = lowMi % 60
            let mi2M = highMi / 60
            let mi2S = highMi % 60
            return String(format: "%d:%02d–%d:%02d/mi", mi1M, mi1S, mi2M, mi2S)
        }
    }
}
