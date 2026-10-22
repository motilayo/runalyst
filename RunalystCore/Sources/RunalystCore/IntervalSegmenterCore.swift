import Foundation

// MARK: - Interval Segmenter Core

/// Pure, stateless sports science engine for multi-signal interval segmentation,
/// oscillation cycle corroboration, and progression detection.
public enum IntervalSegmenterCore {

    /// Smooths the cadence time series using a 2-bucket sliding window average.
    public static func smoothCadences(buckets: [TelemetryBucket]) -> [Double] {
        guard !buckets.isEmpty else { return [] }
        var smoothed: [Double] = []
        smoothed.reserveCapacity(buckets.count)
        for index in 0..<buckets.count {
            let start = max(0, index - 1)
            let end = min(buckets.count, index + 2)
            let slice = buckets[start..<end]
            let avg = slice.map(\.cadenceSPM).reduce(0, +) / Double(slice.count)
            smoothed.append(avg)
        }
        return smoothed
    }

    /// Extracts corroborated surge-and-recovery oscillation cycles from telemetry buckets.
    /// Employs a centered rolling local baseline window of 20 buckets with sub-20s phase debouncing.
    public static func extractOscillationCycles(
        buckets: [TelemetryBucket],
        windowSize: Int = 20
    ) -> [IntervalOscillationCycle] {
        guard buckets.count >= 4 else { return [] }

        let smoothed = smoothCadences(buckets: buckets)

        struct CandidatePhase {
            let isSurge: Bool
            var duration: Double
            var buckets: [TelemetryBucket]
            var avgCadence: Double { buckets.isEmpty ? 0 : (buckets.map(\.cadenceSPM).reduce(0, +) / Double(buckets.count)) }
            var avgPace: Double { buckets.isEmpty ? 0 : (buckets.map(\.paceSecondsPerKm).reduce(0, +) / Double(buckets.count)) }
            var avgHR: Double {
                let valid = buckets.map(\.heartRateBPM).filter { $0 > 0 }
                return valid.isEmpty ? 0 : (valid.reduce(0, +) / Double(valid.count))
            }
        }

        var phases: [CandidatePhase] = []
        var currentIsSurge = false
        var currentBuckets: [TelemetryBucket] = []

        for index in 0..<buckets.count {
            let halfWindow = windowSize / 2
            let windowStart = max(0, index - halfWindow)
            let windowEnd = min(buckets.count - 1, index + halfWindow)
            let window = buckets[windowStart...windowEnd]
            let localMeanCadence = window.map(\.cadenceSPM).reduce(0, +) / Double(window.count)
            let isSurge = smoothed[index] >= localMeanCadence

            if index == 0 {
                currentIsSurge = isSurge
                currentBuckets.append(buckets[index])
            } else if isSurge == currentIsSurge {
                currentBuckets.append(buckets[index])
            } else {
                let dur = currentBuckets.map(\.durationSeconds).reduce(0, +)
                phases.append(CandidatePhase(isSurge: currentIsSurge, duration: dur, buckets: currentBuckets))
                currentIsSurge = isSurge
                currentBuckets = [buckets[index]]
            }
        }
        if !currentBuckets.isEmpty {
            let dur = currentBuckets.map(\.durationSeconds).reduce(0, +)
            phases.append(CandidatePhase(isSurge: currentIsSurge, duration: dur, buckets: currentBuckets))
        }

        // Sub-20s phase debouncing: merge brief flutter (< 20s) into surrounding contiguous phase
        var debouncedPhases: [CandidatePhase] = []
        for phase in phases {
            if let last = debouncedPhases.last, last.isSurge == phase.isSurge {
                debouncedPhases[debouncedPhases.count - 1].buckets.append(contentsOf: phase.buckets)
                debouncedPhases[debouncedPhases.count - 1].duration += phase.duration
            } else if debouncedPhases.count >= 2,
                      let prev = debouncedPhases.last,
                      prev.isSurge != phase.isSurge,
                      prev.duration < 20.0,
                      debouncedPhases[debouncedPhases.count - 2].isSurge == phase.isSurge {
                let glitch = debouncedPhases.removeLast()
                debouncedPhases[debouncedPhases.count - 1].buckets.append(contentsOf: glitch.buckets)
                debouncedPhases[debouncedPhases.count - 1].buckets.append(contentsOf: phase.buckets)
                debouncedPhases[debouncedPhases.count - 1].duration += (glitch.duration + phase.duration)
            } else {
                debouncedPhases.append(phase)
            }
        }
        phases = debouncedPhases

        var cycles: [IntervalOscillationCycle] = []
        var usedRecoveryIndices: Set<Int> = []

        for index in 0..<phases.count where phases[index].isSurge {
            let surge = phases[index]

            var recoveryIndex: Int?
            if index + 1 < phases.count,
               !phases[index + 1].isSurge,
               !usedRecoveryIndices.contains(index + 1),
               phases[index + 1].duration >= 20.0,
               phases[index + 1].avgPace > surge.avgPace + 5.0 {
                recoveryIndex = index + 1
            } else if index > 0 && !phases[index - 1].isSurge && !usedRecoveryIndices.contains(index - 1) {
                recoveryIndex = index - 1
            } else if index > 0 && !phases[index - 1].isSurge {
                // Terminal surge fallback: allow pairing with immediate preceding recovery
                recoveryIndex = index - 1
            }

            guard let recIdx = recoveryIndex else { continue }
            let recovery = phases[recIdx]

            // Minimum duration guards: Surge >= 15s, Recovery >= 20s
            guard surge.duration >= 15.0, recovery.duration >= 20.0 else { continue }

            // Multi-signal corroboration:
            // 1. Cadence: Surge >= Recovery + 5 SPM
            let cadenceDiff = surge.avgCadence - recovery.avgCadence
            let cadenceCorroborated = cadenceDiff >= 5.0

            // 2. Pace: Surge >= 15 s/km faster than Recovery
            let paceDiff = recovery.avgPace - surge.avgPace
            let paceCorroborated = paceDiff >= 15.0

            // 3. Heart Rate: Surge >= Recovery + 3 BPM
            let hrDiff = (surge.avgHR > 0 && recovery.avgHR > 0) ? (surge.avgHR - recovery.avgHR) : 0.0
            let hrCorroborated = hrDiff >= 3.0

            let corroborationScore = (cadenceCorroborated ? 1 : 0) + (paceCorroborated ? 1 : 0) + (hrCorroborated ? 1 : 0)

            // Dominant Pace Surge: >= 30 s/km with biometric signal, or >= 45 s/km pure pace surge
            let isDominantPaceSurge = (paceDiff >= 30.0 && (cadenceDiff >= 3.0 || hrDiff >= 2.0)) || (paceDiff >= 45.0)

            // Valid interval cycle requires either:
            // 1. Dominant pace surge (>= 30-45 s/km)
            // 2. Corroborated biometric & velocity surge (corroborationScore >= 2 AND paceDiff >= 5.0 s/km)
            let isCorroboratedCycle = (corroborationScore >= 2 && paceDiff >= 5.0) || isDominantPaceSurge

            if isCorroboratedCycle {
                usedRecoveryIndices.insert(recIdx)
                cycles.append(IntervalOscillationCycle(
                    workDurationSeconds: surge.duration,
                    recoveryDurationSeconds: recovery.duration,
                    workCadenceSPM: surge.avgCadence,
                    recoveryCadenceSPM: recovery.avgCadence,
                    workPaceSecondsPerKm: surge.avgPace,
                    recoveryPaceSecondsPerKm: recovery.avgPace,
                    workHeartRateBPM: surge.avgHR,
                    recoveryHeartRateBPM: recovery.avgHR,
                    isCorroborated: true,
                    isDominantPaceSurge: isDominantPaceSurge,
                    corroborationScore: corroborationScore
                ))
            }
        }

        return cycles
    }

