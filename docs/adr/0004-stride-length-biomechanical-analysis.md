# 4. Incorporating Stride Length into Biomechanical Analysis and Coaching

* **Status**: Accepted
* **Date**: 2026-09-24 (Updated: 2026-09-25)
* **Deciders**: Runalyst Engineering Team
* **Consulted**: Architecture & AI Coaching Working Group
* **Informed**: Runalyst Core Contributors

## Context and Problem Statement

In running biomechanics, horizontal running speed is governed by the fundamental velocity equation:

```
Speed = Cadence * Stride Length
```

Currently, Runalyst captures and analyzes pace, cadence, heart rate, and vertical oscillation across its data ingestion, aggregation (`FramboiseEngine`), and AI coaching (`CoachingEngine` / `RunAnalyzerActor`) pipelines. However, **stride length was previously absent** from persistent storage (`RunRecord`), baseline calculations (`BaselineStats`), and coaching directives:

1. **Permissions without Persistence**: `HealthKitManager.swift` requested read authorization for `HKQuantityTypeIdentifier.runningStrideLength`, and `LiveCoachDTOs.swift` defined `WatchRunRecordDTO.strideLength`. However, `WatchConnectivityManager.saveRunRecord` dropped the field, and `HealthKitManager` never queried it during sync.
2. **Blunt Heuristic for Overstriding**: In `RunAnalyzerActor.swift`, overstriding was diagnosed using a single scalar cadence floor:
   ```swift
   if run.workingAvgCadence < 150 {
       directiveContext = "The runner is overstriding (low cadence). Prescribe a drill focused on Form, specifically quickening cadence." + goalSuffix
   }
   ```
   This created false positives for tall runners with naturally long, efficient strides, as well as easy recovery runs where cadence is lower without braking forces. Conversely, it failed to detect true braking overstriding at cadences between 150–165 SPM.
3. **Missing Running Economy Benchmark (Vertical Ratio)**: Apple Watch captures both vertical oscillation (VO) and stride length. The ratio of the two—**Vertical Ratio** (`(Vertical Oscillation / Stride Length) * 100%`)—is the gold-standard metric for running economy, describing the percentage of energy directed upward (wasted bounce) versus forward. Runalyst previously could not compute this metric.

### Translating Laboratory Biomechanics into HealthKit Telemetry

While sports science labs require high-speed optical motion capture to measure tibial inclination angles, knee flexion, and distance from the center of mass (COM), Runalyst detects and treats this exact mechanical failure using wrist-based Apple HealthKit telemetry.

Because the Apple Watch is worn on the wrist, it cannot directly measure whether a foot strike is > 30 cm ahead of the COM. However, it captures the three downstream kinematic consequences of that mechanical braking force:

* **Cadence vs. Stride Length Disparity**: Overstriding occurs when a runner reaches forward with their lead leg rather than driving backward with their glutes. In the data pipeline, this manifests as an inflated `runningStrideLength` paired with a sluggish cadence (e.g., < 155 SPM).
* **Spike in Ground Contact Time (GCT)**: When the foot lands with a locked knee and large forward tibial angle, it acts as a mechanical brake. The foot must remain planted on the ground while the runner's COM slowly travels forward over the ankle. That braking phase directly inflates `runningGroundContactTime` (often > 260 ms).
* **Excessive Vertical Oscillation**: Landing stiff-legged sends high vertical impact forces straight up the kinetic chain. The energy that should have propelled the runner forward bounces upward instead, resulting in elevated `runningVerticalOscillation` (e.g., > 10.0 cm, like the 10.6 cm reading flagged in test fixtures).

## Decision Drivers

* **Biomechanical Fidelity**: Distinguish between cadence-driven vs. stride-driven pace adaptations, and detect actual braking overstriding rather than using an arbitrary cadence threshold.
* **Running Economy Scoring**: Enable computation of Vertical Ratio (VR), a key metric for form efficiency.
* **Schema Safety & Zero Redundant Compute**: Model changes must use additive optional fields (`Double?`) to avoid breaking existing SwiftData stores, and working averages must be computed during initial ingestion without launch-time repair scans (per `AGENTS.md`).
* **Deterministic Math over LLM Hallucinations**: Calculate baseline deltas, acceleration mechanics, and vertical ratios deterministically in Swift, injecting concise contextual English strings into the FoundationModels prompt (adhering to Apple TN3193 4,096-token limits).
* **Parity Between Watch and Phone**: Ensure both HealthKit historical sync and watchOS Live Coach transfers capture, persist, and analyze stride length identically.
* **UI Grid Balance & Symmetry**: Maintain a clean, balanced grid in `RunDetailView` without awkward orphan cards.

## Considered Options

