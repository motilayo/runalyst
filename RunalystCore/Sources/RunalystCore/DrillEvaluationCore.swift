import Foundation

// MARK: - Core Drill Interval Evaluator

public enum DrillEvaluationCore {

    public static func checkIsMet(
        workCadence: Int,
        workHeartRate: Int = 0,
        context: DrillEvaluationContextCore
    ) -> Bool {
        guard let lower = context.effectiveTargetMin, let upper = context.effectiveTargetMax else {
            return workCadence >= context.baselineCadence
        }

        switch context.drillIdentifier {
        case "tempo_surges":
            let cadenceMet = workCadence >= (lower - 2) && workCadence <= 195
            let hrMet = workHeartRate >= 160
            return cadenceMet || hrMet

        case "strides", "neuromuscular_primer", "hill_bounds", "fartlek_primer":
            return workCadence >= (lower - 2) && workCadence <= 195

        case "rhythm_intervals", "cadence_pyramids":
            return workCadence >= (lower - 2) && workCadence <= min(185, upper + 8)

        default: // zone2, recovery_jog, aerobic_flush, etc.
            return workCadence >= (lower - 2) && workCadence <= (upper + 2)
        }
    }

    public static func makeRep(
        repIndex: Int,
        work: DrillEvaluationSegmentCore,
        recovery: DrillEvaluationSegmentCore?,
        context: DrillEvaluationContextCore
    ) -> DrillIntervalRepCore {
        let repWorkCadence = Int(round(work.avgCadence))
        let repWorkHR = Int(round(work.avgHR))

        let repRecCadence: Int
        let repRecHR: Int
        if let recovery = recovery, recovery.avgCadence > 0 {
            repRecCadence = Int(round(recovery.avgCadence))
            repRecHR = Int(round(recovery.avgHR))
        } else {
            repRecCadence = max(130, context.baselineCadence - 20)
            repRecHR = 0
        }

        let isMet = checkIsMet(workCadence: repWorkCadence, workHeartRate: repWorkHR, context: context)

        return DrillIntervalRepCore(
            repIndex: repIndex,
            workCadence: repWorkCadence,
            workHeartRate: repWorkHR,
            recoveryCadence: repRecCadence,
            recoveryHeartRate: repRecHR,
            isMet: isMet,
            durationSeconds: work.duration > 0 ? work.duration : nil,
            workPaceSecondsPerKm: work.avgPace,
            recoveryPaceSecondsPerKm: recovery?.avgPace
        )
    }

    public static func evaluateContinuous(
        buckets: [TelemetryBucket],
        context: DrillEvaluationContextCore
    ) -> DrillIntervalSummaryCore {
        let active = buckets.filter { $0.cadenceSPM > 0 }
        let avgCadence: Int
        if active.isEmpty {
            avgCadence = context.baselineCadence
        } else {
            let totalCadence = active.map(\.cadenceSPM).reduce(0, +)
            avgCadence = Int(round(totalCadence / Double(active.count)))
        }

        let inTarget: Bool
        if let lower = context.effectiveTargetMin, let upper = context.effectiveTargetMax {
            inTarget = avgCadence >= lower && avgCadence <= upper
        } else {
            inTarget = true
        }

        let met = inTarget ? 1 : 0
        let tier: DrillAdherenceTierCore
        if inTarget {
            tier = context.oscDelta <= 0 ? .exceeded : .met
        } else {
            tier = .notMet
        }

        return DrillIntervalSummaryCore(
            drillIdentifier: context.drillIdentifier,
            intervalsMet: met,
            totalIntervals: 1,
            workCadenceAvg: avgCadence,
            recoveryCadenceAvg: 0,
            reps: [DrillIntervalRepCore(
                repIndex: 1,
                workCadence: avgCadence,
                workHeartRate: 0,
                recoveryCadence: 0,
                recoveryHeartRate: 0,
                isMet: inTarget
            )],
            tier: tier,
            verdict: inTarget ? "Held steady cadence throughout the drill." : "Cadence missed target steady band."
        )
    }

