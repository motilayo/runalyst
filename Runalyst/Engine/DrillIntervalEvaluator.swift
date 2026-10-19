import Foundation
import HealthKit

/// Represents the evaluated performance of an individual drill work rep.
struct DrillIntervalRep: Sendable, Equatable {
    let repIndex: Int
    let workCadence: Int
    let workHeartRate: Int
    let recoveryCadence: Int
    let recoveryHeartRate: Int
    let isMet: Bool
}

/// The complete interval-by-interval performance scorecard for a prescribed drill.
struct DrillIntervalSummary: Sendable, Equatable {
    let drillId: PreRunDrillId
    let intervalsMet: Int
    let totalIntervals: Int
    let workCadenceAvg: Int
    let recoveryCadenceAvg: Int
    let reps: [DrillIntervalRep]
    let tier: DrillAdherenceTier
    let verdict: String

    var adherencePercentage: Int {
        guard totalIntervals > 0 else { return 0 }
        return Int(round(Double(intervalsMet) / Double(totalIntervals) * 100.0))
    }

    /// Tags to persist interval results in RunRecord.framboiseTags
    var framboiseTags: [String] {
        var tags: [String] = []
        tags.append("drillIntervals:\(intervalsMet)/\(totalIntervals)")
        tags.append("drillWorkCadence:\(workCadenceAvg)")
        tags.append("drillRecCadence:\(recoveryCadenceAvg)")
        let repBits = reps.map { $0.isMet ? "1" : "0" }.joined(separator: ",")
        tags.append("drillReps:\(repBits)")
        return tags
    }

    /// Reconstructs a summary from stored framboiseTags if available
    static func from(tags: [String], drillId: PreRunDrillId) -> DrillIntervalSummary? {
        guard let intervalTag = tags.first(where: { $0.hasPrefix("drillIntervals:") }) else { return nil }
        let rawCounts = intervalTag.replacingOccurrences(of: "drillIntervals:", with: "").split(separator: "/")
        guard rawCounts.count == 2,
              let met = Int(rawCounts[0]),
              let total = Int(rawCounts[1]) else { return nil }

        let workCadence = tags.first(where: { $0.hasPrefix("drillWorkCadence:") })
            .flatMap { Int($0.replacingOccurrences(of: "drillWorkCadence:", with: "")) } ?? 0
        let recCadence = tags.first(where: { $0.hasPrefix("drillRecCadence:") })
            .flatMap { Int($0.replacingOccurrences(of: "drillRecCadence:", with: "")) } ?? 0

        var reps: [DrillIntervalRep] = []
        if let repTag = tags.first(where: { $0.hasPrefix("drillReps:") }) {
            let bits = repTag.replacingOccurrences(of: "drillReps:", with: "").split(separator: ",")
            for (idx, bit) in bits.enumerated() {
                reps.append(DrillIntervalRep(
                    repIndex: idx + 1,
                    workCadence: workCadence,
                    workHeartRate: 0,
                    recoveryCadence: recCadence,
                    recoveryHeartRate: 0,
                    isMet: bit == "1"
                ))
            }
        }

        let tier: DrillAdherenceTier
        let verdict: String
        if met == total && total > 0 {
            tier = .met
            verdict = "Flawless turnover discipline: hit all \(total) work intervals on target."
        } else if met >= (total + 1) / 2 {
            tier = .partiallyMet
            verdict = "Strong turnover adherence: hit \(met) of \(total) target intervals."
        } else {
            tier = .notMet
            verdict = "Developing turnover: hit \(met) of \(total) intervals in target band."
        }

        return DrillIntervalSummary(
            drillId: drillId,
            intervalsMet: met,
            totalIntervals: total,
            workCadenceAvg: workCadence,
            recoveryCadenceAvg: recCadence,
            reps: reps,
            tier: tier,
            verdict: verdict
        )
    }
}

/// Evaluates interval workouts rep-by-rep against prescribed target cadence and durations.
enum DrillIntervalEvaluator {

