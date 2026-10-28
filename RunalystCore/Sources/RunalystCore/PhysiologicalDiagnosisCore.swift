import Foundation

// MARK: - Environmental Domain

/// Environmental and ambient conditions surrounding a run.
public enum EnvironmentalModifier: String, Sendable, Codable, Equatable {
    case highHeat = "High Heat"
    case highElevation = "High Elevation Gain"
    case indoorTreadmill = "Indoor Treadmill"
    case standard = "Standard Ambient"
}

/// Pure thermal and ambient weather evaluation logic.
public enum WeatherProxyCore {
    public static let highHeatTemperatureCelsiusThreshold: Double = 22.0
    public static let highHeatHumidityThresholdPercent: Double = 75.0

    public static func isHighHeat(temperatureCelsius: Double?, humidity: Double?) -> Bool {
        if let temp = temperatureCelsius, temp >= highHeatTemperatureCelsiusThreshold {
            return true
        }
        if let hum = humidity {
            let percent = hum <= 1.0 ? hum * 100.0 : hum
            if percent >= highHeatHumidityThresholdPercent {
                return true
            }
        }
        return false
    }

    public static func evaluateEnvironmentalModifier(
        temperatureCelsius: Double?,
        humidity: Double?,
        isIndoor: Bool,
        elevationGainMeters: Double
    ) -> EnvironmentalModifier {
        if isIndoor {
            return .indoorTreadmill
        }
        if elevationGainMeters >= 40.0 {
            return .highElevation
        }
        if isHighHeat(temperatureCelsius: temperatureCelsius, humidity: humidity) {
            return .highHeat
        }
        return .standard
    }
}

// MARK: - Verdicts & Severity

/// Mathematical severity of a biomechanical or physiological deviation.
public enum DeviationSeverity: String, Sendable, Codable, Equatable {
    case minor = "minor observation"
    case moderate = "tactical adjustment"
    case critical = "primary focus"
}

/// Deterministic root-cause evaluation of stride turnover and cadence mechanics.
public enum CadenceCausalVerdict: Sendable, Equatable {
    case gradeResistance(dropSPM: Int, elevationGainM: Double, severity: DeviationSeverity)
    case lateNeuromuscularFatigue(decaySPM: Int, paceSlowdownSec: Int, severity: DeviationSeverity)
    case subFloorStridePattern(workingSPM: Int, heightFloorSPM: Int, severity: DeviationSeverity)
    case stableHeightCalibratedTurnover(workingSPM: Int)
    case strideOverLengthening(cadenceDropSPM: Int, strideIncreaseM: Double, severity: DeviationSeverity)

    public var summary: String {
        switch self {
        case .gradeResistance(let drop, let elev, let severity):
            return "Grade resistance deceleration (dropped \(drop) SPM over +\(Int(elev))m elevation climb; priority: \(severity.rawValue))"
        case .lateNeuromuscularFatigue(let decay, let pace, let severity):
            return "Late-run turnover fatigue (turnover slowed by \(decay) SPM while pace faded by \(pace)s/km; priority: \(severity.rawValue))"
        case .subFloorStridePattern(let working, let floor, let severity):
            return "Sub-floor cadence pattern (\(working) SPM vs \(floor) SPM height floor; priority: \(severity.rawValue))"
        case .stableHeightCalibratedTurnover(let working):
            return "Stable height-calibrated turnover (\(working) SPM maintained consistently)"
        case .strideOverLengthening(let drop, let str, let severity):
            return "Stride over-lengthening under fatigue (cadence dropped \(drop) SPM while stride reached +\(String(format: "%.2f", str))m; priority: \(severity.rawValue))"
        }
    }
}

/// Deterministic root-cause evaluation of heart rate behavior and cardiac decoupling.
public enum CardiacCausalVerdict: Sendable, Equatable {
    case thermalOrCardiovascularDrift(driftBPM: Int, durationMin: Int, severity: DeviationSeverity)
    case elevationInducedCardiacSurge(elevationGainM: Double, hrRiseBPM: Int, severity: DeviationSeverity)
    case pacingOvershootDecoupling(earlyPaceDeltaSec: Int, lateHRRiseBPM: Int, severity: DeviationSeverity)
    case thermalStrain(heatIndex: String)
    case stableCardiovascularCoupling(avgHR: Int)

