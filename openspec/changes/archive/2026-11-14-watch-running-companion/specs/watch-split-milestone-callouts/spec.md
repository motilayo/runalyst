# Capability Spec: watch-split-milestone-callouts

## ADDED Requirements

### Requirement: Distance Split Boundary Detection
The system SHALL monitor cumulative workout distance and detect when each whole distance unit (kilometer or mile) is crossed.

#### Scenario: Runner crosses 1 km boundary
- **WHEN** cumulative distance transitions from 995 meters to 1005 meters
- **THEN** the system SHALL emit a `.splitMilestone(splitIndex: 1, splitPaceSecondsPerKm: pace)` event
- **AND** update the last completed split index to 1.

### Requirement: Split Milestone Multimodal Feedback
The watchOS `FeedbackDispatcher` SHALL announce split completions with haptics and spoken voice cues.

#### Scenario: Split completion announcement
- **WHEN** a `.splitMilestone` event is dispatched
- **THEN** `FeedbackDispatcher` SHALL play a `.success` haptic tap
- **AND** if voice cues are enabled, speak the split index and formatted split pace.
