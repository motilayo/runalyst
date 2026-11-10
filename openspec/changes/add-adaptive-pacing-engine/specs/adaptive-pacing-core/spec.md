## ADDED Requirements

### Requirement: Sans-I/O Purity and Explicit Time
All adaptive pacing types in RunalystCore SHALL import only `Foundation`, SHALL accept time exclusively as `elapsedSeconds: TimeInterval` measured from session start, and MUST NOT call `Date()`, `Calendar.current`, or any wall-clock API. All public types SHALL be `Sendable` value types.

#### Scenario: Determinism across replays
- **WHEN** the same ordered sequence of `TelemetryTick` values and the same `AthleteCalibrationProfile` are fed to two fresh `AdaptivePacingCore` instances
- **THEN** both instances emit byte-identical sequences of `PacingEvent` values and `PacingDisplayState` snapshots

#### Scenario: Air-Gap audit
- **WHEN** `./assay.sh` runs the Directory Air-Gap and Determinism gates
- **THEN** no file in `RunalystCore/Sources/RunalystCore/` matching `Pacing*` or `AthleteCalibration*` imports HealthKit, CoreMotion, WatchKit, SwiftData, SwiftUI, CoreML, or OSLog, and none contain `Date()`

### Requirement: Dropout-Aware 1D Kalman Conditioning
`KalmanFilter1D` SHALL smooth heart rate and running speed independently using a scalar random-walk model with configurable process noise Q and measurement noise R (defaults: HR Q = 0.1, R = 4.0; speed Q = 0.02, R = 0.25). The first valid measurement SHALL seed the estimate directly (no ramp from 0). A missing or physiologically invalid measurement (HR outside 30...230 BPM, speed outside 0...12 m/s) SHALL trigger a predict-only step that grows the error covariance by Q without moving the estimate.

#### Scenario: Seeding without ramp
- **WHEN** the first HR measurement is 142 BPM
- **THEN** the filtered HR output for that tick is 142 BPM

#### Scenario: Artifact rejection
- **WHEN** a stable 150 BPM stream receives a single 215 BPM wrist-artifact spike
- **THEN** the filtered HR for that tick rises by less than 15 BPM and returns within 2 BPM of 150 within 10 ticks

#### Scenario: Dropout handling
- **WHEN** HR is absent for a tick
- **THEN** the filtered HR equals the previous estimate and the tick is marked `hrValid == false`

### Requirement: Fixed-Capacity Ring Buffer and Rolling Windows
`TelemetryRingBuffer` SHALL store conditioned 1 Hz ticks in a flat, fixed-capacity buffer (capacity 900 ticks) with O(1) append and SHALL expose rolling statistics (mean, standard deviation, valid-sample coverage) over a 30 s short window and a 180 s long window for filtered HR, filtered speed, cadence, power, ground contact time, and vertical oscillation. A window statistic SHALL report `nil` when valid-sample coverage is below 80%.

#### Scenario: Window coverage gate
- **WHEN** 10 of the last 30 ticks have no cadence
- **THEN** the 30 s cadence window statistic is `nil`

#### Scenario: Constant memory
- **WHEN** 7,200 ticks (2 hours) are appended
- **THEN** buffer storage remains 900 ticks and the oldest retained tick is tick 6,301

### Requirement: Efficiency Factor Drift With Grade Guard
`EfficiencyDriftTracker` SHALL compute the Efficiency Factor over the 180 s long window as power / filtered HR when power is available for at least 80% of the window, otherwise as speed / filtered HR. It SHALL lock `EF_0` as the mean EF over elapsed time 300...600 s and report `ΔEF = (EF_t - EF_0) / EF_0`. The EF source (power or speed) used for `EF_0` SHALL be the same source used for `EF_t`; if the source becomes unavailable, `ΔEF` SHALL be `nil`. When EF is speed-based and the absolute grade over the short window exceeds 1.5%, `ΔEF` SHALL be reported as `nil` (suspended). On `.indoor` sessions, speed-based EF SHALL NOT be used at all: if power is unavailable indoors, `ΔEF` SHALL be `nil` for the whole session (wrist-derived treadmill speed and unknown incline make speed/HR unreliable); the HR ceiling and form breakdown triggers remain active.