    /// Slices workouts into individual work and recovery intervals using a 4-tier evaluation hierarchy:
    /// 1. Native `HKWorkoutActivity` intervals (WorkoutKit / Apple Watch intervals, iOS 16+)
    /// 2. Native `HKWorkoutEvent` lap/segment intervals (iOS 8+)
    /// 3. Dynamic cadence waveform segmentation from 15-second `BucketData`
    /// 4. Fallback theoretical schedule (only if buckets are empty or continuous)
    static func evaluate(
        workout: HKWorkout? = nil,
        buckets: [BucketData],
        drillId: PreRunDrillId,
        baselineCadence: Int,
        workoutDuration: Double,
        oscDelta: Double = 0.0,
        targetCadenceOverride: String? = nil
    ) -> DrillIntervalSummary {
        let durationCategory: DrillDuration
        if workoutDuration <= 720 { // <= 12 min
            durationCategory = .tenMinutes
        } else if workoutDuration >= 1500 { // >= 25 min
            durationCategory = .thirtyMinutes
        } else {
            durationCategory = .fifteenMinutes
        }

        let template = DrillTemplate.template(for: drillId)
        let targetCadenceStr = targetCadenceOverride ?? template.calculateTargetCadence(baselineCadence)
        let preRunDrill = PreRunDrill(
            id: drillId,
            previousCadence: baselineCadence,
            targetCadence: targetCadenceStr,
            duration: durationCategory
        )
        let context = Context(
            drillId: drillId,
            effectiveRange: preRunDrill.effectiveTargetCadence,
            baselineCadence: baselineCadence,
            oscDelta: oscDelta,
            durationCategory: durationCategory
        )

        // Continuous drills (Zone 2, Recovery Jog, Aerobic Flush)
        if drillId.isAerobicContinuous {
            return evaluateContinuous(
                buckets: buckets,
                context: context
            )
        }

        // MARK: - Tier 1: Native HKWorkoutActivity Extraction (Apple Watch WorkoutKit)
        if let workout = workout, workout.workoutActivities.count >= 2 {
            if let summary = evaluateFromActivities(
                activities: workout.workoutActivities,
                buckets: buckets,
                context: context
            ) {
                return summary
            }
        }

        // MARK: - Tier 2: Native HKWorkoutEvent Lap/Segment Extraction
        if let workout = workout, let events = workout.workoutEvents,
           events.filter({ $0.type == .lap || $0.type == .segment }).count >= 4 {
            if let summary = evaluateFromEvents(
                events: events,
                buckets: buckets,
                context: context
            ) {
                return summary
            }
        }

        // MARK: - Tier 3: Dynamic Cadence Waveform Peak/Valley Segmentation
        if !buckets.isEmpty {
            if let summary = evaluateFromWaveform(
                buckets: buckets,
                context: context
            ) {
                return summary
            }
        }

        // MARK: - Tier 4: Fallback Theoretical Schedule (when buckets are empty)
        return evaluateFromSchedule(
            buckets: buckets,
            durationCategory: durationCategory,
            context: context
        )
    }

    struct Context: Sendable {
        let drillId: PreRunDrillId
        let effectiveRange: ClosedRange<Int>?
        let baselineCadence: Int
        let oscDelta: Double
        let durationCategory: DrillDuration

        init(
            drillId: PreRunDrillId,
            effectiveRange: ClosedRange<Int>?,
            baselineCadence: Int,
            oscDelta: Double = 0.0,
            durationCategory: DrillDuration = .fifteenMinutes
        ) {
            self.drillId = drillId
            self.effectiveRange = effectiveRange
            self.baselineCadence = baselineCadence
            self.oscDelta = oscDelta
            self.durationCategory = durationCategory
        }
    }

    struct DrillSegment: Sendable {
        let avgCadence: Double
        let avgHR: Double
        let duration: TimeInterval
        let isWorkHint: Bool?
    }

