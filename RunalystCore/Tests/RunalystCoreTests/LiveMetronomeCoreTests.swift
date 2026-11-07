import Foundation
@testable import RunalystCore
import Testing

@Suite("Live Metronome Core Tests")
struct LiveMetronomeCoreTests {

    // MARK: - Prescription Parsing Tests

    @Test("Parses standard prescription format and computes target cadence band")
    func testParseStandardPrescription() {
        let parsed = LiveMetronomeCore.parsePrescription("4x400m intervals", targetSPM: 170)

        #expect(parsed != nil)
        #expect(parsed?.iterations == 4)
        #expect(parsed?.distanceMeters == 400.0)
        #expect(parsed?.cadenceLowerBound == 165.0)
        #expect(parsed?.cadenceUpperBound == 175.0)
        #expect(parsed?.cadenceRange == 165.0...175.0)
    }

    @Test("Parses case-insensitive uppercase prescription correctly")
    func testParseCaseInsensitivePrescription() {
        let parsed = LiveMetronomeCore.parsePrescription("6X200M strides", targetSPM: 180)

        #expect(parsed != nil)
        #expect(parsed?.iterations == 6)
        #expect(parsed?.distanceMeters == 200.0)
        #expect(parsed?.cadenceLowerBound == 175.0)
        #expect(parsed?.cadenceUpperBound == 185.0)
        #expect(parsed?.cadenceRange == 175.0...185.0)
    }

    @Test("Clamps lower cadence bound to zero for very low target SPM")
    func testParseLowTargetSPMClamping() {
        let parsed = LiveMetronomeCore.parsePrescription("8x100m warmup", targetSPM: 3)

        #expect(parsed != nil)
        #expect(parsed?.iterations == 8)
        #expect(parsed?.distanceMeters == 100.0)
        #expect(parsed?.cadenceLowerBound == 0.0)
        #expect(parsed?.cadenceUpperBound == 8.0)
        #expect(parsed?.cadenceRange == 0.0...8.0)
    }

    @Test("Returns nil for malformed or non-positive prescription strings")
    func testParseInvalidPrescriptionStrings() {
        #expect(LiveMetronomeCore.parsePrescription("invalid", targetSPM: 170) == nil)
        #expect(LiveMetronomeCore.parsePrescription("", targetSPM: 170) == nil)
        #expect(LiveMetronomeCore.parsePrescription("4x", targetSPM: 170) == nil)
        #expect(LiveMetronomeCore.parsePrescription("400m", targetSPM: 170) == nil)
        #expect(LiveMetronomeCore.parsePrescription("0x400m", targetSPM: 170) == nil)
        #expect(LiveMetronomeCore.parsePrescription("4x0m", targetSPM: 170) == nil)
    }

    @Test("Directly initializes ParsedIntervalPrescription and verifies Equatable")
    func testParsedIntervalPrescriptionDirectInit() {
        let prescription1 = ParsedIntervalPrescription(
            iterations: 5,
            distanceMeters: 500.0,
            cadenceLowerBound: 160.0,
            cadenceUpperBound: 170.0
        )
        let prescription2 = ParsedIntervalPrescription(
            iterations: 5,
            distanceMeters: 500.0,
            cadenceLowerBound: 160.0,
            cadenceUpperBound: 170.0
        )
        let prescription3 = ParsedIntervalPrescription(
            iterations: 4,
            distanceMeters: 500.0,
            cadenceLowerBound: 160.0,
            cadenceUpperBound: 170.0
        )

        #expect(prescription1 == prescription2)
        #expect(prescription1 != prescription3)
        #expect(prescription1.cadenceRange == 160.0...170.0)
    }

    // MARK: - Beat Interval Tests

    @Test("Calculates beat intervals accurately for valid SPM values")
    func testBeatIntervalCalculation() {
        let interval180 = LiveMetronomeCore.beatIntervalSeconds(forTargetSPM: 180)
        #expect(interval180 != nil)
        if let interval180 {
            #expect(abs(interval180 - (60.0 / 180.0)) < 0.0001)
        }

        let interval150 = LiveMetronomeCore.beatIntervalSeconds(forTargetSPM: 150)
        #expect(interval150 != nil)
        if let interval150 {
            #expect(abs(interval150 - 0.4) < 0.0001)
        }

        let interval120 = LiveMetronomeCore.beatIntervalSeconds(forTargetSPM: 120)
        #expect(interval120 != nil)
        if let interval120 {
            #expect(abs(interval120 - 0.5) < 0.0001)
        }
    }

    @Test("Returns nil for non-positive SPM values")
    func testBeatIntervalNonPositive() {
        #expect(LiveMetronomeCore.beatIntervalSeconds(forTargetSPM: 0) == nil)
        #expect(LiveMetronomeCore.beatIntervalSeconds(forTargetSPM: -10) == nil)
    }

    // MARK: - Corrective Haptic Trigger Tests

