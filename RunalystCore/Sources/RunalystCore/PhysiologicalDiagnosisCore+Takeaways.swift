import Foundation

// MARK: - Aerobic Strain Evaluation

/// Pure deterministic assessment of cardiovascular load and zone ceiling adherence.
public struct AerobicStrainEvaluation: Sendable, Equatable {
    public let isZone4Overreach: Bool
    public let isCeilingExceeded: Bool
    public let effectiveCeilingBPM: Double
    public let isElevatedStrain: Bool
    public let cardiacStabilityText: String
    public let isSevereStrainColor: Bool
    public let stabilitySeverity: String

    public init(
        isZone4Overreach: Bool,
        isCeilingExceeded: Bool,
        effectiveCeilingBPM: Double,
        isElevatedStrain: Bool = false,
        cardiacStabilityText: String = "",
        isSevereStrainColor: Bool = false,
        stabilitySeverity: String = "moderate"
    ) {
        self.isZone4Overreach = isZone4Overreach
        self.isCeilingExceeded = isCeilingExceeded
        self.effectiveCeilingBPM = effectiveCeilingBPM
        self.isElevatedStrain = isElevatedStrain
        self.cardiacStabilityText = cardiacStabilityText
        self.isSevereStrainColor = isSevereStrainColor
        self.stabilitySeverity = stabilitySeverity
    }

    /// Evaluates cardiovascular strain against heart rate ceiling boundaries and anaerobic exposure.
    public static func evaluate(
        workingAvgHeartRate: Double,
        percentZone4: Double,
        zone2Ceiling: Double,
        isRecoveryPrescription: Bool,
        recoveryCeiling: Double = 135.0,
        hrCV: Double? = nil
    ) -> AerobicStrainEvaluation {
        let ceiling = isRecoveryPrescription ? recoveryCeiling : zone2Ceiling
        let effectiveCeiling = ceiling > 0 ? ceiling : (isRecoveryPrescription ? 135.0 : 144.0)

        let isOverreach = percentZone4 > 0.15 || (workingAvgHeartRate > (effectiveCeiling + 12.0))
        let isExceeded = (workingAvgHeartRate > effectiveCeiling) || (percentZone4 > 0.15)
        let isElevated = workingAvgHeartRate > (effectiveCeiling + 3.0)

        let stabilityText: String
        let isSevereColor: Bool
        let severity: String

        if isOverreach {
            stabilityText = "Zone 4 Threshold Strain"
            if percentZone4 >= 0.30 {
                isSevereColor = true
                severity = "severe"
            } else {
                isSevereColor = false
                severity = "moderate"
            }
        } else if isElevated {
            stabilityText = "Elevated Strain (Zone 3)"
            isSevereColor = false
            severity = "moderate"
        } else if percentZone4 <= 0.04 && (hrCV ?? 0.05) <= 0.08 {
            stabilityText = "Cardiac Stability: High"
            isSevereColor = false
            severity = "optimal"
        } else if percentZone4 <= 0.12 {
            stabilityText = "Cardiac Stability: Moderate"
            isSevereColor = false
            severity = "moderate"
        } else {
            stabilityText = "Cardiac Drift Detected"
            isSevereColor = true
            severity = "severe"
        }

        return AerobicStrainEvaluation(
            isZone4Overreach: isOverreach,
            isCeilingExceeded: isExceeded,
            effectiveCeilingBPM: effectiveCeiling,
            isElevatedStrain: isElevated,
            cardiacStabilityText: stabilityText,
            isSevereStrainColor: isSevereColor,
            stabilitySeverity: severity
        )
    }

    /// Evaluates threshold drill achievement tier based on Zone 4 exposure percentage.
    /// Returns "met" (>= 0.20), "partial" (>= 0.15), or "missed" (< 0.15).
    public static func evaluateThresholdGoalTier(percentZone4: Double) -> String {
        if percentZone4 >= 0.20 {
            return "met"
        } else if percentZone4 >= 0.15 {
            return "partial"
        } else {
            return "missed"
        }
    }
}

// MARK: - Run Takeaway Item & Summary

/// Machine-readable takeaway item for deterministic post-workout analysis.
public struct RunTakeawayItemCore: Sendable, Equatable, Identifiable {
    public let id: String
    public let iconName: String
    public let title: String
    public let detail: String
    public let isWarning: Bool

    public init(id: String, iconName: String, title: String, detail: String, isWarning: Bool = false) {
        self.id = id
        self.iconName = iconName
        self.title = title
        self.detail = detail
        self.isWarning = isWarning
    }
}

/// Unified summary of deterministic post-workout takeaways and headline diagnosis.
public struct RunTakeawaySummary: Sendable, Equatable {
    public let headline: String
    public let bullets: [String]
    public let items: [RunTakeawayItemCore]

