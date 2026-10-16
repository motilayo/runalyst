import Foundation
import HealthKit
#if canImport(WeatherKit)
import WeatherKit
#endif
#if canImport(CoreLocation)
import CoreLocation
#endif

/// Environmental and ambient conditions surrounding a run.
enum EnvironmentalModifier: String, Sendable, Codable, Equatable {
    case highHeat = "High Heat"
    case highElevation = "High Elevation Gain"
    case indoorTreadmill = "Indoor Treadmill"
    case standard = "Standard Ambient"
}

/// Thermal and ambient weather proxy engine that cross-references WeatherKit and HealthKit metadata.
enum WeatherProxyEngine {
    static let highHeatTemperatureCelsiusThreshold: Double = 22.0
    static let highHeatHumidityThresholdPercent: Double = 75.0

    static func isHighHeat(temperatureCelsius: Double?, humidity: Double?) -> Bool {
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

    static func evaluateEnvironmentalModifier(
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

    static func extractWeatherMetadata(from workout: HKWorkout) -> (temperatureCelsius: Double?, humidityPercent: Double?) {
        var tempC: Double?
        var humPercent: Double?

        if let tempQuantity = workout.metadata?[HKMetadataKeyWeatherTemperature] as? HKQuantity {
            tempC = tempQuantity.doubleValue(for: .degreeCelsius())
        }
        if let humQuantity = workout.metadata?[HKMetadataKeyWeatherHumidity] as? HKQuantity {
            let val = humQuantity.doubleValue(for: .percent())
            humPercent = val <= 1.0 ? val * 100.0 : val
        }
        return (tempC, humPercent)
    }

    #if canImport(WeatherKit) && canImport(CoreLocation)
    @available(iOS 16.0, *)
    static func fetchWeather(for coordinate: CLLocationCoordinate2D, at date: Date = Date()) async -> (temperatureCelsius: Double?, humidityPercent: Double?) {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        do {
            let weather = try await WeatherService.shared.weather(for: location)
            let tempC = weather.currentWeather.temperature.converted(to: .celsius).value
            let humPercent = weather.currentWeather.humidity * 100.0
            return (tempC, humPercent)
        } catch {
            return (nil, nil)
        }
    }
    #endif
}

/// Mathematical severity of a biomechanical or physiological deviation.
/// Guides the AI's coaching tone:
/// - minor: Encouraging tweak or subtle observation
/// - moderate: Constructive tactical training focus
/// - critical: Primary protective warning or urgent coaching cue
enum DeviationSeverity: String, Sendable, Codable, Equatable {
    case minor = "minor observation"
    case moderate = "tactical adjustment"
    case critical = "primary focus"
}

/// Deterministic root-cause evaluation of stride turnover and cadence mechanics.
enum CadenceCausalVerdict: Sendable, Equatable {
    case gradeResistance(dropSPM: Int, elevationGainM: Double, severity: DeviationSeverity)
    case lateNeuromuscularFatigue(decaySPM: Int, paceSlowdownSec: Int, severity: DeviationSeverity)
    case subFloorStridePattern(workingSPM: Int, heightFloorSPM: Int, severity: DeviationSeverity)
    case stableHeightCalibratedTurnover(workingSPM: Int)
    case strideOverLengthening(cadenceDropSPM: Int, strideIncreaseM: Double, severity: DeviationSeverity)

    var summary: String {
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
enum CardiacCausalVerdict: Sendable, Equatable {
    case thermalOrCardiovascularDrift(driftBPM: Int, durationMin: Int, severity: DeviationSeverity)
    case elevationInducedCardiacSurge(elevationGainM: Double, hrRiseBPM: Int, severity: DeviationSeverity)
    case pacingOvershootDecoupling(earlyPaceDeltaSec: Int, lateHRRiseBPM: Int, severity: DeviationSeverity)
    case thermalStrain(heatIndex: String)
    case stableCardiovascularCoupling(avgHR: Int)

    // swiftlint:disable:next identifier_name
    static func thermalStrain(HeatIndex: String) -> CardiacCausalVerdict {
        .thermalStrain(heatIndex: HeatIndex)
    }

    var summary: String {
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
enum VerticalEconomyVerdict: Sendable, Equatable {
    case excessiveVerticalDisplacement(verticalRatioPercent: Double, bounceCM: Double, severity: DeviationSeverity)
    case optimalForwardKinematics(verticalRatioPercent: Double, bounceCM: Double)
    case treadmillDeckKinematics(cadenceSPM: Int)

    var summary: String {
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
enum PacingExecutionVerdict: Sendable, Equatable {
    case earlyOverpaceFade(firstHalfPaceSec: Double, secondHalfPaceSec: Double, fadeSec: Int, severity: DeviationSeverity)
    case progressiveAcceleration(secondHalfPaceSec: Double, negativeSplitGainSec: Int)
    case disciplinedMetronomic(paceSpreadSec: Int)

    var summary: String {
        switch self {
        case .earlyOverpaceFade(let first, let second, let fade, let severity):
            let p1 = PaceFormatter.formatPace(secondsPerKilometer: first)
            let p2 = PaceFormatter.formatPace(secondsPerKilometer: second)
            return "Early over-pacing fade (faded by \(fade)s/km in second half: \(p1) -> \(p2); priority: \(severity.rawValue))"
        case .progressiveAcceleration(let second, let gain):
            let p2 = PaceFormatter.formatPace(secondsPerKilometer: second)
            return "Progressive negative split discipline (\(gain)s/km faster in second half down to \(p2))"
        case .disciplinedMetronomic(let spread):
            return "Disciplined metronomic pacing (consistent \(spread)s/km spread across all splits)"
        }
    }
}

/// Aggregated physiological diagnostic verdicts deterministically calculated by Swift.
struct PhysiologicalVerdicts: Sendable, Equatable {
    let cadence: CadenceCausalVerdict
    let cardiac: CardiacCausalVerdict
    let verticalEconomy: VerticalEconomyVerdict
    let pacing: PacingExecutionVerdict

    var promptDescription: String {
        return """
        - Cadence Turnover: \(cadence.summary)
        - Aerobic Decoupling & Drift: \(cardiac.summary)
        - Vertical Economy: \(verticalEconomy.summary)
        - Pacing Consistency: \(pacing.summary)
        """
    }
}

/// Telemetry input used by the PhysiologicalDiagnosisEngine.
struct PhysiologicalInput: Sendable {
    let workingCadence: Int
    let heightAdjustedCadenceFloor: Int
    let splits: [RunSplit]
    let elevationGainMeters: Double
    let hasCardiacDrift: Bool
    let cardiacDriftMagnitudeBPM: Int
    let durationSeconds: Double
    let verticalRatio: Double?
    let verticalOscillationCM: Double?
    let isIndoor: Bool
    let firstHalfPaceSec: Double
    let secondHalfPaceSec: Double
    let fastestSplit: RunSplit?
    let slowestSplit: RunSplit?
    let avgHeartRate: Int
    var ambientTemperatureC: Double?
    var ambientHumidity: Double?
    var environmentalModifier: EnvironmentalModifier?
}

/// Swift Physics & Biomechanics Engine that evaluates telemetry deterministically.
enum PhysiologicalDiagnosisEngine {
    static func evaluate(_ input: PhysiologicalInput) -> PhysiologicalVerdicts {
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
            WeatherProxyEngine.isHighHeat(temperatureCelsius: input.ambientTemperatureC, humidity: input.ambientHumidity)

        if input.elevationGainMeters >= 40.0 && input.hasCardiacDrift {
            let sev: DeviationSeverity = input.cardiacDriftMagnitudeBPM >= 12 ? .critical : (input.cardiacDriftMagnitudeBPM >= 7 ? .moderate : .minor)
            cardiacVerdict = .elevationInducedCardiacSurge(elevationGainM: input.elevationGainMeters, hrRiseBPM: input.cardiacDriftMagnitudeBPM, severity: sev)
        } else if isHighHeat && input.hasCardiacDrift && !input.isIndoor {
            // Outdoor Proxy (Apple WeatherKit / Weather Metadata): High heat and humidity impair evaporative cooling
            cardiacVerdict = .thermalStrain(HeatIndex: "High")
        } else if input.hasCardiacDrift {
            let durMin = max(1, Int(input.durationSeconds / 60) / 2)
            let sev: DeviationSeverity = input.cardiacDriftMagnitudeBPM >= 12 ? .critical : (input.cardiacDriftMagnitudeBPM >= 7 ? .moderate : .minor)
            let paceDiff = input.secondHalfPaceSec - input.firstHalfPaceSec // positive = 2nd half slower
            if paceDiff >= 10.0 {
                cardiacVerdict = .pacingOvershootDecoupling(earlyPaceDeltaSec: Int(paceDiff.rounded()), lateHRRiseBPM: input.cardiacDriftMagnitudeBPM, severity: sev)
            } else {
                // Indoor Proxy (No Convective Cooling): Flat deck pacing with HR drift > 8 BPM over ~30 min
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
        let splitDiff = input.firstHalfPaceSec - input.secondHalfPaceSec // positive = second half faster (negative split)
        if splitDiff <= -6.0 {
            let fade = abs(Int(splitDiff.rounded()))
            let sev: DeviationSeverity = fade >= 18 ? .critical : (fade >= 10 ? .moderate : .minor)
            pacingVerdict = .earlyOverpaceFade(firstHalfPaceSec: input.firstHalfPaceSec, secondHalfPaceSec: input.secondHalfPaceSec, fadeSec: fade, severity: sev)
        } else if splitDiff >= 6.0 {
            let gain = Int(splitDiff.rounded())
            pacingVerdict = .progressiveAcceleration(secondHalfPaceSec: input.secondHalfPaceSec, negativeSplitGainSec: gain)
        } else {
            let spread: Int
            if let f = input.fastestSplit, let s = input.slowestSplit {
                spread = abs(Int((s.paceSecondsPerKm - f.paceSecondsPerKm).rounded()))
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