    // swiftlint:disable:next identifier_name
    public static func thermalStrain(HeatIndex: String) -> CardiacCausalVerdict {
        .thermalStrain(heatIndex: HeatIndex)
    }

    public var summary: String {
        switch self {
        case .thermalOrCardiovascularDrift(let drift, let dur, let severity):
            return "Aerobic decoupling / cardiac drift (+\(drift) BPM HR rise over \(dur) min at steady pace; thermal strain or internal fatigue; priority: \(severity.rawValue))"
        case .elevationInducedCardiacSurge(let elev, let rise, let severity):
            return "Gravitational cardiovascular surge (+\(rise) BPM HR rise from +\(Int(elev))m elevation climbing, not aerobic fitness loss; priority: \(severity.rawValue))"
        case .pacingOvershootDecoupling(let paceDelta, let hrRise, let severity):
            return "Pacing overshoot decoupling (started \(paceDelta)s/km too fast, triggering +\(hrRise) BPM cardiac rise; priority: \(severity.rawValue))"
        case .thermalStrain(let heatIndex):
            return "Environmental thermal strain decoupling (cardiac drift under high ambient heat and humidity [Heat Index: \(heatIndex)]; priority: \(DeviationSeverity.critical.rawValue))"
        case .stableCardiovascularCoupling(let avgHR):
            return "Coupled cardiovascular stability (steady heart rate around \(avgHR) BPM tracking pace cleanly)"
        }
    }
}

/// Deterministic root-cause evaluation of vertical displacement and running economy.
public enum VerticalEconomyVerdict: Sendable, Equatable {
    case excessiveVerticalDisplacement(verticalRatioPercent: Double, bounceCM: Double, severity: DeviationSeverity)
    case optimalForwardKinematics(verticalRatioPercent: Double, bounceCM: Double)
    case treadmillDeckKinematics(cadenceSPM: Int)

    public var summary: String {
        switch self {
        case .excessiveVerticalDisplacement(let ratio, let bounce, let severity):
            return "Excessive vertical bounce (Vertical Ratio \(String(format: "%.1f", ratio))%, bounce \(String(format: "%.1f", bounce)) cm; upward bounce wastes propulsion energy; priority: \(severity.rawValue))"
        case .optimalForwardKinematics(let ratio, let bounce):
            return "Optimal forward running economy (Vertical Ratio \(String(format: "%.1f", ratio))%, compact bounce \(String(format: "%.1f", bounce)) cm converted cleanly into forward propulsion)"
        case .treadmillDeckKinematics(let cad):
            return "Treadmill deck running economy (\(cad) SPM turnover evaluated on continuous belt)"
        }
    }
}

/// Deterministic root-cause evaluation of split progression and pacing execution.
public enum PacingExecutionVerdict: Sendable, Equatable {
    case earlyOverpaceFade(firstHalfPaceSec: Double, secondHalfPaceSec: Double, fadeSec: Int, severity: DeviationSeverity)
    case progressiveAcceleration(secondHalfPaceSec: Double, negativeSplitGainSec: Int)
    case disciplinedMetronomic(paceSpreadSec: Int)

    private static func formatPace(secondsPerKilometer: Double) -> String {
        guard secondsPerKilometer.isFinite && secondsPerKilometer > 0 else { return "--:--" }
        let total = Int(secondsPerKilometer.rounded())
        return String(format: "%d:%02d/km", total / 60, total % 60)
    }