    public struct DrillAdherenceContext: Sendable, Equatable {
        public let drillIdentifier: String
        public let drillDisplayName: String
        public let targetCadence: Int
        public let targetHeartRateZone: Int
        public let isHeartRateTargeted: Bool
        public let metCount: Int
        public let totalCount: Int
        public let actualHR: Double
        public let actualCadence: Int
        public let effectiveCadenceFloor: Int
        public let tier: String
        public let tierBadgeText: String

        public init(
            drillIdentifier: String,
            drillDisplayName: String,
            targetCadence: Int,
            targetHeartRateZone: Int = 2,
            isHeartRateTargeted: Bool = false,
            metCount: Int = 0,
            totalCount: Int = 0,
            actualHR: Double = 0.0,
            actualCadence: Int = 0,
            effectiveCadenceFloor: Int = 150,
            tier: String = "met",
            tierBadgeText: String = "Target Achieved"
        ) {
            self.drillIdentifier = drillIdentifier
            self.drillDisplayName = drillDisplayName
            self.targetCadence = targetCadence
            self.targetHeartRateZone = targetHeartRateZone
            self.isHeartRateTargeted = isHeartRateTargeted
            self.metCount = metCount
            self.totalCount = totalCount
            self.actualHR = actualHR
            self.actualCadence = actualCadence
            self.effectiveCadenceFloor = effectiveCadenceFloor
            self.tier = tier
            self.tierBadgeText = tierBadgeText
        }
    }

    public struct IntervalSummaryContext: Sendable, Equatable {
        public let meanWorkPaceSecondsPerKm: Double
        public let avgWorkCadence: Int

        public init(meanWorkPaceSecondsPerKm: Double, avgWorkCadence: Int) {
            self.meanWorkPaceSecondsPerKm = meanWorkPaceSecondsPerKm
            self.avgWorkCadence = avgWorkCadence
        }
    }

    public init(headline: String, bullets: [String], items: [RunTakeawayItemCore] = []) {
        self.headline = headline
        self.bullets = bullets
        self.items = items
    }

