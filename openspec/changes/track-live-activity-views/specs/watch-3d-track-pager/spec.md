## ADDED Requirements

### Requirement: Four-Page Watch Workout Pager (Controls + Track + Metrics + Chart)
`PacingGaugeView.swift` in `RunalystWatch` SHALL remove `splitProgressBezel` (`WatchBezelTrackShape` / `bezelPerimeterPoint`) and host a swipeable `TabView` defaulted to Page 1 (`WatchTrackView`), with a left-swipe Controls page (`WatchControlsView`), Page 2 (`WatchMetricsView`), and Page 3 (`WatchTrajectoryChartView`), each strictly obeying the Hollow View doctrine with zero inline pacing or chart normalization arithmetic.

#### Scenario: Left-swipe Controls page provides Pause, Resume, End Run, and Voice Cues
- **WHEN** the runner swipes left from `WatchTrackView` to `WatchControlsView`
- **THEN** the view exposes **Pause / Resume**, **End Run** (preserving the `"End Run?"` `confirmationDialog`), and **Voice Cues toggle** controls with >= 44pt accessible hit targets.

#### Scenario: Main track page renders 3D 400m oval with glowing biometric dot and calibration/block parity
- **WHEN** an active workout runs on Apple Watch and the runner is on `WatchTrackView`
- **THEN** the view renders a 3D perspective-tilted 400m oval track using `LiveTrackCore.trackOvalPoint` and a glowing runner dot at `trackSnapshot.lapProgress` colored by `LiveTrackCore.paletteRGB`
- **AND** during `isCalibrating == true`, omits the ghost pacer dot and renders the `BASELINE` `calibrationProgressBar` + `calibrationProgressFormatted`
- **AND** once calibrated, displays the muted ghost dot at `ghostProgress` (when present) and `activeBlockBadge` / `activeBlockRemainingFormatted` when an adaptive micro-block is active
- **AND** exposes `trackSnapshot.accessibilitySummary` as a combined VoiceOver label.

#### Scenario: Metrics page renders Sweat-Proof biometric grid with linear pace-band gauge
- **WHEN** the runner swipes to `WatchMetricsView`
- **THEN** the view displays Pace (**Electric Blue**), Cadence (**Vibrant Green**), Heart Rate (**Neon Pink**), and Elapsed/Lap duration in `.monospacedDigit()` `SF Pro Rounded` typography
- **AND** retains `dynamicPaceGauge` (green target corridor + live marker needle) and `refractoryCountdownFormatted` when active.

#### Scenario: Chart page renders pre-normalized pace corridor and HR drift
- **WHEN** the runner swipes to `WatchTrajectoryChartView`
- **THEN** the `Canvas` renders the shaded target corridor (`corridorLowerY...corridorUpperY`), **Electric Blue** pace trace, and **Neon Pink** HR trace directly from `trajectorySummary.points`
- **AND** lists up to `4` recent `TrackLapSplit` chips below the chart without performing client-side min/max math.
