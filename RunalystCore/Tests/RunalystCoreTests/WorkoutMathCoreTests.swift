import Foundation
@testable import RunalystCore
import Testing

@Suite("Workout Math Core Tests")
struct WorkoutMathCoreTests {

    @Test("Calculates pace delta and speed change accurately")
    func testPaceDelta() {
        let result = WorkoutMathCalculatorCore.calculate(
            operation: "pace_delta",
            valueA: "4:30/km",
            valueB: "5:00/km"
        )

        #expect(result.delta == "-30 s/km")
        #expect(result.deltaNumeric == -30.0)
        #expect(result.summary.contains("faster"))
    }

    @Test("Calculates distance delta accurately")
    func testDistanceDelta() {
        let result = WorkoutMathCalculatorCore.calculate(
            operation: "distance_delta",
            valueA: "10.00 km",
            valueB: "8.00 km"
        )

        #expect(result.delta == "+2.00 km")
        #expect(result.deltaNumeric == 2.0)
    }

    @Test("Calculates heart rate delta accurately")
    func testHeartRateDelta() {
        let result = WorkoutMathCalculatorCore.calculate(
            operation: "heart_rate_delta",
            valueA: "165 BPM",
            valueB: "155 BPM"
        )

        #expect(result.delta == "+10 BPM")
        #expect(result.deltaNumeric == 10.0)
    }
}