    /// Evaluates the regularity of work and recovery durations across validated oscillation cycles.
    /// Returns 0.0 to 1.0 (higher = more metronomic/regular).
    public static func calculateCycleRegularity(cycles: [IntervalOscillationCycle]) -> Double {
        guard cycles.count >= 2 else { return 0.0 }
        let workDurations = cycles.map(\.workDurationSeconds)
        let recDurations = cycles.map(\.recoveryDurationSeconds)

        let meanWork = workDurations.reduce(0, +) / Double(workDurations.count)
        let meanRec = recDurations.reduce(0, +) / Double(recDurations.count)

        guard meanWork > 0, meanRec > 0 else { return 0.0 }

        let workVariance = workDurations.map { pow($0 - meanWork, 2) }.reduce(0, +) / Double(workDurations.count)
        let workCV = sqrt(workVariance) / meanWork

        let recVariance = recDurations.map { pow($0 - meanRec, 2) }.reduce(0, +) / Double(recDurations.count)
        let recCV = sqrt(recVariance) / meanRec

        let score = 1.0 - ((workCV + recCV) / 2.0)
        return max(0.0, min(1.0, score))
    }

    /// Evaluates whether the run exhibits monotonic quintile progression (accelerating pace across the run).
    public static func evaluateQuintileProgression(buckets: [TelemetryBucket]) -> Bool {
        guard buckets.count >= 5 else { return false }
        let quintileSize = buckets.count / 5
        var quintilePaces: [Double] = []
        for index in 0..<5 {
            let start = index * quintileSize
            let end = (index == 4) ? buckets.count : (index + 1) * quintileSize
            let slice = buckets[start..<end]
            guard !slice.isEmpty else { return false }
            let avgPace = slice.map(\.paceSecondsPerKm).reduce(0, +) / Double(slice.count)
            quintilePaces.append(avgPace)
        }

        var fasterTransitions = 0
        var slowerTransitions = 0
        for index in 0..<4 {
            if quintilePaces[index + 1] < quintilePaces[index] - 2.0 {
                fasterTransitions += 1
            } else if quintilePaces[index + 1] > quintilePaces[index] + 2.0 {
                slowerTransitions += 1
            }
        }

        let minPace = quintilePaces.min() ?? Double.infinity
        let q5IsFastest = (quintilePaces[4] <= minPace + 0.5)

        return fasterTransitions >= 3 && slowerTransitions == 0 && q5IsFastest
    }