    public var summary: String {
        switch self {
        case .earlyOverpaceFade(let first, let second, let fade, let severity):
            let p1 = Self.formatPace(secondsPerKilometer: first)
            let p2 = Self.formatPace(secondsPerKilometer: second)
            return "Early over-pacing fade (faded by \(fade)s/km in second half: \(p1) -> \(p2); priority: \(severity.rawValue))"
        case .progressiveAcceleration(let second, let gain):
            let p2 = Self.formatPace(secondsPerKilometer: second)
            return "Progressive negative split discipline (\(gain)s/km faster in second half down to \(p2))"
        case .disciplinedMetronomic(let spread):
            return "Disciplined metronomic pacing (consistent \(spread)s/km spread across all splits)"
        }
    }
}

/// Structured, machine-readable physiological diagnosis finding for on-device LLM tools.
public struct PhysiologicalFinding: Codable, Sendable, Equatable {
    public let domain: String
    public let code: String
    public let metric: String
    public let value: Double?
    public let threshold: Double?
    public let severity: String

    public init(
        domain: String,
        code: String,
        metric: String,
        value: Double? = nil,
        threshold: Double? = nil,
        severity: String = "optimal"
    ) {
        self.domain = domain
        self.code = code
        self.metric = metric
        self.value = value
        self.threshold = threshold
        self.severity = severity
    }
}

/// Aggregated physiological diagnostic verdicts deterministically calculated by Swift.
public struct PhysiologicalVerdicts: Sendable, Equatable {
    public let cadence: CadenceCausalVerdict
    public let cardiac: CardiacCausalVerdict
    public let verticalEconomy: VerticalEconomyVerdict
    public let pacing: PacingExecutionVerdict

    public init(
        cadence: CadenceCausalVerdict,
        cardiac: CardiacCausalVerdict,
        verticalEconomy: VerticalEconomyVerdict,
        pacing: PacingExecutionVerdict
    ) {
        self.cadence = cadence
        self.cardiac = cardiac
        self.verticalEconomy = verticalEconomy
        self.pacing = pacing
    }

    public var findings: [PhysiologicalFinding] {
        var list: [PhysiologicalFinding] = []

        switch cadence {
        case .gradeResistance(let drop, let elev, let severity):
            list.append(PhysiologicalFinding(domain: "cadence", code: "grade_resistance", metric: "spm", value: Double(drop), threshold: elev, severity: severity.rawValue))
        case .lateNeuromuscularFatigue(let decay, let pace, let severity):
            list.append(PhysiologicalFinding(domain: "cadence", code: "late_neuromuscular_fatigue", metric: "spm", value: Double(decay), threshold: Double(pace), severity: severity.rawValue))
        case .subFloorStridePattern(let working, let floor, let severity):
            list.append(PhysiologicalFinding(domain: "cadence", code: "sub_floor_cadence", metric: "spm", value: Double(working), threshold: Double(floor), severity: severity.rawValue))
        case .stableHeightCalibratedTurnover(let working):
            list.append(PhysiologicalFinding(domain: "cadence", code: "stable_turnover", metric: "spm", value: Double(working), severity: "optimal"))
        case .strideOverLengthening(let drop, let str, let severity):
            list.append(PhysiologicalFinding(domain: "cadence", code: "stride_over_lengthening", metric: "spm", value: Double(drop), threshold: str, severity: severity.rawValue))
        }

        switch cardiac {
        case .thermalOrCardiovascularDrift(let drift, let dur, let severity):
            list.append(PhysiologicalFinding(domain: "cardiac", code: "cardiac_drift", metric: "bpm", value: Double(drift), threshold: Double(dur), severity: severity.rawValue))
        case .elevationInducedCardiacSurge(let elev, let rise, let severity):
            list.append(PhysiologicalFinding(domain: "cardiac", code: "elevation_cardiac_surge", metric: "bpm", value: Double(rise), threshold: elev, severity: severity.rawValue))
        case .pacingOvershootDecoupling(let paceDelta, let hrRise, let severity):
            list.append(PhysiologicalFinding(domain: "cardiac", code: "pacing_overshoot_decoupling", metric: "bpm", value: Double(hrRise), threshold: Double(paceDelta), severity: severity.rawValue))
        case .thermalStrain:
            list.append(PhysiologicalFinding(domain: "cardiac", code: "thermal_strain", metric: "heat_index", severity: "critical"))
        case .stableCardiovascularCoupling(let avgHR):
            list.append(PhysiologicalFinding(domain: "cardiac", code: "stable_cardiac_coupling", metric: "bpm", value: Double(avgHR), severity: "optimal"))
        }

        switch verticalEconomy {
        case .excessiveVerticalDisplacement(let ratio, let bounce, let severity):
            list.append(PhysiologicalFinding(domain: "vertical_economy", code: "excessive_vertical_bounce", metric: "cm", value: bounce, threshold: ratio, severity: severity.rawValue))
        case .optimalForwardKinematics(let ratio, let bounce):
            list.append(PhysiologicalFinding(domain: "vertical_economy", code: "optimal_forward_kinematics", metric: "cm", value: bounce, threshold: ratio, severity: "optimal"))
        case .treadmillDeckKinematics(let cad):
            list.append(PhysiologicalFinding(domain: "vertical_economy", code: "treadmill_deck_kinematics", metric: "spm", value: Double(cad), severity: "optimal"))
        }

        switch pacing {
        case .earlyOverpaceFade(let first, let second, let fade, let severity):
            list.append(PhysiologicalFinding(domain: "pacing", code: "early_overpace_fade", metric: "s_per_km", value: Double(fade), threshold: second - first, severity: severity.rawValue))
        case .progressiveAcceleration(_, let gain):
            list.append(PhysiologicalFinding(domain: "pacing", code: "progressive_acceleration", metric: "s_per_km", value: Double(gain), severity: "optimal"))
        case .disciplinedMetronomic(let spread):
            list.append(PhysiologicalFinding(domain: "pacing", code: "disciplined_metronomic", metric: "s_per_km", value: Double(spread), severity: "optimal"))
        }

        return list
    }

