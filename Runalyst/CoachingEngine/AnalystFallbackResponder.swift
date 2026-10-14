import Foundation
import SwiftData

/// Generates data-grounded coaching responses when running in offline or fallback environments.
@MainActor
enum AnalystFallbackResponder {
    static func generateResponse(
        for userQuestion: String,
        turnContext: ManagedTurnContext? = nil,
        analysis: WorkoutAnalysisContext,
        runRecord: RunRecord
    ) -> String {
        let q = userQuestion.lowercased().replacingOccurrences(of: "’", with: "'")

        // 1. Subjective distress override
        if turnContext?.isSubjectiveDistress == true || q.contains("fever") || q.contains("feel sick") || q.contains("feeling sick") || q.contains("have a cold") || q.contains("flu") {
            return "When you're dealing with illness, fever, or acute physical distress, training takes a back seat. Prioritize sleep, hydration, and full rest until your symptoms fully resolve."
        }

        // 2. Out-of-scope inquiry
        if turnContext?.turnDomain == .outOfScopeInquiry {
            return "I'm your personal running coach and exercise physiologist, so I specialize in your running biomechanics, training zones, and recovery. What would you like to explore regarding your runs?"
        }

        // 2.5. Workout Comparison (e.g. "compare this run to my September 14 run", "vs last week", "compare to previous intervals")
        let isComparisonIntent = q.contains("compare") || q.contains("versus") || q.contains(" vs ") || q.contains(" vs. ") || q.contains("difference between") || q.contains("how does this compare")
        if isComparisonIntent {
            if let prior = HistoricalRunMatcher.findRun(matching: userQuestion, relativeTo: runRecord, in: runRecord.modelContext) {
                return HistoricalRunMatcher.compare(current: runRecord, with: prior).summary
            } else {
                return "I looked through your workout history, but couldn't find a matching run to compare. If you have a specific date (e.g. 'September 14') or run type in mind, let me know!"
            }
        }

        // 3. Composite Query: Workout Exertion / Heart Rate + Tomorrow Planning
        let hasWorkoutExertionIntent = q.contains("heart") || q.contains("hr") || q.contains("spike") || q.contains("challenging") || q.contains("hard") || q.contains("tiring") || q.contains("drift")
        let hasFuturePlanningIntent = q.contains("tomorrow") || q.contains("next run") || q.contains("rest day") || q.contains("can i run") || q.contains("should i rest")

        if hasWorkoutExertionIntent && hasFuturePlanningIntent {
            let workoutCause: String
            if analysis.cardiacDriftMagnitudeBPM >= 8 {
                let envNote = analysis.isIndoor ? "—amplified by the treadmill's lack of convective wind cooling" : ""
                workoutCause = "In your \(analysis.workoutWeekday) run, cardiac drift (**+\(analysis.cardiacDriftMagnitudeBPM) BPM** rise in the second half) was the primary driver of elevated exertion. Your cardiovascular system worked harder to maintain pace\(envNote)."
            } else {
                workoutCause = "In your \(analysis.workoutWeekday) run, your heart rate tracked your pace consistently with steady aerobic coupling."
            }

            let restPhrase = analysis.daysSinceWorkout > 0
                ? "You have had **\(analysis.daysSinceWorkout) days of rest** since that run."
                : "Looking at your recovery status for tomorrow:"
            let readinessNote = analysis.recoveryTimeline.readyForHard
                ? "Your current recovery status is **\(analysis.recoveryTimeline.state.rawValue)**, meaning your aerobic system has recovered and you are cleared for training."
                : "Your recovery status is **\(analysis.recoveryTimeline.state.rawValue)**, so keep tomorrow's effort disciplined and easy."
            let prescription = "Next recommended session: **\(analysis.lockedPrescription.nextSessionName)** (**\(analysis.lockedPrescription.prescribedDurationBand)** at **\(analysis.lockedPrescription.prescribedPaceBand)**)."

            return "\(workoutCause)\n\n\(restPhrase) \(readinessNote) \(prescription)"
        }

        // 4. Heart Rate, Steady vs Tiring Out, Cardiac Drift
        if q.contains("heart") || q.contains("hr") || q.contains("tiring out") || q.contains("tired out") || q.contains("drift") || q.contains("spike") || (q.contains("steady") && !q.contains("cadence")) {
            switch analysis.physiologicalVerdicts.cardiac {
            case .thermalOrCardiovascularDrift(let drift, let dur, _):
                let envDetail = analysis.isIndoor
                    ? "On a flat treadmill deck, zero forward wind resistance and stagnant indoor air impair sweat evaporation, causing internal thermal accumulation that drove this heart rate drift."
                    : "This pattern reflects aerobic decoupling, where internal thermal strain or cardiovascular fatigue required your heart to pump faster to maintain pace."
                return "Your heart rate did not stay completely steady: it climbed by **+\(drift) BPM** over the final \(dur) minutes of the run. \(envDetail)"
            case .elevationInducedCardiacSurge(_, let rise, _):
                return "Your heart rate surged by **+\(rise) BPM** due to uphill climbing and grade resistance, rather than a loss of aerobic fitness."
            case .pacingOvershootDecoupling(let paceDelta, let hrRise, _):
                return "Your heart rate climbed by **+\(hrRise) BPM** because you started **\(paceDelta)s/km** faster than your sustainable pace, accumulating early fatigue."
            case .thermalStrain(let heatIndex):
                return "Your heart rate experienced high thermal strain decoupling due to elevated ambient temperature and humidity (**Heat Index: \(heatIndex)**)."
            case .stableCardiovascularCoupling(let avgHR):
                return "Your heart rate stayed steady throughout the run, averaging **\(avgHR) BPM** with strong aerobic stability and minimal cardiac drift."
            }
        }

        // 5. Why Run Felt Challenging / Breakdown
        let isChallengingIntent = q.contains("challenging") || q.contains("why did this run feel") || q.contains("breakdown")
        let isGeneralBreakdown = q.contains("break down") && !q.contains("split") && !q.contains("interval") && !q.contains("rep")
        if isChallengingIntent || isGeneralBreakdown {
            var reasons: [String] = []
            if analysis.cardiacDriftMagnitudeBPM >= 8 {
                reasons.append("cardiac drift (**+\(analysis.cardiacDriftMagnitudeBPM) BPM** rise)")
            }
            if analysis.isSubFloorCadence {
                reasons.append("cadence dropping below your **\(analysis.runnerProfile.heightAdjustedCadenceFloor) SPM** floor")
            }
            if reasons.isEmpty {
                reasons.append("holding a working pace of **\(analysis.workingPaceFormatted)** across the session")
            }
            let envNote = analysis.isIndoor ? " On the treadmill, the absence of natural convective airflow also increases thermal strain." : ""
            let focusNote = analysis.overallGradeReport.focus.map { " Focus: \($0)." } ?? ""
            return "This run felt challenging primarily due to \(reasons.joined(separator: " and ")).\(envNote)\(focusNote)"
        }

        // 6. Running Economy & Stride Efficiency
        if q.contains("economy") || q.contains("efficiency") {
            let floor = analysis.runnerProfile.heightAdjustedCadenceFloor
            if let ef = analysis.efficiencyFactor, ef > 0 {
                let efFormatted = String(format: "%.2f", ef)
                let deltaNote = analysis.efficiencyFactorDeltaPercent.map { String(format: " (%+.1f%% vs baseline)", $0) } ?? ""
                return "Your running Efficiency Factor was **\(efFormatted)**\(deltaNote), reflecting speed produced per heartbeat. Your stride archetype is **\(analysis.strideArchetype)** with an average cadence of **\(analysis.workingCadence) SPM** (calibrated against your **\(floor) SPM** height floor)."
            } else {
                return "Your stride archetype is **\(analysis.strideArchetype)** with an average cadence of **\(analysis.workingCadence) SPM** (calibrated against your **\(floor) SPM** height floor). At a working pace of **\(analysis.workingPaceFormatted)**, your stride turnover provided solid mechanical efficiency."
            }
        }

        // 7. Training Goal Progress
        if q.contains("goal") || q.contains("build toward") || q.contains("progress") {
            return "This \(analysis.detectedType) session builds aerobic volume toward your active goal of **\(analysis.runnerProfile.trainingGoal)**. Your current 30-day cumulative load is **\(analysis.runnerProfile.loadSummary)**."
        }

        // 8. Treadmill Overstriding / Form Focus
        if q.contains("overstride") || (q.contains("treadmill") && (q.contains("form") || q.contains("reach"))) {
            let floor = analysis.runnerProfile.heightAdjustedCadenceFloor
            if analysis.workingCadence < floor {
                return "On the treadmill, your cadence was **\(analysis.workingCadence) SPM** (below your **\(floor) SPM** height floor), which can lead to overstriding and braking forces. Focus on landing with your feet directly underneath your hips and driving your elbows backward."
            } else {
                return "Your cadence was **\(analysis.workingCadence) SPM**, safely above your **\(floor) SPM** floor. You maintained quick foot turnover, minimizing braking forces on the belt."
            }
        }

        // 9. Splits, intervals, and pacing segments
        let isSegmentEvalIntent = q.contains("split") || q.contains("interval") || q.contains("segment") || q.contains("lap") || q.contains("fastest") || q.contains("slowest") || q.contains("performance") || q.contains("rep")
        if isSegmentEvalIntent {
            return analysis.formatPerformanceReport()
        }

        // 10. Arm Drive & Upper Body Mechanics
        if q.contains("arm drive") || q.contains("arm swing") || q.contains("arms") {
            return "Active arm drive establishes your stride rhythm and balances pelvic rotation. Driving your elbows straight back (at roughly a 90° angle) stabilizes your torso, prevents lateral twisting, and helps maintain cadence turnover as fatigue sets in."
        }

        // 11. Drills & Form Exercises
        if q.contains("drill") || q.contains("exercise") {
            if let drill = runRecord.insight?.drillRecommendations?.first {
                let target = drill.targetCadence.map { " Target cadence: **\($0) SPM**." } ?? ""
                let purpose = drill.drillPurpose.map { " Purpose: \($0)." } ?? ""
                return "The most effective drill for this workout is **\(drill.drillTitle)**.\(purpose)\(target) Incorporate this during your warm-up to reinforce proper motor patterns."
            } else if analysis.workingCadence < analysis.runnerProfile.heightAdjustedCadenceFloor {
                return "I recommend **Cadence Pyramids** or **Strides** during your warm-up to train your turnover up toward your **\(analysis.runnerProfile.heightAdjustedCadenceFloor) SPM** height floor."
            } else {
                return "I recommend **Strides** (4–6 x 20-second relaxed accelerations) during your warm-up to reinforce neuromuscular sharpness and quick foot turnover."
            }
        }

        // 12. What to Improve / Weakness / Performance Degradation
        if q.contains("improv") || q.contains("weakness") || q.contains("weak point") || q.contains("focus on") || q.contains("critique") || q.contains("degradation") || q.contains("faded") || q.contains("drop-off") {
            if q.contains("degradation") || q.contains("faded") || q.contains("drop-off") {
                if analysis.hasCardiacDrift {
                    return "Mechanically your stride remained consistent, but your heart rate rose by **+\(analysis.cardiacDriftMagnitudeBPM) BPM** in the second half, indicating cardiovascular decoupling."
                } else if analysis.pacingTrendDescription.contains("fade") {
                    return "Toward the end of your run, you experienced a \(analysis.pacingTrendDescription.lowercased())."
                } else {
                    return "I didn't detect significant degradation toward the end of your run: your cadence, pace, and heart rate stayed remarkably stable across the final kilometers."
                }
            }
            if analysis.workingCadence < analysis.runnerProfile.heightAdjustedCadenceFloor {
                return "The primary area to improve is foot turnover: at **\(analysis.workingCadence) SPM**, your cadence was below your **\(analysis.runnerProfile.heightAdjustedCadenceFloor) SPM** floor. Focus on quicker, lighter steps under your hips."
            }
            let cadenceContext = "Your cadence was solid at **\(analysis.workingCadence) SPM** with disciplined foot turnover."
            if let focus = analysis.overallGradeReport.focus {
                let cleanFocus = focus.hasPrefix("your ") ? String(focus.dropFirst(5)) : focus
                if q.contains("form") {
                    return "\(cadenceContext) For your running form, focus on: \(cleanFocus)."
                }
                return "\(cadenceContext) Key area to improve: \(focus)."
            } else {
                if q.contains("form") {
                    return "Your running form remained disciplined throughout—at **\(analysis.workingCadence) SPM**, focus on maintaining quick foot turnover and a relaxed upper body in your next run."
                }
                return "There is no obvious weak spot in this session—at **\(analysis.workingCadence) SPM**, your foot turnover, pacing, and heart rate remained stable throughout."
            }
        }

        // 13. Future Training, Recovery & Readiness
        if q.contains("can i") || q.contains("ready") || q.contains("recovery") || q.contains("rest") || q.contains("tomorrow") || q.contains("next run") || q.contains("what pace") || q.contains("how long") || q.contains("push hard") || q.contains("how hard") || q.contains("push") {
            let recoveryNote: String
            if analysis.recoveryTimeline.readyForHard {
                recoveryNote = "Your recovery status is **\(analysis.recoveryTimeline.state.rawValue)**: fully recovered and cleared for your next workout."
            } else {
                recoveryNote = "Your recovery status is **\(analysis.recoveryTimeline.state.rawValue)**: in active recovery until \(analysis.recoveryTimeline.earliestHardPhrase)."
            }
            return "\(recoveryNote) Next Recommended Session: **\(analysis.lockedPrescription.nextSessionName)** (**\(analysis.lockedPrescription.prescribedDurationBand)** at **\(analysis.lockedPrescription.prescribedPaceBand)**). \(analysis.lockedPrescription.sessionRationale)"
        }

        // 14. Effort & Workout Exertion (Past session inquiry)
        if q.contains("effort") || q.contains("exertion") || q.contains("intensity") {
            let hr = Int(runRecord.workingAvgHeartRate)
            let pace = PaceFormatter.formatPace(secondsPerKilometer: runRecord.workingAvgPace)
            let driftNote = analysis.cardiacDriftMagnitudeBPM >= 8
                ? "You experienced **+\(analysis.cardiacDriftMagnitudeBPM) BPM** of cardiac drift in the second half, indicating late fatigue."
                : "Your cardiovascular system maintained stable aerobic coupling throughout."
            return "Your effort during this **\(analysis.detectedType)** was sustained at an average heart rate of **\(hr) BPM** and pace of **\(pace)**. \(driftNote)"
        }

        // 15. Cadence, Turnover & Rhythm
        let mentionsForm = (q.contains("form") && !q.contains("performance")) || q.contains("technique")
        if q.contains("cadence") || q.contains("rhythm") || q.contains("turnover") || q.contains("spm") || mentionsForm {
            let floor = analysis.runnerProfile.heightAdjustedCadenceFloor
            if analysis.workingCadence < floor {
                return "Your cadence was **\(analysis.workingCadence) SPM**, which is below your **\(floor) SPM** height-adjusted floor. Focus on shorter, lighter steps under your hips to improve turnover."
            } else {
                return "Your cadence was **\(analysis.workingCadence) SPM**, maintaining a healthy turnover above your **\(floor) SPM** height-adjusted floor. Stride rhythm remained disciplined."
            }
        }

        // 16. Highlights / What Went Well
        if q.contains("went well") || q.contains("highlight") || q.contains("positive") || q.contains("strengths") || q.contains("good about") {
            let strengths = analysis.overallGradeReport.strengths.joined(separator: ". ")
            return "Here is what went well: \(strengths)."
        }

        // 17. Grade and Performance Evaluation
        if (q.contains("grade") || q.contains("score") || q.contains("how did i do") || q.contains("rate my") || q.contains("rating")) && !q.contains("heart") && !q.contains("split") {
            return analysis.overallGradeReport.sentence
        }

        // 18. Sensor queries (vertical oscillation, stride length)
        if q.contains("vertical") || q.contains("bounce") || q.contains("oscillation") {
            if let osc = runRecord.workingAvgVerticalOscillation {
                return "Your vertical bounce was **\(String(format: "%.1f", osc)) cm**."
            } else {
                return "Vertical oscillation wasn't recorded for this workout because it was an indoor treadmill run. Apple Watch measures vertical bounce outdoors or when paired with an authentic footpod."
            }
        }
        if q.contains("stride") {
            if let stride = runRecord.workingAvgStrideLength {
                return "Your average stride length was **\(String(format: "%.2f", stride)) m**."
            } else {
                return "Stride length wasn't recorded for this workout because it was an indoor treadmill run without a footpod."
            }
        }

        // 19. Classification explanations
        if q.contains("why") && (q.contains("label") || q.contains("classif") || q.contains("mixed")) {
            let type = runRecord.detectedTypeRaw.isEmpty ? "Run" : runRecord.detectedTypeRaw
            let reason = runRecord.needsInclineReview == true
                ? "surges and cadence drops on the treadmill indicated incline intervals."
                : "repeated pace surges and irregular work/recovery intervals."
            return "This session was classified as **\(type)** due to \(reason)"
        }

        // 20. Calendar / Day queries
        if q.contains("what day is") || q.contains("what is today") || q.contains("what date is") {
            return "Today is \(analysis.currentWeekday), \(analysis.currentDateFormatted)."
        }

        // 21. Runner clarification (didn't run today / yesterday)
        if q.contains("didn't run") || q.contains("didnt run") || q.contains("haven't run") || q.contains("havent run") {
            let timeframe = q.contains("yesterday") ? "yesterday" : "today"
            return "Understood—today is \(analysis.currentWeekday), and you haven't run \(timeframe). You have **\(analysis.daysSinceWorkout) days of rest** since your last session on \(analysis.workoutWeekday)."
        }

        // 22. Concept education
        if q.contains("what is") || q.contains("what does") || q.contains("meaning of") || q.contains("define") {
            if q.contains("vo2") {
                return "VO2 Max is the maximum volume of oxygen your body can process per minute during peak exertion. It serves as a benchmark for aerobic power and endurance capacity."
            }
            if q.contains("threshold") {
                return "Lactate threshold is the running intensity where lactic acid begins accumulating in the bloodstream faster than it can be cleared. Running at or just below this pace improves endurance sustainability."
            }
            if q.contains("drift") || q.contains("decoupling") {
                return "Cardiac drift (aerobic decoupling) occurs when your heart rate drifts upward over time despite holding a constant pace, typically driven by rising core temperature, dehydration, or fatigue."
            }
        }

        // 23. Default: Coach overview
        let pace = PaceFormatter.formatPace(secondsPerKilometer: runRecord.workingAvgPace)
        let cad = Int(runRecord.workingAvgCadence)
        let hr = Int(runRecord.workingAvgHeartRate)
        return "During your **\(analysis.detectedType)** on **\(analysis.workoutWeekday)**, you held an average pace of **\(pace)** with a heart rate of **\(hr) BPM** and cadence of **\(cad) SPM**. \(analysis.overallGradeReport.sentence)"
    }
}

