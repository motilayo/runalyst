# Design: Watch Real-Time Pace Drift Alerts and Environment Preference Synchronization

## Context

During field testing on a 42-minute treadmill run, the runner noted that the watch app's visual gauge accurately rendered real-time pace deviation ("Too Slow", "On Target", "Too Fast"), but delivered zero haptics or audio cues until minute 37.

Analysis proved that `FeedbackDispatcher` only listens to `PacingEvent` emissions, which are currently reserved for macro physiological target adjustments (`.recover` and `.surge`). Because the run's directive was set to "Recovery", `.surge` was gated off, and `.recover` required continuous HR ceiling violations or efficiency drops, which only occurred at the end of the hard effort.

Furthermore, `StartRunView` on watchOS hardcodes `@State private var selectedLocation: PacingLocation = .outdoor`, ignoring the user's persisted `preferredWorkoutIsIndoor` preference.

## Goals / Non-Goals

**Goals:**
* Provide active multimodal feedback (directional haptic tap + optional concise voice cue) whenever the runner drifts off-pace for 12 consecutive seconds.
* Enforce a 30-second refractory cooldown between drift alerts to avoid alert fatigue.
* Preserve mathematical non-destructive invariance: drift alerts notify the runner to adjust their rhythm, but do NOT modify the baseline target pace (`currentTargetPaceSecondsPerKm`).
* Synchronize the user's `preferredWorkoutIsIndoor` preference from iPhone across `WatchConnectivity` to watchOS, automatically defaulting `StartRunView`'s environment selector to the user's preferred location.

**Non-Goals:**
* Modifying the physiological adaptation engine: `.recover` (safety ceiling) and `.surge` (progression) remain unchanged.
* Continuous metronome haptics on every stride: this design emits alert cues upon persistent deviation, not on every individual step.

## Decisions

### 1. Distinct `PacingEvent.paceDrift` vs Target Adjustments
* **Decision**: Add `case paceDrift(deviation: PaceDeviation, deltaSecondsPerKm: Int)` to `PacingEvent` in `RunalystCore`.
* **Rationale**: Decouples immediate rhythm coaching from physiological target modifications. A drift alert tells the runner "speed up or slow down to get back on your prescribed target", whereas `.recover` tells the runner "your physiology is failing, we are forcing your target to be slower".
* **Alternative Considered**: Re-using `.surge` and `.recover`. Rejected because `.surge`/`.recover` mutate `currentTargetPaceSecondsPerKm`, which would distort the runner's baseline workout structure during brief pace lags.

### 2. Time-Based Debounce (12s) and Cooldown (30s)
* **Decision**: Track `paceDriftContinuousSeconds` and `paceDriftCooldownRemainingSeconds` in `AdaptivePacingCore`. Trigger only when deviation persists for >= 12.0 seconds, followed by a 30.0-second quiet period.
* **Rationale**: 12 seconds provides enough smoothing to ignore momentary treadmill motor adjustments, elevation dips, or cornering, while still alerting the runner promptly. 30 seconds prevents wrist buzzing overload.
* **Alternative Considered**: Evaluated purely on the 10-second tick cycle. Rejected because a single tick at 10.1s could trigger an alert after just 1 second of deviation.

### 3. Feedback Specification Mapping
* **Decision**:
  * `.tooSlow`: Haptic `.directionUp`, voice cue: `"Pace dropping. Pick up rhythm."`, accent `.surgeBlue`.
  * `.tooFast`: Haptic `.directionDown`, voice cue: `"Pace high. Ease into rhythm."`, accent `.recoverOrange`.
  * Return to target: Emits `.backOnTarget` when re-entering target band, triggering `.success` haptic.
* **Rationale**: Leverages Apple watchOS native directional haptics (`.directionUp` feels like an upward tap; `.directionDown` feels like a downward brake tap).

### 4. Preferred Location Sync in `WatchPacingContext`
* **Decision**: Add `isIndoorPreferred: Bool?` to `WatchPacingContext` and `WatchResolvedSessionConfig`.
* **Rationale**: `WatchPacingContext` is already transferred via `WCSession.updateApplicationContext` and cached in `WatchContextStore`. Adding this field requires zero new network transports or schema migrations.

## Technical Architecture & Core-First Handshake

```
+--------------------------------------------------------------+
| Runalyst (iOS Foundry)                                       |
| - WatchConnectivityManager: Injects isIndoorPreferred        |
+------------------------------+-------------------------------+
                               | WCSession ApplicationContext
                               v
+--------------------------------------------------------------+
| RunalystWatch (watchOS Foundry)                              |
| - WatchContextStore: Resolves preferredLocation (.indoor)    |
| - StartRunView: selectedLocation defaults to preferredLocation|
| - TelemetryEngine: Feeds 1Hz TelemetryTick to core           |
+------------------------------+-------------------------------+
                               | Pure TelemetryTick
                               v
+--------------------------------------------------------------+
| RunalystCore (Sans-I/O Reference Core)                       |
| - AdaptivePacingCore:                                        |
|     evaluatePaceDriftAlert() -> PacingEvent.paceDrift         |
|     12s debounce + 30s cooldown                              |
|     Non-destructive (currentTarget untouched)                |
+------------------------------+-------------------------------+
                               | PacingEvent.paceDrift
                               v
+--------------------------------------------------------------+
| RunalystWatch / FeedbackDispatcher                           |
| - Plays WKHapticType.directionUp / .directionDown            |
| - Speaks grounded voice cue via AVAudioSession               |
+--------------------------------------------------------------+
```

## Risks / Trade-offs

* **[Risk] Jitter on GPS outdoors causing false alerts** -> *Mitigation*: The 30-second short-window filtered speed stats and the 12-second continuous debounce filter out momentary GPS multipath jumps.
* **[Risk] Core file size inflation** -> *Mitigation*: Place drift tracking and trigger evaluation in `AdaptivePacingCore+Triggers.swift` (currently 208 LOC) to keep `AdaptivePacingCore.swift` well under the 500-LOC modularity guideline.
* **[Risk] High haptic density distracting the runner** -> *Mitigation*: 30-second refractory quiet period ensures at most 2 alerts per minute even in worst-case divergence.