    /// Segments continuous telemetry buckets into Work, Recovery, Steady, or Walking windows.
    public static func segmentPhases(
        buckets: [TelemetryBucket],
        cadenceFloor: Double = 150.0
    ) -> [IntervalPhaseSegment] {
        guard !buckets.isEmpty else { return [] }

        let moving = buckets.filter { $0.cadenceSPM >= 135.0 }
        let activeBuckets = buckets.filter { $0.cadenceSPM >= 60.0 }
        let cadPool = (moving.count >= buckets.count / 3) ? moving : (activeBuckets.isEmpty ? buckets : activeBuckets)
        let allCads = cadPool.map(\.cadenceSPM).sorted()
        let cadP20 = allCads[allCads.count / 5]
        let cadP90 = allCads[min(allCads.count - 1, (allCads.count * 9) / 10)]
        let hasCadenceSurges = (cadP90 - cadP20) >= 14.0
        let movingCads = moving.map(\.cadenceSPM).sorted()
        let medCad = movingCads.isEmpty ? (allCads.isEmpty ? 160.0 : allCads[allCads.count / 2]) : movingCads[movingCads.count / 2]
        let validPaces = moving.map(\.paceSecondsPerKm).filter { $0 > 0 }.sorted()
        let medPace = validPaces.isEmpty ? 300.0 : validPaces[validPaces.count / 2]
        let p20 = validPaces.isEmpty ? medPace : validPaces[validPaces.count / 5]
        let paceCV = FramboiseCore.calculatePaceCV(bucketPaces: validPaces)
        let hasLargePaceRange = (medPace - p20) >= 30.0

        let isUniformSteady = paceCV < 0.10 && (medPace - p20) < 20.0 && !hasCadenceSurges
        let surgePaceThreshold = hasLargePaceRange ? min(medPace - 30.0, p20 + 20.0) : (medPace - 20.0)

        var raw: [IntervalPhaseSegment] = []
        var curKind: IntervalPhaseKind?
        var segStart: Double = 0
        var pSum = 0.0, cSum = 0.0, hrSum = 0.0, count = 0.0, hrCount = 0.0, elapsed = 0.0

        for (index, b) in buckets.enumerated() {
            let windowSize = 20
            let windowStart = max(0, index - windowSize / 2)
            let windowEnd = min(buckets.count - 1, index + windowSize / 2)
            let rawWindow = buckets[windowStart...windowEnd]
            let localWindow = hasCadenceSurges ? Array(rawWindow.filter { $0.cadenceSPM >= 60.0 }) : rawWindow.filter { $0.cadenceSPM >= 135.0 }

            let localMedCad: Double = {
                guard !localWindow.isEmpty else { return medCad }
                let sorted = localWindow.map(\.cadenceSPM).sorted()
                return sorted[sorted.count / 2]
            }()
            let localPaces = localWindow.map(\.paceSecondsPerKm).filter { $0 > 0 }.sorted()
            let localMedPace: Double = {
                guard !localPaces.isEmpty else { return medPace }
                return localPaces[localPaces.count / 2]
            }()

            let isSurge = !isUniformSteady && (
                (b.paceSecondsPerKm > 0 && b.paceSecondsPerKm <= (localMedPace - 15.0) && b.cadenceSPM >= localMedCad - 1.0)
                || (b.cadenceSPM >= (localMedCad + 2.0) && b.paceSecondsPerKm > 0 && b.paceSecondsPerKm <= localMedPace)
                || (b.paceSecondsPerKm > 0 && b.paceSecondsPerKm <= surgePaceThreshold && b.cadenceSPM >= cadenceFloor)
                || (hasCadenceSurges && b.cadenceSPM >= localMedCad + 6.0 && b.cadenceSPM >= cadenceFloor && (b.paceSecondsPerKm <= 0 || b.paceSecondsPerKm <= localMedPace + 5.0))
            )

            let isRec = !isUniformSteady && (
                b.paceSecondsPerKm >= (localMedPace + 15.0)
                || (b.cadenceSPM <= localMedCad - 2.0)
                || (b.cadenceSPM < cadenceFloor)
                || (hasCadenceSurges && b.cadenceSPM <= localMedCad - 6.0)
            )

            let kind: IntervalPhaseKind
            if isSurge {
                kind = .work
            } else if isRec {
                kind = .recovery
            } else if b.cadenceSPM < cadenceFloor && b.cadenceSPM < 135.0 {
                kind = .walking
            } else {
                kind = .steady
            }

            if curKind == nil {
                curKind = kind
                segStart = elapsed
            } else if curKind != kind, let activeKind = curKind {
                let pace = count > 0 ? pSum / count : 0
                let cad = count > 0 ? cSum / count : 0
                let hr = hrCount > 0 ? hrSum / hrCount : 0
                raw.append(IntervalPhaseSegment(startSeconds: segStart, endSeconds: elapsed, kind: activeKind, avgPaceSecondsPerKm: pace, avgCadenceSPM: cad, avgHeartRateBPM: hr))
                curKind = kind
                segStart = elapsed
                pSum = 0; cSum = 0; hrSum = 0; count = 0; hrCount = 0
            }

            pSum += b.paceSecondsPerKm
            cSum += b.cadenceSPM
            if b.heartRateBPM >= 40.0 {
                hrSum += b.heartRateBPM
                hrCount += 1.0
            }
            count += 1.0
            elapsed += b.durationSeconds
        }

        if let activeKind = curKind, elapsed > segStart {
            let pace = count > 0 ? pSum / count : 0
            let cad = count > 0 ? cSum / count : 0
            let hr = hrCount > 0 ? hrSum / hrCount : 0
            raw.append(IntervalPhaseSegment(startSeconds: segStart, endSeconds: elapsed, kind: activeKind, avgPaceSecondsPerKm: pace, avgCadenceSPM: cad, avgHeartRateBPM: hr))
        }

        var consolidated = consolidatePhaseSegments(raw)

        // Minimum Repetition Gate: workRepCount >= 2 required for intervals
        let workSegmentsCount = consolidated.filter { $0.kind == .work }.count
        if workSegmentsCount < 2 {
            consolidated = consolidated.map { seg in
                (seg.kind == .work || seg.kind == .recovery)
                    ? IntervalPhaseSegment(startSeconds: seg.startSeconds, endSeconds: seg.endSeconds, kind: .steady, avgPaceSecondsPerKm: seg.avgPaceSecondsPerKm, avgCadenceSPM: seg.avgCadenceSPM, avgHeartRateBPM: seg.avgHeartRateBPM)
                    : seg
            }

            var coalesced: [IntervalPhaseSegment] = []
            for seg in consolidated {
                if let last = coalesced.last, last.kind == seg.kind {
                    coalesced[coalesced.count - 1] = mergeSegments(last, seg)
                } else {
                    coalesced.append(seg)
                }
            }
            consolidated = coalesced
        }

        return consolidated
    }

