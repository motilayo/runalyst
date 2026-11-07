---
name: engineering-org-delegation
description: >-
  Engineering Organization Hierarchy and Subagent Delegation Playbook for token-efficient
  Spec-Driven Development (OpenSpec). Use this skill whenever planning, exploring, implementing,
  or verifying changes to delegate reconnaissance to Scout (flash_lite), complex core/concurrency
  engineering to Senior (pro/inherit), and high-volume code/view/test implementation to Mid/Junior (flash).
---

# Engineering Org Hierarchy & Subagent Delegation Playbook

To maximize token efficiency and preserve the primary context window for high-leverage architectural reasoning, Runalyst operates like a tiered software engineering organization paired with **OpenSpec** (`openspec`).

---

## 1. The 4-Tier Engineering Organization

| Org Tier | Role Title | Antigravity Agent / Tool | Model Tier | Write Tools | Primary Responsibilities |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Tier 1** | **Staff / Principal Architect** | Parent Agent (You) | `inherit` (Argon / Opus / Sonnet / Pro) | Orchestration & Specs | Owns OpenSpec `proposal.md`, `specs/`, `design.md`, `tasks.md`; decomposes work; dispatches subagents; reviews diffs; signs off on PRs. |
| **Tier 2** | **Senior / Lead Engineer** | `senior-engineer` (via `define_subagent`) | `pro` or `inherit` | `true` | Complex `RunalystCore` biomechanical math, Swift 6 `@ModelActor` / `Sendable` concurrency, and delicate multi-file refactors. |
| **Tier 3** | **Mid-Level / Junior Engineer** | `mid-jnr-engineer` (via `define_subagent`) | `flash` | `true` | High-throughput code execution from `tasks.md`: SwiftUI Hollow Views, Foundry adapters, unit tests, Golden fixtures, boilerplate, and SwiftLint fixes. |
| **Tier 4** | **Scout / Research Intern** | `research` (Built-in) | `flash_lite` or `flash` | `false` (Read-only) | Fast codebase reconnaissance, symbol lookup, LOC audits, call-graph tracing, and `/opsx:verify` requirement-to-code mapping. |

---

## 2. Token Efficiency Guardrails for the Staff Architect (Parent Agent)

1. **Reconnaissance Threshold (> 3 Files)**: Never read more than 3 files directly in the parent context window to locate symbols or understand existing code. Invoke a **Tier 4 Scout** (`TypeName: "research"`, `Model: "flash_lite"`) and ask for a concise (< 300 words) architectural digest with exact file paths and line ranges.
2. **Implementation Threshold (> 30 LOC)**: Never churn out > 30 lines of implementation code, SwiftUI views, or unit tests directly in the parent context window. Define and invoke a **Tier 3 Mid/Jnr Engineer** (`Model: "flash"`) or **Tier 2 Senior Engineer** (`Model: "pro"` / `"inherit"`) with a self-contained spec excerpt.
3. **Context Compression**: Subagents absorb all intermediate compiler output, test logs, file reads, and iterative edits in their own isolated conversation context, returning only a 3-bullet summary (`What changed`, `LOC vs 500 ceiling`, `Verification output`) to the Staff Architect.

---

## 3. Subagent Definitions (`define_subagent` Blueprints)

Before dispatching implementation tasks in a conversation, register the needed subagent types once using `define_subagent`:

### A. Tier 2: Senior / Lead Engineer (`senior-engineer`)

```json
{
  "Name": "senior-engineer",
  "Description": "Senior/Lead Swift Systems & Biomechanics Engineer for complex RunalystCore algorithms, Swift 6 strict concurrency (@ModelActor / Sendable), and intricate multi-file refactors.",
  "EnableWriteTools": true,
  "EnableMCPTools": false,
  "EnableSubagentTools": false,
  "SystemPrompt": "You are a Senior/Lead Swift Engineer on Runalyst. Follow CONSTITUTION.md, AGENTS.md, and GEMINI.md strictly.\n1. RunalystCore Air-Gap: Never import HealthKit, SwiftData, CoreML, SwiftUI, or OSLog in RunalystCore/. Never call Date() or Calendar.current in RunalystCore/.\n2. Mass Limit: Every touched .swift file must remain <= 500 LOC. If a file is near 500 LOC, add new helpers in a clean companion `<Module>+Extension.swift` file — NEVER golf code, delete existing edge-case logic, or make risky cuts just to fit 500 LOC. No force-unwraps (!).\n3. Strict Markdown: Never use LaTeX formatting.\n4. Verification: Run ./assay.sh before completing your task and self-heal any violations.\n5. Output: Return a concise 3-bullet summary (What you transmuted, resulting LOC vs 500 cap for each touched file, and ./assay.sh test result)."
}
```

*Invocation*: `invoke_subagent` with `TypeName: "senior-engineer"`, `Model: "pro"` (or `"inherit"`), `Role: "Senior Core & Concurrency Engineer"`.

