import Foundation
import SwiftData
import RunalystCore

/// Represents a day in the weekly microcycle lookahead horizon.
struct MicrocycleDay: Identifiable, Sendable, Equatable {
    let id: String
    let dayLabel: String       // e.g. "Tomorrow", "Thu", "Fri", "Sat", "Sun"
    let sessionTitle: String   // e.g. "4x800m Threshold", "6 mi Easy Run", "Rest Day", "10x1 min Hill Repeats", "Long Run 13 mi"
    let iconName: String       // e.g. "flag.fill", "tree.fill", "bed.double.fill", "mountain.2.fill", "figure.run"
    let isRestDay: Bool
}

/// Pure, date-addressable planned training session.
public struct PlannedSession: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable {
        case run
        case rest
    }
    public let kind: Kind
    public let intent: DailySessionIntent
    public let title: String
    public let minutesLow: Int
    public let minutesHigh: Int
    public let paceBand: String?
    public let hrCap: String?
    public let cadenceFloor: Int?
    public let primerTitle: String?
    public let adjustmentTriggers: [String]
    public let provisional: Bool

    public init(
        kind: Kind = .run,
        intent: DailySessionIntent? = nil,
        title: String,
        minutesLow: Int,
        minutesHigh: Int,
        paceBand: String? = nil,
        hrCap: String? = nil,
        cadenceFloor: Int? = nil,
        primerTitle: String? = nil,
        adjustmentTriggers: [String] = [],
        provisional: Bool = false
    ) {
        let resolvedIntent = intent ?? (kind == .rest ? .fullRest : .train)
        self.intent = resolvedIntent
        self.kind = resolvedIntent == .fullRest ? .rest : .run
        self.title = title
        self.minutesLow = minutesLow
        self.minutesHigh = minutesHigh
        self.paceBand = paceBand
        self.hrCap = hrCap
        self.cadenceFloor = cadenceFloor
        self.primerTitle = primerTitle
        self.adjustmentTriggers = adjustmentTriggers
        self.provisional = provisional
    }
}

/// Structured multi-part prescribed session synthesized deterministically.
struct PrescribedDailySession: Sendable, Equatable {
    let targetGoal: String
    let sessionTitle: String
    var durationBand: String
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
    var mainSessionTemplateId: PreRunDrillId = .zone2Run
    var mainRunDurationMinutes: Int = 30
    var primerDurationMinutes: Int = 10
    var completedPrimerRun: RunRecordSnapshot?
    var intent: DailySessionIntent = .train
    var isRestDay: Bool {
        intent == .fullRest
    }
    var dayLabel: String?
    var isToday: Bool = false
    var readinessState: ReadinessState = .productive

    /// Total planned duration for the entire workout (Primer + Main Run).
    var totalDurationMinutes: Int {
        if intent == .fullRest { return 0 }
        return primerDurationMinutes + mainRunDurationMinutes
    }

    /// Remaining duration left to run today (drops primer once completed).
    var remainingDurationMinutes: Int {
        if intent == .fullRest { return 0 }
        let activePrimer = (completedPrimerRun != nil) ? 0 : primerDurationMinutes
        return activePrimer + mainRunDurationMinutes
    }

    init(
        targetGoal: String,
        sessionTitle: String,
        durationBand: String,
        paceBand: String,
        hrCap: String,
        cadenceFloor: Int,
        groundedRationale: String,
        readinessStateText: String,
        readinessTriggerLead: String? = nil,
        primerDrillId: PreRunDrillId,
        primerDrillTitle: String,
        primerTargetCadence: String,
        primerWorkDescription: String,
        primerPhasesDuration: String,
        isTrimmed: Bool,
        microcycle: [MicrocycleDay],
        mainSessionTemplateId: PreRunDrillId = .zone2Run,
        mainRunDurationMinutes: Int = 30,
        primerDurationMinutes: Int? = nil,
        completedPrimerRun: RunRecordSnapshot? = nil,
        intent: DailySessionIntent? = nil,
        isRestDay: Bool? = nil,
        dayLabel: String? = nil,
        isToday: Bool = false,
        readinessState: ReadinessState = .productive
    ) {
        self.targetGoal = targetGoal
        self.sessionTitle = sessionTitle
        self.durationBand = durationBand
        self.paceBand = paceBand
        self.hrCap = hrCap
        self.cadenceFloor = cadenceFloor
        self.groundedRationale = groundedRationale
        self.readinessStateText = readinessStateText
        self.readinessTriggerLead = readinessTriggerLead
        self.primerDrillId = primerDrillId
        self.primerDrillTitle = primerDrillTitle
        self.primerTargetCadence = primerTargetCadence
        self.primerWorkDescription = primerWorkDescription
        self.primerPhasesDuration = primerPhasesDuration
        self.isTrimmed = isTrimmed
        self.microcycle = microcycle
        self.mainSessionTemplateId = mainSessionTemplateId
        self.mainRunDurationMinutes = mainRunDurationMinutes
        self.completedPrimerRun = completedPrimerRun
        if let intent {
            self.intent = intent
        } else if let isRestDay, isRestDay {
            self.intent = .fullRest
        } else {
            self.intent = .train
        }

        if let primerDurationMinutes {
            self.primerDurationMinutes = primerDurationMinutes
        } else if self.intent == .fullRest {
            self.primerDurationMinutes = 0
        } else {
            if primerPhasesDuration.contains("15") {
                self.primerDurationMinutes = 15
            } else if primerPhasesDuration.contains("12") {
                self.primerDurationMinutes = 12
            } else if primerPhasesDuration.contains("10") {
                self.primerDurationMinutes = 10
            } else if primerPhasesDuration.contains("7") || primerPhasesDuration.contains("8") {
                self.primerDurationMinutes = 8
            } else if primerPhasesDuration.contains("5") {
                self.primerDurationMinutes = 5
            } else {
                self.primerDurationMinutes = primerDrillId.defaultDuration.rawValue
            }
        }

        self.dayLabel = dayLabel
        self.isToday = isToday
        self.readinessState = readinessState
    }

    /// Resolves the canonical readiness state deterministically from explicit state or status text.
    var resolvedReadinessState: ReadinessState {
        if readinessState != .productive {
            return readinessState
        }
        if readinessStateText.localizedCaseInsensitiveContains("Deload") {
            return .deload
        }
        if isTrimmed || readinessStateText.localizedCaseInsensitiveContains("Fatigue") || readinessStateText.localizedCaseInsensitiveContains("Recovery") {
            return .acuteFatigue
        }
        return .productive
    }

    /// Backwards compatibility alias for code expecting `mainRunDrillId`.
    var mainRunDrillId: PreRunDrillId {
        get { mainSessionTemplateId }
        set { mainSessionTemplateId = newValue }
    }
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

    public var activeSession: PrescribedDailySession {
        switch self {
        case .preRun(let session):
            return session
        case .completedToday(_, let tomorrow):
            return tomorrow
        }
    }

    public var isTodayCompleted: Bool {
        switch self {
        case .preRun:
            return false
        case .completedToday:
            return true
        }
    }

    public var todaySession: PrescribedDailySession? {
        switch self {
        case .preRun(let session):
            return session
        case .completedToday:
            return nil
        }
    }

    public var tomorrowSession: PrescribedDailySession? {
        switch self {
        case .preRun:
            return nil
        case .completedToday(_, let tomorrow):
            return tomorrow
        }
    }
}

/// Swift Deterministic Session Synthesis Engine.
/// Single source of truth powering the dedicated Workouts tab, Dashboard Directive card, and AI Coach state.
enum SessionSynthesisEngine {

    /// Pure, deterministic calculation of target cadence band for a pre-run primer
    /// decoupled from goal-specific branching (enforcing 3NF parameterization).
    public static func targetCadenceBand(
        for primer: PreRunDrillId,
        state: ReadinessState,
        baseCadence: Int
    ) -> String {
        switch state {
        case .acuteFatigue:
            return "\(baseCadence - 1)–\(baseCadence + 5) SPM"
        case .deload:
            return "\(baseCadence + 10)–\(baseCadence + 18) SPM"
        case .productive:
            switch primer {
            case .cadencePyramids:
                return "\(baseCadence + 4)–\(baseCadence + 10) SPM"
            case .rhythmIntervals:
                return "\(baseCadence + 6)–\(baseCadence + 12) SPM"
            case .tempoSurges:
                return "\(baseCadence + 6)–\(baseCadence + 12) SPM"
            case .strides:
                return "\(baseCadence + 8)–\(baseCadence + 14) SPM"
            default:
                return "\(baseCadence + 4)–\(baseCadence + 10) SPM"
            }
        }
    }

    /// Determines whether a workout recorded today is strictly a short pre-run primer drill
    /// rather than the day's main aerobic or quality run.
    @MainActor
    static func isShortPrimerWorkout(_ run: RunRecord) -> Bool {
        run.isPrimerWorkout
    }

    /// Canonical predicate determining whether completed runs on a calendar day satisfy the day's training session.
    /// An athlete completes today's training if they log a primary non-primer run of >= 20 min (1200s),
    /// or achieve a cumulative workout volume of >= 30 min (1800s).
    @MainActor
    public static func isWorkoutDayComplete(runs: [RunRecord]) -> Bool {
        let active = runs.filter { !$0.isDeleted }
        guard !active.isEmpty else { return false }
        let hasMainRun = active.contains { !$0.isPrimerWorkout && $0.duration >= 1200 }
        let totalDuration = active.reduce(0.0) { $0 + $1.duration }
        return hasMainRun || totalDuration >= 1800
    }

