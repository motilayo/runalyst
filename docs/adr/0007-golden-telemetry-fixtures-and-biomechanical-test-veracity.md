# ADR-0007: Golden Telemetry Fixtures and Biomechanical Test Veracity

* Status: Accepted
* Date: 2026-09-28
* Deciders: Antigravity Agent, Joshua Agboola
* Consulted: Engineering & Architecture Guidelines (`AGENTS.md`)
* Informs: `FramboiseEngine.swift`, `WorkoutTelemetryVeracityTests.swift`, `GoldenTelemetryFixtures.swift`

## Context and Problem Statement

Prior to v2.2.1, the Runalyst test suite maintained a 100% pass rate while masking profound real-world failure modes. Unit tests relied on synthetic "metronomic" step functions—such as work intervals at 180 SPM / 172 BPM alternating with recovery periods at 135 SPM / 138 BPM. These tests encoded idealized physical assumptions (instantaneous 45 SPM cadence drops, instant 34 BPM heart rate declines in 30 seconds) rather than authentic human physiology and Apple Watch sensor realities.

When authentic Apple Watch workout streams were introduced, the synthetic test suite was proven false:
1. **Active Recovery & Cardiac Lag**: Real runners jog between reps (5–7 SPM cadence drop, 2–4 BPM heart rate decrease due to EPOC).
2. **Stride-Driven Surges**: Runners often increase velocity by 90–135 s/km primarily by opening stride length (0.85m -> 1.15m) with modest cadence increases.
3. **Window Collapse on Long Reps**: A 10-bucket (5-minute) centered rolling baseline window collapsed inside 5.5-minute interval reps, causing normal +/- 0.5 SPM sensor noise to fragment a single rep into alternating phantom phases.
4. **Velocity Gate Requirement**: Multi-signal corroboration permitted high cadence and high HR without a positive pace delta, risking false positive interval cycles on steep hill climbs where the runner slowed down.
5. **Progressive Monotonic Acceleration**: In monotonic progression runs, each faster split could be paired with the slower split before it, fabricating "oscillation" unless low-variance progression (CV < 0.09) gated intermittent classification.

## Decision Drivers

1. **Empirical Ground-Truth Calibration**: Test fixtures must replay authentic time-series bucket streams rather than synthetic block steps.
2. **Noise Resilience**: Biomechanical classification algorithms must remain 100% stable under realistic sensor jitter (+/- 1.2 SPM cadence, +/- 1.5 BPM HR, +/- 3.0 s/km pace).
3. **Adversarial Falsification**: The test suite must actively test boundary conditions through mutation testing (e.g. flattening pace surges to prove velocity corroboration is not trivially bypassed).
4. **Deterministic Repeatability**: Noise injection must be seed-based and deterministic to eliminate flaky test runs.

## Decision Outcome

We created the **Golden Telemetry Test Veracity Framework**:

1. **`WorkoutTelemetryFixture` & `BucketTelemetrySample`**: Codable schema representing discrete, high-fidelity Apple Watch workout telemetry windows with JSON serialization.
2. **`GoldenTelemetryFixtures`**: A curated library of authentic golden datasets:
   - `authenticIntervals31Min`: Authentic 31:24 Apple Watch workout (active recovery jogs, cardiac lag, stride extension surges, terminal rep).
   - `hillySteadyAerobicRun`: Rolling terrain steady run (pace fluctuates by 140 s/km due to hills, but cadence and HR reflect steady effort; verifies absence of false positive interval cycles).
   - `monotonicProgressionRun`: Monotonic quintile pace acceleration with CV < 0.09.
   - `trueFartlekIrregularRun`: High-frequency 15s-window unstructured fartlek with 5 irregular surges (cycle regularity < 0.65).
   - `fadingCadenceFatigueRun`: 40-minute steady run with 7 SPM turnover decay and +12 BPM cardiac drift modeling acute biomechanical fatigue.
3. **`TelemetryNoiseInjector`**: Deterministic Linear Congruential Generator (LCG) simulating real Apple Watch sensor jitter.
4. **`WorkoutTelemetryVeracityTests`**: 11 new automated veracity tests verifying:
   - Authentic golden fixture classification
   - Multi-seed noise resilience under sensor jitter
   - Adversarial pace flattening mutation
   - Adversarial high-variance progression rejection (CV >= 0.09)
   - Biomechanical fatigue sensitivity (turnover decay >= 3.5 SPM, cardiac drift >= 5.0 BPM)
   - JSON serialization round-trip

### Engine Enhancements Prompted by Veracity Testing

- **Baseline Window Expansion**: Widened `windowSize` from 10 to 20 buckets in `FramboiseEngine.extractOscillationCycles`, preventing window collapse inside long reps.
- **Phase Glitch Debouncing**: Merges sub-20s phase chatter into surrounding contiguous phases of the same type.
- **Velocity Corroboration Gate**: Multi-signal corroboration (`corroborationScore >= 2`) strictly requires `paceDiff >= 5.0` s/km, preventing uphill slogs from qualifying as intervals.
- **Terminal Recovery Fallback**: In `extractOscillationCycles`, if succeeding recovery is invalid or absent, terminal surges reliably pair with the preceding recovery.
- **Low-Variance Progression Priority**: Evaluates `isProgression` (CV < 0.09 with monotonic quintiles) before intermittent oscillation gating.

## Consequences

### Positive Consequences
- **Test Integrity**: Test suite now tests against physiological reality, eliminating the "happy path" circular validation trap.
- **Robust Algorithms**: `FramboiseEngine` is now provably resilient to Apple Watch sensor noise and long interval durations.
- **Regression Immunity**: Any future algorithm modification that breaks velocity corroboration, noise tolerance, or progression boundaries will immediately fail `WorkoutTelemetryVeracityTests`.

### Negative Consequences
- **Test Execution Overhead**: Running full sensor jitter simulations across multiple seeds slightly increases test suite execution time (~1.5s additional wall time).

## Links and References
- Supersedes synthetic interval assumptions from `FramboiseEngineTests.swift`
- Implements validation framework for [ADR-0006](0006-multi-signal-topological-interval-segmentation-and-progression-guardrails.md)