    public var promptDescription: String {
        """
        - Cadence Turnover: \(cadence.summary)
        - Aerobic Decoupling & Drift: \(cardiac.summary)
        - Vertical Economy: \(verticalEconomy.summary)
        - Pacing Consistency: \(pacing.summary)
        """
    }
}

// MARK: - Input & Evaluator

public struct PhysiologicalSplitSample: Sendable, Equatable, Codable {
    public let paceSecondsPerKm: Double
    public let avgCadence: Double

    public init(paceSecondsPerKm: Double, avgCadence: Double) {
        self.paceSecondsPerKm = paceSecondsPerKm
        self.avgCadence = avgCadence
    }
}

public struct PhysiologicalDiagnosisInput: Sendable, Equatable {
    public let workingCadence: Int
    public let heightAdjustedCadenceFloor: Int
    public let splits: [PhysiologicalSplitSample]
    public let elevationGainMeters: Double
    public let hasCardiacDrift: Bool
    public let cardiacDriftMagnitudeBPM: Int
    public let durationSeconds: Double
    public let verticalRatio: Double?
    public let verticalOscillationCM: Double?
    public let isIndoor: Bool
    public let firstHalfPaceSec: Double
    public let secondHalfPaceSec: Double
    public let fastestSplitPaceSec: Double?
    public let slowestSplitPaceSec: Double?
    public let avgHeartRate: Int
    public var ambientTemperatureC: Double?
    public var ambientHumidity: Double?
    public var environmentalModifier: EnvironmentalModifier?

