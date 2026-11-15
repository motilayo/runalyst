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

    // MARK: - Midpoint SPM Extraction Tests

    @Test("Extracts cadence midpoint from ranges with hyphens and en-dashes")
    func testMidpointSPMExtractionRanges() {
        #expect(LiveMetronomeCore.midpointSPM(fromTargetString: "153-159 SPM") == 156)
        #expect(LiveMetronomeCore.midpointSPM(fromTargetString: "153–159 SPM") == 156)
        #expect(LiveMetronomeCore.midpointSPM(fromTargetString: "160–166 SPM (Adapted)") == 163)
        #expect(LiveMetronomeCore.midpointSPM(fromTargetString: "🎯 153-159 SPM") == 156)
    }

    @Test("Extracts single cadence value when string contains single SPM number")
    func testMidpointSPMExtractionSingleValue() {
        #expect(LiveMetronomeCore.midpointSPM(fromTargetString: "170 SPM") == 170)
        #expect(LiveMetronomeCore.midpointSPM(fromTargetString: "Steady 180spm") == 180)
        #expect(LiveMetronomeCore.midpointSPM(fromTargetString: "4x400m intervals at 170 SPM") == 170)
    }

    @Test("Returns nil for invalid, empty, or out-of-range cadence strings")
    func testMidpointSPMExtractionEdgeCases() {
        #expect(LiveMetronomeCore.midpointSPM(fromTargetString: nil) == nil)
        #expect(LiveMetronomeCore.midpointSPM(fromTargetString: "") == nil)
        #expect(LiveMetronomeCore.midpointSPM(fromTargetString: "   ") == nil)
        #expect(LiveMetronomeCore.midpointSPM(fromTargetString: "invalid text") == nil)
        #expect(LiveMetronomeCore.midpointSPM(fromTargetString: "50 SPM") == nil)
        #expect(LiveMetronomeCore.midpointSPM(fromTargetString: "300 SPM") == nil)
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

    // MARK: - SteppedMetronomeRamp Tests

    @Test("Gradual stepped ramp initializes at +3 SPM, holds for 10s, and steps up to goal")
    func testGradualSteppedCadenceRamp() {
        var ramp = SteppedMetronomeRamp()
        let initialCue = ramp.startCadenceBurst(currentSPM: 154, goalSPM: 160)

        #expect(initialCue != nil)
        #expect(initialCue?.mode == .cadenceMetronome)
        #expect(initialCue?.targetBPM == 157)
        #expect(initialCue?.remainingSeconds == 20)
        #expect(initialCue?.stepLabel == "157 -> 160 SPM")
        #expect(ramp.steppedTargetSPM == 157)
        #expect(ramp.goalTargetSPM == 160)
        #expect(ramp.cooldownRemainingSeconds == 0)

        // Hold 157 SPM (within 157 +/- 2) for 9 continuous seconds without reaching goal (160)
        for second in 1...9 {
            let tickCue = ramp.tick(currentSPM: 157, isEffortOnTarget: false)
            #expect(tickCue != nil)
            #expect(ramp.steppedTargetSPM == 157)
            #expect(tickCue?.targetBPM == 157)
            #expect(tickCue?.remainingSeconds == 20 - second)
            #expect(ramp.stepHeldSeconds == Double(second))
        }

        // On the 10th second, step threshold (10.0s) is fulfilled and steps up to 160 SPM
        let steppedCue = ramp.tick(currentSPM: 157, isEffortOnTarget: false)
        #expect(steppedCue != nil)
        #expect(steppedCue?.targetBPM == 160)
        #expect(steppedCue?.stepLabel == "160 SPM")
        #expect(steppedCue?.remainingSeconds == 10)
        #expect(ramp.steppedTargetSPM == 160)
        #expect(ramp.goalTargetSPM == 160)
        #expect(ramp.stepHeldSeconds == 0)
    }

    @Test("Early lock-in silences haptics and starts 240s cooldown after 5s continuous lock")
    func testEarlyLockInSilence() {
        var ramp = SteppedMetronomeRamp()
        ramp.startCadenceBurst(currentSPM: 159, goalSPM: 160)

        #expect(ramp.activeCue != nil)
        #expect(ramp.steppedTargetSPM == 160)
        #expect(ramp.goalTargetSPM == 160)

        // Maintain 160 +/- 2 SPM for 4 seconds
        for second in 1...4 {
            let tickCue = ramp.tick(currentSPM: 160, isEffortOnTarget: false)
            #expect(tickCue != nil)
            #expect(ramp.lockedSeconds == Double(second))
            #expect(ramp.activeCue != nil)
        }

        // 5th continuous second in lock zone triggers early exit before 20s burst expires
        let lockExitCue = ramp.tick(currentSPM: 160, isEffortOnTarget: false)
        #expect(lockExitCue == nil)
        #expect(ramp.activeCue == nil)
        #expect(ramp.cooldownRemainingSeconds == 240.0)
        #expect(ramp.burstElapsedSeconds == 0) // silenceBurst resets elapsed counters
    }

    @Test("20-second timeout without lock silences haptics and enforces 240s cooldown")
    func testTimeoutBackOffEnforcesCooldown() {
        var ramp = SteppedMetronomeRamp()
        ramp.startCadenceBurst(currentSPM: 150, goalSPM: 170)

        #expect(ramp.activeCue != nil)

        // Run for 19 seconds staying at 145 SPM (outside tolerance of stepped 153 and goal 170)
        for second in 1...19 {
            let tickCue = ramp.tick(currentSPM: 145, isEffortOnTarget: false)
            #expect(tickCue != nil)
            #expect(tickCue?.remainingSeconds == 20 - second)
            #expect(ramp.cooldownRemainingSeconds == 0)
        }

        // 20th second triggers burst timeout back-off
        let timeoutCue = ramp.tick(currentSPM: 145, isEffortOnTarget: false)
        #expect(timeoutCue == nil)
        #expect(ramp.activeCue == nil)
        #expect(ramp.cooldownRemainingSeconds == 240.0)

        // Attempting to start burst without bypass during cooldown is rejected
        let rejectedBurst = ramp.startCadenceBurst(currentSPM: 154, goalSPM: 160, bypassCooldown: false)
        #expect(rejectedBurst == nil)
        #expect(ramp.activeCue == nil)

        // Advance 10 seconds of cooldown
        for _ in 1...10 {
            ramp.tick(currentSPM: 160, isEffortOnTarget: false)
        }
        #expect(ramp.cooldownRemainingSeconds == 230.0)
        #expect(ramp.startCadenceBurst(currentSPM: 154, goalSPM: 160, bypassCooldown: false) == nil)
    }

    @Test("Anticipatory bypass arms fresh burst even during active cooldown")
    func testAnticipatoryPhaseBypassArmsFreshBurstDuringCooldown() {
        var ramp = SteppedMetronomeRamp()
        ramp.startCadenceBurst(currentSPM: 150, goalSPM: 160)

        // Force into cooldown
        ramp.silenceBurst(startCooldown: true)
        #expect(ramp.cooldownRemainingSeconds == 240.0)
        #expect(ramp.activeCue == nil)

        // Standard burst ignored
        #expect(ramp.startCadenceBurst(currentSPM: 154, goalSPM: 160, bypassCooldown: false) == nil)

        // Anticipatory phase transition bypasses cooldown
        let armedCue = ramp.startCadenceBurst(currentSPM: 154, goalSPM: 160, bypassCooldown: true)
        #expect(armedCue != nil)
        #expect(armedCue?.mode == .cadenceMetronome)
        #expect(armedCue?.targetBPM == 157)
        #expect(ramp.activeCue != nil)
        #expect(ramp.cooldownRemainingSeconds == 0)
        #expect(ramp.steppedTargetSPM == 157)
        #expect(ramp.goalTargetSPM == 160)
    }

    @Test("Effort down burst emits descending pulse without lowering metronome BPM")
    func testEffortDownSemanticsNeverLowersMetronomeBPM() {
        var ramp = SteppedMetronomeRamp()
        let effortCue = ramp.startEffortBurst(mode: .effortDown)

        #expect(effortCue != nil)
        #expect(effortCue?.mode == .effortDown)
        #expect(effortCue?.targetBPM == nil) // Never lowers metronome BPM below cadence
        #expect(effortCue?.pulseIntervalSeconds == 3.5)
        #expect(effortCue?.remainingSeconds == 20)
        #expect(effortCue?.stepLabel == "Ease Effort")
        #expect(ramp.steppedTargetSPM == nil)
        #expect(ramp.goalTargetSPM == nil)

        // Invalid mode rejected
        #expect(ramp.startEffortBurst(mode: .cadenceMetronome) == nil)

        // Ticking without effort on target decrements remainingSeconds
        let tick1 = ramp.tick(currentSPM: 168, isEffortOnTarget: false)
        #expect(tick1 != nil)
        #expect(tick1?.targetBPM == nil)
        #expect(tick1?.remainingSeconds == 19)
        #expect(ramp.lockedSeconds == 0)

        // 5 consecutive seconds with isEffortOnTarget == true triggers early exit
        for second in 1...4 {
            let effortTick = ramp.tick(currentSPM: 168, isEffortOnTarget: true)
            #expect(effortTick != nil)
            #expect(ramp.lockedSeconds == Double(second))
        }

        let earlyExitCue = ramp.tick(currentSPM: 168, isEffortOnTarget: true)
        #expect(earlyExitCue == nil)
        #expect(ramp.activeCue == nil)
        #expect(ramp.cooldownRemainingSeconds == 240.0)

        // Effort up burst emits "Lift Effort"
        let effortUpCue = ramp.startEffortBurst(mode: .effortUp, bypassCooldown: true)
        #expect(effortUpCue != nil)
        #expect(effortUpCue?.mode == .effortUp)
        #expect(effortUpCue?.targetBPM == nil)
        #expect(effortUpCue?.stepLabel == "Lift Effort")
    }
}
