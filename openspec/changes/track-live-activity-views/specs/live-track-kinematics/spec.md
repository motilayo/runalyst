## ADDED Requirements

### Requirement: Deterministic 400m Track Lap Kinematics
`LiveTrackCore` SHALL compute 400-meter stadium track lap progress, ghost target pacer progress, lead/lag delta, cadence stride frequency, and combined VoiceOver summary purely from deterministic inputs without accessing wall-clock time or Apple UI frameworks.

#### Scenario: Standard 400m lap rollover and progress calculation
- **WHEN** `LiveTrackCalculator` evaluates `totalDistanceMeters = 1040.0` with `elapsedSeconds = 312`, `isCalibrating = false`, and `targetPaceSecondsPerKm = 300` (5:00/km)
- **THEN** `lapNumber` equals `3` (`floor(1040.0 / 400.0) + 1`)
- **AND** `lapDistanceMeters` equals `240` (`1040.0` modulo `400.0`)
- **AND** `lapProgress` equals `0.60` (`240.0 / 400.0`, clamped within `[0.0, 1.0)`)
- **AND** `ghostProgress` equals `(312.0 / 0.300)` modulo `400.0` divided by `400.0` (`0.60`, `ghostDeltaMeters = 0`, `ghostDeltaLabel = "On Pacer"`).

#### Scenario: Calibration phase or missing target pace suppresses ghost pacer
- **WHEN** `isCalibrating == true` or `targetPaceSecondsPerKm == nil`
- **THEN** `ghostProgress` and `ghostDeltaMeters` remain `nil` rather than fabricating a synthetic target pace
- **AND** `ghostDeltaLabel` reports `"Calibrating"` when `isCalibrating == true`.

#### Scenario: Zero distance or paused cadence boundaries
- **WHEN** `totalDistanceMeters <= 0.0`
- **THEN** `lapNumber` defaults to `1`, `lapDistanceMeters` defaults to `0`, and `lapProgress` equals `0.0`.

#### Scenario: Paused or zero-cadence runner stride frequency
- **WHEN** `isPaused == true` or `cadenceSPM == nil`
- **THEN** `runnerStrideHz` equals `0.0` so the iPhone runner avatar pauses smoothly without animating in place.

---

### Requirement: Unit Formatting & Biometric Palette Parity
`LiveTrackCore` and `WatchLiveRunSnapshot` SHALL enforce consistent `useMetricSystem` formatting (`/km` vs `/mi` and `km` vs `mi` total distance) and expose canonical `BiometricPaletteRGB` values for every `PacingAccentToken` so Apple Watch, iPhone, iPad, and `RunalystWidgets` render identical telemetry units and status colors.

#### Scenario: Imperial unit parity across Watch and iPhone snapshots
- **WHEN** `WatchLiveRunSnapshot.from(displayState:..., useMetricSystem: false, ...)` and `LiveTrackCalculator` evaluate an active run at `totalDistanceMeters = 1609.344`
- **THEN** `filteredPaceFormatted` and `targetPaceFormatted` render in `/mi` units matching Watch display formatting
- **AND** `LiveTrackSnapshot.totalDistanceFormatted` renders `"1.00 mi"` while `lapHeaderLabel` remains anchored to the universal 400m track (`"Lap 5 • 9/400m"`).

#### Scenario: Canonical biometric color mapping across targets
- **WHEN** `LiveTrackCore.paletteRGB(for:)` is queried for `.calibratingBlue`, `.surgeTeal`, `.recoverAmber`, `.recoverOrange`, `.electricBlue`, `.vibrantGreen`, and `.neonPink`
- **THEN** each token resolves to a distinct deterministic RGB tuple without collapsing `.calibratingBlue` or `.recoverAmber` into other states.

---

### Requirement: Parametric Oval Coordinate Projection
`LiveTrackCore` SHALL provide a pure `trackOvalPoint(progress:)` projection in normalized `[0.0, 1.0]` coordinates so Watch, iPhone, iPad, and Widget views render identical clockwise stadium geometry with zero view-layer trigonometry.

#### Scenario: Start/finish and half-lap coordinate anchors
- **WHEN** `LiveTrackCore.trackOvalPoint(progress: 0.0)` is evaluated
- **THEN** the point lies at the top-center start/finish anchor (`x = 0.50`, `y` at top straightaway)
- **AND** `trackOvalPoint(progress: 0.5)` lies symmetrically on the opposite bottom straightaway (`x = 0.50`).

---

### Requirement: Rolling 8-Minute Trajectory Sampling & 400m Lap Splits
`LiveTrackAccumulator` SHALL maintain a bounded 480-second rolling trajectory window downsampled to at most `24` normalized points alongside up to `4` most recent completed 400m lap splits.

#### Scenario: Rolling window pruning and downsampling cap
- **WHEN** `recordSample` receives 600 one-second samples across 10 minutes of running
- **THEN** samples older than `latestElapsedSeconds - 480` are pruned
- **AND** `makeTrajectorySummary(targetPaceSecondsPerKm:)` emits at most `24` `LiveTrajectoryPoint` items with pre-normalized `paceNormalizedY` and `hrNormalizedY` in `[0.0, 1.0]`.

#### Scenario: 400m lap completion records split chip
- **WHEN** cumulative distance crosses a 400m boundary (e.g., `398.0 -> 403.0` meters)
- **THEN** `LiveTrackAccumulator` appends a `TrackLapSplit` for that completed lap with formatted duration (e.g., `"2:04"`) and `onTarget` adherence boolean, retaining the most recent `4` splits.