    public static func evaluateSegments(
        _ segments: [DrillEvaluationSegmentCore],
        context: DrillEvaluationContextCore,
        expectedIterations: Int,
        warmupSeconds: Double,
        workSeconds: Double
    ) -> DrillIntervalSummaryCore? {
        guard segments.count >= 2 else { return nil }

        let cadences = segments.map(\.avgCadence).filter { $0 > 0 }
        guard let minC = cadences.min(), let maxC = cadences.max(), (maxC - minC) >= 8.0 else {
            return nil
        }

        // Strategy A: Explicit work/recovery metadata hints
        let workIndices = segments.indices.filter { segments[$0].isWorkHint == true }
        if !workIndices.isEmpty {
            var reps: [DrillIntervalRepCore] = []
            for (repIdx, workIdx) in workIndices.enumerated() {
                let work = segments[workIdx]
                let rec: DrillEvaluationSegmentCore?
                if workIdx + 1 < segments.count && segments[workIdx + 1].isWorkHint == false {
                    rec = segments[workIdx + 1]
                } else {
                    rec = nil
                }
                reps.append(makeRep(repIndex: repIdx + 1, work: work, recovery: rec, context: context))
            }
            if reps.count >= 2 {
                return buildSummary(reps: reps, context: context)
            }
        }

        // Strategy B: Alternating structural sequence pairing
        var working = segments

        // 1. Strip Warmup bookend if present
        if working.count >= 3 {
            let exactBookendMatch = (working.count == 2 * expectedIterations + 2) ||
                (working.count == 2 * expectedIterations + 1)
            let isWarmupDuration = working[0].duration >= min(100.0, warmupSeconds * 0.6) &&
                working[0].duration >= workSeconds * 1.2
            if exactBookendMatch || isWarmupDuration {
                working.removeFirst()
            }
        }

        // 2. Strip Cooldown bookend if present
        if working.count >= 2 {
            let last = working[working.count - 1]
            let isCooldown = last.isWorkHint == false ||
                last.duration >= 90.0 ||
                (last.duration >= 45.0 && last.avgCadence < Double(context.baselineCadence) - 8.0)

            if isCooldown {
                if working.count % 2 == 1 || working.count == 2 * expectedIterations + 2 {
                    working.removeLast()
                }
            }
        }

        guard working.count >= 2 else { return nil }

        var reps: [DrillIntervalRepCore] = []
        let pairCount = working.count / 2

        for k in 0..<pairCount {
            let candidateA = working[2 * k]
            let candidateB = working[2 * k + 1]

            let workSeg: DrillEvaluationSegmentCore
            let recSeg: DrillEvaluationSegmentCore

            if candidateA.avgCadence >= candidateB.avgCadence {
                workSeg = candidateA
                recSeg = candidateB
            } else if (candidateB.avgCadence - candidateA.avgCadence >= 8.0) &&
                (candidateA.duration > candidateB.duration) {
                workSeg = candidateB
                recSeg = candidateA
            } else {
                workSeg = candidateA
                recSeg = candidateB
            }

            reps.append(makeRep(repIndex: k + 1, work: workSeg, recovery: recSeg, context: context))
        }

        if working.count % 2 == 1 {
            let trailingWork = working[working.count - 1]
            let isWorkCadence = trailingWork.isWorkHint == true ||
                trailingWork.avgCadence >= Double(context.baselineCadence) - 8.0
            if trailingWork.duration >= 10.0 && isWorkCadence {
                reps.append(makeRep(repIndex: reps.count + 1, work: trailingWork, recovery: nil, context: context))
            }
        }

        guard reps.count >= 2 else { return nil }

        return buildSummary(reps: reps, context: context)
    }