    public init(
        workingCadence: Int,
        heightAdjustedCadenceFloor: Int,
        splits: [PhysiologicalSplitSample],
        elevationGainMeters: Double,
        hasCardiacDrift: Bool,
        cardiacDriftMagnitudeBPM: Int,
        durationSeconds: Double,
        verticalRatio: Double? = nil,
        verticalOscillationCM: Double? = nil,
        isIndoor: Bool = false,
        firstHalfPaceSec: Double,
        secondHalfPaceSec: Double,
        fastestSplitPaceSec: Double? = nil,
        slowestSplitPaceSec: Double? = nil,
        avgHeartRate: Int,
        ambientTemperatureC: Double? = nil,
        ambientHumidity: Double? = nil,
        environmentalModifier: EnvironmentalModifier? = nil
    ) {
        self.workingCadence = workingCadence
        self.heightAdjustedCadenceFloor = heightAdjustedCadenceFloor
        self.splits = splits
        self.elevationGainMeters = elevationGainMeters
        self.hasCardiacDrift = hasCardiacDrift
        self.cardiacDriftMagnitudeBPM = cardiacDriftMagnitudeBPM
        self.durationSeconds = durationSeconds
        self.verticalRatio = verticalRatio
        self.verticalOscillationCM = verticalOscillationCM
        self.isIndoor = isIndoor
        self.firstHalfPaceSec = firstHalfPaceSec
        self.secondHalfPaceSec = secondHalfPaceSec
        self.fastestSplitPaceSec = fastestSplitPaceSec
        self.slowestSplitPaceSec = slowestSplitPaceSec
        self.avgHeartRate = avgHeartRate
        self.ambientTemperatureC = ambientTemperatureC
        self.ambientHumidity = ambientHumidity
        self.environmentalModifier = environmentalModifier
    }
}

