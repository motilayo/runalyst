import Foundation
import HealthKit
import Observation
import RunalystCore

// MARK: - Workout Manager

/// Coordinates HealthKit workout sessions, live metrics ingestion, and the 1 Hz pacing loop.
@MainActor
@Observable
public final class WorkoutManager: NSObject {
    public static let shared = WorkoutManager()

    public private(set) var sessionState: HKWorkoutSessionState = .notStarted
    public private(set) var currentLocation: PacingLocation = .outdoor

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var telemetryEngine: TelemetryEngine?
    private var tickTask: Task<Void, Never>?
    private weak var pacingViewModel: PacingViewModel?

    override private init() {
        super.init()
    }

    // MARK: - Permissions

    public func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }

        let typesToShare: Set<HKSampleType> = [
            HKObjectType.workoutType()
        ]

        let typesToRead: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.runningSpeed),
            HKQuantityType(.runningPower),
            HKQuantityType(.runningStrideLength),
            HKQuantityType(.runningGroundContactTime),
            HKQuantityType(.runningVerticalOscillation),
            HKQuantityType(.distanceWalkingRunning),
            HKCharacteristicType(.dateOfBirth)
        ]

        do {
            try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Session Control

    public func startWorkout(
        location: PacingLocation,
        intent: WatchRunIntent = .adaptiveBase,
        targetPaceSecondsPerKm: Int? = nil,
        viewModel: PacingViewModel
    ) async {
        self.currentLocation = location
        self.pacingViewModel = viewModel

        let resolved = WatchContextStore.shared.resolveSession(
            runIntent: intent,
            selectedPace: targetPaceSecondsPerKm,
            fallbackAge: athleteAge()
        )

        let engine = TelemetryEngine(
            profile: resolved.profile,
            intent: resolved.intent,
            location: location,
            watchIntent: intent,
            viewModel: viewModel
        )
        self.telemetryEngine = engine

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = (location == .indoor) ? .indoor : .outdoor

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()

            session.delegate = self
            builder.delegate = self
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)

            self.session = session
            self.builder = builder

            let startDate = Date()
            session.startActivity(with: startDate)
            try await builder.beginCollection(at: startDate)

            MotionStreamService.shared.startStreaming(
                location: location,
                telemetryEngine: engine,
                startTime: startDate
            )

            startTickLoop(engine: engine, builder: builder)
            self.sessionState = .running
        } catch {
            // Failed to start session
        }
    }

    public func pauseWorkout() {
        guard let session, session.state == .running else { return }
        session.pause()
        MotionStreamService.shared.pauseStreaming()
        Task {
            await telemetryEngine?.setPaused(true)
        }
        self.sessionState = .paused
    }

    public func resumeWorkout() {
        guard let session, session.state == .paused, let sessionObj = self.session else { return }
        session.resume()
        if let startDate = sessionObj.startDate, let engine = telemetryEngine {
            MotionStreamService.shared.resumeStreaming(
                location: currentLocation,
                telemetryEngine: engine,
                startTime: startDate
            )
        }
        Task {
            await telemetryEngine?.setPaused(false)
        }
        self.sessionState = .running
    }

    @discardableResult
    public func endWorkout() async -> WatchRunDebrief? {
        guard let session, let builder else { return nil }
        tickTask?.cancel()
        tickTask = nil

        let elapsed = builder.elapsedTime
        let totalDistance = builder.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meter())
        let useMetric = UserDefaults.standard.object(forKey: "useMetricSystem") as? Bool ?? true

        let debrief = await telemetryEngine?.buildRunDebrief(
            elapsedSeconds: elapsed,
            totalDistanceMeters: totalDistance,
            useMetricSystem: useMetric
        )

        pacingViewModel?.setCompletedDebrief(debrief)

        MotionStreamService.shared.stopStreaming()
        session.end()

        do {
            try await builder.endCollection(at: Date())
            try await builder.finishWorkout()
        } catch {
            // Finish failed safely
        }

        self.session = nil
        self.builder = nil
        self.telemetryEngine = nil
        self.sessionState = .ended

        return debrief
    }

    // MARK: - 1 Hz Tick Loop

    private func startTickLoop(engine: TelemetryEngine, builder: HKLiveWorkoutBuilder) {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s check interval
                guard let self, self.sessionState == .running else { continue }
                let elapsed = builder.elapsedTime
                let distanceMeters = builder.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meter())
                await engine.processTick(at: elapsed, distanceMeters: distanceMeters)
            }
        }
    }

    private func athleteAge() -> Int? {
        do {
            let birthComponents = try healthStore.dateOfBirthComponents()
            guard let birthYear = birthComponents.year else { return nil }
            let currentYear = Calendar.current.component(.year, from: Date())
            return currentYear - birthYear
        } catch {
            return nil
        }
    }
}

// MARK: - HKWorkoutSessionDelegate & HKLiveWorkoutBuilderDelegate

extension WorkoutManager: HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    nonisolated public func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            self.sessionState = toState
        }
    }

    nonisolated public func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {
        Task { @MainActor in
            self.sessionState = .ended
        }
    }

    nonisolated public func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        Task { @MainActor in
            self.handleCollectedData(workoutBuilder: workoutBuilder, collectedTypes: collectedTypes)
        }
    }

    nonisolated public func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    private func handleCollectedData(
        workoutBuilder: HKLiveWorkoutBuilder,
        collectedTypes: Set<HKSampleType>
    ) {
        guard let engine = telemetryEngine else { return }
        let elapsed = workoutBuilder.elapsedTime

        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType else { continue }
            let statistics = workoutBuilder.statistics(for: quantityType)

            switch quantityType {
            case HKQuantityType(.heartRate):
                if let hr = statistics?.mostRecentQuantity()?.doubleValue(for: HKUnit(from: "count/min")) {
                    Task { await engine.updateHeartRate(hr, at: elapsed) }
                }

            case HKQuantityType(.runningSpeed):
                if let speed = statistics?.mostRecentQuantity()?.doubleValue(for: .meter().unitDivided(by: .second())) {
                    Task { await engine.updateSpeed(speed, at: elapsed) }
                }

            case HKQuantityType(.runningPower):
                if let watts = statistics?.mostRecentQuantity()?.doubleValue(for: .watt()) {
                    Task { await engine.updatePower(watts, at: elapsed) }
                }

            case HKQuantityType(.runningStrideLength):
                if let meters = statistics?.mostRecentQuantity()?.doubleValue(for: .meter()) {
                    Task { await engine.updateStrideLength(meters, at: elapsed) }
                }

            case HKQuantityType(.runningGroundContactTime):
                if let gct = statistics?.mostRecentQuantity()?.doubleValue(for: .secondUnit(with: .milli)) {
                    Task { await engine.updateGroundContactTime(gct, at: elapsed) }
                }

            case HKQuantityType(.runningVerticalOscillation):
                if let cm = statistics?.mostRecentQuantity()?.doubleValue(for: .meterUnit(with: .centi)) {
                    Task { await engine.updateVerticalOscillation(cm, at: elapsed) }
                }

            case HKQuantityType(.distanceWalkingRunning):
                if let meters = statistics?.sumQuantity()?.doubleValue(for: .meter()) {
                    Task { await engine.updateDistance(meters, at: elapsed) }
                }

            default:
                break
            }
        }
    }
}
