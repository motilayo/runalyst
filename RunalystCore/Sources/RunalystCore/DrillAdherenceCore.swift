import Foundation

// MARK: - Drill Adherence Domain Types

public struct DrillAdherenceInputCore: Sendable, Codable, Equatable {
    public let drillIdentifier: String
    public let actualCadence: Int
    public let actualHeartRate: Int
    public let baselineCadence: Int
    public let heightAdjustedCadenceFloor: Int
    public let targetCadenceLower: Int?
    public let targetCadenceUpper: Int?
    public let targetCadenceString: String
    public let targetHeartRateZone: Int?
    public let percentZone4: Double
    public let oscDelta: Double
    public let isHeartRateTargeted: Bool
    public let isAerobicContinuous: Bool
    public let isDualTarget: Bool
    public let intervalSummaryMetCount: Int?
    public let intervalSummaryTotalCount: Int?
    public let intervalSummaryTier: DrillAdherenceTierCore?
    public let intervalSummaryVerdict: String?
    public let repsTotalCount: Int
    public let repsMetCount: Int

    public init(
        drillIdentifier: String,
        actualCadence: Int,
        actualHeartRate: Int,
        baselineCadence: Int,
        heightAdjustedCadenceFloor: Int = 150,
        targetCadenceLower: Int? = nil,
        targetCadenceUpper: Int? = nil,
        targetCadenceString: String = "Steady",
        targetHeartRateZone: Int? = nil,
        percentZone4: Double = 0.0,
        oscDelta: Double = 0.0,
        isHeartRateTargeted: Bool = false,
        isAerobicContinuous: Bool = false,
        isDualTarget: Bool = false,
        intervalSummaryMetCount: Int? = nil,
        intervalSummaryTotalCount: Int? = nil,
        intervalSummaryTier: DrillAdherenceTierCore? = nil,
        intervalSummaryVerdict: String? = nil,
        repsTotalCount: Int = 0,
        repsMetCount: Int = 0
    ) {
        self.drillIdentifier = drillIdentifier
        self.actualCadence = actualCadence
        self.actualHeartRate = actualHeartRate
        self.baselineCadence = baselineCadence
        self.heightAdjustedCadenceFloor = heightAdjustedCadenceFloor
        self.targetCadenceLower = targetCadenceLower
        self.targetCadenceUpper = targetCadenceUpper
        self.targetCadenceString = targetCadenceString
        self.targetHeartRateZone = targetHeartRateZone
        self.percentZone4 = percentZone4
        self.oscDelta = oscDelta
        self.isHeartRateTargeted = isHeartRateTargeted
        self.isAerobicContinuous = isAerobicContinuous
        self.isDualTarget = isDualTarget
        self.intervalSummaryMetCount = intervalSummaryMetCount
        self.intervalSummaryTotalCount = intervalSummaryTotalCount
        self.intervalSummaryTier = intervalSummaryTier
        self.intervalSummaryVerdict = intervalSummaryVerdict
        self.repsTotalCount = repsTotalCount
        self.repsMetCount = repsMetCount
    }
}

public struct DrillAdherenceResultCore: Sendable, Codable, Equatable {
    public let effectiveMetCount: Int
    public let effectiveTotalCount: Int
    public let isIntervalDrill: Bool
    public let tier: DrillAdherenceTierCore
    public let tierDescription: String

    public init(
        effectiveMetCount: Int,
        effectiveTotalCount: Int,
        isIntervalDrill: Bool,
        tier: DrillAdherenceTierCore,
        tierDescription: String
    ) {
        self.effectiveMetCount = effectiveMetCount
        self.effectiveTotalCount = effectiveTotalCount
        self.isIntervalDrill = isIntervalDrill
        self.tier = tier
        self.tierDescription = tierDescription
    }
}

// MARK: - Core Drill Adherence Evaluator

public enum DrillAdherenceCore {

