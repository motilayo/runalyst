# Runalyst Roadmap

## Recently Delivered Capabilities

### 1. Walk-Recovery Interval Preservation (`IntervalSegmenterCore`)
- **Delivered:** V2.5
- **Description:** Multi-signal centered rolling baseline interval engine that distinguishes purposeful walking/standing interval recovery troughs from dead-stop GPS dropouts or urban traffic halts.
- **Key Capabilities:**
  - Multi-signal cycle corroboration requiring genuine pace surge (>= 5.0 s/km) or dominant pace surges (>= 30–45 s/km).
  - Preserves walk recoveries during structured interval workouts without corrupting true working averages or misclassifying interval sessions as erratic runs.
  - Sub-20s phase debouncing prevents phantom interval fragmentation during continuous runs.

### 2. Microcycle-Coherent 14-Day Horizon Synthesis (`SessionHorizonCore`, `SessionSynthesisCore`)
- **Delivered:** V2.5
- **Description:** Calendar-anchored 14-day training horizon modeling progression and recovery without Sunday-to-Monday calendar leakage.
- **Key Capabilities:**
  - Half-open interval calendar windowing (`[T_Monday_Start, T_Next_Monday_Start)`) strictly preventing Sunday long runs from inflating the subsequent microcycle volume.
  - 14-day rolling training horizon synthesis tracking acute:chronic workload ratios (ACWR via `BanisterReadinessCore`) and workout density.
  - Multi-session daily state evaluation (`DailyTrainingState`): handles short pre-run primers (`<= 20 min`) while keeping today's main workout available, transitioning cleanly to `.completedToday` once the primary session finishes.

### 3. Strict Hollow View & Display Modal Consolidation (Reverse Air-Gap)
- **Delivered:** V2.5
- **Description:** Complete architectural refactoring enforcing the Hollow View and Display Modal Doctrine across all UI layers.
- **Key Capabilities:**
  - Removed all leaked domain math, physiological thresholds (e.g. `percentZone4 > 0.15`), and interval phase arithmetic from SwiftUI views (`DashboardView`, `WorkoutsView`, `RunDetailView`) and modal builders (`DrillReadout.swift`, `PreRunDrill.swift`).
  - Pure read-only renderers bind directly to immutable `RunalystCore` structs (`DrillScheduleCore`, `PhysiologicalDiagnosisCore`, `SessionSynthesisCore`, `SessionHorizonCore`).
  - "Sweaty Hands" touch-target standards (44x44pt) and `.monospacedDigit()` jitter-free layout across all metrics cards.

### 4. Spec-Driven Development (`openspec/`) & Automated Assay (`./assay.sh`)
- **Delivered:** V2.5
- **Description:** Full institutionalization of OpenSpec change management paired with a 4-tier subagent hierarchy and automated Assay gatekeeper.
- **Key Capabilities:**
  - Every non-trivial change progresses through `proposal.md` -> `specs/` -> `design.md` -> `tasks.md` via `/opsx-propose`, `/opsx-apply`, `/opsx-verify`, and `/opsx-archive`.
  - `./assay.sh` enforces 5 non-negotiable gates: Directory Air-Gap purity, Determinism Air-Gap (zero wall-clock time in Core), SwiftLint strictness, file mass ceilings (`<= 500 LOC`), Grounded Voice lexicon, and Crucible unit testing.

---

## V3 — Future Features

### Multi-Turn Coaching Sessions
- **Status:** Proposed
- **Complexity:** Medium-High
- **Description:** Persist `LanguageModelSession` across follow-up questions so users can ask their coach clarifying questions (e.g., "Why was my HR so high today?") without re-injecting all metric data.
- **Key Challenges:**
  - Session lifetime management (ephemeral per view vs. durable)
  - Apple's 4,096-token ceiling applies to entire conversation window — need truncation strategy after 3–4 turns
  - Structured (`@Generable`) -> unstructured (`String`) transition for follow-up responses
  - Topic guardrails to prevent hallucinated medical/nutrition advice
- **Prerequisite:** Stable V2 release + real user feedback on what follow-up questions people actually ask

