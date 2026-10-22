import Foundation
import SwiftData

// MARK: - Readiness Domain

/// The runner's acute physiological state, used to modulate 30-day baseline drill prescriptions.
///
/// A 30-day rolling baseline measures chronic adaptation (Chronic Training Load). It cannot see
/// that the runner is carrying muscular damage from a brutal session 36 hours ago, or that they are
/// in a planned deload week. `ReadinessState` bridges that gap using the Acute-to-Chronic Workload
/// Ratio (ACWR) and acute telemetry triggers, resolved deterministically in Swift.
enum ReadinessState: String, Codable, Sendable, Equatable {
    /// Acute ≈ Chronic (ACWR 0.8–1.3). Apply the standard 30-day personalized target.
    case productive
    /// Acute ≫ Chronic (ACWR > 1.5) or acute fatigue telemetry. Relax turnover, cut volume.
    case acuteFatigue
    /// Rolling 7-day mileage down ≥ 25% vs trailing 3-week average at controlled intensity.
    /// Hold intensity, halve volume, extend recovery.
    case deload

    /// Multiplier applied to interval repetitions.
    var volumeScale: Double {
        switch self {
        case .productive: return 1.0
        case .acuteFatigue, .deload: return 0.5
        }
    }

    /// Multiplier applied to recovery intervals (e.g. 60 s → 90 s during a deload).
    var recoveryScale: Double {
        switch self {
        case .productive, .acuteFatigue: return 1.0
        case .deload: return 1.5
        }
    }

    /// Whether overspeed cadence targets are softened back to the runner's natural baseline.
    var relaxesCadenceTarget: Bool {
        self == .acuteFatigue
    }

    var displayName: String {
        switch self {
        case .productive: return "Productive Training"
        case .acuteFatigue: return "Acute Fatigue"
        case .deload: return "Deload Week"
        }
    }

    /// Continuous aerobic drills (flush, recovery jog, Zone 2) are already recovery-appropriate
    /// and are never modulated.
    func applies(to drillId: PreRunDrillId) -> Bool {
        guard self != .productive else { return false }
        switch drillId {
        case .aerobicFlush, .recoveryJog, .zone2Run:
            return false
        default:
            return true
        }
    }
}

/// A concrete telemetry signal that contributed to the readiness verdict.
enum ReadinessTrigger: Sendable, Equatable {
    /// 7-day load exceeds 1.5× the 4-week weekly average.
    case acwrSpike(ratio: Double)
    /// Hard sessions (Zone 4/5 heavy) on two consecutive calendar days, the latest within 72 h.
    case consecutiveHardDays
    /// Cadence decelerated in the final third of each of the prior two runs.
    case cadenceFade
    /// Heart rate drifted upward at a steady pace on the most recent run.
    case cardiacDrift
    /// 7-day mileage dropped by the given fraction vs the trailing 3-week weekly average.
    case mileageDeload(dropFraction: Double)
}

/// A Sendable, SwiftData-free projection of a `RunRecord` used for readiness math.
struct ReadinessRunSnapshot: Sendable, Equatable {
    let date: Date
    let distanceMeters: Double
    let durationSeconds: Double
    let percentZone4: Double
    let detectedType: String
    let tags: Set<String>

    init(
        date: Date,
        distanceMeters: Double,
        durationSeconds: Double,
        percentZone4: Double,
        detectedType: String,
        tags: Set<String> = []
    ) {
        self.date = date
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.percentZone4 = percentZone4
        self.detectedType = detectedType
        self.tags = tags
    }

    public static let heavyTypes: Set<String> = ["Intervals", "Pyramids", "Tempo Run", "Hill Repeats", "Fartlek"]

    /// Matches the Dashboard 7-day tactical coach definition of a heavy session.
    /// Short pre-run primers (<= 20 min and Zone 4 < 25%) are neuromuscular activations, NOT heavy cardiovascular workouts.
    var isHardSession: Bool {
        if (tags.contains("prescribedDrill") || durationSeconds <= 1200) && percentZone4 < 0.25 {
            return false
        }
        return Self.heavyTypes.contains(detectedType) || percentZone4 >= 0.35
    }

