# Design: Watch Zero-Friction Adaptive Running Companion

## 1. RunalystCore Domain Architecture

### 1.1 `WatchRunIntent` & Zero-Friction Session Config (`WatchTargetPaceOption.swift`)
Define `WatchRunIntent` in `RunalystCore/Sources/RunalystCore/WatchTargetPaceOption.swift`:
```swift
public enum WatchRunIntent: String, Sendable, Codable, CaseIterable, Identifiable, Equatable {
    case adaptiveBase
    case pushPerformance
    case recovery

    public var id: String { rawValue }
    public var title: String { ... } // "Adaptive Base", "Push / Performance", "Recovery"
    public var subtitle: String { ... } // "Balanced aerobic run", "Find my ceiling today", "Keep me honest and easy"
    public var pacingIntentKind: PacingIntentKind { ... } // .steady, .tempo, .recovery
}
```
Update `WatchResolvedSessionConfig` so free-run watch sessions (`!hasPrescribedDrill`) default `requiresTargetPacePicker = false` (zero-friction start uses `WatchRunIntent` directly, locking baseline target pace dynamically during Minutes 0–5 calibration).

### 1.2 `AdaptivePacingConfiguration.forWatchCompanion(intent:)` (`AdaptivePacingCore.swift`)
Preserve the default `AdaptivePacingConfiguration()` initializer values so existing 600s core scenario tests continue passing unmodified, while adding:
```swift
public static func forWatchCompanion(intent: WatchRunIntent) -> AdaptivePacingConfiguration
```
Values for watch companion mode:
- `warmupDurationSeconds: 120.0`, `baselineDurationSeconds: 180.0` (total = `300.0s` / 5 minutes calibration lock-in!)
- `maxCalibrationDurationSeconds: 420.0` (allows up to 2x 60s extensions on noisy GPS start, locking cleanly at 5:00 when sensor coverage >= 70%)
- `refractoryDurationSeconds: 90.0`
- Intent tuning:
  - `.adaptiveBase`: `hrCeilingFraction: 0.92`, `hrSurgeCeilingFraction: 0.82`, `recoverEfficiencyDriftThreshold: -0.06`
  - `.pushPerformance`: `hrCeilingFraction: 0.95`, `hrSurgeCeilingFraction: 0.88`, `recoverEfficiencyDriftThreshold: -0.08`, `surgeMagnitudeFraction: 0.04`
  - `.recovery`: `hrCeilingFraction: 0.78`, `hrCeilingDurationSeconds: 20.0`, `recoverEfficiencyDriftThreshold: -0.04` (and `PacingIntentKind.recovery` suppresses surges in `AdaptivePacingCore+Triggers.swift`).

### 1.3 Lifecycle Tracking, Non-Destructive Form Check & Surge Lock-In (`AdaptivePacingCore.swift` & `+Triggers.swift`)
Inside `AdaptivePacingCore`:
- **Calibration Start**: Add `private var hasEmittedCalibrationStart: Bool = false`. On the first ingested tick while in `.calibrating`, emit `.calibrationStarted` once.
- **Surge Lock-In**: Add `internal var awaitingSurgeLockInTargetSecondsPerKm: Int? = nil`. Set on `.surge(..., newTargetSecondsPerKm:)`. While non-nil and `state == .surge` (or `currentPaceDeviation == .onTarget`), emit `.surgeLockedIn(targetPaceSecondsPerKm:)` once and clear `awaitingSurgeLockInTargetSecondsPerKm = nil`.
- **Two-Tier Form & Fatigue Catch**:
  - Add `case formCheck(currentCadenceSPM: Int, targetCadenceSPM: Int?)` and separate BDI/cadence form degradation from immediate pace dial-back:
    - First form degradation trigger (BDI triggered OR cadence drop below target/floor) with `formCheckCooldownRemaining == 0` emits `.formCheck(...)` (haptic: `.threeQuickLightTaps`, voice: `"Form check. Quick, light steps—bring your cadence up."`) and increments `consecutiveFormBreakdowns` WITHOUT dialing target pace back yet.
    - Subsequent cardiac/efficiency drift (`deltaEF <= recoverEfficiencyDriftThreshold`, sustained HR ceiling, or persistent form breakdown after form check) triggers `.recover(...)` (`haptic: .descendingDoublePulse`, warm amber accent, voice: `"Cardiac drift detected. Dialing target back to <pace> to protect your aerobic zone."`).
