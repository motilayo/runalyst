import Foundation
import SwiftData

/// Represents a historical running workout extracted from Apple HealthKit.
/// Persisted locally via SwiftData.
@Model
final class RunRecord {
    /// A unique identifier for the run record in SwiftData.
    @Attribute(.unique) var id: UUID

    /// The original HKWorkout UUID from HealthKit.
    var hkWorkoutID: UUID

    /// The start date and time of the run.
    var date: Date

    /// The total distance covered during the run, stored in meters.
    var totalDistanceMeters: Double

    /// The total duration of the run, stored in seconds.
    var duration: TimeInterval

    // MARK: - Raw Metrics (from Apple Health)
    /// Raw average pace (seconds/km)
    var rawAvgPace: Double
    /// Raw average heart rate (BPM)
    var rawAvgHeartRate: Double
    /// Raw average cadence (SPM)
    var rawAvgCadence: Double

    // MARK: - Framboise Working Metrics
    /// True working distance excluding dead stops (meters)
    var workingDistanceMeters: Double?
    /// True working duration excluding dead stops (seconds)
    var workingDurationSeconds: Double?
    /// Whether the workout was performed indoors (e.g., treadmill)
    var isIndoor: Bool?
    /// True working average pace, excluding dead stops (seconds/km)
    var workingAvgPace: Double
    /// True working average cadence (SPM)
    var workingAvgCadence: Double
    /// True working average heart rate (BPM)
    var workingAvgHeartRate: Double
    /// True working average vertical oscillation (cm)
    var workingAvgVerticalOscillation: Double?
    /// Raw average vertical oscillation (cm)
    var rawAvgVerticalOscillation: Double?

    // MARK: - Biomechanical Stride Metrics (meters)
    /// Raw average stride length (meters)
    var rawAvgStrideLength: Double?
    /// True working average stride length, excluding dead stops (meters)
    var workingAvgStrideLength: Double?

    /// Computed Vertical Ratio (percentage of vertical bounce relative to forward stride)
    var verticalRatio: Double? {
        guard let stride = workingAvgStrideLength ?? rawAvgStrideLength, stride >= 0.3,
              let oscCm = workingAvgVerticalOscillation ?? rawAvgVerticalOscillation, oscCm > 0 else {
            return nil
        }
        return oscCm / stride
    }

    var effectiveWorkingDistanceMeters: Double {
        workingDistanceMeters ?? totalDistanceMeters
    }

    var effectiveWorkingDurationSeconds: Double {
        workingDurationSeconds ?? duration
    }

    /// Speed in meters per minute (derived from working average pace).
    var speedMetersPerMinute: Double? {
        guard workingAvgPace > 0 else { return nil }
        return 60_000.0 / workingAvgPace
    }

    /// Efficiency Factor: Speed (meters/minute) divided by Heart Rate (BPM).
    /// Represents running economy: distance in meters traveled per heartbeat.
    var efficiencyFactor: Double? {
        guard workingAvgHeartRate > 0, let speed = speedMetersPerMinute else { return nil }
        return speed / workingAvgHeartRate
    }

    /// Evaluates whether active running heart rate is implausibly low (e.g. < 85 BPM during active running > 5 min).
    var isHeartRateSensorLowConfidence: Bool {
        guard duration >= 300.0, workingAvgPace > 0, workingAvgPace <= 540.0 else { return false }
        return workingAvgHeartRate > 0 && workingAvgHeartRate < 85.0
    }

    // MARK: - Framboise Mathematical Features
    /// Coefficient of variation for pace (sigma / mu)
    var paceCV: Double
    /// Linear regression slope of pace over time
    var paceSlope: Double
    /// Fraction of time spent in Zone 4
    var percentZone4: Double

    // MARK: - Indoor & Ingestion Source
    /// Source of the run telemetry ("wrist", "gymkit", "footpod")
    var dataSourceRaw: String?

    /// Confidence score from ML classifier (0.0 to 1.0)
    var classificationConfidence: Double?

    /// Encoded dictionary of classification probabilities [String: Double]
    var classificationProbabilitiesData: Data?

