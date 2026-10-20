# Runalyst v2.6.0 — Adaptive Periodization, Biomechanical Synthesis & Training UI Polish 🏃‍♂️🎯

Runalyst 2.6.0 delivers a major architectural upgrade to the daily session prescription and training composability engine (`SessionSynthesisEngine`), implementing periodized 80/20 polarized guardrails, physical pendulum cadence normalization, experience-scaled duration bands, closed-loop biomechanical primers, and Apple-grade "Sweaty Hands" UI refinements.

---

### 🌟 What's New in v2.6.0

#### 1. ⚙️ Dynamic Rolling Baselines & Biomechanical Cadence Normalization
- **Duration & Classification Weighting**: `computeWeightedBaseline` applies 1.5x weight to steady-state workouts and filters out short sprints (< 10 min), preventing brief outliers from skewing aerobic pace bands.
- **Physical Pendulum Cadence Floor**: Dynamically calibrates the cadence floor (`calibratedCadenceFloor`) against the runner's stored height (`userHeightCm`) using leg-length pendulum physics (~150 SPM floor for 190 cm tall runners up to ~162 SPM for 155 cm runners).

#### 2. 🛡️ 80/20 Polarized Guardrails & Goal-Specific Quality Sessions
- **Rolling 7-Day Stimulus Capping**: Strictly enforces that hard/quality workouts are permitted only when fewer than 2 hard stimuli have occurred in the trailing 7 days (`hardSessionsLast7d < 2`). Quality requests automatically revert to Zone 2 Aerobic Base if fatigue is banked.
- **Target Goal Specialization**: Quality workouts specialize by race goal: 5K prioritizes Rhythm Intervals, 10K targets Threshold Surges, and Half/Full Marathon targets Lactate Threshold Steady workouts.

#### 3. 🎯 Closed-Loop Biomechanical Primers & Clean Coaching Language
- **Biomechanical Deficit Targeting**: Automatically prescribes Cadence Pyramids when elevated vertical bounce (> 10 cm or > 9.0% oscillation ratio) is detected, and Rhythm Intervals when late-run cadence fading (> 5 SPM drop) occurs.
- **Clean Safety & Taper Strings**: In `.acuteFatigue` and `.deload` recovery states, primers display strictly `7m 30s` with clean target bands (e.g., `155–161 SPM`) and zero apologetic suffixes (eliminating `(Adapted)` and `(Trimmed from ...)`).

#### 4. ⏱️ Experience-Aware Duration Bands & WorkoutKit Parity
- **Tiered Aerobic Base Bands**: Zone 2 Aerobic Base sessions scale deterministically by runner experience level across UI cards, phase breakdown bars, and watchOS WorkoutKit plans:
  - **Novice**: `25–35 Min` (30 min -> 5m warm-up / 20m steady / 5m cool-down)
  - **Intermediate**: `35–45 Min` (40 min -> 5m warm-up / 30m steady / 5m cool-down)
  - **Advanced / Competitive / Elite**: `45–60 Min` (50 min -> 5m warm-up / 40m steady / 5m cool-down)
- **Extended WorkoutKit Intervals**: Added `.fortyMinutes` (40 min) and `.fiftyMinutes` (50 min) structured interval generation to `DrillDuration`.

#### 5. 📱 Sweaty Hands UX & Completed Session Geometric Polish
- **Full-Row Touch Targets**: Converted completed session rows into full-width interactive buttons conforming to Apple's 44pt minimum hit target with light haptic feedback.
- **Fixed Status Pill Proportions**: Replaced stretched vertical status bars with fixed-size horizontal capsules (`✓ Target Met` and `Grade A`) and Apple-standard disclosure chevrons.
- **Clean Title Scaling**: Added `.minimumScaleFactor(0.85)` with single-line tail truncation to prevent text overflow on narrower displays.

#### 6. 🏃‍♂️ Indoor/Outdoor Flexibility & Profile Onboarding Integration
- **Environment Quick Toggle**: Smoothly switch scheduled runs between Indoor Treadmill and Outdoor with automatic watchOS alert validation.
- **Profile Walkthrough**: Interactive profile configuration seamlessly embedded into the onboarding walkthrough.

---

### 🛠️ Technical Improvements & Architecture
- **241 Passing Unit & Integration Tests**: 0 failures, 0 regressions across the entire test suite.
- **Strict SwiftLint Gate**: 0 violations across all 110 Swift source files (`--strict`).
- **Decoupled Taxonomy**: Renamed `mainRunDrillId` to `mainSessionTemplateId` (with backward-compatible alias) to decouple main aerobic sessions from drill copy pickers.

---

**Full Changelog**: https://github.com/motilayo/runalyzer/compare/v2.5.1...v2.6.0