#### Scenario: Cardiac drift detected
- **WHEN** EF_0 is 1.80 W/BPM and the current long-window EF is 1.68 W/BPM
- **THEN** `ΔEF` is approximately -0.067

#### Scenario: Hill climb without power does not fake drift
- **WHEN** EF is speed-based and the runner climbs a 4% grade causing speed/HR to drop 9%
- **THEN** `ΔEF` is `nil` for the duration of the climb and no RECOVER transition is triggered by EF

#### Scenario: Indoor without power
- **WHEN** an indoor session has no running power samples
- **THEN** `ΔEF` is `nil` for the entire session and only HR ceiling and form breakdown can trigger RECOVER

#### Scenario: Source mismatch
- **WHEN** EF_0 was locked from power and power drops out for 3 minutes
- **THEN** `ΔEF` is `nil` rather than mixing a speed-based EF against a power-based baseline

### Requirement: Biomechanical Degradation Index
`BiomechanicalDegradationIndex` SHALL lock `GCT_0` and `Cadence_0` as the means over elapsed 300...600 s and compute `BDI_t = (GCT_t / GCT_0) * (Cadence_0 / Cadence_t) - 1` over the 30 s short window. It SHALL also expose the raw components `gctDeltaFraction` and `cadenceDropSPM`. A `formBreakdown` flag SHALL be true only when `gctDeltaFraction > 0.07` AND `cadenceDropSPM > 4`. When ground contact time is unavailable (e.g., indoor without footpod), BDI and `formBreakdown` SHALL be `nil` / false.

#### Scenario: Form breakdown
- **WHEN** GCT_0 = 240 ms, Cadence_0 = 168 SPM, and the short window shows GCT 260 ms, cadence 163 SPM
- **THEN** `gctDeltaFraction` ≈ 0.083, `cadenceDropSPM` = 5, `formBreakdown` is true, and BDI ≈ 0.117

#### Scenario: Relative, not absolute
- **WHEN** a runner's calibrated baseline is GCT 275 ms at 158 SPM and those values persist unchanged
- **THEN** `formBreakdown` is false (no hardcoded `gct > 260 && cadence < 165` rule exists)

### Requirement: Calibrating State
`AdaptivePacingCore` SHALL start in `calibrating` and SHALL NOT emit target adjustments while calibrating. Calibration SHALL complete at elapsed 600 s (0...300 s warm-up discarded, 300...600 s baseline window) if HR and speed valid-sample coverage in the baseline window are each at least 80%. If coverage fails, calibration SHALL extend in 60 s steps up to 900 s; if still failing, the core SHALL enter `tracking` with `adjustmentsEnabled == false` (monitor-only) for the rest of the session.

#### Scenario: Normal calibration
- **WHEN** a runner runs steadily with clean sensors for 600 s
- **THEN** the state becomes `tracking` at tick 600 with EF_0, GCT_0, Cadence_0, and `Pace_0` locked

#### Scenario: Persistent sensor failure
- **WHEN** HR coverage stays at 50% through elapsed 900 s
- **THEN** the state is `tracking` with `adjustmentsEnabled == false` and no SURGE or RECOVER is ever emitted

### Requirement: Recover Transition
From `tracking`, evaluated every 10 s, the core SHALL transition to `recover` and emit a target slowdown when any of the following holds: (a) `ΔEF <= -0.06`; (b) filtered HR exceeds `0.94 * maxHR` continuously for more than 30 s; (c) `formBreakdown` is true for two consecutive evaluations. The slowdown magnitude SHALL be 3% of the current target pace for a single trigger of (a) or (c), 5% for (b), and 8% when two or more triggers hold simultaneously, each then capped by the step limit. RECOVER SHALL be evaluated before SURGE, and RECOVER SHALL be permitted regardless of session intent.

#### Scenario: HR ceiling sustained
- **WHEN** maxHR is 190 and filtered HR stays above 178.6 BPM for 35 s at a target of 300 s/km
- **THEN** a `recover` event is emitted with reason `.heartRateCeiling` and target delta +10 s/km (5% = 15 s/km, capped at 10)

#### Scenario: HR ceiling brief spike
- **WHEN** filtered HR exceeds 0.94 * maxHR for 25 s then drops below
- **THEN** no `recover` event is emitted

#### Scenario: Form breakdown reason
- **WHEN** `formBreakdown` is true for two consecutive 10 s evaluations and `ΔEF` is -0.02
- **THEN** a `recover` event is emitted with reason `.formBreakdown`