    public static func evaluateFromWaveform(
        buckets: [TelemetryBucket],
        context: DrillEvaluationContextCore
    ) -> DrillIntervalSummaryCore? {
        let active = buckets.filter { $0.cadenceSPM > 0 && $0.durationSeconds > 0 }
        guard active.count >= 6 else { return nil }

        var smoothed: [Double] = []
        smoothed.reserveCapacity(active.count)
        for i in 0..<active.count {
            let start = max(0, i - 1)
            let end = min(active.count, i + 2)
            let slice = active[start..<end]
            smoothed.append(slice.map(\.cadenceSPM).reduce(0, +) / Double(slice.count))
        }

        guard let minC = smoothed.min(), let maxC = smoothed.max(), (maxC - minC) >= 12.0 else {
            return nil
        }

        let threshold = (minC + maxC) / 2.0

        struct WaveSegment {
            let isWork: Bool
            var duration: Double
            var cadences: [Double]
            var hrs: [Double]
            var avgCadence: Double { cadences.isEmpty ? 0 : (cadences.reduce(0, +) / Double(cadences.count)) }
            var avgHR: Double {
                let valid = hrs.filter { $0 > 0 }
                return valid.isEmpty ? 0 : (valid.reduce(0, +) / Double(valid.count))
            }
        }

        var segments: [WaveSegment] = []
        var currentIsWork = active[0].cadenceSPM >= threshold
        var currentC = [active[0].cadenceSPM]
        var currentHR = [active[0].heartRateBPM]
        var currentDur = active[0].durationSeconds

        for i in 1..<active.count {
            let isWork = active[i].cadenceSPM >= threshold
            if isWork == currentIsWork {
                currentC.append(active[i].cadenceSPM)
                currentHR.append(active[i].heartRateBPM)
                currentDur += active[i].durationSeconds
            } else {
                segments.append(WaveSegment(isWork: currentIsWork, duration: currentDur, cadences: currentC, hrs: currentHR))
                currentIsWork = isWork
                currentC = [active[i].cadenceSPM]
                currentHR = [active[i].heartRateBPM]
                currentDur = active[i].durationSeconds
            }
        }
        segments.append(WaveSegment(isWork: currentIsWork, duration: currentDur, cadences: currentC, hrs: currentHR))

        var debounced: [WaveSegment] = []
        for seg in segments {
            if let last = debounced.last, last.isWork == seg.isWork {
                debounced[debounced.count - 1].duration += seg.duration
                debounced[debounced.count - 1].cadences.append(contentsOf: seg.cadences)
                debounced[debounced.count - 1].hrs.append(contentsOf: seg.hrs)
            } else if debounced.count >= 2,
                      seg.isWork,
                      let gap = debounced.last,
                      !gap.isWork,
                      gap.duration <= 15.0,
                      debounced[debounced.count - 2].isWork {
                let removedGap = debounced.removeLast()
                debounced[debounced.count - 1].duration += (removedGap.duration + seg.duration)
                debounced[debounced.count - 1].cadences.append(contentsOf: removedGap.cadences + seg.cadences)
                debounced[debounced.count - 1].hrs.append(contentsOf: removedGap.hrs + seg.hrs)
            } else {
                debounced.append(seg)
            }
        }

        var reps: [DrillIntervalRepCore] = []
        var repIndex = 1

        for i in 0..<debounced.count {
            let seg = debounced[i]
            guard seg.isWork && seg.duration >= 15.0 && seg.duration <= 300.0 else { continue }

            let repWorkCadence = Int(round(seg.avgCadence))
            let repWorkHR = Int(round(seg.avgHR))

            let repRecCadence: Int
            let repRecHR: Int
            if i + 1 < debounced.count && !debounced[i + 1].isWork {
                let recSeg = debounced[i + 1]
                repRecCadence = Int(round(recSeg.avgCadence))
                repRecHR = Int(round(recSeg.avgHR))
            } else {
                repRecCadence = max(130, context.baselineCadence - 20)
                repRecHR = 0
            }

            let isMet = checkIsMet(workCadence: repWorkCadence, workHeartRate: repWorkHR, context: context)

            reps.append(DrillIntervalRepCore(
                repIndex: repIndex,
                workCadence: repWorkCadence,
                workHeartRate: repWorkHR,
                recoveryCadence: repRecCadence,
                recoveryHeartRate: repRecHR,
                isMet: isMet
            ))
            repIndex += 1
        }

        guard reps.count >= 2 else { return nil }
        return buildSummary(reps: reps, context: context)
    }