    /// Session load proxy (TRIMP-style): working minutes, with Zone 4/5 minutes weighted 3×.
    var trainingLoad: Double {
        let minutes = max(0, durationSeconds) / 60.0
        let z4 = min(1.0, max(0.0, percentZone4))
        return minutes * (1.0 + 2.0 * z4)
    }
}

/// The deterministic output of the readiness evaluator.
struct ReadinessAssessment: Sendable, Equatable {
    let state: ReadinessState
    let triggers: [ReadinessTrigger]
    /// Sum of session load over the last 7 days.
    let acuteLoad: Double
    /// Average weekly session load over the last 28 days.
    let chronicWeeklyLoad: Double
    /// Acute-to-Chronic Workload Ratio, or `nil` when history is too thin to trust.
    let acwr: Double?
    /// Fractional mileage drop vs the trailing 3-week weekly average (positive = less mileage).
    let mileageDropFraction: Double?

    static let productive = ReadinessAssessment(
        state: .productive,
        triggers: [],
        acuteLoad: 0,
        chronicWeeklyLoad: 0,
        acwr: nil,
        mileageDropFraction: nil
    )
}

// MARK: - Evaluator

/// Deterministic ACWR + acute-telemetry readiness evaluator.
///
/// Priority is resolved in Swift (never by the LLM): Acute Fatigue > Deload > Productive.
enum ReadinessEvaluator {
    static let acuteWindowDays = 7
    static let chronicWindowDays = 28
    static let acwrFatigueThreshold = 1.5
    static let deloadDropThreshold = 0.25
    static let deloadMaxZone4Fraction = 0.10
    static let acuteTriggerWindowHours: Double = 72
    /// Minimum span of history (days) before ACWR is trusted; avoids new-user false spikes.
    static let minimumHistorySpanDays = 14
    static let minimumChronicRuns = 4
    static let minimumTrailingRuns = 3
    static let minimumTrailingWeeklyMeters = 5_000.0