    public static func evaluate(
        detectedTypeRaw: String,
        workingAvgCadence: Double,
        workingAvgHeartRate: Double,
        percentZone4: Double,
        heightAdjustedCadenceFloor: Int,
        isIndoor: Bool = false,
        hasCardiacDrift: Bool = false,
        cardiacDriftMagnitudeBPM: Int = 0,
        prescribedDrillName: String? = nil,
        drillAdherence: DrillAdherenceContext? = nil,
        intervalSummary: IntervalSummaryContext? = nil,
        cachedInsightHeadline: String? = nil,
        calibratedZone2CeilingBPM: Double? = nil,
        calibratedRecoveryCeilingBPM: Double? = nil
    ) -> RunTakeawaySummary {
        guard workingAvgCadence > 0 || workingAvgHeartRate > 0 else {
            return RunTakeawaySummary(
                headline: "Biometric Analysis Unavailable",
                bullets: [],
                items: []
            )
        }

        let isRecovery = detectedTypeRaw == "Recovery Run" ||
            (percentZone4 <= 0.02 && workingAvgHeartRate > 0 && workingAvgHeartRate <= 135)
        let effectiveFloor = isRecovery ? max(138, heightAdjustedCadenceFloor - 10) : heightAdjustedCadenceFloor
        let cad = Int(round(workingAvgCadence))
        let workingHR = Int(round(workingAvgHeartRate))

        var items: [RunTakeawayItemCore] = []

        // 1. Cadence & Biomechanics
        if let adherence = drillAdherence, prescribedDrillName != nil {
            let metCount = adherence.metCount
            let totalCount = adherence.totalCount
            let targetCadence = adherence.targetCadence
            let cadDetail: String
            if totalCount > 0 && metCount == totalCount {
                cadDetail = "Target turnover of \(targetCadence) SPM was held flawlessly across all \(totalCount) work intervals, reinforcing efficient running economy."
            } else if totalCount > 0 && metCount > 0 {
                cadDetail = "Target turnover reached \(targetCadence) SPM on \(metCount) of \(totalCount) work intervals, building consistent neuromuscular turnover."
            } else {
                cadDetail = "Turnover averaged \(cad) SPM against your \(targetCadence) SPM drill target."
            }
            items.append(RunTakeawayItemCore(
                id: "drill-turnover",
                iconName: "metronome.fill",
                title: "Drill Turnover",
                detail: cadDetail,
                isWarning: false
            ))
        } else if cad > 0 {
            let cadDetail: String
            let isWarning = cad < effectiveFloor
            if isRecovery {
                cadDetail = "Turnover averaged \(cad) SPM with relaxed, low-impact stride mechanics, ideal for active recovery and flushing muscular fatigue."
            } else if cad > effectiveFloor {
                cadDetail = "Turnover averaged \(cad) SPM, safely above your \(heightAdjustedCadenceFloor) SPM mechanical floor. This cadence helps keep foot strikes underneath your hips and cushions joint landing\(isIndoor ? " on the treadmill belt" : "")."
            } else if cad == effectiveFloor {
                cadDetail = "Turnover averaged \(cad) SPM, matching your \(heightAdjustedCadenceFloor) SPM mechanical floor. This cadence helps keep foot strikes underneath your hips and cushions joint landing\(isIndoor ? " on the treadmill belt" : "")."
            } else {
                let diff = effectiveFloor - cad
                cadDetail = "Turnover averaged \(cad) SPM, \(diff) SPM below your \(heightAdjustedCadenceFloor) SPM mechanical floor. Increasing step rate will shorten your stride and cushion joint landing\(isIndoor ? " on the moving belt" : "")."
            }
            items.append(RunTakeawayItemCore(
                id: "cadence-form",
                iconName: "figure.run",
                title: "Cadence & Form",
                detail: cadDetail,
                isWarning: isWarning
            ))
        }

        // 2. Cardiovascular Effort & Decoupling
        if workingAvgHeartRate > 0 {
            let zone2Ceiling = calibratedZone2CeilingBPM ?? 144.0
            let recoveryCeiling = calibratedRecoveryCeilingBPM ?? 135.0
            let hrCeiling: Int = {
                if let drill = drillAdherence {
                    return drill.targetHeartRateZone == 2 ? Int(zone2Ceiling.rounded()) : Int(recoveryCeiling.rounded())
                }
                return isRecovery ? Int(recoveryCeiling.rounded()) : Int(zone2Ceiling.rounded())
            }()
            let strain = AerobicStrainEvaluation.evaluate(
                workingAvgHeartRate: workingAvgHeartRate,
                percentZone4: percentZone4,
                zone2Ceiling: zone2Ceiling,
                isRecoveryPrescription: isRecovery,
                recoveryCeiling: recoveryCeiling
            )

            let hrDetail: String
            if strain.isCeilingExceeded {
                if isIndoor {
                    hrDetail = "Running indoors without convective airflow accelerates thermal buildup; your \(workingHR) BPM average drifted above your \(hrCeiling) BPM target ceiling under indoor thermal load."
                } else if hasCardiacDrift {
                    hrDetail = "Heart rate climbed +\(cardiacDriftMagnitudeBPM) BPM over the duration, exceeding your \(hrCeiling) BPM target ceiling as internal fatigue accumulated."
                } else {
                    hrDetail = "Heart rate averaged \(workingHR) BPM, drifting above your \(hrCeiling) BPM target ceiling under cardiovascular strain."
                }
            } else if isIndoor {
                hrDetail = "Running indoors without convective airflow accelerates thermal buildup; your \(workingHR) BPM average reflects steady aerobic conditioning under indoor heat accumulation."
            } else if hasCardiacDrift {
                hrDetail = "Heart rate climbed +\(cardiacDriftMagnitudeBPM) BPM over the duration, reflecting cardiovascular drift and internal fatigue as the session progressed."
            } else {
                hrDetail = "Heart rate averaged \(workingHR) BPM with stable cardiovascular coupling, demonstrating controlled aerobic efficiency throughout."
            }
            items.append(RunTakeawayItemCore(
                id: "cardio-control",
                iconName: "heart.fill",
                title: "Cardiovascular Control",
                detail: hrDetail,
                isWarning: strain.isCeilingExceeded || hasCardiacDrift
            ))
        }

        // 3. Modality Execution
        if let drill = drillAdherence {
            let hrCeiling = drill.targetHeartRateZone == 2 ? 144 : 135
            let actualHR = drill.actualHR > 0 ? drill.actualHR : workingAvgHeartRate
            let isHRFailure = (drill.isHeartRateTargeted && actualHR > Double(hrCeiling)) ||
                percentZone4 > 0.15 || hasCardiacDrift
            let isCadenceFailure = cad > 0 && cad < effectiveFloor

            let execDetail: String
            if drill.tier == "exceeded" || drill.tier == "met" {
                execDetail = "Execution Status: \(drill.tierBadgeText) — aerobic target and cadence stability were maintained throughout the session."
            } else {
                let failureReason: String
                if isHRFailure && isCadenceFailure {
                    failureReason = "cardiac drift above target zone ceiling and cadence drop below target floor"
                } else if isHRFailure {
                    failureReason = "cardiac drift above target zone ceiling"
                } else if isCadenceFailure {
                    failureReason = "cadence drop below target floor"
                } else {
                    failureReason = "cardiac drift above target zone ceiling"
                }
                execDetail = "Execution Status: \(drill.tierBadgeText) — telemetry showed \(failureReason)."
            }
            items.append(RunTakeawayItemCore(
                id: "execution-verdict",
                iconName: "checkmark.seal.fill",
                title: "Execution Verdict",
                detail: execDetail,
                isWarning: drill.tier == "notMet"
            ))
        } else if let interval = intervalSummary {
            let total = Int(interval.meanWorkPaceSecondsPerKm.rounded())
            let paceStr = String(format: "%d:%02d/km", total / 60, total % 60)
            items.append(RunTakeawayItemCore(
                id: "interval-execution",
                iconName: "flag.checkered",
                title: "Interval Execution",
                detail: "Active work reps hit \(paceStr) at \(interval.avgWorkCadence) SPM with consistent pacing repeatability.",
                isWarning: false
            ))
        }

        // Headline calculation
        let headline: String = {
            let hrCeil = isRecovery ? 135 : 144
            if let drill = drillAdherence {
                if drill.tier == "notMet" {
                    let drillCeiling = drill.targetHeartRateZone == 2 ? 144 : 135
                    let actualHR = drill.actualHR > 0 ? drill.actualHR : workingAvgHeartRate
                    let isHRFail = (drill.isHeartRateTargeted && actualHR > Double(drillCeiling)) || percentZone4 > 0.15
                    let actualCad = drill.actualCadence > 0 ? drill.actualCadence : cad
                    let isCadFail = actualCad > 0 && actualCad < drill.effectiveCadenceFloor
                    if isHRFail && isCadFail {
                        return "Target Ceiling & Floor Missed"
                    } else if isHRFail {
                        return "Target Ceiling Exceeded"
                    } else if isCadFail {
                        return "Mechanical Floor Missed"
                    } else {
                        return "Target Boundaries Exceeded"
                    }
                }
            } else {
                let isHRFail = workingHR > hrCeil || percentZone4 > 0.15
                let isCadFail = cad > 0 && cad < effectiveFloor
                if isHRFail || isCadFail {
                    if isHRFail && isCadFail {
                        return "Target Ceiling & Floor Missed"
                    } else if isHRFail {
                        return "Target Ceiling Exceeded"
                    } else {
                        return "Mechanical Floor Missed"
                    }
                }
            }

            if let drillName = prescribedDrillName {
                return "\(drillName) Technique Analysis"
            }
            if let cached = cachedInsightHeadline, !cached.isEmpty {
                return cached
            }
            return "\(detectedTypeRaw) Biomechanical Analysis"
        }()

        return RunTakeawaySummary(
            headline: headline,
            bullets: items.map(\.detail),
            items: items
        )
    }
}

