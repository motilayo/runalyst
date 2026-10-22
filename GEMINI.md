# Runalyst Constitution: The Assay-Driven Engineering Model

## 1. Prime Directive
You are operating inside a strict **Assay-Driven Engineering Workspace**. Runalyst separates biomechanical math (Rapid Domain Discovery / Prospecting) from heavy iOS infrastructure (Industrial Extraction) using a strict Directory Air-Gap. 
- **The Core (`RunalystCore/`):** Pure, deterministic sports science. Optimize for speed and mathematical purity.
- **The Foundry (`Runalyst/` iOS App):** Heavy infrastructure. Adapters, persistence, UI, and AI routing.

## 2. The Laws of `RunalystCore` (The Reference Core)
When working inside the `RunalystCore` Local Swift Package, you must strictly obey these laws:
1. **The Air-Gap (Zero I/O & Frameworks):** You must NEVER import `HealthKit`, `SwiftData`, `CoreML`, `SwiftUI`, or `OSLog`. Only `Foundation` is allowed. Do not use wall-clock time (`Date()`); accept continuous `DateInterval` boundaries explicitly.
2. **The Mass Limit (< 500 LOC):** No `.swift` file inside `RunalystCore/Sources` may exceed 500 lines of code. If a domain module (like `FramboiseCore` or `TreadmillKinematicsCore`) exceeds this, melt it down and recast it.
3. **Pure Math for Thin AI:** LLM tools (`OrthogonalToolsCore`) must return raw domain structs and enums (`RunDirective`, `SubjectiveDistressSignal`), never scripted conversational strings.
4. **Zero Tolerance Quality:** No force-unwraps (`!`). The core must pass `swiftlint --strict` with zero violations. **Never generate LaTeX** formatting (e.g., `$...$`, `\approx`) in comments or documentation.

## 3. The Laws of `Runalyst` (The Foundry)
When working inside the iOS App directory (`Runalyst/`):
1. **Hollow Adapters:** iOS service classes (`HealthKitIngestor`, `RunAnalyzerActor`) are strictly for state hydration, `SwiftData` batching (25 runs), and iOS concurrency. They must perform **zero** physiological math. They exist solely to map iOS objects to `RunalystCore` structs and back.
2. **"Sweaty Hands" UX:** SwiftUI views must maintain 44x44pt hit targets, `.monospacedDigit()` for jitter-free charts, and `SF Pro Rounded`.

## 4. Autonomous Execution Loop
On every prompt altering the biomechanical core, execute this loop:
1. **Smelt/Recast:** Update the pure domain module cleanly within the 500-LOC mass limit.
2. **Run The Assay (`./assay.sh`):** Execute the root verification script. Self-heal immediately if linting, mass caps, or purity checks fail.
3. **Report:** Output a 3-bullet summary: What you transmuted, the resulting LOC vs 500 cap, and the crucible test result.