### Prompt A/B Testing
- **Status:** Proposed
- **Complexity:** Medium
- **Description:** Instrument prompt variants and measure coaching quality against user satisfaction signals (e.g., drill completion rates, thumbs-up/down on insights).
- **Key Challenges:**
  - Requires a lightweight telemetry/analytics pipeline
  - Need sufficient TestFlight/production volume for statistical significance
  - Privacy-preserving design (no raw biometric data leaves the device)

### Cross-Device iCloud Sync & Ambient Compute Mesh
- **Status:** Proposed
- **Complexity:** Medium-High
- **Description:** Leverage SwiftData + CloudKit to maintain complete workout and coaching consistency across all user devices (iPhone, iPad, Mac), enabling higher-powered hardware (e.g. MacBook Pro M4 or iPad with Apple Silicon) to serve as a private ambient "compute node" for older iPhones (e.g. iPhone 14 and below) that lack on-device Apple Intelligence support.
- **Key Features:**
  - **Seamless SwiftData + CloudKit Synchronization:** Silent, zero-configuration background sync of `RunRecord`, `CoachingInsight`, `DrillRecommendation`, and user action state (`isCompleted`, classification corrections) across all devices sharing the user's Apple ID.
  - **Ambient Compute Mesh (Mac/iPad Inference Offloading):** When an older iPhone records a workout, it syncs the `RunRecord` with `insight == nil` to CloudKit. When the user's Apple Silicon Mac or iPad runs Runalyst (or wakes via silent push), it opportunistically executes `RunAnalyzerActor` using its native on-device `SystemLanguageModel`, writes the generated `CoachingInsight` and drills back to SwiftData, and CloudKit automatically syncs them down to the iPhone.
  - **100% Privacy & Zero Cloud Costs:** Preserves Runalyst's strictly offline-first, privacy-first ethos—no external API keys, third-party servers, or subscriptions required.
  - **Cross-Device Settings Consistency:** Synchronize user preferences (`trainingGoal`, `useMetricSystem`, experience level) across devices using `NSUbiquitousKeyValueStore` or SwiftData profile models.
  - **Older Device Graceful UI:** iPhone 14 UI clearly communicates when coaching insights are pending sync from their Mac/iPad while immediately displaying deterministic form statistics and cadence targets.
- **Key Challenges:**
  - **SwiftData + CloudKit Schema Rules:** CloudKit forbids `@Attribute(.unique)`. Requires dropping `@Attribute(.unique)` from `RunRecord.id` and `TrainingCorrection.id` in a versioned schema migration (`RunalystSchemaV2`), relying on Swift-level deduplication via `hkWorkoutID`.
  - **Attribute Nullability & Defaults:** All model properties must have default values or be marked optional for CloudKit record type validation.
  - **Multiplatform Target (`macOS` / Mac Catalyst):** Enabling macOS target support in `Runalyst.xcodeproj` so the Mac app can share the CoreML / FoundationModels code.
  - **Background Triggering:** Configuring silent CloudKit push subscriptions (`CKDatabaseSubscription`) and `BGAppRefreshTask` to process pending workouts on the Mac even when the window is closed.
- **Prerequisite:** SwiftData CloudKit migration (`RunalystSchemaV2`) and macOS destination setup in `Runalyst.xcodeproj`.

### Cloud Model Fallback
- **Status:** Proposed
- **Complexity:** High
- **Description:** For apple users with no on-device models (iphone 14 and below) we can use apple's private cloud compute.
- **Key Challenges:**
  - Contradicts Runalyst's offline-first, privacy-first philosophy
  - Requires explicit user opt-in and clear data handling disclosures
  - Latency and cost management
  - May not be necessary if on-device models continue improving

### Apple Adaptation / Fine-Tuning
- **Status:** Watching
- **Complexity:** Unknown (depends on Apple API availability)
- **Description:** If Apple exposes model adaptation or fine-tuning APIs for on-device Foundation Models, use accumulated `TrainingCorrection` data to personalize the coaching model per user.

