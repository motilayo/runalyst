import Foundation

// MARK: - Formatted Dynamic Text Presentations

extension WorkoutAnalysisContext {
    /// Builds a rich-text performance report adaptive to the workout's authentic classification.
    func formatPerformanceReport() -> String {
        if evaluationModality == .intervals && !intervalEvaluations.isEmpty {
            var lines = ["Here is the breakdown of your intervals:"]
            for rep in intervalEvaluations.prefix(24) {
                var repLine = "• Rep \(rep.repIndex) (\(rep.workPaceFormatted), \(rep.workCadence) SPM, \(rep.workHeartRate) BPM): \(rep.letterGrade) — \(rep.observation)"
                if let rPace = rep.recoveryPaceFormatted, let rDrop = rep.recoveryHeartRateDrop, rDrop > 0 {
                    let thermalNote = isIndoor && rDrop < 10 ? " (blunted by indoor thermal buildup)" : ""
                    repLine += "\n  Recovery \(rep.repIndex) (\(rPace)): HR dropped -\(rDrop) BPM into recovery zone\(thermalNote)"
                } else if let rPace = rep.recoveryPaceFormatted {
                    repLine += "\n  Recovery \(rep.repIndex) (\(rPace)): controlled active recovery jog"
                }
                lines.append(repLine)
            }

            if let fRep = fastestWorkRep, let sRep = slowestWorkRep, workSegments.count >= 2 {
                let fIdx = (workSegments.firstIndex(where: { $0.id == fRep.id }) ?? 0) + 1
                let sIdx = (workSegments.firstIndex(where: { $0.id == sRep.id }) ?? 0) + 1
                let fRepPace = PaceFormatter.formatPace(secondsPerKilometer: fRep.avgPace)
                let sRepPace = PaceFormatter.formatPace(secondsPerKilometer: sRep.avgPace)
                let fRepStart = Int(fRep.startSeconds / 60)
                let fRepEnd = Int(fRep.endSeconds / 60)
                let sRepStart = Int(sRep.startSeconds / 60)
                let sRepEnd = Int(sRep.endSeconds / 60)
                lines.append("")
                lines.append("Overall interval execution: \(overallGradeReport.grade). Fastest work rep was Rep \(fIdx) (min \(fRepStart)–\(fRepEnd)) at \(fRepPace); slowest was Rep \(sIdx) (min \(sRepStart)–\(sRepEnd)) at \(sRepPace) (pace spread: \(Int(workRepPaceSpreadSec))s/km).")
            }
            let envSummary = isIndoor
                ? "Environment: Indoor Treadmill — belt-regulated pace with zero wind resistance; static room air elevates thermal strain in recovery phases."
                : "Environment: Outdoor — self-regulated pacing across road/track conditions with natural convective cooling."
            lines.append(envSummary)
            return lines.joined(separator: "\n")
        }

        // Continuous / Distance Splits
        guard !splitEvaluations.isEmpty else {
            return overallGradeReport.sentence
        }

        let header: String = {
            switch evaluationModality {
            case .aerobicBase:
                return "Here is the breakdown of your Zone 2 aerobic splits:"
            case .progression:
                return "Here is the breakdown of your progression splits:"
            default:
                return "Here is the breakdown of your splits:"
            }
        }()

        var lines = [header]
        for s in splitEvaluations.prefix(8) {
            lines.append("• km \(s.index) (\(s.paceFormatted), \(s.cadence) SPM, \(s.heartRate) BPM): \(s.letterGrade) — \(s.observation)")
        }

        if let f = fastestSplit, let s = slowestSplit, splitEvaluations.count >= 2 {
            var fStartSec: Double = 0
            for split in splits.prefix(while: { $0.index < f.index }) {
                fStartSec += split.durationSeconds
            }
            let fMinStart = Int(fStartSec / 60)
            let fMinEnd = Int((fStartSec + f.durationSeconds) / 60)

            var sStartSec: Double = 0
            for split in splits.prefix(while: { $0.index < s.index }) {
                sStartSec += split.durationSeconds
            }
            let sMinStart = Int(sStartSec / 60)
            let sMinEnd = Int((sStartSec + s.durationSeconds) / 60)

            let fPace = PaceFormatter.formatPace(secondsPerKilometer: f.paceSecondsPerKm)
            let sPace = PaceFormatter.formatPace(secondsPerKilometer: s.paceSecondsPerKm)
            lines.append("")
            lines.append("Overall split execution: \(overallGradeReport.grade). \(pacingTrendDescription). Fastest split was km \(f.index) (min \(fMinStart)–\(fMinEnd)) at \(fPace); slowest was km \(s.index) (min \(sMinStart)–\(sMinEnd)) at \(sPace).")
        }

        return lines.joined(separator: "\n")
    }

