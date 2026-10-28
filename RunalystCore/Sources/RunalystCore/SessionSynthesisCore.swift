import Foundation

// MARK: - Synthesis Input Types

/// Pure value-type representation of a historical workout for deterministic synthesis.
public struct SynthesisRunSample: Sendable, Equatable, Codable {
    public let id: UUID
    public let date: Date
    public let durationSeconds: Double
    public let distanceMeters: Double
    public let workingAvgPaceSecPerKm: Double
    public let workingAvgCadenceSPM: Double
    public let workingAvgHeartRateBPM: Double
    public let percentZone4: Double
    public let detectedType: String
    public let isPrimer: Bool
    public let hadCardiacDrift: Bool
    public let driftBPM: Int
    public let hadCadenceFade: Bool
    public let efficiencyFactor: Double?
    public let verticalOscillationCm: Double?
    public let strideLengthMeters: Double?
    public let verticalRatio: Double?

    public init(
        id: UUID = UUID(),
        date: Date,
        durationSeconds: Double,
        distanceMeters: Double,
        workingAvgPaceSecPerKm: Double,
        workingAvgCadenceSPM: Double,
        workingAvgHeartRateBPM: Double,
        percentZone4: Double,
        detectedType: String,
        isPrimer: Bool = false,
        hadCardiacDrift: Bool = false,
        driftBPM: Int = 0,
        hadCadenceFade: Bool = false,
        efficiencyFactor: Double? = nil,
        verticalOscillationCm: Double? = nil,
        strideLengthMeters: Double? = nil,
        verticalRatio: Double? = nil
    ) {
        self.id = id
        self.date = date
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.workingAvgPaceSecPerKm = workingAvgPaceSecPerKm
        self.workingAvgCadenceSPM = workingAvgCadenceSPM
        self.workingAvgHeartRateBPM = workingAvgHeartRateBPM
        self.percentZone4 = percentZone4
        self.detectedType = detectedType
        self.isPrimer = isPrimer
        self.hadCardiacDrift = hadCardiacDrift
        self.driftBPM = driftBPM
        self.hadCadenceFade = hadCadenceFade
        self.efficiencyFactor = efficiencyFactor
        self.verticalOscillationCm = verticalOscillationCm
        self.strideLengthMeters = strideLengthMeters
        self.verticalRatio = verticalRatio
    }
}

/// Pure athlete context for deterministic session synthesis.
public struct AthleteSynthesisContext: Sendable, Equatable {
    public let activeGoal: String
    public let experienceLevel: String
    public let useMetric: Bool
    public let userHeightCm: Double
    public let now: Date
    public let calendar: Calendar

    public init(
        activeGoal: String = "Base Building",
        experienceLevel: String = "Intermediate",
        useMetric: Bool = true,
        userHeightCm: Double = 175.0,
        now: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) {
        self.activeGoal = activeGoal
        self.experienceLevel = experienceLevel
        self.useMetric = useMetric
        self.userHeightCm = userHeightCm
        self.now = now
        self.calendar = calendar
    }
}

// MARK: - Intensity Zones & Primer Drill Keys

public enum SessionIntensityZone: String, Sendable, Equatable, Codable {
    case rest, zone1Flush, zone2Base, zone3Steady, zone4Tempo, zone5Interval
}

public enum PrimerDrillKey: String, Sendable, Equatable, Codable {
    case cadencePyramids, rhythmIntervals, tempoSurges, strides, recoveryJog, zone2Run

    public init?(identifier: String) {
        let normalized = identifier.lowercased().replacingOccurrences(of: " ", with: "_")
        switch normalized {
        case "cadence_pyramids", "cadencepyramids": self = .cadencePyramids
        case "rhythm_intervals", "rhythmintervals": self = .rhythmIntervals
        case "tempo_surges", "temposurges": self = .tempoSurges
        case "strides": self = .strides
        case "recovery_jog", "recoveryjog": self = .recoveryJog
        case "zone_2_run", "zone2run": self = .zone2Run
        default:
            if let direct = PrimerDrillKey(rawValue: identifier) {
                self = direct
            } else {
                return nil
            }
        }
    }

    public var title: String {
        switch self {
        case .cadencePyramids: return "Cadence Pyramids"
        case .rhythmIntervals: return "Rhythm Intervals"
        case .tempoSurges: return "Tempo Surges"
        case .strides: return "Strides"
        case .recoveryJog: return "Rest & Mobility"
        case .zone2Run: return "Zone 2 Run"
        }
    }
}

// MARK: - Horizon & Session Specs

