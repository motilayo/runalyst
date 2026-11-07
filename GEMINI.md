# Runalyst Constitution: The Assay-Driven Engineering Model

## 1. Prime Directive
You are operating inside a strict **Assay-Driven Engineering Workspace**. Runalyst separates biomechanical math (Rapid Domain Discovery / Prospecting) from heavy iOS infrastructure (Industrial Extraction) using a strict Directory Air-Gap. 
- **The Core (`RunalystCore/`):** Pure, deterministic sports science. Optimize for speed and mathematical purity.
- **The Foundry (`Runalyst/` iOS App):** Heavy infrastructure. Adapters, persistence, UI, and AI routing.

## 2. The Laws of `RunalystCore` (The Reference Core)
When working inside the `RunalystCore` Local Swift Package, you must strictly obey these laws:
1. **The Air-Gap (Zero I/O & Frameworks):** You must NEVER import `HealthKit`, `SwiftData`, `CoreML`, `SwiftUI`, or `OSLog`. Only `Foundation` is allowed. Do not use wall-clock time (`Date()`); accept continuous `DateInterval` boundaries explicitly.
2. **Modularity Guideline (~500 LOC Soft Target — Never a Hard Rule):** Aim to keep files around ~500 lines of code by splitting genuinely distinct concerns into companion `<Module>+Extension.swift` files when natural, but **500 LOC is NEVER a hard limit**. Correctness, readability, and preserving existing edge-case logic always take priority over line count. Never compress code, delete guards, or make artificial cuts just to stay under 500 lines.
3. **Pure Math for Thin AI:** LLM tools (`OrthogonalToolsCore`) must return raw domain structs and enums (`RunDirective`, `SubjectiveDistressSignal`), never scripted conversational strings.
4. **Zero Tolerance Quality:** No force-unwraps (`!`). The core must pass `swiftlint --strict` with zero violations. **Never generate LaTeX** formatting (e.g., `$...$`, `\approx`) in comments or documentation.

## 3. The Laws of `Runalyst` (The Foundry)
When working inside the iOS App directory (`Runalyst/`):
1. **Hollow Adapters (`Runalyst/Engine/`, `Runalyst/Services/`, `Runalyst/Models/`):** iOS service classes, workout builders, and modal wrappers (`HealthKitIngestor`, `RunAnalyzerActor`, `SessionSynthesisEngine`, `PreRunDrill`, `DrillReadout`) are strictly for state hydration, `SwiftData` batching (25 runs), `WorkoutKit` mapping, and iOS concurrency. They must perform **zero** physiological, interval-phase, duration-mapping, or zone-threshold math. They exist solely to map iOS objects to `RunalystCore` structs (`DrillScheduleCore`, `PhysiologicalDiagnosisCore`, `SessionSynthesisCore`, `SessionHorizonCore`) and back.
2. **Hollow Views & Display Modals (`Runalyst/Views/`):** SwiftUI views and modal sheets (`RunDetailView`, `WorkoutsView`, `PrescribedSessionCardView`, `DrillPrimerCardView`, `DrillInterstitialReadoutView`, `DrillExecutionScorecard`, `HeartRateTrajectoryMapView`) are strictly read-only renderers over pre-computed `RunalystCore` structs. Writing inline domain thresholds (e.g., `percentZone4 > 0.15`, `workingHR > 144`), duration/phase switches (e.g., `if raw >= 7 && raw <= 8`), or `.reduce` math inside `Runalyst/Views/` or `Runalyst/Models/` is a hard constitutional violation.
3. **Core-First Handshake:** Whenever a display card, modal, or view needs a computed duration, phase breakdown, cadence band, or diagnostic takeaway, `RunalystCore` must expose that property first (via `senior-engineer`), and the Foundry/View layer (via `mid-jnr-engineer`) must only bind to it.
4. **"Sweaty Hands" UX:** SwiftUI views must maintain 44x44pt hit targets, `.monospacedDigit()` for jitter-free charts, and `SF Pro Rounded`.

## 4. Spec-Driven Development (OpenSpec) & Engineering Org Delegation
1. **OpenSpec Workflow (`openspec/`):** All non-trivial changes flow through OpenSpec (`proposal.md` -> `specs/` -> `design.md` -> `tasks.md` via `/opsx-propose`, `/opsx-explore`, `/opsx-apply`, `/opsx-verify`, `/opsx-archive`) governed by `openspec/config.yaml`.
2. **4-Tier Engineering Org Hierarchy (`.agent/skills/engineering-org-delegation/SKILL.md`):**
   - **Staff / Principal Architect (Parent Agent — Argon / Opus / Sonnet / Pro):** Owns specs, architecture, `design.md`, `tasks.md`, and code review. Never read > 3 files directly for recon or write > 30 LOC of implementation/test code directly in the parent context.
   - **Senior / Lead Engineer (`senior-engineer` subagent — `Model: 'pro'` or `'inherit'`):** Executes complex `RunalystCore` math, `@ModelActor` / `Sendable` concurrency, and multi-file refactors.
   - **Mid / Junior Engineer (`mid-jnr-engineer` subagent — `Model: 'flash'`):** Executes well-specified `tasks.md` items (Hollow SwiftUI Views, Foundry adapters, unit tests, fixtures, lint fixes).
   - **Scout / Research Intern (`research` subagent — `Model: 'flash_lite'` or `'flash'`, read-only):** Fast codebase reconnaissance, symbol lookup, LOC audits, and `/opsx-verify` checks.

## 5. Autonomous Execution Loop
On every prompt altering the biomechanical core, execute this loop:
1. **Smelt/Recast:** Update the pure domain module cleanly within the 500-LOC mass limit (delegating via the Engineering Org Hierarchy).
2. **Run The Assay (`./assay.sh`):** Execute the root verification script. Self-heal immediately if linting, mass caps, or purity checks fail.
3. **Report:** Output a 3-bullet summary: What you transmuted, the resulting LOC vs 500 cap, and the crucible test result.