    @Test("Evaluates corrective haptic triggers based on cadence drop")
    func testCorrectiveHapticTrigger() {
        #expect(LiveMetronomeCore.shouldTriggerCorrectiveHaptic(currentSPM: 169, targetSPM: 170) == true)
        #expect(LiveMetronomeCore.shouldTriggerCorrectiveHaptic(currentSPM: 170, targetSPM: 170) == false)
        #expect(LiveMetronomeCore.shouldTriggerCorrectiveHaptic(currentSPM: 171, targetSPM: 170) == false)
    }

    // MARK: - Duty-Cycled Haptic Tests

    @Test("Suppresses haptics unconditionally when disabled")
    func testDutyCycledHapticWhenDisabled() {
        let result1 = LiveMetronomeCore.shouldTriggerDutyCycledHaptic(
            isEnabled: false,
            currentSPM: 150,
            targetSPM: 170,
            intervalElapsedSeconds: 5.0
        )
        #expect(result1 == false)

        let result2 = LiveMetronomeCore.shouldTriggerDutyCycledHaptic(
            isEnabled: false,
            currentSPM: 150,
            targetSPM: 170,
            intervalElapsedSeconds: 30.0
        )
        #expect(result2 == false)
    }

    @Test("Pulses during the initial lock-in window regardless of target match")
    func testDutyCycledHapticInitialLockInWindow() {
        // At start of interval
        let resultStart = LiveMetronomeCore.shouldTriggerDutyCycledHaptic(
            isEnabled: true,
            currentSPM: 170,
            targetSPM: 170,
            intervalElapsedSeconds: 0.0
        )
        #expect(resultStart == true)

        // Mid-window
        let resultMid = LiveMetronomeCore.shouldTriggerDutyCycledHaptic(
            isEnabled: true,
            currentSPM: 175,
            targetSPM: 170,
            intervalElapsedSeconds: 15.0
        )
        #expect(resultMid == true)

        // Exactly at boundary of lock-in window (20.0s)
        let resultBoundary = LiveMetronomeCore.shouldTriggerDutyCycledHaptic(
            isEnabled: true,
            currentSPM: 170,
            targetSPM: 170,
            intervalElapsedSeconds: 20.0
        )
        #expect(resultBoundary == true)
    }

    @Test("Enforces drift tolerance after initial lock-in window has elapsed")
    func testDutyCycledHapticPostLockInWindow() {
        // 20.1 seconds elapsed: on target -> false
        let onTarget = LiveMetronomeCore.shouldTriggerDutyCycledHaptic(
            isEnabled: true,
            currentSPM: 170,
            targetSPM: 170,
            intervalElapsedSeconds: 20.1
        )
        #expect(onTarget == false)

        // 20.1 seconds elapsed: target - 2 (168 vs 170) -> within tolerance -> false
        let withinTolerance = LiveMetronomeCore.shouldTriggerDutyCycledHaptic(
            isEnabled: true,
            currentSPM: 168,
            targetSPM: 170,
            intervalElapsedSeconds: 20.1
        )
        #expect(withinTolerance == false)

        // 20.1 seconds elapsed: target - 3 (167 vs 170) -> beyond tolerance -> true
        let beyondTolerance = LiveMetronomeCore.shouldTriggerDutyCycledHaptic(
            isEnabled: true,
            currentSPM: 167,
            targetSPM: 170,
            intervalElapsedSeconds: 20.1
        )
        #expect(beyondTolerance == true)

        // 45.0 seconds elapsed: target - 2 -> false
        let laterWithin = LiveMetronomeCore.shouldTriggerDutyCycledHaptic(
            isEnabled: true,
            currentSPM: 168,
            targetSPM: 170,
            intervalElapsedSeconds: 45.0
        )
        #expect(laterWithin == false)

        // 45.0 seconds elapsed: target - 3 -> true
        let laterBeyond = LiveMetronomeCore.shouldTriggerDutyCycledHaptic(
            isEnabled: true,
            currentSPM: 167,
            targetSPM: 170,
            intervalElapsedSeconds: 45.0
        )
        #expect(laterBeyond == true)
    }

    @Test("Verifies shouldTriggerHaptic alias produces identical results")
    func testShouldTriggerHapticAlias() {
        let aliasInWindow = LiveMetronomeCore.shouldTriggerHaptic(
            isEnabled: true,
            currentSPM: 169,
            targetSPM: 170,
            intervalElapsedSeconds: 15.0
        )
        #expect(aliasInWindow == true)

        let aliasPostWindowSteady = LiveMetronomeCore.shouldTriggerHaptic(
            isEnabled: true,
            currentSPM: 168,
            targetSPM: 170,
            intervalElapsedSeconds: 25.0
        )
        #expect(aliasPostWindowSteady == false)

        let aliasPostWindowDrift = LiveMetronomeCore.shouldTriggerHaptic(
            isEnabled: true,
            currentSPM: 166,
            targetSPM: 170,
            intervalElapsedSeconds: 25.0
        )
        #expect(aliasPostWindowDrift == true)
    }
}
