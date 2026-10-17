import Foundation
import HealthKit
#if canImport(WorkoutKit)
@preconcurrency import WorkoutKit
#endif

/// The recognized drill pattern signature and confidence metrics.
struct DrillPatternMatch: Sendable, Equatable {
    let drillId: PreRunDrillId
    let confidence: Double
    let detectedIntervalCount: Int
    let avgWorkCadence: Int
    let avgRecoveryCadence: Int
    let signatureDescription: String
}

/// A deterministic pattern recognition engine that identifies structured drills
/// directly from HealthKit biomechanical time-series data, workout activities, and workout events.
enum DrillPatternRecognizer {

    // MARK: - Primary Time-Series Pattern Recognizer

    /// Evaluates 15-second BucketData time-series to detect drill patterns autonomously.
    static func recognizeDrill(
        buckets: [BucketData],
        baselineCadence: Int = 155,
        workoutDuration: Double,
        zone4Threshold: Double = 161.5,
        zone2Threshold: Double = 142.0,
        zone1Threshold: Double = 125.0
    ) -> DrillPatternMatch? {
        guard buckets.count >= 8 else { return nil }

        let active = buckets.filter { $0.meanCadence > 0 && $0.durationSeconds > 0 }
        guard active.count >= 8 else { return nil }

        let cadences = active.map(\.meanCadence)
        let meanCadence = cadences.reduce(0, +) / Double(cadences.count)
        let varianceCadence = cadences.map { pow($0 - meanCadence, 2) }.reduce(0, +) / Double(cadences.count)
        let stdCadence = sqrt(varianceCadence)
        let cadenceCV = meanCadence > 0 ? (stdCadence / meanCadence) : 0.0

        let refBaseline = baselineCadence > 0 ? Double(baselineCadence) : meanCadence

        // MARK: 1. Tempo Surges Signature (Continuous Tempo Run with Threshold Surges)
        // A continuous aerobic run with distinct surges pushing into Zone 4
        if workoutDuration >= 360.0 {
            if let tempoMatch = detectTempoSurges(
                buckets: buckets,
                refBaseline: refBaseline,
                workoutDuration: workoutDuration,
                zone4Threshold: zone4Threshold,
                zone2Threshold: zone2Threshold
            ) {
                return tempoMatch
            }
        }

        // Continuous Run Guardrail for Turnover Intervals:
        // A run with low-to-moderate cadence variability across the session is a continuous aerobic run
        // (e.g. Easy Run, Steady Effort, Recovery Run, Tempo Run).
        // Continuous runs MUST NEVER be autonomously recognized as drills; standard run classifiers handle them.
        guard cadenceCV >= 0.020 && stdCadence >= 2.5 else {
            return nil
        }

        // Smooth cadences using a 2-bucket (30-second) sliding window
        var smoothedCadences: [Double] = []
        smoothedCadences.reserveCapacity(active.count)
        for i in 0..<active.count {
            let start = max(0, i - 1)
            let end = min(active.count, i + 2)
            let slice = active[start..<end]
            let avg = slice.map(\.meanCadence).reduce(0, +) / Double(slice.count)
            smoothedCadences.append(avg)
        }

        // A true interval workout requires clear cadence contrast between work and recovery (at least 4.0 SPM).
        // Terrain fluctuations and street corner dips (10-15 SPM) do not constitute an interval drill without interval alternation.
        guard let rawMinC = cadences.min(),
              let rawMaxC = cadences.max(),
              (rawMaxC - rawMinC) >= 4.0 else {
            return nil
        }

        // Segment contiguous buckets into candidate work and recovery regions.
        // Uses a two-pass approach:
        // Pass 1: Global midpoint threshold (min + max) / 2.
        // Pass 2: High-cadence float recovery search when a slow warmup pulls global threshold below active recovery.
        struct CandidateSegment {
            let isWork: Bool
            var duration: Double
            var buckets: [BucketData]
            var avgCadence: Double {
                buckets.isEmpty ? 0 : (buckets.map(\.meanCadence).reduce(0, +) / Double(buckets.count))
            }
            var avgHR: Double {
                let validHRs = buckets.map(\.meanHR).filter { $0 > 0 }
                return validHRs.isEmpty ? 0 : (validHRs.reduce(0, +) / Double(validHRs.count))
            }
            var maxCadence: Double {
                buckets.map(\.meanCadence).max() ?? 0
            }
        }

        func buildSegments(withThreshold threshold: Double) -> (workReps: [CandidateSegment], recReps: [CandidateSegment], allIntervalSegments: [CandidateSegment]) {
            var rawSegments: [CandidateSegment] = []
            var currentIsWork = smoothedCadences[0] >= threshold
            var currentBuckets: [BucketData] = [active[0]]

            for i in 1..<smoothedCadences.count {
                let isWork = smoothedCadences[i] >= threshold
                let curAvgCadence = currentBuckets.map(\.meanCadence).reduce(0, +) / Double(currentBuckets.count)
                let curDuration = currentBuckets.map(\.durationSeconds).reduce(0, +)
                let isCadenceStep = curDuration >= 60.0 && abs(smoothedCadences[i] - curAvgCadence) >= 10.0

                if isWork == currentIsWork && !isCadenceStep {
                    currentBuckets.append(active[i])
                } else {
                    let dur = currentBuckets.map(\.durationSeconds).reduce(0, +)
                    rawSegments.append(CandidateSegment(isWork: currentIsWork, duration: dur, buckets: currentBuckets))
                    currentIsWork = isWork
                    currentBuckets = [active[i]]
                }
            }
            if !currentBuckets.isEmpty {
                let dur = currentBuckets.map(\.durationSeconds).reduce(0, +)
                rawSegments.append(CandidateSegment(isWork: currentIsWork, duration: dur, buckets: currentBuckets))
            }

            var intervalSegments = rawSegments
            if intervalSegments.count >= 3 && !intervalSegments[0].isWork && intervalSegments[0].duration >= 45.0 {
                intervalSegments.removeFirst()
            }

            let work = intervalSegments.filter { $0.isWork && $0.duration >= 15.0 && $0.duration <= 130.0 }
            let rec = intervalSegments.filter { !$0.isWork && $0.duration >= 20.0 }
            return (work, rec, intervalSegments)
        }

        let globalThreshold = (rawMinC + rawMaxC) / 2.0
        var (workReps, recReps, intervalSegments) = buildSegments(withThreshold: globalThreshold)

        // Pass 2: High-cadence float recovery search
        // When a slow warmup pulls globalThreshold below recovery cadence,
        // search for peaks and valleys within the elevated region (>= globalThreshold - 2.0)
        if !(workReps.count >= 3 && recReps.count >= 2) {
            var elevatedPeaks: [Double] = []
            var elevatedValleys: [Double] = []

            for i in 1..<(smoothedCadences.count - 1) {
                guard smoothedCadences[i] >= globalThreshold - 2.0 else { continue }
                if smoothedCadences[i] >= smoothedCadences[i - 1] && smoothedCadences[i] >= smoothedCadences[i + 1] && (smoothedCadences[i] > smoothedCadences[i - 1] || smoothedCadences[i] > smoothedCadences[i + 1]) {
                    elevatedPeaks.append(smoothedCadences[i])
                } else if smoothedCadences[i] <= smoothedCadences[i - 1] && smoothedCadences[i] <= smoothedCadences[i + 1] && (smoothedCadences[i] < smoothedCadences[i - 1] || smoothedCadences[i] < smoothedCadences[i + 1]) {
                    elevatedValleys.append(smoothedCadences[i])
                }
            }

            if elevatedPeaks.count >= 2 && elevatedValleys.count >= 2 {
                let medPeak = elevatedPeaks.sorted()[elevatedPeaks.count / 2]
                let medValley = elevatedValleys.sorted()[elevatedValleys.count / 2]
                if (medPeak - medValley) >= 3.5 {
                    let floatThreshold = (medPeak + medValley) / 2.0
                    let (pass2Work, pass2Rec, pass2Intervals) = buildSegments(withThreshold: floatThreshold)
                    if pass2Work.count >= 3 && pass2Rec.count >= 2 {
                        workReps = pass2Work
                        recReps = pass2Rec
                        intervalSegments = pass2Intervals
                    }
                }
            }
        }

        // Structured intervals require alternating sets with at least 3 distinct recovery reps
        guard workReps.count >= 3 && recReps.count >= 2 else {
            return nil
        }

        let totalWorkTime = workReps.map(\.duration).reduce(0, +)
        let totalRecTime = recReps.map(\.duration).reduce(0, +)
        // Recovery must be at least 15% of the active interval block duration
        guard (totalWorkTime + totalRecTime) > 0, (totalRecTime / (totalWorkTime + totalRecTime)) >= 0.15 else {
            return nil
        }

        // MARK: 1. Strides Signature
        // 3-10 brief (15s to 45s) high-cadence bursts reaching >= 178 SPM (or baseline + 18)
        // with walking/slow-jog recovery (<= 130 SPM or >= 30 SPM drop)
        let stridesCandidates = workReps.filter {
            $0.duration <= 45.0 && ($0.maxCadence >= 178.0 || $0.avgCadence >= refBaseline + 18.0)
        }
        if stridesCandidates.count >= 3 && Double(stridesCandidates.count) >= Double(workReps.count) * 0.70 {
            let avgRecC = recReps.isEmpty ? 0.0 : (recReps.map { $0.avgCadence }.reduce(0, +) / Double(recReps.count))
            let avgStridesC = stridesCandidates.map { $0.avgCadence }.reduce(0, +) / Double(stridesCandidates.count)
            let avgWorkDur = stridesCandidates.map(\.duration).reduce(0, +) / Double(stridesCandidates.count)
            let avgRecDur = recReps.isEmpty ? 0.0 : (recReps.map(\.duration).reduce(0, +) / Double(recReps.count))

            if let sched = DrillSchedule.findMatchingSchedule(
                workoutDuration: workoutDuration,
                detectedIterations: stridesCandidates.count,
                avgWorkDuration: avgWorkDur,
                avgRecoveryDuration: avgRecDur,
                candidateDrills: [.strides]
            ), avgRecC <= 130.0 || (avgStridesC - avgRecC) >= 28.0 {
                return DrillPatternMatch(
                    drillId: .strides,
                    confidence: 0.95,
                    detectedIntervalCount: stridesCandidates.count,
                    avgWorkCadence: Int(round(avgStridesC)),
                    avgRecoveryCadence: Int(round(avgRecC)),
                    signatureDescription: "Detected \(stridesCandidates.count) explosive accelerations (\(sched.durationCategory.title), avg \(Int(round(avgStridesC))) SPM) with walk/light recovery."
                )
            }
        }

        // MARK: 2. Cadence Pyramids vs Rhythm Intervals
        let intervalWorkReps = workReps.filter { $0.duration >= 20.0 && $0.duration <= 130.0 }
        if intervalWorkReps.count >= 3 && recReps.count >= 2 {
            let workCadences = intervalWorkReps.map { $0.avgCadence }
            let wMean = workCadences.reduce(0, +) / Double(workCadences.count)
            let avgRecC = recReps.map { $0.avgCadence }.reduce(0, +) / Double(recReps.count)
            let contrast = wMean - avgRecC
            let avgWorkDur = intervalWorkReps.map(\.duration).reduce(0, +) / Double(intervalWorkReps.count)
            let avgRecDur = recReps.map(\.duration).reduce(0, +) / Double(recReps.count)

            // Cadence Pyramids: progressive monotonic step-up (>= 2.0 SPM per step) or up/down pyramid
            let isMonotonicUp: Bool = {
                for i in 0..<(workCadences.count - 1) where (workCadences[i + 1] - workCadences[i]) < 2.0 {
                    return false
                }
                return true
            }()
            let cadenceSpread = (workCadences.max() ?? 0) - (workCadences.min() ?? 0)

            var isPyramid = false
            if workCadences.count >= 4 && !isMonotonicUp {
                if let maxVal = workCadences.max(), let peakIdx = workCadences.firstIndex(of: maxVal), peakIdx > 0 && peakIdx < workCadences.count - 1 {
                    var leftUp = true
                    for i in 0..<peakIdx where workCadences[i + 1] < workCadences[i] - 0.5 {
                        leftUp = false
                        break
                    }
                    var rightDown = true
                    for i in peakIdx..<(workCadences.count - 1) where workCadences[i + 1] > workCadences[i] + 0.5 {
                        rightDown = false
                        break
                    }
                    if leftUp && rightDown && cadenceSpread >= 5.0 {
                        isPyramid = true
                    }
                }
            }

            if let sched = DrillSchedule.findMatchingSchedule(
                workoutDuration: workoutDuration,
                detectedIterations: intervalWorkReps.count,
                avgWorkDuration: avgWorkDur,
                avgRecoveryDuration: avgRecDur,
                candidateDrills: [.cadencePyramids]
            ), contrast >= 12.0 && ((isMonotonicUp && cadenceSpread >= 5.0) || isPyramid) {
                return DrillPatternMatch(
                    drillId: .cadencePyramids,
                    confidence: 0.95,
                    detectedIntervalCount: intervalWorkReps.count,
                    avgWorkCadence: Int(round(wMean)),
                    avgRecoveryCadence: Int(round(avgRecC)),
                    signatureDescription: "Detected \(intervalWorkReps.count) stepped intervals (\(sched.durationCategory.title)) with progressive turnover range (\(Int(round(workCadences.min() ?? 0)))–\(Int(round(workCadences.max() ?? 0))) SPM)."
                )
            }

            // Rhythm Intervals:
            // Crucial Guardrail: The work cadence MUST be distinctly elevated above the aerobic baseline
            // (at least baseline - 2.0 SPM when baseline is supplied), with easy jog float recovery,
            // contrast >= 4.0 SPM, and tight metronomic work consistency (wStd <= 3.8).
            let wVariance = workCadences.map { pow($0 - wMean, 2) }.reduce(0, +) / Double(workCadences.count)
            let wStd = sqrt(wVariance)

            let isElevatedAboveBaseline: Bool = {
                if baselineCadence > 0 {
                    return wMean >= Double(baselineCadence) - 2.0
                }
                return true
            }()

            if let sched = DrillSchedule.findMatchingSchedule(
                workoutDuration: workoutDuration,
                detectedIterations: intervalWorkReps.count,
                avgWorkDuration: avgWorkDur,
                avgRecoveryDuration: avgRecDur,
                candidateDrills: [.rhythmIntervals]
            ), contrast >= 4.0 &&
               isElevatedAboveBaseline &&
               wStd <= 3.8 {
                return DrillPatternMatch(
                    drillId: .rhythmIntervals,
                    confidence: 0.95,
                    detectedIntervalCount: intervalWorkReps.count,
                    avgWorkCadence: Int(round(wMean)),
                    avgRecoveryCadence: Int(round(avgRecC)),
                    signatureDescription: "Detected \(intervalWorkReps.count) steady rhythm intervals (\(sched.durationCategory.title)) at \(Int(round(wMean))) SPM with tight turnover consistency (std \(String(format: "%.1f", wStd)) SPM)."
                )
            }
        }

        return nil
    }