    /// Synthesizes the athlete's daily state machine deterministically.
    @MainActor
    static func evaluateDailyState(
        runRecords: [RunRecord],
        activeGoal: String = "Base Building",
        experienceLevel: String = "Intermediate",
        useMetric: Bool = true,
        userHeightCm: Double = 175.0,
        now: Date = Date()
    ) -> DailyTrainingState {
        let calendar = Calendar.current
        let todayRuns = runRecords
            .filter { calendar.isDate($0.date, inSameDayAs: now) && !$0.isDeleted }
            .sorted { $0.date < $1.date }

        // 1. If today has no completed workouts, remain in .preRun
        guard !todayRuns.isEmpty else {
            let todaySession = synthesizePreRunPrescription(
                runRecords: runRecords,
                activeGoal: activeGoal,
                experienceLevel: experienceLevel,
                useMetric: useMetric,
                userHeightCm: userHeightCm,
                now: now
            )
            return .preRun(session: todaySession)
        }

        // 2. If the runner completed a primer or partial run that does not yet satisfy a full day's completion:
        // Keep today's session in .preRun with the primer attached so the runner can start/complete the main run!
        if !isWorkoutDayComplete(runs: todayRuns) {
            let priorRuns = runRecords.filter { !calendar.isDate($0.date, inSameDayAs: now) && !$0.isDeleted }
            var todaySession = synthesizePreRunPrescription(
                runRecords: priorRuns,
                activeGoal: activeGoal,
                experienceLevel: experienceLevel,
                useMetric: useMetric,
                userHeightCm: userHeightCm,
                now: now
            )
            if let completedPrimer = todayRuns.first(where: { isShortPrimerWorkout($0) }) ?? todayRuns.first {
                todaySession.completedPrimerRun = buildSnapshot(from: completedPrimer, useMetric: useMetric)
                todaySession.durationBand = "\(todaySession.mainRunDurationMinutes) Min"
            }
            return .preRun(session: todaySession)
        }

        // 3. Main Run satisfied: transition to .completedToday and prepare tomorrow's prescription
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
                userHeightCm: userHeightCm,
                now: now
            )
            let tomorrowSession = synthesizeTomorrowPrescription(
                todayRun: primaryRun,
                runRecords: runRecords,
                context: context
            )
            return .completedToday(completedRun: primarySnapshot, tomorrowSession: tomorrowSession)
        }

        // 4. Fallback Pre-Run State
        let todaySession = synthesizePreRunPrescription(
            runRecords: runRecords,
            activeGoal: activeGoal,
            experienceLevel: experienceLevel,
            useMetric: useMetric,
            userHeightCm: userHeightCm,
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
        userHeightCm: Double = 175.0,
        now: Date
    ) -> PrescribedDailySession {
        let readiness = ReadinessEvaluator.assess(runRecords: runRecords, now: now)
        let weightedBase = computeWeightedBaseline(from: runRecords, priorTo: now)
        let basePace = weightedBase.pace
        let baseCadence = weightedBase.cadence

        let heightScale = max(130.0, min(220.0, userHeightCm)) / 175.0
        let calibratedCadenceFloor = Int((150.0 / heightScale).rounded())

        let recentRun = runRecords.first(where: { !$0.isDeleted && $0.date < now })
        var hadCardiacDrift = readiness.triggers.contains(.cardiacDrift)
        var driftBPM = 18
        if let recent = recentRun {
            if recent.framboiseTags.contains("cardiacDrift") || recent.framboiseTags.contains("fatigueDrift") {
                hadCardiacDrift = true
            }
            let splits = recent.splits
            if splits.count >= 4 {
                let half = splits.count / 2
                let earlySplits = Array(splits[0..<half])
                let lateSplits = Array(splits[half...])
                let earlyHR = earlySplits.reduce(0.0) { $0 + $1.avgHeartRate } / Double(earlySplits.count)
                let lateHR = lateSplits.reduce(0.0) { $0 + $1.avgHeartRate } / Double(lateSplits.count)
                let hrRise = Int((lateHR - earlyHR).rounded())
                let earlyPace = earlySplits.reduce(0.0) { $0 + $1.paceSecondsPerKm } / Double(earlySplits.count)
                let latePace = lateSplits.reduce(0.0) { $0 + $1.paceSecondsPerKm } / Double(lateSplits.count)
                let paceDiff = latePace - earlyPace
                if hrRise >= 5 && paceDiff >= -2.0 {
                    hadCardiacDrift = true
                    driftBPM = max(18, hrRise)
                }
            }
        }

        // 7-day stimulus & recovery clock evaluation
        let snapshots = runRecords.filter { !$0.isDeleted && $0.date <= now }.map(ReadinessRunSnapshot.init(run:))
        let recoveryTimeline = RecoveryTimeline.build(runs: snapshots, readiness: readiness, now: now)
        let cal = Calendar.current
        let sevenDaysAgo = cal.date(byAdding: .day, value: -7, to: now) ?? now.addingTimeInterval(-7 * 24 * 3600)
        let hardSessionsLast7d = runRecords.filter { run in
            guard !run.isDeleted && run.date <= now && run.date >= sevenDaysAgo else { return false }
            let hasDrillTag = run.framboiseTags.contains("prescribedDrill") || run.prescribedDrillName != nil
            if (hasDrillTag || run.duration <= 1200) && run.percentZone4 < 0.25 {
                return false
            }
            return (run.percentZone4 >= 0.35 || run.detectedTypeRaw == "Intervals" || run.detectedTypeRaw == "Fartlek" || run.detectedTypeRaw == "Tempo Run" || run.detectedTypeRaw == "Pyramids" || run.detectedTypeRaw == "Hill Repeats" || run.detectedTypeRaw == "Progression Run" || run.detectedTypeRaw == "Progression")
        }.count
        let readyForQuality = (readiness.state == .productive) && !hadCardiacDrift && recoveryTimeline.readyForHard && (hardSessionsLast7d < 2)

        let sessionTitle: String
        let durationBand: String
        let paceBand: String
        let hrCap: String
        let cadenceFloor: Int
        let rationale: String
        let readinessStatus: String
        let primerDrillId: PreRunDrillId
        let primerTitle: String
        let primerWork: String
        var primerDuration: String
        let isTrimmed: Bool
        let mainSessionTemplateId: PreRunDrillId
        let mainRunDurationMinutes: Int

        // Biomechanical Limiter Detection on Recent Run (Closed-Loop Primer Selection)
        let recentHadExcessiveBounce: Bool = {
            guard let recent = recentRun else { return false }
            let vr = recent.verticalRatio ?? 0.0
            let osc = recent.workingAvgVerticalOscillation ?? recent.rawAvgVerticalOscillation ?? 0.0
            let subFloor = recent.workingAvgCadence > 0 && recent.workingAvgCadence < Double(calibratedCadenceFloor)
            return vr > 9.0 || osc > 10.0 || subFloor
        }()
        let recentHadCadenceFade: Bool = {
            guard let recent = recentRun else { return false }
            // Tier 1 (Tag): Persisted Tag
            if recent.framboiseTags.contains(FramboiseReadinessTag.cadenceFade) {
                return true
            }
            // Tier 2 (Linear Regression Slope): Slope < -0.15
            if let slope = recent.cadenceSlope {
                return slope < -0.15
            }
            // Tier 3 (Raw Split Telemetry Decay): >= 3 splits, mean cadence drop >= 5.0 SPM
            let splits = recent.splits
            if splits.count >= 3 {
                let splitIdx = (splits.count * 2) / 3
                let earlyCount = Double(splitIdx)
                let lateCount = Double(splits.count - splitIdx)
                guard earlyCount > 0 && lateCount > 0 else { return false }
                let early = splits[0..<splitIdx].map(\.avgCadence).reduce(0, +) / earlyCount
                let late = splits[splitIdx...].map(\.avgCadence).reduce(0, +) / lateCount
                if (early - late) >= 5.0 {
                    return true
                }
            }
            return false
        }()

        // Evaluate Streak & 48-Hour Volume Compression
        let streakSummary = StreakAndVolumeSummary.evaluate(
            runs: runRecords,
            experienceLevel: experienceLevel,
            trainingGoal: activeGoal,
            now: now
        )

        if streakSummary.shouldRecommendRestDay {
            let sessionTitle = "Rest & Structural Recovery Day"
            let durationBand = "Full Rest Day"
            let paceBand = "No Pacing Target"
            let hrCap = "HR: Rest / < 125 BPM"
            let cadenceFloor = 0
            let rationale = streakSummary.restDayReason ?? "Scheduled rest day to consolidate aerobic adaptations and protect tendons."
            let readinessStatus = "Scheduled Structural Recovery"
            let primerDrillId: PreRunDrillId = .recoveryJog
            let primerTitle = "Rest & Mobility"
            let primerTarget = "Rest"
            let primerWork = "Full rest • Mobility or gentle walking only"
            let primerDuration = "0 min"

            let remainingHours = recoveryTimeline.readyForHard ? 0.0 : max(0.0, recoveryTimeline.requiredHours - (recoveryTimeline.hoursSinceLastHard ?? 0.0))
            let microcycle = generateMicrocycle(
                activeGoal: activeGoal,
                now: now,
                useMetric: useMetric,
                isRecoveryWindow: true,
                startsAfterTomorrow: false,
                recoveryHoursRemaining: remainingHours,
                hasRecentLongRun: false,
                consecutiveRunDays: streakSummary.consecutiveRunDays,
                isTomorrowRest: true
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
                readinessTriggerLead: streakSummary.volumeRatio48h >= streakSummary.volumeCompressionThreshold
                    ? "48-Hour Volume Compression (\(Int(round(streakSummary.volumeRatio48h * 100)))% of weekly baseline)"
                    : "Consecutive Day Streak Cap Reached (\(streakSummary.consecutiveRunDays) Days)",
                primerDrillId: primerDrillId,
                primerDrillTitle: primerTitle,
                primerTargetCadence: primerTarget,
                primerWorkDescription: primerWork,
                primerPhasesDuration: primerDuration,
                isTrimmed: true,
                microcycle: microcycle,
                mainSessionTemplateId: .recoveryJog,
                mainRunDurationMinutes: 0,
                primerDurationMinutes: 0,
                completedPrimerRun: nil,
                intent: .fullRest,
                dayLabel: "Today",
                isToday: true,
                readinessState: .acuteFatigue
            )
        }

        let zones = TrainingZoneCore.calculateZones(anchorPaceSecPerKm: basePace, activeGoal: activeGoal)

        if readiness.state == .acuteFatigue || hadCardiacDrift {
            readinessStatus = hadCardiacDrift
                ? "Active Recovery Window (Post-\(recentRun?.detectedTypeRaw ?? "Workout") Drift)"
                : "Active Recovery Window (Acute Fatigue)"

            sessionTitle = "Zone 1 Active Recovery Flush"
            durationBand = "15–20 Min"
            mainRunDurationMinutes = 20
            mainSessionTemplateId = .recoveryJog
            paceBand = zones.zone1Recovery.formatted(useMetric: useMetric)
            hrCap = "HR: < 135 BPM"
            cadenceFloor = max(140, calibratedCadenceFloor - 6)

            let recentName = recentRun?.detectedTypeRaw ?? "workout"
            let recentRef = relativeWorkoutReference(for: recentRun?.date, relativeTo: now, workoutType: recentName)
            let goalPhrasing: String = {
                if activeGoal.localizedCaseInsensitiveContains("Base") {
                    return "develops your aerobic foundation with an easy active flush"
                } else if activeGoal.localizedCaseInsensitiveContains("5K") {
                    return "promotes muscular recovery without cardiovascular strain for your 5K"
                } else {
                    return "promotes muscular recovery without cardiovascular strain for your \(activeGoal) progression"
                }
            }()
            rationale = hadCardiacDrift
                ? "\(recentRef) banked your speed work for the week, but drove +\(driftBPM) BPM cardiac drift. Today \(goalPhrasing) with a short Zone 1 flush while keeping your heart rate strictly capped."
                : "Recent high-load training requires active recovery to consolidate neuromuscular adaptations while protecting your mechanics."

            primerDrillId = .cadencePyramids
            primerTitle = "Cadence Pyramids"
            primerWork = "2 x 30 sec work • 45 sec walk • Moderate / Zone 3"
            primerDuration = "7m 30s"
            isTrimmed = true
        } else if readiness.state == .deload {
            readinessStatus = "Deload Week (Consolidation)"
            sessionTitle = "Zone 2 Easy Aerobic Maintenance"
            durationBand = "30–35 Min"
            mainRunDurationMinutes = 30
            mainSessionTemplateId = .zone2Run
            paceBand = zones.zone2AerobicBase.formatted(useMetric: useMetric)
            hrCap = "HR: < 150 BPM"
            cadenceFloor = calibratedCadenceFloor

            rationale = "Deload phase in progress. Mileage is reduced to clear accumulated fatigue while maintaining sharp leg turnover."

            primerDrillId = .strides
            primerTitle = "Strides"
            primerWork = "3 x 20 sec strides • 90 sec walk"
            primerDuration = "12m 30s"
            isTrimmed = true
        } else if readyForQuality {
            // Cleared for Quality Stimulus
            readinessStatus = "Productive Training (Ready for Quality)"
            isTrimmed = false

            if activeGoal.localizedCaseInsensitiveContains("5K") {
                sessionTitle = "5K Rhythm Intervals"
                durationBand = "30–35 Min"
                mainRunDurationMinutes = 30
                mainSessionTemplateId = .rhythmIntervals
                paceBand = zones.zone5Interval.formatted(useMetric: useMetric)
                hrCap = "HR: < 168 BPM"
                cadenceFloor = max(160, calibratedCadenceFloor)
                rationale = "Cleared for quality work. Today targets your 5K race pace turnover with crisp aerobic interval reps."

                primerDrillId = recentHadExcessiveBounce ? .cadencePyramids : (recentHadCadenceFade ? .rhythmIntervals : .strides)
                primerTitle = primerDrillId == .cadencePyramids ? "Cadence Pyramids" : (primerDrillId == .rhythmIntervals ? "Rhythm Intervals" : "Strides")
                primerWork = primerDrillId == .strides ? "4 x 15 sec strides • 45 sec walk" : (primerDrillId == .cadencePyramids ? "4 x 30 sec work • 45 sec walk" : "4 x 30 sec work • 45 sec jog float")
                primerDuration = "10 min drill"
            } else if activeGoal.localizedCaseInsensitiveContains("10K") {
                sessionTitle = "10K Threshold Surges"
                durationBand = "35–40 Min"
                mainRunDurationMinutes = 35
                mainSessionTemplateId = .tempoSurges
                paceBand = zones.zone4Threshold.formatted(useMetric: useMetric)
                hrCap = "HR: < 165 BPM"
                cadenceFloor = max(155, calibratedCadenceFloor)
                rationale = "Cleared for quality work. Today targets lactate threshold resistance with controlled tempo surges."

                primerDrillId = recentHadCadenceFade ? .rhythmIntervals : (recentHadExcessiveBounce ? .cadencePyramids : .tempoSurges)
                primerTitle = primerDrillId == .tempoSurges ? "Tempo Surges" : (primerDrillId == .rhythmIntervals ? "Rhythm Intervals" : "Cadence Pyramids")
                primerWork = "4 x 30 sec work • 45 sec recovery"
                primerDuration = "10 min drill"
            } else if activeGoal.localizedCaseInsensitiveContains("Half") || activeGoal.localizedCaseInsensitiveContains("Marathon") {
                if hardSessionsLast7d == 0 {
                    sessionTitle = "Lactate Threshold Tempo Surges"
                    durationBand = "35–40 Min"
                    mainRunDurationMinutes = 35
                    mainSessionTemplateId = .tempoSurges
                    paceBand = zones.zone4Threshold.formatted(useMetric: useMetric)
                    hrCap = "HR: < 162 BPM"
                    cadenceFloor = calibratedCadenceFloor
                    rationale = "Cleared for quality work. Today introduces threshold surges to elevate metabolic efficiency toward \(activeGoal)."

                    primerDrillId = recentHadExcessiveBounce ? .cadencePyramids : (recentHadCadenceFade ? .rhythmIntervals : .strides)
                    primerTitle = primerDrillId == .cadencePyramids ? "Cadence Pyramids" : (primerDrillId == .rhythmIntervals ? "Rhythm Intervals" : "Strides")
                    primerWork = primerDrillId == .strides ? "4 x 15 sec strides • 45 sec walk" : "4 x 30 sec work • 45 sec walk"
                    primerDuration = "10 min drill"
                } else {
                    // Polarized Base Consolidation for Half/Full
                    sessionTitle = "Zone 2 Easy Aerobic Base"
                    let (band, mins) = aerobicDurationForExperience(experienceLevel)
                    durationBand = band
                    mainRunDurationMinutes = mins
                    mainSessionTemplateId = .zone2Run
                    paceBand = zones.zone2AerobicBase.formatted(useMetric: useMetric)
                    hrCap = "HR: < 152 BPM"
                    cadenceFloor = calibratedCadenceFloor
                    rationale = "Quality stimulus already banked for the week. Today maintains polarized aerobic development at conversational pace toward \(activeGoal)."

                    primerDrillId = recentHadExcessiveBounce ? .cadencePyramids : (recentHadCadenceFade ? .rhythmIntervals : .strides)
                    primerTitle = primerDrillId == .strides ? "Strides" : (primerDrillId == .rhythmIntervals ? "Rhythm Intervals" : "Cadence Pyramids")
                    primerWork = "4 x 30 sec work • 45 sec walk"
                    primerDuration = "10 min drill"
                }
            } else {
                // Base Building / Default Aerobic Progression
                sessionTitle = "Zone 2 Easy Aerobic Base"
                let (band, mins) = aerobicDurationForExperience(experienceLevel)
                durationBand = band
                mainRunDurationMinutes = mins
                mainSessionTemplateId = .zone2Run
                paceBand = zones.zone2AerobicBase.formatted(useMetric: useMetric)
                hrCap = "HR: < 152 BPM"
                cadenceFloor = calibratedCadenceFloor
                var baseRationale = "Aerobic foundation primed. Build continuous capillary density and fat oxidation capacity toward \(activeGoal)."
                if recentHadExcessiveBounce {
                    baseRationale += " Primer focuses on Cadence Pyramids to eliminate vertical oscillation bounce and protect joints."
                } else if recentHadCadenceFade {
                    baseRationale += " Primer focuses on Rhythm Intervals to build cadence fatigue resistance."
                }
                rationale = baseRationale

                primerDrillId = recentHadExcessiveBounce ? .cadencePyramids : (recentHadCadenceFade ? .rhythmIntervals : .strides)
                primerTitle = primerDrillId == .cadencePyramids ? "Cadence Pyramids" : (primerDrillId == .rhythmIntervals ? "Rhythm Intervals" : "Strides")
                primerWork = primerDrillId == .strides ? "4 x 15 sec strides • 45 sec walk" : "4 x 30 sec work • 45 sec walk"
                primerDuration = "10 min drill"
            }
        } else {
            // 80/20 Polarized Guardrail (banked hard sessions or recovery clock in effect)
            readinessStatus = "Productive Training (Aerobic Consolidation)"
            isTrimmed = false
            sessionTitle = "Zone 2 Easy Aerobic Base"
            let (band, mins) = aerobicDurationForExperience(experienceLevel)
            durationBand = band
            mainRunDurationMinutes = mins
            mainSessionTemplateId = .zone2Run
            paceBand = zones.zone2AerobicBase.formatted(useMetric: useMetric)
            hrCap = "HR: < 152 BPM"
            cadenceFloor = calibratedCadenceFloor
            var polarizedRationale = "Quality stimulus already banked for the week. Today maintains 80/20 polarized aerobic balance to consolidate fitness without overloading your nervous system."
            if recentHadExcessiveBounce {
                polarizedRationale += " Primer focuses on Cadence Pyramids to eliminate vertical oscillation bounce and protect joints."
            } else if recentHadCadenceFade {
                polarizedRationale += " Primer focuses on Rhythm Intervals to build cadence fatigue resistance."
            }
            rationale = polarizedRationale

            primerDrillId = recentHadExcessiveBounce ? .cadencePyramids : (recentHadCadenceFade ? .rhythmIntervals : .strides)
            primerTitle = primerDrillId == .cadencePyramids ? "Cadence Pyramids" : (primerDrillId == .rhythmIntervals ? "Rhythm Intervals" : "Strides")
            primerWork = primerDrillId == .strides ? "4 x 15 sec strides • 45 sec walk" : "4 x 30 sec work • 45 sec walk"
            primerDuration = "10 min drill"
        }

        let resolvedTodayReadiness: ReadinessState = {
            if readiness.state == .acuteFatigue || hadCardiacDrift {
                return .acuteFatigue
            } else if readiness.state == .deload {
                return .deload
            } else {
                return .productive
            }
        }()

        let primerTarget = targetCadenceBand(for: primerDrillId, state: resolvedTodayReadiness, baseCadence: baseCadence)

        // Deterministically compute exact primer duration directly from biomechanical phase geometry
        let dynamicPrimer = PreRunDrill(
            id: primerDrillId,
            previousCadence: calibratedCadenceFloor,
            targetCadence: primerTarget,
            readinessState: resolvedTodayReadiness,
            isIndoor: false
        )
        let totalPrimerSecs = dynamicPrimer.generatePhases().reduce(0) { $0 + $1.durationSeconds }
        let primerMins = totalPrimerSecs / 60
        let primerSecsRemainder = totalPrimerSecs % 60
        primerDuration = primerSecsRemainder == 0 ? "\(primerMins) min" : "\(primerMins)m \(primerSecsRemainder)s"

        let isRecovery = (readiness.state == .acuteFatigue || hadCardiacDrift)
        let threeDaysAgo = cal.date(byAdding: .day, value: -3, to: now) ?? now.addingTimeInterval(-3 * 86400)
        let microcycle = generateMicrocycle(
            activeGoal: activeGoal,
            now: now,
            useMetric: useMetric,
            isRecoveryWindow: isRecovery,
            recoveryHoursRemaining: recoveryTimeline.readyForHard ? 0 : (recoveryTimeline.requiredHours - (recoveryTimeline.hoursSinceLastHard ?? 0)),
            hasRecentLongRun: runRecords.contains(where: { !$0.isDeleted && $0.date <= now && $0.date >= threeDaysAgo && ($0.detectedTypeRaw == "Long Run" || $0.totalDistanceMeters >= 12000.0) }),
            consecutiveRunDays: streakSummary.consecutiveRunDays,
            isTomorrowRest: false
        )

        let todayIntent: DailySessionIntent = {
            if streakSummary.shouldRecommendRestDay {
                return .fullRest
            } else if readiness.state == .acuteFatigue || hadCardiacDrift {
                return .recoveryFlush
            } else {
                return .train
            }
        }()

        let totalSessionMins = (todayIntent == .fullRest) ? 0 : (primerMins + mainRunDurationMinutes)
        let effectiveDurationBand: String = {
            if todayIntent == .fullRest {
                return "Full Rest Day"
            }
            return "\(totalSessionMins) Min"
        }()

        return PrescribedDailySession(
            targetGoal: activeGoal,
            sessionTitle: sessionTitle,
            durationBand: effectiveDurationBand,
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
            mainSessionTemplateId: mainSessionTemplateId,
            mainRunDurationMinutes: mainRunDurationMinutes,
            primerDurationMinutes: todayIntent == .fullRest ? 0 : primerMins,
            completedPrimerRun: nil,
            intent: todayIntent,
            dayLabel: "Today",
            isToday: true,
            readinessState: resolvedTodayReadiness
        )
    }

    static func aerobicDurationForExperience(_ level: String) -> (band: String, minutes: Int) {
        if level.contains("Novice") {
            return ("25–35 Min", 30)
        } else if level.contains("Advanced") || level.contains("Competitive") || level.contains("Elite") {
            return ("45–60 Min", 50)
        } else {
            return ("35–45 Min", 40)
        }
    }

    public struct SynthesisContext: Sendable {
        public let activeGoal: String
        public let experienceLevel: String
        public let useMetric: Bool
        public let userHeightCm: Double
        public let now: Date

        public init(activeGoal: String, experienceLevel: String, useMetric: Bool, userHeightCm: Double = 175.0, now: Date = Date()) {
            self.activeGoal = activeGoal
            self.experienceLevel = experienceLevel
            self.useMetric = useMetric
            self.userHeightCm = userHeightCm
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
        let weightedBase = computeWeightedBaseline(from: runRecords, priorTo: todayRun.date)
        let rollingBasePace = weightedBase.pace
        let rollingBaseCadence = weightedBase.cadence

        let heightScale = max(130.0, min(220.0, context.userHeightCm)) / 175.0
        let calibratedCadenceFloor = Int((150.0 / heightScale).rounded())

        let basePace = todayRun.workingAvgPace > 0 ? todayRun.workingAvgPace : rollingBasePace
        let baseCadence = todayRun.workingAvgCadence > 0 ? Int(todayRun.workingAvgCadence) : rollingBaseCadence

        // Evaluate Streak & 48-Hour Volume Compression
        let streakSummary = StreakAndVolumeSummary.evaluate(
            runs: runRecords,
            experienceLevel: context.experienceLevel,
            trainingGoal: context.activeGoal,
            now: context.now
        )

        if streakSummary.shouldRecommendRestDay {
            let tomorrowTitle = "Rest & Structural Recovery Day"
            let durationBand = "Full Rest Day"
            let paceBand = "No Pacing Target"
            let hrCap = "HR: Rest / < 125 BPM"
            let cadenceFloor = 0
            let rationale = streakSummary.restDayReason ?? "Scheduled rest day to consolidate aerobic adaptations and protect tendons."
            let readinessState = "Scheduled Structural Recovery"
            let triggerLead = streakSummary.volumeRatio48h >= streakSummary.volumeCompressionThreshold
                ? "48-Hour Volume Compression (\(Int(round(streakSummary.volumeRatio48h * 100)))% of weekly baseline)"
                : "Consecutive Day Streak Cap Reached (\(streakSummary.consecutiveRunDays) Days)"

            let primerDrillId: PreRunDrillId = .recoveryJog
            let primerTitle = "Rest & Mobility"
            let primerTarget = "Rest"
            let primerWork = "Full rest • Mobility or gentle walk optional"
            let primerDuration = "0 min"

            let tomorrowDate = Calendar.current.date(byAdding: .day, value: 1, to: context.now) ?? context.now
            let tomorrowWeekday = TrainingCalendar.weekdayFormatter.string(from: tomorrowDate)
            let microcycle = generateMicrocycle(
                activeGoal: context.activeGoal,
                now: tomorrowDate,
                useMetric: context.useMetric,
                isRecoveryWindow: true,
                startsAfterTomorrow: true,
                recoveryHoursRemaining: 24.0,
                hasRecentLongRun: false,
                consecutiveRunDays: streakSummary.consecutiveRunDays,
                isTomorrowRest: true
            )

            return PrescribedDailySession(
                targetGoal: context.activeGoal,
                sessionTitle: tomorrowTitle,
                durationBand: durationBand,
                paceBand: paceBand,
                hrCap: hrCap,
                cadenceFloor: cadenceFloor,
                groundedRationale: rationale,
                readinessStateText: readinessState,
                readinessTriggerLead: triggerLead,
                primerDrillId: primerDrillId,
                primerDrillTitle: primerTitle,
                primerTargetCadence: primerTarget,
                primerWorkDescription: primerWork,
                primerPhasesDuration: primerDuration,
                isTrimmed: true,
                microcycle: microcycle,
                mainSessionTemplateId: .recoveryJog,
                mainRunDurationMinutes: 0,
                primerDurationMinutes: 0,
                completedPrimerRun: nil,
                intent: .fullRest,
                dayLabel: tomorrowWeekday,
                isToday: false,
                readinessState: .acuteFatigue
            )
        }

        let wasHardSession = todayRun.percentZone4 >= 0.20 || todayRun.detectedTypeRaw == "Intervals" || todayRun.detectedTypeRaw == "Fartlek" || todayRun.detectedTypeRaw == "Tempo Run"

        let tomorrowTitle = wasHardSession ? "Zone 1 Active Recovery Flush" : "Zone 2 Easy Aerobic Base"
        let (aerobicBand, aerobicMins) = aerobicDurationForExperience(context.experienceLevel)
        let durationBand = wasHardSession ? "15–20 Min" : aerobicBand
        let mainRunDurationMinutes = wasHardSession ? 20 : aerobicMins

        let zones = TrainingZoneCore.calculateZones(anchorPaceSecPerKm: basePace, activeGoal: context.activeGoal)
        let paceBand = wasHardSession
            ? zones.zone1Recovery.formatted(useMetric: context.useMetric)
            : zones.zone2AerobicBase.formatted(useMetric: context.useMetric)
        let hrCap = wasHardSession ? "HR: < 135 BPM" : "HR: < 150 BPM"
        let cadenceFloor = max(140, calibratedCadenceFloor - 6)
        let tomorrowIntent: DailySessionIntent = wasHardSession ? .recoveryFlush : .train

        let rationale = wasHardSession
            ? "Today's \(todayRun.detectedTypeRaw) workout banked heavy neuromuscular stimuli. Tomorrow automatically shifts to an active recovery flush to clear metabolic waste and protect your legs."
            : "Building continuous consistency toward \(context.activeGoal). Tomorrow keeps aerobic volume progressing at conversational intensity."

        let todayHadExcessiveBounce: Bool = {
            let vr = todayRun.verticalRatio ?? 0.0
            let osc = todayRun.workingAvgVerticalOscillation ?? todayRun.rawAvgVerticalOscillation ?? 0.0
            let subFloor = todayRun.workingAvgCadence > 0 && todayRun.workingAvgCadence < Double(calibratedCadenceFloor)
            return vr > 9.0 || osc > 10.0 || subFloor
        }()
        let todayHadCadenceFade: Bool = {
            if todayRun.framboiseTags.contains(FramboiseReadinessTag.cadenceFade) {
                return true
            }
            if let slope = todayRun.cadenceSlope {
                return slope < -0.15
            }
            let splits = todayRun.splits
            if splits.count >= 3 {
                let splitIdx = (splits.count * 2) / 3
                let earlyCount = Double(splitIdx)
                let lateCount = Double(splits.count - splitIdx)
                guard earlyCount > 0 && lateCount > 0 else { return false }
                let early = splits[0..<splitIdx].map(\.avgCadence).reduce(0, +) / earlyCount
                let late = splits[splitIdx...].map(\.avgCadence).reduce(0, +) / lateCount
                if (early - late) >= 5.0 {
                    return true
                }
            }
            return false
        }()

        let primerDrillId: PreRunDrillId
        let primerTitle: String
        let primerTarget: String
        let primerWork: String

        if wasHardSession {
            primerDrillId = .cadencePyramids
            primerTitle = "Cadence Pyramids"
            primerTarget = "\(baseCadence - 2)–\(baseCadence + 4) SPM"
            primerWork = "2 x 30 sec work • 45 sec walk • Gentle"
        } else if todayHadExcessiveBounce {
            primerDrillId = .cadencePyramids
            primerTitle = "Cadence Pyramids"
            primerTarget = "\(baseCadence - 2)–\(baseCadence + 4) SPM"
            primerWork = "4 x 30 sec work • 45 sec walk"
        } else if todayHadCadenceFade {
            primerDrillId = .rhythmIntervals
            primerTitle = "Rhythm Intervals"
            primerTarget = "\(baseCadence + 4)–\(baseCadence + 8) SPM"
            primerWork = "4 x 30 sec work • 45 sec jog"
        } else {
            primerDrillId = .strides
            primerTitle = "Strides"
            primerTarget = "\(baseCadence + 4)–\(baseCadence + 10) SPM"
            primerWork = "4 x 15 sec strides • 45 sec walk"
        }

        let tomorrowPrimerDrill = PreRunDrill(
            id: primerDrillId,
            previousCadence: calibratedCadenceFloor,
            targetCadence: primerTarget,
            readinessState: wasHardSession ? .acuteFatigue : .productive,
            isIndoor: false
        )
        let totalTomorrowPrimerSecs = tomorrowPrimerDrill.generatePhases().reduce(0) { $0 + $1.durationSeconds }
        let tomorrowPrimerMins = totalTomorrowPrimerSecs / 60
        let tomorrowPrimerSecs = totalTomorrowPrimerSecs % 60
        let primerDuration = tomorrowPrimerSecs == 0 ? "\(tomorrowPrimerMins) min" : "\(tomorrowPrimerMins)m \(tomorrowPrimerSecs)s"

        let tomorrowDate = Calendar.current.date(byAdding: .day, value: 1, to: context.now) ?? context.now
        let tomorrowWeekday = TrainingCalendar.weekdayFormatter.string(from: tomorrowDate)
        let microcycle = generateMicrocycle(
            activeGoal: context.activeGoal,
            now: tomorrowDate,
            useMetric: context.useMetric,
            isRecoveryWindow: wasHardSession,
            startsAfterTomorrow: true,
            recoveryHoursRemaining: wasHardSession ? 48.0 : 0.0,
            hasRecentLongRun: false,
            consecutiveRunDays: streakSummary.consecutiveRunDays,
            isTomorrowRest: false
        )

        let totalTomorrowMins = (tomorrowIntent == .fullRest) ? 0 : (tomorrowPrimerMins + mainRunDurationMinutes)
        let effectiveTomorrowDurationBand: String = {
            if tomorrowIntent == .fullRest {
                return "Full Rest Day"
            }
            return "\(totalTomorrowMins) Min"
        }()

        return PrescribedDailySession(
            targetGoal: context.activeGoal,
            sessionTitle: tomorrowTitle,
            durationBand: effectiveTomorrowDurationBand,
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
            mainSessionTemplateId: wasHardSession ? .recoveryJog : .zone2Run,
            mainRunDurationMinutes: mainRunDurationMinutes,
            primerDurationMinutes: tomorrowIntent == .fullRest ? 0 : tomorrowPrimerMins,
            completedPrimerRun: nil,
            intent: tomorrowIntent,
            dayLabel: tomorrowWeekday,
            isToday: false,
            readinessState: wasHardSession ? .acuteFatigue : .productive
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

        let gradeInput = RunGradeInput(
            type: run.detectedTypeRaw,
            isHard: run.detectedTypeRaw.localizedCaseInsensitiveContains("Interval") || run.detectedTypeRaw.localizedCaseInsensitiveContains("Tempo"),
            percentZone4: run.percentZone4,
            cadence: Int(run.workingAvgCadence.rounded()),
            workPaces: [],
            paceDeltaVsBaseline: nil,
            hrDeltaVsBaseline: nil,
            cadenceFade: run.framboiseTags.contains(FramboiseReadinessTag.cadenceFade),
            cardiacDrift: run.framboiseTags.contains(FramboiseReadinessTag.cardiacDrift)
        )
        let grade = RunGrade.evaluate(gradeInput).grade

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

    // MARK: - Date-Addressable Planner (Pure OOP Timeline)

    /// Deterministically computes the planned session for any target date.
    /// Invariant: Target date session is pure and stable regardless of query window.
    @MainActor
    public static func plannedSession(
        on targetDate: Date,
        runRecords: [RunRecord],
        activeGoal: String,
        profile: RunnerProfile,
        useMetric: Bool,
        now: Date = Date(),
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> PlannedSession {
        let dailyState = DailyTrainingStateStore.shared.resolveState(
            runRecords: runRecords,
            activeGoal: activeGoal,
            experienceLevel: profile.experienceLevel,
            useMetric: useMetric,
            userHeightCm: profile.userHeightCm,
            now: now
        )
        let targetDay = calendar.startOfDay(for: targetDate)
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today

        // 0. Target day is Today: Return today's exact synthesized prescription
        if targetDay == today {
            switch dailyState {
            case .preRun(let session):
                return PlannedSession(
                    kind: session.isRestDay ? .rest : .run,
                    intent: session.intent,
                    title: session.sessionTitle,
                    minutesLow: session.isRestDay ? 0 : session.totalDurationMinutes,
                    minutesHigh: session.isRestDay ? 0 : session.totalDurationMinutes,
                    paceBand: session.isRestDay ? nil : session.paceBand,
                    hrCap: session.hrCap,
                    cadenceFloor: session.cadenceFloor > 0 ? session.cadenceFloor : nil,
                    primerTitle: session.isRestDay ? nil : session.primerDrillTitle,
                    adjustmentTriggers: session.isTrimmed ? ["readiness_adjusted"] : [],
                    provisional: false
                )
            case .completedToday(let completedRun, _):
                let todayRuns = runRecords.filter { calendar.isDateInToday($0.date) && !$0.isDeleted }
                let durMins = max(1, Int((todayRuns.reduce(0.0) { $0 + $1.duration } / 60.0).rounded()))
                return PlannedSession(
                    kind: .run,
                    title: completedRun.workoutType,
                    minutesLow: durMins,
                    minutesHigh: durMins,
                    paceBand: nil,
                    hrCap: "< 152 BPM",
                    cadenceFloor: profile.heightAdjustedCadenceFloor,
                    primerTitle: nil,
                    adjustmentTriggers: ["completed_today"],
                    provisional: false
                )
            }
        }

        // 1. Target day is Tomorrow: Return tomorrow's exact prescription (matching Workouts tab)
        if targetDay == tomorrow {
            let tomorrowSession: PrescribedDailySession
            switch dailyState {
            case .completedToday(_, let tomorrow):
                tomorrowSession = tomorrow
            case .preRun(let todaySession):
                let microDay = todaySession.microcycle.first(where: { $0.id == "day-1" })
                let isRest = microDay?.isRestDay ?? false
                let title = microDay?.sessionTitle ?? "Zone 2 Easy Aerobic Base"
                var cal = calendar
                cal.firstWeekday = 1
                let weekday = cal.component(.weekday, from: tomorrow)
                let template = templateSessionForWeekday(weekday: weekday, activeGoal: activeGoal, profile: profile, useMetric: useMetric)
                let (minsLow, minsHigh): (Int, Int) = {
                    if isRest { return (0, 0) }
                    if title.contains("Recovery Flush") { return (35, 40) }
                    return (template.minutesLow, template.minutesHigh)
                }()
                let tomorrowIntent: DailySessionIntent = {
                    if isRest { return .fullRest }
                    if title.contains("Recovery Flush") { return .recoveryFlush }
                    return .train
                }()
                let resolvedPaceBand: String? = {
                    if isRest { return nil }
                    let weightedBase = computeWeightedBaseline(from: runRecords, priorTo: now)
                    let zones = TrainingZoneCore.calculateZones(anchorPaceSecPerKm: weightedBase.pace, activeGoal: activeGoal)
                    if title.contains("Recovery Flush") {
                        return zones.zone1Recovery.formatted(useMetric: useMetric)
                    }
                    return template.paceBand ?? zones.zone2AerobicBase.formatted(useMetric: useMetric)
                }()
                return PlannedSession(
                    kind: isRest ? .rest : .run,
                    intent: tomorrowIntent,
                    title: title,
                    minutesLow: minsLow,
                    minutesHigh: minsHigh,
                    paceBand: resolvedPaceBand,
                    hrCap: isRest ? "HR: Rest / < 125 BPM" : (tomorrowIntent == .recoveryFlush ? "HR: < 135 BPM" : (template.hrCap ?? "HR: < 150 BPM")),
                    cadenceFloor: isRest ? nil : (template.cadenceFloor ?? profile.heightAdjustedCadenceFloor),
                    primerTitle: isRest ? nil : template.primerTitle,
                    adjustmentTriggers: todaySession.isTrimmed ? ["recovery_window"] : [],
                    provisional: true
                )
            }

            var triggers: [String] = []
            if tomorrowSession.isRestDay {
                triggers.append("volume_compression")
            }
            if tomorrowSession.isTrimmed {
                triggers.append("recovery_window")
            }

            return PlannedSession(
                kind: tomorrowSession.isRestDay ? .rest : .run,
                intent: tomorrowSession.intent,
                title: tomorrowSession.sessionTitle,
                minutesLow: tomorrowSession.isRestDay ? 0 : tomorrowSession.totalDurationMinutes,
                minutesHigh: tomorrowSession.isRestDay ? 0 : tomorrowSession.totalDurationMinutes,
                paceBand: tomorrowSession.isRestDay ? nil : tomorrowSession.paceBand,
                hrCap: tomorrowSession.hrCap,
                cadenceFloor: tomorrowSession.cadenceFloor > 0 ? tomorrowSession.cadenceFloor : nil,
                primerTitle: tomorrowSession.isRestDay ? nil : tomorrowSession.primerDrillTitle,
                adjustmentTriggers: triggers,
                provisional: false
            )
        }

        // 2. Target day within active microcycle horizon (+2...+5 days)
        let dayOffset = calendar.dateComponents([.day], from: today, to: targetDay).day ?? 0
        if dayOffset >= 2 && dayOffset <= 5 {
            let microcycle = dailyState.activeSession.microcycle
            if let matchedDay = microcycle.first(where: { $0.id == "day-\(dayOffset)" }) {
                var cal = calendar
                cal.firstWeekday = 1
                let weekday = cal.component(.weekday, from: targetDay)
                let template = templateSessionForWeekday(weekday: weekday, activeGoal: activeGoal, profile: profile, useMetric: useMetric)
                let (minsLow, minsHigh): (Int, Int) = {
                    if matchedDay.isRestDay { return (0, 0) }
                    if matchedDay.sessionTitle.contains("Recovery Flush") { return (35, 40) }
                    return (template.minutesLow, template.minutesHigh)
                }()
                let dayIntent: DailySessionIntent = {
                    if matchedDay.isRestDay { return .fullRest }
                    if matchedDay.sessionTitle.contains("Recovery Flush") { return .recoveryFlush }
                    return .train
                }()
                let resolvedPaceBand: String? = {
                    if matchedDay.isRestDay { return nil }
                    let weightedBase = computeWeightedBaseline(from: runRecords, priorTo: now)
                    let zones = TrainingZoneCore.calculateZones(anchorPaceSecPerKm: weightedBase.pace, activeGoal: activeGoal)
                    if matchedDay.sessionTitle.contains("Recovery Flush") {
                        return zones.zone1Recovery.formatted(useMetric: useMetric)
                    }
                    return template.paceBand ?? zones.zone2AerobicBase.formatted(useMetric: useMetric)
                }()
                return PlannedSession(
                    kind: matchedDay.isRestDay ? .rest : .run,
                    intent: dayIntent,
                    title: matchedDay.sessionTitle,
                    minutesLow: minsLow,
                    minutesHigh: minsHigh,
                    paceBand: resolvedPaceBand,
                    hrCap: matchedDay.isRestDay ? "HR: Rest / < 125 BPM" : (dayIntent == .recoveryFlush ? "HR: < 135 BPM" : (template.hrCap ?? "HR: < 150 BPM")),
                    cadenceFloor: matchedDay.isRestDay ? nil : (template.cadenceFloor ?? profile.heightAdjustedCadenceFloor),
                    primerTitle: matchedDay.isRestDay ? nil : template.primerTitle,
                    adjustmentTriggers: [],
                    provisional: true
                )
            }
        }

        // 3. Past days or beyond the microcycle: pure weekly template
        var cal = calendar
        cal.firstWeekday = 1
        let weekday = cal.component(.weekday, from: targetDay)
        return templateSessionForWeekday(weekday: weekday, activeGoal: activeGoal, profile: profile, useMetric: useMetric)
    }

    /// Pure weekday template for goals (Sun = 1, Mon = 2, Tue = 3, Wed = 4, Thu = 5, Fri = 6, Sat = 7).
    public static func templateSessionForWeekday(
        weekday: Int,
        activeGoal: String,
        profile: RunnerProfile,
        useMetric: Bool
    ) -> PlannedSession {
        let (aerobicBand, defaultMins) = aerobicDurationForExperience(profile.experienceLevel)
        _ = aerobicBand

        if activeGoal.localizedCaseInsensitiveContains("5K") {
            switch weekday {
            case 1: // Sun
                return PlannedSession(kind: .run, title: useMetric ? "Aerobic Consistency Run (5 km)" : "Aerobic Consistency Run (3 mi)", minutesLow: 25, minutesHigh: 35, provisional: true)
            case 2: // Mon
                return PlannedSession(kind: .run, title: "4x800m 5K Rhythm Intervals (35m)", minutesLow: 30, minutesHigh: 35, primerTitle: "Rhythm Intervals", provisional: true)
            case 3: // Tue
                return PlannedSession(kind: .run, title: useMetric ? "5 km Easy Aerobic Run" : "3 mi Easy Aerobic Run", minutesLow: 25, minutesHigh: 30, provisional: true)
            case 4: // Wed
                return PlannedSession(kind: .rest, title: "Rest Day", minutesLow: 0, minutesHigh: 0, provisional: true)
            case 5: // Thu
                return PlannedSession(kind: .run, title: "8x1 min Hill Surges (30m)", minutesLow: 25, minutesHigh: 30, primerTitle: "Cadence Pyramids", provisional: true)
            case 6: // Fri
                return PlannedSession(kind: .run, title: useMetric ? "5 km Easy Aerobic Run" : "3 mi Easy Aerobic Run", minutesLow: 25, minutesHigh: 30, provisional: true)
            case 7: // Sat
                return PlannedSession(kind: .run, title: useMetric ? "Long Run 7 km" : "Long Run 4.5 mi", minutesLow: 40, minutesHigh: 50, provisional: true)
            default:
                return PlannedSession(kind: .run, title: "Easy Aerobic Run", minutesLow: 30, minutesHigh: 35, provisional: true)
            }
        } else if activeGoal.localizedCaseInsensitiveContains("10K") {
            switch weekday {
            case 1: // Sun
                return PlannedSession(kind: .run, title: useMetric ? "Aerobic Consistency Run (6 km)" : "Aerobic Consistency Run (3.5 mi)", minutesLow: 30, minutesHigh: 40, provisional: true)
            case 2: // Mon
                return PlannedSession(kind: .run, title: "5x1 km Threshold Intervals (40m)", minutesLow: 35, minutesHigh: 40, primerTitle: "Rhythm Intervals", provisional: true)
            case 3: // Tue
                return PlannedSession(kind: .run, title: useMetric ? "6 km Easy Aerobic Run" : "3.5 mi Easy Aerobic Run", minutesLow: 30, minutesHigh: 35, provisional: true)
            case 4: // Wed
                return PlannedSession(kind: .rest, title: "Rest Day", minutesLow: 0, minutesHigh: 0, provisional: true)
            case 5: // Thu
                return PlannedSession(kind: .run, title: "Tempo Progression (35m)", minutesLow: 30, minutesHigh: 35, primerTitle: "Tempo Surges", provisional: true)
            case 6: // Fri
                return PlannedSession(kind: .run, title: useMetric ? "6 km Easy Aerobic Run" : "3.5 mi Easy Aerobic Run", minutesLow: 30, minutesHigh: 35, provisional: true)
            case 7: // Sat
                return PlannedSession(kind: .run, title: useMetric ? "Long Run 10 km" : "Long Run 6 mi", minutesLow: 50, minutesHigh: 65, provisional: true)
            default:
                return PlannedSession(kind: .run, title: "Easy Aerobic Run", minutesLow: 30, minutesHigh: 35, provisional: true)
            }
        } else if activeGoal.localizedCaseInsensitiveContains("Half") || activeGoal.localizedCaseInsensitiveContains("Marathon") {
            switch weekday {
            case 1: // Sun
                return PlannedSession(kind: .run, title: useMetric ? "Aerobic Consistency Run (8 km)" : "Aerobic Consistency Run (5 mi)", minutesLow: 40, minutesHigh: 50, provisional: true)
            case 2: // Mon
                return PlannedSession(kind: .run, title: "Zone 2 Steady (45m)", minutesLow: 40, minutesHigh: 45, primerTitle: "Cadence Pyramids", provisional: true)
            case 3: // Tue
                return PlannedSession(kind: .run, title: useMetric ? "6 km Easy Aerobic Run" : "3.5 mi Easy Aerobic Run", minutesLow: 30, minutesHigh: 35, provisional: true)
            case 4: // Wed
                return PlannedSession(kind: .rest, title: "Rest Day", minutesLow: 0, minutesHigh: 0, provisional: true)
            case 5: // Thu
                return PlannedSession(kind: .run, title: "Tempo Surges (35m)", minutesLow: 30, minutesHigh: 35, primerTitle: "Tempo Surges", provisional: true)
            case 6: // Fri
                return PlannedSession(kind: .run, title: useMetric ? "Zone 1 Recovery Flush (40m)" : "Zone 1 Recovery Flush (40m)", minutesLow: 35, minutesHigh: 40, provisional: true)
            case 7: // Sat
                return PlannedSession(kind: .run, title: useMetric ? "Long Run 14 km" : "Long Run 8.5 mi", minutesLow: 70, minutesHigh: 90, provisional: true)
            default:
                return PlannedSession(kind: .run, title: "Easy Aerobic Run", minutesLow: 35, minutesHigh: 45, provisional: true)
            }
        } else if activeGoal.localizedCaseInsensitiveContains("Recovery") || activeGoal.localizedCaseInsensitiveContains("Injury") {
            switch weekday {
            case 1: // Sun
                return PlannedSession(kind: .run, title: "Zone 1 Easy Aerobic (30m)", minutesLow: 25, minutesHigh: 30, provisional: true)
            case 2: // Mon
                return PlannedSession(kind: .rest, title: "Rest & Mobility Day", minutesLow: 0, minutesHigh: 0, provisional: true)
            case 3: // Tue
                return PlannedSession(kind: .run, title: "Zone 1 Recovery Flush (25m)", minutesLow: 20, minutesHigh: 25, provisional: true)
            case 4: // Wed
                return PlannedSession(kind: .rest, title: "Rest Day", minutesLow: 0, minutesHigh: 0, provisional: true)
            case 5: // Thu
                return PlannedSession(kind: .run, title: "Walk-Jog Progression (20m)", minutesLow: 15, minutesHigh: 20, provisional: true)
            case 6: // Fri
                return PlannedSession(kind: .rest, title: "Rest Day", minutesLow: 0, minutesHigh: 0, provisional: true)
            case 7: // Sat
                return PlannedSession(kind: .run, title: "Zone 1 Easy Aerobic (30m)", minutesLow: 25, minutesHigh: 30, provisional: true)
            default:
                return PlannedSession(kind: .run, title: "Recovery Flush (20m)", minutesLow: 15, minutesHigh: 20, provisional: true)
            }
        } else {
            // Base Building / Just for Fun (Aerobic Foundation)
            switch weekday {
            case 1: // Sun
                return PlannedSession(kind: .run, title: "Aerobic Consistency Run (35m)", minutesLow: 30, minutesHigh: 35, paceBand: "Zone 2 Base", primerTitle: "Cadence Pyramids", provisional: true)
            case 2: // Mon
                return PlannedSession(kind: .run, title: useMetric ? "Aerobic Long Run (8 km)" : "Aerobic Long Run (5 mi)", minutesLow: 45, minutesHigh: 55, paceBand: "Zone 2 Base", primerTitle: "Strides", provisional: true)
            case 3: // Tue
                return PlannedSession(kind: .run, title: "Zone 2 Easy Aerobic Base", minutesLow: max(25, defaultMins - 5), minutesHigh: defaultMins, paceBand: "Zone 2 Base", primerTitle: "Cadence Pyramids", provisional: true)
            case 4: // Wed
                return PlannedSession(kind: .rest, title: "Rest Day", minutesLow: 0, minutesHigh: 0, provisional: true)
            case 5: // Thu
                return PlannedSession(kind: .run, title: "Zone 1 Recovery Flush (40m)", minutesLow: 35, minutesHigh: 40, paceBand: "Zone 1 Flush", primerTitle: "Optional 10m Walk", provisional: true)
            case 6: // Fri
                return PlannedSession(kind: .run, title: "Aerobic Consistency Run (30m)", minutesLow: 25, minutesHigh: 30, paceBand: "Zone 2 Base", primerTitle: "Rhythm Intervals", provisional: true)
            case 7: // Sat
                return PlannedSession(kind: .rest, title: "Rest Day", minutesLow: 0, minutesHigh: 0, provisional: true)
            default:
                return PlannedSession(kind: .run, title: "Zone 2 Steady (40m)", minutesLow: 35, minutesHigh: 40, paceBand: "Zone 2 Base", provisional: true)
            }
        }
    }

    @MainActor
    static func generateMicrocycle(
        activeGoal: String,
        now: Date,
        runRecords: [RunRecord] = [],
        profile: RunnerProfile? = nil,
        useMetric: Bool = true,
        isRecoveryWindow: Bool = false,
        startsAfterTomorrow: Bool = false,
        recoveryHoursRemaining: Double = 0.0,
        hasRecentLongRun: Bool = false,
        consecutiveRunDays: Int = 0,
        isTomorrowRest: Bool = false
    ) -> [MicrocycleDay] {
        let calendar = Calendar.current
        var days: [MicrocycleDay] = []
        let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let effectiveProfile = profile ?? RunnerProfile.compute(from: runRecords, now: now)

        for offset in 1...5 {
            guard let targetDate = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            let weekday = calendar.component(.weekday, from: targetDate)
            let dayLabel = (offset == 1 && !startsAfterTomorrow) ? "Tomorrow" : dayNames[weekday - 1]

            let template = templateSessionForWeekday(
                weekday: weekday,
                activeGoal: activeGoal,
                profile: effectiveProfile,
                useMetric: useMetric
            )

            let isTomorrowShiftedToRecovery = (offset == 1 && !startsAfterTomorrow && isRecoveryWindow)
            let isRest = template.kind == .rest || (offset == 1 && isTomorrowRest && !startsAfterTomorrow)

            let sessionTitle: String = {
                if isRest {
                    return "Rest Day"
                }
                if isTomorrowShiftedToRecovery {
                    return "Zone 1 Recovery Flush (40m)"
                }
                // If 5th day and no long run has been scheduled in the 5-day horizon for race goals, include the calibrated long run
                if offset == 5 && !hasRecentLongRun && !days.contains(where: { $0.sessionTitle.lowercased().contains("long") }) {
                    if activeGoal.localizedCaseInsensitiveContains("5K") {
                        return useMetric ? "Long Run 7 km" : "Long Run 4.5 mi"
                    } else if activeGoal.localizedCaseInsensitiveContains("10K") {
                        return useMetric ? "Long Run 10 km" : "Long Run 6 mi"
                    } else if activeGoal.localizedCaseInsensitiveContains("Half") || activeGoal.localizedCaseInsensitiveContains("Marathon") {
                        return useMetric ? "Long Run 14 km" : "Long Run 8.5 mi"
                    }
                }
                return template.title
            }()

            let iconName: String = {
                if isRest {
                    return "bed.double.fill"
                }
                let lower = sessionTitle.lowercased()
                if lower.contains("interval") || lower.contains("surge") || lower.contains("stride") {
                    return "flag.fill"
                } else if lower.contains("tempo") || lower.contains("progress") {
                    return "bolt.fill"
                } else if lower.contains("recovery") || lower.contains("flush") {
                    return "leaf.fill"
                } else if lower.contains("long") {
                    return "point.topleft.down.to.point.bottomright.curvepath.fill"
                } else {
                    return "figure.run"
                }
            }()

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

    /// Canonical duration- and classification-weighted 30-day baseline statistics.
    public struct WeightedBaselineStats: Sendable, Equatable {
        public let avgPace: Double
        public let avgCadence: Double
        public let avgHR: Double
        public let avgOscillation: Double?
        public let avgStrideLength: Double?
        public let avgVerticalRatio: Double?

        public init(
            avgPace: Double,
            avgCadence: Double,
            avgHR: Double,
            avgOscillation: Double? = nil,
            avgStrideLength: Double? = nil,
            avgVerticalRatio: Double? = nil
        ) {
            self.avgPace = avgPace
            self.avgCadence = avgCadence
            self.avgHR = avgHR
            self.avgOscillation = avgOscillation
            self.avgStrideLength = avgStrideLength
            self.avgVerticalRatio = avgVerticalRatio
        }
    }

    public enum TrajectoryVerdict: String, Sendable, Equatable {
        case easeUp
        case onTrack
        case stepItUp
    }

    public struct TrajectoryAssessment: Sendable, Equatable {
        public let verdict: TrajectoryVerdict
        public let efDelta: Double
        public let hrDelta: Double
        public let oscDelta: Double
        public let vrDelta: Double
        public let avgRecentEF: Double
        public let avgRecentOsc: Double
        public let avgRecentVR: Double

        public init(
            verdict: TrajectoryVerdict,
            efDelta: Double,
            hrDelta: Double,
            oscDelta: Double,
            vrDelta: Double,
            avgRecentEF: Double,
            avgRecentOsc: Double,
            avgRecentVR: Double
        ) {
            self.verdict = verdict
            self.efDelta = efDelta
            self.hrDelta = hrDelta
            self.oscDelta = oscDelta
            self.vrDelta = vrDelta
            self.avgRecentEF = avgRecentEF
            self.avgRecentOsc = avgRecentOsc
            self.avgRecentVR = avgRecentVR
        }
    }

    /// Evaluates physiological adaptation trajectory over 30 days comparing the last 15 days against the prior 15 days.
    public static func evaluate30DayTrajectory(
        from runs: [RunRecord],
        now: Date = Date()
    ) -> TrajectoryAssessment {
        let cal = Calendar.current
        let thirtyDaysAgo = cal.date(byAdding: .day, value: -30, to: now) ?? now.addingTimeInterval(-30 * 24 * 3600)
        let validRuns = runs.filter {
            $0.date >= thirtyDaysAgo &&
            $0.date <= now &&
            $0.workingAvgPace > 0 &&
            $0.workingAvgHeartRate > 0 &&
            !$0.isDeleted
        }

        let midDate = cal.date(byAdding: .day, value: -15, to: now) ?? now.addingTimeInterval(-15 * 24 * 3600)
        let recentRuns = validRuns.filter { $0.date >= midDate }
        let olderRuns = validRuns.filter { $0.date < midDate }

        let recentEF = recentRuns.compactMap(\.efficiencyFactor)
        let olderEF = olderRuns.compactMap(\.efficiencyFactor)
        let avgRecentEF = recentEF.isEmpty ? 0.0 : (recentEF.reduce(0, +) / Double(recentEF.count))
        let avgOlderEF = olderEF.isEmpty ? 0.0 : (olderEF.reduce(0, +) / Double(olderEF.count))
        let efDelta = (avgRecentEF > 0 && avgOlderEF > 0) ? (avgRecentEF - avgOlderEF) : 0.0

        let recentOscs = recentRuns.compactMap { $0.workingAvgVerticalOscillation ?? $0.rawAvgVerticalOscillation }
        let olderOscs = olderRuns.compactMap { $0.workingAvgVerticalOscillation ?? $0.rawAvgVerticalOscillation }
        let avgRecentOsc = recentOscs.isEmpty ? 0.0 : (recentOscs.reduce(0, +) / Double(recentOscs.count))
        let avgOlderOsc = olderOscs.isEmpty ? 0.0 : (olderOscs.reduce(0, +) / Double(olderOscs.count))
        let oscDelta = (avgRecentOsc > 0 && avgOlderOsc > 0) ? (avgRecentOsc - avgOlderOsc) : 0.0

        let recentVRs = recentRuns.compactMap(\.verticalRatio)
        let olderVRs = olderRuns.compactMap(\.verticalRatio)
        let avgRecentVR = recentVRs.isEmpty ? 0.0 : (recentVRs.reduce(0, +) / Double(recentVRs.count))
        let avgOlderVR = olderVRs.isEmpty ? 0.0 : (olderVRs.reduce(0, +) / Double(olderVRs.count))
        let vrDelta = (avgRecentVR > 0 && avgOlderVR > 0) ? (avgRecentVR - avgOlderVR) : 0.0

        let recentHR = recentRuns.map(\.workingAvgHeartRate).reduce(0, +) / Double(max(1, recentRuns.count))
        let olderHR = olderRuns.map(\.workingAvgHeartRate).reduce(0, +) / Double(max(1, olderRuns.count))
        let hrDelta = (recentHR > 0 && olderHR > 0) ? (recentHR - olderHR) : 0.0

        let verdict: TrajectoryVerdict
        if (efDelta <= -0.02 && olderEF.count >= 2) || (hrDelta >= 3.0 && olderHR > 0) {
            verdict = .easeUp
        } else if efDelta > 0.02 || hrDelta < -2.0 || oscDelta < -0.2 || vrDelta < -0.3 {
            verdict = .onTrack
        } else {
            verdict = .stepItUp
        }

        return TrajectoryAssessment(
            verdict: verdict,
            efDelta: efDelta,
            hrDelta: hrDelta,
            oscDelta: oscDelta,
            vrDelta: vrDelta,
            avgRecentEF: avgRecentEF,
            avgRecentOsc: avgRecentOsc,
            avgRecentVR: avgRecentVR
        )
    }

    /// Computes duration- and classification-weighted 30-day baseline statistics matching the canonical athletic model.
    public static func computeWeightedBaselineStats(
        from runRecords: [RunRecord],
        priorTo date: Date = Date()
    ) -> WeightedBaselineStats? {
        let cal = Calendar.current
        let thirtyDaysAgo = cal.date(byAdding: .day, value: -30, to: date) ?? date.addingTimeInterval(-30 * 24 * 3600)
        let baselineRuns = runRecords.filter {
            $0.workingAvgPace > 0 &&
            $0.duration > 0 &&
            $0.date < date &&
            $0.date >= thirtyDaysAgo &&
            !$0.isDeleted
        }

        guard !baselineRuns.isEmpty else {
            return nil
        }

        let totalDuration = baselineRuns.map(\.duration).reduce(0, +)
        guard totalDuration > 0 else {
            return nil
        }

        if baselineRuns.count < 3 {
            let pace = baselineRuns.map { $0.workingAvgPace * $0.duration }.reduce(0, +) / totalDuration
            let cadRuns = baselineRuns.filter { $0.workingAvgCadence > 0 }
            let cadDur = cadRuns.map(\.duration).reduce(0, +)
            let cad = cadDur > 0 ? (cadRuns.map { $0.workingAvgCadence * $0.duration }.reduce(0, +) / cadDur) : 155.0

            let hrRuns = baselineRuns.filter { $0.workingAvgHeartRate > 0 }
            let hrDur = hrRuns.map(\.duration).reduce(0, +)
            let hr = hrDur > 0 ? (hrRuns.map { $0.workingAvgHeartRate * $0.duration }.reduce(0, +) / hrDur) : 0.0

            let oscRuns = baselineRuns.compactMap { r -> (Double, Double)? in
                guard let v = r.workingAvgVerticalOscillation ?? r.rawAvgVerticalOscillation, v > 0 else { return nil }
                return (v, r.duration)
            }
            let oscDur = oscRuns.map(\.1).reduce(0, +)
            let osc = oscDur > 0 ? (oscRuns.map { $0.0 * $0.1 }.reduce(0, +) / oscDur) : nil

            let strideRuns = baselineRuns.compactMap { r -> (Double, Double)? in
                guard let v = r.workingAvgStrideLength ?? r.rawAvgStrideLength, v > 0 else { return nil }
                return (v, r.duration)
            }
            let strideDur = strideRuns.map(\.1).reduce(0, +)
            let stride = strideDur > 0 ? (strideRuns.map { $0.0 * $0.1 }.reduce(0, +) / strideDur) : nil

            let vrRuns = baselineRuns.compactMap { r -> (Double, Double)? in
                guard let v = r.verticalRatio, v > 0 else { return nil }
                return (v, r.duration)
            }
            let vrDur = vrRuns.map(\.1).reduce(0, +)
            let vr = vrDur > 0 ? (vrRuns.map { $0.0 * $0.1 }.reduce(0, +) / vrDur) : nil

            return WeightedBaselineStats(
                avgPace: pace,
                avgCadence: cad,
                avgHR: hr,
                avgOscillation: osc,
                avgStrideLength: stride,
                avgVerticalRatio: vr
            )
        }

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

        let totalWeight = baselineRuns.map { aerobicWeight(for: $0) }.reduce(0, +)
        guard totalWeight > 0 else {
            return nil
        }

        let pace = baselineRuns.map { $0.workingAvgPace * aerobicWeight(for: $0) }.reduce(0, +) / totalWeight

        let cadRuns = baselineRuns.filter { $0.workingAvgCadence > 0 }
        let cadWeight = cadRuns.map { aerobicWeight(for: $0) }.reduce(0, +)
        let cad = cadWeight > 0 ? (cadRuns.map { $0.workingAvgCadence * aerobicWeight(for: $0) }.reduce(0, +) / cadWeight) : 155.0

        let hrRuns = baselineRuns.filter { $0.workingAvgHeartRate > 0 }
        let hrWeight = hrRuns.map { aerobicWeight(for: $0) }.reduce(0, +)
        let hr = hrWeight > 0 ? (hrRuns.map { $0.workingAvgHeartRate * aerobicWeight(for: $0) }.reduce(0, +) / hrWeight) : 0.0

        let oscRuns = baselineRuns.compactMap { r -> (Double, Double)? in
            guard let v = r.workingAvgVerticalOscillation ?? r.rawAvgVerticalOscillation, v > 0 else { return nil }
            return (v, aerobicWeight(for: r))
        }
        let oscWeight = oscRuns.map(\.1).reduce(0, +)
        let osc = oscWeight > 0 ? (oscRuns.map { $0.0 * $0.1 }.reduce(0, +) / oscWeight) : nil

        let strideRuns = baselineRuns.compactMap { r -> (Double, Double)? in
            guard let v = r.workingAvgStrideLength ?? r.rawAvgStrideLength, v > 0 else { return nil }
            return (v, aerobicWeight(for: r))
        }
        let strideWeight = strideRuns.map(\.1).reduce(0, +)
        let stride = strideWeight > 0 ? (strideRuns.map { $0.0 * $0.1 }.reduce(0, +) / strideWeight) : nil

        let vrRuns = baselineRuns.compactMap { r -> (Double, Double)? in
            guard let v = r.verticalRatio, v > 0 else { return nil }
            return (v, aerobicWeight(for: r))
        }
        let vrWeight = vrRuns.map(\.1).reduce(0, +)
        let vr = vrWeight > 0 ? (vrRuns.map { $0.0 * $0.1 }.reduce(0, +) / vrWeight) : nil

        return WeightedBaselineStats(
            avgPace: pace,
            avgCadence: cad,
            avgHR: hr,
            avgOscillation: osc,
            avgStrideLength: stride,
            avgVerticalRatio: vr
        )
    }

    /// Computes duration- and classification-weighted 30-day baseline stats matching RunAnalyzerActor.
    /// Falls back to unweighted mean if valid runs < 3 to ensure predictable cold-start and test behavior.
    static func computeWeightedBaseline(from runRecords: [RunRecord], priorTo date: Date) -> (pace: Double, cadence: Int) {
        if let stats = computeWeightedBaselineStats(from: runRecords, priorTo: date) {
            return (stats.avgPace, Int(stats.avgCadence.rounded()))
        }
        let fallbackRuns = runRecords.filter { $0.workingAvgPace > 0 && $0.date < date && !$0.isDeleted }
        let pace = fallbackRuns.isEmpty ? 340.0 : (fallbackRuns.prefix(10).map(\.workingAvgPace).reduce(0, +) / Double(min(10, fallbackRuns.count)))
        let cad = fallbackRuns.isEmpty ? 155 : Int(fallbackRuns.prefix(10).map(\.workingAvgCadence).reduce(0, +) / Double(min(10, fallbackRuns.count)))
        return (pace, cad)
    }
}