    /// Legacy compatibility alias for formatPerformanceReport
    func formatSplitReport() -> String {
        formatPerformanceReport()
    }

    /// Formats precomputed analytical findings into a compact context block for the on-device language model.
    func groundedPromptSummary(turnContext: ManagedTurnContext? = nil) -> String {
        if let tc = turnContext, tc.stripWorkoutPayload {
            var lines = ["ATHLETE IDENTITY & CURRENT LOAD:"]
            lines.append("- Athletic Experience Level: \(runnerProfile.experienceLevel)")
            lines.append("- Active Training Goal: \(runnerProfile.trainingGoal)")
            lines.append("- Current Date (Today): \(currentWeekday), \(currentDateFormatted)")
            lines.append("")
            lines.append(tc.promptHeader)
            return lines.joined(separator: "\n")
        }

        if let tc = turnContext, tc.turnDomain == .futureSessionPlanning || tc.prunePhysiologicalVerdicts {
            var lines = ["ATHLETE IDENTITY & CURRENT LOAD:"]
            lines.append("- Athletic Experience Level: \(runnerProfile.experienceLevel)")
            lines.append("- Active Training Goal: \(runnerProfile.trainingGoal)")
            lines.append("- Current 30-Day Training Load: \(runnerProfile.loadSummary)")
            lines.append("- Runner Height: \(Int(runnerProfile.userHeightCm)) cm (Height-calibrated cadence floor: \(runnerProfile.heightAdjustedCadenceFloor) SPM)")
            lines.append("")
            lines.append("CALENDAR & TEMPORAL CONTEXT:")
            lines.append("- Current Date (Today): \(currentWeekday), \(currentDateFormatted)")
            let elapsedNote: String = {
                if isWorkoutToday { return "logged earlier today" }
                if isWorkoutYesterday { return "logged yesterday" }
                return "\(daysSinceWorkout) days ago on \(workoutWeekday), \(workoutDateFormatted)"
            }()
            lines.append("- Workout Date: \(workoutWeekday), \(workoutDateFormatted) (\(elapsedNote))")
            if isWorkoutToday {
                lines.append("- Activity Status: This workout took place today.")
            } else {
                let todayStatus = hasRunToday ? "Logged another run today." : "Did NOT run today."
                let yesterdayStatus = hasRunYesterday ? "Logged a run yesterday." : "Did NOT run yesterday."
                let restNote = daysSinceWorkout > 1 ? "\(daysSinceWorkout) days of rest since this session (fully rested and fresh)." : "1 day of rest since this session."
                lines.append("- Recent Activity: \(todayStatus) \(yesterdayStatus) (\(restNote))")
            }
            let durationMin = max(1, Int((runRecord.duration / 60.0).rounded()))
            let distKm = String(format: "%.1f km", runRecord.totalDistanceMeters / 1000.0)
            lines.append("")
            lines.append("RECENT SESSION CONTEXT (Brief reference for last logged session):")
            lines.append("- Last Session (\(workoutWeekday)): \(detectedType) (\(isIndoor ? "Treadmill" : "Outdoors")), \(distKm) in \(durationMin) min, Working Pace: \(workingPaceFormatted), Working HR: \(workingHR) BPM")
            lines.append("")
            lines.append("FUTURE TRAINING & READINESS:")
            lines.append("- Current Readiness: \(recoveryTimeline.state.rawValue)")
            if recoveryTimeline.readyForHard {
                lines.append("- Recovery Status: FULLY RECOVERED and fresh. Cleared for any workout including speed, tempo, or intervals (last hard session was \(Int(hoursSinceWorkout))h ago; required was only \(Int(recoveryTimeline.requiredHours))h). Zero residual fatigue remains.")
            } else if let cap = recoveryTimeline.easyCap {
                lines.append("- Recovery Status: In active recovery window until \(recoveryTimeline.earliestHardPhrase). Keep next run easy (cap: \(cap.lowerBound)–\(cap.upperBound) min).")
            }
            lines.append("")
            lines.append(lockedPrescription.promptDescription)
            if let drill = runRecord.insight?.drillRecommendations?.first ?? runRecord.insight?.drillRecommendation {
                lines.append("- Pre-Run Technique Drill Option: \(drill.drillTitle) (warm-up turnover prep, not mandatory rehab)")
            }
            lines.append("")
            lines.append(tc.promptHeader)
            return lines.joined(separator: "\n")
        }

        var lines: [String] = []

        // Athlete Identity & Current Load
        lines.append("ATHLETE IDENTITY & CURRENT LOAD:")
        lines.append("- Athletic Experience Level: \(runnerProfile.experienceLevel)")
        lines.append("- Active Training Goal: \(runnerProfile.trainingGoal)")
        lines.append("- Current 30-Day Training Load: \(runnerProfile.loadSummary)")
        lines.append("- Runner Height: \(Int(runnerProfile.userHeightCm)) cm (Height-calibrated cadence floor: \(runnerProfile.heightAdjustedCadenceFloor) SPM)")
        lines.append("")

        // Calendar & Temporal Grounding
        lines.append("CALENDAR & TEMPORAL CONTEXT:")
        lines.append("- Current Date (Today): \(currentWeekday), \(currentDateFormatted)")
        let elapsedNote: String = {
            if isWorkoutToday { return "logged earlier today" }
            if isWorkoutYesterday { return "logged yesterday" }
            return "\(daysSinceWorkout) days ago on \(workoutWeekday), \(workoutDateFormatted)"
        }()
        lines.append("- Workout Date: \(workoutWeekday), \(workoutDateFormatted) (\(elapsedNote))")
        if isWorkoutToday {
            lines.append("- Activity Status: This workout took place today.")
        } else {
            let todayStatus = hasRunToday ? "Logged another run today." : "Did NOT run today."
            let yesterdayStatus = hasRunYesterday ? "Logged a run yesterday." : "Did NOT run yesterday."
            let restNote = daysSinceWorkout > 1 ? "\(daysSinceWorkout) days of rest since this session (fully rested and fresh)." : "1 day of rest since this session."
            lines.append("- Recent Activity: \(todayStatus) \(yesterdayStatus) (\(restNote))")
        }

        let durationMin = max(1, Int((runRecord.duration / 60.0).rounded()))
        let distKm = String(format: "%.1f km", runRecord.totalDistanceMeters / 1000.0)

        lines.append("")
        lines.append("WORKOUT PROFILE (\(workoutWeekday), \(workoutDateFormatted)):")
        lines.append("- Type: \(detectedType) (\(isIndoor ? "Treadmill" : "Outdoors"))")
        lines.append("- Volume: \(distKm) in \(durationMin) min (Working Pace: \(workingPaceFormatted))")
        let floorStr = runnerProfile.heightAdjustedCadenceFloor == 150 ? "150 floor" : "\(runnerProfile.heightAdjustedCadenceFloor) floor (height-adjusted)"
        lines.append("- Biomechanics: Cadence \(workingCadence) SPM (\(isSubFloorCadence ? "BELOW \(floorStr)" : "healthy turnover above floor"))")
        if let osc = verticalOscillationCM {
            lines.append("- Vertical Oscillation: \(String(format: "%.1f", osc)) cm")
        }
        if let str = strideLengthM {
            lines.append("- Stride Length: \(String(format: "%.2f", str)) m")
        }
        if let vr = verticalRatio {
            lines.append("- Vertical Ratio: \(String(format: "%.1f", vr))% (vertical bounce relative to stride length; ideal: 6–8%)")
        }
        lines.append("- Stride Archetype: \(strideArchetype)")
        if let ef = efficiencyFactor {
            var efDeltaText = ""
            if let delta = efficiencyFactorDeltaPercent {
                let sign = delta >= 0 ? "+" : ""
                efDeltaText = String(format: " (%@%.1f%% vs 30-day baseline)", sign, delta)
            }
            lines.append("- Aerobic Efficiency Factor: \(String(format: "%.2f", ef)) m/heartbeat\(efDeltaText)")
        }
        if let env = environmentModifier {
            lines.append("- Terrain & Environment Modifier: \(env)")
        }
        lines.append("- Cardiovascular Strain: Working HR \(workingHR) BPM; \(percentZone4)% in Zone 4 (Threshold)")

        // Physiological Deterministic Causal Verdicts
        lines.append("")
        lines.append("PHYSIOLOGICAL & BIOMECHANICAL VERDICTS (ROOT-CAUSE DIAGNOSIS):")
        lines.append(physiologicalVerdicts.promptDescription)

        // Pacing & Performance Findings
        if evaluationModality == .intervals && !intervalEvaluations.isEmpty {
            lines.append("")
            lines.append("INTERVAL EXECUTION (\(intervalEvaluations.count) work reps):")
            lines.append("- Environment: \(isIndoor ? "Indoor Treadmill (belt-driven, static room air, zero convective wind cooling)" : "Outdoor (self-regulated pace, road friction, natural convective cooling)")")
            if let f = fastestWorkRep, let s = slowestWorkRep {
                lines.append("- Rep Pace Range: \(PaceFormatter.formatPace(secondsPerKilometer: f.avgPace)) to \(PaceFormatter.formatPace(secondsPerKilometer: s.avgPace)) (spread: \(Int(workRepPaceSpreadSec))s/km)")
            }
            if workRepPaceSpreadSec <= 8.0 {
                lines.append("- Pacing Consistency: Disciplined, tightly controlled interval pacing")
            } else {
                lines.append("- Pacing Consistency: Wide pace spread (\(Int(workRepPaceSpreadSec))s/km difference between fastest and slowest reps; indicates late-rep fatigue)")
            }
            lines.append("Interval Rep Details (Evaluate by these reps, NOT arbitrary distance splits):")
            for rep in intervalEvaluations.prefix(24) {
                var detail = "  • Rep \(rep.repIndex) (\(rep.workPaceFormatted), \(rep.workCadence) SPM, \(rep.workHeartRate) BPM): Grade \(rep.letterGrade) — \(rep.observation)"
                if let rPace = rep.recoveryPaceFormatted, let rDrop = rep.recoveryHeartRateDrop, rDrop > 0 {
                    detail += " [Recovery: \(rPace), -\(rDrop) BPM HR drop]"
                }
                lines.append(detail)
            }
        } else if !splitEvaluations.isEmpty {
            let sectionTitle: String = {
                switch evaluationModality {
                case .aerobicBase:
                    return "ZONE 2 AEROBIC SPLIT FINDINGS (\(splitEvaluations.count) splits):"
                case .progression:
                    return "PROGRESSION SPLIT FINDINGS (\(splitEvaluations.count) splits):"
                default:
                    return "PACING & SPLIT FINDINGS (\(splitEvaluations.count) splits):"
                }
            }()
            lines.append("")
            lines.append(sectionTitle)
            lines.append("- Trend: \(pacingTrendDescription)")
            if let f = fastestSplit {
                lines.append("- Fastest Split: km \(f.index) at \(PaceFormatter.formatPace(secondsPerKilometer: f.paceSecondsPerKm)) (\(Int(f.avgCadence)) SPM, \(Int(f.avgHeartRate)) BPM)")
            }
            if let s = slowestSplit {
                lines.append("- Slowest Split: km \(s.index) at \(PaceFormatter.formatPace(secondsPerKilometer: s.paceSecondsPerKm)) (\(Int(s.avgCadence)) SPM, \(Int(s.avgHeartRate)) BPM)")
            }
            if hasCardiacDrift {
                lines.append("- Heart Rate Drift: Cardiac drift detected (+\(cardiacDriftMagnitudeBPM) BPM HR rise in second half despite steady/fading pace; indicates fatigue or thermal drift, not acceleration)")
            }
            lines.append("Split Details:")
            for s in splitEvaluations.prefix(8) {
                lines.append("  • km \(s.index): \(s.paceFormatted), \(s.cadence) SPM, \(s.heartRate) BPM — \(s.observation)")
            }
        }

        // Baseline Context
        if let diag = longitudinalDiagnosis {
            lines.append("")
            lines.append("30-DAY BASELINE CONTRAST:")
            lines.append("- \(diag)")
        }

        // Future Training & Recovery (Included only when runner asks about upcoming runs or readiness)
        let isFutureTurn = turnContext?.turnDomain == .futureSessionPlanning || turnContext?.turnDomain == .compositeWorkoutAndPlanning
        if isFutureTurn || turnContext == nil {
            lines.append("")
            lines.append("[FUTURE TRAINING & READINESS]:")
            lines.append("- Current Readiness: \(recoveryTimeline.state.rawValue)")
            if recoveryTimeline.readyForHard {
                lines.append("- Recovery Status: FULLY RECOVERED and fresh. Cleared for any workout including speed, tempo, or intervals (last hard session was \(Int(hoursSinceWorkout))h ago; required was only \(Int(recoveryTimeline.requiredHours))h). Zero residual fatigue remains.")
            } else if let cap = recoveryTimeline.easyCap {
                lines.append("- Recovery Status: In active recovery window until \(recoveryTimeline.earliestHardPhrase). Keep next run easy (cap: \(cap.lowerBound)–\(cap.upperBound) min).")
            }
            lines.append("")
            lines.append(lockedPrescription.promptDescription)

            if let drill = runRecord.insight?.drillRecommendations?.first ?? runRecord.insight?.drillRecommendation {
                lines.append("- Pre-Run Technique Drill Option: \(drill.drillTitle) (warm-up turnover prep, not mandatory rehab)")
            }
        }

        if let tc = turnContext {
            lines.append("")
            lines.append(tc.promptHeader)
        }

        return lines.joined(separator: "\n")
    }

