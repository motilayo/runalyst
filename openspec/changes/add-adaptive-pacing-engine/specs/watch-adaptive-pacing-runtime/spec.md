## ADDED Requirements

### Requirement: Standalone Workout Session Lifecycle
The `RunalystWatch` app SHALL run an `HKWorkoutSession` paired with `HKLiveWorkoutBuilder` using activity type `.running` and location `.outdoor` or `.indoor`, supporting start, pause, resume, and end, and SHALL save the finished `HKWorkout` to HealthKit so the existing iPhone ingestion pipeline picks it up unchanged. The runtime MUST operate with no iPhone or network connection.

#### Scenario: Phone absent
- **WHEN** the runner starts a session with the iPhone powered off
- **THEN** the session runs, adaptive pacing operates using the last cached calibration context (or fallback), and the workout is saved to HealthKit on end

#### Scenario: Pause freezes the engine
- **WHEN** the session is paused for 120 s
- **THEN** no ticks are forwarded to `AdaptivePacingCore` during the pause and elapsed time used by the core excludes the paused interval

### Requirement: 1 Hz Tick Alignment Adapter
`TelemetryEngine` (a Swift `actor`) SHALL collect the latest HealthKit quantities (heart rate, running speed, running power, stride length, ground contact time, vertical oscillation) and `CMPedometer` cadence, and SHALL emit exactly one `TelemetryTick` per elapsed second derived from `HKLiveWorkoutBuilder.elapsedTime`. A metric with no sample newer than 5 s SHALL be emitted as `nil`. `TelemetryEngine` MUST NOT contain filtering, thresholds, or pacing logic; it SHALL forward ticks to `AdaptivePacingCore` and publish the returned events and display state to the main actor.

#### Scenario: Stale metric
- **WHEN** the last ground contact time sample is 8 s old
- **THEN** the emitted tick has `groundContactTimeMs == nil`

#### Scenario: Hollow actor audit
- **WHEN** the reverse Air-Gap gate scans `RunalystWatch/`
- **THEN** no numeric physiological thresholds (e.g., `0.94`, `0.82`, `-0.06`, `165`, `260`) appear outside RunalystCore

### Requirement: Power-Conscious Motion Streaming
`MotionStreamService` SHALL stream `CMPedometer` cadence and pace for all sessions. It SHALL start 50 Hz `CMMotionManager` device-motion updates only when the session location is `.indoor`, and SHALL stop them on pause and end. On indoor sessions the IMU-derived step frequency SHALL be supplied in the tick as `imuCadenceSPM` for cross-checking; any reconciliation logic lives in RunalystCore.

#### Scenario: Outdoor session
- **WHEN** an outdoor session is running
- **THEN** `CMMotionManager.isDeviceMotionActive` is false

#### Scenario: Indoor session
- **WHEN** an indoor session is running and not paused
- **THEN** device motion updates are active at 50 Hz

### Requirement: Multimodal Feedback Delivery
`FeedbackDispatcher` SHALL map each `PacingEvent` to a haptic, an optional voice cue, and a UI accent, with color tokens bound to the causal metric:

| Event | Haptic (`WKHapticType`) | Voice cue | Accent token |
| :--- | :--- | :--- | :--- |
| `surge` | `.directionUp` | "Target pace up. Quicken your steps." | Electric Blue (Pace) |
| `recover` (`.efficiencyDrift` / `.heartRateCeiling`) | `.directionDown` | "Heart rate drifting. Ease the pace." | Neon Pink (Heart Rate) |
| `recover` (`.formBreakdown`) | `.retry` | "Cadence dropping. Short, quick steps." | Vibrant Green (Cadence) |
| `backOnTarget` | `.success` | none | Neutral |

Voice cues SHALL play through an `AVAudioSession` configured with category `.playback` and option `.duckOthers`, deactivated after each cue so external audio resumes. Cue strings SHALL be localized via `String(localized:)` and SHALL pass the Grounded Voice lexicon audit. Voice cues SHALL be disabled by default until the runner enables them; haptics are enabled by default. Haptics SHALL be serialized so two haptics never fire within 1.5 s of each other.

#### Scenario: Ducking
- **WHEN** a `recover` cue plays while a podcast is playing
- **THEN** the podcast volume ducks for the cue and resumes at full volume after it

#### Scenario: Voice cues disabled
- **WHEN** the runner has disabled voice cues in watch settings
- **THEN** only the haptic and accent are delivered

### Requirement: Hollow Pacing Gauge
The watch workout view SHALL render on a pure black background and bind exclusively to `PacingDisplayState`: current target pace, filtered pace, filtered HR, deviation classification, state label, and refractory countdown. All numeric text SHALL use `SF Pro Rounded` with `.monospacedDigit()`; primary controls (pause, end, voice toggle) SHALL have at least 44x44pt hit targets. The view MUST NOT compute deltas, percentages, or threshold comparisons.

#### Scenario: Calibrating display
- **WHEN** the core state is `calibrating`
- **THEN** the gauge shows a calibration progress label sourced from `PacingDisplayState` and no adjust accent

### Requirement: Battery Budget
With the display in always-on low-luminance mode and voice cues enabled, an outdoor 60-minute session SHALL consume less than 12% battery on Apple Watch Series 10 or Ultra 2, measured on device.

#### Scenario: On-device battery measurement
- **WHEN** a 60-minute outdoor session is run on a fully charged Series 10
- **THEN** the battery level drop recorded at session end is less than 12 percentage points
