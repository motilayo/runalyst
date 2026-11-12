# Proposal: Watch Zero-Friction Adaptive Running Companion

## Problem Statement

While `RunalystCore` and `RunalystWatch` have an initial adaptive pacing skeleton, several key pieces of the end-to-end "zero-friction" Apple Watch running companion experience are incomplete or diverge from the runner journey:

1. **Configuration Friction at the Curb**: `StartRunView` currently asks the runner to spin through a manual `"Target Pace"` wheel (`4:00`–`8:00 /km`) rather than offering one-tap run intent selection (**Adaptive Base**, **Push / Performance**, **Recovery**) alongside **Outdoor** / **Indoor**.
2. **Calibration Timing & Edge Aura**: `AdaptivePacingCore` defaults to a 10-minute (`600s`) calibration window rather than a focused 5-minute (`300s`) lock-in, emits no audio cue at start (*"Find a comfortable rhythm. Reading your baseline."*), emits `nil` audio on lock-in instead of announcing the locked target pace, and lacks the calm pulsing **blue aura** edge border on `PacingGaugeView`.
3. **In-Flow Visuals & Surge Lock-In Confirmation**: `PacingGaugeView` displays stacked numeric labels instead of a central **Dynamic Pace Gauge** showing live position within the target window plus a 0.5s-glance **Biometric Status Ring** (`Green`/`Blue`/`Amber`). Audio cues default to muted (`watchVoiceCuesEnabled = false`), surge haptics lack **two ascending pulses**, and there is no **single confirmation tap** when the runner reaches the new surge target zone before entering the 90s refractory cooldown.
4. **Two-Step Form & Fatigue Escalation**: Biomechanical form breakdown currently skips directly to slowing pace via `.recover`, whereas the companion experience requires a **non-destructive first-tier Form Check** (three quick light taps + *"Form check. Quick, light steps—bring your cadence up."*) and reserves **Recovery pace dial-back** (*descending double-tap*, warm amber accent, *"Cardiac drift detected. Dialing target back to <pace> to protect your aerobic zone."*) for sustained cardiac/efficiency drift.
5. **No On-Wrist Instant Debrief**: Tapping End Run dismisses `PacingGaugeView` immediately with no **Coach's Takeaway** summary on the wrist.

## Architectural Boundary & Scope

- **`RunalystCore/` (Sans-I/O Core)**:
  - `WatchTargetPaceOption.swift`: Add `WatchRunIntent` (`adaptiveBase`, `pushPerformance`, `recovery`) and update `WatchResolvedSessionConfig` for zero-friction start.
  - `AdaptivePacingCore.swift`, `AdaptivePacingCore+Triggers.swift`, `AdaptivePacingCore+Presentation.swift`: Add `AdaptivePacingConfiguration.forWatchCompanion(intent:)` (5-minute / `300s` calibration, 90s refractory cooldown, intent-specific surge/HR ceilings), `calibrationStarted`, `surgeLockedIn`, and non-destructive `formCheck` events, unit-aware voice scripts, new haptic semantics, Dynamic Pace Gauge normalized geometry, Biometric Status Ring tokens, and run-lifecycle accumulators.
  - `WatchRunDebriefCore.swift` (new pure Core file): Computes post-run `WatchRunDebrief` ("Coach's Takeaway": `Adaptations`, `Efficiency Score`, `Form Insight`).
- **`RunalystWatch/` (Foundry & Hollow Views)**:
  - `FeedbackDispatcher.swift`: Default voice cues ON; execute multi-pulse watchOS haptic sequences (`.ascendingDoublePulse`, `.threeQuickLightTaps`, `.descendingDoublePulse`, `.subtleConfirmation`) and metric/imperial ducked speech synthesis.
  - `TelemetryEngine.swift`, `WorkoutManager.swift`, `PacingViewModel.swift`: Wire `WatchRunIntent`, capture `WatchRunDebrief` on workout end.
  - `StartRunView.swift`, `PacingGaugeView.swift`, `RunSummaryView.swift` (new hollow view), `RunalystWatchApp.swift`: Render zero-friction start, calibration blue aura, central dynamic pace gauge + status ring, and 3-bullet wrist debrief.

## Impact & Air-Gap Assessment

- **Air-Gap Compliance**: Zero Apple infrastructure frameworks (`HealthKit`, `SwiftData`, `SwiftUI`, `AVFoundation`, `WatchKit`) imported inside `RunalystCore/`. Zero `Date()` or `Calendar.current` calls in `RunalystCore/`.
- **Reverse Air-Gap Compliance**: All gauge normalization, band bounds, status colors, calibration progress, and debrief copy formatting live in `RunalystCore/`. Watch views bind read-only to `PacingDisplayState` and `WatchRunDebrief`.
- **Modularity Guideline (~500 LOC soft target)**: Debrief generation is isolated into `WatchRunDebriefCore.swift` and wrist summary UI into `RunSummaryView.swift` so every touched file stays concise and focused.