    /// Merges fragmented work segments separated by brief dips and filters out stray warmup/cooldown surges.
    public static func consolidatePhaseSegments(_ segments: [IntervalPhaseSegment]) -> [IntervalPhaseSegment] {
        guard !segments.isEmpty else { return [] }

        // Step 1: Gap bridging: merge work segments separated by brief momentary flutter (<= 15s)
        // or steady compound transitions (<= 65s steady, pace < 400 s/km, cadence >= 156 SPM)
        var bridged: [IntervalPhaseSegment] = []
        for seg in segments {
            if let last = bridged.last, last.kind == .work && seg.kind == .work {
                bridged[bridged.count - 1] = mergeSegments(last, seg)
            } else if bridged.count >= 2,
                      seg.kind == .work,
                      let gap = bridged.last,
                      gap.kind != .work,
                      gap.durationSeconds <= 15.0 || (gap.kind == .steady && gap.durationSeconds <= 65.0 && gap.avgPaceSecondsPerKm < 400.0 && gap.avgCadenceSPM >= 156.0),
                      bridged[bridged.count - 2].kind == .work {
                _ = bridged.removeLast()
                let prev = bridged.removeLast()
                bridged.append(mergeSegments(prev, seg))
            } else {
                bridged.append(seg)
            }
        }

        // Step 2: Outlier rejection: remove stray pickups vastly slower or shorter than true work reps
        let workPaces = bridged.filter { $0.kind == .work && $0.avgPaceSecondsPerKm > 0 }.map(\.avgPaceSecondsPerKm).sorted()
        var filtered = bridged
        if workPaces.count >= 4 {
            let medWork = workPaces[workPaces.count / 2]
            filtered = bridged.map { seg in
                guard seg.kind == .work else { return seg }
                let isVastlySlower = (seg.avgPaceSecondsPerKm > medWork + 45.0 && seg.avgCadenceSPM < 162.0)
                let isMicroGlitch = seg.durationSeconds <= 20.0 && seg.avgPaceSecondsPerKm > medWork + 20.0
                let isTooBrief = seg.durationSeconds < 14.0
                if isVastlySlower || isMicroGlitch || isTooBrief {
                    return IntervalPhaseSegment(startSeconds: seg.startSeconds, endSeconds: seg.endSeconds, kind: .steady, avgPaceSecondsPerKm: seg.avgPaceSecondsPerKm, avgCadenceSPM: seg.avgCadenceSPM, avgHeartRateBPM: seg.avgHeartRateBPM)
                }
                return seg
            }
        }

        // Step 3: Isolated Warmup / Cooldown Strides (separated by >= 240s-300s from clustered work set)
        let workIdxs = filtered.enumerated().filter { $0.element.kind == .work }.map(\.offset)
        if workIdxs.count >= 4 {
            let workDurs = workIdxs.map { filtered[$0].durationSeconds }
            let medWorkDur = workDurs.sorted()[workDurs.count / 2]

            let firstWork = workIdxs[0], secondWork = workIdxs[1]
            let gapBeforeSet = filtered[secondWork].startSeconds - filtered[firstWork].endSeconds
            var gaps: [Double] = []
            for i in 1..<(workIdxs.count - 1) {
                gaps.append(filtered[workIdxs[i + 1]].startSeconds - filtered[workIdxs[i]].endSeconds)
            }
            let medGap = gaps.isEmpty ? 90.0 : gaps.sorted()[gaps.count / 2]
            if gapBeforeSet >= 240.0 && medGap <= 150.0 && filtered[firstWork].durationSeconds <= medWorkDur * 0.65 {
                let w = filtered[firstWork]
                filtered[firstWork] = IntervalPhaseSegment(startSeconds: w.startSeconds, endSeconds: w.endSeconds, kind: .steady, avgPaceSecondsPerKm: w.avgPaceSecondsPerKm, avgCadenceSPM: w.avgCadenceSPM, avgHeartRateBPM: w.avgHeartRateBPM)
            }
            let lastWork = workIdxs[workIdxs.count - 1], penWork = workIdxs[workIdxs.count - 2]
            let gapAfterSet = filtered[lastWork].startSeconds - filtered[penWork].endSeconds
            if gapAfterSet >= 300.0 && medGap <= 150.0 && filtered[lastWork].durationSeconds <= medWorkDur * 0.65 {
                let w = filtered[lastWork]
                filtered[lastWork] = IntervalPhaseSegment(startSeconds: w.startSeconds, endSeconds: w.endSeconds, kind: .steady, avgPaceSecondsPerKm: w.avgPaceSecondsPerKm, avgCadenceSPM: w.avgCadenceSPM, avgHeartRateBPM: w.avgHeartRateBPM)
            }
        }

        // Step 4: Speed & cadence contrast validation between candidate work and recovery
        let candidateWorks = filtered.filter { $0.kind == .work && $0.avgPaceSecondsPerKm > 0 }
        let candidateRecs = filtered.filter { $0.kind == .recovery && $0.avgPaceSecondsPerKm > 0 }
        if !candidateWorks.isEmpty && !candidateRecs.isEmpty {
            let avgWorkPace = candidateWorks.map(\.avgPaceSecondsPerKm).reduce(0, +) / Double(candidateWorks.count)
            let avgRecPace = candidateRecs.map(\.avgPaceSecondsPerKm).reduce(0, +) / Double(candidateRecs.count)
            let avgWorkCad = candidateWorks.map(\.avgCadenceSPM).reduce(0, +) / Double(candidateWorks.count)
            let avgRecCad = candidateRecs.map(\.avgCadenceSPM).reduce(0, +) / Double(candidateRecs.count)
            let contrast = avgRecPace - avgWorkPace
            let cadContrast = avgWorkCad - avgRecCad
            if contrast < 20.0 && cadContrast < 14.0 {
                filtered = filtered.map { seg in
                    (seg.kind == .work || seg.kind == .recovery)
                        ? IntervalPhaseSegment(startSeconds: seg.startSeconds, endSeconds: seg.endSeconds, kind: .steady, avgPaceSecondsPerKm: seg.avgPaceSecondsPerKm, avgCadenceSPM: seg.avgCadenceSPM, avgHeartRateBPM: seg.avgHeartRateBPM)
                        : seg
                }
            }
        }

        // Step 5: Coalesce adjacent identical kinds
        var finalSegments: [IntervalPhaseSegment] = []
        for seg in filtered {
            if let last = finalSegments.last, last.kind == seg.kind {
                finalSegments[finalSegments.count - 1] = mergeSegments(last, seg)
            } else {
                finalSegments.append(seg)
            }
        }

        return finalSegments
    }