    private static func evaluateContinuous(
        buckets: [BucketData],
        context: Context
    ) -> DrillIntervalSummary {
        let active = buckets.filter { $0.meanCadence > 0 }
        let avgCadence: Int
        if active.isEmpty {
            avgCadence = context.baselineCadence
        } else {
            let totalCadence = active.map(\.meanCadence).reduce(0, +)
            avgCadence = Int(round(totalCadence / Double(active.count)))
        }
        let inTarget = context.effectiveRange?.contains(avgCadence) ?? true
        let met = inTarget ? 1 : 0
        let tier: DrillAdherenceTier
        if inTarget {
            tier = context.oscDelta <= 0 ? .exceeded : .met
        } else {
            tier = .notMet
        }
        return DrillIntervalSummary(
            drillId: context.drillId,
            intervalsMet: met,
            totalIntervals: 1,
            workCadenceAvg: avgCadence,
            recoveryCadenceAvg: 0,
            reps: [DrillIntervalRep(
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

    static func evaluateFromActivities(
        activities: [HKWorkoutActivity],
        buckets: [BucketData],
        context: Context
    ) -> DrillIntervalSummary? {
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)
        let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate)

        let sortedActivities = activities.sorted { $0.startDate < $1.startDate }
        var segments: [DrillSegment] = []

        for act in sortedActivities {
            guard act.duration > 0 else { continue }
            let steps = stepType.flatMap { act.allStatistics[$0]?.sumQuantity()?.doubleValue(for: .count()) } ?? 0
            let hrVal = hrType.flatMap {
                act.allStatistics[$0]?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            } ?? 0

            let avgC: Double
            let avgH: Double

            if steps > 0 {
                // Priority 1: Exact native Apple Watch hardware statistics for this activity segment
                avgC = steps / (act.duration / 60.0)
                avgH = hrVal
            } else {
                // Priority 2: Fallback to time-series bucket interpolation (e.g. test mocks without allStatistics)
                let actEnd = act.endDate ?? act.startDate.addingTimeInterval(act.duration)
                let actBuckets = buckets.filter { $0.startTime >= act.startDate && $0.startTime < actEnd }
                if !actBuckets.isEmpty {
                    let validCadences = actBuckets.map(\.meanCadence).filter { $0 > 0 }
                    avgC = validCadences.isEmpty ? 0 : (validCadences.reduce(0, +) / Double(validCadences.count))
                    let validHRs = actBuckets.map(\.meanHR).filter { $0 > 0 }
                    avgH = validHRs.isEmpty ? 0 : (validHRs.reduce(0, +) / Double(validHRs.count))
                } else {
                    avgC = 0
                    avgH = hrVal
                }
            }

            var hint: Bool?
            if let metadata = act.metadata {
                for (_, v) in metadata {
                    let valStr = String(describing: v).lowercased()
                    if valStr.contains("work") || valStr.contains("interval") {
                        hint = true
                        break
                    } else if valStr.contains("recovery") || valStr.contains("rest") {
                        hint = false
                        break
                    }
                }
            }

            segments.append(DrillSegment(
                avgCadence: avgC,
                avgHR: avgH,
                duration: act.duration,
                isWorkHint: hint
            ))
        }

        return evaluateSegments(segments, context: context)
    }

    static func evaluateFromEvents(
        events: [HKWorkoutEvent],
        buckets: [BucketData],
        context: Context
    ) -> DrillIntervalSummary? {
        let intervalEvents = events.filter { $0.type == .lap || $0.type == .segment }
        guard intervalEvents.count >= 2 else { return nil }

        let sortedEvents = intervalEvents.sorted { $0.dateInterval.start < $1.dateInterval.start }
        var segments: [DrillSegment] = []
        for evt in sortedEvents {
            guard evt.dateInterval.duration > 0 else { continue }
            let start = evt.dateInterval.start
            let end = evt.dateInterval.end
            let duration = evt.dateInterval.duration
            let segBuckets = buckets.filter { $0.startTime >= start && $0.startTime < end }
            let avgC = segBuckets.isEmpty ? 0.0 : (segBuckets.map(\.meanCadence).reduce(0, +) / Double(segBuckets.count))
            let validHRs = segBuckets.map(\.meanHR).filter { $0 > 0 }
            let avgH = validHRs.isEmpty ? 0.0 : (validHRs.reduce(0, +) / Double(validHRs.count))

            var hint: Bool?
            if let metadata = evt.metadata {
                for (_, v) in metadata {
                    let valStr = String(describing: v).lowercased()
                    if valStr.contains("work") || valStr.contains("interval") {
                        hint = true
                        break
                    } else if valStr.contains("recovery") || valStr.contains("rest") {
                        hint = false
                        break
                    }
                }
            }

            segments.append(DrillSegment(
                avgCadence: avgC,
                avgHR: avgH,
                duration: duration,
                isWorkHint: hint
            ))
        }

        return evaluateSegments(segments, context: context)
    }

    static func evaluateSegments(
        _ segments: [DrillSegment],
        context: Context
    ) -> DrillIntervalSummary? {
        guard segments.count >= 2 else { return nil }

        let cadences = segments.map(\.avgCadence).filter { $0 > 0 }
        guard let minC = cadences.min(), let maxC = cadences.max(), (maxC - minC) >= 8.0 else {
            return nil
        }

        let schedule = DrillSchedule.schedule(for: context.drillId, duration: context.durationCategory)
        let expectedIterations = schedule.iterations

        // Strategy A: Explicit work/recovery metadata hints
        let workIndices = segments.indices.filter { segments[$0].isWorkHint == true }
        if !workIndices.isEmpty {
            var reps: [DrillIntervalRep] = []
            for (repIdx, workIdx) in workIndices.enumerated() {
                let work = segments[workIdx]
                let rec: DrillSegment?
                if workIdx + 1 < segments.count && segments[workIdx + 1].isWorkHint == false {
                    rec = segments[workIdx + 1]
                } else {
                    rec = nil
                }
                reps.append(makeRep(
                    repIndex: repIdx + 1,
                    work: work,
                    recovery: rec,
                    context: context
                ))
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
            let isWarmupDuration = working[0].duration >= min(100.0, schedule.warmup * 0.6) &&
                working[0].duration >= schedule.workSec * 1.2
            if exactBookendMatch || isWarmupDuration {
                working.removeFirst()
            }
        }

        // 2. Strip Cooldown bookend if present (only if the last segment is truly a cooldown/rest, not a work rep)
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

        var reps: [DrillIntervalRep] = []
        let pairCount = working.count / 2

        for k in 0..<pairCount {
            let candidateA = working[2 * k]
            let candidateB = working[2 * k + 1]

            let workSeg: DrillSegment
            let recSeg: DrillSegment

            if candidateA.avgCadence >= candidateB.avgCadence {
                workSeg = candidateA
                recSeg = candidateB
            } else if (candidateB.avgCadence - candidateA.avgCadence >= 8.0) &&
                (candidateA.duration > candidateB.duration) {
                // Inverted sequence
                workSeg = candidateB
                recSeg = candidateA
            } else {
                workSeg = candidateA
                recSeg = candidateB
            }

            reps.append(makeRep(
                repIndex: k + 1,
                work: workSeg,
                recovery: recSeg,
                context: context
            ))
        }

        // Odd trailing work interval without recovery (e.g. runner finishes workout on the final work rep)
        if working.count % 2 == 1 {
            let trailingWork = working[working.count - 1]
            let isWorkCadence = trailingWork.isWorkHint == true ||
                trailingWork.avgCadence >= Double(context.baselineCadence) - 8.0
            if trailingWork.duration >= 10.0 && isWorkCadence {
                reps.append(makeRep(
                    repIndex: reps.count + 1,
                    work: trailingWork,
                    recovery: nil,
                    context: context
                ))
            }
        }

        guard reps.count >= 2 else { return nil }

        return buildSummary(reps: reps, context: context)
    }

    static func checkIsMet(
        workCadence: Int,
        workHeartRate: Int = 0,
        context: Context
    ) -> Bool {
        guard let range = context.effectiveRange else {
            return workCadence >= context.baselineCadence
        }

        switch context.drillId {
        case .tempoSurges:
            // Dual-target surge: met if cadence reaches the surge floor OR if heart rate achieves Zone 4 threshold effort (>= 160 BPM)
            let cadenceMet = workCadence >= (range.lowerBound - 2) && workCadence <= 195
            let hrMet = workHeartRate >= 160
            return cadenceMet || hrMet

        case .strides, .neuromuscularPrimer, .hillBounds, .fartlekPrimer:
            // Sprint & explosive turnover drills: target is a floor (capped at safe physiological limit 195 SPM)
            return workCadence >= (range.lowerBound - 2) && workCadence <= 195

        case .rhythmIntervals, .cadencePyramids:
            // Rhythm & cadence pyramid drills: standard lower buffer with generous upward tolerance (+8 SPM, up to 185 SPM)
            return workCadence >= (range.lowerBound - 2) && workCadence <= min(185, range.upperBound + 8)

        case .zone2Run, .recoveryJog, .aerobicFlush:
            // Continuous aerobic / active recovery: steady band
            return workCadence >= (range.lowerBound - 2) && workCadence <= (range.upperBound + 2)
        }
    }

    private static func makeRep(
        repIndex: Int,
        work: DrillSegment,
        recovery: DrillSegment?,
        context: Context
    ) -> DrillIntervalRep {
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

        return DrillIntervalRep(
            repIndex: repIndex,
            workCadence: repWorkCadence,
            workHeartRate: repWorkHR,
            recoveryCadence: repRecCadence,
            recoveryHeartRate: repRecHR,
            isMet: isMet
        )
    }

    static func evaluateFromWaveform(
        buckets: [BucketData],
        context: Context
    ) -> DrillIntervalSummary? {
        let active = buckets.filter { $0.meanCadence > 0 && $0.durationSeconds > 0 }
        guard active.count >= 6 else { return nil }

        // Smooth cadences using a 2-bucket (30-second) sliding window
        var smoothed: [Double] = []
        smoothed.reserveCapacity(active.count)
        for i in 0..<active.count {
            let start = max(0, i - 1)
            let end = min(active.count, i + 2)
            let slice = active[start..<end]
            smoothed.append(slice.map(\.meanCadence).reduce(0, +) / Double(slice.count))
        }

        guard let minC = smoothed.min(), let maxC = smoothed.max(), (maxC - minC) >= 12.0 else {
            return nil
        }

        let threshold = (minC + maxC) / 2.0

        struct WaveformSegment {
            let isWork: Bool
            var duration: Double
            var buckets: [BucketData]
            var avgCadence: Double {
                buckets.isEmpty ? 0 : (buckets.map(\.meanCadence).reduce(0, +) / Double(buckets.count))
            }
            var avgHR: Double {
                let valid = buckets.map(\.meanHR).filter { $0 > 0 }
                return valid.isEmpty ? 0 : (valid.reduce(0, +) / Double(valid.count))
            }
        }

        var segments: [WaveformSegment] = []
        var currentIsWork = active[0].meanCadence >= threshold
        var currentBuckets: [BucketData] = [active[0]]

        for i in 1..<active.count {
            let isWork = active[i].meanCadence >= threshold
            if isWork == currentIsWork {
                currentBuckets.append(active[i])
            } else {
                let dur = currentBuckets.map(\.durationSeconds).reduce(0, +)
                segments.append(WaveformSegment(isWork: currentIsWork, duration: dur, buckets: currentBuckets))
                currentIsWork = isWork
                currentBuckets = [active[i]]
            }
        }
        if !currentBuckets.isEmpty {
            let dur = currentBuckets.map(\.durationSeconds).reduce(0, +)
            segments.append(WaveformSegment(isWork: currentIsWork, duration: dur, buckets: currentBuckets))
        }

        // Debounce / gap bridge: merge work segments separated by brief momentary dip (<= 15s)
        var debounced: [WaveformSegment] = []
        for seg in segments {
            if let last = debounced.last, last.isWork == seg.isWork {
                debounced[debounced.count - 1].duration += seg.duration
                debounced[debounced.count - 1].buckets.append(contentsOf: seg.buckets)
            } else if debounced.count >= 2,
                      seg.isWork,
                      let gap = debounced.last,
                      !gap.isWork,
                      gap.duration <= 15.0,
                      debounced[debounced.count - 2].isWork {
                let removedGap = debounced.removeLast()
                debounced[debounced.count - 1].duration += (removedGap.duration + seg.duration)
                debounced[debounced.count - 1].buckets.append(contentsOf: removedGap.buckets)
                debounced[debounced.count - 1].buckets.append(contentsOf: seg.buckets)
            } else {
                debounced.append(seg)
            }
        }
        segments = debounced

        // Filter valid interval work segments (duration >= 15s and <= 300s)
        var reps: [DrillIntervalRep] = []
        var repIndex = 1

        for i in 0..<segments.count {
            let seg = segments[i]
            guard seg.isWork && seg.duration >= 15.0 && seg.duration <= 300.0 else { continue }

            let repWorkCadence = Int(round(seg.avgCadence))
            let repWorkHR = Int(round(seg.avgHR))

            let repRecCadence: Int
            let repRecHR: Int
            if i + 1 < segments.count && !segments[i + 1].isWork {
                let recSeg = segments[i + 1]
                repRecCadence = Int(round(recSeg.avgCadence))
                repRecHR = Int(round(recSeg.avgHR))
            } else {
                repRecCadence = max(130, context.baselineCadence - 20)
                repRecHR = 0
            }

            let isMet = checkIsMet(workCadence: repWorkCadence, workHeartRate: repWorkHR, context: context)

            reps.append(DrillIntervalRep(
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

        return buildSummary(
            reps: reps,
            context: context
        )
    }

    private static func evaluateFromSchedule(
        buckets: [BucketData],
        durationCategory: DrillDuration,
        context: Context
    ) -> DrillIntervalSummary {
        let schedule = DrillSchedule.schedule(for: context.drillId, duration: durationCategory)
        let warmupSec = schedule.warmupSeconds
        let iterations = schedule.iterations
        let workSec = schedule.workSeconds
        let recSec = schedule.recoverySeconds

        guard iterations > 1, !buckets.isEmpty, let workoutStart = buckets.first?.startTime else {
            return evaluateContinuous(
                buckets: buckets,
                context: context
            )
        }

        var reps: [DrillIntervalRep] = []
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
                let mid = bucket.startTime.addingTimeInterval(bucket.durationSeconds / 2.0)
                return mid >= workStartDate && mid < workEndDate
            }
            let recBuckets = buckets.filter { bucket in
                let mid = bucket.startTime.addingTimeInterval(bucket.durationSeconds / 2.0)
                return mid >= recStartDate && mid < recEndDate
            }

            let repWorkCadence = workBuckets.isEmpty ? context.baselineCadence :
                Int(round(workBuckets.map(\.meanCadence).reduce(0, +) / Double(workBuckets.count)))
            let validWorkHR = workBuckets.map(\.meanHR).filter { $0 > 0 }
            let repWorkHR = validWorkHR.isEmpty ? 0 : Int(round(validWorkHR.reduce(0, +) / Double(validWorkHR.count)))

            let repRecCadence = recBuckets.isEmpty ? max(130, context.baselineCadence - 20) :
                Int(round(recBuckets.map(\.meanCadence).reduce(0, +) / Double(recBuckets.count)))
            let validRecHR = recBuckets.map(\.meanHR).filter { $0 > 0 }
            let repRecHR = validRecHR.isEmpty ? 0 : Int(round(validRecHR.reduce(0, +) / Double(validRecHR.count)))

            let isMet = checkIsMet(workCadence: repWorkCadence, workHeartRate: repWorkHR, context: context)

            reps.append(DrillIntervalRep(
                repIndex: i + 1,
                workCadence: repWorkCadence,
                workHeartRate: repWorkHR,
                recoveryCadence: repRecCadence,
                recoveryHeartRate: repRecHR,
                isMet: isMet
            ))
        }

        return buildSummary(
            reps: reps,
            context: context
        )
    }

    private static func buildSummary(
        reps: [DrillIntervalRep],
        context: Context
    ) -> DrillIntervalSummary {
        let intervalsMet = reps.filter(\.isMet).count
        let totalIntervals = reps.count
        let totalWorkCadence = reps.map(\.workCadence).reduce(0, +)
        let totalRecCadence = reps.map(\.recoveryCadence).reduce(0, +)
        let avgWork = totalIntervals > 0 ? (totalWorkCadence / totalIntervals) : context.baselineCadence
        let avgRec = totalIntervals > 0 ? (totalRecCadence / totalIntervals) : max(130, context.baselineCadence - 20)

        let tier: DrillAdherenceTier
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

        return DrillIntervalSummary(
            drillId: context.drillId,
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
