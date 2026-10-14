import Foundation
import HealthKit

/// A deterministic calculator that applies physiological guardrails to AI prescriptions.
/// Ensures the AI does not prescribe dangerous target thresholds.
enum SafeTargetCalculator {
    /// Caps the prescribed cadence alert range to a maximum of 185 SPM to prevent overstriding.
    static func safeCadenceTarget(requestedCadence: Int?, previousCadence: Int?) -> HKQuantity? {
        guard let requested = requestedCadence else { return nil }

        let safeMax = 185
        let floor = max(140, previousCadence ?? 150)
        let safeTarget = min(safeMax, max(floor, requested))

        return HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: Double(safeTarget))
    }
}
