# watch-treadmill-live-reliability Specification

## Purpose
Indoor treadmill Kalman wrist-speed damping, outlier clamping, relative baseline lock-in, and HR/IMU-cadence/Power effort anchoring on Apple Watch.

## Requirements
### Requirement: Live Indoor Speed Damping & Outlier Clamping
When `location == .indoor`, `PacingSignalCore` and `AdaptivePacingCore` SHALL damp wrist-accelerometer speed jitter and reject brief arm-swing artifacts before updating display pace or triggers.

#### Scenario: Brief console-tap or water-bottle speed artifact is clamped
- **WHEN** `location == .indoor` and instantaneous `speedMetersPerSecond` deviates by more than `25%` from the trailing `30s` median speed (e.g., grabbing treadmill rails or wiping sweat)
- **THEN** `AdaptivePacingCore` MUST clamp the indoor speed sample within `[0.75 * median, 1.25 * median]` and apply indoor Kalman noise parameters (`Q = 0.01, R = 0.64`) so transient drops do not trigger false drift events.

---

### Requirement: Effort & IMU Cadence Anchoring on Treadmill
When `location == .indoor`, adaptive block triggers and pace-drift alerts SHALL prioritize Heart Rate, `50 Hz` IMU Cadence, and Power over uncalibrated wrist accelerometer pace.

#### Scenario: Outdoor-vs-belt calibration offset does not trigger false pace-drift nudges
- **WHEN** `location == .indoor`, iPhone synced an outdoor `targetPaceSecondsPerKm`, and Watch wrist speed reads slower/faster by `5–15%` while Heart Rate and `50 Hz` IMU cadence are already inside the session's target zone
- **THEN** `AdaptivePacingCore` MUST NOT emit `"too slow"` or `"too fast"` `paceDrift` tactile bursts based on raw wrist speed alone
- **AND** `EfficiencyDriftTracker` MUST continue excluding `.speed` EF fallback when `location == .indoor`.

#### Scenario: Calibration locks relative treadmill baseline
- **WHEN** `location == .indoor` completes the `300`-second calibration window
- **THEN** `AdaptivePacingCore` locks the observed treadmill wrist speed as the relative baseline for block speed-change detection while driving `.thresholdSurge` and `.effortEase` decisions primarily from HR, IMU cadence, and Power.