public struct PlannedSessionSpec: Sendable, Equatable, Codable {
    public let kind: String
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
        kind: String = "run",
        intent: DailySessionIntent = .train,
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
        self.kind = kind
        self.intent = intent
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

public struct SynthesizedHorizonDay: Identifiable, Sendable, Equatable, Codable {
    public let id: String
    public let date: Date
    public let dayLabel: String
    public let sessionTitle: String
    public let iconName: String
    public let isRestDay: Bool
    public let spec: PlannedSessionSpec

    public init(
        id: String,
        date: Date,
        dayLabel: String,
        sessionTitle: String,
        iconName: String,
        isRestDay: Bool,
        spec: PlannedSessionSpec
    ) {
        self.id = id
        self.date = date
        self.dayLabel = dayLabel
        self.sessionTitle = sessionTitle
        self.iconName = iconName
        self.isRestDay = isRestDay
        self.spec = spec
    }
}

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
    case easeUp, onTrack, stepItUp
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

public struct WeekdayTemplateSpec: Sendable, Equatable {
    public let kind: String
    public let title: String
    public let intensityZone: SessionIntensityZone
    public let minutesLow: Int
    public let minutesHigh: Int
    public let primerTitle: String?
    public let iconName: String
}

// MARK: - Core Engine

public enum SessionSynthesisCore {

    public struct RecentLimiterAssessment: Sendable, Equatable {
        public let hadExcessiveBounce: Bool
        public let hadCadenceFade: Bool

        public init(hadExcessiveBounce: Bool, hadCadenceFade: Bool) {
            self.hadExcessiveBounce = hadExcessiveBounce
            self.hadCadenceFade = hadCadenceFade
        }
    }

    public static func detectRecentLimiters(
        verticalRatio: Double?,
        verticalOscillationCm: Double?,
        cadenceSPM: Double,
        cadenceFloor: Int,
        hasCadenceFadeTag: Bool,
        cadenceSlope: Double?,
        splitCadences: [Double]
    ) -> RecentLimiterAssessment {
        let vr = verticalRatio ?? 0.0
        let osc = verticalOscillationCm ?? 0.0
        let subFloor = cadenceSPM > 0 && cadenceSPM < Double(cadenceFloor)
        let hadExcessiveBounce = vr > 9.0 || osc > 10.0 || subFloor

        var hadCadenceFade = hasCadenceFadeTag
        if !hadCadenceFade, let slope = cadenceSlope {
            hadCadenceFade = slope < -0.15
        }
        if !hadCadenceFade, splitCadences.count >= 3 {
            let splitIdx = (splitCadences.count * 2) / 3
            let earlyCount = Double(splitIdx)
            let lateCount = Double(splitCadences.count - splitIdx)
            if earlyCount > 0 && lateCount > 0 {
                let early = splitCadences[0..<splitIdx].reduce(0, +) / earlyCount
                let late = splitCadences[splitIdx...].reduce(0, +) / lateCount
                if (early - late) >= 5.0 {
                    hadCadenceFade = true
                }
            }
        }
        return RecentLimiterAssessment(hadExcessiveBounce: hadExcessiveBounce, hadCadenceFade: hadCadenceFade)
    }

    public static func heightAdjustedCadenceFloor(heightCm: Double) -> Int {
        let clamped = max(130.0, min(220.0, heightCm))
        return Int((150.0 / (clamped / 175.0)).rounded())
    }

    public static func heightAdjustedMaxOscillation(heightCm: Double) -> Double {
        let clamped = max(130.0, min(220.0, heightCm))
        return 9.5 * (clamped / 175.0)
    }

    public static func isWorkoutDayComplete(runs: [SynthesisRunSample]) -> Bool {
        guard !runs.isEmpty else { return false }
        let hasMain = runs.contains { !$0.isPrimer && $0.durationSeconds >= 1200 }
        let total = runs.reduce(0.0) { $0 + $1.durationSeconds }
        return hasMain || total >= 1800
    }

    public static func targetCadenceBand(for primer: PrimerDrillKey, isAcuteFatigue: Bool, isDeload: Bool, baseCadence: Int) -> String {
        if isAcuteFatigue { return "\(baseCadence - 1)–\(baseCadence + 5) SPM" }
        if isDeload { return "\(baseCadence + 10)–\(baseCadence + 18) SPM" }
        switch primer {
        case .cadencePyramids: return "\(baseCadence + 4)–\(baseCadence + 10) SPM"
        case .rhythmIntervals, .tempoSurges: return "\(baseCadence + 6)–\(baseCadence + 12) SPM"
        case .strides: return "\(baseCadence + 8)–\(baseCadence + 14) SPM"
        default: return "\(baseCadence + 4)–\(baseCadence + 10) SPM"
        }
    }