    public static func mergeSegments(_ a: IntervalPhaseSegment, _ b: IntervalPhaseSegment) -> IntervalPhaseSegment {
        let durA = a.durationSeconds
        let durB = b.durationSeconds
        let activeDur = durA + durB
        let hrDurA = a.avgHeartRateBPM > 0 ? durA : 0.0
        let hrDurB = b.avgHeartRateBPM > 0 ? durB : 0.0
        let totalHRDur = hrDurA + hrDurB
        let mergedHR = totalHRDur > 0 ? (a.avgHeartRateBPM * hrDurA + b.avgHeartRateBPM * hrDurB) / totalHRDur : (a.avgHeartRateBPM > 0 ? a.avgHeartRateBPM : b.avgHeartRateBPM)

        return IntervalPhaseSegment(
            startSeconds: a.startSeconds,
            endSeconds: b.endSeconds,
            kind: a.kind,
            avgPaceSecondsPerKm: activeDur > 0 ? (a.avgPaceSecondsPerKm * durA + b.avgPaceSecondsPerKm * durB) / activeDur : a.avgPaceSecondsPerKm,
            avgCadenceSPM: activeDur > 0 ? (a.avgCadenceSPM * durA + b.avgCadenceSPM * durB) / activeDur : a.avgCadenceSPM,
            avgHeartRateBPM: mergedHR
        )
    }

