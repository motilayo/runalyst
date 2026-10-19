# AI Coding Guidelines for Runalyst

This `AGENTS.md` file acts as the primary repository of architectural context, technical rules, and best practices for developing and maintaining the Runalyst iOS application. It is primarily intended for AI assistants, but serves as useful documentation for human developers.

> [!IMPORTANT]
> **The Runalyst Product & Architecture Blueprint**: All feature development and UI/UX design must adhere to the product manifesto enshrined in [docs/BLUEPRINT.md](file:///Users/motilayo/workspace/runalyzer/docs/BLUEPRINT.md), synthesizing Aarron Walter's Hierarchy of Needs, the "Thick Client, Thin AI" architectural doctrine, and Apple-centric "Sweaty Hands" User-Centered Design.

## Critical Workflow, Tooling & Formatting Rules (Read First)

- **Git Branch & Pull Request Discipline**: Committing or pushing directly to `main` is strictly forbidden. All modifications—including bug fixes, architectural enhancements, refactors, and documentation updates—must be developed on a dedicated feature or fix branch (`feat/...`, `fix/...`, `chore/...`, `docs/...`). If the current branch's PR is already `MERGED`, always create a new branch before committing. Before opening a PR, ensure the local test suite passes (`xcodebuild test`) and SwiftLint passes with 0 violations (`swiftlint --strict`). Changes must be pushed to origin and merged exclusively via GitHub Pull Requests.
- **Strict Markdown Only (No LaTeX)**: Never use LaTeX mathematical formatting (`$...$`, `$$...$$`, `\text{...}`, `\sim`, `\circ`, `\approx`, `\rightarrow`, etc.) in responses, commit messages, PR descriptions, or documentation. LaTeX formatting does not render properly in this IDE chat interface and produces broken visual noise. Always format numbers, units, ranges, and symbols using standard GitHub Markdown and clean Unicode characters (e.g., `15°–20°`, `~8°–10°`, `> 30 cm`, `0 cm`, `O(1)`, `O(N * M)`, `->`).
- **Bash Scripting**: When modifying Swift files programmatically via bash (sed/python), replace complete logical blocks or overwrite the file entirely instead of using targeted string insertions to avoid nested duplications and syntax errors.

## 0. Product & UX Core Doctrine (UCD & Walter's Hierarchy)

- **Target Persona & Mandates**: Designed specifically for the *Data-Rich, Insight-Poor Runner*. Three foundational mandates govern every feature:
  - *Translation Mandate*: Convert raw Apple HealthKit telemetry into empathetic, actionable coaching English.
  - *Protection Mandate*: Prioritize human biological safety over rigid data through subjective overrides and deterministically calculated recovery timelines.
  - *Progression Mandate*: Replace algorithmic guesswork with locked, mathematically proven pacing and duration bands.
  - *Understanding & Refinement Philosophy*: Ultimately, understand the runner: where they are currently, where they want to be based on stated goals and intents expressed in conversations, how they are trying to get there, and how you can help them get there as a runner. It is not about perfection—it is about improvement, understanding, refinement, and excellence.
- **Thick Client, Thin AI**: The backend is deterministic and local. Swift does the math, the physics engine models mechanical realities, and on-device iOS `FoundationModels` perform semantic translation and conversational synthesis. The LLM never hallucinates numbers.
- **Sweaty Hands UX (Usable & Pleasurable)**:
  - *One Metric Primary View*: High signal-to-noise ratio. The top area delivers today's single clear directive; deep data progressively discloses.
  - *Glass-Box Modals*: Tapping highlighted metrics (e.g., 156 SPM) opens native bottom sheets revealing the exact Swift math behind the recommendation.
  - *Subconscious Data Binding*: Universally consistent Apple-native color tokens: **Neon Pink** for Heart Rate, **Electric Blue** for Pace, **Vibrant Green** for Cadence.
  - *Situational Accessibility (A11y)*: 44x44pt minimum hit targets for shaking hands, `SF Pro Rounded` paired with strictly `.monospacedDigit()` to eliminate horizontal jitter, `UIImpactFeedbackGenerator` tactile scrub ticks, and combined semantic VoiceOver labels.

## 1. SwiftData & Concurrency Architecture

- **Thread Safety with ModelContext**: SwiftData `PersistentModel` and `ModelContext` are not `Sendable` and cannot be safely accessed across `await` boundaries within unstructured or detached tasks. Extract necessary properties into a `Sendable` struct beforehand, await the operation, and apply updates back on the `MainActor` or within a dedicated `@ModelActor`.
- **Background Operations**: The 30-day relative baseline logic is encapsulated entirely within a `@ModelActor` (`RunAnalyzerActor`) to safely execute SwiftData fetches, mathematical calculations, and LLM inference in the background.
- **Model Migrations & Versioning**: SwiftData models are managed under explicit `VersionedSchema` versions (`RunalystSchemaV1`, etc.) coordinated by `RunalystMigrationPlan`. When introducing breaking or structural changes, declare a new `VersionedSchema`, add it to `RunalystMigrationPlan.schemas`, and register the appropriate `MigrationStage` (`.lightweight` or `.custom`). For additive optional fields within an existing schema, mark properties as Optional (e.g., `String?`) and gracefully unwrap in code.
- **Zero Redundant Compute & Repairs**: Do not run ongoing data repair or migration loops (e.g., scanning all historical runs on app launch or in view `.task` modifiers). Ingested workouts must calculate and finalize their working metrics and tags upon initial insertion.
- **Ingestion Performance & Scaling**: For O(1) deduplication during HealthKit syncs, always use `Set<UUID>` (`Set(currentExistingRuns.map(\.hkWorkoutID))`) instead of O(N * M) `contains(where:)` array scans. Batch SQLite `try? modelContext.save()` commits (every 25 runs) instead of saving after every single run.
- **User Action State Preservation**: State representing user actions (`DrillRecommendation.isCompleted`, `TrainingCorrection` feedback, `"userLinkedDrill"`, `"userUnlinkedDrill"`, `"userSetIndoor"`, `"userSetOutdoor"`) must be immediately saved (`try? modelContext.save()`) upon user interaction and preserved across future schema migrations and HealthKit refreshes.
- **Sort Orders**: Fetch and process workouts newest-to-oldest (`$0.startDate > $1.startDate` / `HKSampleSortIdentifierStartDate` descending) so that the runner's most recent runs appear immediately on the dashboard. Views like `DashboardView` present newest runs first via `@Query(sort: \.date, order: .reverse)`.
- **Clearing Cache**: The "Resync Health Data & Rebuild AI Insights" button in `SettingsView` deletes all local `RunRecord` entries via `modelContext.delete(run)` and clears cached `@AppStorage` dashboard headlines/bodies.

## 2. FoundationModels & AI Coaching Engine

- **Availability**: FoundationModels SDK components (`CoachingEngine`, `RunInsight`, `SuggestedDrill`) must retain `@available(iOS 26.0, *)` annotations, and call sites invoking them must wrap usage in `if #available(iOS 26.0, *)` checks.
- **Structured Output**: When defining structured output for the LLM using `@Generable`, use explicit, semantically named properties (`drillWork`, `drillRecovery`, `drillCues`, `drillEffort`, `drillPurpose`) instead of generic arrays. Pair each property with a precise `@Guide` description.
- **Schema Mapping & Fallbacks**:
  - Do not instruct the model to output raw JSON or YAML strings. The SDK compiles the Swift struct directly into its proprietary schema.
  - Explicitly define output requirements for *every* field in the `@Generable` payload struct within the system prompt and via strict negative constraints in `@Guide` descriptions.
  - Always wrap `LanguageModelSession.respond` in a `do-catch` block with a graceful fallback wrapped in `String(localized:)`.
- **System Prompt & Tone**: Enforce a conversational tone via `conversational, motivational tone; speak directly to the runner`, and append localization instructions (`Respond entirely in \(Locale.current.language.languageCode)`).
- **The Core Triad: Math, Physics, and Language**:
  - **The Math (Swift)**: Deterministic, local computation of rolling window baselines, metric deltas, interval segmentation, cadence floors, pace variances, and recovery heart rate drops.
  - **The Physics (Swift)**: Physiological and mechanical realities modeled directly in code—gravitational resistance on outdoor hill climbs, kinetic friction vs. moving treadmill belts (braking shock when cadence falls below floor), thermodynamics and lack of convective wind cooling indoors creating thermal accumulation, and cardiac lag.
  - **The Language (The AI)**: Left entirely to FoundationModels. Swift feeds structured mathematical facts and physical findings into the prompt and tools; Swift must never generate canned coaching prose or simulated conversational scripts.
  - **Native Tool Calling Across the Board**: Use Apple FoundationModels Native Tool Calling (`@Generable` queries and `Tool` protocol conformances) across the board (`fetchWorkoutAnalysis`, `fetchHistoricalWorkout`, `fetchIntervalPerformance`, `fetchWorkoutPhysics`, `fetchReadinessAndPrescription`, `fetchAthleteProfile`).
- **Timeless Software Design over Prompt Bloat**:
  - **Swift Implements the Interface**: Swift does the type checking, filtering (`isIndoor`, date ranges, workout types), and mathematical comparison (`ComparisonTelemetry` diffing `RunRecord` A vs `RunRecord` B polymorphically).
  - **Tools Expose the Interface**: Tools act as published OpenAPI/Swagger-style endpoints.
  - **The LLM is Purely the Interpreter**: The model calls the interface, receives the clean diff from Swift, and translates the facts into empathetic coaching English.
- **Deterministic Math & Directives**:
  - Vertical Oscillation is mathematically linked to cadence. High vertical oscillation (> 10 cm) indicates bounding/overstriding, prompting cadence relationship analysis and drills like `'Cadence Pyramids'`.
  - Evaluate metrics locally via Swift in `RunAnalyzerActor` to compute a `directiveContext` alongside `strictly_follow_the_DIRECTIVE_for_tone_and_drill_selection`.
  - **Deterministic Guardrails over Prompt Guardrails**: Resolve conflicts deterministically in Swift before constructing the directive. When fatigue is detected (`paceDiff < 0 && hrDelta > 0`), Swift strips the user's training goal and injects `"PRIORITY: prescribe Easy Aerobic Recovery. Safety overrides any race goal."`.
- **Token Limits**: Comply with Apple's TN3193 strict 4,096-token limit by using concise property names in `@Generable` structs, capping array sizes in `@Guide(description:)` strings (never use `maximumCount`), keeping system prompts under 3 paragraphs, and injecting input data as compact comma-separated strings.
- **Strict Guardrails**:
  - No isolated cadence judgments without pace. Emphasis on rhythm and aerobic stability.
  - Drill titles must be exactly one of: `Cadence Pyramids`, `Rhythm Intervals`, `Tempo Surges`, `Strides`.
  - Separate historical and current data using `'Current:'`, `'Baseline:'`, `'Deltas:'`, and preserve `GROUP_A_CARDIO`, `GROUP_B_FORM`, `GROUP_C_PACING` labels.
- **Training Goal Context**: Stored in `@AppStorage("trainingGoal")` and injected into `directiveContext` by Swift (omitted when fatigue is detected).
- **Drill Schema Detail**: Maintain four sequential fields: `drillPurpose`, `drillWork`, `drillEffort`, and `drillRecovery`. `targetCadence` is `String?` (e.g., `'142-146'`), while `previousCadence` is `Int?`.

## 3. HealthKit, WorkoutKit & Data Management

- **Data Ingestion Sync**: Centralized in `ContentView.swift` via `syncData()`. Child views trigger syncs via an async `onSync` closure.
- **Run Iteration**: Iterate through unsynced workouts sequentially from oldest to newest, invoking a `@ModelActor` per run with deliberate delays (5s normally, 10s every 5 runs).
- **Filters & Units**: Apply user preference filters (`minimumRunDistance`) directly in `HealthKitManager`.
- **Extracted Metrics & VO2 Max**: Extract `.runningVerticalOscillation` (cm), `.runningGroundContactTime`, `.runningStrideLength`, and `.vo2Max`. VO2 Max is a global profile stat fetched via a predicate-free `HKSampleQuery` sorted by `HKSampleSortIdentifierEndDate` descending.
- **Baselines**: Use a strict rolling baseline time-locked to the run being analyzed (`$0.date < targetDate`).
- **Background Delivery & Permissions**: Store a reference to the active `HKObserverQuery` and call `completionHandler` only after awaiting updates. Call `HealthKitManager.shared.requestAuthorization()` in a `.task` modifier on `DashboardView`.
- **Global Preferences**: Managed via `@AppStorage` in SwiftUI (`useMetricSystem`, `trainingGoal`, `preferredWorkoutIsIndoor`) and read via `UserDefaults.standard` in non-UI code. DateFormatter locale must be `en_US_POSIX`.
- **Working Stats Engine**: When no dead-stop buckets are trimmed (`trimmed.count == originalBucketCount`), `FramboiseEngine.calculateWorkingAverages` bypasses bucket summation and strictly inherits raw HealthKit values.
- **Run Classification Labels**: The canonical label for moderate-effort steady runs is `"Steady Effort"` (not `"Steady Run"`).
- **Interval Segmentation & Classification**: Use a centered rolling local baseline window of 20 buckets (10 minutes) with sub-20s phase debouncing. Multi-signal cycle corroboration (`corroborationScore >= 2`) strictly requires a positive pace surge (`paceDiff >= 5.0` s/km) or a dominant pace surge (>= 30–45 s/km). Progression runs require strict monotonic quintile acceleration with low pace variance (`cv < 0.09`).
- **Biomechanical Test Veracity & Golden Fixtures**: Validate classification and coaching against authentic continuous recordings in `GoldenTelemetryFixtures` with `TelemetryNoiseInjector` (+/- 1.2 SPM cadence, +/- 1.5 BPM HR, +/- 3.0 s/km pace) and adversarial boundary mutations (ADR-0007).
- **Dual-Scope Refresh Lifecycle**:
  - *Macro Scope (`DashboardView`)*: Pull-to-refresh coordinates with `onSync(false)` inside an unstructured `Task`, re-queries VO2 Max, invalidates `@AppStorage` headline caches, and triggers macro readiness coaching.
  - *Micro Scope (`RunDetailView`)*: Pull-to-refresh invokes `HealthKitManager.shared.refreshWorkoutMetrics(for:in:)` to re-extract metrics in-place while strictly preserving `TrainingCorrection` manual overrides and `"userLinkedDrill"` / `"userUnlinkedDrill"` / `"userSetIndoor"` / `"userSetOutdoor"` / `"drillTarget:..."` tags. Ad-hoc repair loops in view `.task` modifiers are strictly forbidden.
- **Indoor & Outdoor WorkoutKit Support & Treadmill Heuristics**:
  - Custom workouts scheduled via `PreRunDrill.buildWorkoutPlan()` support both `.outdoor` and `.indoor` (`isIndoor: Bool`, persisted via `@AppStorage("preferredWorkoutIsIndoor")`) across `WorkoutsView`, `DrillsLibraryView`, and `DrillInterstitialReadoutView`. Always validate alert compatibility via `CustomWorkout.supportsAlert(..., activity: .running, location: location)` before attaching alerts, and embed target cadence in `CustomWorkout.displayName` for `.indoor` workouts where watchOS disables `CadenceRangeAlert`.
  - Treadmill runs (`isIndoor == true`) apply median pace filtering and 25% outlier clamping, reconcile post-workout distance calibration mutations (> 5m) via `refreshWorkoutMetrics()`, omit vertical oscillation/stride length cards when no footpod is present, and support manual `Outdoor <-> Indoor (Treadmill)` switching on `RunDetailView`.
- **Drill Matching, Adapted Targets & Multi-Session Daily State**:
  - Completing a recommended drill must never relabel an older historical run (never fall back to `insight.drillRecommendations.first(where: \.isCompleted)` in `RunRecord.prescribedDrillName`). Autonomous pattern matching for non-continuous primers is restricted to workouts <= 22 minutes (`1320s`).
  - Normalize cadence target strings (`PreRunDrill.normalizeCadenceTargetString`) to strip `"SPM"`, `"(Adapted)"`, and en-dashes (`"–"`), and evaluate `DrillExecutionScorecard` and `DrillIntervalEvaluator` against `RunRecord.effectivePrescribedTargetCadence`.
  - Completing only a short Pre-Run Primer (`<= 20 min`) keeps `SessionSynthesisEngine.evaluateDailyState` in `.preRun` with `completedPrimerRun` populated so Today's Main Run remains ready to start; once the Main Run is completed, `.completedToday` surfaces all sessions completed today (`allCompletedRunsToday`).
- **Incline Inference & Interactive RAG AI Analyst**: Flag `needsInclineReview` when HR strain spikes while pace is flat and cadence drops on indoor runs. RAG chat uses native tool calling and obeys Medical, Hardware, and Subjective boundaries.

## 4. SwiftUI Presentation & Layout

- **Lazy Evaluation & Aggregated Data**: Use `Section` instead of `VStack` inside `LazyVStack`. Compute global UI metrics in `DashboardView` from the unfiltered `@Query` array.
- **Race Conditions, Refreshable & Navigation**: Gate on-demand `.task` generation with `!isSyncing`. Wrap `.refreshable` syncs in an unstructured `Task`. Declare `@Environment` at the top level of the view struct, and use value-based `.navigationDestination(for: Model.self)`.
- **Layout & iPad Proportionality (`horizontalSizeClass`)**: Use `GridItem(.adaptive(minimum: 140), spacing: 16)`, `.background(.regularMaterial.ignoresSafeArea(edges: .top))` on custom headers, `.safeAreaInset(edge: .bottom, spacing: 80)` for floating bars, and `renderDualCardLayout` on `.regular` size classes so diagnostic scorecards and AI Coaching sit side-by-side on iPad.
- **UI Element Specs**: Use tap-to-alert only on explicit info (`ⓘ`) taps, display 30-Day Average SPM and Average Pace on dashboard cards, show Focus Pill tags on historical run rows, include the AI informational disclaimer, use `.secondary` instead of `.tertiaryLabel`, and compute Experience Level and Weekly Volume dynamically in `UserProfileView`.