// MARK: - Historical Run Matcher & Comparison

/// Deterministic matching and mathematical comparison between the active workout and a historical workout.
@MainActor
struct HistoricalRunMatcher {

    struct ComparisonReport: Sendable {
        let currentRunDate: Date
        let currentRunType: String
        let currentPaceSec: Double
        let currentCadence: Int
        let currentHeartRate: Int
        let currentDistanceMeters: Double
        let currentDurationSeconds: Double

        let priorRunDate: Date
        let priorRunType: String
        let priorPaceSec: Double
        let priorCadence: Int
        let priorHeartRate: Int
        let priorDistanceMeters: Double
        let priorDurationSeconds: Double
        let priorIsIndoor: Bool

        // Deltas
        let paceDeltaSeconds: Int        // prior - current: positive = current is faster
        let cadenceDelta: Int            // current - prior: positive = current is higher
        let heartRateDelta: Int          // current - prior: positive = current is higher

        // Formatted Text
        let summary: String
    }

    /// Finds a historical run in the model context matching the user's natural language query.
    static func findRun(
        matching query: String,
        relativeTo currentRun: RunRecord,
        in context: ModelContext?
    ) -> RunRecord? {
        guard let context = context else { return nil }
        let descriptor = FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        guard let allRuns = try? context.fetch(descriptor) else { return nil }

        let otherRuns = allRuns.filter { $0.id != currentRun.id }
        guard !otherRuns.isEmpty else { return nil }

        let lower = query.lowercased()

        // 1. Month + Day parsing (e.g., "September 14", "Sep 14", "Sept 14", "9/14")
        let months: [(name: String, number: Int)] = [
            ("january", 1), ("jan", 1),
            ("february", 2), ("feb", 2),
            ("march", 3), ("mar", 3),
            ("april", 4), ("apr", 4),
            ("may", 5),
            ("june", 6), ("jun", 6),
            ("july", 7), ("jul", 7),
            ("august", 8), ("aug", 8),
            ("september", 9), ("sept", 9), ("sep", 9),
            ("october", 10), ("oct", 10),
            ("november", 11), ("nov", 11),
            ("december", 12), ("dec", 12)
        ]

        let matchedMonth = months.first(where: { lower.contains($0.name) })?.number

        let calendar = Calendar.current
        if let m = matchedMonth {
            // Find integers in the query string
            let tokens = lower.components(separatedBy: CharacterSet.alphanumerics.inverted)
            for token in tokens {
                let cleaned = token
                    .replacingOccurrences(of: "st", with: "")
                    .replacingOccurrences(of: "nd", with: "")
                    .replacingOccurrences(of: "rd", with: "")
                    .replacingOccurrences(of: "th", with: "")
                if let day = Int(cleaned), day >= 1 && day <= 31 {
                    // Look for exact month + day match
                    if let exact = otherRuns.first(where: {
                        let comps = calendar.dateComponents([.month, .day], from: $0.date)
                        return comps.month == m && comps.day == day
                    }) {
                        return exact
                    }
                }
            }

            // Fallback: closest run in that month
            if let monthRun = otherRuns.first(where: { calendar.component(.month, from: $0.date) == m }) {
                return monthRun
            }
        }

        // 2. Relative keywords (e.g. "previous run", "last run", "prior run")
        if lower.contains("last run") || lower.contains("previous run") || lower.contains("prior run") {
            return otherRuns.first(where: { $0.date < currentRun.date }) ?? otherRuns.first
        }

        // 3. Modality keywords (e.g. "previous intervals", "last tempo", "last long run")
        let modalities = ["intervals", "tempo", "easy", "steady", "recovery", "pyramids", "fartlek", "progression", "hill repeats", "long run"]
        for modality in modalities where lower.contains(modality) {
            if let matched = otherRuns.first(where: {
                $0.date < currentRun.date && $0.normalizedClassification.lowercased().contains(modality)
            }) {
                return matched
            }
        }

        // 4. Default: most recent prior run before this one
        return otherRuns.first(where: { $0.date < currentRun.date }) ?? otherRuns.first
    }