    /// Builds a focused mathematical report of interval execution for native tool calling
    /// partitioned into strongly-typed namespaces with explicit metadata descriptions.
    func formatIntervalPerformanceSummary() -> String {
        guard evaluationModality == .intervals && !intervalEvaluations.isEmpty else {
            let fallback: [String: Any] = [
                "schema_name": "INTERVAL_PERFORMANCE_TELEMETRY",
                "status": "NOT_AN_INTERVAL_WORKOUT",
                "detected_type": detectedType,
                "message": "This workout was classified as continuous \(detectedType), not discrete interval reps. There are no active work reps or recovery phases in this session. For continuous pacing and splits, consult fetchWorkoutAnalysis."
            ]
            if let data = try? JSONSerialization.data(withJSONObject: fallback, options: [.prettyPrinted, .sortedKeys]),
               let str = String(data: data, encoding: .utf8) {
                return str
            }
            return fallback.description
        }

        let distKm = String(format: "%.1f km", runRecord.totalDistanceMeters / 1000.0)
        let durMin = max(1, Int((runRecord.duration / 60.0).rounded()))
        let floor = runnerProfile.heightAdjustedCadenceFloor

        var root: [String: Any] = [:]
        root["schema_name"] = "INTERVAL_PERFORMANCE_TELEMETRY"
        root["overview"] = [
            "work_reps_detected": intervalEvaluations.count,
            "work_reps_detected_summary": "\(intervalEvaluations.count) Work Reps Detected",
            "environment": isIndoor ? "Indoor Treadmill (belt-driven, static room air)" : "Outdoor (self-propelled road/track)"
        ]

        // Category 1: Overall Session Totals
        var sessionTotals: [String: Any] = [:]
        sessionTotals["_description"] = "Contains the blended averages for the entire run (including warm-up, active intervals, recovery jogs, and cooldown). Do not use these metrics to evaluate the runner's active exertion or form."
        sessionTotals["total_distance"] = distKm
        sessionTotals["total_duration"] = "\(durMin) min"
        sessionTotals["blended_session_avg_pace"] = workingPaceFormatted
        sessionTotals["blended_session_avg_cadence"] = "\(workingCadence) SPM"
        sessionTotals["blended_session_avg_heart_rate"] = "\(workingHR) BPM"
        root["category_1_session_totals"] = sessionTotals

        // Category 2: Active Work Performance
        var workPerf: [String: Any] = [:]
        workPerf["_description"] = "Exclusively contains data from the high-intensity intervals. By nesting active work pace and turnover inside this Work bucket, these metrics represent the primary effort."
        workPerf["work_reps_count"] = intervalEvaluations.count
        let avgCad = workSegments.isEmpty ? 0 : Int(workSegments.reduce(0.0) { $0 + $1.avgCadence } / Double(workSegments.count))
        let avgHR = workSegments.isEmpty ? 0 : Int(workSegments.reduce(0.0) { $0 + $1.avgHR } / Double(workSegments.count))
        let meanPaceSec = workSegments.isEmpty ? 0 : workSegments.reduce(0.0) { $0 + $1.avgPace } / Double(workSegments.count)
        workPerf["work_avg_pace"] = PaceFormatter.formatPace(secondsPerKilometer: meanPaceSec)
        if let f = fastestWorkRep, let s = slowestWorkRep {
            workPerf["work_pace_range"] = "\(PaceFormatter.formatPace(secondsPerKilometer: f.avgPace)) to \(PaceFormatter.formatPace(secondsPerKilometer: s.avgPace)) (spread: \(Int(workRepPaceSpreadSec))s/km)"
        }
        let pacingConsistencySummary = workRepPaceSpreadSec <= 8.0 ? "Disciplined (tight ±\(Int(workRepPaceSpreadSec / 2.0))s/km spread)" : "Variable (\(Int(workRepPaceSpreadSec))s/km spread; late rep fatigue)"
        workPerf["work_pacing_consistency"] = pacingConsistencySummary
        workPerf["work_repeatability"] = pacingConsistencySummary
        workPerf["work_avg_cadence"] = "\(avgCad) SPM"
        workPerf["work_turnover_adherence"] = "Work average \(avgCad) SPM vs \(floor) SPM height floor (\(avgCad >= floor ? "above floor" : "sub-floor"))"
        workPerf["work_avg_heart_rate"] = "\(avgHR) BPM"
        root["category_2_active_work_performance"] = workPerf

        // Category 3: Recovery Performance
        var recPerf: [String: Any] = [:]
        recPerf["_description"] = "Exclusively contains the resting and recovery jog phases between work reps. Slower paces and heart rate drops live here. By isolating them under Recovery, do not narrate them as the workload."
        recPerf["recovery_modality"] = "Active recovery jog between work sets to clear lactate"
        let recWithPace = recoverySegments.filter { $0.avgPace > 0 }
        if !recWithPace.isEmpty {
            let avgRecPaceSec = recWithPace.reduce(0.0) { $0 + $1.avgPace } / Double(recWithPace.count)
            recPerf["recovery_avg_pace"] = PaceFormatter.formatPace(secondsPerKilometer: avgRecPaceSec)
        }
        let validDrops = intervalEvaluations.compactMap(\.recoveryHeartRateDrop)
        if !validDrops.isEmpty {
            let avgDrop = Int((Double(validDrops.reduce(0, +)) / Double(validDrops.count)).rounded())
            recPerf["recovery_avg_heart_rate_drop"] = "Average drop of -\(avgDrop) BPM between sets"
        }
        if isIndoor {
            recPerf["thermal_strain_impact"] = "Indoor treadmill static room air blunted convective cooling and elevated thermal cardiac strain during recovery phases"
        }
        root["category_3_recovery_performance"] = recPerf

        // Category 4: Rep-by-Rep Breakdown
        var repsList: [[String: Any]] = []
        for rep in intervalEvaluations.prefix(24) {
            var repDict: [String: Any] = [:]
            repDict["rep_index"] = rep.repIndex
            repDict["work_phase"] = [
                "pace": rep.workPaceFormatted,
                "cadence": "\(rep.workCadence) SPM",
                "heart_rate": "\(rep.workHeartRate) BPM",
                "letter_grade": rep.letterGrade,
                "observation": rep.observation
            ]
            var recDict: [String: Any] = [:]
            if let rPace = rep.recoveryPaceFormatted {
                recDict["pace"] = rPace
            }
            if let rDrop = rep.recoveryHeartRateDrop, rDrop > 0 {
                recDict["heart_rate_drop"] = "-\(rDrop) BPM into recovery zone"
            }
            repDict["recovery_phase"] = recDict.isEmpty ? ["status": "controlled active recovery"] : recDict
            repsList.append(repDict)
        }
        var repBreakdown: [String: Any] = [:]
        repBreakdown["_description"] = "Instead of a flat chronological timeline of splits, every individual interval rep internally separates its own Work phase metrics from its Recovery phase metrics."
        repBreakdown["sets"] = repsList
        root["category_4_rep_by_rep_breakdown"] = repBreakdown

        if let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return root.description
    }