    static func assess(
        runs: [ReadinessRunSnapshot],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ReadinessAssessment {
        let dayInterval: TimeInterval = 24 * 3600
        let acuteCutoff = now.addingTimeInterval(-Double(acuteWindowDays) * dayInterval)
        let chronicCutoff = now.addingTimeInterval(-Double(chronicWindowDays) * dayInterval)
        let triggerCutoff = now.addingTimeInterval(-acuteTriggerWindowHours * 3600)

        // Newest first, strictly prior to `now`, within the 28-day window.
        let window = runs
            .filter { $0.date <= now && $0.date >= chronicCutoff }
            .sorted { $0.date > $1.date }

        guard !window.isEmpty else { return .productive }

        let acuteRuns = window.filter { $0.date >= acuteCutoff }
        let trailingRuns = window.filter { $0.date < acuteCutoff }

        // --- ACWR (coupled: chronic window includes the acute week) ---
        let acuteLoad = acuteRuns.map(\.trainingLoad).reduce(0, +)
        let chronicWeeklyLoad = window.map(\.trainingLoad).reduce(0, +) / (Double(chronicWindowDays) / 7.0)

        let oldestDate = window.last?.date ?? now
        let historySpanDays = now.timeIntervalSince(oldestDate) / dayInterval
        let hasChronicHistory = historySpanDays >= Double(minimumHistorySpanDays)
            && window.count >= minimumChronicRuns
            && chronicWeeklyLoad > 0
        let acwr: Double? = hasChronicHistory ? acuteLoad / chronicWeeklyLoad : nil

        // --- Mileage drop vs trailing 3-week average ---
        let acuteMeters = acuteRuns.map(\.distanceMeters).reduce(0, +)
        let trailingWeeks = Double(chronicWindowDays - acuteWindowDays) / 7.0
        let trailingWeeklyMeters = trailingRuns.map(\.distanceMeters).reduce(0, +) / trailingWeeks
        let hasTrailingHistory = trailingRuns.count >= minimumTrailingRuns
            && trailingWeeklyMeters >= minimumTrailingWeeklyMeters
        let mileageDrop: Double? = hasTrailingHistory ? (1.0 - acuteMeters / trailingWeeklyMeters) : nil

        // --- Acute fatigue triggers ---
        var fatigueTriggers: [ReadinessTrigger] = []

        if hasConsecutiveHardDays(in: acuteRuns, triggerCutoff: triggerCutoff, calendar: calendar) {
            fatigueTriggers.append(.consecutiveHardDays)
        }
        if let ratio = acwr, ratio > acwrFatigueThreshold {
            fatigueTriggers.append(.acwrSpike(ratio: ratio))
        }
        let lastTwo = Array(acuteRuns.prefix(2))
        if lastTwo.count == 2,
           let latest = lastTwo.first, latest.date >= triggerCutoff,
           lastTwo.allSatisfy({ $0.tags.contains(FramboiseReadinessTag.cadenceFade) }) {
            fatigueTriggers.append(.cadenceFade)
        }
        if let latest = acuteRuns.first, latest.date >= triggerCutoff {
            let hasDrift = latest.tags.contains(FramboiseReadinessTag.cardiacDrift) || latest.tags.contains("fatigueDrift")
            if hasDrift {
                fatigueTriggers.append(.cardiacDrift)
            }
        }

        if !fatigueTriggers.isEmpty {
            return ReadinessAssessment(
                state: .acuteFatigue,
                triggers: fatigueTriggers,
                acuteLoad: acuteLoad,
                chronicWeeklyLoad: chronicWeeklyLoad,
                acwr: acwr,
                mileageDropFraction: mileageDrop
            )
        }

        // --- Deload: mileage down ≥ 25% with controlled (Zone 1–2) intensity ---
        if let drop = mileageDrop, drop >= deloadDropThreshold {
            let acuteSeconds = acuteRuns.map(\.durationSeconds).reduce(0, +)
            let weightedZ4 = acuteSeconds > 0
                ? acuteRuns.map { $0.percentZone4 * $0.durationSeconds }.reduce(0, +) / acuteSeconds
                : 0
            let intensityControlled = weightedZ4 <= deloadMaxZone4Fraction
                && !acuteRuns.contains(where: \.isHardSession)
            if intensityControlled {
                return ReadinessAssessment(
                    state: .deload,
                    triggers: [.mileageDeload(dropFraction: drop)],
                    acuteLoad: acuteLoad,
                    chronicWeeklyLoad: chronicWeeklyLoad,
                    acwr: acwr,
                    mileageDropFraction: drop
                )
            }
        }

        return ReadinessAssessment(
            state: .productive,
            triggers: [],
            acuteLoad: acuteLoad,
            chronicWeeklyLoad: chronicWeeklyLoad,
            acwr: acwr,
            mileageDropFraction: mileageDrop
        )
    }

    private static func hasConsecutiveHardDays(
        in acuteRuns: [ReadinessRunSnapshot],
        triggerCutoff: Date,
        calendar: Calendar
    ) -> Bool {
        let hard = acuteRuns.filter(\.isHardSession)
        guard hard.count >= 2 else { return false }
        for index in 0..<(hard.count - 1) {
            let later = hard[index]
            let earlier = hard[index + 1]
            guard later.date >= triggerCutoff else { continue }
            let laterDay = calendar.startOfDay(for: later.date)
            let earlierDay = calendar.startOfDay(for: earlier.date)
            if let days = calendar.dateComponents([.day], from: earlierDay, to: laterDay).day, days == 1 {
                return true
            }
        }
        return false
    }
}

// MARK: - SwiftData Adapters

extension ReadinessRunSnapshot {
    @MainActor
    init(run: RunRecord) {
        self.init(
            date: run.date,
            distanceMeters: run.effectiveWorkingDistanceMeters,
            durationSeconds: run.effectiveWorkingDurationSeconds,
            percentZone4: run.percentZone4,
            detectedType: run.detectedTypeRaw,
            tags: Set(run.framboiseTags)
        )
    }
}

extension ReadinessEvaluator {
    /// Evaluates readiness from an already-fetched `@Query` array (e.g. `DashboardView.runRecords`).
    @MainActor
    static func assess(runRecords: [RunRecord], now: Date = Date()) -> ReadinessAssessment {
        let cutoff = now.addingTimeInterval(-Double(chronicWindowDays) * 24 * 3600)
        let snapshots = runRecords
            .filter { !$0.isDeleted && $0.modelContext != nil && $0.date >= cutoff }
            .map(ReadinessRunSnapshot.init(run:))
        return assess(runs: snapshots, now: now)
    }

