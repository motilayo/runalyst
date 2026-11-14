# watch-live-cadence-nudge Specification

## Purpose
TBD - created by archiving change watch-running-companion. Update Purpose after archive.
## Requirements
### Requirement: Cadence Baseline Locking
The system SHALL lock a target cadence upon completion of the calibration window in `AdaptivePacingCore` if no explicit prescription target was provided.

#### Scenario: Prescription cadence target takes precedence
- **WHEN** `intent.targetCadenceSPM` is provided (e.g., 160 SPM)
- **THEN** `currentTargetCadenceSPM` SHALL equal 160 SPM upon calibration lock.

#### Scenario: Observed mean cadence locked when no prescription provided
- **WHEN** `intent.targetCadenceSPM` is nil
- **AND** calibration completes with valid cadence telemetry
- **THEN** `currentTargetCadenceSPM` SHALL equal the rounded mean cadence from the baseline window (clamped to at least 150 SPM).

### Requirement: Debounced Cadence Drop Monitoring
The system SHALL monitor consecutive continuous seconds where short-window filtered cadence drops more than 6 SPM below `currentTargetCadenceSPM`.

#### Scenario: Cadence drops below threshold for debounce duration
- **WHEN** the runner's cadence remains > 6 SPM below target continuously for at least 12 seconds
- **AND** the core is outside any active cadence drift cooldown interval
- **THEN** the system SHALL emit a `.cadenceDrift(currentCadenceSPM:targetCadenceSPM:deltaSPM:)` event
- **AND** reset the consecutive cadence drop accumulation timer.

#### Scenario: Brief cadence dip returns to normal
- **WHEN** the runner's cadence drops for 5 seconds and returns within 6 SPM of target
- **THEN** the accumulation timer SHALL reset to 0 with no alert emitted.

### Requirement: Cadence Nudge Multimodal Feedback
The watchOS `FeedbackDispatcher` SHALL map `.cadenceDrift` events to rhythmic haptics and voice cues.

#### Scenario: Cadence drop triggers multimodal feedback
- **WHEN** a `.cadenceDrift` event is dispatched
- **THEN** `FeedbackDispatcher` SHALL trigger a rhythmic double-tap haptic
- **AND** if voice cues are enabled, speak "Cadence dropping. Quicken your steps."