    public static func evaluateAdherence(input: DrillAdherenceInputCore) -> DrillAdherenceResultCore {
        let isIntervalDrill = (input.intervalSummaryTotalCount ?? 0) > 1 || input.repsTotalCount > 1

        let effectiveMetCount: Int
        let effectiveTotalCount: Int
        if let total = input.intervalSummaryTotalCount, total > 1 {
            let summaryMet = input.intervalSummaryMetCount ?? 0
            effectiveMetCount = input.repsTotalCount == 0 ? summaryMet : max(summaryMet, input.repsMetCount)
            effectiveTotalCount = input.repsTotalCount == 0 ? total : input.repsTotalCount
        } else if isIntervalDrill && input.repsTotalCount > 0 {
            effectiveMetCount = input.repsMetCount
            effectiveTotalCount = input.repsTotalCount
        } else {
            effectiveMetCount = input.intervalSummaryMetCount ?? 0
            effectiveTotalCount = input.intervalSummaryTotalCount ?? 0
        }

        let tier: DrillAdherenceTierCore
        let tierDescription: String

        if let total = input.intervalSummaryTotalCount, total > 1 {
            if input.isDualTarget {
                let intervalsOk = effectiveMetCount >= (effectiveTotalCount + 1) / 2
                let zone4Ok = input.percentZone4 >= 0.20
                if effectiveMetCount == effectiveTotalCount && input.percentZone4 >= 0.35 {
                    tier = .exceeded
                    tierDescription = "Nailed all \(effectiveTotalCount) surges with high threshold capacity (≥35% Zone 4)."
                } else if (input.intervalSummaryTier == .met || input.intervalSummaryTier == .exceeded) || (intervalsOk && zone4Ok) {
                    tier = .met
                    tierDescription = "Landed target surges with sustained threshold effort."
                } else if intervalsOk || input.percentZone4 >= 0.15 {
                    tier = .partiallyMet
                    tierDescription = intervalsOk
                        ? "Hit turnover surges, but overall time in threshold was limited."
                        : "Reached threshold intensity, but surge turnover discipline was developing."
                } else {
                    tier = .notMet
                    tierDescription = input.intervalSummaryVerdict ?? "Turnover surges and threshold goals missed."
                }
            } else if effectiveMetCount > (input.intervalSummaryMetCount ?? 0) {
                if effectiveMetCount == effectiveTotalCount && effectiveTotalCount > 0 {
                    tier = .met
                    tierDescription = "Flawless turnover discipline: hit all \(effectiveTotalCount) work intervals on target."
                } else if effectiveMetCount >= (effectiveTotalCount + 1) / 2 {
                    tier = .partiallyMet
                    tierDescription = "Strong turnover adherence: hit \(effectiveMetCount) of \(effectiveTotalCount) target intervals."
                } else {
                    tier = .notMet
                    tierDescription = "Developing turnover: hit \(effectiveMetCount) of \(effectiveTotalCount) intervals in target band."
                }
            } else {
                tier = input.intervalSummaryTier ?? .met
                tierDescription = input.intervalSummaryVerdict ?? "Interval drill completed."
            }
        } else if isIntervalDrill && input.repsTotalCount > 0 {
            if effectiveMetCount == effectiveTotalCount {
                tier = .met
                tierDescription = "Flawless turnover discipline: hit all \(effectiveTotalCount) work intervals on target."
            } else if effectiveMetCount >= (effectiveTotalCount + 1) / 2 {
                tier = .partiallyMet
                tierDescription = "Strong turnover adherence: hit \(effectiveMetCount) of \(effectiveTotalCount) target intervals."
            } else {
                tier = .notMet
                tierDescription = "Developing turnover: hit \(effectiveMetCount) of \(effectiveTotalCount) intervals in target band."
            }
        } else if input.isDualTarget {
            let cadenceExact: Bool
            let cadenceClose: Bool
            if let lower = input.targetCadenceLower, let upper = input.targetCadenceUpper {
                cadenceExact = input.actualCadence >= lower && input.actualCadence <= upper
                cadenceClose = input.actualCadence >= (lower - 2) && input.actualCadence <= (upper + 2)
            } else {
                cadenceExact = true
                cadenceClose = true
            }

            if cadenceExact && input.percentZone4 >= 0.35 {
                tier = .exceeded
                tierDescription = "Held target turnover with high threshold capacity (≥35% Zone 4)."
            } else if (cadenceExact || cadenceClose) && input.percentZone4 >= 0.20 {
                tier = .met
                tierDescription = "Landed in target cadence band with sustained threshold effort."
            } else if cadenceExact || input.percentZone4 >= 0.15 {
                tier = .partiallyMet
                tierDescription = cadenceExact
                    ? "Hit turnover target, but effort remained sub-threshold."
                    : "Reached threshold intensity, but cadence was off target."
            } else {
                tier = .notMet
                tierDescription = "Missed both target cadence and threshold intensity goals."
            }
        } else if input.isHeartRateTargeted {
            let zone = input.targetHeartRateZone ?? 2
            let effectiveFloor = input.heightAdjustedCadenceFloor
            if zone == 2 {
                if input.actualHeartRate > 0 {
                    let zone2Ceiling = 144
                    if input.actualHeartRate <= zone2Ceiling && input.actualCadence >= effectiveFloor && input.percentZone4 <= 0.02 {
                        tier = .exceeded
                        tierDescription = "Preserved Zone 2 ceiling with crisp turnover (≥\(effectiveFloor) SPM)."
                    } else if input.actualHeartRate <= zone2Ceiling && input.percentZone4 <= 0.05 {
                        tier = .met
                        tierDescription = "Successfully maintained steady Zone 2 aerobic intensity."
                    } else if input.actualHeartRate <= zone2Ceiling + 8 && input.percentZone4 <= 0.10 {
                        tier = .partiallyMet
                        tierDescription = "Moderate intensity drift; effort rose above Zone 2 aerobic ceiling into Zone 3."
                    } else {
                        tier = .notMet
                        tierDescription = "Cardiac drift exceeded Zone 2 aerobic ceiling into sustained Zone 3 strain."
                    }
                } else {
                    tier = .met
                    tierDescription = "Completed steady aerobic effort."
                }
            } else { // Zone 1
                if input.actualHeartRate > 0 {
                    let zone1Ceiling = 135
                    if input.percentZone4 == 0.0 && input.actualHeartRate <= 125 {
                        tier = .exceeded
                        tierDescription = "Flawless active recovery with zero cardiac strain."
                    } else if input.percentZone4 <= 0.03 && input.actualHeartRate <= zone1Ceiling {
                        tier = .met
                        tierDescription = "Controlled intensity within the Zone 1 recovery envelope."
                    } else if input.percentZone4 <= 0.10 && input.actualHeartRate <= zone1Ceiling + 6 {
                        tier = .partiallyMet
                        tierDescription = "Effort drifted slightly higher than target recovery ceiling."
                    } else {
                        tier = .notMet
                        tierDescription = "Intensity was too elevated for an active recovery run."
                    }
                } else {
                    tier = .met
                    tierDescription = "Completed gentle recovery effort."
                }
            }
        } else if let lower = input.targetCadenceLower, let upper = input.targetCadenceUpper {
            let inRange = input.actualCadence >= lower && input.actualCadence <= upper
            let zeroSpike = input.percentZone4 <= 0.05
            let formImproved = input.oscDelta <= 0.0

            if inRange && zeroSpike && formImproved {
                tier = .exceeded
                tierDescription = "Target turnover held with effortless aerobic stability and form control."
            } else if inRange {
                tier = .met
                tierDescription = "Cadence landed precisely within the target \(input.targetCadenceString) SPM band."
            } else if input.actualCadence >= (lower - 2) && input.actualCadence <= (upper + 2) {
                tier = .partiallyMet
                tierDescription = "Turnover was close to target (within 2 SPM of target band)."
            } else {
                tier = .notMet
                tierDescription = "Turnover missed the target cadence band by more than 2 SPM."
            }
        } else {
            tier = .met
            tierDescription = "Completed steady effort drill."
        }

        return DrillAdherenceResultCore(
            effectiveMetCount: effectiveMetCount,
            effectiveTotalCount: effectiveTotalCount,
            isIntervalDrill: isIntervalDrill,
            tier: tier,
            tierDescription: tierDescription
        )
    }
}