### B. Tier 3: Mid-Level / Junior Engineer (`mid-jnr-engineer`)

```json
{
  "Name": "mid-jnr-engineer",
  "Description": "Mid-Level/Junior Swift Engineer (Flash tier) for high-throughput implementation of well-specified tasks: SwiftUI Hollow Views, Foundry adapters, unit tests, fixture wiring, and lint fixes.",
  "EnableWriteTools": true,
  "EnableMCPTools": false,
  "EnableSubagentTools": false,
  "SystemPrompt": "You are a fast, disciplined Mid/Junior Swift Engineer on Runalyst executing a well-specified task from an OpenSpec design.\n1. Follow the exact type signatures, file paths, and acceptance criteria provided in your prompt.\n2. Strict Hollow Views, Modals & Adapters (Reverse Air-Gap): SwiftUI views (`Runalyst/Views/`), modal models (`DrillReadout.swift`), and workout builders (`PreRunDrill.swift`) are pure read-only renderers/mappers over `RunalystCore` structs (`DrillScheduleCore`, `PhysiologicalDiagnosisCore`, `SessionSynthesisCore`). You are STRICTLY FORBIDDEN from writing domain thresholds (e.g. `percentZone4 > 0.15`, `hr > 144`), duration/phase calculation switches, or inline `.reduce` math inside `Runalyst/`. If a needed property does not exist on a `RunalystCore` struct, stop and report back to the Staff Architect so `senior-engineer` can add it to `RunalystCore`.\n3. Sweaty Hands UX: Use 44x44pt hit targets, .monospacedDigit(), and SF Pro Rounded.\n4. Quality Gates: Every touched .swift file must stay <= 500 LOC (use `<Module>+Extension.swift` if needed—never golf code), contain zero force-unwraps (!), use Grounded Voice (no cheerleading fluff), and contain zero LaTeX.\n5. Verification: Run ./assay.sh (or swiftlint --strict) after editing and fix any issues immediately.\n6. Output: Return a concise 3-bullet summary (Files modified/created, LOC count per file vs 500 cap, and verification command status)."
}
```

*Invocation*: `invoke_subagent` with `TypeName: "mid-jnr-engineer"`, `Model: "flash"`, `Role: "Mid/Jnr Implementation Engineer"`.

### C. Tier 4: Scout / Research Intern (`research`)

Use the built-in `research` subagent directly (no `define_subagent` call required):
*Invocation*: `invoke_subagent` with `TypeName: "research"`, `Model: "flash_lite"` (or `"flash"`), `Role: "Codebase Scout & Spec Auditor"`.

---

## 4. OpenSpec Phase-to-Hierarchy Mapping

### Phase 1: `/opsx:explore` & `/opsx:propose` (Discovery, Specs & Architecture)
1. **Scout Recon (`research` | `flash_lite`)**: Staff Architect dispatches 1-2 Scout subagents to inspect relevant modules, check current file LOC counts, and extract existing struct/protocol signatures.
2. **Staff Architecture (`parent` | Argon/Opus/Pro)**: Using the Scout digest, the Staff Architect authors `proposal.md`, `specs/<capability>/spec.md`, `design.md`, and `tasks.md`.
3. **Task Tagging in `tasks.md`**: Every task in `tasks.md` is tagged with its execution tier:
   - `- [ ] 1.1 [Senior | pro] Implement pure epoch window slicer in RunalystCore/Sources/RunalystCore/TemporalSnapshotCore.swift`
   - `- [ ] 1.2 [Mid/Jnr | flash] Wire Hollow View card in Runalyst/Views/DashboardView.swift per design.md Section 3`
   - `- [ ] 1.3 [Mid/Jnr | flash] Add unit test coverage in RunalystCore/Tests/RunalystCoreTests/TemporalSnapshotTests.swift`

### Phase 2: `/opsx:apply` & `/opsx:ff` (Implementation Execution)
1. Staff Architect reads `tasks.md` and `design.md`.
2. For each task (or parallel batch of non-overlapping tasks):
   - Tasks tagged `[Mid/Jnr | flash]` are delegated to `mid-jnr-engineer` (`Model: "flash"`).
   - Tasks tagged `[Senior | pro]` are delegated to `senior-engineer` (`Model: "pro"` or `"inherit"`).
   - When running multiple write subagents in parallel on independent modules, either ensure strictly disjoint file sets on `Workspace: "inherit"` or use `Workspace: "share"` for branch isolation.
3. As each subagent reports completion, the Staff Architect verifies the summary, checks off `- [x]` in `tasks.md`, and proceeds.

### Phase 3: `/opsx:verify` & `/opsx:archive` (Audit & Closure)
1. Staff Architect dispatches a **Tier 4 Scout** (`research` | `flash_lite`) to cross-check every `### Requirement:` and `#### Scenario:` in the delta specs against the actual codebase line numbers.
2. Staff Architect runs `./assay.sh` once to confirm all 5 gates pass, presents the Verification Scorecard, and archives the change via `/opsx:archive`.