    public static func evaluateFromSchedule(
        buckets: [TelemetryBucket],
        schedule: DrillScheduleCore,
        context: DrillEvaluationContextCore
    ) -> DrillIntervalSummaryCore {
        let warmupSec = schedule.warmupSeconds
        let iterations = schedule.iterations
        let workSec = schedule.workSeconds
        let recSec = schedule.recoverySeconds

        guard iterations > 1, !buckets.isEmpty, let workoutStart = buckets.first?.timestamp else {
            return evaluateContinuous(buckets: buckets, context: context)
        }

        var reps: [DrillIntervalRepCore] = []
        for i in 0..<iterations {
            let workStartOffset = warmupSec + Double(i) * (workSec + recSec)
            let workEndOffset = workStartOffset + workSec
            let recStartOffset = workEndOffset
            let recEndOffset = recStartOffset + recSec

            let workStartDate = workoutStart.addingTimeInterval(workStartOffset)
            let workEndDate = workoutStart.addingTimeInterval(workEndOffset)
            let recStartDate = workoutStart.addingTimeInterval(recStartOffset)
            let recEndDate = workoutStart.addingTimeInterval(recEndOffset)

            let workBuckets = buckets.filter { bucket in
                let mid = bucket.timestamp.addingTimeInterval(bucket.durationSeconds / 2.0)
                return mid >= workStartDate && mid < workEndDate
            }
            let recBuckets = buckets.filter { bucket in
                let mid = bucket.timestamp.addingTimeInterval(bucket.durationSeconds / 2.0)
                return mid >= recStartDate && mid < recEndDate
            }

            let repWorkCadence = workBuckets.isEmpty ? context.baselineCadence :
                Int(round(workBuckets.map(\.cadenceSPM).reduce(0, +) / Double(workBuckets.count)))
            let validWorkHR = workBuckets.map(\.heartRateBPM).filter { $0 > 0 }
            let repWorkHR = validWorkHR.isEmpty ? 0 : Int(round(validWorkHR.reduce(0, +) / Double(validWorkHR.count)))

            let repRecCadence = recBuckets.isEmpty ? max(130, context.baselineCadence - 20) :
                Int(round(recBuckets.map(\.cadenceSPM).reduce(0, +) / Double(recBuckets.count)))
            let validRecHR = recBuckets.map(\.heartRateBPM).filter { $0 > 0 }
            let repRecHR = validRecHR.isEmpty ? 0 : Int(round(validRecHR.reduce(0, +) / Double(validRecHR.count)))

            let isMet = checkIsMet(workCadence: repWorkCadence, workHeartRate: repWorkHR, context: context)

            reps.append(DrillIntervalRepCore(
                repIndex: i + 1,
                workCadence: repWorkCadence,
                workHeartRate: repWorkHR,
                recoveryCadence: repRecCadence,
                recoveryHeartRate: repRecHR,
                isMet: isMet
            ))
        }

        return buildSummary(reps: reps, context: context)
    }

    public static func buildSummary(
        reps: [DrillIntervalRepCore],
        context: DrillEvaluationContextCore
    ) -> DrillIntervalSummaryCore {
        let intervalsMet = reps.filter(\.isMet).count
        let totalIntervals = reps.count
        let totalWorkCadence = reps.map(\.workCadence).reduce(0, +)
        let totalRecCadence = reps.map(\.recoveryCadence).reduce(0, +)
        let avgWork = totalIntervals > 0 ? (totalWorkCadence / totalIntervals) : context.baselineCadence
        let avgRec = totalIntervals > 0 ? (totalRecCadence / totalIntervals) : max(130, context.baselineCadence - 20)

        let tier: DrillAdherenceTierCore
        let verdict: String

        if intervalsMet == totalIntervals && totalIntervals > 0 {
            if context.oscDelta <= 0 {
                tier = .exceeded
                verdict = "Flawless form execution: nailed all \(totalIntervals) intervals with improved vertical efficiency."
            } else {
                tier = .met
                verdict = "Target discipline held: nailed all \(totalIntervals) of \(totalIntervals) work intervals on target."
            }
        } else if intervalsMet >= (totalIntervals + 1) / 2 {
            tier = .partiallyMet
            verdict = "Solid effort: landed \(intervalsMet) of \(totalIntervals) work intervals within the target turnover band."
        } else {
            tier = .notMet
            verdict = "Developing turnover rhythm: completed \(intervalsMet) of \(totalIntervals) intervals in the target zone."
        }

        return DrillIntervalSummaryCore(
            drillIdentifier: context.drillIdentifier,
            intervalsMet: intervalsMet,
            totalIntervals: totalIntervals,
            workCadenceAvg: avgWork,
            recoveryCadenceAvg: avgRec,
            reps: reps,
            tier: tier,
            verdict: verdict
        )
    }
}
