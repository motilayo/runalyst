# watch-pace-drift-alerts Specification

## Purpose
TBD - created by archiving change watch-pace-drift-alerts. Update Purpose after archive.
## Requirements
### Requirement: Debounced Continuous Pace Deviation Monitoring
The system SHALL monitor consecutive continuous seconds spent in `.tooSlow` and `.tooFast` states during active tracking in `AdaptivePacingCore`.

#### Scenario: Continuous slow pace breaches debounce threshold
- **WHEN** the runner's filtered pace remains in `.tooSlow` continuously for at least 12 seconds
- **AND** the core is outside any active pace drift cooldown interval
- **THEN** the system SHALL emit a `.paceDrift(deviation: .tooSlow, deltaSecondsPerKm: delta)` event
- **AND** reset the consecutive `.tooSlow` accumulation timer.

#### Scenario: Continuous fast pace breaches debounce threshold
- **WHEN** the runner's filtered pace remains in `.tooFast` continuously for at least 12 seconds
- **AND** the core is outside any active pace drift cooldown interval
- **THEN** the system SHALL emit a `.paceDrift(deviation: .tooFast, deltaSecondsPerKm: delta)` event
- **AND** reset the consecutive `.tooFast` accumulation timer.

#### Scenario: Momentary pace fluctuation does not trigger alert
- **WHEN** the runner enters `.tooSlow` for 6 seconds and then returns to `.onTarget`
- **THEN** the system SHALL reset the `.tooSlow` accumulation timer to 0
- **AND** emit no `.paceDrift` event.

### Requirement: Pace Drift Alert Cooldown & Non-Destructive Invariance
The system SHALL enforce a refractory cooldown of at least 30 seconds following a `.paceDrift` event before another drift alert can be emitted. Pace drift alerts SHALL NOT modify `currentTargetPaceSecondsPerKm` or `originalTargetPaceSecondsPerKm`.

#### Scenario: Cooldown suppresses rapid repeated alerts
- **WHEN** a `.paceDrift` event was emitted 15 seconds ago
- **AND** the runner remains in `.tooSlow` for an additional 12 consecutive seconds
- **THEN** the system SHALL suppress emission of a new `.paceDrift` event until the 30-second cooldown expires.

#### Scenario: Target pace preservation during drift alert
- **WHEN** a `.paceDrift` event is emitted
- **THEN** `currentTargetPaceSecondsPerKm` SHALL remain identical to its pre-event value.

### Requirement: Multimodal Drift Feedback Mapping
The watchOS `FeedbackDispatcher` SHALL map `.paceDrift` events to directional haptics and grounded voice cues.

#### Scenario: Feedback for falling behind target pace
- **WHEN** a `.paceDrift(deviation: .tooSlow, ...)` event is dispatched
- **THEN** `FeedbackDispatcher` SHALL trigger a `.directionUp` haptic tap
- **AND** if voice cues are enabled, speak "Pace dropping. Pick up rhythm."

#### Scenario: Feedback for exceeding target pace
- **WHEN** a `.paceDrift(deviation: .tooFast, ...)` event is dispatched
- **THEN** `FeedbackDispatcher` SHALL trigger a `.directionDown` haptic tap
- **AND** if voice cues are enabled, speak "Pace high. Ease into rhythm."

