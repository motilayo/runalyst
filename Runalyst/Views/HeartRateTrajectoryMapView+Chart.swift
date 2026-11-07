import SwiftUI
import Charts
import RunalystCore

struct HRPlotPoint: Identifiable {
    let id: String
    let minute: Double
    let heartRate: Double
    let kind: String
    let isAnchor: Bool
}

extension HeartRateTrajectoryMapView {
    var chartPoints: [HRPlotPoint] {
        var points: [HRPlotPoint] = []
        let validBuckets = buckets.filter { $0.meanHR >= 40.0 && $0.durationSeconds > 0 }
        let validSegments = normalizedSegments.filter { $0.avgHR >= 40.0 && $0.durationSeconds > 0 }
        let hasIntervalSegments = validSegments.contains { $0.kind == "work" || $0.kind == "recovery" }
        let validSplits = splits.filter { $0.avgHeartRate >= 40.0 && $0.durationSeconds > 0 }

        if validBuckets.count >= 2 {
            // Strategy 1: Authentic Bucketed Telemetry (Preserves interval oscillations and peak HR)
            let totalBucketSec = validBuckets.map(\.durationSeconds).reduce(0, +)
            let targetSec = workoutDuration ?? totalBucketSec
            let timeScale = (targetSec > totalBucketSec && totalBucketSec > 0 && abs(targetSec - totalBucketSec) > 60.0)
                ? (targetSec / totalBucketSec)
                : 1.0

            var elapsedSec = 0.0
            let firstHR = validBuckets[0].meanHR
            points.append(
                HRPlotPoint(
                    id: "bucket-warmup",
                    minute: 0.0,
                    heartRate: firstHR,
                    kind: "steady",
                    isAnchor: false
                )
            )

            for (idx, bucket) in validBuckets.enumerated() {
                let startSec = elapsedSec
                elapsedSec += bucket.durationSeconds
                let midMin = ((startSec + elapsedSec) / 2.0 * timeScale) / 60.0

                let isLocalPeak = (idx > 0 && idx < validBuckets.count - 1) &&
                    (bucket.meanHR >= validBuckets[idx - 1].meanHR && bucket.meanHR >= validBuckets[idx + 1].meanHR) &&
                    bucket.meanHR > effectiveThreshold
                let isLocalTrough = (idx > 0 && idx < validBuckets.count - 1) &&
                    (bucket.meanHR <= validBuckets[idx - 1].meanHR && bucket.meanHR <= validBuckets[idx + 1].meanHR)
                let isExtremum = isLocalPeak || isLocalTrough

                points.append(
                    HRPlotPoint(
                        id: "bucket-\(idx)",
                        minute: midMin,
                        heartRate: bucket.meanHR,
                        kind: isLocalPeak ? "work" : (isLocalTrough ? "recovery" : "steady"),
                        isAnchor: isExtremum
                    )
                )
            }

            let finalHR = validBuckets.last?.meanHR ?? effectiveWorkingHR
            points.append(
                HRPlotPoint(
                    id: "bucket-finish",
                    minute: maxMinutes,
                    heartRate: finalHR,
                    kind: "steady",
                    isAnchor: false
                )
            )
        } else if hasIntervalSegments || (validSegments.count >= 3 && validSplits.count < 2) {
            // Strategy 2: Multi-Segment Phase Structure (Intervals, Fartleks, Mixed Phases)
            let firstSegHR = validSegments[0].avgHR > 0 ? validSegments[0].avgHR : effectiveWorkingHR
            if let firstStart = validSegments.first?.startSeconds, firstStart > 30.0 {
                points.append(
                    HRPlotPoint(
                        id: "seg-start",
                        minute: 0.0,
                        heartRate: firstSegHR * 0.9,
                        kind: "steady",
                        isAnchor: false
                    )
                )
            }

            for (idx, seg) in validSegments.enumerated() {
                let hr = seg.avgHR > 0 ? seg.avgHR : effectiveWorkingHR
                let startMin = seg.startSeconds / 60.0
                let endMin = seg.endSeconds / 60.0
                let midMin = (seg.startSeconds + seg.endSeconds) / 120.0
                let durationMin = (seg.endSeconds - seg.startSeconds) / 60.0

                if durationMin > 4.0 {
                    points.append(HRPlotPoint(id: "\(idx)-s", minute: startMin + 0.5, heartRate: hr, kind: seg.kind, isAnchor: false))
                    points.append(HRPlotPoint(id: "\(idx)-m", minute: midMin, heartRate: hr, kind: seg.kind, isAnchor: true))
                    points.append(HRPlotPoint(id: "\(idx)-e", minute: endMin - 0.5, heartRate: hr, kind: seg.kind, isAnchor: false))
                } else {
                    points.append(HRPlotPoint(id: "\(idx)-m", minute: midMin, heartRate: hr, kind: seg.kind, isAnchor: true))
                }
            }

            let lastSegHR = validSegments.last?.avgHR ?? effectiveWorkingHR
            points.append(
                HRPlotPoint(
                    id: "seg-finish",
                    minute: maxMinutes,
                    heartRate: lastSegHR,
                    kind: "steady",
                    isAnchor: false
                )
            )
        } else if validSplits.count >= 2 {
            // Strategy 3: Authentic Splits Progression (Warmup, Splits, Drift)
            let totalSplitSec = validSplits.map(\.durationSeconds).reduce(0, +)
            let targetSec = workoutDuration ?? totalSplitSec
            let timeScale = (targetSec > totalSplitSec && totalSplitSec > 0 && abs(targetSec - totalSplitSec) > 60.0)
                ? (targetSec / totalSplitSec)
                : 1.0

            var elapsedSec = 0.0
            let firstSplitHR = validSplits[0].avgHeartRate
            // Warm-up ramp anchor at minute 0
            points.append(
                HRPlotPoint(
                    id: "split-warmup",
                    minute: 0.0,
                    heartRate: firstSplitHR * 0.88,
                    kind: "steady",
                    isAnchor: false
                )
            )

            for split in validSplits {
                let startSec = elapsedSec
                elapsedSec += split.durationSeconds
                let midMin = ((startSec + elapsedSec) / 2.0 * timeScale) / 60.0
                points.append(
                    HRPlotPoint(
                        id: "split-\(split.index)",
                        minute: midMin,
                        heartRate: split.avgHeartRate,
                        kind: "steady",
                        isAnchor: true
                    )
                )
            }

            // Final anchor at completion
            let finalHR = validSplits.last?.avgHeartRate ?? effectiveWorkingHR
            points.append(
                HRPlotPoint(
                    id: "split-finish",
                    minute: maxMinutes,
                    heartRate: finalHR * 1.01,
                    kind: "steady",
                    isAnchor: false
                )
            )
        } else {
            // Strategy 4: Continuous Steady Physiological Curve anchored to effectiveWorkingHR
            // Warmup rise (0-8m) -> Steady aerobic cruising -> Gentle late drift
            let targetHR = effectiveWorkingHR
            let mMax = maxMinutes

            let anchors: [(fraction: Double, hrMultiplier: Double, isAnchor: Bool)] = [
                (0.00, 0.82, false),
                (min(0.06, 3.0 / max(1.0, mMax)), 0.91, true),
                (min(0.15, 8.0 / max(1.0, mMax)), 0.97, true),
                (0.40, 0.99, true),
                (0.65, 1.01, true),
                (0.85, 1.03, true),
                (1.00, 1.05, false)
            ]

            for (idx, anchor) in anchors.enumerated() {
                let minVal = min(mMax, anchor.fraction * mMax)
                points.append(
                    HRPlotPoint(
                        id: "phys-\(idx)",
                        minute: minVal,
                        heartRate: targetHR * anchor.hrMultiplier,
                        kind: "steady",
                        isAnchor: anchor.isAnchor
                    )
                )
            }
        }

        // Defensive guarantee: Swift Charts requires at least 2 points to render AreaMark and LineMark
        if points.count < 2 {
            let hr = effectiveWorkingHR
            points = [
                HRPlotPoint(id: "start", minute: 0, heartRate: hr * 0.85, kind: "steady", isAnchor: false),
                HRPlotPoint(id: "mid", minute: maxMinutes / 2.0, heartRate: hr, kind: "steady", isAnchor: true),
                HRPlotPoint(id: "end", minute: maxMinutes, heartRate: hr * 1.03, kind: "steady", isAnchor: false)
            ]
        }

        return points.sorted(by: { $0.minute < $1.minute })
    }