* **Option 1 (Full-Pipeline Biomechanical Integration - Balanced 8-Card Layout)**: Ingest `runningStrideLength` from HealthKit and watchOS, persist `rawAvgStrideLength` and `workingAvgStrideLength` on `RunRecord`, calculate 30-day weighted baselines and Vertical Ratio in Swift, inject deterministic acceleration/form directives into `RunAnalyzerActor` and `DashboardView`, and display both Stride Length and Vertical Ratio in an 8-card balanced grid.
* **Option 2 (Display-Only Ingestion)**: Ingest and store stride length on `RunRecord` for presentation in `RunDetailView`, but omit it from `BaselineStats`, `FramboiseEngine`, and AI coaching.
* **Option 3 (Status Quo)**: Continue using cadence as an indirect proxy for stride dynamics and overstriding.

## Decision Outcome

Chosen option: **Option 1 (Full-Pipeline Biomechanical Integration - Balanced 8-Card Layout)**, because stride length completes the velocity equation, eliminates false-positive overstriding diagnoses, unlocks Vertical Ratio running economy benchmarks, and maintains visual symmetry in the workout details grid.

---

## Technical Specification & Architecture

### 1. SwiftData Model Changes (`RunRecord.swift`)

Add additive optional properties to `RunRecord` (preserving backwards compatibility without migration plan breaks) with biological sanity clamping:

```swift
// MARK: - Biomechanical Stride Metrics (meters)
var rawAvgStrideLength: Double?
var workingAvgStrideLength: Double?

/// Computed Vertical Ratio (percentage of vertical bounce relative to forward stride)
/// Includes biological minimum clamp (stride >= 0.3m) to guard against division-by-near-zero anomalies during GPS hiccups.
var verticalRatio: Double? {
    guard let stride = workingAvgStrideLength ?? rawAvgStrideLength, stride >= 0.3,
          let oscCm = workingAvgVerticalOscillation ?? rawAvgVerticalOscillation, oscCm > 0 else {
        return nil
    }
    // oscCm is in centimeters; stride is in meters -> (oscCm / (stride * 100)) * 100 = oscCm / stride
    return oscCm / stride
}
```

### 2. Ingestion Pipeline & Persistence Bridge

* **HealthKit Continuous Bucketing & Summary Sync (`HealthKitManager.swift`)**:
  - In `fetchBucketedSamples(for:)`, execute continuous time-slice statistics for `.runningStrideLength` with unit `HKUnit.meter()`, populating `BucketData.meanStrideLength`.
  - In `extractRunRecord(from:engine:priorRuns:)`, fetch workout discrete average via `HKStatisticsQuery` for `.runningStrideLength`, calculate noise-filtered working averages via `FramboiseEngine`, and populate `RunRecordDTO.rawAvgStrideLength` and `RunRecordDTO.workingAvgStrideLength`.
* **Working Stats Engine (`FramboiseEngine.swift`)**:
  - `BucketData` carries `meanStrideLength: Double`.
  - `calculateWorkingAverages` accumulates stride samples strictly from active running buckets (`meanStrideLength > 0`). When no dead stops are trimmed (`isFullyActive`), it strictly inherits `rawAvgStrideLength` to eliminate floating-point divergence.
* **SwiftData Ingestion Bridge (`ContentView.swift`)**:
  - In `syncData()`, forward `dto.rawAvgStrideLength` and `dto.workingAvgStrideLength` when instantiating `RunRecord`.
* **Watch Transfer (`WatchConnectivityManager.swift`)**:
  - In `saveRunRecord(from dto: WatchRunRecordDTO, context: ModelContext)`, map `dto.strideLength` to `rawAvgStrideLength` and `workingAvgStrideLength`.
* **Seed Data Tooling (`HealthKitSeeder.swift`)**:
  - Seed realistic continuous stride lengths dynamically derived from the velocity equation (`v = distance / time`, `stride = v / (cadence / 60)`).

### 3. Baseline & AI Coaching Integration (`RunAnalyzerActor` & `DashboardView`)

Extend `BaselineStats` to track 30-day weighted stride length:

```swift
struct BaselineStats: Sendable {
    let avgPace: Double
    let avgCadence: Double
    let avgHR: Double
    let avgOscillation: Double
    let avgStrideLength: Double? // in meters
}
```

#### Deterministic Form & Overstriding Directives (`RunAnalyzerActor`)

Replace the scalar `cadence < 150` check with multi-signal evaluation:

1. **True Overstriding / High Braking Signature**:
   - `cadence < 155 SPM` AND `verticalRatio > 9.5%` (or vertical oscillation `> 10.0 cm` with stride length exceeding baseline by `> 5%`).
   - Directive: `"The runner shows high vertical bounce relative to stride length (VR: X%), indicating overstriding and braking forces. Prescribe Cadence Pyramids or Rhythm Intervals to quicken turnover."`
