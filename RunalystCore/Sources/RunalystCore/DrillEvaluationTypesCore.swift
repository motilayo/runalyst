import Foundation

// MARK: - Drill Adherence Tier

public enum DrillAdherenceTierCore: String, Sendable, Codable, Equatable {
    case exceeded
    case met
    case partiallyMet
    case notMet
}

// MARK: - Drill Interval Rep

public struct DrillIntervalRepCore: Sendable, Codable, Equatable {
    public let repIndex: Int
    public let workCadence: Int
    public let workHeartRate: Int
    public let recoveryCadence: Int
    public let recoveryHeartRate: Int
    public let isMet: Bool
    public var durationSeconds: Double?
    public var workPaceSecondsPerKm: Double?
    public var recoveryPaceSecondsPerKm: Double?

    public var recoveryHeartRateDrop: Int? {
        guard workHeartRate > 0, recoveryHeartRate > 0 else { return nil }
        return workHeartRate - recoveryHeartRate
    }

    public init(
        repIndex: Int,
        workCadence: Int,
        workHeartRate: Int,
        recoveryCadence: Int,
        recoveryHeartRate: Int,
        isMet: Bool,
        durationSeconds: Double? = nil,
        workPaceSecondsPerKm: Double? = nil,
        recoveryPaceSecondsPerKm: Double? = nil
    ) {
        self.repIndex = repIndex
        self.workCadence = workCadence
        self.workHeartRate = workHeartRate
        self.recoveryCadence = recoveryCadence
        self.recoveryHeartRate = recoveryHeartRate
        self.isMet = isMet
        self.durationSeconds = durationSeconds
        self.workPaceSecondsPerKm = workPaceSecondsPerKm
        self.recoveryPaceSecondsPerKm = recoveryPaceSecondsPerKm
    }
}

// MARK: - Drill Interval Summary

public struct DrillIntervalSummaryCore: Sendable, Codable, Equatable {
    public let drillIdentifier: String
    public let intervalsMet: Int
    public let totalIntervals: Int
    public let workCadenceAvg: Int
    public let recoveryCadenceAvg: Int
    public let reps: [DrillIntervalRepCore]
    public let tier: DrillAdherenceTierCore
    public let verdict: String

    public var adherencePercentage: Int {
        guard totalIntervals > 0 else { return 0 }
        return Int(round(Double(intervalsMet) / Double(totalIntervals) * 100.0))
    }

    public var framboiseTags: [String] {
        var tags: [String] = []
        tags.append("drillIntervals:\(intervalsMet)/\(totalIntervals)")
        tags.append("drillWorkCadence:\(workCadenceAvg)")
        tags.append("drillRecCadence:\(recoveryCadenceAvg)")
        let repBits = reps.map { $0.isMet ? "1" : "0" }.joined(separator: ",")
        tags.append("drillReps:\(repBits)")

        let hasRichReps = reps.contains { $0.durationSeconds != nil || $0.workPaceSecondsPerKm != nil || $0.workHeartRate > 0 }
        if hasRichReps {
            let details = reps.map { rep in
                let wCad = rep.workCadence
                let wHR = rep.workHeartRate
                let wPace = rep.workPaceSecondsPerKm.map { String(format: "%.1f", $0) } ?? ""
                let dur = rep.durationSeconds.map { String(format: "%.0f", $0) } ?? ""
                let rCad = rep.recoveryCadence
                let rHR = rep.recoveryHeartRate
                let rPace = rep.recoveryPaceSecondsPerKm.map { String(format: "%.1f", $0) } ?? ""
                let metBit = rep.isMet ? "1" : "0"
                return "\(rep.repIndex):\(wCad):\(wHR):\(wPace):\(dur):\(rCad):\(rHR):\(rPace):\(metBit)"
            }.joined(separator: ";")
            tags.append("drillRepDetails:\(details)")
        }
        return tags
    }

    public init(
        drillIdentifier: String,
        intervalsMet: Int,
        totalIntervals: Int,
        workCadenceAvg: Int,
        recoveryCadenceAvg: Int,
        reps: [DrillIntervalRepCore],
        tier: DrillAdherenceTierCore,
        verdict: String
    ) {
        self.drillIdentifier = drillIdentifier
        self.intervalsMet = intervalsMet
        self.totalIntervals = totalIntervals
        self.workCadenceAvg = workCadenceAvg
        self.recoveryCadenceAvg = recoveryCadenceAvg
        self.reps = reps
        self.tier = tier
        self.verdict = verdict
    }