    private static func detectTempoSurges(
        buckets: [BucketData],
        refBaseline: Double,
        workoutDuration: Double,
        zone4Threshold: Double,
        zone2Threshold: Double
    ) -> DrillPatternMatch? {
        guard workoutDuration >= 360.0 else { return nil }

        // Identify candidate surge reps: contiguous bucket index ranges with HR in Zone 4 and elevated cadence
        var surgeRanges: [Range<Int>] = []
        var surgeStart: Int?

        for i in 0..<buckets.count {
            let b = buckets[i]
            let isSurge = b.meanHR >= (zone4Threshold - 2.0) && b.meanCadence >= (refBaseline + 5.0)
            if isSurge {
                if surgeStart == nil { surgeStart = i }
            } else {
                if let start = surgeStart {
                    let dur = buckets[start..<i].map(\.durationSeconds).reduce(0, +)
                    if dur >= 20.0 && dur <= 240.0 {
                        surgeRanges.append(start..<i)
                    }
                    surgeStart = nil
                }
            }
        }
        if let start = surgeStart {
            let dur = buckets[start..<buckets.count].map(\.durationSeconds).reduce(0, +)
            if dur >= 20.0 && dur <= 240.0 {
                surgeRanges.append(start..<buckets.count)
            }
        }

        // Tempo Surges in Runalyst strictly prescribes 3 iterations (10m, 15m) or 4 iterations (30m)
        guard surgeRanges.count == 3 || surgeRanges.count == 4 else { return nil }

        let surgeDurations = surgeRanges.map { r in
            buckets[r].map(\.durationSeconds).reduce(0, +)
        }
        let avgWorkDuration = surgeDurations.reduce(0, +) / Double(surgeDurations.count)

        // Compute recovery durations between consecutive surges
        var recDurations: [Double] = []
        for idx in 0..<(surgeRanges.count - 1) {
            let recStart = surgeRanges[idx].upperBound
            let recEnd = surgeRanges[idx + 1].lowerBound
            if recEnd > recStart {
                let dur = buckets[recStart..<recEnd].map(\.durationSeconds).reduce(0, +)
                recDurations.append(dur)
            }
        }
        let avgRecDuration = recDurations.isEmpty ? 0.0 : (recDurations.reduce(0, +) / Double(recDurations.count))

        // Strict schedule matching: Must match one of the canonical Tempo Surges schedules
        guard let matchingSchedule = DrillSchedule.findMatchingSchedule(
            workoutDuration: workoutDuration,
            detectedIterations: surgeRanges.count,
            avgWorkDuration: avgWorkDuration,
            avgRecoveryDuration: avgRecDuration,
            candidateDrills: [.tempoSurges]
        ) else {
            return nil
        }

        // Inspect baseline running outside of surges
        var surgeIndices = Set<Int>()
        for r in surgeRanges {
            for idx in r { surgeIndices.insert(idx) }
        }
        let baseBuckets = (0..<buckets.count).filter { !surgeIndices.contains($0) && buckets[$0].meanCadence > 0 }.map { buckets[$0] }
        guard !baseBuckets.isEmpty else { return nil }

        let baseCadence = baseBuckets.map(\.meanCadence).reduce(0, +) / Double(baseBuckets.count)
        let validHRBase = baseBuckets.map(\.meanHR).filter { $0 > 0 }
        let baseHR = validHRBase.isEmpty ? 0 : (validHRBase.reduce(0, +) / Double(validHRBase.count))

        let allSurgeBuckets = surgeIndices.map { buckets[$0] }
        let surgeCadence = allSurgeBuckets.map(\.meanCadence).reduce(0, +) / Double(allSurgeBuckets.count)
        let surgeTime = allSurgeBuckets.map(\.durationSeconds).reduce(0, +)

        // Baseline must be in aerobic tempo (near baseline cadence and >= Zone 2 HR)
        guard baseCadence >= (refBaseline - 4.0),
              baseHR >= (zone2Threshold - 2.0),
              (surgeCadence - baseCadence) >= 7.0,
              (surgeTime / workoutDuration) <= 0.35 else {
            return nil
        }

        return DrillPatternMatch(
            drillId: .tempoSurges,
            confidence: 0.94,
            detectedIntervalCount: surgeRanges.count,
            avgWorkCadence: Int(round(surgeCadence)),
            avgRecoveryCadence: Int(round(baseCadence)),
            signatureDescription: "Detected continuous tempo run containing \(surgeRanges.count) threshold surges (\(matchingSchedule.durationCategory.title), avg \(Int(round(surgeCadence))) SPM in Zone 4)."
        )
    }

