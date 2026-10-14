# System Architecture

Runalyst V2 is built around a unidirectional data flow: fetching from Apple Health, mathematically normalizing the data, running it through CoreML classifiers, and feeding the structured output into Apple FoundationModels for natural language coaching.

For the overarching product manifesto and User-Centered Design philosophy, see [The Runalyst Product & Architecture Blueprint](BLUEPRINT.md).

## High-Level Data Flow

The following Mermaid diagram illustrates the lifecycle of a `RunRecord` from extraction to UI presentation.

```mermaid
graph TD
    A["Apple HealthKit"] -->|"HKWorkout Queries"| B("HealthKitManager")
    B -->|"Raw Metrics"| C{"Framboise Engine"}
    C -->|"Normalizes dead-stops"| D["Working Averages"]
    D --> E("ModelManager / CoreML")
    E -->|"Predicts Class"| F["RunRecord DTO"]
    F -->|"Persisted"| G[("SwiftData SQLite")]
    G -->|"On-Demand Task"| H("RunAnalyzerActor")
    H -->|"Constructs Directive"| I["CoachingEngine"]
    I -->|"System Prompt"| J(("Apple FoundationModels"))
    J -->|"Structured JSON"| K["DrillRecommendation & Insight"]
    K --> G
    G -->|"@Query"| L["SwiftUI Views"]
```

## Core Components

### 1. Data Ingestion (`HealthKitManager.swift`)
**Role**: Extracts raw `HKWorkout` and `HKQuantitySample` data.
**Future Code Context**: When adding new biometrics (e.g., Running Power), add the `HKQuantityTypeIdentifier` to the read request. Do not attempt to calculate working averages here; pass raw arrays of buckets to the `FramboiseEngine`.

### 2. Normalization (`FramboiseEngine.swift`)
**Role**: The deterministic mathematical core. It strips out sensor "dead time" (e.g., heart rate < 40 BPM, pace = 0) to compute *Effective Working Averages*.
**Future Code Context**: Any changes to how fitness metrics are calculated must be made here deterministically. Do NOT rely on the AI/LLM to do math.

### 3. Machine Learning (`ModelManager.swift`)
**Role**: Interfaces with the offline-trained `RunalystClassifier.mlmodel`.
**Future Code Context**: Because CoreML output is non-sendable across Swift 6 strict concurrency boundaries, the `RunalystClassifierOutput` uses `@unchecked Sendable`. If you update the model to output new targets, ensure the Swift interface handles the new labels gracefully.

### 4. Background Processing (`RunAnalyzerActor.swift`)
**Role**: A `@ModelActor` that safely executes the heavy lifting in the background without blocking the UI.
**Future Code Context**: Never pass a `PersistentModel` instance across thread boundaries. Always extract primitive values into a `Sendable` DTO struct, perform the AI generation, and then apply the results back onto the model inside the actor.

### 5. Generative AI (`CoachingEngine.swift`)
**Role**: Sends the computed metrics and historical baselines to the native iOS 26 FoundationModels.
**Future Code Context**: When adding new drill types, add them to the system prompt's allowed ENUM constraint and update the deterministic logic in `RunAnalyzerActor` to flag them. Maintain strict token efficiency by using concise property names.

### 6. Presentation (SwiftUI)
**Role**: Declarative UI binding directly to the local SwiftData cache via `@Query`.
**Future Code Context**: Do not trigger data processing tasks implicitly within `var body`. Use explicit user intents (Pull to Refresh, Button Taps) combined with `.task` or unstructured `Task {}` blocks.

## Concurrency & Actor Isolation

To ensure thread safety and respect Apple's on-device AI rate limits, Runalyst V2 strictly partitions work across actors:

```mermaid
graph TD
    A["HealthKit (Daemon)"] -->|"HKObserverQuery"| B["@MainActor (UI Thread)"]
    C["WCSession (Daemon)"] -->|"WatchConnectivityManager"| B
    
    subgraph UI & Ingestion
    B -->|"ContentView.syncData()"| D[("SwiftData (Main Context)")]
    end
    
    subgraph Background Analytics
    E["@ModelActor (RunAnalyzerActor)"] -->|"Private Background Context"| F[("SwiftData (Background Context)")]
    end
    
    subgraph AI Safety & Queueing
    G["actor ModelInferenceSerializer"] -->|"LanguageModelSession"| H(("Apple Neural Engine"))
    end
    
    B -.->|"Passes PersistentIdentifier (Sendable)"| E
    E -->|"Queues Request"| G
```

1. **`@MainActor`**: Handles SwiftUI views, the view-level SwiftData `ModelContext`, and the newest-first incremental ingestion loop (`ContentView.syncData()`).
2. **`@ModelActor`**: `RunAnalyzerActor` runs on a background executor with its own private `ModelContext`. It is responsible for calculating 30-day relative baselines without blocking the UI. You must never pass a `PersistentModel` to it; only pass `PersistentIdentifier` (which is `Sendable`).
3. **`actor ModelInferenceSerializer`**: Acts as a FIFO queue (using `CheckedContinuation`) to protect Apple's on-device `LanguageModelSession`. Apple's `SensitiveContentAnalysisML` safety filter enforces single-client limits; concurrent calls crash with `Client rate limit exceeded`. This actor serializes all requests.
4. **Background Signals**: `HKObserverQuery` and `WCSessionDelegate` receive events on background daemon threads and dispatch them back to the `@MainActor`.

---

## Architecture Decision Records (ADRs)

Detailed historical decisions, considered alternatives, and invariants are preserved in the [Architecture Decision Records directory](adr/README.md).

