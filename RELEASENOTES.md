# Runalyst v2.4.0 — Interactive AI Coach, Structured Runs & Primers, ACWR Readiness & Treadmill Intelligence 🏃‍♂️🧠

Runalyst 2.4.0 is a milestone release delivering an on-device conversational AI Running Coach powered natively by Apple FoundationModels, a dedicated Workouts & Pre-Run Primers training hub, Acute:Chronic Workload Ratio (ACWR) readiness tracking, and indoor treadmill intelligence.

---

### 🌟 What's New in v2.4.0

#### 1. 🧠 Interactive On-Device AI Running Coach (`AnalystChatView`)
- **Apple FoundationModels Native Tool Calling**: Pure tool-calling facade (`inspectWorkout`, `manageTrainingState`, `executeCoachAction`) giving the on-device language model direct access to deterministic Swift math and physics.
- **Zero-Hallucination Architectural Doctrine**: Swift deterministically computes moving vs. gross stats, split letter grades, pacing variances, and physiological verdicts. FoundationModels acts purely as the empathetic conversational interpreter.
- **Dual Conversation Modes**:
  - `Macro Coach`: Anchored globally to your weekly progression, active goal (5K to Marathon), and today's readiness.
  - `Workout Inspection`: Deep-dives into telemetry anomalies, cadence floor compliance, and cardiac lag from a specific run.
- **Interactive Inline Cards**: Dynamic coaching suggestions render rich, tappable workout and drill cards with one-tap Apple Watch WorkoutKit export.
- **Temporal Calendar Grounding**: Real-world date awareness accurately contextualizes workouts (*“Thursday’s Fartlek”*, *“Today’s Steady Run”*).

#### 2. ⚡ Structured Workouts & Pre-Run Primers Hub (`WorkoutsView`)
- **Unified Training Taxonomy**: Dedicated "Workouts" navigation hub organizing daily training into two intuitive steps:
  - **Pre-Run Primer**: 5–15 minute neuromuscular form primers (*Cadence Pyramids*, *Rhythm Intervals*, *Strides*) with customizable haptics.
  - **Today's Run**: Locked aerobic session (*Zone 2 Easy Base*, *Tempo Surges*, *Threshold Intervals*) with dynamic duration bands (e.g. 30–45 min) tailored to your active goal.
- **Multi-Goal Schedule Synthesis**: Supports *Base Building*, *5K*, *10K*, *Half Marathon*, *Marathon*, and *Injury Recovery*.
- **Apple Watch WorkoutKit Bridge**: One-tap handoff sends structured interval blocks and target cadence bands straight to your Apple Watch.

#### 3. 🛡️ Acute Readiness & ACWR (Acute:Chronic Workload Ratio)
- **Workload Protection Mandate**: Benchmarks 7-day acute workload against 28-day chronic rolling volume to calculate your ACWR.
- **Automatic Fatigue Safeguards**: When cardiac drift, high ACWR (> 1.2), or consecutive hard training days are flagged, Runalyst automatically scales down workout intensity and prescribes active recovery flushes.
- **Glass-Box Math Modal**: Transparent half-sheet bottom modal revealing the exact mathematical formula and data points behind your readiness status.

#### 4. 🏃‍♂️ Indoor Intelligence & Treadmill Physics
- **Arm Swing Heuristics**: Applies median pace filtering and 25% outlier clamping to dampen erratic arm motion during treadmill workouts.
- **Incline Surge Detection**: Identifies steep treadmill incline intervals when heart rate spikes while pace remains flat and cadence drops.
- **Dual-Scope Data Ingestion**: Cleanly reconciles HealthKit distance calibration mutations while preserving user overrides.

#### 5. 📊 Workout Rhythm & Variance Map (`RunVarianceMapView`)
- **Continuous Rhythm Segmentation**: Maps intervals, steady running segments, and walking recoveries along with your personal cadence floor boundary.
- **Pacing Quality Scoring**: Evaluates continuous pacing consistency (CV) and flags deceleration fade vs. controlled negative splits.

#### 6. 📱 App Store Release Assets & Website Tour
- **Apple Review Compliant Previews**: 25.0s H.264 High Profile Level 4.2 video tours with stereo AAC audio across iPhone (886x1920, 1284x2778, 1242x2688) and iPad (1200x1600, 2732x2048, 2752x2064).
- **High-Resolution Presentation Cards**: 7 bespoke marketing screenshot suites framing live biometrics, AI coaching, structured runs, overstride kinematics, progression, and privacy.
- **Refreshed Promo Videos**: 9:16 vertical and 16:9 landscape cinematic marketing videos for social launches and web showcase.
- **Updated Website (runalyst.ca)**: Live interactive showcase tabs, responsive feature highlights, and updated video tour.

---

### 🛠️ Technical Improvements & Architecture
- **Expanded Test Coverage**: Comprehensive suite of 227 automated unit and integration tests across 110 Swift source files with 100% pass rate.
- **Strict SwiftLint Gate**: Zero violations under `--strict` across the entire codebase.
- **Apple TN3193 Context Conservation**: Streamlined tool schemas and compact JSON payloads keeping token utilization well within device limits.

---

**Full Changelog**: https://github.com/motilayo/runalyzer/compare/v2.3.0...v2.4.0