    /// Evaluates readiness by fetching only the trailing 28-day window from SwiftData.
    @MainActor
    static func assess(context: ModelContext, now: Date = Date()) -> ReadinessAssessment {
        let cutoff = now.addingTimeInterval(-Double(chronicWindowDays) * 24 * 3600)
        let descriptor = FetchDescriptor<RunRecord>(
            predicate: #Predicate<RunRecord> { $0.date >= cutoff },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        guard let runs = try? context.fetch(descriptor) else { return .productive }
        return assess(runs: runs.map(ReadinessRunSnapshot.init(run:)), now: now)
    }
}

// MARK: - Target & Context Modifier

/// The adapted cadence prescription for a drill.
struct AdaptiveDrillTarget: Sendable, Equatable {
    /// The standard 30-day personalized target (unmodified).
    let standardTargetCadence: String?
    /// The target actually prescribed today.
    let targetCadence: String?

    var isCadenceRelaxed: Bool {
        standardTargetCadence != targetCadence
    }
}

enum ReadinessModifier {
    /// Softens an overspeed cadence target back to the runner's neutral baseline band during
    /// acute fatigue. Deload and productive states keep intensity identical.
    static func adaptTarget(
        _ target: String?,
        baselineCadence: Int?,
        drillId: PreRunDrillId,
        state: ReadinessState
    ) -> AdaptiveDrillTarget {
        guard let rawTarget = target else {
            return AdaptiveDrillTarget(standardTargetCadence: nil, targetCadence: nil)
        }
        let normalizedTarget = PreRunDrill.normalizeCadenceTargetString(rawTarget)
        // If the caller already supplied an explicitly adapted target (e.g. "155–161 SPM (Adapted)"
        // from SessionSynthesisEngine), preserve that exact adapted range and derive the unadapted
        // standard target from the drill template.
        if rawTarget.localizedCaseInsensitiveContains("adapted") {
            let standard = DrillTemplate.template(for: drillId).calculateTargetCadence(baselineCadence ?? 155)
            return AdaptiveDrillTarget(standardTargetCadence: standard, targetCadence: normalizedTarget)
        }

        guard state.relaxesCadenceTarget, state.applies(to: drillId),
              let baseline = baselineCadence, baseline > 0,
              let midpoint = cadenceMidpoint(of: normalizedTarget),
              midpoint > Double(baseline) + 1 else {
            let passthrough = (rawTarget.contains("–") || rawTarget.contains("—")) ? normalizedTarget : rawTarget
            return AdaptiveDrillTarget(standardTargetCadence: passthrough, targetCadence: passthrough)
        }
        let neutral = "\(max(140, baseline - 3))-\(min(185, baseline + 3))"
        return AdaptiveDrillTarget(standardTargetCadence: normalizedTarget, targetCadence: neutral)
    }

    /// Parses "159-165", "155–161 SPM (Adapted)", "162", or "162 SPM" into a midpoint cadence.
    static func cadenceMidpoint(of target: String) -> Double? {
        let clean = PreRunDrill.normalizeCadenceTargetString(target)
        let parts = clean.components(separatedBy: "-").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count == 2, let lower = Double(parts[0]), let upper = Double(parts[1]) {
            return (lower + upper) / 2.0
        }
        return Double(clean)
    }