public enum PhysiologicalDiagnosisCore {
    public static func evaluate(_ input: PhysiologicalDiagnosisInput) -> PhysiologicalVerdicts {
        // 1. Cadence Evaluation
        let cadenceVerdict: CadenceCausalVerdict
        if input.splits.count >= 3 {
            let mid = input.splits.count / 2
            let early = input.splits.prefix(mid)
            let late = input.splits.suffix(input.splits.count - mid)
            let earlyCad = early.reduce(0.0) { $0 + $1.avgCadence } / Double(early.count)
            let lateCad = late.reduce(0.0) { $0 + $1.avgCadence } / Double(late.count)
            let decay = earlyCad - lateCad
            let earlyPace = early.reduce(0.0) { $0 + $1.paceSecondsPerKm } / Double(early.count)
            let latePace = late.reduce(0.0) { $0 + $1.paceSecondsPerKm } / Double(late.count)
            let paceSlowing = latePace - earlyPace

            if input.elevationGainMeters >= 40.0 && decay >= 4.0 {
                let sev: DeviationSeverity = decay >= 10.0 ? .critical : (decay >= 6.0 ? .moderate : .minor)
                cadenceVerdict = .gradeResistance(dropSPM: Int(decay.rounded()), elevationGainM: input.elevationGainMeters, severity: sev)
            } else if decay >= 5.0 && paceSlowing >= 5.0 {
                let sev: DeviationSeverity = decay >= 10.0 ? .critical : (decay >= 7.0 ? .moderate : .minor)
                cadenceVerdict = .lateNeuromuscularFatigue(decaySPM: Int(decay.rounded()), paceSlowdownSec: Int(paceSlowing.rounded()), severity: sev)
            } else if input.workingCadence < input.heightAdjustedCadenceFloor {
                let gap = input.heightAdjustedCadenceFloor - input.workingCadence
                let sev: DeviationSeverity = gap >= 10 ? .critical : (gap >= 5 ? .moderate : .minor)
                cadenceVerdict = .subFloorStridePattern(workingSPM: input.workingCadence, heightFloorSPM: input.heightAdjustedCadenceFloor, severity: sev)
            } else {
                cadenceVerdict = .stableHeightCalibratedTurnover(workingSPM: input.workingCadence)
            }
        } else if input.workingCadence < input.heightAdjustedCadenceFloor {
            let gap = input.heightAdjustedCadenceFloor - input.workingCadence
            let sev: DeviationSeverity = gap >= 10 ? .critical : (gap >= 5 ? .moderate : .minor)
            cadenceVerdict = .subFloorStridePattern(workingSPM: input.workingCadence, heightFloorSPM: input.heightAdjustedCadenceFloor, severity: sev)
        } else {
            cadenceVerdict = .stableHeightCalibratedTurnover(workingSPM: input.workingCadence)
        }

        // 2. Cardiac Decoupling Evaluation (Thermal & Environmental Proxies)
        let cardiacVerdict: CardiacCausalVerdict
        let isHighHeat = input.environmentalModifier == .highHeat ||
            WeatherProxyCore.isHighHeat(temperatureCelsius: input.ambientTemperatureC, humidity: input.ambientHumidity)

        if input.elevationGainMeters >= 40.0 && input.hasCardiacDrift {
            let sev: DeviationSeverity = input.cardiacDriftMagnitudeBPM >= 12 ? .critical : (input.cardiacDriftMagnitudeBPM >= 7 ? .moderate : .minor)
            cardiacVerdict = .elevationInducedCardiacSurge(elevationGainM: input.elevationGainMeters, hrRiseBPM: input.cardiacDriftMagnitudeBPM, severity: sev)
        } else if isHighHeat && input.hasCardiacDrift && !input.isIndoor {
            cardiacVerdict = .thermalStrain(HeatIndex: "High")
        } else if input.hasCardiacDrift {
            let durMin = max(1, Int(input.durationSeconds / 60) / 2)
            let sev: DeviationSeverity = input.cardiacDriftMagnitudeBPM >= 12 ? .critical : (input.cardiacDriftMagnitudeBPM >= 7 ? .moderate : .minor)
            let paceDiff = input.secondHalfPaceSec - input.firstHalfPaceSec
            if paceDiff >= 10.0 {
                cardiacVerdict = .pacingOvershootDecoupling(earlyPaceDeltaSec: Int(paceDiff.rounded()), lateHRRiseBPM: input.cardiacDriftMagnitudeBPM, severity: sev)
            } else {
                cardiacVerdict = .thermalOrCardiovascularDrift(driftBPM: input.cardiacDriftMagnitudeBPM, durationMin: durMin, severity: sev)
            }
        } else {
            cardiacVerdict = .stableCardiovascularCoupling(avgHR: input.avgHeartRate)
        }

        // 3. Vertical Running Economy
        let verticalVerdict: VerticalEconomyVerdict
        if input.isIndoor || input.verticalRatio == nil || input.verticalOscillationCM == nil {
            verticalVerdict = .treadmillDeckKinematics(cadenceSPM: input.workingCadence)
        } else if let vr = input.verticalRatio, let bounce = input.verticalOscillationCM {
            if vr > 8.5 {
                let sev: DeviationSeverity = vr >= 10.0 ? .critical : (vr >= 9.0 ? .moderate : .minor)
                verticalVerdict = .excessiveVerticalDisplacement(verticalRatioPercent: vr, bounceCM: bounce, severity: sev)
            } else {
                verticalVerdict = .optimalForwardKinematics(verticalRatioPercent: vr, bounceCM: bounce)
            }
        } else {
            verticalVerdict = .treadmillDeckKinematics(cadenceSPM: input.workingCadence)
        }

        // 4. Pacing Execution
        let pacingVerdict: PacingExecutionVerdict
        let splitDiff = input.firstHalfPaceSec - input.secondHalfPaceSec
        if splitDiff <= -6.0 {
            let fade = abs(Int(splitDiff.rounded()))
            let sev: DeviationSeverity = fade >= 18 ? .critical : (fade >= 10 ? .moderate : .minor)
            pacingVerdict = .earlyOverpaceFade(firstHalfPaceSec: input.firstHalfPaceSec, secondHalfPaceSec: input.secondHalfPaceSec, fadeSec: fade, severity: sev)
        } else if splitDiff >= 6.0 {
            let gain = Int(splitDiff.rounded())
            pacingVerdict = .progressiveAcceleration(secondHalfPaceSec: input.secondHalfPaceSec, negativeSplitGainSec: gain)
        } else {
            let spread: Int
            if let f = input.fastestSplitPaceSec, let s = input.slowestSplitPaceSec {
                spread = abs(Int((s - f).rounded()))
            } else {
                spread = 0
            }
            pacingVerdict = .disciplinedMetronomic(paceSpreadSec: spread)
        }

        return PhysiologicalVerdicts(
            cadence: cadenceVerdict,
            cardiac: cardiacVerdict,
            verticalEconomy: verticalVerdict,
            pacing: pacingVerdict
        )
    }
}


