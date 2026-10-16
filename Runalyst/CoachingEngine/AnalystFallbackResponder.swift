import Foundation
import SwiftData

/// Generates data-grounded coaching telemetry responses when running in offline, test, or fallback environments.
@MainActor
enum AnalystFallbackResponder {
    static func generateResponse(
        for userQuestion: String,
        turnContext: ManagedTurnContext? = nil,
        analysis: WorkoutAnalysisContext,
        runRecord: RunRecord
    ) -> String {
        let q = userQuestion.lowercased().replacingOccurrences(of: "’", with: "'")

        // 1. Subjective distress override (Illness, Fever)
        if (turnContext?.isSubjectiveDistress == true && !q.contains("knee") && !q.contains("pain") && !q.contains("hurt")) || q.contains("fever") || q.contains("feel sick") || q.contains("feeling sick") || q.contains("have a cold") || q.contains("flu") {
            return "When you're dealing with illness, fever, or acute physical distress, training takes a back seat. Prioritize sleep, hydration, and full rest until your symptoms fully resolve."
        }

        // 1.5. Musculoskeletal Pain, Joint Discomfort or Injury Inquiry
        let painKeywords = ["pain", "hurt", "hurts", "hurting", "knee", "shin", "achilles", "plantar", "injury", "injured", "soreness", "swollen", "painkiller"]
        if painKeywords.contains(where: { q.contains($0) }) {
            let floor = analysis.runnerProfile.heightAdjustedCadenceFloor
            let cad = analysis.workingCadence
            let pace = analysis.workingPaceFormatted
            let osc = runRecord.workingAvgVerticalOscillation

            let medicalBoundary = "I'm an AI running analyst, not a doctor or physical therapist. If you're experiencing pain, swelling, or persistent discomfort, please consult a medical doctor or physical therapist for a professional evaluation."

            let telemetryInsight: String
            let oscText = osc.map { ", with **\(String(format: "%.1f", $0)) cm** of vertical bounce" } ?? ""
            if cad < floor {
                telemetryInsight = "Looking at your telemetry from this run: your cadence was **\(cad) SPM** (below your **\(floor) SPM** height floor) at a working pace of **\(pace)**\(oscText). When cadence drops below your floor, it often indicates overstriding—reaching your foot out ahead of your center of mass. This creates braking forces that send impact shock directly into the knee joint rather than allowing your hips and calves to absorb the load."
            } else {
                telemetryInsight = "Looking at your telemetry from this run: your cadence was **\(cad) SPM** (above your **\(floor) SPM** floor) at a working pace of **\(pace)**\(oscText). While your turnover was disciplined, subtle overstriding or excessive vertical bounce can still transfer braking shock into the knee joint."
            }

            let nextSteps = "If you decide to seek medical help, that takes priority—rest and let a clinician evaluate it. If you and your provider determine you are cleared to run, I recommend **Cadence Pyramids** or **Strides** during your warm-up as your next drill to help shorten your stride, increase foot turnover under your hips, and soften landing impact."

            return "\(medicalBoundary)\n\n\(telemetryInsight)\n\n\(nextSteps)"
        }

        // 1.6. Hardware Boundary (Indoor GPS inquiry)
        let gpsKeywords = ["gps", "satellite", "route", "map", "inaccurate distance"]
        if (analysis.isIndoor || runRecord.isIndoor == true) && gpsKeywords.contains(where: { q.contains($0) }) {
            return "This run was recorded on an indoor treadmill. Apple Watch turns off GPS and satellite tracking indoors because satellite signals cannot penetrate indoor walls and ceilings. Instead, your distance and pace were calculated using wrist accelerometer arm swing and cadence. If the treadmill display differed, you can calibrate distance in the Apple Health or Fitness app."
        }

        // 1.7. Subjective Gear / Shoe Boundary
        let gearKeywords = ["shoes", "shoe", "vaporfly", "alphafly", "superblast", "hoka", "nike", "saucony", "gear to buy", "what shoes", "footwear", "carbon shoes"]
        if gearKeywords.contains(where: { q.contains($0) }) {
            return "I focus on your running biomechanics, cadence turnover, and aerobic consistency rather than specific shoe brands. The best footwear is whatever feels natural and comfortable for you, but maintaining a quick cadence turnover of **\(analysis.workingCadence) SPM** with your feet landing under your hips does far more to protect your joints and improve your speed than any shoe brand."
        }

        // 2. Out-of-scope inquiry
        if turnContext?.turnDomain == .outOfScopeInquiry {
            if q.contains("dougie") || q.contains("dance") {
                return "I'm not equipped to teach dance moves, but I can help you optimize your running performance and recovery. What would you like to explore about your running form, pacing, or workouts?"
            }
            return "I'm your personal running coach and exercise physiologist, so I specialize in your running biomechanics, training zones, and recovery. What would you like to explore regarding your runs?"
        }

        // 2.4. 30-Day Performance Arc & Best vs Worst Rankings
        let mentionsSplitsOrSegments = q.contains("split") || q.contains("segment") || q.contains("lap") || q.contains("rep")
        let isArcIntent = !mentionsSplitsOrSegments && (
            (q.contains("best") && (q.contains("worst") || q.contains("toughest") || (q.contains("performance") && !q.contains("interval")) || q.contains("run") || q.contains("workout"))) ||
            (q.contains("past 30 days") && (q.contains("best") || q.contains("worst") || q.contains("rank") || q.contains("performance"))) ||
            q.contains("performance arc")
        )
        if isArcIntent {
            let arc = HistoricalRunMatcher.analyzePerformanceArc(relativeTo: runRecord, in: runRecord.modelContext)
            return arc.coachingArcSummary
        }

        // 2.5. Historical Workout Inquiry & Comparison (e.g. "compare this run to my September 14 run", "tell me about my last outdoor run", "check recent outdoor activity")
        let isHistoricalOrComparisonIntent = q.contains("compare") || q.contains("versus") || q.contains(" vs ") || q.contains(" vs. ") ||
            q.contains("difference between") || q.contains("how does this compare") ||
            q.contains("outdoor run") || q.contains("outdoor activity") || q.contains("last outdoor") ||
            q.contains("previous run") || q.contains("prior run") || q.contains("earlier run") ||
            (q.contains("outdoor") && (q.contains("activity") || q.contains("history") || q.contains("run") || q.contains("workout")))
        if isHistoricalOrComparisonIntent {
            if let compound = HistoricalRunMatcher.parseComparisonTargets(from: userQuestion),
               let comparison = HistoricalRunMatcher.compareRuns(queryA: compound.targetA, queryB: compound.targetB, relativeTo: runRecord, in: runRecord.modelContext) {
                return comparison.coachingComparisonSummary
            } else if let prior = HistoricalRunMatcher.findRun(matching: userQuestion, relativeTo: runRecord, in: runRecord.modelContext) {
                return HistoricalRunMatcher.compare(current: runRecord, with: prior).coachingComparisonSummary
            } else {
                return "No historical workout matching '\(userQuestion)' was found in stored records."
            }
        }

        // 2.6. Workout Type & Environmental Mechanics Clarification
        if q.contains("what type of run") || q.contains("what kind of run") || q.contains("what type of workout") || q.contains("what kind of workout") {
            let env = analysis.isIndoor ? "indoor treadmill" : "outdoors"
            return "Your \(analysis.workoutWeekday) run was an **\(analysis.detectedType.lowercased()) session** \(analysis.isIndoor ? "on the " : "")\(env)."
        }
        if ((q.contains("belt") || q.contains("belt-driven")) && (q.contains("why") || q.contains("matter"))) || ((q.contains("static air") || q.contains("treadmill air")) && (q.contains("why") || q.contains("matter"))) {
            return "That distinction matters mechanically and thermodynamically: on a treadmill, the motor-driven belt moves beneath your feet, requiring active turnover under your hips to avoid braking shock. In stagnant indoor air, the lack of convective wind cooling impairs sweat evaporation, causing internal heat accumulation and cardiac drift."
        }

        // 2.7. Conversational Follow-Up / Elaboration ("That's all?", "Tell me more", "Why?", "Explain further")
        let isElaborationIntent = turnContext?.turnDomain == .elaborationOrFollowUp ||
            q.contains("that's all") || q.contains("thats all") || q.contains("is that all") ||
            q.contains("tell me more") || q.contains("elaborate") || q.contains("go deeper")
        if isElaborationIntent {
            let digest = turnContext?.cleanConversationDigest.lowercased() ?? ""
            if digest.contains("comparing") || digest.contains("versus") || digest.contains("vs") || digest.contains("september") || digest.contains("faster in current") || digest.contains("slower in current") {
                let envNote = analysis.isIndoor ? "on the treadmill" : "outdoors"
                return "Going deeper into the comparison: the primary physiological difference stems from the workout structure. Your \(analysis.detectedType) \(envNote) had active recovery periods that allowed your cardiovascular system to lower heart rate between work bouts, holding your average to **\(Int(runRecord.workingAvgHeartRate)) BPM**. In contrast, a continuous tempo run demands unbroken threshold effort without recovery valleys, creating much higher cumulative cardiac load. Mechanically, your turnover remained disciplined at **\(Int(runRecord.workingAvgCadence)) SPM**, showing smooth, steady stride rhythm."
            } else if analysis.evaluationModality == .intervals {
                return "Looking closer at your interval execution: the key to this session was managing turnover during the late work reps. While your average cadence was **\(analysis.workingCadence) SPM**, maintaining that rhythm as fatigue sets in prevents braking forces and keeps your ground contact time sharp."
            } else {
                return "Delving deeper into this run: your cardiovascular coupling and cadence of **\(analysis.workingCadence) SPM** provided consistent mechanical stability. The primary physiological takeaway is how your body maintained aerobic containment throughout the working distance."
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
                return "Your heart rate did not stay completely steady: it climbed by **+\(drift) BPM** over the second half of the run (final \(dur) minutes). \(envDetail)"
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

        // 4b. Duration / Session length challenge (e.g., "Final 45mins of the run???")
        let isDurationClarification = (q.contains("45 min") || q.contains("45min") || q.contains("whole run") || q.contains("entire run") || q.contains("final 45"))
        if isDurationClarification {
            let durTotal = max(1, Int(runRecord.duration / 60))
            let halfMin = max(1, durTotal / 2)
            return "To clarify: your entire workout was **\(durTotal) minutes**. The **+\(analysis.cardiacDriftMagnitudeBPM) BPM** cardiac drift occurred across the second half of the session (the final **\(halfMin) minutes**), driven by thermal accumulation on the indoor treadmill."
        }

        // 4c. Easy Run terminology challenge (e.g., "Why do you keep saying easy run?")
        let isEasyRunChallenge = q.contains("easy run") || q.contains("saying easy") || q.contains("what easy")
        if isEasyRunChallenge {
            if analysis.evaluationModality == .intervals || !analysis.workSegments.isEmpty {
                let meanWorkPaceSec = analysis.workSegments.isEmpty ? runRecord.workingAvgPace : analysis.workSegments.reduce(0.0) { $0 + $1.avgPace } / Double(analysis.workSegments.count)
                let workPace = PaceFormatter.formatPace(secondsPerKilometer: meanWorkPaceSec)
                let repsCount = analysis.intervalEvaluations.count
                return "You're right to call that out—this was certainly not an easy run. It was a high-intensity **\(analysis.detectedType)** with **\(repsCount) fast work reps** averaging **\(workPace)**. When I mentioned easy running, I was referring exclusively to your upcoming **\(analysis.lockedPrescription.nextSessionName)** prescribed for tomorrow to help clear metabolic fatigue."
            } else {
                return "Good catch—your pace and effort in this session reached well above recovery levels. Any easy run guidance applies to tomorrow's recovery flush (**\(analysis.lockedPrescription.nextSessionName)**) to ensure safe adaptation."
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

        // 8.5. Pacing Repeatability & Consistency Concept
        if q.contains("repeatability") || q.contains("what does repeatability") {
            let spreadNote = Int(analysis.workRepPaceSpreadSec)
            let spreadText = spreadNote <= 8 ? "disciplined and steady (held within ±\(max(1, Int(Double(spreadNote) / 2.0)))s/km of your average)" : "variable (\(spreadNote)s/km spread between fastest and slowest reps)"
            return "Pacing repeatability simply means holding an even, steady speed across all your intervals so you don't burn out early. In your session, your work pacing was \(spreadText)."
        }

        // 9. Splits, intervals, and pacing segments
        let isSegmentEvalIntent = q.contains("split") || q.contains("interval") || q.contains("segment") || q.contains("lap") || q.contains("fastest") || q.contains("slowest") || q.contains("performance") || q.contains("each rep") || q.contains("every rep") || q.contains("break down") || q.contains("breakdown")
        if isSegmentEvalIntent {
            return analysis.formatPerformanceReport()
        }

        // 10. Arm Drive & Upper Body Mechanics
        if q.contains("arm drive") || q.contains("arm swing") || q.contains("arms") {
            return "Active arm drive establishes your stride rhythm and balances pelvic rotation. Driving your elbows straight back (at roughly a 90° angle) stabilizes your torso, prevents lateral twisting, and helps maintain cadence turnover as fatigue sets in."
        }

        // 11. Workout Structuring & Training Programs (e.g. "How to structure my run tomorrow with the recommended drills and zone 1 recovery", "Can you make the program for me")
        let isStructuringIntent = ((q.contains("structure") || q.contains("combine") || q.contains("routine") || q.contains("how to do both") || q.contains("how do i do both")) &&
            (q.contains("run") || q.contains("drill") || q.contains("recovery") || q.contains("session"))) ||
            q.contains("make the program") || q.contains("make a program") || q.contains("create a program") ||
            q.contains("safe progression") || q.contains("progression plan") ||
            (q.contains("program") && (q.contains("run") || q.contains("tomorrow") || q.contains("for me") || q.contains("training")))
        if isStructuringIntent {
            let drillTitle = runRecord.insight?.drillRecommendations?.first?.drillTitle ?? "Cadence Pyramids"
            let sessionName = analysis.lockedPrescription.nextSessionName
            let paceBand = analysis.lockedPrescription.prescribedPaceBand
            return """
            Here is the ideal structure for tomorrow's session:

            1. **Warm-Up (5–10 min)**: Start with an easy, very gentle jog and dynamic mobility to loosen up your hips and calves.
            2. **Form Drill (5 min)**: Perform your **\(drillTitle)** drill early in the session while your nervous system is fresh to wake up quick foot turnover.
            3. **Recovery Flush (20–25 min)**: Settle into your **\(sessionName)** at an easy, conversational pace (**\(paceBand)**) to flush metabolic fatigue.
            4. **Cool-Down (3–5 min)**: Finish with a relaxed walking cool-down.
            """
        }

        // 11.5. Drills & Form Exercises
        if q.contains("drill") || q.contains("exercise") || q.contains("pyramid") || q.contains("stride") {
            if let drill = runRecord.insight?.drillRecommendations?.first {
                let target = drill.targetCadence.map {
                    let clean = $0.replacingOccurrences(of: " SPM", with: "").replacingOccurrences(of: "SPM", with: "").trimmingCharacters(in: .whitespaces)
                    return " Target cadence: **\(clean) SPM**."
                } ?? ""
                let purpose = drill.drillPurpose.map {
                    let clean = $0.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
                    return " Purpose: \(clean)."
                } ?? ""
                return "The most effective drill for this workout is **\(drill.drillTitle)**.\(purpose)\(target) Incorporate this during your warm-up to reinforce proper motor patterns."
            } else if analysis.workingCadence < analysis.runnerProfile.heightAdjustedCadenceFloor {
                return "I recommend **Cadence Pyramids** or **Strides** during your warm-up to train your turnover up toward your **\(analysis.runnerProfile.heightAdjustedCadenceFloor) SPM** height floor."
            } else {
                return "I recommend **Strides** (4–6 x 20-second relaxed accelerations) during your warm-up to wake up quick foot turnover and a springy stride."
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

        // 12.5. Session & Drill Sequencing ("Which order should I do both runs?", "Which one first?")
        let isSequencingIntent = q.contains("which order") || q.contains("what order") ||
            q.contains("order should i") || q.contains("in what order") ||
            q.contains("which one first") || q.contains("which should i do first") ||
            q.contains("which run first") || q.contains("both runs") ||
            q.contains("both sessions") || q.contains("both workouts") ||
            q.contains("before or after") || q.contains("same day") ||
            (q.contains("order") && (q.contains("run") || q.contains("drill") || q.contains("session") || q.contains("both")))

        if isSequencingIntent {
            let drillTitle = runRecord.insight?.drillRecommendations?.first?.drillTitle ?? "Cadence Pyramids"
            let sessionName = analysis.lockedPrescription.nextSessionName
            let paceBand = analysis.lockedPrescription.prescribedPaceBand
            return """
            Do them in this order:

            1. **First (Recovery)**: Complete your **\(sessionName)** session first (at **\(paceBand)**). This flushes metabolic waste and lowers cardiovascular fatigue without heavy impact.
            2. **Second (Form Refinement)**: Save the **\(drillTitle)** drill for your next active training session, performing it during your warm-up once your neuromuscular system is fully recovered and fresh.
            """
        }

        // 13. Future Training, Recovery & Readiness
        if q.contains("can i") || q.contains("ready") || q.contains("recovery") || q.contains("rest") || q.contains("tomorrow") || q.contains("next run") || q.contains("what pace") || q.contains("how long") || q.contains("push hard") || q.contains("how hard") || q.contains("push") {
            let recoveryNote: String
            if analysis.recoveryTimeline.readyForHard {
                recoveryNote = "Your recovery status is **\(analysis.recoveryTimeline.state.rawValue)**: fully recovered and cleared for your next workout."
            } else {
                recoveryNote = "Your recovery status is **\(analysis.recoveryTimeline.state.rawValue)**: in an active recovery window until \(analysis.recoveryTimeline.earliestHardPhrase). You are cleared for light active recovery movement tomorrow, but keep effort strictly low-intensity."
            }
            return "\(recoveryNote) Next Recommended Session: **\(analysis.lockedPrescription.nextSessionName)** (**\(analysis.lockedPrescription.prescribedDurationBand)** at **\(analysis.lockedPrescription.prescribedPaceBand)**). \(analysis.lockedPrescription.sessionRationale)"
        }

        // 14. Effort & Workout Exertion (Past session inquiry)
        if q.contains("effort") || q.contains("exertion") || q.contains("intensity") {
            let pace: String
            let hr: Int
            if analysis.evaluationModality == .intervals && !analysis.workSegments.isEmpty {
                let meanWorkPaceSec = analysis.workSegments.reduce(0.0) { $0 + $1.avgPace } / Double(analysis.workSegments.count)
                pace = PaceFormatter.formatPace(secondsPerKilometer: meanWorkPaceSec)
                hr = Int(analysis.workSegments.reduce(0.0) { $0 + $1.avgHR } / Double(analysis.workSegments.count))
            } else {
                hr = Int(runRecord.workingAvgHeartRate)
                pace = PaceFormatter.formatPace(secondsPerKilometer: runRecord.workingAvgPace)
            }
            let driftNote = analysis.cardiacDriftMagnitudeBPM >= 8
                ? "You experienced **+\(analysis.cardiacDriftMagnitudeBPM) BPM** of cardiac drift in the second half, indicating late fatigue."
                : "Your cardiovascular system maintained stable aerobic coupling throughout."
            return "Your effort during this **\(analysis.detectedType)** was sustained at an average heart rate of **\(hr) BPM** and pace of **\(pace)**. \(driftNote)"
        }

        // 15. Cadence, Turnover & Rhythm
        let isFormIntent = q.contains("running form") || q.contains("my form") || q.contains("technique") || q.contains("posture") || q.contains("biomechanic")
        if q.contains("cadence") || q.contains("rhythm") || q.contains("turnover") || q.contains("spm") || isFormIntent {
            let floor = analysis.runnerProfile.heightAdjustedCadenceFloor
            if (analysis.evaluationModality == .intervals || !analysis.workSegments.isEmpty) && !analysis.workSegments.isEmpty {
                let workCad = Int((analysis.workSegments.reduce(0.0) { $0 + $1.avgCadence } / Double(analysis.workSegments.count)).rounded())
                let overallCad = Int(runRecord.workingAvgCadence.rounded())
                let comparison = workCad >= floor ? "disciplined and above" : "slightly below"
                return "Across your fast work reps, turnover averaged **\(workCad) SPM** (\(comparison) your **\(floor) SPM** height-adjusted floor), while overall workout cadence including recovery jogs was **\(overallCad) SPM**."
            } else {
                let cad = analysis.workingCadence
                if cad < floor {
                    return "Your cadence was **\(cad) SPM**, which is below your **\(floor) SPM** height-adjusted floor. Focus on shorter, lighter steps under your hips to improve turnover."
                } else {
                    return "Your cadence was **\(cad) SPM**, maintaining a healthy turnover above your **\(floor) SPM** height-adjusted floor. Stride rhythm remained disciplined."
                }
            }
        }

        // 16. Highlights / What Went Well
        if q.contains("went well") || q.contains("highlight") || q.contains("positive") || q.contains("strengths") || q.contains("good about") {
            let strengths = analysis.overallGradeReport.strengths.joined(separator: ". ")
            return "Here is what went well: \(strengths)."
        }

        // 17. Grade and Performance Evaluation
        let isGradingExplanation = q.contains("explain") || q.contains("why") || q.contains("break down") || q.contains("details")
        if (q.contains("grade") || q.contains("score") || q.contains("how did i do") || q.contains("rate my") || q.contains("rating") || q.contains("perform") || q.contains("how was this run") || q.contains("how was my run")) && !q.contains("heart") && !q.contains("split") {
            if isGradingExplanation {
                let strengths = analysis.overallGradeReport.strengths.joined(separator: ", ")
                let focus = analysis.overallGradeReport.focus ?? "maintaining your steady rhythm"
                return "Your Grade **\(analysis.overallGradeReport.grade)** is calculated directly from your telemetry. Strengths noted: \(strengths). The main area affecting your score was that \(focus)."
            }
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
        if analysis.evaluationModality == .intervals && !analysis.intervalEvaluations.isEmpty {
            let meanWorkPaceSec = analysis.workSegments.isEmpty ? runRecord.workingAvgPace : analysis.workSegments.reduce(0.0) { $0 + $1.avgPace } / Double(analysis.workSegments.count)
            let workPace = PaceFormatter.formatPace(secondsPerKilometer: meanWorkPaceSec)
            let workCad = analysis.workSegments.isEmpty ? Int(runRecord.workingAvgCadence) : Int(analysis.workSegments.reduce(0.0) { $0 + $1.avgCadence } / Double(analysis.workSegments.count))
            let workHR = analysis.workSegments.isEmpty ? Int(runRecord.workingAvgHeartRate) : Int(analysis.workSegments.reduce(0.0) { $0 + $1.avgHR } / Double(analysis.workSegments.count))
            let repsCount = analysis.intervalEvaluations.count
            return "During your **\(repsCount)-rep \(analysis.detectedType)** on **\(analysis.workoutWeekday)**, you held an active work pace of **\(workPace)** with a heart rate of **\(workHR) BPM** and cadence of **\(workCad) SPM**. \(analysis.overallGradeReport.sentence)"
        }

        let pace = PaceFormatter.formatPace(secondsPerKilometer: runRecord.workingAvgPace)
        let cad = Int(runRecord.workingAvgCadence)
        let hr = Int(runRecord.workingAvgHeartRate)
        return "During your **\(analysis.detectedType)** on **\(analysis.workoutWeekday)**, you held an average pace of **\(pace)** with a heart rate of **\(hr) BPM** and cadence of **\(cad) SPM**. \(analysis.overallGradeReport.sentence)"
    }
}