// MARK: - PhysiologicalDiagnosisCore Takeaway Forwarder

extension PhysiologicalDiagnosisCore {
    public static func evaluate(
        detectedTypeRaw: String,
        workingAvgCadence: Double,
        workingAvgHeartRate: Double,
        percentZone4: Double,
        heightAdjustedCadenceFloor: Int,
        isIndoor: Bool = false,
        hasCardiacDrift: Bool = false,
        cardiacDriftMagnitudeBPM: Int = 0,
        prescribedDrillName: String? = nil,
        drillAdherence: RunTakeawaySummary.DrillAdherenceContext? = nil,
        intervalSummary: RunTakeawaySummary.IntervalSummaryContext? = nil,
        cachedInsightHeadline: String? = nil,
        calibratedZone2CeilingBPM: Double? = nil,
        calibratedRecoveryCeilingBPM: Double? = nil
    ) -> RunTakeawaySummary {
        RunTakeawaySummary.evaluate(
            detectedTypeRaw: detectedTypeRaw,
            workingAvgCadence: workingAvgCadence,
            workingAvgHeartRate: workingAvgHeartRate,
            percentZone4: percentZone4,
            heightAdjustedCadenceFloor: heightAdjustedCadenceFloor,
            isIndoor: isIndoor,
            hasCardiacDrift: hasCardiacDrift,
            cardiacDriftMagnitudeBPM: cardiacDriftMagnitudeBPM,
            prescribedDrillName: prescribedDrillName,
            drillAdherence: drillAdherence,
            intervalSummary: intervalSummary,
            cachedInsightHeadline: cachedInsightHeadline,
            calibratedZone2CeilingBPM: calibratedZone2CeilingBPM,
            calibratedRecoveryCeilingBPM: calibratedRecoveryCeilingBPM
        )
    }
}