    var yMin: Double {
        let pts = chartPoints.map(\.heartRate)
        let lowest = min(pts.min() ?? (effectiveWorkingHR - 20), effectiveThreshold - 20)
        return max(50, floor((lowest - 8) / 5) * 5)
    }

    var yMax: Double {
        let pts = chartPoints.map(\.heartRate)
        let highest = max(pts.max() ?? (effectiveWorkingHR + 20), effectiveThreshold + 12)
        return min(220, ceil((highest + 8) / 5) * 5)
    }

    var peakPoint: HRPlotPoint? {
        chartPoints.max(by: { $0.heartRate < $1.heartRate })
    }

    var scrubbedPoint: HRPlotPoint? {
        guard let minute = selectedMinute else { return nil }
        return chartPoints.min(by: { abs($0.minute - minute) < abs($1.minute - minute) })
    }

    var xAxisTicks: [Double] {
        let mMax = maxMinutes
        if mMax <= 15 {
            var ticks = Array(stride(from: 0.0, through: mMax, by: 5.0))
            if let last = ticks.last, (mMax - last) >= 2.0 {
                ticks.append(mMax)
            } else if ticks.count > 1 {
                ticks[ticks.count - 1] = mMax
            }
            return Array(Set(ticks)).sorted()
        } else if mMax <= 45 {
            var ticks = Array(stride(from: 0.0, to: mMax, by: 10.0))
            if let last = ticks.last, (mMax - last) >= 3.0 {
                ticks.append(mMax)
            } else if ticks.count > 1 {
                ticks[ticks.count - 1] = mMax
            } else {
                ticks.append(mMax)
            }
            return Array(Set(ticks)).sorted()
        } else {
            var ticks = Array(stride(from: 0.0, to: mMax, by: 15.0))
            if let last = ticks.last, (mMax - last) >= 5.0 {
                ticks.append(mMax)
            } else if ticks.count > 1 {
                ticks[ticks.count - 1] = mMax
            } else {
                ticks.append(mMax)
            }
            return Array(Set(ticks)).sorted()
        }
    }

