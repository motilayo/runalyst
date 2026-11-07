# Runalyst System Constitution

> **Core Objective:** Build a biomechanically intelligent, zero-lie training engine for runners using pure functional domain math and strict architectural boundaries.

---

## 1. System Mission & Core Invariants

You are executing tasks on **Runalyst**, an industrial-grade running analysis and coaching engine built in Swift for iOS and watchOS.

### The 3 Non-Negotiable Athlete Outcomes
1. **Unquestioned Trust:** Zero lies in the ledger. Sunday runs must never bleed into Monday-anchored calendar weeks (9.46 km actual distance must render as exactly 9.46 km across all views and AI summaries).
2. **Mechanical Protection:** Biomechanical guardrails intercept overstriding and impact shock based on anthropometric height calibrations before joint tissue micro-trauma occurs.
3. **Peace of Mind:** Under 3-second pre-run checks, instant post-run debriefs (< 100ms load), and grounded, direct coaching without corporate cheerleading fluff.

---

## 2. Directory Structure & Strangler Fig Boundary

The codebase is split strictly into an **air-gapped pure core** and **framework delivery layers**:

```
runalyst/
├── RunalystCore/                 # Pure Swift Package (27 Sans-I/O Domain Modules <= 500 LOC)
│   ├── Package.swift
│   ├── Sources/RunalystCore/
│   │   ├── TheMold.swift                         # Value types, telemetry buckets & contracts
│   │   ├── FramboiseCore.swift                   # Dead-stop trimming & working averages
│   │   ├── RunClassifierCore.swift               # Taxonomic classification engine
│   │   ├── DrillPatternCore.swift                # Form drill archetypes & adaptation
│   │   ├── DrillPatternCore+Extended.swift       # Companion extension for progression cues
│   │   ├── DrillScheduleCore.swift               # Session structure & interval steps
│   │   ├── DrillScheduleCore+Breakdown.swift     # Structured phase breakdown calculation
│   │   ├── PhysiologicalDiagnosisCore.swift      # Fatigue, overstride & drift diagnostics
│   │   ├── PhysiologicalDiagnosisCore+Takeaways.swift # Deterministic coaching takeaways
│   │   ├── SessionSynthesisCore.swift            # Daily state evaluation & primer logic
│   │   ├── SessionHorizonCore.swift              # 14-day microcycle progression horizon
│   │   ├── OrthogonalToolsCore.swift             # Native FoundationModels Tool primitives
│   │   ├── BanisterReadinessCore.swift           # TRIMP & acute:chronic workload ratio
│   │   ├── TreadmillKinematicsCore.swift         # Indoor pace clamping & friction physics
│   │   ├── IntervalSegmenterCore.swift           # Rep/recovery interval cycle detection
│   │   ├── MacroVolumeCore.swift                 # Calendar-anchored volume aggregation
│   │   ├── TemporalSnapshotCore.swift            # Mon-Sun calendar window partitioning
│   │   ├── ProgressionChartCore.swift            # Efficiency factor trend aggregation
│   │   ├── GoalBenchmarkCore.swift               # Target distance & pacing benchmarks
│   │   ├── HistoricalQueryCore.swift             # Polymorphic workout comparison
│   │   ├── LifetimeMilestonesCore.swift          # Volume and streak record evaluation
│   │   ├── RunGradeCore.swift                    # Mechanical grade scoring
│   │   ├── TrainingZoneCore.swift                # 5-zone power & HR boundary modeling
│   │   ├── DrillAdherenceCore.swift              # Post-drill target compliance scoring
│   │   ├── DrillEvaluationCore.swift             # Drill cadence variance evaluation
│   │   ├── DrillEvaluationTypesCore.swift        # Drill scorecard evaluation types
│   │   └── WorkoutMathCore.swift                 # Statistical variance & rolling averages
│   └── Tests/RunalystCoreTests/
│       ├── GoldenTelemetryFixtures.swift         # Authentic continuous sensor fixtures
│       ├── TelemetryNoiseInjector.swift          # Adversarial jitter injection harness
│       └── [Module]CoreTests.swift               # Sub-5ms Crucible unit tests
├── Runalyst/                     # iOS Foundry Application (Frameworks Allowed)
│   ├── Engine/                   # Foundry adapters (PreRunDrill, SessionSynthesisEngine)
│   ├── Models/                   # SwiftData schemas, migrations & readouts (DrillReadout)
│   ├── CoachingEngine/           # FoundationModels integration & tool dispatch
│   ├── LiveCoach/                # watchOS real-time sync & haptics
│   ├── Managers/                 # HealthKitManager & system I/O
│   ├── Utilities/                # Formatting & UI tokens
│   └── Views/                    # Hollow SwiftUI Views (DashboardView, WorkoutsView)
├── RunalystTests/                # Integration, mill persistence, and telemetry veracity tests
├── openspec/                     # Spec-Driven Development changes, specs, and proposals
├── .agent/skills/                # Engineering Org delegation & OpenSpec agent skills
├── docs/                         # Architecture, AI pipeline, blueprint, and ADR specifications
└── scripts/                      # CoreML data generation, training, and App Store screenshot utilities
```

