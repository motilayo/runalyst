## ADDED Requirements

### Requirement: Phone-Side Calibration Context Publishing
The iOS app SHALL build a `WatchPacingContext` (an `AthleteCalibrationProfile` from `AthleteCalibrationCore` plus today's `PacingSessionIntent` derived from the existing `SessionSynthesisCore` prescription) and publish it via `WCSession.updateApplicationContext` after each successful HealthKit sync and whenever today's prescription changes. `WatchCalibrationBridge` SHALL be a hollow adapter: encoding and transport only, no physiological math.

#### Scenario: Publish after sync
- **WHEN** a HealthKit sync completes and the watch app is installed and paired
- **THEN** `updateApplicationContext` is called once with the encoded `WatchPacingContext`

#### Scenario: Watch not installed
- **WHEN** `WCSession.isWatchAppInstalled` is false
- **THEN** no context is sent and no error is surfaced to the runner

### Requirement: Session Intent Mapping
`PacingSessionIntent` SHALL contain `targetPaceSecondsPerKm: Int?`, `intent` (one of `recovery`, `easyAerobic`, `steady`, `tempo`, `progression`, `intervals`), `subjectiveDistress: Bool`, and `validForDay` (an ISO-8601 calendar date string). The mapping from a `SessionSynthesisCore` prescription to `PacingSessionIntent` SHALL live in RunalystCore. For `intervals`, adaptive pacing SHALL be disabled (monitor-only), because interval structure is owned by WorkoutKit.

#### Scenario: Recovery prescription
- **WHEN** today's prescription is Easy Aerobic Recovery
- **THEN** the published intent is `recovery` and SURGE is locked out on the watch

#### Scenario: Interval prescription
- **WHEN** today's prescription is an interval session
- **THEN** the watch runs with `adjustmentsEnabled == false`

### Requirement: Watch-Side Context Caching and Fallback
The watch SHALL persist the most recently received `WatchPacingContext` locally and use it at session start. If no context exists, or `validForDay` does not match the session's local date, the watch SHALL use the cached profile (if any) with intent `steady` and the target pace chosen by the runner on the watch (default option "Just Run": `targetPaceSecondsPerKm == nil`, so the core adapts around `Pace_0`), else the fallback profile (`maxHR` from `208 - 0.7 * age` if age is readable from HealthKit, else 190; `isFallback == true`). With a fallback profile SURGE SHALL be disabled; RECOVER SHALL remain enabled.

#### Scenario: Stale intent
- **WHEN** the cached context's `validForDay` is yesterday
- **THEN** the cached profile is reused, the intent is ignored, and the runner is offered a target pace picker defaulting to "Just Run"

#### Scenario: First launch without phone
- **WHEN** the watch app has never received a context
- **THEN** the session uses the fallback profile, SURGE never fires, and RECOVER triggers remain active

### Requirement: Versioned Context Encoding
`WatchPacingContext` SHALL be encoded as `Codable` JSON with an integer `schemaVersion` field. A watch receiving an unknown higher `schemaVersion` SHALL ignore the payload and keep its existing cached context.

#### Scenario: Forward-incompatible payload
- **WHEN** the watch receives a context with `schemaVersion` greater than it supports
- **THEN** the payload is discarded and the previous cache is retained
