# Contributing to Runalyst

Thank you for contributing to Runalyst! We operate under an **Assay-Driven Engineering Model** and strict **Spec-Driven Development** to preserve sports science accuracy, code mass limits, and token efficiency.

---

## Environment Setup
- **macOS**: Compatible with Xcode 18.
- **Xcode 18+**: Required for the iOS 26 SDK, `LanguageModelSession` FoundationModels, and WorkoutKit enhancements.
- **Tooling**: Install SwiftLint (`brew install swiftlint`).
- **Physical Device**: Testing on-device FoundationModels and the Neural Engine for CoreML requires a physical iOS device with Apple HealthKit running data.

---

## Spec-Driven Development (OpenSpec)

All non-trivial feature additions, architectural refactors, and domain enhancements must follow the OpenSpec workflow before writing production code:
1. **Proposal (`/opsx-propose`)**: Create `proposal.md`, delta `specs/`, `design.md`, and `tasks.md`.
2. **Subagent Task Tagging**: Every task in `tasks.md` must be assigned to an Engineering Org tier:
   - `[Staff/Lead | parent]`: Architecture, specifications, review.
   - `[Senior | pro]`: `RunalystCore` biomechanical math, `@ModelActor` concurrency, multi-file refactors.
   - `[Mid/Jnr | flash]`: Hollow SwiftUI views, Foundry adapters, unit tests, fixtures, and lint fixes.
   - `[Scout | flash_lite]`: Fast read-only codebase reconnaissance, LOC audits, and verification.
3. **Verification (`/opsx-verify`)**: Audit implementation against requirements before archiving via `/opsx-archive`.

---

## Architectural Guardrails

### 1. Forward Air-Gap (`RunalystCore/`)
- Pure, sans-I/O Swift Package importing only `Foundation`.
- Zero imports of `HealthKit`, `SwiftData`, `CoreML`, `SwiftUI`, or `FoundationModels`.
- Zero wall-clock `Date()` or dynamic `Calendar.current` calls. Pass timestamps as explicit epoch seconds or `DateInterval` boundaries.
- **Mass Ceiling (< 500 LOC per File)**: Every core module must stay `<= 500 LOC`. When domain complexity expands, use the companion extension pattern (`<Module>+Extension.swift`). Never code-golf or delete edge-case guards to fit.

### 2. Reverse Air-Gap & Hollow View Doctrine (`Runalyst/`)
- SwiftUI views (`Runalyst/Views/`) and modal/workout bridges (`DrillReadout.swift`, `PreRunDrill.swift`) are strictly read-only renderers and mappers over `RunalystCore` structs.
- Never write domain thresholds (e.g., `percentZone4 > 0.15`), phase/duration calculation switches, or inline `.reduce` math in presentation views.
- **Core-First Handshake**: If a view needs a new diagnostic breakdown or duration value, implement it in `RunalystCore` first.

### 3. "Sweaty Hands" UX
- 44x44pt minimum hit targets for shaking, post-run hands.
- SF Pro Rounded paired strictly with `.monospacedDigit()` for jitter-free numbers.

### 4. Grounded Voice Doctrine
- Athlete-to-athlete directness. No cheerleading fluff (*"champion"*, *"real engine building"*, *"unleash your spirit"*, *"crushed that interval"*).

---

## Verification: The Assay Gatekeeper (`./assay.sh`)

Before opening a pull request, run `./assay.sh` locally:

```bash
./assay.sh
```

All 5 gates must pass:
1. **Gate 1**: Directory Air-Gap purity (zero illegal frameworks in Core).
2. **Gate 1b**: Determinism Air-Gap (zero `Date()` or `Calendar.current` in Core).
3. **Gate 2**: SwiftLint strict compliance (0 violations).
4. **Gate 3**: Mass audit (all Core files `<= 500 LOC`).
5. **Gate 4**: Grounded Voice Doctrine lexicon audit.
6. **Gate 5**: Crucible burn (`swift test --package-path RunalystCore` in under 5ms).

---

## Opening a Pull Request

1. **Git Discipline**: Direct pushes to `main` are strictly forbidden. Always create a dedicated branch (`feat/...`, `fix/...`, `docs/...`).
2. **Tests & Lint**: Ensure `xcodebuild test` and `./assay.sh` pass locally before pushing.
3. **Commit Messages**: Follow Conventional Commits (`feat(...)`, `fix(...)`, `docs(...)`, `refactor(...)`).
4. **Strict Markdown**: Never use LaTeX formatting (`$...$`, `\approx`, `\rightarrow`) in commit messages, PR descriptions, or documentation.