    /// Produces a prescription DTO carrying the adapted target and readiness state so the
    /// Apple Watch `WorkoutPlan` compiled by `WorkoutBridge` matches the readout exactly.
    static func adaptedDTO(_ dto: DrillPrescriptionDTO, readiness: ReadinessAssessment) -> DrillPrescriptionDTO {
        let drillId = dto.preRunDrillId.flatMap(PreRunDrillId.init(rawValue:)) ?? .strides
        let effectiveState: ReadinessState = {
            if readiness.state != .productive {
                return readiness.state
            }
            if let explicit = dto.readinessState.flatMap(ReadinessState.init(rawValue:)) {
                return explicit
            }
            return .productive
        }()
        let state = effectiveState.applies(to: drillId) ? effectiveState : .productive
        let target = adaptTarget(dto.targetCadence, baselineCadence: dto.previousCadence, drillId: drillId, state: state)
        return DrillPrescriptionDTO(
            title: dto.title,
            preRunDrillId: dto.preRunDrillId,
            purpose: dto.purpose,
            targetCadence: target.targetCadence,
            previousCadence: dto.previousCadence,
            durationMinutes: dto.durationMinutes,
            hapticMode: dto.hapticMode,
            readinessState: state == .productive ? nil : state.rawValue,
            isIndoor: dto.isIndoor
        )
    }

    /// Deterministic, runner-facing explanation of why today's drill was adapted.
    static func coachContext(
        assessment: ReadinessAssessment,
        target: AdaptiveDrillTarget,
        baselineCadence: Int?,
        standardSpec: IntervalSpec?,
        adaptedSpec: IntervalSpec?
    ) -> String? {
        switch assessment.state {
        case .productive:
            return nil
        case .acuteFatigue:
            var sentences: [String] = [fatigueLead(for: assessment.triggers)]
            if target.isCadenceRelaxed, let baseline = baselineCadence {
                sentences.append("Today's cadence target has been relaxed to your natural \(baseline) SPM rhythm so you can focus on fluid form rather than forcing turnover under fatigue.")
            }
            if let standard = standardSpec, let adapted = adaptedSpec, adapted.iterations < standard.iterations {
                sentences.append("Reps are trimmed from \(standard.iterations) to \(adapted.iterations) to protect your mechanics.")
            }
            return sentences.joined(separator: " ")
        case .deload:
            let dropPct = Int(((assessment.mileageDropFraction ?? deloadFallbackDrop) * 100).rounded())
            var sentence = "Your mileage is down \(dropPct)% versus your trailing 3-week average, so this is a deload week. Intensity stays the same to keep your legs sharp"
            if let standard = standardSpec, let adapted = adaptedSpec {
                sentence += ", but reps drop from \(standard.iterations) to \(adapted.iterations)"
                if let stdRec = standard.recoverySeconds, let newRec = adapted.recoverySeconds, newRec > stdRec {
                    sentence += " and recovery stretches from \(stdRec) to \(newRec) seconds"
                }
            }
            sentence += " so you shed fatigue without lactic build-up."
            return sentence
        }
    }

    private static let deloadFallbackDrop = 0.25