### Apple Watch Companion App & In-Run Metronome
- **Status:** Proposed
- **Complexity:** High
- **Description:** Native watchOS companion app providing live in-run biofeedback, pre-run drill execution, and an on-wrist **Cadence Metronome** (tactile haptic pulses and audio cues) to help runners lock into target cadence bands prescribed by the AI coaching engine (e.g., Cadence Pyramids, Rhythm Intervals, or overstriding correction).
- **Key Features:**
  - **Haptic & Audio Cadence Metronome:** Rhythmic haptic taps (`WKInterfaceDevice.play` / CoreHaptics) and audible clicks calibrated to target SPM (e.g., AI drill targets like 170–175 SPM or user-defined bands).
  - **Intelligent Metronome Modes:**
    - *Continuous Mode:* Steady rhythmic beat for cadence intervals and stride drills.
    - *Intermittent Training Mode:* Periodic bursts (e.g., 30 seconds every 2 minutes) to recalibrate runner rhythm without sensory fatigue.
    - *Cadence Drift Alert Mode:* Silent monitoring that only fires haptic correction pulses when real-time cadence drops below the target floor or baseline.
  - **Pre-Run Drill Guidance:** Standalone on-wrist drill player displaying AI cues (`drillCues`), work/recovery intervals, and target effort zones before starting the main run.
  - **Live Biomechanical Telemetry:** Real-time on-wrist heads-up display of working cadence, heart rate zones, ground contact time, and vertical oscillation during active `HKWorkoutSession`.
- **Key Challenges:**
  - **Battery Optimization & Haptic Duty-Cycle Throttling:** Firing haptics at ~160–180 SPM (~3 Hz) continuously during an hour-long run causes severe battery drain and watchOS thermal/actuator throttling. Requires duty-cycled burst pacing and smart drift-detection triggers.
  - **Timer Precision Under watchOS Power Management:** Maintaining precise metronome intervals without micro-stutter while the watch display is dimmed or asleep during background `HKWorkoutSession` execution.
  - **Audio Session Concurrency:** Seamlessly mixing audible metronome clicks with background music or podcasts using `AVAudioSession` (`.mixWithOthers`, `.duckOthers`) without audio clipping or interruption.
  - **Bidirectional Sync (`WatchConnectivity`):** Reliably synchronizing SwiftData drill recommendations, user cadence targets, and completed workout telemetry between iPhone and watchOS without requiring constant active connectivity.
- **Prerequisite:** Stable V2 WorkoutKit bridge and watchOS target integration in `Runalyst.xcodeproj`.

### HealthKit Heart Rate Zone Integration (iOS 27+)
- **Status:** Proposed
- **Complexity:** Medium
- **Description:** Ingest native HealthKit Heart Rate Zone data (available starting with iOS 27) to capture precise workout intensity distributions (time and percentage in Zones 1–5), measure aerobic efficiency, and power deeper physiological coaching.
- **Key Features:**
  - **Native Zone Breakdown Ingestion:** Extract official Apple Watch heart rate zone durations and user-configured zone thresholds directly from HealthKit instead of relying solely on flat workout averages.
  - **Aerobic Drift & Compliance Coaching:** Feed time-in-zone data into `CoachingEngine` and `RunAnalyzerActor` to detect cardiac drift (e.g., creeping from Zone 2 into Zone 3+ during base runs) and adjust recovery directives accordingly.
  - **Enhanced ML Classification:** Incorporate multi-zone signatures (e.g., `% in Zone 2` vs. `% in Zone 4/5`) into `FramboiseEngine` and `RunalystClassifier` to separate true easy runs from tempo/threshold efforts with high precision.
  - **Workout Adherence Verification:** Compare prescribed `WorkoutBridge` zone targets against post-run zone execution to score workout compliance.
- **Key Challenges:**
  - **OS Availability & Graceful Fallback:** Requires `@available(iOS 27.0, *)` branching with fallback to existing `workingAvgHeartRate` calculations on iOS 26.
  - **SwiftData Schema Migration (`RunalystSchemaV3`):** Safely adding optional zone distribution storage to `RunRecord` while preserving legacy workout records via `RunalystMigrationPlan`.
  - **Token Optimization for FoundationModels:** Formatting multi-zone metrics into ultra-compact strings (e.g., `ZONES: Z1:10%, Z2:75%, Z3:15%`) to stay well within Apple's 4,096-token ceiling.
- **Prerequisite:** iOS 27 SDK availability and SwiftData Schema V3 migration.