    /// Builds a focused physical reality report (friction, thermodynamics, gravity, cardiac lag) for native tool calling.
    func formatWorkoutPhysicsSummary(domain: String? = nil) -> String {
        var lines = ["WORKOUT PHYSICS & PHYSIOLOGY:"]

        // 1. Kinematics & Kinetic Friction
        lines.append("1. Kinematics & Kinetic Friction:")
        if isIndoor {
            lines.append("- Surface: Moving treadmill belt. Zero forward road displacement; belt is motor-driven beneath feet.")
            if isSubFloorCadence {
                lines.append("- Braking Shock: Turnover dipped below \(runnerProfile.heightAdjustedCadenceFloor) SPM floor. Low cadence on a moving belt increases foot contact ahead of center-of-mass, creating severe kinetic braking shock.")
            } else {
                lines.append("- Turnover Stability: Turnover maintained above \(runnerProfile.heightAdjustedCadenceFloor) SPM floor, minimizing braking impulse on the belt.")
            }
            lines.append("- Air Drag: Zero relative wind resistance.")
        } else {
            lines.append("- Surface: Ground-truth road/track pavement. Authentic friction and self-propulsion required.")
            lines.append("- Wind Drag: Authentic convective aerodynamic resistance.")
        }

        // 2. Thermodynamics & Thermal Accumulation
        lines.append("")
        lines.append("2. Thermodynamics & Cooling:")
        if isIndoor {
            lines.append("- Heat Dissipation: Static room air with 0 km/h relative airflow impairs sweat evaporation. Thermal accumulation elevates core temperature and causes cardiac drift even on flat grades.")
        } else {
            let tempStr = runRecord.ambientTemperatureCelsius.map { String(format: "%.1f°C", $0) } ?? "ambient"
            let humStr = runRecord.ambientHumidity.map { "\($0 <= 1.0 ? Int($0 * 100) : Int($0))%" } ?? "ambient"
            lines.append("- Heat Dissipation: Natural convective wind cooling assists sweat evaporation (\(tempStr), \(humStr) humidity).")
            if (runRecord.ambientTemperatureCelsius ?? 0) >= 22.0 {
                lines.append("- High Ambient Heat: Elevated temperature blunts evaporative cooling, triggering heart rate drift.")
            }
        }

        // 3. Gravitational Resistance
        lines.append("")
        lines.append("3. Gravitational Resistance:")
        if isIndoor {
            lines.append("- Deck Grade: Flat 0% grade has ZERO added gravitational resistance (1g normal force). Never misattribute indoor strain to gravity.")
        } else {
            if elevationGainMeters >= 30.0 {
                lines.append("- Hill Climbing: +\(Int(elevationGainMeters))m elevation climbed requires mechanical work against gravity. Cardiac surge on hills is gravitational load, not aerobic fitness decline.")
            } else {
                lines.append("- Terrain: Flat topography (+\(Int(elevationGainMeters))m gain); standard 1g gravitational load.")
            }
        }

        // 4. Cardiac Lag & Heart Rate Drift
        lines.append("")
        lines.append("4. Cardiac Lag & Heart Rate Drift:")
        lines.append("- Physiological Delay: Heart rate naturally lags pace changes by 15–30 seconds due to autonomic circulatory kinetics.")
        if hasCardiacDrift {
            lines.append("- Drift: Cardiac drift detected (+\(cardiacDriftMagnitudeBPM) BPM in second half despite flat/fading pace). Cause: thermal strain or glycogen depletion, not speeding up.")
        } else {
            lines.append("- Stability: Heart rate stayed stable and in lockstep with pace.")
        }

        return lines.joined(separator: "\n")
    }

