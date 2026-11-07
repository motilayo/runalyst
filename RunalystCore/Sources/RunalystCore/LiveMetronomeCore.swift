import Foundation

/// Pure sports science model representing a parsed interval prescription.
public struct ParsedIntervalPrescription: Sendable, Equatable {
    public let iterations: Int
    public let distanceMeters: Double
    public let cadenceLowerBound: Double
    public let cadenceUpperBound: Double

    public var cadenceRange: ClosedRange<Double> {
        cadenceLowerBound...cadenceUpperBound
    }

    public init(
        iterations: Int,
        distanceMeters: Double,
        cadenceLowerBound: Double,
        cadenceUpperBound: Double
    ) {
        self.iterations = iterations
        self.distanceMeters = distanceMeters
        self.cadenceLowerBound = cadenceLowerBound
        self.cadenceUpperBound = cadenceUpperBound
    }
}

/// Pure domain calculations for live metronome pacing and duty-cycled haptics.
public enum LiveMetronomeCore {

    /// Initial lock-in window where metronome pulses continuously to entrain rhythm.
    public static let initialLockInWindowSeconds: TimeInterval = 20.0

    /// Tolerance in SPM below target cadence before duty-cycled haptic cues fire.
    public static let dutyCycledDriftToleranceSPM: Int = 2

    /// Half-width in SPM around the target cadence to establish the alert band (+/- 5 SPM).
    public static let cadenceBandHalfWidthSPM: Int = 5

    /// Parses an AI drill prescription string (e.g. "4x400m intervals") into interval components
    /// and calculates the cadence alert boundaries around target SPM.
    public static func parsePrescription(_ prescription: String, targetSPM: Int) -> ParsedIntervalPrescription? {
        let pattern = #"(\d+)x(\d+)m"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(
                in: prescription,
                options: [],
                range: NSRange(location: 0, length: prescription.utf16.count)
              ),
              let iterRange = Range(match.range(at: 1), in: prescription),
              let distRange = Range(match.range(at: 2), in: prescription),
              let iterations = Int(prescription[iterRange]),
              let distance = Double(prescription[distRange]),
              iterations > 0,
              distance > 0 else {
            return nil
        }

        let lowerBound = Double(max(0, targetSPM - cadenceBandHalfWidthSPM))
        let upperBound = Double(max(Int(lowerBound), targetSPM + cadenceBandHalfWidthSPM))

        return ParsedIntervalPrescription(
            iterations: iterations,
            distanceMeters: distance,
            cadenceLowerBound: lowerBound,
            cadenceUpperBound: upperBound
        )
    }

    /// Calculates the beat interval in seconds corresponding to a target SPM.
    /// Returns nil if targetSPM is non-positive.
    public static func beatIntervalSeconds(forTargetSPM targetSPM: Int) -> TimeInterval? {
        guard targetSPM > 0 else { return nil }
        return 60.0 / Double(targetSPM)
    }

    /// Determines if a corrective haptic cue should trigger based on falling below target cadence.
    public static func shouldTriggerCorrectiveHaptic(currentSPM: Int, targetSPM: Int) -> Bool {
        currentSPM < targetSPM
    }

    /// Evaluates if haptic feedback should be delivered according to duty-cycling rules.
    /// Fires during the initial lock-in window or when cadence drifts below tolerance.
    public static func shouldTriggerDutyCycledHaptic(
        isEnabled: Bool,
        currentSPM: Int,
        targetSPM: Int,
        intervalElapsedSeconds: TimeInterval
    ) -> Bool {
        guard isEnabled else { return false }
        return intervalElapsedSeconds <= initialLockInWindowSeconds
            || currentSPM < (targetSPM - dutyCycledDriftToleranceSPM)
    }

    /// Alias for `shouldTriggerDutyCycledHaptic` conforming to the haptic trigger protocol.
    public static func shouldTriggerHaptic(
        isEnabled: Bool,
        currentSPM: Int,
        targetSPM: Int,
        intervalElapsedSeconds: TimeInterval
    ) -> Bool {
        shouldTriggerDutyCycledHaptic(
            isEnabled: isEnabled,
            currentSPM: currentSPM,
            targetSPM: targetSPM,
            intervalElapsedSeconds: intervalElapsedSeconds
        )
    }
}
