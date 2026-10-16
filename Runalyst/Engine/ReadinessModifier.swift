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

    private static let heavyTypes: Set<String> = ["Intervals", "Pyramids", "Tempo Run", "Hill Repeats", "Fartlek"]

    /// Matches the Dashboard 7-day tactical coach definition of a heavy session.
    var isHardSession: Bool {
        Self.heavyTypes.contains(detectedType) || percentZone4 >= 0.35
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
        guard state.relaxesCadenceTarget, state.applies(to: drillId),
              let baseline = baselineCadence, baseline > 0,
              let target, let midpoint = cadenceMidpoint(of: target),
              midpoint > Double(baseline) + 1 else {
            return AdaptiveDrillTarget(standardTargetCadence: target, targetCadence: target)
        }
        let neutral = "\(max(140, baseline - 3))-\(min(185, baseline + 3))"
        return AdaptiveDrillTarget(standardTargetCadence: target, targetCadence: neutral)
    }

    /// Parses "159-165", "162", or "162 SPM" into a midpoint cadence.
    static func cadenceMidpoint(of target: String) -> Double? {
        let clean = target.replacingOccurrences(of: "SPM", with: "").trimmingCharacters(in: .whitespaces)
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
        let state = readiness.state.applies(to: drillId) ? readiness.state : .productive
        let target = adaptTarget(dto.targetCadence, baselineCadence: dto.previousCadence, drillId: drillId, state: state)
        return DrillPrescriptionDTO(
            title: dto.title,
            preRunDrillId: dto.preRunDrillId,
            purpose: dto.purpose,
            targetCadence: target.targetCadence,
            previousCadence: dto.previousCadence,
            durationMinutes: dto.durationMinutes,
            hapticMode: dto.hapticMode,
            readinessState: state == .productive ? nil : state.rawValue
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