    func interpolatedHR(at minute: Double) -> Double {
        guard !chartPoints.isEmpty else { return effectiveWorkingHR }
        if minute <= chartPoints[0].minute {
            return chartPoints[0].heartRate
        }
        if minute >= chartPoints[chartPoints.count - 1].minute {
            return chartPoints[chartPoints.count - 1].heartRate
        }
        for idx in 0..<(chartPoints.count - 1) {
            let p1 = chartPoints[idx]
            let p2 = chartPoints[idx + 1]
            if minute >= p1.minute && minute <= p2.minute {
                let range = p2.minute - p1.minute
                guard range > 0.001 else { return p1.heartRate }
                let progress = (minute - p1.minute) / range
                return p1.heartRate + progress * (p2.heartRate - p1.heartRate)
            }
        }
        return effectiveWorkingHR
    }

    func zoneLabel(for hr: Double) -> String {
        if hr <= zone1Ceiling {
            return "Zone 1 (Recovery)"
        } else if hr <= zone2Ceiling {
            return "Zone 2 (Aerobic)"
        } else if hr <= (zone2Ceiling + 12.0) {
            return "Zone 3 (Tempo)"
        } else {
            return "Zone 4+ (Threshold)"
        }
    }

    func zoneColor(for hr: Double) -> Color {
        if hr <= zone1Ceiling {
            return Color.teal
        } else if hr <= zone2Ceiling {
            return Color.green
        } else if hr <= (zone2Ceiling + 12.0) {
            return Color.orange
        } else {
            return Color.red
        }
    }

    var audioGraphDescriptor: HRWaveAudioGraphDescriptor {
        HRWaveAudioGraphDescriptor(
            points: chartPoints.map { ($0.minute, $0.heartRate) },
            title: isRecovery ? "Recovery Heart Rate Envelope" : "Heart Rate Trajectory",
            summary: "Heart rate trajectory spanning \(Int(maxMinutes)) minutes with working average of \(Int(round(effectiveWorkingHR))) BPM."
        )
    }
}
