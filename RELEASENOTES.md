# Runalyst v2.7.0 — Assay-Driven Core Architecture, Apple HIG Polish & Telemetry Veracity 🏃‍♂️💎

Runalyst 2.7.0 delivers a foundational transformation of the biomechanical engine and app experience: extracting the sports science logic into the strictly air-gapped `RunalystCore` package via the Assay-Driven Architecture, achieving complete Apple Human Interface Guidelines (HIG) compliance with the Liquid Glass design system, hardening workout telemetry veracity across indoor and outdoor modalities, and introducing date-addressable training horizons with synchronized watchOS workout durations.

---

### 🌟 What's New in v2.7.0

#### 1. ⚖️ The Assay-Driven Architecture & RunalystCore Package
- **Strict Air-Gap & Purity**: Sports science calculations completely extracted into a standalone Swift package (`RunalystCore`) free of iOS frameworks (`SwiftUI`, `HealthKit`, `SwiftData`, `CoreML`), using explicit `DateInterval` boundaries rather than system clocks.
- **24 Pure Domain Ingots (< 500 LOC)**: Decomposed complex kinematics, interval segmentation, Banister impulse-response modeling, and session synthesis into 24 focused domain modules, each strictly capped under 500 lines of code.
- **5-Gate Verification Gate (`assay.sh`)**: Automated compliance pipeline validating framework purity, determinism, strict SwiftLint standards, code mass, and crucible unit tests.
- **Continuous Mill Assay**: Multi-fixture differential fuzzing and noise injection validating biomechanical determinism against real-world sensor jitter and adversarial edge cases.

#### 2. 🎨 Apple Human Interface Guidelines (HIG) & Liquid Glass Design System
- **Accessible Touch Targets**: Every card, action, and filter upgraded to exceed Apple's 44x44pt minimum hit target with nuanced haptic feedback for one-handed operation.
- **Liquid Glass Container System**: Translucent, elevated card surfaces with synchronized workout phase color palettes (Warmup, Work, Recovery, Cooldown).
- **Glass-Box Explainer Modals**: Interactive bottom sheets revealing the exact Swift math and physiological rationale behind every calculated recommendation.
- **Zero Horizontal Jitter**: Standardized `.monospacedDigit()` and `SF Pro Rounded` typography across all telemetry cards, trend badges, and timers.
- **Streamlined View Hierarchies**: Redesigned layouts across `RunDetailView`, `WorkoutsView`, `AnalysisDashboardView`, and `DashboardView`, featuring an expanded Personal Records (PR) grid and goal readiness progress tracking.

#### 3. 🫀 Biomechanical Telemetry & Cardiovascular Veracity
- **Native Interval Metric Extraction**: Extracts authentic workout interval metrics directly from HealthKit workouts, preventing sensor lag from misattributing work and recovery segments.
- **Indoor Treadmill Surge Preservation**: Intelligent handling of treadmill accelerations and cadence drops, alerting runners when indoor incline reviews are warranted.
- **Cardiovascular Calibration**: Eliminated phantom trajectory spikes, synchronized biometric rounding, and refined Zone 2 aerobic adherence scoring.

#### 4. ⏱️ Workout Duration Synchronization & WorkoutKit Parity
- **Bijective Duration Guarantees**: Perfect synchronization of duration bands across upcoming schedule cards, session detail modals, and exported Apple Watch WorkoutKit custom workout plans.
- **Primer Drill Harmonization**: Seamlessly connects pre-run primer drills with target cadence bands, ensuring safe progression before main aerobic sessions.

#### 5. 🤖 Pure Native Tool Calling & Orthogonal Tool Contracts
- **Single-Responsibility Tool Endpoints**: Re-architected on-device Apple Intelligence tools into orthogonal domain primitives (`inspectWorkout`, `getTrainingSchedule`, `getReadinessAndWorkload`, `queryWorkoutHistory`, `executeCoachAction`) with zero response sniffing or dialogue scripting.
- **Date-Addressable Horizons**: Clean parameterized time ranges for training schedules and continuous ACWR (Acute:Chronic Workload Ratio) readiness calculations.

---

### 🛠️ Technical Improvements & Architecture
- **368 Passing Tests**: 298 passing unit and integration tests in `RunalystTests` plus 70 passing crucible tests across 17 suites in `RunalystCore` with 0 failures and 0 regressions.
- **Strict SwiftLint Gate**: 0 violations across all 131 Swift source files (`swiftlint --strict`).
- **Version Bump**: CFBundleShortVersionString `2.7.0` (Build 10) and updated website deployment metadata.

---

**Full Changelog**: https://github.com/motilayo/runalyst/compare/v2.6.0...v2.7.0