    public static func computeWeightedBaselineStats(
        from runs: [SynthesisRunSample],
        priorTo date: Date,
        calendar: Calendar? = nil
    ) -> WeightedBaselineStats? {
        let cal = calendar ?? Calendar(identifier: .gregorian)
        let thirtyDaysAgo = cal.date(byAdding: .day, value: -30, to: date) ?? date.addingTimeInterval(-30 * 86400)
        let valid = runs.filter {
            $0.workingAvgPaceSecPerKm > 0 && $0.durationSeconds > 0 &&
            $0.date < date && $0.date >= thirtyDaysAgo
        }
        guard !valid.isEmpty else { return nil }

        func aerobicWeight(for r: SynthesisRunSample) -> Double {
            if valid.count < 3 { return 1.0 * r.durationSeconds }
            switch r.detectedType {
            case "Steady Effort", "Easy Run", "Long Run": return 1.0 * r.durationSeconds
            case "Tempo Run", "Progression Run", "Recovery Run": return 0.8 * r.durationSeconds
            case "Intervals", "Pyramids", "Fartlek": return 0.3 * r.durationSeconds
            default: return 0.7 * r.durationSeconds
            }
        }

        let totalWeight = valid.map { aerobicWeight(for: $0) }.reduce(0, +)
        guard totalWeight > 0 else { return nil }

        let pace = valid.map { $0.workingAvgPaceSecPerKm * aerobicWeight(for: $0) }.reduce(0, +) / totalWeight
        let cadRuns = valid.filter { $0.workingAvgCadenceSPM > 0 }
        let cadWeight = cadRuns.map { aerobicWeight(for: $0) }.reduce(0, +)
        let cad = cadWeight > 0 ? (cadRuns.map { $0.workingAvgCadenceSPM * aerobicWeight(for: $0) }.reduce(0, +) / cadWeight) : 155.0

        let hrRuns = valid.filter { $0.workingAvgHeartRateBPM > 0 }
        let hrWeight = hrRuns.map { aerobicWeight(for: $0) }.reduce(0, +)
        let hr = hrWeight > 0 ? (hrRuns.map { $0.workingAvgHeartRateBPM * aerobicWeight(for: $0) }.reduce(0, +) / hrWeight) : 0.0

        let oscRuns = valid.compactMap { r -> (Double, Double)? in
            guard let v = r.verticalOscillationCm, v > 0 else { return nil }
            return (v, aerobicWeight(for: r))
        }
        let oscWeight = oscRuns.map(\.1).reduce(0, +)
        let osc = oscWeight > 0 ? (oscRuns.map { $0.0 * $0.1 }.reduce(0, +) / oscWeight) : nil

        let strideRuns = valid.compactMap { r -> (Double, Double)? in
            guard let v = r.strideLengthMeters, v > 0 else { return nil }
            return (v, aerobicWeight(for: r))
        }
        let strideWeight = strideRuns.map(\.1).reduce(0, +)
        let stride = strideWeight > 0 ? (strideRuns.map { $0.0 * $0.1 }.reduce(0, +) / strideWeight) : nil

        let vrRuns = valid.compactMap { r -> (Double, Double)? in
            guard let v = r.verticalRatio, v > 0 else { return nil }
            return (v, aerobicWeight(for: r))
        }
        let vrWeight = vrRuns.map(\.1).reduce(0, +)
        let vr = vrWeight > 0 ? (vrRuns.map { $0.0 * $0.1 }.reduce(0, +) / vrWeight) : nil

        return WeightedBaselineStats(avgPace: pace, avgCadence: cad, avgHR: hr, avgOscillation: osc, avgStrideLength: stride, avgVerticalRatio: vr)
    }

    public static func computeWeightedBaseline(
        from runs: [SynthesisRunSample],
        priorTo date: Date,
        calendar: Calendar? = nil
    ) -> (pace: Double, cadence: Int) {
        if let stats = computeWeightedBaselineStats(from: runs, priorTo: date, calendar: calendar) {
            return (stats.avgPace, Int(stats.avgCadence.rounded()))
        }
        let fallback = runs.filter { $0.workingAvgPaceSecPerKm > 0 && $0.date < date }
        let pace = fallback.isEmpty ? 340.0 : (fallback.prefix(10).map(\.workingAvgPaceSecPerKm).reduce(0, +) / Double(min(10, fallback.count)))
        let cad = fallback.isEmpty ? 155 : Int(fallback.prefix(10).map(\.workingAvgCadenceSPM).reduce(0, +) / Double(min(10, fallback.count)))
        return (pace, cad)
    }

