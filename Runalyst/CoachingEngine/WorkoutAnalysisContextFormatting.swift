import Foundation

// MARK: - Native Tool Payloads

extension WorkoutAnalysisContext {
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

        let isLowConfidenceHR = runRecord.isHeartRateSensorLowConfidence
        let hrConfidence: SensorConfidence = isLowConfidenceHR ? .unreliableArtifact : .reliable
        let hrStatus: HeartRateStatus = isLowConfidenceHR ? .sensorLockAnomaly : .reliable
        let hrStatusStr: String? = isLowConfidenceHR ? "sensor_lock_anomaly" : nil

        let blendedTotals = BlendedTotals(
            _description: nil,
            total_distance: distKm,
            total_duration: "\(durMin) min",
            blended_session_avg_pace: workingPaceFormatted,
            blended_session_avg_cadence_spm: workingCadence,
            blended_session_avg_heart_rate_bpm: isLowConfidenceHR ? nil : workingHR,
            heart_rate_status: hrStatusStr,
            height_cadence_floor_spm: floor,
            aerobic_efficiency_factor: efficiencyFactor.map { String(format: "%.2f m/beat", $0) },
            cardiac_drift: hasCardiacDrift ? "+\(cardiacDriftMagnitudeBPM) BPM" : nil,
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
                average_hr_drop: isLowConfidenceHR ? 0 : signedAvgDrop,
                total_work_reps: intervalEvaluations.count,
                session_grade: overallGradeReport.grade,
                pacing_consistency: consistency,
                active_avg_heart_rate_bpm: isLowConfidenceHR ? nil : avgWorkHR,
                heart_rate_status: hrStatusStr,
                cadence_floor_status: "\(avgWorkCad) SPM vs \(floor) SPM floor (\(avgWorkCad >= floor ? "above floor" : "sub-floor"))"
            )

            repsList = intervalEvaluations.prefix(12).map { rep in
                let recPace = rep.recoveryPaceFormatted ?? "controlled recovery jog"
                let recDrop = rep.recoveryHeartRateDrop.map { -$0 } ?? 0
                var flags: [String] = []
                if rep.workCadence < floor {
                    flags.append("cadence_below_floor")
                }
                if let drop = rep.recoveryHeartRateDrop, drop < 10 {
                    flags.append("blunted_hr_recovery")
                }
                return IntervalRepDetail(
                    rep_number: rep.repIndex,
                    work_pace: rep.workPaceFormatted,
                    work_cadence_spm: rep.workCadence,
                    rep_grade: rep.letterGrade,
                    recovery_pace: recPace,
                    recovery_hr_drop_bpm: isLowConfidenceHR ? nil : recDrop,
                    work_heart_rate_bpm: isLowConfidenceHR ? nil : rep.workHeartRate,
                    heart_rate_status: hrStatusStr,
                    flags: flags,
                    observation: rep.observation.isEmpty ? nil : rep.observation
                )
            }