### Requirement: Surge Transition and Protection Gate
From `tracking`, the core SHALL transition to `surge` and emit a target speed-up of 2% of current target pace (capped by the step limit) only when ALL hold over the latest evaluation: filtered HR < `0.82 * maxHR`; `ΔEF >= -0.01`; 30 s cadence standard deviation < 2.0 SPM; long-window power / HR >= the profile's `powerToHRTopQuartile`; session intent is `steady`, `tempo`, or `progression`; `subjectiveDistress == false`; and the profile is not a fallback profile. If power is unavailable the power condition SHALL be treated as unmet.

#### Scenario: Recovery day lockout
- **WHEN** intent is `recovery` and every physiological SURGE condition is met
- **THEN** no `surge` event is emitted

#### Scenario: Fallback profile lockout
- **WHEN** the watch has no calibration profile from iPhone and is using the fallback profile
- **THEN** no `surge` event is emitted for the session

#### Scenario: Valid surge
- **WHEN** intent is `tempo`, target 270 s/km, HR is 0.78 * maxHR, `ΔEF` is +0.01, cadence σ is 1.4 SPM, and power/HR is above the top quartile
- **THEN** a `surge` event is emitted with target delta -5 s/km (2% = 5.4, rounded to nearest whole second)

### Requirement: Hysteresis, Step, and Cumulative Damping
After any adjustment, the core SHALL enter a 90 s refractory period during which no further adjustment is emitted, then return to `tracking`. Each adjustment SHALL be capped at 10 s/km in magnitude. The cumulative target SHALL remain within `Pace_target_original * (1 +/- 0.12)`; an adjustment that would exceed the cap SHALL be truncated to the cap and, if the truncated delta is 0, SHALL NOT be emitted.

#### Scenario: Cooldown blocks oscillation
- **WHEN** a `recover` is emitted at elapsed 1,200 s and RECOVER conditions persist
- **THEN** the next possible adjustment is at the first 10 s evaluation at or after elapsed 1,290 s

#### Scenario: Cumulative cap
- **WHEN** the original target is 300 s/km and four consecutive `recover` events of +10 s/km are triggered
- **THEN** the target progresses 310, 320, 330, 336 s/km and no further slowdown event is emitted

### Requirement: Back-On-Target and Display State
The core SHALL emit `backOnTarget` once per adjustment when the 30 s filtered pace first enters the tolerance band `target +/- max(5 s/km, 2% of target)` after that adjustment. Each tick SHALL produce a `PacingDisplayState` containing state, current target pace, filtered pace, filtered HR, deviation classification (`onTarget`, `tooFast`, `tooSlow`), refractory seconds remaining, and the most recent event reason, so views perform no arithmetic.

#### Scenario: Confirmation after slowdown
- **WHEN** a `recover` raised the target to 315 s/km and the runner's 30 s pace reaches 318 s/km
- **THEN** exactly one `backOnTarget` event is emitted

### Requirement: Athlete Calibration Derivation
`AthleteCalibrationCore` SHALL derive `AthleteCalibrationProfile` from historical inputs: `maxHR` = highest 60 s sustained HR observed in the last 180 days of buckets, falling back to `208 - 0.7 * age`, then to 190; `restingHR` = median of supplied resting HR samples from the last 30 days, else `nil`; `powerToHRTopQuartile` = 75th percentile of steady-run bucket power/HR, else `nil`. The profile SHALL carry `isFallback == true` when `maxHR` came from a non-observed source.

#### Scenario: Observed max HR
- **WHEN** history contains a 60 s sustained peak of 187 BPM and the runner is 40
- **THEN** `maxHR` is 187 and `isFallback` is false

#### Scenario: Age fallback
- **WHEN** history is empty and age is 40
- **THEN** `maxHR` is 180 and `isFallback` is true

### Requirement: Real-Time Budget
A single `AdaptivePacingCore.ingest(_:)` call SHALL complete in under 0.1 ms on the CI host (median over 10,000 ticks) and SHALL perform no heap allocation growth after the ring buffer is full.

#### Scenario: Crucible timing
- **WHEN** the crucible test replays a 2-hour synthetic session (7,200 ticks)
- **THEN** the median per-tick ingest time is under 0.1 ms
