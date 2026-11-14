import Foundation
import RunalystCore

// MARK: - Telemetry Engine

/// Actor coordinating real-time 1 Hz sample alignment, staleness nulling, and core pacing ingestion.
///
/// Strictly obeys the Hollow Foundry doctrine: performs zero threshold comparisons, zero filtering,
/// and zero domain arithmetic. All math is performed exclusively by `RunalystCore`.
public actor TelemetryEngine {
    private var core: AdaptivePacingCore
    private weak var viewModel: PacingViewModel?

    private struct MetricSample: Sendable {
        var value: Double?
        var timestamp: TimeInterval?
    }

    // Per-metric latest sample caches
    private var heartRate = MetricSample()
    private var speed = MetricSample()
    private var power = MetricSample()
    private var strideLength = MetricSample()
    private var groundContactTime = MetricSample()
    private var verticalOscillation = MetricSample()
    private var pedometerCadence = MetricSample()
    private var imuCadence = MetricSample()
    private var gradeFraction = MetricSample()

    private var lastEmittedSecond: Int = -1
    private var isPaused: Bool = false
    private var lastCompletedSplit: Int = 0
    private var cumulativeDistanceMeters: Double = 0.0
    private var lastSplitElapsed: TimeInterval = 0.0
    private var latestElapsedSeconds: TimeInterval = 0.0
    private var latestDistanceMeters: Double?

    public init(
        profile: AthleteCalibrationProfile,
        intent: PacingSessionIntent,
        location: PacingLocation,
        configuration: AdaptivePacingConfiguration? = nil,
        watchIntent: WatchRunIntent = .adaptiveBase,
        viewModel: PacingViewModel? = nil
    ) {
        let resolvedConfig: AdaptivePacingConfiguration = {
            if let configuration {
                return configuration
            }
            if intent.intent != .intervals && intent.prescribedDrillId == nil {
                return .forWatchCompanion(intent: watchIntent, cadenceFloorSPM: intent.targetCadenceSPM)
            }
            return .standard
        }()
        self.core = AdaptivePacingCore(
            profile: profile,
            intent: intent,
            location: location,
            configuration: resolvedConfig
        )
        self.viewModel = viewModel
    }

    // MARK: - Configuration & Lifecycle

    /// Attaches the main-actor pacing view model for publication.
    public func bindViewModel(_ viewModel: PacingViewModel) {
        self.viewModel = viewModel
    }

    /// Reconfigures the core state machine for a newly started workout session.
    public func reconfigure(
        profile: AthleteCalibrationProfile,
        intent: PacingSessionIntent,
        location: PacingLocation,
        configuration: AdaptivePacingConfiguration? = nil,
        watchIntent: WatchRunIntent = .adaptiveBase
    ) {
        let resolvedConfig: AdaptivePacingConfiguration = {
            if let configuration {
                return configuration
            }
            if intent.intent != .intervals && intent.prescribedDrillId == nil {
                return .forWatchCompanion(intent: watchIntent, cadenceFloorSPM: intent.targetCadenceSPM)
            }
            return .standard
        }()
        self.core = AdaptivePacingCore(
            profile: profile,
            intent: intent,
            location: location,
            configuration: resolvedConfig
        )
        self.lastEmittedSecond = -1
        self.isPaused = false
        self.lastCompletedSplit = 0
        self.cumulativeDistanceMeters = 0.0
        self.lastSplitElapsed = 0.0
        self.latestElapsedSeconds = 0.0
        self.latestDistanceMeters = nil
        self.resetSamples()
    }

    /// Sets the paused state. When paused, tick emissions are frozen.
    public func setPaused(_ paused: Bool) {
        self.isPaused = paused
    }

    /// Clears cached metric samples.
    public func resetSamples() {
        heartRate = MetricSample()
        speed = MetricSample()
        power = MetricSample()
        strideLength = MetricSample()
        groundContactTime = MetricSample()
        verticalOscillation = MetricSample()
        pedometerCadence = MetricSample()
        imuCadence = MetricSample()
        gradeFraction = MetricSample()
    }

    // MARK: - Metric Ingestion

    public func updateHeartRate(_ bpm: Double, at elapsed: TimeInterval) {
        heartRate = MetricSample(value: bpm, timestamp: elapsed)
    }

    public func updateSpeed(_ mps: Double, at elapsed: TimeInterval) {
        speed = MetricSample(value: mps, timestamp: elapsed)
    }

    public func updatePower(_ watts: Double, at elapsed: TimeInterval) {
        power = MetricSample(value: watts, timestamp: elapsed)
    }

    public func updateStrideLength(_ meters: Double, at elapsed: TimeInterval) {
        strideLength = MetricSample(value: meters, timestamp: elapsed)
    }

    public func updateGroundContactTime(_ ms: Double, at elapsed: TimeInterval) {
        groundContactTime = MetricSample(value: ms, timestamp: elapsed)
    }

    public func updateVerticalOscillation(_ cm: Double, at elapsed: TimeInterval) {
        verticalOscillation = MetricSample(value: cm, timestamp: elapsed)
    }

    public func updatePedometerCadence(_ spm: Double, at elapsed: TimeInterval) {
        pedometerCadence = MetricSample(value: spm, timestamp: elapsed)
    }

    public func updateIMUCadence(_ spm: Double, at elapsed: TimeInterval) {
        imuCadence = MetricSample(value: spm, timestamp: elapsed)
    }

    public func updateGradeFraction(_ fraction: Double, at elapsed: TimeInterval) {
        gradeFraction = MetricSample(value: fraction, timestamp: elapsed)
    }

    public func updateDistance(_ meters: Double, at elapsed: TimeInterval) {
        cumulativeDistanceMeters = max(cumulativeDistanceMeters, meters)
        latestDistanceMeters = cumulativeDistanceMeters
        latestElapsedSeconds = max(latestElapsedSeconds, elapsed)
    }

    // MARK: - 1 Hz Tick Generation

    /// Emits exactly one `TelemetryTick` per whole elapsed second from `elapsedTime`.
    ///
    /// Skips tick emission if paused or if this whole second was already emitted.
    @discardableResult
    public func processTick(
        at elapsed: TimeInterval,
        distanceMeters: Double? = nil
    ) async -> (events: [PacingEvent], display: PacingDisplayState)? {
        guard !isPaused else { return nil }

        let currentSecond = Int(elapsed)
        guard currentSecond > lastEmittedSecond, currentSecond >= 0 else { return nil }
        lastEmittedSecond = currentSecond
        latestElapsedSeconds = elapsed

        if let distanceMeters {
            cumulativeDistanceMeters = max(cumulativeDistanceMeters, distanceMeters)
            latestDistanceMeters = cumulativeDistanceMeters
        }

        let tick = TelemetryTick(
            elapsedSeconds: elapsed,
            heartRateBPM: TelemetryStalenessPolicy.validValue(
                heartRate.value,
                sampleTimestamp: heartRate.timestamp,
                currentElapsed: elapsed
            ),
            speedMetersPerSecond: TelemetryStalenessPolicy.validValue(
                speed.value,
                sampleTimestamp: speed.timestamp,
                currentElapsed: elapsed
            ),
            powerWatts: TelemetryStalenessPolicy.validValue(
                power.value,
                sampleTimestamp: power.timestamp,
                currentElapsed: elapsed
            ),
            cadenceSPM: TelemetryStalenessPolicy.validValue(
                pedometerCadence.value,
                sampleTimestamp: pedometerCadence.timestamp,
                currentElapsed: elapsed
            ),
            imuCadenceSPM: TelemetryStalenessPolicy.validValue(
                imuCadence.value,
                sampleTimestamp: imuCadence.timestamp,
                currentElapsed: elapsed
            ),
            groundContactTimeMs: TelemetryStalenessPolicy.validValue(
                groundContactTime.value,
                sampleTimestamp: groundContactTime.timestamp,
                currentElapsed: elapsed
            ),
            verticalOscillationCm: TelemetryStalenessPolicy.validValue(
                verticalOscillation.value,
                sampleTimestamp: verticalOscillation.timestamp,
                currentElapsed: elapsed
            ),
            strideLengthMeters: TelemetryStalenessPolicy.validValue(
                strideLength.value,
                sampleTimestamp: strideLength.timestamp,
                currentElapsed: elapsed
            ),
            gradeFraction: TelemetryStalenessPolicy.validValue(
                gradeFraction.value,
                sampleTimestamp: gradeFraction.timestamp,
                currentElapsed: elapsed
            ),
            totalDistanceMeters: distanceMeters
        )

        let result = core.ingest(tick)
        var finalEvents = result.events

        let useMetric = UserDefaults.standard.object(forKey: "useMetricSystem") as? Bool
            ?? (Locale.current.measurementSystem == .metric)
        let splitUnitMeters = useMetric ? 1000.0 : 1609.344
        while cumulativeDistanceMeters >= Double(lastCompletedSplit + 1) * splitUnitMeters {
            lastCompletedSplit += 1
            let splitDuration = elapsed - lastSplitElapsed
            let fallbackKmPace = result.display.filteredPaceSecondsPerKm ?? 300
            let fallbackSplitPace = useMetric
                ? fallbackKmPace
                : Int((Double(fallbackKmPace) * 1.609344).rounded())
            let splitPace = splitDuration > 0 ? Int(splitDuration) : fallbackSplitPace
            lastSplitElapsed = elapsed
            let splitEvent = PacingEvent.splitMilestone(
                splitIndex: lastCompletedSplit,
                splitPaceSecondsPerKm: splitPace
            )
            finalEvents.append(splitEvent)
        }

        if let vm = viewModel {
            await vm.update(events: finalEvents, display: result.display)
        }
        return (events: finalEvents, display: result.display)
    }

    // MARK: - Post-Run Debrief

    /// Builds a deterministic, unit-aware post-run debrief summary from the core engine.
    public func buildRunDebrief(
        elapsedSeconds: TimeInterval,
        totalDistanceMeters: Double?,
        useMetricSystem: Bool
    ) -> WatchRunDebrief {
        let finalElapsed = elapsedSeconds > 0 ? elapsedSeconds : latestElapsedSeconds
        let finalDistance = totalDistanceMeters ?? latestDistanceMeters ?? cumulativeDistanceMeters
        return core.buildRunDebrief(
            elapsedSeconds: finalElapsed,
            totalDistanceMeters: finalDistance,
            useMetricSystem: useMetricSystem
        )
    }
}
