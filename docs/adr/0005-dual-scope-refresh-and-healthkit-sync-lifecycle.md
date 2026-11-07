# 5. Dual-Scope Refresh and HealthKit Synchronization Lifecycle

* **Status**: Accepted
* **Date**: 2026-09-24
* **Deciders**: Runalyst Engineering Team
* **Consulted**: Architecture & Data Engineering Working Group
* **Informed**: Runalyst Core Contributors

## Context and Problem Statement

Runalyst is a local-first iOS application that bridges HealthKit workout data, custom biomechanical analysis engines (`FramboiseEngine`), and on-device AI coaching (`CoachingEngine` / `RunAnalyzerActor`). 

A major usability and architectural discrepancy exists between what users expect when using SwiftUI's pull-down-to-refresh gesture and what the system currently executes:

1. **Dashboard Refresh Skips HealthKit**: Pulling down to refresh on `DashboardView` (`DashboardView.swift:1174`) previously cleared the `@AppStorage` headline text cache and re-prompted the macro LLM (`fetchInsight()`), but **did not trigger HealthKit data synchronization** (`onSync`). If a runner finished a workout on their Apple Watch while Runalyst was backgrounded, pulling to refresh on the dashboard did nothing to import the new run. HealthKit sync was only triggered during view initialization (`.task`).
2. **Missing Baseline Recalculation on Dashboard**: `refreshBaselineVO2Max()` and `fetchRecentGlobalVO2Maxes(limit: 1)` were called on `.task` launch but omitted from `.refreshable`.
3. **The "All-or-Nothing" Re-Ingestion Dilemma**: On `RunDetailView` (`RunDetailView.swift:646`), pull-down-to-refresh re-prompted the AI coaching model with `force: true`. However, it operated exclusively on previously persisted scalars. If new quantity types were added to the ingestion engine (e.g., Stride Length in [ADR 0004](0004-stride-length-biomechanical-analysis.md)) or if run classification algorithms were revised (e.g., Topological Signature Classification in [ADR 0003](0003-topological-signature-classification-for-run-types.md)), the user had no way to refresh a single workout from HealthKit. Their only recourse was the "Resync Health Data & Rebuild AI Insights" button in `SettingsView`, which nukes the entire SwiftData SQLite database, destroys user action history, and forces minutes of sequential LLM re-analysis.
4. **SwiftUI Task Cancellation Vulnerability**: As documented in `AGENTS.md`, SwiftUI `.refreshable` cancels its internal cooperative task if the view hierarchy re-renders during state mutations. Synchronous HealthKit queries and SQLite saves placed directly inside `.refreshable` risk mid-flight aborts.

## Decision Drivers

* **User Mental Model Parity**: Pulling down on the dashboard must check for new workouts and update readiness; pulling down on a specific run must re-query that run's raw metrics and refresh its coaching.
* **Granular Backfilling Without Database Wipes**: Allow individual workouts to incorporate newly supported metrics (like Stride Length or topological classifications) via single-record re-ingestion without resetting user history.
* **Preservation of User-Edited State**: Protect manual user classifications (`TrainingCorrection`), user drill associations, and completed drill states during any re-ingestion.
* **Non-Blocking UI Spinners**: Do not hold the pull-to-refresh UI spinner hostage while on-device LLMs process multi-run queues.
* **Cancellation and Concurrency Safety**: Wrap long-running operations in detached or unstructured tasks per `AGENTS.md` to prevent view re-render cancellations. Guard against race conditions using `isSyncing`.

## Considered Options

* **Option 1 (Dual-Scope Refresh Architecture: Macro Incremental Sync + Targeted Micro Re-Ingestion)**:
  - **Macro Scope (`DashboardView`)**: Guard against `isSyncing` -> trigger incremental HealthKit workout ingestion via unstructured task -> refresh VO2 Max baseline -> invalidate headline cache -> generate fresh macro readiness insight.
  - **Micro Scope (`RunDetailView`)**: Query HealthKit for that specific `hkWorkoutID` -> extract all sample streams (including stride length) -> re-run `FramboiseEngine` working stats and topological classifier -> update SwiftData in-place -> trigger single-run AI coaching.
* **Option 2 (Prompt-Only Refresh + Settings Resync Only - Status Quo)**:
  - Keep pull-to-refresh restricted to re-prompting the LLM with existing scalar data; require users to wipe the entire database in Settings to update any HealthKit metrics or classifications.
* **Option 3 (Full Historical Scan on Dashboard Pull)**:
  - Trigger a full historical re-sync and re-analysis of all runs whenever the dashboard is refreshed. (Rejected: severely violates the "Zero Redundant Compute & Repairs" rule in `AGENTS.md`, causing thermal throttling and battery drain).

## Decision Outcome

