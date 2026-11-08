# Runalyst v2.8.0 — Siri AI App Intents, Apple Fitness Awards, Live Cadence Metronome & Interval Synthesis 🏃‍♂️🏅

Runalyst 2.8.0 delivers an expansive update to intelligence, motivation, and auditory coaching: hands-free voice interactions with Siri AI and App Intents, visual recognition through Apple Fitness-style 3D milestone medallions with deep workout provenance, a live audio-haptic cadence metronome, unified working metric parity, and multi-signal interval corroboration across the entire app.

---

### 🌟 What's New in v2.8.0

#### 1. 🎙️ Siri AI, App Intents & Spotlight Semantic Indexing (#169)
- **Deep Siri Voice Integration**: Ask Siri about your recovery, training directives, and log subjective fatigue with hands-free App Intents:
  - `CheckReadinessIntent`: Query today's ACWR score, fatigue flags, and Banister readiness balance with instant conversational speech.
  - `GetPrescribedWorkoutIntent`: Surface your next prescribed workout, target duration, cadence band, and warmup structure.
  - `ReportSubjectiveDistressIntent`: Instantly record physical distress or soreness directly into your biological training model.
- **Native Siri Snippet Views**: Custom, glanceable Liquid Glass interface snippets rendered natively inside Siri (`SiriReadinessSnippetView`, `SiriWorkoutSnippetView`, and `SiriDistressSnippetView`).
- **RunalystAppShortcuts**: Zero-configuration phrases ready in the iOS Shortcuts app ("Check my readiness on Runalyst", "What's my workout on Runalyst?").
- **Spotlight Semantic Indexing**: `RunRecordAppEntity` conforms to `AppEntity` and `IndexedEntity`, automatically donating ingested HealthKit workouts to iOS Spotlight Search for instant device-wide recall.

#### 2. 🏅 Apple Fitness-Style Milestone Medallions & Workout Provenance (#170)
- **3D Metallic Medallion Grid**: Redesigned Lifetime Milestones card featuring Apple Fitness-inspired metallic finishes and geometry (`circleRecord` for Personal Bests, `splitHorizonDistance` for Lifetime Distance thresholds, and `hexagonStreak` for Consecutive Day streaks).
- **Earned Metric Subtitles & Repeat Pills**: Clean contextual labels under each medallion with subtle counter badges (e.g., `2x`, `8x`) celebrating repeat achievements.
- **Interactive Award Detail Sheet**: Tapping any medallion opens `MilestoneAwardDetailSheet` with inspiring narrative prose, historical achievement dates, and qualifying metrics.
- **Direct Workout Provenance Navigation**: Every milestone card links directly to its clinching workout via an interactive provenance card that pushes `RunDetailView` onto the view stack.
- **Bracketed Distance Tier Logic**: Mathematically sound distance tier allocation (`selectBestTierRun`) pairing standard distances (5K, 10K, Half Marathon, Marathon) with your fastest authentic pace, plus chronological volume-clinching provenance (`clinchingVolumeRun`).

#### 3. 🥁 Live Cadence Beat Player & Audio-Haptic Metronome (#169, #170)
- **Pure Domain Engine (`LiveMetronomeCore`)**: Mathematically exact BPM-to-interval clock calculations, cadence deviation thresholds, and tempo scaling.
- **Interactive Cadence Beat Preview**: Auditory and haptic preview player integrated directly into `DrillInterstitialReadoutView` before starting primer drills.
- **Non-Ducking Synthetic Audio**: Generates crisp, wooden-block percussion audio pulses using `.playback` + `.mixWithOthers` audio session configuration so your running music and podcasts never cut out.
- **Synchronized Haptic Pulses**: Pairs each auditory beat with a tactile `.light` UI feedback pulse for rhythmic muscle memory.

#### 4. 📊 Interval Segmentation, Working Metric Parity & Accessibility (#167, #168, #169, #170)
- **Unified Working Metric Parity**: Standardized `effectiveWorkingAvgPace`, `effectiveWorkingDistanceMeters`, and `effectiveWorkingDurationSeconds` across Dashboard run rows, `RunDetailView` hero banners, and Milestone calculations, eliminating dead-stop distortions.
- **Multi-Signal Interval Corroboration**: Rigorous sub-20s phase debouncing with multi-stream corroboration between cadence spikes and pace surges to classify fartleks, track reps, and progression runs.
- **Inline Rep Disclosure Chevrons**: Interactive expansion for interval workouts disclosing individual work and recovery splits.
- **VoiceOver Audio Graphs**: Full `AXChartDescriptorRepresentable` implementation across `HeartRateTrajectoryMapView`, `RunVarianceMapView`, and `ProgressionChartView`, enabling vision-impaired runners to hear their workout trends as continuous pitch-modulated sound.

---

### 🛠️ Technical Improvements & Architecture
- **413 Passing Tests**: 302 unit and integration tests in `RunalystTests` plus 111 crucible tests across 20 suites in `RunalystCore` with 0 failures and 0 regressions.
- **Strict SwiftLint & Constitutional Gate**: 0 violations across all 138 Swift source files validated via `./assay.sh`.
- **Version Bump**: `CFBundleShortVersionString` set to `2.8.0` (Build `11`), with updated website deployment metadata.

---

**Full Changelog**: https://github.com/motilayo/runalyst/compare/v2.7.0...v2.8.0