    /// Builds a deterministic comparison between the current run and a matched historical run.
    static func compare(current: RunRecord, with prior: RunRecord) -> ComparisonReport {
        let currentPace = current.workingAvgPace > 0 ? current.workingAvgPace : current.rawAvgPace
        let priorPace = prior.workingAvgPace > 0 ? prior.workingAvgPace : prior.rawAvgPace
        let paceDeltaSec = Int(priorPace - currentPace) // > 0 means current is faster

        let currentCad = Int(current.workingAvgCadence > 0 ? current.workingAvgCadence : current.rawAvgCadence)
        let priorCad = Int(prior.workingAvgCadence > 0 ? prior.workingAvgCadence : prior.rawAvgCadence)
        let cadDelta = currentCad - priorCad

        let currentHR = Int(current.workingAvgHeartRate > 0 ? current.workingAvgHeartRate : current.rawAvgHeartRate)
        let priorHR = Int(prior.workingAvgHeartRate > 0 ? prior.workingAvgHeartRate : prior.rawAvgHeartRate)
        let hrDelta = currentHR - priorHR

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "EEEE, MMMM d"

        let currentFormattedDate = dateFormatter.string(from: current.date)
        let priorFormattedDate = dateFormatter.string(from: prior.date)

        let currentPaceStr = PaceFormatter.formatPace(secondsPerKilometer: currentPace)
        let priorPaceStr = PaceFormatter.formatPace(secondsPerKilometer: priorPace)

        let paceChangeText: String
        if paceDeltaSec > 0 {
            paceChangeText = "**+\(paceDeltaSec)s/km faster**"
        } else if paceDeltaSec < 0 {
            paceChangeText = "**\(abs(paceDeltaSec))s/km slower**"
        } else {
            paceChangeText = "identical pace"
        }

        let cadChangeText: String
        if cadDelta > 0 {
            cadChangeText = "**+\(cadDelta) SPM** higher turnover"
        } else if cadDelta < 0 {
            cadChangeText = "**\(cadDelta) SPM** lower turnover"
        } else {
            cadChangeText = "matched turnover"
        }

        let hrChangeText: String
        if hrDelta > 0 {
            hrChangeText = "**+\(hrDelta) BPM** higher cardiac cost"
        } else if hrDelta < 0 {
            hrChangeText = "**\(abs(hrDelta)) BPM** lower cardiovascular cost"
        } else {
            hrChangeText = "identical average heart rate"
        }

        let currentType = current.detectedTypeRaw.isEmpty ? current.normalizedClassification : current.detectedTypeRaw
        let priorType = prior.detectedTypeRaw.isEmpty ? prior.normalizedClassification : prior.detectedTypeRaw

        // Takeaway synthesis
        var takeaway: String
        if paceDeltaSec > 0 && hrDelta <= 0 {
            takeaway = "Clear aerobic efficiency progression: you sustained a faster pace with lower cardiovascular strain and \(cadChangeText)."
        } else if paceDeltaSec > 0 && hrDelta > 0 {
            takeaway = "You pushed the pace significantly faster, which naturally elevated cardiovascular demand."
        } else if paceDeltaSec <= 0 && hrDelta < 0 {
            takeaway = "Disciplined aerobic containment: you ran at an easier pace and kept your heart rate well controlled."
        } else {
            takeaway = "Consistent pacing and turnover relative to your prior session."
        }

        let summary = """
        Comparing your **\(currentFormattedDate) \(currentType)** to your **\(priorFormattedDate) \(priorType)**:

        • **Pace**: **\(currentPaceStr)** vs **\(priorPaceStr)** (\(paceChangeText))
        • **Cadence**: **\(currentCad) SPM** vs **\(priorCad) SPM** (\(cadChangeText))
        • **Heart Rate**: **\(currentHR) BPM** vs **\(priorHR) BPM** (\(hrChangeText))

        \(takeaway)
        """

        return ComparisonReport(
            currentRunDate: current.date,
            currentRunType: currentType,
            currentPaceSec: currentPace,
            currentCadence: currentCad,
            currentHeartRate: currentHR,
            currentDistanceMeters: current.totalDistanceMeters,
            currentDurationSeconds: current.duration,
            priorRunDate: prior.date,
            priorRunType: priorType,
            priorPaceSec: priorPace,
            priorCadence: priorCad,
            priorHeartRate: priorHR,
            priorDistanceMeters: prior.totalDistanceMeters,
            priorDurationSeconds: prior.duration,
            priorIsIndoor: prior.isIndoor ?? false,
            paceDeltaSeconds: paceDeltaSec,
            cadenceDelta: cadDelta,
            heartRateDelta: hrDelta,
            summary: summary
        )
    }
}