    /// Coefficient of variation for heart rate (sigma / mu)
    var hrCV: Double?

    /// Linear regression slope of cadence over time
    var cadenceSlope: Double?

    /// Whether the run was flagged for potential incline/hill intervals requiring user confirmation
    var needsInclineReview: Bool?

    /// Persisted RunSignature for RAG coaching and variance map visualization
    var runSignatureData: Data?

    // MARK: - Environmental & Ambient Metrics
    /// Ambient temperature in Celsius at start of run (from HealthKit metadata or WeatherKit)
    var ambientTemperatureCelsius: Double?
    /// Relative humidity as a fraction (0.0–1.0) or percentage (from HealthKit metadata or WeatherKit)
    var ambientHumidity: Double?

    // MARK: - Classification & Tags
    /// The deterministic or CoreML predicted run type
    var detectedTypeRaw: String
    /// Epistemic provenance of the classification (.deterministic, .inferred, .needsReview, .userConfirmed)
    var classificationProvenanceRaw: String?
    /// Tags generated by the Framboise engine (e.g., urbanTraffic, fatigue Drift)
    var framboiseTags: [String]

    /// Epistemic provenance as a strongly typed enum.
    var classificationProvenance: ClassificationProvenance? {
        get {
            guard let raw = classificationProvenanceRaw else { return nil }
            return ClassificationProvenance(rawValue: raw)
        }
        set {
            classificationProvenanceRaw = newValue?.rawValue
        }
    }

    /// Whether this workout actively requires human review.
    /// In accordance with Automata Theory, `.userConfirmed` and `.deterministic` are absorbing states.
    var needsClassificationReview: Bool {
        if let prov = classificationProvenance {
            switch prov {
            case .userConfirmed, .deterministic:
                return false
            case .needsReview:
                return true
            case .inferred:
                return detectedTypeRaw == "Mixed Effort (Review)" || (classificationConfidence ?? 1.0) < 0.75
            }
        }
        // Fallback for legacy records ingested before provenance tracking:
        if framboiseTags.contains("userConfirmedClassification") {
            return false
        }
        return detectedTypeRaw == "Mixed Effort (Review)" || (classificationConfidence ?? 1.0) < 0.75
    }

    // MARK: - AI Coaching
    /// A one-to-one relationship to the AI-generated coaching insight.
    /// Retained from v1.1 for structured drill display in V2 UI.
    @Relationship(deleteRule: .cascade, inverse: \CoachingInsight.runRecord)
    var insight: CoachingInsight?

    var classificationProbabilities: [String: Double]? {
        get {
            guard let data = classificationProbabilitiesData else { return nil }
            return try? JSONDecoder().decode([String: Double].self, from: data)
        }
        set {
            classificationProbabilitiesData = try? JSONEncoder().encode(newValue)
        }
    }

    var signature: RunSignature? {
        get {
            guard let data = runSignatureData else { return nil }
            return try? JSONDecoder().decode(RunSignature.self, from: data)
        }
        set {
            runSignatureData = try? JSONEncoder().encode(newValue)
        }
    }

    var splits: [RunSplit] {
        signature?.splits ?? []
    }

