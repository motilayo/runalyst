# Runalyst System Constitution

> **Core Objective:** Build a biomechanically intelligent, zero-lie training engine for runners using pure functional domain math and strict architecture boundaries.

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
Runalyst/
├── RunalystCore/                 # Pure Swift Package (Sans-I/O Core)
│   ├── Package.swift
│   ├── Sources/RunalystCore/
│   │   ├── Biomechanics.swift
│   │   ├── BanisterACWR.swift
│   │   ├── TemporalSnapshotCore.swift
│   │   ├── IntervalSegmentation.swift
│   │   └── DrillAdherenceCore.swift
│   └── Tests/RunalystCoreTests/
│       ├── TemporalSnapshotTests.swift
│       └── BiomechanicsTests.swift
├── Runalyst/                     # Main App Target (Frameworks Allowed)
│   ├── Engine/                   # Daily state foundry & coordination
│   ├── Models/                   # SwiftData / Persistence Entities (17 models)
│   ├── CoachingEngine/           # Apple FoundationModels & RAG tools
│   ├── LiveCoach/                # watchOS real-time sync & haptics
│   ├── Managers/                 # HealthKitManager & system I/O
│   ├── Utilities/                # Formatting & math helpers
│   └── Views/                    # SwiftUI Presentation (Hollow Views)
│       └── DesignSystem/
└── RunalystTests/                # Integration, Harness & Mill Tests
    └── Engine/
```

---

## 3. Mandatory Architectural Constraints

When writing or refactoring Swift code in this repository, you **MUST** strictly abide by these 5 rules. Failure to do so will cause the `./assay.sh` CI bouncer script to reject your PR.

### Rule 1: Sans-I/O Core Air-Gap (`RunalystCore/`)
* **NO** `import SwiftUI`, `import HealthKit`, `import SwiftData`, or `import Foundation` calendar/time globals inside `RunalystCore/`.
* **NO** calling `Date()`, `Date.now`, or `Calendar.current` inside `RunalystCore/`. All timestamps must be passed in as explicit epoch values (`TimeInterval` or Unix integer seconds) or discrete calendar intervals.
* Core structures must be pure functions over immutable `Sendable` value structs.

### Rule 2: File Mass Ceiling (<= 500 LOC)
* No single `.swift` file inside `RunalystCore/` may exceed **500 lines of code** (excluding standard license headers).
* During Brick 4 view rewiring, this limit strictly extends to all SwiftUI views.
* If a file approaches 450 LOC, you must break it down into modular single-responsibility extensions or child types.

### Rule 3: Hollow View Pattern (SwiftUI Pure Renderers)
* SwiftUI views in `Runalyst/Views/` are **read-only renderers**.
* **PROHIBITED in Views:** Direct calculation logic, inline `.reduce` aggregations, or unmanaged date windowing.
* Views must only receive pre-computed `ViewState` structs passed down from state stores or snapshot models.

### Rule 4: Zero Shadow Fallbacks
* **PROHIBITED:** Defense pattern nil-coalescing fallbacks in views like `snapshot?.totalDistance ?? runs.reduce(0, { $0 + $1.distance })`.
* If a snapshot is `nil`, render an explicit loading or empty state. Never calculate secondary fallback values inside presentation components.

### Rule 5: Grounded Voice Doctrine
* All generated text, prompt templates, and UI strings must adhere to athlete-to-athlete directness.
* **BANNED LEXICON:** *"champion"*, *"real engine building"*, *"unleash your spirit"*, *"crushed that interval"*, *"heart rate quiet"*, *"quiet heart rate"*, or generic cheerleading fluff.
* **ALLOWED STYLE:** Clear metric callouts, precise pace band guidance, and direct mechanical feedback (e.g., *"Keep effort in Zone 2 / conversational pace."*).

---

## 4. Key Mathematical Invariants & Formulas

When implementing or editing domain logic, verify your calculations against these formal specifications:

### A. Temporal Snapshot Half-Open Interval Alignment
To solve the 19.5 km vs 9.46 km weekly volume defect, calendar windows are calculated using half-open intervals anchored to Monday 00:00:00 local epoch time:

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

## 5. Phased Execution Roadmap (The 6 Bricks)

```
[Brick 1: Golden Test Harness] -> [Brick 2: Pure Temporal Core] -> [Brick 3: Foundry Persistence]
                                                                        |
[Brick 6: CI Assay Sweep]    <- [Brick 5: AI & Watch Anchor]   <- [Brick 4: Hollow View Rewire]
```

1. **Brick 1: Golden Truth Harness (`RunalystTests/`)**
   - Codify the authentic workout test fixtures (Sun long run through current week runs).
   - Assert 9.46 km weekly total vs 19.5 km rolling aggregate.
2. **Brick 2: Pure Temporal Core (`RunalystCore/`)**
   - Write `TemporalSnapshotCore.swift` (< 500 LOC) using pure functional epoch interval math.
3. **Brick 3: Foundry Persistence (`Runalyst/Engine/`)**
   - Implement two-stage hydration in `RunAnalyzerActor.swift` with treadmill manual entry mutation listeners.
4. **Brick 4: Hollow View Rewire (`Runalyst/Views/`)**
   - Rewire `DashboardView.swift` to consume `DailyTrainingState`. Delete all direct `@Query` reductions in cards.
5. **Brick 5: AI & Watch Anchor (`Runalyst/CoachingEngine/`)**
   - Re-anchor Apple FoundationModels RAG tools (`WorkoutSplitsTool`, `CadenceStressTool`, `ACWRTool`, `WeeklySnapshotTool`) to pure snapshots.
6. **Brick 6: Assay Crucible (`./assay.sh`)**
   - Execute the static bouncer script to verify zero rule regressions across all files.

---

## 6. Continuous Integration Gatekeeper (`./assay.sh`)

Every coding session MUST end with a passing check from `./assay.sh`:
* Gate 1: Core Sans-I/O Air-Gap Check (zero Apple frameworks in Core).
* Gate 1b: Determinism Air-Gap Check (zero `Date()` or `Calendar.current` in Core).
* Gate 2: File Mass Ceiling Check (<= 500 LOC in Core, extending to all touched views).
* Gate 3: SwiftLint strict compliance (0 violations).
* Gate 4: Grounded Voice Doctrine lexicon audit.
* Gate 5: Swift Test Suite execution (Crucible burn).