    /// Builds the definitive, strongly-typed unified workout tool response.
    /// For interval workouts, places `interval_scorecard` and full `reps` array at the top level
    /// while strictly demoting blended session aggregates to `background_session_totals`.
    func buildUnifiedWorkoutToolResponse() -> UnifiedWorkoutToolResponse {
        let distKm = String(format: "%.1f km", runRecord.totalDistanceMeters / 1000.0)
        let durMin = max(1, Int((runRecord.duration / 60.0).rounded()))
        let floor = runnerProfile.heightAdjustedCadenceFloor
        let envString = isIndoor
            ? "Indoor Treadmill (belt-driven, static room air)"
            : "Outdoors (road/track)"

        let blendedTotals = BlendedTotals(
            _description: "Contains blended averages for the entire session (warm-up, work bouts, recovery jogs, and cooldown combined). SECONDARY: Do NOT cite these as the interval workload or active pace.",
            total_distance: distKm,
            total_duration: "\(durMin) min",
            blended_session_avg_pace: workingPaceFormatted,
            blended_session_avg_cadence_spm: workingCadence,
            blended_session_avg_heart_rate_bpm: workingHR,
            height_cadence_floor_spm: floor,
            aerobic_efficiency_factor: efficiencyFactor.map { String(format: "%.2f m/beat", $0) },
            cardiac_drift: hasCardiacDrift ? "+\(cardiacDriftMagnitudeBPM) BPM rise in second half" : nil,
            stride_archetype: strideArchetype
        )

        let isIntervals = evaluationModality == .intervals && !intervalEvaluations.isEmpty

        let intervalScorecard: IntervalScorecard?
        let repsList: [IntervalRepDetail]?
        let steadyScorecard: SteadyStateScorecard?
        let splitsList: [SplitDetail]?

        if isIntervals {
            let avgWorkCad = workSegments.isEmpty ? workingCadence : Int(workSegments.reduce(0.0) { $0 + $1.avgCadence } / Double(workSegments.count))
            let avgWorkHR = workSegments.isEmpty ? workingHR : Int(workSegments.reduce(0.0) { $0 + $1.avgHR } / Double(workSegments.count))
            let meanWorkPaceSec = workSegments.isEmpty ? runRecord.workingAvgPace : workSegments.reduce(0.0) { $0 + $1.avgPace } / Double(workSegments.count)
            let activeWorkPace = PaceFormatter.formatPace(secondsPerKilometer: meanWorkPaceSec)

            let validDrops = intervalEvaluations.compactMap(\.recoveryHeartRateDrop)
            let avgDrop = validDrops.isEmpty ? 0 : Int((Double(validDrops.reduce(0, +)) / Double(validDrops.count)).rounded())
            let signedAvgDrop = -abs(avgDrop)

            let consistency = workRepPaceSpreadSec <= 8.0
                ? "Disciplined (tight ±\(max(1, Int(workRepPaceSpreadSec / 2.0)))s/km spread)"
                : "Variable (\(Int(workRepPaceSpreadSec))s/km spread; late rep fatigue)"

            intervalScorecard = IntervalScorecard(
                active_work_pace: activeWorkPace,
                active_turnover_spm: avgWorkCad,
                average_hr_drop: signedAvgDrop,
                total_work_reps: intervalEvaluations.count,
                session_grade: overallGradeReport.grade,
                pacing_consistency: consistency,
                active_avg_heart_rate_bpm: avgWorkHR,
                cadence_floor_status: "\(avgWorkCad) SPM vs \(floor) SPM floor (\(avgWorkCad >= floor ? "above floor" : "sub-floor"))"
            )

            repsList = intervalEvaluations.prefix(24).map { rep in
                let recPace = rep.recoveryPaceFormatted ?? "controlled recovery jog"
                let recDrop = rep.recoveryHeartRateDrop.map { -$0 } ?? 0
                return IntervalRepDetail(
                    rep_number: rep.repIndex,
                    work_pace: rep.workPaceFormatted,
                    work_cadence_spm: rep.workCadence,
                    rep_grade: rep.letterGrade,
                    recovery_pace: recPace,
                    recovery_hr_drop_bpm: recDrop,
                    work_heart_rate_bpm: rep.workHeartRate,
                    observation: rep.observation
                )
            }

            steadyScorecard = nil
            splitsList = nil
        } else {
            intervalScorecard = nil
            repsList = nil

            let fSplitDesc = fastestSplit.map { "km \($0.index) at \(PaceFormatter.formatPace(secondsPerKilometer: $0.paceSecondsPerKm)) (\(Int($0.avgCadence)) SPM, \(Int($0.avgHeartRate)) BPM)" }
            let sSplitDesc = slowestSplit.map { "km \($0.index) at \(PaceFormatter.formatPace(secondsPerKilometer: $0.paceSecondsPerKm)) (\(Int($0.avgCadence)) SPM, \(Int($0.avgHeartRate)) BPM)" }

            steadyScorecard = SteadyStateScorecard(
                avg_pace: workingPaceFormatted,
                avg_turnover_spm: workingCadence,
                avg_heart_rate_bpm: workingHR,
                session_grade: overallGradeReport.grade,
                pacing_trend: pacingTrendDescription,
                cadence_floor_status: "\(workingCadence) SPM vs \(floor) SPM floor (\(workingCadence >= floor ? "above floor" : "sub-floor"))",
                fastest_split: fSplitDesc,
                slowest_split: sSplitDesc
            )

            splitsList = splitEvaluations.prefix(24).map { split in
                SplitDetail(
                    split_index: split.index,
                    pace: split.paceFormatted,
                    cadence_spm: split.cadence,
                    heart_rate_bpm: split.heartRate,
                    grade: split.letterGrade,
                    observation: split.observation
                )
            }
        }

        let hrConfidence: String = runRecord.isHeartRateSensorLowConfidence
            ? "unreliable_sensor_artifact (resting/cadence-lock HR < 85 BPM detected; do NOT evaluate or praise cardiovascular effort from this number)"
            : "reliable"

        return UnifiedWorkoutToolResponse(
            schema_name: "UNIFIED_WORKOUT_TOOL_RESPONSE",
            workout_type: detectedType,
            date: "\(workoutWeekday), \(workoutDateFormatted)",
            environment: envString,
            interval_scorecard: intervalScorecard,
            reps: repsList,
            steady_state_scorecard: steadyScorecard,
            splits: splitsList,
            background_session_totals: blendedTotals,
            physiological_verdicts: physiologicalVerdicts.promptDescription,
            heart_rate_confidence: hrConfidence
        )
    }

    /// Serializes the unified workout response into clean, pretty-printed JSON.
    func unifiedWorkoutAnalysisJSON() -> String {
        let response = buildUnifiedWorkoutToolResponse()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(response),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{\n  \"workout_type\": \"\(detectedType)\",\n  \"date\": \"\(workoutWeekday), \(workoutDateFormatted)\"\n}"
    }

    /// Builds a compact, token-efficient telemetry summary for on-device FoundationModels tool calling.
    /// Returns the unified workout analysis schema with interval scorecards and full rep arrays.
    func compactTelemetryAnalysis(focus: String? = nil) -> String {
        unifiedWorkoutAnalysisJSON()
    }
}