    init(
        id: UUID = UUID(),
        hkWorkoutID: UUID,
        date: Date,
        totalDistanceMeters: Double,
        duration: TimeInterval,
        rawAvgPace: Double,
        rawAvgHeartRate: Double,
        rawAvgCadence: Double,
        workingAvgPace: Double,
        workingAvgCadence: Double,
        workingAvgHeartRate: Double,
        workingAvgVerticalOscillation: Double? = nil,
        rawAvgVerticalOscillation: Double? = nil,
        rawAvgStrideLength: Double? = nil,
        workingAvgStrideLength: Double? = nil,
        workingDistanceMeters: Double? = nil,
        workingDurationSeconds: TimeInterval? = nil,
        isIndoor: Bool? = nil,
        paceCV: Double,
        paceSlope: Double,
        percentZone4: Double,
        detectedTypeRaw: String,
        framboiseTags: [String] = [],
        insight: CoachingInsight? = nil,
        dataSourceRaw: String? = nil,
        classificationConfidence: Double? = nil,
        classificationProbabilitiesData: Data? = nil,
        hrCV: Double? = nil,
        cadenceSlope: Double? = nil,
        needsInclineReview: Bool? = nil,
        runSignatureData: Data? = nil,
        ambientTemperatureCelsius: Double? = nil,
        ambientHumidity: Double? = nil,
        classificationProvenanceRaw: String? = nil
    ) {
        self.id = id
        self.hkWorkoutID = hkWorkoutID
        self.date = date
        self.totalDistanceMeters = totalDistanceMeters
        self.duration = duration
        self.rawAvgPace = rawAvgPace
        self.rawAvgHeartRate = rawAvgHeartRate
        self.rawAvgCadence = rawAvgCadence
        self.workingAvgPace = workingAvgPace
        self.workingAvgCadence = workingAvgCadence
        self.workingAvgHeartRate = workingAvgHeartRate
        self.workingAvgVerticalOscillation = workingAvgVerticalOscillation
        self.rawAvgVerticalOscillation = rawAvgVerticalOscillation
        self.rawAvgStrideLength = rawAvgStrideLength
        self.workingAvgStrideLength = workingAvgStrideLength
        self.workingDistanceMeters = workingDistanceMeters
        self.workingDurationSeconds = workingDurationSeconds
        self.isIndoor = isIndoor
        self.dataSourceRaw = dataSourceRaw
        self.classificationConfidence = classificationConfidence
        self.classificationProbabilitiesData = classificationProbabilitiesData
        self.classificationProvenanceRaw = classificationProvenanceRaw
        self.hrCV = hrCV
        self.cadenceSlope = cadenceSlope
        self.needsInclineReview = needsInclineReview
        self.runSignatureData = runSignatureData
        self.ambientTemperatureCelsius = ambientTemperatureCelsius
        self.ambientHumidity = ambientHumidity
        self.paceCV = paceCV
        self.paceSlope = paceSlope
        self.percentZone4 = percentZone4
        self.detectedTypeRaw = detectedTypeRaw
        self.framboiseTags = framboiseTags
        self.insight = insight
    }
}

extension RunRecord {
    /// Computes the duration-weighted 30-day baseline cadence strictly prior to this run's date from a collection of runs.
    func computeHistoricalBaselineCadence(in runs: [RunRecord]) -> Double? {
        SessionSynthesisEngine.computeWeightedBaselineStats(from: runs, priorTo: self.date)?.avgCadence
    }

