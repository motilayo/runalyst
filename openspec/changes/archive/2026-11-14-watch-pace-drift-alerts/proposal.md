# Proposal: Watch Real-Time Pace Drift Alerts and Environment Preference Synchronization

## Why

During real-world live testing of the watchOS companion app on a 42-minute treadmill run, the runner observed that the visual gauge accurately reflected real-time pace deviation ("Too Slow", "On Target", "Too Fast"), but the app provided zero haptic or voice feedback until the final 5 minutes. 

Investigation revealed that multimodal feedback is currently wired exclusively to macro physiological target adjustments (`.recover` and `.surge`), which are muted during calibration (first 10–15 minutes) and gated off under recovery intents. Runners expecting active pacing cues while running without looking at their wrist receive no sensory feedback when drifting off-pace. Additionally, `StartRunView` on watchOS hardcodes its environment picker to `.outdoor`, ignoring the user's persisted `preferredWorkoutIsIndoor` preference.

This change introduces debounced real-time pace drift haptics to active tracking, and synchronizes the user's preferred workout environment (indoor vs. outdoor) across WatchConnectivity.

## What Changes

* **Real-Time Pace Drift Detection (`RunalystCore`)**: Track continuous seconds spent in `.tooSlow` and `.tooFast` states within `AdaptivePacingCore`. When a runner stays off-pace for a configurable debounce window (e.g., 12 consecutive seconds) outside of a cooldown interval, emit a non-destructive `.paceDrift(deviation:deltaSecondsPerKm:)` event.
* **Multimodal Drift Feedback (`RunalystWatch`)**: Map `.paceDrift` events in `FeedbackDispatcher` to distinct, lightweight directional haptics (`.directionUp` for too slow, `.directionDown` for too fast) and grounded voice cues ("Pace dropping. Pick up rhythm." / "Pace high. Ease into rhythm.") without modifying the baseline target pace.
* **Environment Preference Synchronization (`Runalyst` & `RunalystWatch`)**: Extend `WatchPacingContext` (or application context payload) to include `isIndoorPreferred: Bool`.
* **Indoor Default on Watch (`RunalystWatch`)**: Bind `StartRunView.selectedLocation` initialization to `WatchContextStore.shared.preferredLocation` so indoor treadmill runners do not need to manually toggle from Outdoor to Indoor on every session.

## Capabilities

### New Capabilities
- `watch-pace-drift-alerts`: Defines debounced continuous pace deviation monitoring, cooldown limits, and directional haptic/audio cue dispatching on watchOS without altering physiological target pace.
- `watch-environment-preference-sync`: Defines synchronization of user indoor/outdoor preferences from iOS `@AppStorage` to watchOS `WatchContextStore` and automatic binding in `StartRunView`.

### Modified Capabilities
<!-- None: existing core adaptive pacing and calibration handoff requirements remain untouched -->

## Impact & Air-Gap Assessment

* **RunalystCore (Sans-I/O Core)**:
  * Updates `AdaptivePacingCore` and `PacingEvent` to track continuous deviation duration and emit `.paceDrift`.
  * Strict Air-Gap: Pure functional Swift, zero Apple framework imports, zero wall-clock time (`Date()`).
  * File mass: `AdaptivePacingCore.swift` is currently ~480 LOC; new trigger logic will be partitioned cleanly into `AdaptivePacingCore+Triggers.swift` (currently 208 LOC) to preserve the <= 500 LOC modularity guideline.
* **RunalystWatch (Foundry Companion)**:
  * Updates `FeedbackDispatcher` to support `.paceDrift` feedback specs.
  * Updates `StartRunView` to initialize with the synced environment preference.
* **Runalyst (iOS Foundry)**:
  * Includes `preferredWorkoutIsIndoor` in the `WatchConnectivityManager` pacing context payload.
* **Crucible Verification**:
  * Unit tests in `AdaptivePacingCoreTests.swift` validating 12s debounce timing, cooldown refractory limits, and non-destructive event emission.
  * `./assay.sh` verification (Air-Gap, LOC limits, SwiftLint, and all tests passing).
