import Foundation

// MARK: - Pattern Match Result

public struct DrillPatternMatchCore: Sendable, Equatable {
    public let drillIdentifier: String
    public let confidence: Double
    public let detectedIntervalCount: Int
    public let avgWorkCadence: Int
    public let avgRecoveryCadence: Int
    public let signatureDescription: String

    public init(
        drillIdentifier: String,
        confidence: Double,
        detectedIntervalCount: Int,
        avgWorkCadence: Int,
        avgRecoveryCadence: Int,
        signatureDescription: String
    ) {
        self.drillIdentifier = drillIdentifier
        self.confidence = confidence
        self.detectedIntervalCount = detectedIntervalCount
        self.avgWorkCadence = avgWorkCadence
        self.avgRecoveryCadence = avgRecoveryCadence
        self.signatureDescription = signatureDescription
    }
}

// MARK: - Drill Pattern Core

public enum DrillPatternCore {

    public static func recognizeDrill(
        buckets: [TelemetryBucket],
        baselineCadence: Int = 155,
        workoutDuration: Double,
        zone4Threshold: Double = 161.5,
        zone2Threshold: Double = 142.0,
        zone1Threshold: Double = 125.0
    ) -> DrillPatternMatchCore? {
        guard buckets.count >= 8 else { return nil }
        let active = buckets.filter { $0.cadenceSPM > 0 && $0.durationSeconds > 0 }
        guard active.count >= 8 else { return nil }

        let cadences = active.map(\.cadenceSPM)
        let meanCadence = cadences.reduce(0, +) / Double(cadences.count)
        let varianceCadence = cadences.map { pow($0 - meanCadence, 2) }.reduce(0, +) / Double(cadences.count)
        let stdCadence = sqrt(varianceCadence)
        let cadenceCV = meanCadence > 0 ? (stdCadence / meanCadence) : 0.0
        let refBaseline = baselineCadence > 0 ? Double(baselineCadence) : meanCadence

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

        guard cadenceCV >= 0.020 && stdCadence >= 2.5 else { return nil }

        var smoothedCadences: [Double] = []
        smoothedCadences.reserveCapacity(active.count)
        for i in 0..<active.count {
            let start = max(0, i - 1)
            let end = min(active.count, i + 2)
            let slice = active[start..<end]
            let avg = slice.map(\.cadenceSPM).reduce(0, +) / Double(slice.count)
            smoothedCadences.append(avg)
        }

        guard let rawMinC = cadences.min(), let rawMaxC = cadences.max(), (rawMaxC - rawMinC) >= 4.0 else {
            return nil
        }

        struct CandidateSegment {
            let isWork: Bool
            var duration: Double
            var buckets: [TelemetryBucket]
            var avgCadence: Double {
                buckets.isEmpty ? 0 : (buckets.map(\.cadenceSPM).reduce(0, +) / Double(buckets.count))
            }
            var maxCadence: Double {
                buckets.map(\.cadenceSPM).max() ?? 0
            }
        }

        func buildSegments(withThreshold threshold: Double) -> (workReps: [CandidateSegment], recReps: [CandidateSegment]) {
            var rawSegments: [CandidateSegment] = []
            var currentIsWork = smoothedCadences[0] >= threshold
            var currentBuckets: [TelemetryBucket] = [active[0]]

            for i in 1..<smoothedCadences.count {
                let isWork = smoothedCadences[i] >= threshold
                let curAvgCadence = currentBuckets.map(\.cadenceSPM).reduce(0, +) / Double(currentBuckets.count)
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
            return (work, rec)
        }

        let globalThreshold = (rawMinC + rawMaxC) / 2.0
        var (workReps, recReps) = buildSegments(withThreshold: globalThreshold)

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
                    let (pass2Work, pass2Rec) = buildSegments(withThreshold: floatThreshold)
                    if pass2Work.count >= 3 && pass2Rec.count >= 2 {
                        workReps = pass2Work
                        recReps = pass2Rec
                    }
                }
            }
        }

        guard workReps.count >= 3 && recReps.count >= 2 else { return nil }

        let totalWorkTime = workReps.map(\.duration).reduce(0, +)
        let totalRecTime = recReps.map(\.duration).reduce(0, +)
        guard (totalWorkTime + totalRecTime) > 0, (totalRecTime / (totalWorkTime + totalRecTime)) >= 0.15 else {
            return nil
        }

        // Strides detection
        let stridesCandidates = workReps.filter {
            $0.duration <= 45.0 && ($0.maxCadence >= 178.0 || $0.avgCadence >= refBaseline + 18.0)
        }
        if stridesCandidates.count >= 3 && Double(stridesCandidates.count) >= Double(workReps.count) * 0.70 {
            let avgRecC = recReps.isEmpty ? 0.0 : (recReps.map { $0.avgCadence }.reduce(0, +) / Double(recReps.count))
            let avgStridesC = stridesCandidates.map { $0.avgCadence }.reduce(0, +) / Double(stridesCandidates.count)
            let avgWorkDur = stridesCandidates.map(\.duration).reduce(0, +) / Double(stridesCandidates.count)
            let avgRecDur = recReps.isEmpty ? 0.0 : (recReps.map(\.duration).reduce(0, +) / Double(recReps.count))

            if let sched = DrillScheduleCore.findMatchingSchedule(
                workoutDuration: workoutDuration,
                detectedIterations: stridesCandidates.count,
                avgWorkDuration: avgWorkDur,
                avgRecoveryDuration: avgRecDur,
                candidateDrills: ["strides"]
            ), avgRecC <= 130.0 || (avgStridesC - avgRecC) >= 28.0 {
                return DrillPatternMatchCore(
                    drillIdentifier: "strides",
                    confidence: 0.95,
                    detectedIntervalCount: stridesCandidates.count,
                    avgWorkCadence: Int(round(avgStridesC)),
                    avgRecoveryCadence: Int(round(avgRecC)),
                    signatureDescription: "Detected \(stridesCandidates.count) explosive accelerations (\(sched.durationMinutes) min, avg \(Int(round(avgStridesC))) SPM) with walk/light recovery."
                )
            }
        }

        // Cadence Pyramids vs Rhythm Intervals
        let intervalWorkReps = workReps.filter { $0.duration >= 20.0 && $0.duration <= 130.0 }
        if intervalWorkReps.count >= 3 && recReps.count >= 2 {
            let workCadences = intervalWorkReps.map { $0.avgCadence }
            let wMean = workCadences.reduce(0, +) / Double(workCadences.count)
            let avgRecC = recReps.map { $0.avgCadence }.reduce(0, +) / Double(recReps.count)
            let contrast = wMean - avgRecC
            let avgWorkDur = intervalWorkReps.map(\.duration).reduce(0, +) / Double(intervalWorkReps.count)
            let avgRecDur = recReps.map(\.duration).reduce(0, +) / Double(recReps.count)

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

            if isMonotonicUp || isPyramid {
                if let sched = DrillScheduleCore.findMatchingSchedule(
                    workoutDuration: workoutDuration,
                    detectedIterations: intervalWorkReps.count,
                    avgWorkDuration: avgWorkDur,
                    avgRecoveryDuration: avgRecDur,
                    candidateDrills: ["cadence_pyramids"]
                ) {
                    let shape = isMonotonicUp ? "progressive step-up ladder" : "ascending and descending pyramid"
                    return DrillPatternMatchCore(
                        drillIdentifier: "cadence_pyramids",
                        confidence: 0.92,
                        detectedIntervalCount: intervalWorkReps.count,
                        avgWorkCadence: Int(round(wMean)),
                        avgRecoveryCadence: Int(round(avgRecC)),
                        signatureDescription: "Detected \(intervalWorkReps.count)-stage \(shape) (\(sched.durationMinutes) min, spread \(Int(round(cadenceSpread))) SPM, contrast +\(Int(round(contrast))) SPM)."
                    )
                }
            }

            let workVariance = workCadences.map { pow($0 - wMean, 2) }.reduce(0, +) / Double(workCadences.count)
            let workStd = sqrt(workVariance)
            if contrast >= 4.0 && workStd <= 7.0 {
                if let sched = DrillScheduleCore.findMatchingSchedule(
                    workoutDuration: workoutDuration,
                    detectedIterations: intervalWorkReps.count,
                    avgWorkDuration: avgWorkDur,
                    avgRecoveryDuration: avgRecDur,
                    candidateDrills: ["rhythm_intervals"]
                ) {
                    return DrillPatternMatchCore(
                        drillIdentifier: "rhythm_intervals",
                        confidence: 0.90,
                        detectedIntervalCount: intervalWorkReps.count,
                        avgWorkCadence: Int(round(wMean)),
                        avgRecoveryCadence: Int(round(avgRecC)),
                        signatureDescription: "Detected \(intervalWorkReps.count) rhythmic cadence repeats (\(sched.durationMinutes) min, target turnover \(Int(round(wMean))) SPM with +\(Int(round(contrast))) SPM contrast)."
                    )
                }
            }
        }
        return nil
    }

    private static func detectTempoSurges(
        buckets: [TelemetryBucket],
        refBaseline: Double,
        workoutDuration: Double,
        zone4Threshold: Double,
        zone2Threshold: Double
    ) -> DrillPatternMatchCore? {
        guard workoutDuration >= 360.0 else { return nil }

        var surgeRanges: [Range<Int>] = []
        var surgeStart: Int?

        for i in 0..<buckets.count {
            let b = buckets[i]
            let isSurge = b.heartRateBPM >= (zone4Threshold - 2.0) && b.cadenceSPM >= (refBaseline + 5.0)
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

        guard surgeRanges.count == 3 || surgeRanges.count == 4 else { return nil }

        let surgeDurations = surgeRanges.map { r in
            buckets[r].map(\.durationSeconds).reduce(0, +)
        }
        let avgWorkDuration = surgeDurations.reduce(0, +) / Double(surgeDurations.count)

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

        guard let matchingSchedule = DrillScheduleCore.findMatchingSchedule(
            workoutDuration: workoutDuration,
            detectedIterations: surgeRanges.count,
            avgWorkDuration: avgWorkDuration,
            avgRecoveryDuration: avgRecDuration,
            candidateDrills: ["tempo_surges"]
        ) else {
            return nil
        }

        var surgeIndices = Set<Int>()
        for r in surgeRanges {
            for idx in r { surgeIndices.insert(idx) }
        }
        let baseBuckets = (0..<buckets.count).filter { !surgeIndices.contains($0) && buckets[$0].cadenceSPM > 0 }.map { buckets[$0] }
        guard !baseBuckets.isEmpty else { return nil }

        let baseCadence = baseBuckets.map(\.cadenceSPM).reduce(0, +) / Double(baseBuckets.count)
        let validHRBase = baseBuckets.map(\.heartRateBPM).filter { $0 > 0 }
        let baseHR = validHRBase.isEmpty ? 0 : (validHRBase.reduce(0, +) / Double(validHRBase.count))

        let allSurgeBuckets = surgeIndices.map { buckets[$0] }
        let surgeCadence = allSurgeBuckets.map(\.cadenceSPM).reduce(0, +) / Double(allSurgeBuckets.count)
        let surgeTime = allSurgeBuckets.map(\.durationSeconds).reduce(0, +)

        guard baseCadence >= (refBaseline - 4.0),
              baseHR >= (zone2Threshold - 2.0),
              (surgeCadence - baseCadence) >= 7.0,
              (surgeTime / workoutDuration) <= 0.35 else {
            return nil
        }

        return DrillPatternMatchCore(
            drillIdentifier: "tempo_surges",
            confidence: 0.94,
            detectedIntervalCount: surgeRanges.count,
            avgWorkCadence: Int(round(surgeCadence)),
            avgRecoveryCadence: Int(round(baseCadence)),
            signatureDescription: "Detected continuous tempo run containing \(surgeRanges.count) threshold surges (\(matchingSchedule.durationMinutes) min, avg \(Int(round(surgeCadence))) SPM in Zone 4)."
        )
    }

    public struct SegmentStatsCore: Sendable, Equatable {
        public let avgCadence: Double
        public let avgHR: Double
        public let durationSeconds: Double

        public init(avgCadence: Double, avgHR: Double, durationSeconds: Double) {
            self.avgCadence = avgCadence
            self.avgHR = avgHR
            self.durationSeconds = durationSeconds
        }
    }

    public static func recognizeFromSegments(
        segments: [SegmentStatsCore],
        baselineCadence: Int,
        sourceLabel: String
    ) -> DrillPatternMatchCore? {
        guard segments.count >= 4 else { return nil }

        guard let minC = segments.map({ $0.avgCadence }).min(),
              let maxC = segments.map({ $0.avgCadence }).max(),
              (maxC - minC) >= 10.0 else {
            return nil
        }

        let threshold = (minC + maxC) / 2.0
        let workActs = segments.filter { $0.avgCadence >= threshold && $0.durationSeconds >= 15.0 }
        let recActs = segments.filter { $0.avgCadence < threshold }

        guard workActs.count >= 3 else { return nil }

        let workCadences = workActs.map { $0.avgCadence }
        let wMean = workCadences.reduce(0, +) / Double(workCadences.count)
        let wVariance = workCadences.map { pow($0 - wMean, 2) }.reduce(0, +) / Double(workCadences.count)
        let wStd = sqrt(wVariance)
        let avgRecC = recActs.isEmpty ? 0.0 : (recActs.map { $0.avgCadence }.reduce(0, +) / Double(recActs.count))

        let totalActDuration = segments.map(\.durationSeconds).reduce(0, +)
        let avgWorkDur = workActs.map(\.durationSeconds).reduce(0, +) / Double(workActs.count)
        let avgRecDur = recActs.isEmpty ? 0.0 : (recActs.map(\.durationSeconds).reduce(0, +) / Double(recActs.count))

        // Strides check
        if let sched = DrillScheduleCore.findMatchingSchedule(
            workoutDuration: totalActDuration,
            detectedIterations: workActs.count,
            avgWorkDuration: avgWorkDur,
            avgRecoveryDuration: avgRecDur,
            candidateDrills: ["strides"]
        ), workActs.allSatisfy({ $0.durationSeconds <= 45.0 }) && (wMean >= 174.0 || wMean >= Double(baselineCadence) + 16.0) {
            return DrillPatternMatchCore(
                drillIdentifier: "strides",
                confidence: 0.95,
                detectedIntervalCount: workActs.count,
                avgWorkCadence: Int(round(wMean)),
                avgRecoveryCadence: Int(round(avgRecC)),
                signatureDescription: "\(sourceLabel): \(workActs.count) short stride sprints (\(sched.durationMinutes) min) at \(Int(round(wMean))) SPM."
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
        if let sched = DrillScheduleCore.findMatchingSchedule(
            workoutDuration: totalActDuration,
            detectedIterations: workActs.count,
            avgWorkDuration: avgWorkDur,
            avgRecoveryDuration: avgRecDur,
            candidateDrills: ["cadence_pyramids"]
        ), isMonotonicUp && spread >= 5.0 {
            return DrillPatternMatchCore(
                drillIdentifier: "cadence_pyramids",
                confidence: 0.96,
                detectedIntervalCount: workActs.count,
                avgWorkCadence: Int(round(wMean)),
                avgRecoveryCadence: Int(round(avgRecC)),
                signatureDescription: "\(sourceLabel): \(workActs.count) progressive pyramid reps (\(sched.durationMinutes) min, \(Int(round(workCadences.min() ?? 0)))–\(Int(round(workCadences.max() ?? 0))) SPM)."
            )
        }

        // Rhythm intervals check
        if let sched = DrillScheduleCore.findMatchingSchedule(
            workoutDuration: totalActDuration,
            detectedIterations: workActs.count,
            avgWorkDuration: avgWorkDur,
            avgRecoveryDuration: avgRecDur,
            candidateDrills: ["rhythm_intervals"]
        ), wStd <= 3.8 {
            return DrillPatternMatchCore(
                drillIdentifier: "rhythm_intervals",
                confidence: 0.95,
                detectedIntervalCount: workActs.count,
                avgWorkCadence: Int(round(wMean)),
                avgRecoveryCadence: Int(round(avgRecC)),
                signatureDescription: "\(sourceLabel): \(workActs.count) steady rhythm intervals (\(sched.durationMinutes) min) at \(Int(round(wMean))) SPM."
            )
        }

        // Tempo surges check
        if let sched = DrillScheduleCore.findMatchingSchedule(
            workoutDuration: totalActDuration,
            detectedIterations: workActs.count,
            avgWorkDuration: avgWorkDur,
            avgRecoveryDuration: avgRecDur,
            candidateDrills: ["tempo_surges"]
        ), wMean >= Double(baselineCadence) + 5.0 {
            return DrillPatternMatchCore(
                drillIdentifier: "tempo_surges",
                confidence: 0.95,
                detectedIntervalCount: workActs.count,
                avgWorkCadence: Int(round(wMean)),
                avgRecoveryCadence: Int(round(avgRecC)),
                signatureDescription: "\(sourceLabel): \(workActs.count) tempo surge reps (\(sched.durationMinutes) min) at \(Int(round(wMean))) SPM."
            )
        }

        return nil
    }
}
