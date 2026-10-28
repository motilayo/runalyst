import Testing
@testable import RunalystCore

@Suite("Physiological Diagnosis & Run Grade Core Tests")
struct PhysiologicalDiagnosisCoreTests {

    @Test("Weather proxy detects high heat threshold")
    func testWeatherProxyHighHeat() {
        #expect(WeatherProxyCore.isHighHeat(temperatureCelsius: 23.0, humidity: 50.0))
        #expect(WeatherProxyCore.isHighHeat(temperatureCelsius: 18.0, humidity: 80.0))
        #expect(!WeatherProxyCore.isHighHeat(temperatureCelsius: 18.0, humidity: 60.0))
    }

    @Test("Environmental modifier evaluation")
    func testEnvironmentalModifier() {
        #expect(WeatherProxyCore.evaluateEnvironmentalModifier(temperatureCelsius: 18.0, humidity: 50.0, isIndoor: true, elevationGainMeters: 0) == .indoorTreadmill)
        #expect(WeatherProxyCore.evaluateEnvironmentalModifier(temperatureCelsius: 18.0, humidity: 50.0, isIndoor: false, elevationGainMeters: 55.0) == .highElevation)
        #expect(WeatherProxyCore.evaluateEnvironmentalModifier(temperatureCelsius: 24.0, humidity: 50.0, isIndoor: false, elevationGainMeters: 10.0) == .highHeat)
        #expect(WeatherProxyCore.evaluateEnvironmentalModifier(temperatureCelsius: 18.0, humidity: 50.0, isIndoor: false, elevationGainMeters: 10.0) == .standard)
    }

    @Test("Cadence causal verdict: grade resistance vs fatigue vs sub-floor")
    func testCadenceCausalVerdicts() {
        let splitsClimb = [
            PhysiologicalSplitSample(paceSecondsPerKm: 300, avgCadence: 168),
            PhysiologicalSplitSample(paceSecondsPerKm: 305, avgCadence: 167),
            PhysiologicalSplitSample(paceSecondsPerKm: 320, avgCadence: 160),
            PhysiologicalSplitSample(paceSecondsPerKm: 325, avgCadence: 158)
        ]
        let inputClimb = PhysiologicalDiagnosisInput(
            workingCadence: 163,
            heightAdjustedCadenceFloor: 155,
            splits: splitsClimb,
            elevationGainMeters: 60.0,
            hasCardiacDrift: false,
            cardiacDriftMagnitudeBPM: 0,
            durationSeconds: 1800,
            firstHalfPaceSec: 302.5,
            secondHalfPaceSec: 322.5,
            avgHeartRate: 150
        )
        let verdictsClimb = PhysiologicalDiagnosisCore.evaluate(inputClimb)
        guard case .gradeResistance(let drop, _, _) = verdictsClimb.cadence else {
            #expect(Bool(false), "Expected grade resistance")
            return
        }
        #expect(drop >= 8)

        // Sub-floor test
        let inputSubFloor = PhysiologicalDiagnosisInput(
            workingCadence: 142,
            heightAdjustedCadenceFloor: 155,
            splits: [],
            elevationGainMeters: 0.0,
            hasCardiacDrift: false,
            cardiacDriftMagnitudeBPM: 0,
            durationSeconds: 1800,
            firstHalfPaceSec: 320,
            secondHalfPaceSec: 320,
            avgHeartRate: 145
        )
        let verdictsSubFloor = PhysiologicalDiagnosisCore.evaluate(inputSubFloor)
        guard case .subFloorStridePattern(let working, let floor, _) = verdictsSubFloor.cadence else {
            #expect(Bool(false), "Expected sub floor stride pattern")
            return
        }
        #expect(working == 142)
        #expect(floor == 155)
    }

    @Test("Run grade evaluation: A vs B vs penalties")
    func testRunGradeCoreEvaluation() {
        let inputClean = RunGradeInput(
            type: "Steady Effort",
            isHard: false,
            percentZone4: 0.05,
            cadence: 168,
            paceDeltaVsBaseline: 6.0,
            hrDeltaVsBaseline: 1.0,
            cadenceFade: false,
            cardiacDrift: false
        )
        let reportClean = RunGradeCore.evaluate(inputClean)
        #expect(reportClean.grade == "A")
        #expect(!reportClean.strengths.isEmpty)

        let inputFatigued = RunGradeInput(
            type: "Tempo Run",
            isHard: true,
            percentZone4: 0.60,
            cadence: 146,
            workPaces: [280, 282, 310],
            paceDeltaVsBaseline: -8.0,
            hrDeltaVsBaseline: 8.0,
            cadenceFade: true,
            cardiacDrift: true
        )
        let reportFatigued = RunGradeCore.evaluate(inputFatigued)
        #expect(reportFatigued.grade != "A")
        #expect(reportFatigued.focus != nil)
    }
}
