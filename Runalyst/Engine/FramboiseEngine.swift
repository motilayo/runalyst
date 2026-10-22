import Foundation
import RunalystCore

/// The hollow iOS adapter for Runalyst telemetry analysis.
/// Acts strictly as an infrastructure perimeter: maps iOS domain types to pure RunalystCore ingots,
/// delegates all sports science and biomechanical mathematics to RunalystCore, and returns results.
actor FramboiseEngine {

    // MARK: - Dead Stop & Walking Filter

    /// Filters out stationary time, traffic stops, and walking breaks.
    func filterRunningSamples(buckets: [BucketData]) -> [BucketData] {
        let telemetry = buckets.map { $0.toTelemetryBucket() }
        let filtered = FramboiseCore.filterRunningSamples(buckets: telemetry)
        return filtered.map(BucketData.init(from:))
    }

    /// Alias for filterRunningSamples to maintain backward compatibility with callers.
    func trimDeadStops(buckets: [BucketData]) -> [BucketData] {
        filterRunningSamples(buckets: buckets)
    }

    // MARK: - Working Averages & Aggregate Pace

    /// Calculates true working averages by delegating to FramboiseCore.
    func calculateWorkingAverages(
        trimmed: [BucketData],
        rawWorkoutDuration: Double? = nil,
        rawWorkoutDistance: Double? = nil,
        originalBucketCount: Int? = nil,
        rawAvgStrideLength: Double? = nil
    ) -> (
        workingPace: Double,
        workingCadence: Double,
        workingHR: Double,
        workingOscillation: Double,
        workingDistance: Double,
        workingDuration: Double,
        workingStrideLength: Double?
    ) {
        let coreTrimmed = trimmed.map { $0.toTelemetryBucket() }
        let result = FramboiseCore.calculateWorkingAverages(
            trimmed: coreTrimmed,
            rawWorkoutDuration: rawWorkoutDuration,
            rawWorkoutDistance: rawWorkoutDistance,
            originalBucketCount: originalBucketCount,
            rawAvgStrideLength: rawAvgStrideLength
        )
        return (
            workingPace: result.workingPace,
            workingCadence: result.workingCadence,
            workingHR: result.workingHR,
            workingOscillation: result.workingOscillation ?? 0.0,
            workingDistance: result.workingDistance,
            workingDuration: result.workingDuration,
            workingStrideLength: result.workingStrideLength
        )
    }

    // MARK: - Mathematical Features

    /// Calculates the Coefficient of Variation for pace across buckets.
    func calculatePaceCV(bucketPaces: [Double]) -> Double {
        FramboiseCore.calculatePaceCV(bucketPaces: bucketPaces)
    }

    /// Calculates the Coefficient of Variation for cadence across buckets.
    func calculateCadenceCV(bucketCadences: [Double]) -> Double {
        FramboiseCore.calculateCadenceCV(bucketCadences: bucketCadences)
    }

    /// Calculates the linear regression slope of pace over time (least-squares).
    func calculatePaceSlope(bucketPaces: [Double]) -> Double {
        FramboiseCore.calculatePaceSlope(bucketPaces: bucketPaces)
    }

    /// Calculates the linear regression slope of cadence over time (least-squares).
    func calculateCadenceSlope(bucketCadences: [Double]) -> Double {
        FramboiseCore.calculateCadenceSlope(bucketCadences: bucketCadences)
    }

    /// Calculates the Coefficient of Variation for heart rate across buckets.
    func calculateHRCV(bucketHRs: [Double]) -> Double {
        FramboiseCore.calculateHRCV(bucketHRs: bucketHRs)
    }

    /// Defensive treadmill heuristics for wrist accelerometer pace smoothing.
    func applyIndoorWristPaceSmoothing(buckets: [BucketData]) -> [BucketData] {
        let telemetry = buckets.map { $0.toTelemetryBucket() }
        let smoothed = TreadmillKinematicsCore.applyWristPaceSmoothing(buckets: telemetry)
        return smoothed.map(BucketData.init(from:))
    }

    /// Segments continuous buckets into Work, Recovery, Steady, or Walking windows.
    func generatePhaseSegments(from buckets: [BucketData], cadenceFloor: Double = 150.0) -> [PhaseSegment] {
        let telemetry = buckets.map { $0.toTelemetryBucket() }
        let segments = IntervalSegmenterCore.segmentPhases(buckets: telemetry, cadenceFloor: cadenceFloor)
        return segments.map(PhaseSegment.init(from:))
    }

    /// Merges fragmented work segments separated by brief dips and filters out stray warmup/cooldown surges.
    static func consolidatePhaseSegments(_ segments: [PhaseSegment]) -> [PhaseSegment] {
        let coreSegments = segments.map { $0.toIntervalPhaseSegment() }
        let consolidated = IntervalSegmenterCore.consolidatePhaseSegments(coreSegments)
        return consolidated.map(PhaseSegment.init(from:))
    }

    /// Merges two phase segments.
    static func mergeSegments(_ a: PhaseSegment, _ b: PhaseSegment) -> PhaseSegment {
        let coreA = a.toIntervalPhaseSegment()
        let coreB = b.toIntervalPhaseSegment()
        let merged = IntervalSegmenterCore.mergeSegments(coreA, coreB)
        return PhaseSegment(from: merged)
    }

    /// Calculates the fraction of time spent in Zone 4 (or higher).
    func calculatePercentZone4(bucketHRs: [Double], maxHR: Double) -> Double {
        FramboiseCore.calculatePercentZone4(bucketHRs: bucketHRs, maxHR: maxHR)
    }

    // MARK: - Classification & Oscillations

    /// Smooths the cadence time series using sliding window average.
    func smoothCadences(buckets: [BucketData]) -> [Double] {
        IntervalSegmenterCore.smoothCadences(buckets: buckets.map { $0.toTelemetryBucket() })
    }

    /// Extracts corroborated surge-and-recovery oscillation cycles from the bucket time series.
    func extractOscillationCycles(buckets: [BucketData]) -> [SurgeRecoveryCycle] {
        let telemetry = buckets.map { $0.toTelemetryBucket() }
        let cycles = IntervalSegmenterCore.extractOscillationCycles(buckets: telemetry)
        return cycles.map(SurgeRecoveryCycle.init(from:))
    }

    /// Evaluates the regularity of work and recovery durations across validated oscillation cycles.
    func calculateCycleRegularity(cycles: [SurgeRecoveryCycle]) -> Double {
        IntervalSegmenterCore.calculateCycleRegularity(cycles: cycles.map { $0.toIntervalOscillationCycle() })
    }

    /// Evaluates whether the run exhibits monotonic quintile progression.
    func evaluateQuintileProgression(buckets: [BucketData]) -> Bool {
        IntervalSegmenterCore.evaluateQuintileProgression(buckets: buckets.map { $0.toTelemetryBucket() })
    }

    /// Calculates the mean cadence of the slowest 20% pace buckets or recovery phases.
    func calculateRecoveryCadenceFloor(buckets: [BucketData], cycles: [SurgeRecoveryCycle] = []) -> Double {
        let telemetry = buckets.map { $0.toTelemetryBucket() }
        let coreCycles = cycles.map { $0.toIntervalOscillationCycle() }
        return RunClassifierCore.calculateRecoveryCadenceFloor(buckets: telemetry, cycles: coreCycles)
    }

    /// Evaluates the duration symmetry of intermittent work intervals.
    func calculateWorkBlockSymmetry(cycles: [SurgeRecoveryCycle]) -> Double {
        RunClassifierCore.calculateWorkBlockSymmetry(cycles: cycles.map { $0.toIntervalOscillationCycle() })
    }

    /// Evaluates non-periodic cadence crashes and pace dropouts characteristic of city running.
    func detectUrbanTrafficEntropy(buckets: [BucketData]) -> Double {
        RunClassifierCore.detectUrbanTrafficEntropy(buckets: buckets.map { $0.toTelemetryBucket() })
    }

    /// Detects repeated saw-tooth elevation climbs synchronized with cardiac surges.
    func detectHillRepeats(buckets: [BucketData]) -> Bool {
        RunClassifierCore.detectHillRepeats(buckets: buckets.map { $0.toTelemetryBucket() })
    }

    /// Multi-delta weighted classification engine delegating directly to RunClassifierCore.
    func classifyRun(
        buckets: [BucketData],
        cv: Double,
        slope: Double,
        zone4: Double,
        durationMinutes: Double,
        cadenceCV: Double = 0.0,
        averageHR: Double? = nil,
        paceDelta: Double? = nil,
        hrDelta: Double? = nil,
        cycles: [SurgeRecoveryCycle]? = nil,
        deadStopsCount: Int = 0,
        hoursSinceHeavyEffort: Double? = nil,
        isIndoor: Bool = false
    ) -> String {
        RunClassifierCore.classifyRun(
            buckets: buckets.map { $0.toTelemetryBucket() },
            cv: cv,
            slope: slope,
            zone4: zone4,
            durationMinutes: durationMinutes,
            cadenceCV: cadenceCV,
            averageHR: averageHR,
            paceDelta: paceDelta,
            hrDelta: hrDelta,
            cycles: cycles?.map { $0.toIntervalOscillationCycle() },
            deadStopsCount: deadStopsCount,
            hoursSinceHeavyEffort: hoursSinceHeavyEffort,
            isIndoor: isIndoor
        )
    }

    // MARK: - Tags & Diagnostic Markers

    /// Emits biomechanical diagnostic tags by delegating to FramboiseCore.
    func generateFramboiseTags(
        cv: Double,
        slope: Double,
        deadStopsCount: Int,
        buckets: [BucketData] = [],
        isIndoor: Bool = false
    ) -> [String] {
        FramboiseCore.generateFramboiseTags(
            cv: cv,
            slope: slope,
            deadStopsCount: deadStopsCount,
            buckets: buckets.map { $0.toTelemetryBucket() },
            isIndoor: isIndoor
        )
    }

    /// Detects progressive cadence turnover decay.
    func detectCadenceFade(buckets: [BucketData]) -> Bool {
        FramboiseCore.detectCadenceFade(buckets: buckets.map { $0.toTelemetryBucket() })
    }

    /// Detects cardiac drift.
    func detectCardiacDrift(buckets: [BucketData], paceSlope: Double) -> Bool {
        FramboiseCore.detectCardiacDrift(buckets: buckets.map { $0.toTelemetryBucket() }, paceSlope: paceSlope)
    }

    // MARK: - Distance Splits

    /// Computes authentic distance splits from continuous telemetry buckets.
    func calculateSplits(from buckets: [BucketData], splitDistanceMeters: Double = 1000.0) -> [RunSplit] {
        let telemetry = buckets.map { $0.toTelemetryBucket() }
        let splits = FramboiseCore.calculateSplits(from: telemetry, splitDistanceMeters: splitDistanceMeters)
        return splits.map(RunSplit.init(from:))
    }
}