Chosen option: **Option 1 (Dual-Scope Refresh Architecture)**, because it aligns user intuition with system behavior, provides non-destructive single-run backfills, and respects device thermal and battery constraints.

---

## Technical Specification & Architecture

### 1. Macro Scope Lifecycle (`DashboardView.swift`)

When the user pulls down on the dashboard:

```text
[Runner] ──(Pull to Refresh)──> [DashboardView]
                                      │
                                      ├── 1. Check !isSyncing (Guard against concurrent syncs)
                                      ├── 2. Task { await onSync(false) } ──> [HealthKit]
                                      │                                            │
                                      │   [SwiftData] <── (Ingest RunRecords) ─────┘
                                      │
                                      ├── 3. fetchRecentGlobalVO2Maxes() + refreshBaselineVO2Max()
                                      ├── 4. Invalidate all @AppStorage headlines (7-day, 30-day, all-time)
                                      ├── 5. fetchInsight() (Macro readiness & trends via LLM)
                                      └── 6. Dismiss spinner + Success Haptic
```

#### Implementation Rules for Macro Scope
1. **Unstructured Task Safety & Spinner Coordination**: Invoke `onSync` inside an unstructured `Task { ... }` and await its value (`_ = await syncTask.value`) so SwiftUI keeps the spinner visible during HealthKit sync while protecting the sync from mid-flight aborts if view re-renders:

```swift
.refreshable {
    guard !isSyncing else { return }
    isSyncing = true
    defer { isSyncing = false }

    let syncTask = Task {
        if let onSync {
            await onSync(false)
        }
    }
    _ = await syncTask.value

    if let vo2s = try? await HealthKitManager.shared.fetchRecentGlobalVO2Maxes(limit: 1), !vo2s.isEmpty {
        globalVO2Max = vo2s[0]
    }
    refreshBaselineVO2Max()
    sanitizeSpuriousDrillTags()

    cachedHeadline7Day = ""
    cachedBody7Day = ""
    cachedHeadline30Day = ""
    cachedBody30Day = ""
    cachedHeadlineAllTime = ""
    cachedBodyAllTime = ""

    fetchInsight()
    UINotificationFeedbackGenerator().notificationOccurred(.success)
}
```
2. **ContentView Async Await**: In `ContentView.swift`, pass an async closure that directly awaits `syncData(force: force)` rather than launching a detached task:

```swift
DashboardView(onSync: { force in
    await syncData(force: force)
})
```

---

### 2. Micro Scope Lifecycle (`RunDetailView.swift`)

When the user pulls down on an individual run detail screen:

```text
[Runner] ──(Pull to Refresh)──> [RunDetailView]
                                      │
                                      ├── 1. HealthKitManager.refreshWorkoutMetrics(for: runRecord, in: context)
                                      │            │
                                      │            ├── Fetch HKWorkout by hkWorkoutID
                                      │            ├── Re-run canonical extractRunRecord() (samples, bucketing, classifier)
                                      │            ├── Check & preserve TrainingCorrection and userLinkedDrill tags
                                      │            └── Mutate runRecord in-place & save to SwiftData
                                      │
                                      ├── 2. CoachingEngine.shared.requestAnalysis(for: runRecord, force: true)
                                      │            └── Recompute 30-day baseline relative to run.date via RunAnalyzerActor
                                      │
                                      └── 3. Render updated CoachingInsight & Drills + Success Haptic
```

#### Canonical Ingestion API on `HealthKitManager`
Implement targeted single-run re-ingestion in `HealthKitManager.swift`, reusing `extractRunRecord`:

```swift
func refreshWorkoutMetrics(for record: RunRecord, in context: ModelContext) async throws {
    guard let workout = try await fetchWorkout(with: record.hkWorkoutID) else {
        throw HKError(.errorNoData)
    }

    // 1. Fetch prior runs for 30-day baseline context
    let targetDate = record.date
    let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: targetDate) ?? targetDate
    let targetRecordID = record.id
    let descriptor = FetchDescriptor<RunRecord>(
        predicate: #Predicate { $0.date >= thirtyDaysAgo && $0.date < targetDate && $0.id != targetRecordID }
    )
    let priorRecords = (try? context.fetch(descriptor)) ?? []
    let priorRuns = priorRecords.map {
        RunBaselineData(
            date: $0.date,
            pace: $0.workingAvgPace > 0 ? $0.workingAvgPace : $0.rawAvgPace,
            hr: $0.workingAvgHeartRate > 0 ? $0.workingAvgHeartRate : $0.rawAvgHeartRate,
            cadence: $0.workingAvgCadence > 0 ? $0.workingAvgCadence : $0.rawAvgCadence,
            duration: $0.duration,
            isPrescribedDrill: $0.framboiseTags.contains("prescribedDrill")
        )
    }

    // 2. Canonical extraction and bucketing
    let engine = FramboiseEngine()
    let dto = try await extractRunRecord(from: workout, engine: engine, priorRuns: priorRuns)

    // 3. Check for existing manual user correction
    let correctionDescriptor = FetchDescriptor<TrainingCorrection>(
        predicate: #Predicate { $0.runRecordID == targetRecordID }
    )
    let hasManualCorrection = (try? context.fetch(correctionDescriptor))?.isEmpty == false

    // 4. Update RunRecord in-place
    if !hasManualCorrection {
        record.detectedTypeRaw = dto.detectedTypeRaw
    }
    record.totalDistanceMeters = dto.totalDistanceMeters
    record.duration = dto.duration
    record.rawAvgPace = dto.rawAvgPace
    record.rawAvgHeartRate = dto.rawAvgHeartRate
    record.rawAvgCadence = dto.rawAvgCadence
    record.workingAvgPace = dto.workingAvgPace
    record.workingAvgCadence = dto.workingAvgCadence
    record.workingAvgHeartRate = dto.workingAvgHeartRate
    record.workingDistanceMeters = dto.workingDistanceMeters
    record.workingDurationSeconds = dto.workingDurationSeconds
    record.isIndoor = dto.isIndoor
    record.rawAvgVerticalOscillation = dto.rawAvgVerticalOscillation
    record.workingAvgVerticalOscillation = dto.workingAvgVerticalOscillation
    record.rawAvgStrideLength = dto.rawAvgStrideLength
    record.workingAvgStrideLength = dto.workingAvgStrideLength
    record.paceCV = dto.paceCV
    record.paceSlope = dto.paceSlope
    record.percentZone4 = dto.percentZone4

    // Preserve user drill intent tags
    var mergedTags = dto.framboiseTags
    if record.framboiseTags.contains("userLinkedDrill") && !mergedTags.contains("userLinkedDrill") {
        mergedTags.append("userLinkedDrill")
    }
    if record.framboiseTags.contains("userUnlinkedDrill") && !mergedTags.contains("userUnlinkedDrill") {
        mergedTags.append("userUnlinkedDrill")
    }
    record.framboiseTags = mergedTags

    try context.save()
}
```

---

## Positive Consequences

* **Intuitive Dashboard Behavior**: Pulling down on the dashboard immediately pulls in runs logged on other devices or Apple Watch during the session.
* **Targeted Recovery from Schema/Algorithm Updates**: When new metrics (like Stride Length in ADR 0004) or new classifiers (like Topological Signatures in ADR 0003) are released, users can refresh specific older runs on demand without wiping their entire app history.
* **User Data Preservation**: User-specified training corrections and completed drill records remain intact.
* **Thermal & Battery Protection**: Preserves the zero-launch-loop invariant while providing deterministic, user-controlled synchronization.

## Negative Consequences / Tradeoffs

* **HealthKit Read Dependency on Detail View**: `RunDetailView` now depends on HealthKit read availability. If HealthKit authorization is denied or revoked, single-run re-ingestion must gracefully fall back to prompt-only re-analysis.
* **Concurrency Coordination**: Multiple views can request HealthKit reads. All entry points must pass through `HealthKitManager` and coordinate state using `isSyncing`.

## Pros and Cons of Considered Options

### Option 1: Dual-Scope Refresh Architecture

* Good, because it solves both macro synchronization and micro backfilling.
* Good, because it eliminates the need to wipe SQLite when testing or rolling out new metrics.
* Good, because it decouples long-running AI queues from UI spinners.
* Bad, because it requires adding a single-run query method to `HealthKitManager`.

### Option 2: Status Quo (Prompt-Only)

* Good, because zero code changes are needed.
* Bad, because the dashboard pull-to-refresh fails to import new runs, frustrating runners.
* Bad, because backfilling new metrics requires a complete database wipe in Settings.

### Option 3: Full Historical Scan on Dashboard Pull

* Good, because all runs are always up to date.
* Bad, because scanning dozens of runs and re-querying HealthKit samples on a simple pull-down destroys battery life and causes severe thermal throttling.
* Bad, because it violates explicit engineering directives in `AGENTS.md`.

---

## Links and References

* [`AGENTS.md`](../../AGENTS.md) — Section 1 (Zero Redundant Compute & Clearing Cache), Section 3 (Data Ingestion Sync & Run Iteration), Section 4 (Race Conditions & Refreshable Modifier).
* [ADR 0003: Topological Signature Classification for Run Types](0003-topological-signature-classification-for-run-types.md).
* [ADR 0004: Incorporating Stride Length into Biomechanical Analysis and Coaching](0004-stride-length-biomechanical-analysis.md).
