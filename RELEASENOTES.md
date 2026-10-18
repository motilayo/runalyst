# Runalyst v2.5.1 — Interval Segmentation Veracity & Scorecard Polish 🏃‍♂️⚡

Runalyst 2.5.1 introduces key refinements to the core biomechanical signal processing engine (`FramboiseEngine`), hardening interval detection against cardiovascular lag and sensor artifacts, alongside scorecard UI fallbacks for structured workouts.

---

### 🌟 What's New in v2.5.1

#### 1. ⚙️ Dynamic Rolling Baseline Window (`FramboiseEngine`)
- **20-Bucket Centered Window**: Implemented a localized 20-bucket rolling centered baseline window to dynamically track median pace and cadence throughout workouts, preventing baseline collapse during extended warm-ups or recovery periods.
- **Walking Boundary Filter**: Filtered baseline moving buckets to >= 135 SPM, preventing walking recovery periods and cooldowns from artificially pulling down the baseline running pace and turnover thresholds.

#### 2. 🫀 Elimination of Cardiac Lag Merging
- **Disentangled Recovery Jog Heart Rate**: Removed elevated heart rate triggers (`isCardioInclineSurge`) during recovery jog intervals. By relying on biomechanical work indicators (pace surge and cadence turnover relative to the local baseline), the engine prevents adjacent work intervals from falsely merging during active recoveries when heart rate remains elevated due to cardiac lag.

#### 3. 🛡️ Outlier & Micro-Glitch Rejection
- **Artifact Cleansing**: Refined `consolidatePhaseSegments` to filter out brief (<= 16s) sensor spikes occurring at recovery jog paces (> 30s/km slower than typical work reps), cleanly preserving genuine 1-minute sprints while eliminating rogue recovery glitches.
- **Multi-Rep Veracity**: Verified 100% rep preservation across multi-interval and mixed-effort workouts (e.g. 5-rep cadence pyramids and 12-effort mixed treadmill sessions).

#### 4. 📋 Drill Execution Scorecard Fallbacks (`DrillExecutionScorecard`)
- **Defensive Pacing & Duration Fallbacks**: Enhanced `DrillExecutionScorecard` to cleanly fall back to scheduled drill work durations and overall working average pace when individual interval evaluation matching is deferred, eliminating empty badges.

---

### 🛠️ Technical Improvements & Architecture
- **230 Passing Unit & Integration Tests**: 0 failures, 0 regressions across the entire test suite.
- **Strict SwiftLint Gate**: 0 violations across all 110 Swift source files (`--strict`).

---

**Full Changelog**: https://github.com/motilayo/runalyzer/compare/v2.5.0...v2.5.1
