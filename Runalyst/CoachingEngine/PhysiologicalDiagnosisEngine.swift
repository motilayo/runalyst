import Foundation
import HealthKit
#if canImport(WeatherKit)
import WeatherKit
#endif
#if canImport(CoreLocation)
import CoreLocation
#endif
import RunalystCore

public typealias EnvironmentalModifier = RunalystCore.EnvironmentalModifier
public typealias DeviationSeverity = RunalystCore.DeviationSeverity
public typealias CadenceCausalVerdict = RunalystCore.CadenceCausalVerdict
public typealias CardiacCausalVerdict = RunalystCore.CardiacCausalVerdict
public typealias VerticalEconomyVerdict = RunalystCore.VerticalEconomyVerdict
public typealias PacingExecutionVerdict = RunalystCore.PacingExecutionVerdict
public typealias PhysiologicalFinding = RunalystCore.PhysiologicalFinding
public typealias PhysiologicalVerdicts = RunalystCore.PhysiologicalVerdicts

/// Thermal and ambient weather proxy engine that cross-references WeatherKit and HealthKit metadata.
enum WeatherProxyEngine {
    static let highHeatTemperatureCelsiusThreshold: Double = WeatherProxyCore.highHeatTemperatureCelsiusThreshold
    static let highHeatHumidityThresholdPercent: Double = WeatherProxyCore.highHeatHumidityThresholdPercent

    static func isHighHeat(temperatureCelsius: Double?, humidity: Double?) -> Bool {
        WeatherProxyCore.isHighHeat(temperatureCelsius: temperatureCelsius, humidity: humidity)
    }

    static func evaluateEnvironmentalModifier(
        temperatureCelsius: Double?,
        humidity: Double?,
        isIndoor: Bool,
        elevationGainMeters: Double
    ) -> EnvironmentalModifier {
        WeatherProxyCore.evaluateEnvironmentalModifier(
            temperatureCelsius: temperatureCelsius,
            humidity: humidity,
            isIndoor: isIndoor,
            elevationGainMeters: elevationGainMeters
        )
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
        let splitSamples = input.splits.map {
            PhysiologicalSplitSample(paceSecondsPerKm: $0.paceSecondsPerKm, avgCadence: $0.avgCadence)
        }
        let coreInput = PhysiologicalDiagnosisInput(
            workingCadence: input.workingCadence,
            heightAdjustedCadenceFloor: input.heightAdjustedCadenceFloor,
            splits: splitSamples,
            elevationGainMeters: input.elevationGainMeters,
            hasCardiacDrift: input.hasCardiacDrift,
            cardiacDriftMagnitudeBPM: input.cardiacDriftMagnitudeBPM,
            durationSeconds: input.durationSeconds,
            verticalRatio: input.verticalRatio,
            verticalOscillationCM: input.verticalOscillationCM,
            isIndoor: input.isIndoor,
            firstHalfPaceSec: input.firstHalfPaceSec,
            secondHalfPaceSec: input.secondHalfPaceSec,
            fastestSplitPaceSec: input.fastestSplit?.paceSecondsPerKm,
            slowestSplitPaceSec: input.slowestSplit?.paceSecondsPerKm,
            avgHeartRate: input.avgHeartRate,
            ambientTemperatureC: input.ambientTemperatureC,
            ambientHumidity: input.ambientHumidity,
            environmentalModifier: input.environmentalModifier
        )
        return PhysiologicalDiagnosisCore.evaluate(coreInput)
    }
}