// MARK: - Foundry Domain Bridging Extensions

extension BucketData {
    func toTelemetryBucket() -> TelemetryBucket {
        TelemetryBucket(
            timestamp: startTime,
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            paceSecondsPerKm: meanPaceSecPerKm,
            cadenceSPM: meanCadence,
            heartRateBPM: meanHR,
            verticalOscillationCm: meanVerticalOscillation > 0 ? meanVerticalOscillation : nil,
            strideLengthMeters: meanStrideLength > 0 ? meanStrideLength : nil,
            elevationGainMeters: elevationGainMeters
        )
    }

    init(from telemetry: TelemetryBucket) {
        self.init(
            startTime: telemetry.timestamp,
            distanceMeters: telemetry.distanceMeters,
            durationSeconds: telemetry.durationSeconds,
            meanPaceSecPerKm: telemetry.paceSecondsPerKm,
            meanCadence: telemetry.cadenceSPM,
            meanHR: telemetry.heartRateBPM,
            meanVerticalOscillation: telemetry.verticalOscillationCm ?? 0.0,
            meanStrideLength: telemetry.strideLengthMeters ?? 0.0,
            elevationGainMeters: telemetry.elevationGainMeters ?? 0.0
        )
    }
}

extension PhaseSegment {
    func toIntervalPhaseSegment() -> IntervalPhaseSegment {
        let phaseKind: IntervalPhaseKind
        switch kind.lowercased() {
        case "work": phaseKind = .work
        case "recovery": phaseKind = .recovery
        case "walking": phaseKind = .walking
        default: phaseKind = .steady
        }
        return IntervalPhaseSegment(
            startSeconds: startSeconds,
            endSeconds: endSeconds,
            kind: phaseKind,
            avgPaceSecondsPerKm: avgPace,
            avgCadenceSPM: avgCadence,
            avgHeartRateBPM: avgHR
        )
    }

