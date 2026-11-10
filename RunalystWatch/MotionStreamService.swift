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

    private var lastAltitudeMeters: Double?
    private var lastAltitudeDistanceMeters: Double?
    private var currentCumulativeDistanceMeters: Double?

    private init() {}

    // MARK: - Lifecycle

    /// Starts streaming motion sensors for a session.
    public func startStreaming(
        location: PacingLocation,
        telemetryEngine: TelemetryEngine,
        startTime: Date
    ) {
        // 1. CMPedometer streaming for all sessions
        if CMPedometer.isStepCountingAvailable() {
            pedometer.startUpdates(from: startTime) { [weak self] data, _ in
                guard let self, let data else { return }
                let elapsed = data.endDate.timeIntervalSince(startTime)

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

                // Update cumulative distance for grade calculation
                if let distance = data.distance?.doubleValue {
                    self.currentCumulativeDistanceMeters = distance
                }
            }
        }

        // 2. High-rate IMU (50 Hz) only on indoor sessions
        if location == .indoor && motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 1.0 / 50.0
            motionManager.startDeviceMotionUpdates(to: .main) { motion, _ in
                guard let motion else { return }
                // Supply user acceleration magnitude for IMU cadence cross-check
                let accelMagnitude = sqrt(
                    motion.userAcceleration.x * motion.userAcceleration.x +
                    motion.userAcceleration.y * motion.userAcceleration.y +
                    motion.userAcceleration.z * motion.userAcceleration.z
                )
                // Passing raw estimate without domain thresholds
                let nowElapsed = Date().timeIntervalSince(startTime)
                Task {
                    await telemetryEngine.updateIMUCadence(accelMagnitude * 60.0, at: nowElapsed)
                }
            }
        }

        // 3. CMAltimeter relative altitude for outdoor grade tracking
        if location == .outdoor && CMAltimeter.isRelativeAltitudeAvailable() {
            altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] altData, _ in
                guard let self, let altData else { return }
                let altitude = altData.relativeAltitude.doubleValue
                let elapsed = Date().timeIntervalSince(startTime)

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

    /// Stops all sensor streams.
    public func stopStreaming() {
        pedometer.stopUpdates()
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
        altimeter.stopRelativeAltitudeUpdates()
        lastAltitudeMeters = nil
        lastAltitudeDistanceMeters = nil
        currentCumulativeDistanceMeters = nil
    }

    /// Pauses high-rate motion streaming to conserve battery.
    public func pauseStreaming() {
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
    }

    /// Resumes high-rate motion streaming when an indoor session unpauses.
    public func resumeStreaming(location: PacingLocation, telemetryEngine: TelemetryEngine, startTime: Date) {
        if location == .indoor && motionManager.isDeviceMotionAvailable {
            motionManager.startDeviceMotionUpdates(to: .main) { motion, _ in
                guard let motion else { return }
                let accelMagnitude = sqrt(
                    motion.userAcceleration.x * motion.userAcceleration.x +
                    motion.userAcceleration.y * motion.userAcceleration.y +
                    motion.userAcceleration.z * motion.userAcceleration.z
                )
                let nowElapsed = Date().timeIntervalSince(startTime)
                Task {
                    await telemetryEngine.updateIMUCadence(accelMagnitude * 60.0, at: nowElapsed)
                }
            }
        }
    }
}
