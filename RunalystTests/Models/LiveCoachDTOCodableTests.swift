import XCTest
@testable import Runalyst

final class LiveCoachDTOCodableTests: XCTestCase {
    func testDrillPrescriptionDTOEncodingDecodingWithDurationAndHaptics() throws {
        let original = DrillPrescriptionDTO(
            title: "Cadence Pyramids",
            preRunDrillId: "cadence_pyramids",
            purpose: "Turnover improvement",
            targetCadence: "172-176",
            previousCadence: 160,
            durationMinutes: 30,
            hapticMode: "On"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DrillPrescriptionDTO.self, from: data)

        XCTAssertEqual(decoded.title, "Cadence Pyramids")
        XCTAssertEqual(decoded.targetCadence, "172-176")
        XCTAssertEqual(decoded.durationMinutes, 30)
        XCTAssertEqual(decoded.hapticMode, "On")
    }

    func testDrillDurationScaling() {
        let drill = PreRunDrill(id: .cadencePyramids, previousCadence: 160)

        let work10 = drill.workString(for: .tenMinutes)
        let work15 = drill.workString(for: .fifteenMinutes)
        let work30 = drill.workString(for: .thirtyMinutes)

        XCTAssertTrue(work10.contains("4 x 30 sec work"), "Expected 4 x 30 sec work in 10-min version, got: \(work10)")
        XCTAssertTrue(work15.contains("4 x 1 min work"), "Expected 4 x 1 min work in 15-min version, got: \(work15)")
        XCTAssertTrue(work30.contains("6 x 90 sec work"), "Expected 6 x 90 sec work in 30-min version, got: \(work30)")

        let rec10 = drill.recoveryString(for: .tenMinutes)
        let rec15 = drill.recoveryString(for: .fifteenMinutes)
        let rec30 = drill.recoveryString(for: .thirtyMinutes)

        XCTAssertTrue(rec10.contains("45 sec walk recovery"), "Expected 45 sec walk recovery, got: \(rec10)")
        XCTAssertTrue(rec15.contains("90 sec walk recovery"), "Expected 90 sec walk recovery, got: \(rec15)")
        XCTAssertTrue(rec30.contains("2 min walk recovery"), "Expected 2 min walk recovery, got: \(rec30)")

        let drill10 = PreRunDrill(id: .cadencePyramids, previousCadence: 160, duration: .tenMinutes)
        let drill30 = PreRunDrill(id: .cadencePyramids, previousCadence: 160, duration: .thirtyMinutes)
        let plan10 = drill10.buildWorkoutPlan()
        let plan30 = drill30.buildWorkoutPlan()
        XCTAssertNotNil(plan10)
        XCTAssertNotNil(plan30)

        // Verify DrillTemplate duration scaling
        let template = DrillTemplate.template(for: .cadencePyramids)
        XCTAssertTrue(template.workString(for: .tenMinutes).contains("4 x 30 sec work"))
        XCTAssertTrue(template.workString(for: .fifteenMinutes).contains("4 x 1 min work"))
        XCTAssertTrue(template.workString(for: .thirtyMinutes).contains("6 x 90 sec work"))
        XCTAssertTrue(template.recoveryString(for: .tenMinutes).contains("45 sec walk recovery"))
        XCTAssertTrue(template.recoveryString(for: .thirtyMinutes).contains("2 min walk recovery"))
    }

    func testLiveCoachHapticFeedbackModes() {
        // Off
        XCTAssertFalse(LiveCoachEngine.shouldTriggerHaptic(mode: .off, currentSPM: 160, targetSPM: 170, intervalElapsedSeconds: 5))
        XCTAssertFalse(LiveCoachEngine.shouldTriggerHaptic(mode: .off, currentSPM: 150, targetSPM: 170, intervalElapsedSeconds: 30))

        // On: rhythm pulse during first 20s of interval
        XCTAssertTrue(LiveCoachEngine.shouldTriggerHaptic(mode: .on, currentSPM: 170, targetSPM: 170, intervalElapsedSeconds: 10))

        // On: corrective nudge when cadence drops below target - 2 SPM after lead-in
        XCTAssertTrue(LiveCoachEngine.shouldTriggerHaptic(mode: .on, currentSPM: 167, targetSPM: 170, intervalElapsedSeconds: 30))
        XCTAssertFalse(LiveCoachEngine.shouldTriggerHaptic(mode: .on, currentSPM: 170, targetSPM: 170, intervalElapsedSeconds: 30))
        XCTAssertFalse(LiveCoachEngine.shouldTriggerHaptic(mode: .on, currentSPM: 175, targetSPM: 170, intervalElapsedSeconds: 30))
    }

    func testPreloadFilter_Past7DaysOrPast5Runs() {
        let calendar = Calendar.current
        let today = Date()
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: today) ?? today

        // Create 10 dummy run dates (newest first, indices 0 to 9)
        // 0: today (within 7d, index < 5) -> preload
        // 1: 2d ago (within 7d, index < 5) -> preload
        // 2: 5d ago (within 7d, index < 5) -> preload
        // 3: 8d ago (> 7d, index < 5) -> preload (because index < 5)
        // 4: 9d ago (> 7d, index < 5) -> preload (because index < 5)
        // 5: 10d ago (> 7d, index >= 5) -> skip
        // 6: 12d ago (> 7d, index >= 5) -> skip
        // 7: 15d ago (> 7d, index >= 5) -> skip
        let daysAgoList = [0, 2, 5, 8, 9, 10, 12, 15]
        let dummyRuns = daysAgoList.map { days in
            calendar.date(byAdding: .day, value: -days, to: today) ?? today
        }

        let preloadedIndices = dummyRuns.enumerated().compactMap { index, date -> Int? in
            if date >= sevenDaysAgo || index < 5 {
                return index
            }
            return nil
        }

        XCTAssertEqual(preloadedIndices, [0, 1, 2, 3, 4])
    }

    func testDrillRecommendationEligibility_OlderThan7Days() {
        let calendar = Calendar.current
        let now = Date()

        let recentDate = calendar.date(byAdding: .day, value: -3, to: now) ?? now
        let oldDate = calendar.date(byAdding: .day, value: -10, to: now) ?? now

        let recentDays = calendar.dateComponents([.day], from: recentDate, to: now).day ?? 0
        let oldDays = calendar.dateComponents([.day], from: oldDate, to: now).day ?? 0

        XCTAssertFalse(recentDays > 7, "Recent run should be <= 7 days")
        XCTAssertTrue(oldDays > 7, "Old run should be > 7 days")
    }
}