---

## 3. Mandatory Architectural Laws

When writing or refactoring code in this repository, you **MUST** strictly abide by these laws. Failure to do so will cause `./assay.sh` or code review to reject your changes.

### Law 1: Forward Air-Gap (`RunalystCore/`)
* **Strict Framework Isolation:** Zero `import SwiftUI`, `import HealthKit`, `import SwiftData`, `import CoreML`, `import OSLog`, or `import FoundationModels`. Only `Foundation` is allowed.
* **Determinism Invariant:** Zero calling `Date()`, `Date.now`, or `Calendar.current` inside `RunalystCore/`. All time boundaries must be passed in explicitly as epoch seconds (`TimeInterval`) or discrete `DateInterval` ranges.
* **Mass Ceiling (< 500 LOC per Ingot):** No single `.swift` file inside `RunalystCore/Sources` may exceed 500 lines of code.
* **The Anti-Golfing Rule:** When a module approaches 500 LOC, split cohesive logic cleanly into a companion `<Module>+Extension.swift` file (e.g., `DrillScheduleCore+Breakdown.swift`, `DrillPatternCore+Extended.swift`, `PhysiologicalDiagnosisCore+Takeaways.swift`). **Never code-golf, compress formatting, delete existing edge-case guards, or make risky structural cuts just to squeeze under 500 lines.**

### Law 2: Reverse Air-Gap & Hollow View / Display Modal Doctrine (`Runalyst/`)
* **Hollow Views & Modals:** SwiftUI views (`Runalyst/Views/`), modal presentation sheets (`DrillReadout.swift`), and workout bridges (`PreRunDrill.swift`) are pure read-only renderers and `WorkoutKit` mappers over immutable `RunalystCore` structs (`DrillScheduleCore`, `PhysiologicalDiagnosisCore`, `SessionSynthesisCore`, `SessionHorizonCore`).
* **Zero Leaked Domain Math:** Never write physiological thresholds (e.g., `percentZone4 > 0.15`, `workingHR > 144`), workout phase/cooldown arithmetic, duration template mapping switches (e.g., `if raw >= 7 && raw <= 8`), or inline `.reduce` math inside `Runalyst/Views/` or `Runalyst/Models/`.
* **Core-First Handshake:** Whenever a display card, modal, or view needs a computed duration, phase breakdown, cadence band, or diagnostic takeaway, `RunalystCore` must expose that property first (implemented by `senior-engineer`), and the Foundry/View layer (implemented by `mid-jnr-engineer`) must only bind to it.
* **Zero Shadow Fallbacks:** Never write defense-pattern nil-coalescing math fallbacks in views like `snapshot?.totalDistance ?? runs.reduce(0, { $0 + $1.distance })`. If a snapshot is `nil`, render an explicit loading or empty state.

### Law 3: "Sweaty Hands" UX Doctrine
* **Tactile Targets:** 44x44pt minimum hit targets for shaking, sweaty fingers during or after a run.
* **Jitter-Free Telemetry:** Strictly pair `SF Pro Rounded` with `.monospacedDigit()` across all dynamic numbers and charts to prevent horizontal layout vibration.
* **Subconscious Color Binding:** Universally consistent Apple-native color tokens: Neon Pink for Heart Rate, Electric Blue for Pace, Vibrant Green for Cadence.

### Law 4: Grounded Voice Doctrine
* All generated text, prompt templates, and UI strings must adhere to athlete-to-athlete directness.
* **BANNED LEXICON:** *"champion"*, *"real engine building"*, *"unleash your spirit"*, *"crushed that interval"*, *"heart rate quiet"*, *"quiet heart rate"*, or generic cheerleading fluff.
* **ALLOWED STYLE:** Clear metric callouts, precise pace band guidance, and direct mechanical feedback (e.g., *"Keep effort in Zone 2 / conversational pace."*).

---

## 4. Spec-Driven Development & 4-Tier Engineering Org Hierarchy

Runalyst operates under strict **Spec-Driven Development (`openspec/`)** and a token-efficient **4-tier Engineering Organization**:

### OpenSpec Workflow
All non-trivial changes, refactors, and domain enhancements follow the OpenSpec lifecycle:
1. `proposal.md` -> Strategic justification, scope, and capabilities.
2. `specs/` -> Delta specifications formalizing requirements.
3. `design.md` -> Architecture, data flows, and module contracts.
4. `tasks.md` -> Granular task breakdown where every task carries an explicit Engineering Org tier tag (`[Scout | flash_lite]`, `[Mid/Jnr | flash]`, `[Senior | pro]`, or `[Staff/Lead | parent]`).

### The 4-Tier Subagent Delegation Hierarchy
1. **Tier 1 — Staff / Principal Architect (`parent` agent, Pro/Opus):**
   - Owns OpenSpec proposals, specs, system design, task decomposition, and code reviews.
   - Preserves token context: never reads > 3 files directly for exploratory recon or writes > 30 LOC directly in the parent context.
2. **Tier 2 — Senior / Lead Engineer (`senior-engineer` subagent, Pro):**
   - Implements complex `RunalystCore` sports science math, Swift 6 `@ModelActor` / `Sendable` concurrency, and multi-file architectural refactors.
3. **Tier 3 — Mid-Level / Junior Engineer (`mid-jnr-engineer` subagent, Flash):**
   - High-throughput execution of well-specified tasks: Hollow SwiftUI views, Foundry adapters, unit tests, fixture wiring, boilerplate, and SwiftLint fixes.
4. **Tier 4 — Scout / Research Intern (`research` subagent, Flash-Lite):**
   - Fast read-only codebase reconnaissance, symbol tracing, LOC audits, and `/opsx-verify` compliance audits.

---

## 5. Key Mathematical Invariants & Formulas

When implementing or editing domain logic, verify your calculations against these formal specifications (strictly formatted without LaTeX):

### A. Temporal Snapshot Half-Open Interval Alignment
To prevent Sunday runs from bleeding into Monday-anchored weeks, calendar windows are calculated using half-open intervals anchored to Monday 00:00:00 local epoch time:

```
W_current = [T_Monday_Start, T_Next_Monday_Start)
```

* Workouts falling on `T < T_Monday_Start` belong strictly to `W_-1` (Last Week).
* Trailing 7-day rolling windows (`[T - 7 days, T]`) are stored only in `RollingHorizonSummary` and **NEVER** bound to "This Week" UI cards.
* End boundaries are anchored to the following Monday's 00:00:00 epoch to ensure complete Daylight Saving Time (DST) safety without assuming a fixed 86,400s per day.

### B. Anthropometric Cadence Floor Calculation
Minimum safe cadence floor (`C_floor`) to prevent knee braking shock:

```
C_floor(Height, Pace) = C_base(Height) + Delta_C(Pace)
```

Where `C_base(Height)` by height:
* `Height < 163 cm` -> `175 SPM`
* `163 cm <= Height <= 173 cm` -> `170 SPM`
* `173 cm < Height <= 183 cm` -> `165 SPM`
* `Height > 183 cm` -> `160 SPM`

Pace Offset `Delta_C(Pace)`:
* Aerobic / Easy: `+0 SPM`
* Tempo / Threshold: `+10 SPM` to `+15 SPM`
* Interval / 5K: `+20 SPM`

### C. Banister Exponential TRIMP & ACWR
Heart Rate Reserve fraction (`Delta_HR_r`):

```
Delta_HR_r = (HR_avg - HR_rest) / (HR_max - HR_rest)
```

Banister TRIMP (`w`):

```
w = Duration_minutes * Delta_HR_r * 0.64 * e^(1.92 * Delta_HR_r)
```

Exponential Acute:Chronic Workload Ratio (`ACWR`):

```
ACWR = EWMA_acute(7-day TRIMP) / EWMA_chronic(28-day TRIMP)
```

* **Target Sweet Spot:** `0.80 <= ACWR <= 1.30`
* **High Injury Risk Band:** `ACWR >= 1.40` (Emergency directive triggers easy recovery).

---

## 6. Continuous Integration Gatekeeper (`./assay.sh`)

Every engineering cycle MUST verify against `./assay.sh`:
* **Gate 1: Directory Air-Gap Purity** — Zero Apple infrastructure frameworks (`HealthKit`, `SwiftData`, `CoreML`, `SwiftUI`, `FoundationModels`) in `RunalystCore/`.
* **Gate 1b: Determinism Air-Gap** — Zero wall-clock `Date()` or dynamic `Calendar.current` calls in `RunalystCore/`.
* **Gate 2: SwiftLint Compliance** — Zero violations under `swiftlint --strict`.
* **Gate 3: File Mass Ceiling** — Every file in `RunalystCore/` must stay strictly `<= 500 LOC`.
* **Gate 4: Grounded Voice Doctrine** — Zero banned cheerleading clichés across the entire repository.
* **Gate 5: Crucible Burn** — Instant sub-5ms pure unit tests passing across all `RunalystCore` modules.