    public static func evaluate30DayTrajectory(
        from runs: [SynthesisRunSample],
        now: Date,
        calendar: Calendar? = nil
    ) -> TrajectoryAssessment {
        let cal = calendar ?? Calendar(identifier: .gregorian)
        let thirtyDaysAgo = cal.date(byAdding: .day, value: -30, to: now) ?? now.addingTimeInterval(-30 * 86400)
        let valid = runs.filter {
            $0.date >= thirtyDaysAgo && $0.date <= now &&
            $0.workingAvgPaceSecPerKm > 0 && $0.workingAvgHeartRateBPM > 0
        }
        let midDate = cal.date(byAdding: .day, value: -15, to: now) ?? now.addingTimeInterval(-15 * 86400)
        let recent = valid.filter { $0.date >= midDate }
        let older = valid.filter { $0.date < midDate }

        let rEF = recent.compactMap(\.efficiencyFactor)
        let oEF = older.compactMap(\.efficiencyFactor)
        let avgREF = rEF.isEmpty ? 0.0 : (rEF.reduce(0, +) / Double(rEF.count))
        let avgOEF = oEF.isEmpty ? 0.0 : (oEF.reduce(0, +) / Double(oEF.count))
        let efDelta = (avgREF > 0 && avgOEF > 0) ? (avgREF - avgOEF) : 0.0

        let rOsc = recent.compactMap(\.verticalOscillationCm)
        let oOsc = older.compactMap(\.verticalOscillationCm)
        let avgROsc = rOsc.isEmpty ? 0.0 : (rOsc.reduce(0, +) / Double(rOsc.count))
        let avgOOsc = oOsc.isEmpty ? 0.0 : (oOsc.reduce(0, +) / Double(oOsc.count))
        let oscDelta = (avgROsc > 0 && avgOOsc > 0) ? (avgROsc - avgOOsc) : 0.0

        let rVR = recent.compactMap(\.verticalRatio)
        let oVR = older.compactMap(\.verticalRatio)
        let avgRVR = rVR.isEmpty ? 0.0 : (rVR.reduce(0, +) / Double(rVR.count))
        let avgOVR = oVR.isEmpty ? 0.0 : (oVR.reduce(0, +) / Double(oVR.count))
        let vrDelta = (avgRVR > 0 && avgOVR > 0) ? (avgRVR - avgOVR) : 0.0

        let rHR = recent.map(\.workingAvgHeartRateBPM).reduce(0, +) / Double(max(1, recent.count))
        let oHR = older.map(\.workingAvgHeartRateBPM).reduce(0, +) / Double(max(1, older.count))
        let hrDelta = (rHR > 0 && oHR > 0) ? (rHR - oHR) : 0.0

        let verdict: TrajectoryVerdict
        if (efDelta <= -0.02 && oEF.count >= 2) || (hrDelta >= 3.0 && oHR > 0) {
            verdict = .easeUp
        } else if efDelta > 0.02 || hrDelta < -2.0 || oscDelta < -0.2 || vrDelta < -0.3 {
            verdict = .onTrack
        } else {
            verdict = .stepItUp
        }

        return TrajectoryAssessment(
            verdict: verdict, efDelta: efDelta, hrDelta: hrDelta, oscDelta: oscDelta,
            vrDelta: vrDelta, avgRecentEF: avgREF, avgRecentOsc: avgROsc, avgRecentVR: avgRVR
        )
    }

    public static func aerobicDurationForExperience(_ level: String) -> (band: String, minutes: Int) {
        if level.contains("Novice") { return ("25–35 Min", 30) }
        if level.contains("Advanced") || level.contains("Competitive") || level.contains("Elite") { return ("45–60 Min", 50) }
        return ("35–45 Min", 40)
    }

    public static func resolvePaceBand(for zone: SessionIntensityZone, matrix: TrainingZoneMatrix, useMetric: Bool) -> String? {
        switch zone {
        case .rest: return nil
        case .zone1Flush: return matrix.zone1Recovery.formatted(useMetric: useMetric)
        case .zone2Base: return matrix.zone2AerobicBase.formatted(useMetric: useMetric)
        case .zone3Steady: return matrix.zone3Steady.formatted(useMetric: useMetric)
        case .zone4Tempo: return matrix.zone4Threshold.formatted(useMetric: useMetric)
        case .zone5Interval: return matrix.zone5Interval.formatted(useMetric: useMetric)
        }
    }
}
