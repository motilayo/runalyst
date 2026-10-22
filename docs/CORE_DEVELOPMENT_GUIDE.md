# Runalyst Core Development Guide: Adding New Biomechanical Modules

This guide establishes the mandatory workflow for designing, implementing, and verifying new domain logic within the **RunalystCore** Local Swift Package under the **Assay-Driven Engineering Model**.

---

## The Four-Step Core Development Pipeline

### Step 1: Prospecting & Updating "The Mold"

Before writing any algorithm, define the pure data contracts.

* **File:** `RunalystCore/Sources/RunalystCore/TheMold.swift`
* **Requirement:** Define any new pure input parameters, metrics, or output directives as immutable, `Sendable`, `Codable`, `Equatable` value types.
* **Constraint:** Never import Apple frameworks or use `@Model` macros here. Use raw Swift primitives (`Double`, `DateInterval`, enums).

### Step 2: Forging the Core Ingot

Create the isolated, stateless mathematical module.

* **File:** `RunalystCore/Sources/RunalystCore/[FeatureName]Core.swift`
* **Requirement:** Write pure, deterministic functions (`Sans-I/O`) taking the types defined in `TheMold.swift`.
* **Strict Constraints:**
  * **Zero I/O:** No network calls, no disk reads, no wall-clock time (`Date()`). Pass time and ranges explicitly.
  * **Mass Cap:** The file must stay strictly **under 500 lines of code**. If it grows larger, decompose it into smaller sub-modules.
  * **Purity:** Only `import Foundation`. No `HealthKit`, `SwiftData`, or `SwiftUI`.

### Step 3: Igniting the Crucible (Unit Testing)

Verify mathematical invariants instantly.

* **File:** `RunalystCore/Tests/RunalystCoreTests/[FeatureName]CoreTests.swift`
* **Requirement:** Write deterministic unit tests leveraging `GoldenTelemetryFixtures` and `TelemetryNoiseInjector` to subject the new algorithm to adversarial sensor chatter.
* **Performance Rule:** The entire test suite must execute in **under 5 milliseconds** on a local CPU without booting a simulator.

### Step 4: Industrial Extraction & Mill Assay Wiring

Connect the proven math to the iOS app and verify state equivalence.

* **Action (Foundry):** Create or update a thin adapter service in the main iOS app (`Runalyst/Services/`) that fetches raw data, maps it to `TheMold` types, invokes `[FeatureName]Core`, and stores results via `@ModelActor`.
* **Action (Mill Assay):** Add a corresponding test case inside `ContinuousMillAssayTests.swift` to prove that the `SwiftData` persistence layer matches the pure core output bit-for-bit.

---

## Standard Template for a New Core Module

When instructing Antigravity to build a new core feature, enforce this structural template:

```swift
import Foundation

/// [FeatureName]Core: Brief description of the physiological or biomechanical calculation.
public enum [FeatureName]Core {
    
    public struct Parameters: Sendable, Codable, Equatable {
        public let threshold: Double
        
        public init(threshold: Double) {
            self.threshold = threshold
        }
    }
    
    public struct Result: Sendable, Codable, Equatable {
        public let computedMetric: Double
        public let isSatisfied: Bool
        
        public init(computedMetric: Double, isSatisfied: Bool) {
            self.computedMetric = computedMetric
            self.isSatisfied = isSatisfied
        }
    }
    
    /// Executes the pure, deterministic calculation.
    /// - Parameters:
    ///   - buckets: Sanitized telemetry samples from TheMold
    ///   - parameters: Pure configuration values
    /// - Returns: Pure calculation results or directives
    public static func evaluate(
        buckets: [TelemetryBucket],
        parameters: Parameters
    ) -> Result {
        // 1. Guard against empty or invalid data streams
        guard !buckets.isEmpty else {
            return Result(computedMetric: 0.0, isSatisfied: false)
        }
        
        // 2. Perform pure mathematical transformations
        // (No side effects, no global state, no Date() calls)
        let metric = calculateMetric(from: buckets)
        let satisfied = metric >= parameters.threshold
        
        // 3. Return immutable result struct
        return Result(computedMetric: metric, isSatisfied: satisfied)
    }
    
    private static func calculateMetric(from buckets: [TelemetryBucket]) -> Double {
        // Pure math implementation
        let total = buckets.reduce(0.0) { $0 + $1.heartRateBPM }
        return buckets.isEmpty ? 0.0 : total / Double(buckets.count)
    }
}
```

---

## The Final Gate: Running `./assay.sh`

Before opening any pull request, ensure the codebase passes the local assay verification:

```bash
./assay.sh
```

If the script outputs `[HALLMARK GRANTED]`, the module is certified pure, mass-compliant, and ready for industrial extraction.