    init(from coreSegment: IntervalPhaseSegment) {
        self.init(
            startSeconds: coreSegment.startSeconds,
            endSeconds: coreSegment.endSeconds,
            kind: coreSegment.kind.rawValue,
            avgPace: coreSegment.avgPaceSecondsPerKm,
            avgCadence: coreSegment.avgCadenceSPM,
            avgHR: coreSegment.avgHeartRateBPM
        )
    }
}

extension SurgeRecoveryCycle {
    func toIntervalOscillationCycle() -> IntervalOscillationCycle {
        IntervalOscillationCycle(
            workDurationSeconds: workDuration,
            recoveryDurationSeconds: recoveryDuration,
            workCadenceSPM: workCadence,
            recoveryCadenceSPM: recoveryCadence,
            workPaceSecondsPerKm: workPace,
            recoveryPaceSecondsPerKm: recoveryPace,
            workHeartRateBPM: workHR,
            recoveryHeartRateBPM: recoveryHR,
            isCorroborated: isCorroborated
        )
    }

    init(from coreCycle: IntervalOscillationCycle) {
        self.init(
            workDuration: coreCycle.workDurationSeconds,
            recoveryDuration: coreCycle.recoveryDurationSeconds,
            workCadence: coreCycle.workCadenceSPM,
            recoveryCadence: coreCycle.recoveryCadenceSPM,
            workPace: coreCycle.workPaceSecondsPerKm,
            recoveryPace: coreCycle.recoveryPaceSecondsPerKm,
            workHR: coreCycle.workHeartRateBPM,
            recoveryHR: coreCycle.recoveryHeartRateBPM,
            isCorroborated: coreCycle.isCorroborated
        )
    }
}

extension RunSplit {
    init(from split: TelemetrySplit) {
        self.init(
            index: split.index,
            distanceMeters: split.distanceMeters,
            durationSeconds: split.durationSeconds,
            paceSecondsPerKm: split.paceSecondsPerKm,
            avgHeartRate: split.avgHeartRateBPM,
            avgCadence: split.avgCadenceSPM,
            elevationGainMeters: split.elevationGainMeters
        )
    }
}