2. **Acceleration Mechanics (Cadence vs. Stride Expansion)**:
   - When pace is faster than baseline:
     - If `cadenceDelta > 4` and `strideDelta <= 0.03`: `"Pace increase driven primarily by turnover frequency (+X SPM)."`
     - If `strideDelta > 0.05` and `cadenceDelta <= 2`: `"Pace increase driven by stride extension (+X cm), maintaining steady rhythm."`
     - If both increased: `"Balanced acceleration via both turnover and stride extension."`
3. **Late-Run Stride Collapse (Mechanical Fatigue)**:
   - When cadence remains stable (`+/- 2 SPM`) but pace drops and stride length compresses by `> 8%`, flag mechanical fatigue: `"The runner shows mechanical stride collapse... Prescribe a Form drill to reinforce hip extension and posture under fatigue."`
4. **Cardiovascular Safety Priority**:
   - As mandated by `AGENTS.md`, cardiac fatigue (`paceDiff < 0 && hrDelta > 0`) overrides race goals and form directives with recovery priority.

#### Macro Strategic AI (`DashboardView.swift`)

In the 30-Day Dashboard view, longitudinal Vertical Ratio changes (`Delta VR < -0.3%`) are evaluated alongside Efficiency Factor and cardiac cost to prompt the sports scientist persona on running economy expansion.

### 4. FoundationModels Prompt Injection

To stay strictly within Apple's TN3193 4,096-token limit, compact biomechanical telemetry directly into `cadenceContext` under running economy rules:

```text
Current: 168 SPM, Baseline: 165 SPM, Deltas: +3. Turnover quickened with improved vertical efficiency. Form: 1.18m stride, 8.1cm osc, (VR: 6.9%).
```

### 5. UI Presentation & Explainer Sheets (`RunDetailView.swift`)

The metrics grid is organized into an **8-card balanced layout** (2 x 4 rows in portrait mode, avoiding an orphan 7th card):

| Row | Metric 1 | Metric 2 | Thematic Domain |
| :--- | :--- | :--- | :--- |
| **Row 1** | **Distance** | **Moving / Total Time** | Volume & Duration |
| **Row 2** | **Avg Pace** | **Avg HR** | Cardiovascular Intensity |
| **Row 3** | **Avg Cadence** | **Avg Stride** | Velocity Equation (`v = f * lambda`) |
| **Row 4** | **Vert. Osc.** | **Vertical Ratio** | Vertical Running Economy |

* **Unit Localization**: Stride length formats in meters (`m`) when `useMetricSystem == true`, and converts to feet (`m * 3.28084`) with unit `"ft"` when imperial. Vertical Ratio remains a dimensionless percentage (`%`) across both systems.
* **Rolling Baselines**: `baselineStrideLength` and `baselineVerticalRatio` compute duration-weighted 30-day averages strictly prior to the run date to drive relative delta comparison pills (`StatBox`).
* **On-Demand Historical Backfill**: When viewing historical runs with missing stride metrics, `RunDetailView` performs a single-run on-demand extraction via HealthKit, satisfying `AGENTS.md` zero-launch-repair constraints.
* **Explainer Sheets**: [`MetricDetailExplainer`](../Runalyst/Utilities/PaceFormatter.swift) includes comprehensive explainers for **Stride Length** and **Vertical Ratio**.

---

## Positive Consequences

* **Accurate Overstriding Attribution**: Runners are no longer penalized with overstriding warnings based purely on height or easy pace.
* **Vertical Ratio Availability**: Unlocks a standard, industry-recognized mechanical efficiency metric directly on workout summary screens.
* **Speed Profile Insights**: Gives runners visibility into whether their speed gains stem from cadence turnover or stride power.
* **Visual Symmetry**: The 8-card layout maintains balanced 2-column symmetry across device sizes.
* **Zero Breaking Migrations**: Additive optional properties allow seamless upgrades for existing SwiftData stores.

## Negative Consequences / Tradeoffs

* **Sensor Dependency**: Stride length requires an Apple Watch Series 6 or newer running watchOS 9+, or paired footpod sensors. Third-party workouts imported without dynamics leave these fields `nil`. All downstream code handles `Double?` gracefully.
* **Minor Ingestion Query Overhead**: Syncing historical runs queries one additional `HKQuantityTypeIdentifier`. Batching and 5s iteration spacing are preserved.

---

## Links and References

* [AGENTS.md](../../AGENTS.md) — Section 1 (SwiftData & Concurrency Architecture), Section 2 (FoundationModels Token Limits & Deterministic Directives), Section 3 (HealthKit & Data Management).
* [ADR 0003: Topological Signature Classification for Run Types](0003-topological-signature-classification-for-run-types.md).
* Apple Developer Documentation: [`HKQuantityTypeIdentifier.runningStrideLength`](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/3926079-runningstridelength).