    // MARK: - Tier 2: HKWorkoutActivity Structural Extraction

    /// Inspects native Apple Watch workout interval activities (iOS 16+) to match drill patterns.
    static func recognizeFromActivities(
        activities: [HKWorkoutActivity],
        buckets: [BucketData],
        baselineCadence: Int
    ) -> DrillPatternMatch? {
        guard activities.count >= 4 else { return nil }

        // Compute average cadence and HR for each activity
        struct ActivityStats {
            let activity: HKWorkoutActivity
            let avgCadence: Double
            let avgHR: Double
            let duration: TimeInterval
        }

        var activityStats: [ActivityStats] = []
        for act in activities {
            let actEnd = act.endDate ?? act.startDate.addingTimeInterval(act.duration)
            let actBuckets = buckets.filter { $0.startTime >= act.startDate && $0.startTime < actEnd }
            let avgC: Double
            let avgH: Double
            if !actBuckets.isEmpty {
                avgC = actBuckets.map { $0.meanCadence }.reduce(0, +) / Double(actBuckets.count)
                let validHRs = actBuckets.map { $0.meanHR }.filter { $0 > 0 }
                avgH = validHRs.isEmpty ? 0.0 : (validHRs.reduce(0, +) / Double(validHRs.count))
            } else {
                let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)
                let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate)
                let steps = stepType.flatMap { act.allStatistics[$0]?.sumQuantity()?.doubleValue(for: .count()) } ?? 0
                let hrVal = hrType.flatMap { act.allStatistics[$0]?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) } ?? 0
                avgC = act.duration > 0 ? (steps / (act.duration / 60.0)) : 0
                avgH = hrVal
            }
            activityStats.append(ActivityStats(activity: act, avgCadence: avgC, avgHR: avgH, duration: act.duration))
        }

        // Determine high (work) vs low (recovery) activities
        guard let minC = activityStats.map({ $0.avgCadence }).min(),
              let maxC = activityStats.map({ $0.avgCadence }).max(),
              (maxC - minC) >= 10.0 else {
            return nil
        }

        let threshold = (minC + maxC) / 2.0
        let workActs = activityStats.filter { $0.avgCadence >= threshold && $0.duration >= 15.0 }
        let recActs = activityStats.filter { $0.avgCadence < threshold }

        guard workActs.count >= 3 else { return nil }

        let workCadences = workActs.map { $0.avgCadence }
        let wMean = workCadences.reduce(0, +) / Double(workCadences.count)
        let wVariance = workCadences.map { pow($0 - wMean, 2) }.reduce(0, +) / Double(workCadences.count)
        let wStd = sqrt(wVariance)
        let avgRecC = recActs.isEmpty ? 0.0 : (recActs.map { $0.avgCadence }.reduce(0, +) / Double(recActs.count))

        let totalActDuration = activityStats.map(\.duration).reduce(0, +)
        let avgWorkDur = workActs.map(\.duration).reduce(0, +) / Double(workActs.count)
        let avgRecDur = recActs.isEmpty ? 0.0 : (recActs.map(\.duration).reduce(0, +) / Double(recActs.count))

        // Strides check
        if let sched = DrillSchedule.findMatchingSchedule(
            workoutDuration: totalActDuration,
            detectedIterations: workActs.count,
            avgWorkDuration: avgWorkDur,
            avgRecoveryDuration: avgRecDur,
            candidateDrills: [.strides]
        ), workActs.allSatisfy({ $0.duration <= 45.0 }) && (wMean >= 174.0 || wMean >= Double(baselineCadence) + 16.0) {
            return DrillPatternMatch(
                drillId: .strides,
                confidence: 0.95,
                detectedIntervalCount: workActs.count,
                avgWorkCadence: Int(round(wMean)),
                avgRecoveryCadence: Int(round(avgRecC)),
                signatureDescription: "Structured workout activities: \(workActs.count) short stride sprints (\(sched.durationCategory.title)) at \(Int(round(wMean))) SPM."
            )
        }

        // Pyramids check
        let isMonotonicUp: Bool = {
            for i in 0..<(workCadences.count - 1) where (workCadences[i + 1] - workCadences[i]) < 2.0 {
                return false
            }
            return true
        }()
        let spread = (workCadences.max() ?? 0) - (workCadences.min() ?? 0)
        if let sched = DrillSchedule.findMatchingSchedule(
            workoutDuration: totalActDuration,
            detectedIterations: workActs.count,
            avgWorkDuration: avgWorkDur,
            avgRecoveryDuration: avgRecDur,
            candidateDrills: [.cadencePyramids]
        ), isMonotonicUp && spread >= 5.0 {
            return DrillPatternMatch(
                drillId: .cadencePyramids,
                confidence: 0.96,
                detectedIntervalCount: workActs.count,
                avgWorkCadence: Int(round(wMean)),
                avgRecoveryCadence: Int(round(avgRecC)),
                signatureDescription: "Structured workout activities: \(workActs.count) progressive pyramid reps (\(sched.durationCategory.title), \(Int(round(workCadences.min() ?? 0)))–\(Int(round(workCadences.max() ?? 0))) SPM)."
            )
        }

        // Rhythm intervals check
        if let sched = DrillSchedule.findMatchingSchedule(
            workoutDuration: totalActDuration,
            detectedIterations: workActs.count,
            avgWorkDuration: avgWorkDur,
            avgRecoveryDuration: avgRecDur,
            candidateDrills: [.rhythmIntervals]
        ), wStd <= 3.8 {
            return DrillPatternMatch(
                drillId: .rhythmIntervals,
                confidence: 0.95,
                detectedIntervalCount: workActs.count,
                avgWorkCadence: Int(round(wMean)),
                avgRecoveryCadence: Int(round(avgRecC)),
                signatureDescription: "Structured workout activities: \(workActs.count) interval reps (\(sched.durationCategory.title)) dialed to \(Int(round(wMean))) SPM."
            )
        }

        // Tempo surges check
        if let sched = DrillSchedule.findMatchingSchedule(
            workoutDuration: totalActDuration,
            detectedIterations: workActs.count,
            avgWorkDuration: avgWorkDur,
            avgRecoveryDuration: avgRecDur,
            candidateDrills: [.tempoSurges]
        ), wMean >= Double(baselineCadence) + 5.0 {
            return DrillPatternMatch(
                drillId: .tempoSurges,
                confidence: 0.95,
                detectedIntervalCount: workActs.count,
                avgWorkCadence: Int(round(wMean)),
                avgRecoveryCadence: Int(round(avgRecC)),
                signatureDescription: "Structured workout activities: \(workActs.count) tempo surge reps (\(sched.durationCategory.title)) at \(Int(round(wMean))) SPM."
            )
        }

        return nil
    }

    // MARK: - Tier 2: HKWorkoutEvent Lap/Segment Structural Extraction

    /// Inspects native lap/segment HKWorkoutEvents to match interval patterns.
    static func recognizeFromEvents(
        events: [HKWorkoutEvent],
        buckets: [BucketData],
        baselineCadence: Int
    ) -> DrillPatternMatch? {
        let intervalEvents = events.filter { $0.type == .lap || $0.type == .segment }
        guard intervalEvents.count >= 4 else { return nil }

        struct LapStats {
            let start: Date
            let end: Date
            let avgCadence: Double
            let duration: TimeInterval
        }

        var lapStats: [LapStats] = []
        for evt in intervalEvents {
            let start = evt.dateInterval.start
            let end = evt.dateInterval.end
            let lapBuckets = buckets.filter {
                $0.startTime >= start && $0.startTime < end
            }
            guard !lapBuckets.isEmpty else { continue }
            let avgC = lapBuckets.map(\.meanCadence).reduce(0, +) / Double(lapBuckets.count)
            lapStats.append(LapStats(start: start, end: end, avgCadence: avgC, duration: evt.dateInterval.duration))
        }

        guard lapStats.count >= 4 else { return nil }
        guard let minC = lapStats.map({ $0.avgCadence }).min(),
              let maxC = lapStats.map({ $0.avgCadence }).max(),
              (maxC - minC) >= 10.0 else {
            return nil
        }

        let threshold = (minC + maxC) / 2.0
        let workLaps = lapStats.filter { $0.avgCadence >= threshold }
        let recLaps = lapStats.filter { $0.avgCadence < threshold }

        guard workLaps.count >= 3 else { return nil }

        let workCadences = workLaps.map { $0.avgCadence }
        let wMean = workCadences.reduce(0, +) / Double(workCadences.count)
        let wVariance = workCadences.map { pow($0 - wMean, 2) }.reduce(0, +) / Double(workCadences.count)
        let wStd = sqrt(wVariance)
        let avgRecC = recLaps.isEmpty ? 0.0 : (recLaps.map { $0.avgCadence }.reduce(0, +) / Double(recLaps.count))

        let totalEvtDuration = lapStats.map(\.duration).reduce(0, +)
        let avgWorkDur = workLaps.map(\.duration).reduce(0, +) / Double(workLaps.count)
        let avgRecDur = recLaps.isEmpty ? 0.0 : (recLaps.map(\.duration).reduce(0, +) / Double(recLaps.count))

        // Check Pyramids
        let isMonotonicUp: Bool = {
            for i in 0..<(workCadences.count - 1) where (workCadences[i + 1] - workCadences[i]) < 2.0 {
                return false
            }
            return true
        }()
        let spread = (workCadences.max() ?? 0) - (workCadences.min() ?? 0)
        if let sched = DrillSchedule.findMatchingSchedule(
            workoutDuration: totalEvtDuration,
            detectedIterations: workLaps.count,
            avgWorkDuration: avgWorkDur,
            avgRecoveryDuration: avgRecDur,
            candidateDrills: [.cadencePyramids]
        ), isMonotonicUp && spread >= 5.0 {
            return DrillPatternMatch(
                drillId: .cadencePyramids,
                confidence: 0.94,
                detectedIntervalCount: workLaps.count,
                avgWorkCadence: Int(round(wMean)),
                avgRecoveryCadence: Int(round(avgRecC)),
                signatureDescription: "Event lap markers: \(workLaps.count) progressive cadence pyramid laps (\(sched.durationCategory.title))."
            )
        }

        // Check Rhythm Intervals
        if let sched = DrillSchedule.findMatchingSchedule(
            workoutDuration: totalEvtDuration,
            detectedIterations: workLaps.count,
            avgWorkDuration: avgWorkDur,
            avgRecoveryDuration: avgRecDur,
            candidateDrills: [.rhythmIntervals]
        ), wStd <= 3.8 {
            return DrillPatternMatch(
                drillId: .rhythmIntervals,
                confidence: 0.93,
                detectedIntervalCount: workLaps.count,
                avgWorkCadence: Int(round(wMean)),
                avgRecoveryCadence: Int(round(avgRecC)),
                signatureDescription: "Event lap markers: \(workLaps.count) steady rhythm interval laps (\(sched.durationCategory.title)) at \(Int(round(wMean))) SPM."
            )
        }

        return nil
    }

    // MARK: - Dynamic Zone Thresholds Extraction

    #if canImport(HealthKit)
    static func extractZoneThresholds(from config: Any) -> (zone1Max: Double?, zone2Max: Double?, zone4Min: Double?) {
        let bpmUnit = HKUnit(from: "count/min")
        var z1Max: Double?
        var z2Max: Double?
        var z4Min: Double?

        guard let configObj = config as? NSObject,
              let zones = configObj.value(forKey: "zones") as? [NSObject] else {
            return (nil, nil, nil)
        }

        for (idx, zone) in zones.enumerated() {
            let zoneIndex = (zone.value(forKey: "index") as? Int) ?? (idx + 1)
            let maxQty = zone.value(forKey: "maximum") as? HKQuantity
            let minQty = zone.value(forKey: "minimum") as? HKQuantity

            if zoneIndex == 1 || (zoneIndex == 0 && zones.count >= 5) {
                z1Max = maxQty?.doubleValue(for: bpmUnit)
            } else if zoneIndex == 2 || (zoneIndex == 1 && zones.count >= 5) {
                z2Max = maxQty?.doubleValue(for: bpmUnit)
            } else if zoneIndex == 4 || (zoneIndex == 3 && zones.count >= 5) {
                z4Min = minQty?.doubleValue(for: bpmUnit)
            }
        }

        // Fallback by array index if zone.index didn't explicitly match
        if z4Min == nil && zones.count >= 4 {
            let minQty = zones[3].value(forKey: "minimum") as? HKQuantity
            z4Min = minQty?.doubleValue(for: bpmUnit)
        }
        if z2Max == nil && zones.count >= 2 {
            let maxQty = zones[1].value(forKey: "maximum") as? HKQuantity
            z2Max = maxQty?.doubleValue(for: bpmUnit)
        }
        if z1Max == nil && !zones.isEmpty {
            let maxQty = zones[0].value(forKey: "maximum") as? HKQuantity
            z1Max = maxQty?.doubleValue(for: bpmUnit)
        }

        return (z1Max, z2Max, z4Min)
    }
    #endif
}