- **Debrief Accumulators**:
  - `surgeCount: Int`, `peakSurgeDeltaSecondsPerKm: Int`
  - `recoveryAdjustmentCount: Int`
  - `firstDriftElapsedSeconds: TimeInterval?` (captured on first cardiac/efficiency drift or recover event)
  - `solidCadenceUntilDistanceMeters: Double?` (updated when persistent cadence breakdown occurs post-calibration; remains nil if cadence held rock-solid throughout)
  - Rolling sum counters (`totalPaceSampleSecondsPerKm`, `paceSampleCount`, `totalHR`, `hrSampleCount`, `totalCadence`, `cadenceSampleCount`) so `buildRunDebrief(elapsedSeconds:totalDistanceMeters:useMetricSystem:)` runs in O(1) at End Run.

### 1.4 Unit-Aware Haptics, Audio Scripts & Normalized Display State (`AdaptivePacingCore+Presentation.swift`)
- Add cases to `PacingHapticSemantic`: `.ascendingDoublePulse`, `.threeQuickLightTaps`, `.descendingDoublePulse`, `.subtleConfirmation`.
- Add cases to `PacingAccentToken`: `.calibratingBlue`, `.surgeTeal`, `.recoverAmber`.
- Update `PacingEventFeedbackSpec.init(for event: PacingEvent, useMetricSystem: Bool = true)` with exact grounded scripts:
  - `.calibrationStarted`: `.none`, `.calibratingBlue`, `"Find a comfortable rhythm. Reading your baseline."`
  - `.calibrationComplete(let target, _)`: `.success`, `.electricBlue`, `"Baseline locked. Target pace: \(pace) per \(unitName). Let's roll."`
  - `.surge(_, let newTarget)`: `.ascendingDoublePulse`, `.surgeTeal`, `"Efficiency is high—you've got reserves. Nudging target pace to \(pace)."`
  - `.surgeLockedIn`: `.subtleConfirmation`, `.surgeTeal`, `nil`
  - `.formCheck` / `.cadenceDrift`: `.threeQuickLightTaps`, `.recoverAmber`, `"Form check. Quick, light steps—bring your cadence up."`
  - `.recover(_, let newTarget, _)`: `.descendingDoublePulse`, `.recoverAmber`, `"Cardiac drift detected. Dialing target back to \(pace) to protect your aerobic zone."`
- Update `PacingDisplayState` with pre-computed view properties:
  - `isCalibrating: Bool`, `elapsedTimeFormatted: String`
  - `paceGaugeNormalizedPosition: Double` (0.0 slow .. 0.5 center .. 1.0 fast; mapped cleanly from `(target - filteredPace) / (target * 0.25)` clamped to `[0, 1]`)
  - `targetBandLowerNormalized: Double`, `targetBandUpperNormalized: Double` (typically `0.42...0.58`)
  - `biometricStatusToken: PacingAccentToken`, `biometricStatusLabel: String` (`"Calibrating"`, `"Locked In"`, `"High Efficiency"`, `"Surge Zone"`, `"Protecting Zone"`)

### 1.5 Pure Debrief Core (`RunalystCore/Sources/RunalystCore/WatchRunDebriefCore.swift`)
New ~140-LOC Core file defining `WatchRunDebrief` and `AdaptivePacingCore.buildRunDebrief(...)`:
- `adaptationsBullet`: e.g. `"3 surges (+15s/km peak), 1 recovery adjustment."` (adapts singular/plural, imperial `s/mi` if `!useMetricSystem`, or `"Held steady baseline pacing throughout."` when 0 surges & 0 recoveries).
- `efficiencyScoreBullet`: e.g. `"Held baseline efficiency for 34 minutes before cardiac drift."` (uses `firstDriftElapsedSeconds` if drift occurred, else `"Held baseline efficiency for all <M> minutes."`).
- `formInsightBullet`: e.g. `"Cadence stayed rock-solid at 174 spm until kilometer 6."` (or `"Cadence stayed rock-solid at 174 spm across the run."`, localized unit km/mile).

---

## 2. RunalystWatch Foundry & Hollow Views

