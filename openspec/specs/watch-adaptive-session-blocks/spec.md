# watch-adaptive-session-blocks Specification

## Purpose
On-the-fly visual-only adaptive session micro-blocks, readiness/walk-load handoff, mid-block physiological and behavioral backoffs, block-aware post-run debriefs, and rest-gap resilient deload classification.

## Requirements
### Requirement: Readiness & Non-Running Load Handoff
`WatchPacingContext` and `AthleteCalibrationCore` SHALL carry lightweight pre-run readiness and limiter context from iPhone to Apple Watch without persisting non-running walks as `RunRecord` entities.

#### Scenario: Multi-day non-running gap with daily walks
- **WHEN** iPhone builds `WatchPacingContext` after 2+ days with no recorded runs (e.g., Thursday/Friday `> 5 km` walks, Saturday/Sunday rest, Monday morning gym run)
- **THEN** `WatchReadinessHint` MUST record `daysSinceLastRun >= 2`, `recentWalkMeters48h`, `hadRecentCadenceFade`, `hadRecentBounce`, and `isClearedForQuality`
- **AND** walking workouts MUST NOT be inserted as `RunRecord` rows in SwiftData.

---

### Requirement: Visual-Only On-the-Fly Session Block Orchestration
`AdaptivePacingCore` SHALL dynamically open, time, and close `AdaptiveBlockState` micro-blocks (`cadenceReset`, `thresholdSurge`, `cooldownFloor`, `effortEase`) inside `AdaptivePacingCore+SessionBlocks.swift` and surface them visually on `PacingDisplayState` without vocalized audio.

#### Scenario: Stiff opening cadence after rest days triggers Cadence Reset block
- **WHEN** calibration completes at `300` seconds with `daysSinceLastRun >= 2` (or `hadRecentCadenceFade == true`) and observed baseline cadence is below the runner's `calibratedCadenceFloorSPM` while HR remains below `0.85 * maxHR`
- **THEN** `AdaptivePacingCore` MUST open an `AdaptiveBlockState` with `kind: .cadenceReset` (`180` seconds duration) targeting `+4` to `+6 SPM` above opening cadence
- **AND** `PacingDisplayState.activeBlockBadge` MUST expose the visual badge (e.g., `"CADENCE 158->162"`) and countdown for `PacingGaugeView` with `voiceCueText: nil`.

#### Scenario: Cleared fresh legs open Threshold Surge block
- **WHEN** the session intent is `.tempo` or `.adaptiveBase` with `isClearedForQuality == true`, opening cadence is at or above floor, HR is below the surge ceiling, and efficiency drift is non-negative (`deltaEF >= -0.01`)
- **THEN** `AdaptivePacingCore` opens an `AdaptiveBlockState` with `kind: .thresholdSurge` (`240` seconds duration) followed by a `120`-second `.cooldownFloor` recovery float guarding against cadence collapse.

#### Scenario: Protection Mandate blocks upward session shaping in Recovery
- **WHEN** `WatchRunIntent == .recovery` or `subjectiveDistress == true`
- **THEN** `AdaptivePacingCore` MUST NEVER open `.thresholdSurge` and MUST transition to `.effortEase` whenever HR exceeds the recovery ceiling (`0.78 * maxHR` for `20.0s`).

---

### Requirement: Mid-Block Physiological & Behavioral Backoffs
`AdaptivePacingCore` SHALL abort or dissolve active adaptive blocks early whenever physiological strain rises or the runner chooses not to engage, backing off exponentially before proposing another block.

#### Scenario: Physiological mid-block abort triggers effortEase and lockout
- **WHEN** HR exceeds the active block ceiling (`0.88 * maxHR` for `thresholdSurge` or intent ceiling for `cadenceReset`), `deltaEF` drops below `recoverEfficiencyDriftThreshold`, or two consecutive `BDI` form breakdowns occur while a block is active
- **THEN** `AdaptivePacingCore` MUST abort the active block immediately, transition to `.effortEase` (triggering spaced `.descendingDoublePulse` if effort remains elevated), and lock out new upward blocks for `480` seconds (`8` minutes).

#### Scenario: Behavioral non-adoption dissolves ignored block after 60s
- **WHEN** `AdaptivePacingCore` opens `.thresholdSurge` or `.cadenceReset` and the runner maintains steady baseline effort/cadence without engaging the block target for `60.0` continuous seconds
- **THEN** `AdaptivePacingCore` MUST silently dissolve the block (`kind: .none`) so an ignored countdown timer is cleared from `PacingGaugeView`
- **AND** double the block re-evaluation cooldown (`300s -> 600s`) before proposing another block.

#### Scenario: Per-run cap stops repeated block proposals after 2 backoffs
- **WHEN** a session accumulates `2` physiological aborts or behavioral non-adoptions in the same workout
- **THEN** `AdaptivePacingCore` MUST suppress all further `.thresholdSurge` and `.cadenceReset` proposals for the remainder of that run while retaining safety-only `.effortEase` protection.

---

### Requirement: Post-Run Debrief Reflects Adaptive Blocks & Backoffs
`WatchRunDebriefCore` SHALL incorporate completed adaptive blocks and block backoffs into `WatchRunDebrief.adaptationsBullet` so both Watch `RunSummaryView` and iPhone `WatchLiveCompanionBannerView` accurately summarize the adaptive session.

#### Scenario: Debrief summarizes executed blocks instead of defaulting to steady
- **WHEN** a run completes with at least one `cadenceReset`, `thresholdSurge`, `cooldownFloor`, `effortEase`, or block backoff recorded
- **THEN** `AdaptivePacingCore.buildRunDebrief(...)` MUST report the completed/backed-off blocks in `adaptationsBullet` rather than falling back to `"Held steady baseline pacing throughout."`.

---

### Requirement: Rest-Gap Resilient Readiness Classification
`BanisterReadinessCore` and `ReadinessEvaluator` SHALL guard against false-positive `.deload` classification when a `2–4` day rest/walk gap causes an earlier run to roll outside the strict `7`-day cutoff despite healthy prior-week mileage.

#### Scenario: Monday morning after 4-day rest/walk gap preserves Productive readiness
- **WHEN** the runner's trailing 3-week average is `20.43 km/wk` (`23.0`, `21.6`, `16.7 km`), the most recent calendar week recorded `19.7 km` early in the week followed by `2–4` non-running days (including `> 5 km` daily walks), and acute fatigue triggers are absent
- **THEN** `ReadinessEvaluator.assess` MUST evaluate the runner as `.productive` (not `.deload`) when normalized trailing `10`-day / prior-week load remains `>= 80%` of the chronic weekly baseline.