            steadyScorecard = nil
            splitsList = nil
        } else {
            intervalScorecard = nil
            repsList = nil

            let fSplitDesc = fastestSplit.map { split in
                let cad = "\(Int(split.avgCadence)) SPM"
                if isLowConfidenceHR {
                    return "km \(split.index) at \(PaceFormatter.formatPace(secondsPerKilometer: split.paceSecondsPerKm)) (\(cad))"
                } else {
                    return "km \(split.index) at \(PaceFormatter.formatPace(secondsPerKilometer: split.paceSecondsPerKm)) (\(cad), \(Int(split.avgHeartRate)) BPM)"
                }
            }
            let sSplitDesc = slowestSplit.map { split in
                let cad = "\(Int(split.avgCadence)) SPM"
                if isLowConfidenceHR {
                    return "km \(split.index) at \(PaceFormatter.formatPace(secondsPerKilometer: split.paceSecondsPerKm)) (\(cad))"
                } else {
                    return "km \(split.index) at \(PaceFormatter.formatPace(secondsPerKilometer: split.paceSecondsPerKm)) (\(cad), \(Int(split.avgHeartRate)) BPM)"
                }
            }

            steadyScorecard = SteadyStateScorecard(
                avg_pace: workingPaceFormatted,
                avg_turnover_spm: workingCadence,
                avg_heart_rate_bpm: isLowConfidenceHR ? nil : workingHR,
                heart_rate_status: hrStatusStr,
                session_grade: overallGradeReport.grade,
                pacing_trend: pacingTrendDescription,
                cadence_floor_status: "\(workingCadence) SPM vs \(floor) SPM floor (\(workingCadence >= floor ? "above floor" : "sub-floor"))",
                fastest_split: fSplitDesc,
                slowest_split: sSplitDesc
            )

            splitsList = splitEvaluations.prefix(12).map { split in
                var flags: [String] = []
                if split.cadence < floor {
                    flags.append("cadence_below_floor")
                }
                if let f = fastestSplit, f.index == split.index {
                    flags.append("fastest_split")
                }
                if let s = slowestSplit, s.index == split.index {
                    flags.append("slowest_split")
                }
                return SplitDetail(
                    split_index: split.index,
                    pace: split.paceFormatted,
                    cadence_spm: split.cadence,
                    heart_rate_bpm: isLowConfidenceHR ? nil : split.heartRate,
                    heart_rate_status: hrStatusStr,
                    grade: split.letterGrade,
                    flags: flags,
                    observation: split.observation.isEmpty ? nil : split.observation
                )
            }
        }

        let movingSec = runRecord.effectiveWorkingDurationSeconds
        let movingMin = max(1, Int((movingSec / 60.0).rounded()))
        let movingTimeStr = String(format: "%d:%02d", max(0, Int(movingSec) / 60), max(0, Int(movingSec) % 60))
        let workingStats = WorkingStatsDetail(
            moving_time: movingTimeStr,
            moving_pace: workingPaceFormatted,
            working_cadence_spm: workingCadence,
            working_heart_rate_bpm: isLowConfidenceHR ? nil : workingHR,
            _description: nil
        )

        let totalSec = runRecord.duration
        let totalTimeStr = String(format: "%d:%02d", max(0, Int(totalSec) / 60), max(0, Int(totalSec) % 60))
        let grossPaceSec = runRecord.totalDistanceMeters > 0
            ? (runRecord.duration / (runRecord.totalDistanceMeters / 1000.0))
            : runRecord.rawAvgPace
        let grossPaceStr = PaceFormatter.formatPace(secondsPerKilometer: grossPaceSec)
        let workoutStats = WorkoutStatsDetail(
            total_time: totalTimeStr,
            gross_pace: grossPaceStr,
            raw_cadence_spm: Int(runRecord.rawAvgCadence.rounded()),
            raw_heart_rate_bpm: isLowConfidenceHR ? nil : Int(runRecord.rawAvgHeartRate.rounded()),
            _description: nil
        )

        let durationClass: DurationClass
        if movingMin <= 20 {
            durationClass = .primer
        } else if movingMin <= 35 {
            durationClass = .short
        } else if movingMin <= 60 {
            durationClass = .standard
        } else {
            durationClass = .long
        }
        let durationDetail = DurationDetail(
            duration_class: durationClass,
            moving_minutes: movingMin,
            total_minutes: durMin
        )

        return UnifiedWorkoutToolResponse(
            schema_name: "UNIFIED_WORKOUT_TOOL_RESPONSE",
            workout_type: detectedType,
            date: "\(workoutWeekday), \(workoutDateFormatted)",
            environment: envString,
            interval_scorecard: intervalScorecard,
            reps: repsList,
            steady_state_scorecard: steadyScorecard,
            splits: splitsList,
            working_stats: workingStats,
            workout_stats: workoutStats,
            background_session_totals: blendedTotals,
            findings: physiologicalVerdicts.findings,
            heart_rate_confidence: hrConfidence,
            heart_rate_status: hrStatus,
            duration: durationDetail,
            duration_summary: "Total elapsed time: \(durMin) minutes",
            physiological_verdicts: physiologicalVerdicts.promptDescription,
            metric_explainers: nil
        )
    }

    /// Serializes the unified workout response into clean, compact JSON.
    func unifiedWorkoutAnalysisJSON() -> String {
        let response = buildUnifiedWorkoutToolResponse()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
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