### 2.1 Audio & Multi-Pulse Haptic Engine (`FeedbackDispatcher.swift`)
- Register `UserDefaults.standard.register(defaults: ["watchVoiceCuesEnabled": true])` so audio cues play cleanly in headphones without manual setup.
- Implement timed `@MainActor` multi-pulse sequences via `WKInterfaceDevice.current().play(...)`:
  - `.ascendingDoublePulse`: `.directionUp` @ 0ms, `.directionUp` @ 140ms
  - `.threeQuickLightTaps`: `.click` @ 0ms, `.click` @ 110ms, `.click` @ 220ms
  - `.descendingDoublePulse`: `.directionDown` @ 0ms, `.directionDown` @ 160ms
  - `.subtleConfirmation`: `.click`
- Pass `useMetricSystem` user default to `event.feedbackSpec(useMetricSystem:)`.

### 2.2 Telemetry & Debrief Capture (`TelemetryEngine.swift`, `WorkoutManager.swift`, `PacingViewModel.swift`)
- Pass `intent: WatchRunIntent` into `WorkoutManager.startWorkout(location:intent:targetPaceSecondsPerKm:viewModel:)` -> `TelemetryEngine.reconfigure(...)` using `AdaptivePacingConfiguration.forWatchCompanion(intent:)`.
- On `endWorkout()`, call `telemetryEngine.buildRunDebrief(elapsedSeconds:totalDistanceMeters:useMetricSystem:)` and store on `pacingViewModel.completedDebrief`.

### 2.3 Hollow Watch Views (`StartRunView.swift`, `PacingGaugeView.swift`, `RunSummaryView.swift`, `RunalystWatchApp.swift`)
- `StartRunView.swift`:
  - High-contrast **Outdoor / Indoor** selector + 3-card/chip **Intent Picker** (`Adaptive Base` [default], `Push / Performance`, `Recovery`) with concise subtitles, plus `Start Run` CTA (`44pt+` height). Preserves optional Prescribed Drill card when pushed from iPhone.
- `PacingGaugeView.swift`:
  - Full-screen edge glow aura (`RoundedRectangle` stroke/glow overlay): pulsing calm **blue aura** when `displayState.isCalibrating`, steady **neutral blue** border once locked, **teal/green** glow on surge / high efficiency, warm **amber** glow on cardiac drift / recovery!
  - Top row: `biometricStatusLabel` pill + elapsed timer (`elapsedTimeFormatted`).
  - Center: **Dynamic Pace Gauge** horizontal/arc track (`targetBandLowerNormalized...targetBandUpperNormalized` highlighted green window + live indicator dot at `paceGaugeNormalizedPosition`), or smooth calibration progress bar during Minutes 0–5.
  - Primary Metrics: Large `.monospacedDigit()` **Current Pace** (Electric Blue) & **Heart Rate** (Neon Pink), compact live Cadence (Vibrant Green).
  - End Run button captures `completedDebrief` and sets `showingSummary = true`, presenting `.fullScreenCover` or `navigationDestination` to `RunSummaryView`.
- `RunSummaryView.swift` (added to `RunalystWatch` target in `project.pbxproj`):
  - Displays `"Coach's Takeaway"` header, compact metrics strip (Time, Distance, Avg Pace), and 3 color-coded takeaway cards: **Adaptations**, **Efficiency Score**, **Form Insight** + `Done` CTA.
- `RunalystWatchApp.swift`: Register default `watchVoiceCuesEnabled = true` on launch and add `summary` preview state to `RUNALYST_PREVIEW_SCREEN` so all states (`start`, `calibrating`, `tracking`, `surge`, `recover`, `summary`) can be previewed/rendered.

## 3. Subagent Ownership

- **Senior Engineer (`senior-engineer` | `pro`)**: Core domain types, triggers, accumulators, debrief engine, and presentation geometry (`WatchTargetPaceOption.swift`, `AdaptivePacingCore.swift`, `AdaptivePacingCore+Triggers.swift`, `AdaptivePacingCore+Presentation.swift`, `WatchRunDebriefCore.swift`).
- **Mid/Jnr Engineer (`mid-jnr-engineer` | `flash`)**:
  - Track A: Core unit tests (`AdaptivePacingCoreTests.swift`, `AdaptivePacingCore+ScenariosTests.swift`, new `WatchRunDebriefCoreTests.swift`).
  - Track B: Watch Foundry (`FeedbackDispatcher.swift`, `TelemetryEngine.swift`, `WorkoutManager.swift`, `PacingViewModel.swift`).
  - Track C: Hollow Views & Project Wiring (`StartRunView.swift`, `PacingGaugeView.swift`, `RunSummaryView.swift`, `RunalystWatchApp.swift`, `Runalyst.xcodeproj/project.pbxproj`).
