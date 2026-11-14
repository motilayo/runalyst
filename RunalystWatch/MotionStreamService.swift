import CoreMotion
import Foundation
import RunalystCore

// MARK: - Motion Stream Service

/// Power-conscious sensor streaming service coordinating pedometer, altimeter, and IMU data.
///
/// Strictly obeys the Hollow Foundry doctrine: passes raw measurements directly to `TelemetryEngine`
/// and RunalystCore without inline threshold comparisons or filtering.
public final class MotionStreamService: @unchecked Sendable {
    public static let shared = MotionStreamService()

    private let pedometer = CMPedometer()
    private let motionManager = CMMotionManager()
    private let altimeter = CMAltimeter()

    private var pausedAccumulatedSeconds: TimeInterval = 0
    private var pauseStartDate: Date?

    private var lastAltitudeMeters: Double?
    private var lastAltitudeDistanceMeters: Double?
    private var currentCumulativeDistanceMeters: Double?

    private init() {}

    // MARK: - Active Elapsed Time

    private func activeElapsed(since startTime: Date, at now: Date = Date()) -> TimeInterval {
        let rawElapsed = now.timeIntervalSince(startTime)
        let ongoingPause = pauseStartDate.map { max(0.0, now.timeIntervalSince($0)) } ?? 0.0
        let active = rawElapsed - pausedAccumulatedSeconds - ongoingPause
        return max(0.0, active)
    }

    // MARK: - Lifecycle

    /// Starts streaming motion sensors for a session.
    public func startStreaming(
        location: PacingLocation,
        telemetryEngine: TelemetryEngine,
        startTime: Date
    ) {
        pausedAccumulatedSeconds = 0
        pauseStartDate = nil
        lastAltitudeMeters = nil
        lastAltitudeDistanceMeters = nil
        currentCumulativeDistanceMeters = nil

        startPedometer(from: startTime, startTime: startTime, telemetryEngine: telemetryEngine)

        if location == .indoor {
            startDeviceMotion(startTime: startTime, telemetryEngine: telemetryEngine)
        } else if location == .outdoor {
            startAltimeter(startTime: startTime, telemetryEngine: telemetryEngine)
        }
    }

    /// Stops all sensor streams.
    public func stopStreaming() {
        pedometer.stopUpdates()
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
        altimeter.stopRelativeAltitudeUpdates()

        pausedAccumulatedSeconds = 0
        pauseStartDate = nil
        lastAltitudeMeters = nil
        lastAltitudeDistanceMeters = nil
        currentCumulativeDistanceMeters = nil
    }

    /// Pauses motion streaming to conserve battery during paused workouts.
    public func pauseStreaming() {
        if pauseStartDate == nil {
            pauseStartDate = Date()
        }
        pedometer.stopUpdates()
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
        altimeter.stopRelativeAltitudeUpdates()
        lastAltitudeMeters = nil
        lastAltitudeDistanceMeters = nil
        currentCumulativeDistanceMeters = nil
    }

    /// Resumes motion streaming when a workout unpauses.
    public func resumeStreaming(
        location: PacingLocation,
        telemetryEngine: TelemetryEngine,
        startTime: Date
    ) {
        if let pauseStartDate {
            pausedAccumulatedSeconds += max(0.0, Date().timeIntervalSince(pauseStartDate))
            self.pauseStartDate = nil
        }

        startPedometer(from: Date(), startTime: startTime, telemetryEngine: telemetryEngine)

        if location == .indoor {
            startDeviceMotion(startTime: startTime, telemetryEngine: telemetryEngine)
        } else if location == .outdoor {
            startAltimeter(startTime: startTime, telemetryEngine: telemetryEngine)
        }
    }

    // MARK: - Sensor Streaming Helpers

    private func startPedometer(
        from fromDate: Date,
        startTime: Date,
        telemetryEngine: TelemetryEngine
    ) {
        guard CMPedometer.isStepCountingAvailable() else { return }
        pedometer.startUpdates(from: fromDate) { [weak self] data, _ in
            guard let self, let data else { return }
            let elapsed = self.activeElapsed(since: startTime, at: data.endDate)

            if let currentCadence = data.currentCadence?.doubleValue {
                // CMPedometer reports steps per second; convert to SPM (steps per minute)
                let cadenceSPM = currentCadence * 60.0
                Task {
                    await telemetryEngine.updatePedometerCadence(cadenceSPM, at: elapsed)
                }
            }

            if let currentPace = data.currentPace?.doubleValue, currentPace > 0 {
                // CMPedometer currentPace is seconds per meter; speed = 1.0 / pace
                let speedMps = 1.0 / currentPace
                Task {
                    await telemetryEngine.updateSpeed(speedMps, at: elapsed)
                }
            }

            if let distance = data.distance?.doubleValue {
                self.currentCumulativeDistanceMeters = distance
            }
        }
    }

    private func startDeviceMotion(
        startTime: Date,
        telemetryEngine: TelemetryEngine
    ) {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 50.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let accelMagnitude = sqrt(
                motion.userAcceleration.x * motion.userAcceleration.x +
                motion.userAcceleration.y * motion.userAcceleration.y +
                motion.userAcceleration.z * motion.userAcceleration.z
            )
            let elapsed = self.activeElapsed(since: startTime)
            Task {
                await telemetryEngine.updateIMUCadence(accelMagnitude * 60.0, at: elapsed)
            }
        }
    }

    private func startAltimeter(
        startTime: Date,
        telemetryEngine: TelemetryEngine
    ) {
        guard CMAltimeter.isRelativeAltitudeAvailable() else { return }
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] altData, _ in
            guard let self, let altData else { return }
            let altitude = altData.relativeAltitude.doubleValue
            let elapsed = self.activeElapsed(since: startTime)

            if let prevAlt = self.lastAltitudeMeters,
               let prevDist = self.lastAltitudeDistanceMeters,
               let currentDist = self.currentCumulativeDistanceMeters {
                let altDelta = altitude - prevAlt
                let distDelta = currentDist - prevDist
                if let grade = TelemetryStalenessPolicy.computeGradeFraction(
                    altitudeDeltaMeters: altDelta,
                    distanceDeltaMeters: distDelta
                ) {
                    Task {
                        await telemetryEngine.updateGradeFraction(grade, at: elapsed)
                    }
                    self.lastAltitudeMeters = altitude
                    self.lastAltitudeDistanceMeters = currentDist
                }
            } else {
                self.lastAltitudeMeters = altitude
                self.lastAltitudeDistanceMeters = self.currentCumulativeDistanceMeters
            }
        }
    }
}