    public static func from(tags: [String], drillIdentifier: String) -> DrillIntervalSummaryCore? {
        guard let intervalTag = tags.first(where: { $0.hasPrefix("drillIntervals:") }) else { return nil }
        let rawCounts = intervalTag.replacingOccurrences(of: "drillIntervals:", with: "").split(separator: "/")
        guard rawCounts.count == 2,
              let met = Int(rawCounts[0]),
              let total = Int(rawCounts[1]) else { return nil }

        let workCadence = tags.first(where: { $0.hasPrefix("drillWorkCadence:") })
            .flatMap { Int($0.replacingOccurrences(of: "drillWorkCadence:", with: "")) } ?? 0
        let recCadence = tags.first(where: { $0.hasPrefix("drillRecCadence:") })
            .flatMap { Int($0.replacingOccurrences(of: "drillRecCadence:", with: "")) } ?? 0

        var reps: [DrillIntervalRepCore] = []
        if let detailsTag = tags.first(where: { $0.hasPrefix("drillRepDetails:") }) {
            let rawDetails = detailsTag.replacingOccurrences(of: "drillRepDetails:", with: "")
            let repEntries = rawDetails.split(separator: ";")
            for entry in repEntries {
                let parts = entry.split(separator: ":", omittingEmptySubsequences: false)
                guard parts.count >= 9,
                      let idx = Int(parts[0]),
                      let wCad = Int(parts[1]),
                      let wHR = Int(parts[2]),
                      let rCad = Int(parts[5]),
                      let rHR = Int(parts[6]) else { continue }
                let wPace = Double(parts[3])
                let dur = Double(parts[4])
                let rPace = Double(parts[7])
                let isMet = parts[8] == "1"

                reps.append(DrillIntervalRepCore(
                    repIndex: idx,
                    workCadence: wCad,
                    workHeartRate: wHR,
                    recoveryCadence: rCad,
                    recoveryHeartRate: rHR,
                    isMet: isMet,
                    durationSeconds: dur,
                    workPaceSecondsPerKm: wPace,
                    recoveryPaceSecondsPerKm: rPace
                ))
            }
        }

        if reps.isEmpty, let repTag = tags.first(where: { $0.hasPrefix("drillReps:") }) {
            let bits = repTag.replacingOccurrences(of: "drillReps:", with: "").split(separator: ",")
            for (idx, bit) in bits.enumerated() {
                reps.append(DrillIntervalRepCore(
                    repIndex: idx + 1,
                    workCadence: workCadence,
                    workHeartRate: 0,
                    recoveryCadence: recCadence,
                    recoveryHeartRate: 0,
                    isMet: bit == "1"
                ))
            }
        }

        let tier: DrillAdherenceTierCore
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

        return DrillIntervalSummaryCore(
            drillIdentifier: drillIdentifier,
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

// MARK: - Evaluation Segment & Context

public struct DrillEvaluationSegmentCore: Sendable, Equatable {
    public let avgCadence: Double
    public let avgHR: Double
    public let duration: TimeInterval
    public let isWorkHint: Bool?
    public var avgPace: Double?

    public init(
        avgCadence: Double,
        avgHR: Double,
        duration: TimeInterval,
        isWorkHint: Bool? = nil,
        avgPace: Double? = nil
    ) {
        self.avgCadence = avgCadence
        self.avgHR = avgHR
        self.duration = duration
        self.isWorkHint = isWorkHint
        self.avgPace = avgPace
    }
}

public struct DrillEvaluationContextCore: Sendable, Equatable {
    public let drillIdentifier: String
    public let effectiveTargetMin: Int?
    public let effectiveTargetMax: Int?
    public let baselineCadence: Int
    public let oscDelta: Double
    public let isAerobicContinuous: Bool

    public init(
        drillIdentifier: String,
        effectiveTargetMin: Int?,
        effectiveTargetMax: Int?,
        baselineCadence: Int,
        oscDelta: Double = 0.0,
        isAerobicContinuous: Bool = false
    ) {
        self.drillIdentifier = drillIdentifier
        self.effectiveTargetMin = effectiveTargetMin
        self.effectiveTargetMax = effectiveTargetMax
        self.baselineCadence = baselineCadence
        self.oscDelta = oscDelta
        self.isAerobicContinuous = isAerobicContinuous
    }
}