    private static func fatigueLead(for triggers: [ReadinessTrigger]) -> String {
        for trigger in triggers {
            switch trigger {
            case .consecutiveHardDays:
                return "You've stacked back-to-back hard sessions over the past 48 hours."
            case .acwrSpike(let ratio):
                return "Your 7-day training load is \(String(format: "%.1f", ratio))× your 4-week average, a sharp short-term spike."
            case .cadenceFade:
                return "Your cadence faded in the final third of your last two runs, a classic sign of accumulated fatigue."
            case .cardiacDrift:
                return "Your heart rate drifted upward at a steady pace on your last run, a sign your body is still recovering."
            case .mileageDeload:
                continue
            }
        }
        return "Your recent training shows signs of acute fatigue."
    }
}

/// Readiness tags emitted by `FramboiseEngine.generateReadinessTags(buckets:)` at ingestion time.
enum FramboiseReadinessTag {
    static let cadenceFade = "cadenceFade"
    static let cardiacDrift = "cardiacDrift"
}

// MARK: - Streak & 48-Hour Volume Summary

/// Evaluates multi-day streaks, 48-hour volume compression, and day-over-day cardiac decoupling
/// calibrated by the runner's experience level and active training goal.
public struct StreakAndVolumeSummary: Sendable, Equatable {
    public let consecutiveRunDays: Int
    public let last48hDurationMinutes: Double
    public let trailingWeeklyDurationMinutes: Double
    public let trailingWeeklyActiveDays: Double
    public let backToBackHRDecouplingBPM: Double
    public let volumeRatio48h: Double
    public let maxConsecutiveDays: Int
    public let volumeCompressionThreshold: Double
    public let shouldRecommendRestDay: Bool
    public let restDayReason: String?

