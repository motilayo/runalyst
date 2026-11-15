# Proposal: Watch Running Companion Experience (Live Cadence Nudges, Split Callouts, and Glanceable Turnover)

## Why

To transform the Apple Watch from a passive metric monitor into a true running companion, runners need proactive sensory coaching that keeps their biomechanics and pacing locked in without requiring constant wrist glances.

Currently, while pace drift is monitored, cadence—the critical biomechanical lever protecting joints from overstriding and braking shock—is only coached during structured drills. Furthermore, runners have no sensory awareness of kilometer/mile split completions or overall cadence health while running in the zone.

This proposal introduces live cadence turnover nudging, periodic split callouts, and glanceable live cadence on the watch gauge.

## What Changes

* **Live Cadence Turnover Nudging (`RunalystCore`)**:
  * Locks a baseline cadence during the 10-minute calibration window (or uses `intent.targetCadenceSPM` if prescribed).
  * Continuously evaluates 30-second short-window filtered cadence against target turnover.
  * If cadence drops > 6 SPM below target for >= 12 consecutive seconds outside cooldown, emits a non-destructive `PacingEvent.cadenceDrift(currentCadenceSPM:targetCadenceSPM:deltaSPM:)`.
* **Multimodal Cadence Feedback (`RunalystWatch`)**:
  * Maps `.cadenceDrift` to a distinct rhythmic double-tap haptic and grounded voice cue: *"Cadence dropping. Quicken your steps."*
  * Refractory 30-second cooldown prevents alert fatigue.
* **Periodic Split Announcements (`RunalystWatch` & `RunalystCore`)**:
  * Emits split milestone events upon crossing each kilometer (or mile, based on user unit preference).
  * Triggers a `.success` haptic tap and speaks split time (e.g., *"Kilometer 1: 6:30 pace."*).
* **Glanceable Turnover on Watch Gauge (`RunalystWatch`)**:
  * Displays live filtered cadence alongside pace and heart rate in `PacingGaugeView` styled with the canonical **Vibrant Green** color token.

## Capabilities

### New Capabilities
- `watch-live-cadence-nudge`: Debounced turnover monitoring and rhythmic haptic/audio nudging when cadence drops below target floor.
- `watch-split-milestone-callouts`: Distance split tracking and spoken pacing summaries at kilometer/mile boundaries.

### Modified Capabilities
<!-- None: existing adaptive pacing core mechanics remain backward compatible -->

## Impact & Air-Gap Assessment

* **RunalystCore**: Pure functional extension to `AdaptivePacingCore+Triggers.swift` and `AdaptivePacingCore+Presentation.swift`. Zero Apple frameworks, zero `Date()`. All files remain <= 500 LOC.
* **RunalystWatch**: `FeedbackDispatcher` handles cadence and split events; `PacingGaugeView` renders live cadence.
* **Crucible Verification**: Verified via `./assay.sh` (Air-Gap, LOC mass, SwiftLint, and test suite) and multi-platform `xcodebuild test`.