    /// Computes the duration-weighted 30-day baseline cadence strictly prior to this run's date using its SwiftData ModelContext.
    func computeHistoricalBaselineCadence() -> Double? {
        guard let context = self.modelContext else { return nil }
        let runDate = self.date
        guard let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: runDate) else { return nil }
        let descriptor = FetchDescriptor<RunRecord>(
            predicate: #Predicate<RunRecord> {
                $0.date < runDate && $0.date >= thirtyDaysAgo
            }
        )
        guard let priorRuns = try? context.fetch(descriptor) else { return nil }
        return computeHistoricalBaselineCadence(in: priorRuns)
    }

    /// Whether this workout is a short pre-run primer or technique drill rather than a main training session.
    var isPrimerWorkout: Bool {
        guard duration <= 1200 else { return false } // <= 20 min
        if let drillName = prescribedDrillName,
           let drillId = PreRunDrillId.resolve(from: drillName),
           !drillId.isAerobicContinuous {
            return true
        }
        if framboiseTags.contains("prescribedDrill") {
            return true
        }
        return duration <= 960 && totalDistanceMeters < 2500
    }

    /// Canonical user-facing drill title associated with this run, if any (e.g. "Tempo Surges", "Cadence Pyramids").
    var prescribedDrillName: String? {
        guard !isDeleted else { return nil }
        guard !framboiseTags.contains("userUnlinkedDrill") else { return nil }

        // Long full-distance runs (> 25 min and > 4 km) that were not explicitly linked by the user
        // should never be relabeled as short pre-run primer drills.
        let isUnlinkedLongRun = duration > 1500 && totalDistanceMeters > 4000 && !framboiseTags.contains("userLinkedDrill")

        func validatedDrillTitle(_ title: String) -> String? {
            guard let resolved = PreRunDrillId.resolve(from: title) else {
                return nil
            }
            // Continuous aerobic workouts (Zone 2 Run, Aerobic Flush, Recovery Jog) are main workouts,
            // not technique primer drills. Drill must remain blank unless a technique drill is explicitly linked.
            if resolved.isAerobicContinuous {
                return nil
            }
            if isUnlinkedLongRun {
                return nil
            }
            return resolved.title
        }

        // 1. Explicit tag "drill:<title>"
        if let tag = framboiseTags.first(where: { $0.hasPrefix("drill:") }) {
            let candidate = String(tag.dropFirst(6))
            if let canonical = PreRunDrillId.canonicalDrillTitle(for: candidate) {
                return validatedDrillTitle(canonical)
            }
            return validatedDrillTitle(candidate.replacingOccurrences(of: "_", with: " ").capitalized)
        }
        // 2. PreRunDrillId rawValue in framboiseTags
        if let drill = PreRunDrillId.techniqueDrills.first(where: { framboiseTags.contains($0.rawValue) }) {
            return validatedDrillTitle(drill.title)
        }
        // 3. PreRunDrillId title in framboiseTags
        if let drill = PreRunDrillId.techniqueDrills.first(where: { framboiseTags.contains($0.title) }) {
            return validatedDrillTitle(drill.title)
        }
        // 4. If detectedTypeRaw is itself a specific drill title (e.g. "Rhythm Intervals")
        if let canonical = PreRunDrillId.canonicalDrillTitle(for: detectedTypeRaw) {
            return validatedDrillTitle(canonical)
        }
        return nil
    }

    /// Resolves the prescribed target cadence band for this run, accounting for explicit drillTarget tags,
    /// scheduled drill intents, and readiness/cardiac-drift adaptations active at the time of the workout.
    @MainActor
    func effectivePrescribedTargetCadence(drillId: PreRunDrillId, baselineCadence: Int) -> String? {
        guard !drillId.isHeartRateTargeted && !drillId.isAerobicContinuous else { return nil }

        // 1. Explicit persisted target tag on the run
        if let tag = framboiseTags.first(where: { $0.hasPrefix("drillTarget:") }) {
            let raw = String(tag.dropFirst("drillTarget:".count))
            let clean = PreRunDrill.normalizeCadenceTargetString(raw)
            if !clean.isEmpty {
                return clean
            }
        }

        // 2. Recent scheduled drill intent matching this workout
        let intents = WorkoutBridge.recentIntents()
        if let matchedIntent = intents.first(where: { intent in
            if intent.matchedWorkoutID == self.hkWorkoutID { return true }
            let diff = abs(self.date.timeIntervalSince(intent.scheduledDate))
            let sameDrill = intent.preRunDrillId == drillId.rawValue || intent.drillTitle == drillId.title
            return sameDrill && diff <= 12 * 3600
        }), let intentTarget = matchedIntent.targetCadence {
            let clean = PreRunDrill.normalizeCadenceTargetString(intentTarget)
            if !clean.isEmpty,
               intentTarget.localizedCaseInsensitiveContains("adapted") ||
               clean != DrillTemplate.template(for: drillId).calculateTargetCadence(baselineCadence) {
                return clean
            }
        }

        // 3. Evaluate readiness and prior-run cardiac drift at the time of this workout
        if let context = self.modelContext {
            let runDate = self.date
            let descriptor = FetchDescriptor<RunRecord>(
                predicate: #Predicate<RunRecord> { $0.date < runDate },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            if let priorRuns = try? context.fetch(descriptor), !priorRuns.isEmpty {
                let readiness = ReadinessEvaluator.assess(runRecords: priorRuns, now: runDate)
                let validPrior = priorRuns.filter { !$0.isDeleted && $0.workingAvgPace > 0 }
                let sessionBaseCadence = validPrior.isEmpty
                    ? baselineCadence
                    : Int(validPrior.prefix(10).map(\.workingAvgCadence).reduce(0, +) / Double(min(10, validPrior.count)))

                var hadCardiacDrift = readiness.triggers.contains(.cardiacDrift)
                if let recent = priorRuns.first(where: { !$0.isDeleted }) {
                    if recent.framboiseTags.contains("cardiacDrift") || recent.framboiseTags.contains("fatigueDrift") {
                        hadCardiacDrift = true
                    } else {
                        let analysisContext = WorkoutAnalysisContext(
                            runRecord: recent,
                            runSignature: recent.signature,
                            macroProfile: nil,
                            recoveryTimeline: RecoveryTimeline(now: runDate, lastHard: nil, hardSessionsLast72h: 0, requiredHours: 24, state: .productive)
                        )
                        if analysisContext.hasCardiacDrift {
                            hadCardiacDrift = true
                        }
                    }
                }

                if readiness.state == .acuteFatigue || hadCardiacDrift {
                    if drillId == .cadencePyramids {
                        return "\(sessionBaseCadence - 1)-\(sessionBaseCadence + 5)"
                    }
                    let standard = DrillTemplate.template(for: drillId).calculateTargetCadence(baselineCadence)
                    return ReadinessModifier.adaptTarget(
                        standard,
                        baselineCadence: baselineCadence,
                        drillId: drillId,
                        state: .acuteFatigue
                    ).targetCadence
                } else if readiness.state == .deload && drillId == .strides {
                    return "\(sessionBaseCadence + 10)-\(sessionBaseCadence + 18)"
                }
            }
        }

        return DrillTemplate.template(for: drillId).calculateTargetCadence(baselineCadence)
    }

    /// Canonical user-facing run classification (e.g. "Steady Effort", "Easy Run", "Intervals").
    var normalizedClassification: String {
        guard !isDeleted else { return "Steady Effort" }
        // If an unlinked long run (> 25 min and > 4 km) previously had a false-positive primer tag
        // that overwrote detectedTypeRaw to "Intervals", restore its native signature classification (e.g. "Fartlek").
        let hasDrillTag = framboiseTags.contains("prescribedDrill") || framboiseTags.contains(where: { $0.hasPrefix("drill:") })
        if duration > 1500 && totalDistanceMeters > 4000 && !framboiseTags.contains("userLinkedDrill"),
           prescribedDrillName == nil,
           hasDrillTag,
           let sigClass = signature?.classification.trimmingCharacters(in: .whitespacesAndNewlines),
           !sigClass.isEmpty {
            return sigClass
        }

        let trimmed = detectedTypeRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.localizedCaseInsensitiveCompare("steady") == .orderedSame {
            return "Steady Effort"
        }
        if let parentClassification = PreRunDrillId.correspondingClassification(for: trimmed) {
            return parentClassification
        }
        if let canonical = PreRunDrillId.canonicalDrillTitle(for: trimmed),
           let parent = PreRunDrillId.correspondingClassification(for: canonical) {
            return parent
        }
        return trimmed
    }

    /// Evaluation modality derived from the canonical run classification.
    var evaluationModality: WorkoutEvaluationModality {
        let norm = normalizedClassification
        let intervalClassifications: Set<String> = ["Intervals", "Pyramids", "Fartlek", "Hill Repeats"]
        if intervalClassifications.contains(norm) {
            return .intervals
        }
        if norm.localizedCaseInsensitiveContains("easy") || norm.localizedCaseInsensitiveContains("recovery") || norm.localizedCaseInsensitiveContains("zone 2") {
            return .aerobicBase
        }
        if norm.localizedCaseInsensitiveContains("progression") {
            return .progression
        }
        return .steadySplits
    }

    /// Checks if this run matches the provided filter chip (either canonical classification or drill name).
    func matchesFilter(_ filter: String) -> Bool {
        guard !isDeleted else { return false }
        let cleanFilter = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedClassification.localizedCaseInsensitiveCompare(cleanFilter) == .orderedSame {
            return true
        }
        if let drill = prescribedDrillName, drill.localizedCaseInsensitiveCompare(cleanFilter) == .orderedSame {
            return true
        }
        if detectedTypeRaw.localizedCaseInsensitiveCompare(cleanFilter) == .orderedSame {
            return true
        }
        return false
    }
}