    @MainActor
    static func evaluate(
        runs: [RunRecord],
        experienceLevel: String,
        trainingGoal: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> StreakAndVolumeSummary {
        // 1. Separate main runs (>= 20 min or non-primer) from short primers (< 20 min)
        let mainRuns = runs.filter { run in
            guard !run.isDeleted && run.date <= now else { return false }
            let hasDrillTag = run.framboiseTags.contains("prescribedDrill") || run.prescribedDrillName != nil
            let isShortPrimer = (hasDrillTag || run.duration < 1200) && run.percentZone4 < 0.25
            return !isShortPrimer
        }.sorted { $0.date > $1.date }

        // 2. Trailing 28-day baseline (duration and frequency)
        let day28Cutoff = calendar.date(byAdding: .day, value: -28, to: now) ?? now.addingTimeInterval(-28 * 24 * 3600)
        let trailingRuns = mainRuns.filter { $0.date >= day28Cutoff }
        let totalTrailingDurationMins = trailingRuns.map { $0.duration / 60.0 }.reduce(0, +)
        let trailingWeeklyDurationMinutes = totalTrailingDurationMins > 0 ? (totalTrailingDurationMins / 4.0) : 150.0

        var uniqueTrailingDays = Set<DateComponents>()
        for run in trailingRuns {
            uniqueTrailingDays.insert(calendar.dateComponents([.year, .month, .day], from: run.date))
        }
        let trailingWeeklyActiveDays = !uniqueTrailingDays.isEmpty ? (Double(uniqueTrailingDays.count) / 4.0) : 3.5

        // 3. 48-Hour Volume (Includes all runs banked in past 48 hours)
        let cutoff48h = now.addingTimeInterval(-48 * 3600)
        let runs48h = runs.filter { !$0.isDeleted && $0.date <= now && $0.date >= cutoff48h }
        let last48hDurationMinutes = runs48h.map { $0.duration / 60.0 }.reduce(0, +)
        let volumeRatio48h = trailingWeeklyDurationMinutes > 0 ? (last48hDurationMinutes / trailingWeeklyDurationMinutes) : 0.0

        // 4. Consecutive Run Days (Streak)
        var streak = 0
        var checkDate = now
        let todayComponents = calendar.dateComponents([.year, .month, .day], from: now)
        let hasRunToday = mainRuns.contains { calendar.dateComponents([.year, .month, .day], from: $0.date) == todayComponents }
        if !hasRunToday {
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: now) {
                let yesterdayComponents = calendar.dateComponents([.year, .month, .day], from: yesterday)
                let hasRunYesterday = mainRuns.contains { calendar.dateComponents([.year, .month, .day], from: $0.date) == yesterdayComponents }
                if hasRunYesterday {
                    checkDate = yesterday
                }
            }
        }

        while streak < 14 {
            guard let targetDay = calendar.date(byAdding: .day, value: -streak, to: checkDate) else { break }
            let targetComponents = calendar.dateComponents([.year, .month, .day], from: targetDay)
            let ranOnDay = mainRuns.contains { calendar.dateComponents([.year, .month, .day], from: $0.date) == targetComponents }
            if ranOnDay {
                streak += 1
            } else {
                break
            }
        }

        // 5. Back-to-Back HR Decoupling (Day-over-Day)
        var hrDecoupling = 0.0
        if streak >= 2, mainRuns.count >= 2 {
            let latest = mainRuns[0]
            let previous = mainRuns[1]
            if calendar.isDate(latest.date, inSameDayAs: checkDate),
               let prevExpected = calendar.date(byAdding: .day, value: -1, to: checkDate),
               calendar.isDate(previous.date, inSameDayAs: prevExpected) {
                let latestHR = latest.workingAvgHeartRate > 0 ? latest.workingAvgHeartRate : latest.rawAvgHeartRate
                let prevHR = previous.workingAvgHeartRate > 0 ? previous.workingAvgHeartRate : previous.rawAvgHeartRate
                if latestHR > 0 && prevHR > 0 {
                    hrDecoupling = latestHR - prevHR
                }
            }
        }

        // 6. Calibration Matrix (Experience & Goal)
        let exp = experienceLevel.lowercased()
        let baseMaxDays: Int
        let baseCompressionThreshold: Double

        if exp.contains("novice") || exp.contains("beginner") {
            baseMaxDays = 2
            baseCompressionThreshold = 0.50
        } else if exp.contains("advanced") || exp.contains("veteran") {
            baseMaxDays = 4
            baseCompressionThreshold = 0.68
        } else if exp.contains("competitive") || exp.contains("elite") {
            baseMaxDays = 5
            baseCompressionThreshold = 0.75
        } else {
            // Intermediate / Default
            baseMaxDays = 3
            baseCompressionThreshold = 0.60
        }

        // Goal Modifiers
        var maxDays = baseMaxDays
        var compressionThreshold = baseCompressionThreshold
        let goal = trainingGoal.lowercased()

        if goal.contains("injury") || goal.contains("recovery") {
            maxDays = 1
            compressionThreshold = 0.45
        } else if goal.contains("half") || goal.contains("marathon") {
            if !exp.contains("novice") {
                maxDays = min(5, baseMaxDays + 1)
            }
            compressionThreshold = min(0.85, baseCompressionThreshold + 0.05)
        }

        // 7. Decision
        var recommendRest = false
        var reason: String?

        if streak >= maxDays {
            recommendRest = true
            reason = "You've completed \(streak) consecutive days of running. A scheduled rest day allows muscle and tendon rebuilding before your next run toward \(trainingGoal)."
        } else if volumeRatio48h >= compressionThreshold && last48hDurationMinutes >= 60.0 {
            recommendRest = true
            let pct = Int(round(volumeRatio48h * 100))
            let mins48 = Int(round(last48hDurationMinutes))
            let weeklyMins = Int(round(trailingWeeklyDurationMinutes))
            reason = "48-Hour Volume Compression: You've banked \(mins48) min in the last 48 hours (\(pct)% of your \(weeklyMins) min/week average). A rest day allows deep recovery to prevent cumulative overload."
        } else if streak >= 2 && hrDecoupling >= 10.0 {
            recommendRest = true
            let shift = Int(round(hrDecoupling))
            reason = "Day-over-day cardiac drift (+\(shift) BPM) indicates autonomic fatigue after consecutive runs. Take a rest day to recover baseline cardiac cost."
        }

        return StreakAndVolumeSummary(
            consecutiveRunDays: streak,
            last48hDurationMinutes: last48hDurationMinutes,
            trailingWeeklyDurationMinutes: trailingWeeklyDurationMinutes,
            trailingWeeklyActiveDays: trailingWeeklyActiveDays,
            backToBackHRDecouplingBPM: hrDecoupling,
            volumeRatio48h: volumeRatio48h,
            maxConsecutiveDays: maxDays,
            volumeCompressionThreshold: compressionThreshold,
            shouldRecommendRestDay: recommendRest,
            restDayReason: reason
        )
    }
}