    /// Evaluates continuous telemetry and generates a comprehensive interval segmentation report.
    public static func segment(
        buckets: [TelemetryBucket],
        cadenceFloor: Double = 150.0
    ) -> IntervalSegmentationReport {
        let phases = segmentPhases(buckets: buckets, cadenceFloor: cadenceFloor)
        let cycles = extractOscillationCycles(buckets: buckets)
        let regularity = calculateCycleRegularity(cycles: cycles)
        let workReps = phases.filter { $0.kind == .work }.count

        let validPaces = buckets.map(\.paceSecondsPerKm).filter { $0 > 0 }
        let cv = FramboiseCore.calculatePaceCV(bucketPaces: validPaces)
        let isUniformSteady = cv < 0.10
        let totalDurationMinutes = buckets.map(\.durationSeconds).reduce(0, +) / 60.0

        let isProgression = totalDurationMinutes >= 20.0 && cv < 0.11 && evaluateQuintileProgression(buckets: buckets)

        let avgCycleContrast = cycles.isEmpty ? 0.0 : (cycles.map { $0.recoveryPaceSecondsPerKm - $0.workPaceSecondsPerKm }.reduce(0, +) / Double(cycles.count))

        let isIntermittent = !isProgression && avgCycleContrast >= 25.0 && (cycles.count >= 3 || (cycles.count == 2 && cv >= 0.12 && !isUniformSteady))

        return IntervalSegmentationReport(
            phases: phases,
            cycles: cycles,
            workRepsCount: workReps,
            cycleRegularityScore: regularity,
            isMonotonicProgression: isProgression,
            isIntermittentWorkout: isIntermittent
        )
    }
}
