# The Runalyst Product & Architecture Blueprint

This is the definitive manifesto for Runalyst. It synthesizes the deterministic Swift backend, Native Tool Calling AI, and Apple-centric User-Centered Design (UCD) into a cohesive, premium product built upon Aarron Walter’s Hierarchy of Needs.

---

### 1. Core Identity: Audience & Purpose

Runalyst exists to democratize elite sports science for the **Data-Rich, Insight-Poor Runner** within the Apple ecosystem.

* **The Translation Mandate:** Convert thousands of raw Apple HealthKit data points into empathetic, actionable coaching English.
* **The Protection Mandate:** Prioritize human biological safety over rigid data through subjective overrides and deterministically calculated recovery timelines.
* **The Progression Mandate:** Replace algorithmic guesswork with locked, mathematically proven pacing and duration bands to safely advance the user toward their goals.

---

### 2. The Foundation (Functional & Reliable)

The backend operates on a strict **"Thick Client, Thin AI"** architecture. The app earns deep user trust because the AI never does math, and the physics engine never hallucinates.

* **Native Tool Calling Orchestration:** The LLM acts purely as a semantic router and translator. It starts with an empty context window and autonomously calls Swift tools (`fetchWorkoutAnalysis`, `fetchIntervalPerformance`, `fetchWorkoutPhysics`, `fetchReadinessAndPrescription`, `fetchAthleteProfile`, `reportSubjectiveDistress`) based on natural language intent.
* **Deterministic Authority:** Swift’s `PhysiologicalDiagnosisEngine` and `TrainingZoneEngine` generate the absolute truth. If the AI advises a user to run at `7:11/km`, it is because Swift explicitly commanded it to.
* **Privacy as a Feature:** Processing is executed via on-device iOS `FoundationModels`. A persistent UI indicator (*"Analyzed on-device"*) guarantees to the user that their sensitive health telemetry and physiological distress reports never leave their iPhone.

---

### 3. Information Architecture: The "Sweaty Hands" UX (Usable)

The app is designed for runners experiencing physiological and cognitive depletion. Navigation requires zero mental effort.

* **The "One Metric" Home Screen:** The overarching philosophy is Signal vs. Noise. The top 60% of the screen displays today’s single directive (e.g., **Zone 2 Aerobic Base • 45 Min**). Deep data is pushed to secondary tabs.
* **Ambient UX (Zero Friction):** The cognitive load drops to absolute zero via interactive Lock Screen and Home Screen widgets. Users can see their clearance status (e.g., **Recovery Day: Full Rest**) without even unlocking their device.
* **The Wrist-First Extension:** The Apple Watch companion app handles execution, not analysis. It displays the locked pacing gauge and delivers targeted haptic alerts if the runner falls out of their prescribed zone, leaving the heavy AI translation exclusively for the iPhone.

---

### 4. Interface & Interaction Design (Pleasurable)

The UI translates raw sports science into a tactile, premium, and inherently transparent experience.

* **Progressive Disclosure (Glass-Box Modals):** The AI outputs clean, conversational advice with highlighted metrics. Tapping a color-coded metric (e.g., **156 SPM**) slides up a native SwiftUI bottom-sheet revealing the exact Swift math behind the number, preserving user agency and proving the app's work.
* **Subjective Distress UI:** A frictionless toggle above the chat labeled *"Feeling off today?"* allows sick or exhausted users to report subjective distress instantly. This triggers the safety override tool, bypassing all performance data to prescribe rest.
* **Honest Transparency (Latency Guards):** When syncing massive datasets from Apple Watch, the UI replaces empty states with a glowing skeleton loader (*"Analyst is processing 12,000 telemetry points..."*), ensuring the user always knows what the system is doing.
* **Subconscious Data Binding:** Adhering to Jacob's Law and Apple's design language, metrics are universally color-coded:
  * **Neon Pink** for Heart Rate
  * **Electric Blue** for Pace
  * **Vibrant Green** for Cadence

---

### 5. Accessibility & Sensory Feedback (A11y)

Accessibility in Runalyst accounts for temporary situational impairments like sun glare, shaking hands, and physical exhaustion.

* **Tactile Navigation:** Extensive use of `UIImpactFeedbackGenerator`. The app delivers a `.light` haptic tick when scrubbing across pace charts to count splits by feel, and a `.rigid` thud for state confirmations.
* **Visual Precision:** Massive hit targets (44x44pt minimum) accommodate shaking thumbs. `SF Pro Rounded` is paired with strictly `.monospacedDigit()` for all biometric outputs to prevent horizontal jitter when data updates in real-time. Icons and text dynamically scale via `@ScaledMetric`.
* **Semantic VoiceOver:** Post-run biometric cards use `.accessibilityElement(children: .combine)`. Instead of reading disconnected UI elements, the screen reader fluidly synthesizes the data: *"Cadence Stable, 156 Steps Per Minute."*

---

By strictly enforcing this blueprint, Runalyst ceases to be a generic AI wrapper and becomes a definitive, Apple-native sports science tool—where the technology entirely disappears, leaving only the coaching.
