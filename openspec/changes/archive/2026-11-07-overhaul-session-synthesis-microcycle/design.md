## Context

Our architectural and sports-science audit of `SessionSynthesisEngine.swift` (`1,472 LOC`), `SessionSynthesisCore.swift` (`486 LOC`), and `SessionHorizonCore.swift` (`256 LOC`) identified why multi-week real-world usage felt repetitive and out of sync:

1. **False-Positive Split Drift Trigger (`SessionSynthesisEngine.swift` lines 420-435)**:
   - Currently, if a run has `>= 2` splits where split pace is within `15 s/km` and split HR rises by `>= 5 BPM`, `inferredCardiacDrift` fires and sets `driftBPM = max(18, hrRise)`.
   - Because structured interval workouts (`4m` warmup + `4 x (3m work / 3m walk)` + `7m` cooldown) and normal aerobic runs (where kilometer 1 includes cardiac warmup lag) routinely have a `>= 5 BPM` difference between first and last split, nearly every run fabricates a `+18 BPM` cardiac drift emergency!
   - That forces `20m Zone 1 Active Recovery Flush` the next day; completing that recovery run clears the drift check on the following day, which immediately prescribes `10K Threshold Surges` again—creating the exact 2-day ping-pong loop seen in the screenshots.
2. **Quality Session Monotony & Back-to-Back Spacing**:
   - `hadRecentQualityStimulus` (`SessionSynthesisEngine.swift` lines 442-462) checks the last 7 days, and when no quality session is detected (including when `10K Threshold Surges` was misclassified as `"Easy Run"`!), `synthesizePreRunPrescription` only ever prescribes `10K Threshold Surges` for a `10K` goal—never `Tempo Progression` or `Long Aerobic Endurance` even when the calendar weekday calls for them.
3. **Off-by-One Horizon Indexing (`SessionSynthesisEngine.swift` lines 866 & 1228-1234)**:
   - When `dailyState == .completedToday`, `generateMicrocycle(startsAfterTomorrow: true)` generates days starting at `now + 2 days` (`id: "day-1"`), while `plannedSession(on:)` looks up `id: "day-\(dayOffset)"` where `dayOffset == 2`, shifting the schedule lookup by 1 day.
4. **Static HR String Literals (`SessionHorizonCore.swift` lines 204-213)**:
   - `SessionHorizonCore.synthesizeHorizon` uses hardcoded `"< 135 BPM"`, `"< 150 BPM"`, and `"< 168 BPM"` instead of dynamic zone ceilings.

## Goals / Non-Goals

**Goals:**
- Eliminate the 2-day ping-pong loop by restricting `inferredCardiacDrift` to non-interval continuous runs and requiring a true steady-state decoupling (`hrRise >= 12 BPM` at steady/slower pace, using actual `hrRise` instead of `max(18, hrRise)`), while preserving explicit `"Cardiac Drift"` tag handling tested in `SessionSynthesisEngineTests`.
- Prevent back-to-back quality interval days and honour weekday variety (`Tempo Progression`, `Long Aerobic Endurance`, `Easy Aerobic Base`, `10K Threshold Surges`) across `SessionHorizonCore` and `SessionSynthesisEngine`.
- Fix the `startsAfterTomorrow` day-offset indexing in `plannedSession(on:)`.
- Replace hardcoded HR string literals in `SessionHorizonCore` with dynamic zone ceilings from `TrainingZoneCore`.
- Keep all `RunalystCore` files strictly `<= 500 LOC` without compressing or deleting existing edge-case logic.

**Non-Goals:**
- Breaking any existing assertions in `SessionSynthesisEngineTests.swift` (all existing test expectations for explicit tags, goal prescriptions, and primer recommendations must remain 100% green).

## Decisions

### Decision 1: Pure Microcycle & Drift Helpers in `SessionHorizonCore.swift` (Senior Tier — `pro`)
- **Approach**:
  - `SessionHorizonCore.swift` is only `256 / 500 LOC` (244 lines of headroom!), whereas `SessionSynthesisCore.swift` is `486 / 500 LOC`. We will place the new pure helper functions in `SessionHorizonCore.swift`:
    1. `evaluateSteadyStateSplitDrift(splits: [(pace: Double, hr: Int)], isIntervalOrTempo: Bool) -> Int?`: Returns `nil` for interval/tempo workouts or `< 2` splits; otherwise compares steady-state splits and only returns the actual `hrRise` when `hrRise >= 12` at flat/slower pace (`paceDelta >= -5.0`).
    2. `resolveDynamicMaxHeartRate(zone: SessionIntensityZone, zone1Ceiling: Int, zone2Ceiling: Int, zone3Ceiling: Int, zone4Ceiling: Int) -> String`: Computes `"< \(ceiling) BPM"` from the athlete's real zone ceilings instead of hardcoded `"< 135 BPM"` / `"< 150 BPM"` / `"< 168 BPM"`.
- **Rationale**: Keeps `SessionSynthesisCore.swift` untouched at `486 / 500 LOC`, moves domain math out of `SessionSynthesisEngine.swift` into `RunalystCore`, and respects the 500-LOC ceiling cleanly.

### Decision 2: Horizon-Aware Synthesis & Off-by-One Fix in `SessionSynthesisEngine.swift` (Senior Tier — `pro`)
- **Approach**:
  - Replace the inline split drift block (`SessionSynthesisEngine.swift` lines 420-435) with `SessionHorizonCore.evaluateSteadyStateSplitDrift(...)` (while keeping explicit tag checks like `tags.contains("Cardiac Drift")` -> `driftBPM = max(18, ...)` so existing tag-based unit tests in `SessionSynthesisEngineTests` pass unchanged).
  - In `SessionSynthesisEngine.swift`: recognize `"10K Threshold Surges"`, `"Tempo Surges"`, `"5K Rhythm Intervals"`, `"Tempo"`, and `"Intervals"` in `hadRecentQualityStimulus`, and when a quality session was already completed within the last 48 hours (1-2 days ago) without acute fatigue, prescribe `Easy Aerobic Base` (or `Tempo Progression` / `Long Aerobic Endurance` when matching the weekday template) so the runner never gets stuck in a 2-day loop.
  - In `plannedSession(on:)` (lines 1228-1234): account for `dailyState.isCompletedToday` when resolving the `upcomingMicrocycle` day index so `dayOffset` maps to the exact calendar date (`day.date` same-day check via `calendar.isDate(day.date, inSameDayAs: targetDay)` first, falling back to `id`).

## Risks / Trade-offs

- **[Risk] Existing unit tests in `SessionSynthesisEngineTests` expecting specific titles or `driftBPM >= 15` when `"Cardiac Drift"` tag is present** -> **Mitigation**: Preserve exact behavior when the explicit `"Cardiac Drift"` tag or `hrDelta >= 8` baseline spike is present on a fixture run; only tighten the *untagged* split-inference heuristic (`inferredCardiacDrift`) that was misfiring on normal runs.
