import Foundation
@testable import RunalystCore
import Testing

@Suite("Adaptive Pacing Core Tests")
struct AdaptivePacingCoreTests {

    private let standardProfile = AthleteCalibrationProfile(
        maxHR: 190.0,
        restingHR: 52.0,
        powerToHRTopQuartile: 2.50,
        isFallback: false
    )

    private let standardIntent = PacingSessionIntent(
        targetPaceSecondsPerKm: 300,
        intent: .steady,
        subjectiveDistress: false,
        validForDay: "2026-11-09"
    )

    // MARK: - Determinism & Calibration Tests

    @Test("Determinism across replays: identical ticks emit identical events and display snapshots")
    func testDeterminismAcrossReplays() {
        var coreA = AdaptivePacingCore(profile: standardProfile, intent: standardIntent, location: .outdoor)
        var coreB = AdaptivePacingCore(profile: standardProfile, intent: standardIntent, location: .outdoor)

        let ticks = PacingSessionFixtures.makeSteadyEasyRun(durationSeconds: 1200, seedNoise: 123)

        for tick in ticks {
            let resA = coreA.ingest(tick)
            let resB = coreB.ingest(tick)

            #expect(resA.events == resB.events)
            #expect(resA.display == resB.display)
        }
    }

    @Test("Normal calibration: steady sensors complete calibration at tick 600 and enter tracking")
    func testNormalCalibration() {
        // High topQuartile ensures surge is not triggered at tick 610
        let steadyProfile = AthleteCalibrationProfile(
            maxHR: 190.0,
            restingHR: 52.0,
            powerToHRTopQuartile: 2.50,
            isFallback: false
        )
        var core = AdaptivePacingCore(profile: steadyProfile, intent: standardIntent, location: .outdoor)
        let ticks = PacingSessionFixtures.makeSteadyEasyRun(durationSeconds: 610)

        var calibrationCompleteEvent: PacingEvent?
        for tick in ticks {
            let result = core.ingest(tick)
            for event in result.events {
                if case .calibrationComplete = event {
                    calibrationCompleteEvent = event
                }
            }
        }

        #expect(calibrationCompleteEvent != nil)
        if case .calibrationComplete(let target, let enabled) = calibrationCompleteEvent {
            #expect(target == 300)
            #expect(enabled == true)
        }

        // Display state at tick 611 reflects tracking
        let latest = core.ingest(TelemetryTick(elapsedSeconds: 611, heartRateBPM: 145, speedMetersPerSecond: 3.33))
        #expect(latest.display.state == .tracking)
        #expect(latest.display.adjustmentsEnabled == true)
    }

    @Test("Persistent sensor failure: 50% HR coverage extends to 900 s and enters monitor-only tracking")
    func testPersistentSensorFailure() {
        var core = AdaptivePacingCore(profile: standardProfile, intent: standardIntent, location: .outdoor)
        let ticks = PacingSessionFixtures.makeSensorDropout(durationSeconds: 1000, dropoutProbability: 0.50)

        var calibrationCompleteEvent: PacingEvent?
        var adjustments: [PacingEvent] = []

        for tick in ticks {
            let result = core.ingest(tick)
            for event in result.events {
                switch event {
                case .calibrationComplete:
                    calibrationCompleteEvent = event
                case .surge, .recover:
                    adjustments.append(event)
                default:
                    break
                }
            }
        }

        #expect(calibrationCompleteEvent != nil)
        if case .calibrationComplete(let target, let enabled) = calibrationCompleteEvent {
            #expect(target == 300)
            #expect(enabled == false, "Adjustments must be disabled after persistent sensor failure")
        }

        #expect(adjustments.isEmpty, "Zero surge or recover adjustments allowed in monitor-only mode")
    }

    // MARK: - Hysteresis & Damping Tests

    @Test("Hysteresis: 90 s refractory period blocks oscillating adjustments")
    func testRefractoryPeriodCooldown() {
        var core = AdaptivePacingCore(profile: standardProfile, intent: standardIntent, location: .outdoor)
        for tick in PacingSessionFixtures.makeSteadyEasyRun(durationSeconds: 600) { _ = core.ingest(tick) }

        // Trigger recover by sustained ceiling starting at tick 610 with scaled power (280 W)
        var firstRecoverTick = 0
        for s in 601...700 {
            let hr: Double = (s >= 610) ? 185.0 : 145.0
            let power: Double = (s >= 610) ? 280.0 : 220.0
            let tick = TelemetryTick(
                elapsedSeconds: TimeInterval(s),
                heartRateBPM: hr,
                speedMetersPerSecond: 3.33,
                powerWatts: power,
                cadenceSPM: 168.0,
                groundContactTimeMs: 240.0
            )
            let res = core.ingest(tick)
            if res.events.contains(where: { if case .recover = $0 { return true }; return false }) {
                firstRecoverTick = s
                break
            }
        }
        #expect(firstRecoverTick > 0)

        // Ticks during refractory period (next 89 seconds) must emit zero adjustments
        var refractoryAdjustments: [PacingEvent] = []
        let refractoryEnd = firstRecoverTick + 89
        for s in (firstRecoverTick + 1)...refractoryEnd {
            let tick = TelemetryTick(
                elapsedSeconds: TimeInterval(s),
                heartRateBPM: 185.0,
                speedMetersPerSecond: 3.33,
                powerWatts: 280.0,
                cadenceSPM: 168.0,
                groundContactTimeMs: 240.0
            )
            let res = core.ingest(tick)
            refractoryAdjustments.append(contentsOf: res.events.filter {
                switch $0 {
                case .recover, .surge: return true
                default: return false
                }
            })
        }
        #expect(refractoryAdjustments.isEmpty, "Refractory period must suppress adjustments")
    }

    @Test("Cumulative cap: 12% ceiling stops adjustments at 336 s/km for 300 s/km target")
    func testCumulativeCapTruncation() {
        var core = AdaptivePacingCore(profile: standardProfile, intent: standardIntent, location: .outdoor)
        for tick in PacingSessionFixtures.makeSteadyEasyRun(durationSeconds: 600) { _ = core.ingest(tick) }

        var targetSequence: [Int] = []
        var currentTick = 601

        // Repeatedly trigger adjustments across 5 cycles
        for _ in 1...5 {
            // Wait out 90s refractory plus 10s evaluation
            for _ in 0..<100 {
                let tick = TelemetryTick(
                    elapsedSeconds: TimeInterval(currentTick),
                    heartRateBPM: 185.0,
                    speedMetersPerSecond: 3.33,
                    powerWatts: 220.0,
                    cadenceSPM: 168.0,
                    groundContactTimeMs: 240.0
                )
                let res = core.ingest(tick)
                for event in res.events {
                    if case .recover(_, let newTarget, _) = event {
                        targetSequence.append(newTarget)
                    }
                }
                currentTick += 1
            }
        }

        // Expected progression: 310, 320, 330, 336 (cap is 300 * 1.12 = 336), then nothing
        #expect(targetSequence == [310, 320, 330, 336])
    }

    @Test("Back-on-target event emitted once when filtered pace enters tolerance band")
    func testBackOnTargetEvent() {
        var core = AdaptivePacingCore(profile: standardProfile, intent: standardIntent, location: .outdoor)
        for tick in PacingSessionFixtures.makeSteadyEasyRun(durationSeconds: 600) { _ = core.ingest(tick) }

        // Trigger recover to 310 s/km
        var recoverFired = false
        var currentTick = 601
        while !recoverFired && currentTick < 700 {
            let tick = TelemetryTick(
                elapsedSeconds: TimeInterval(currentTick),
                heartRateBPM: 185.0,
                speedMetersPerSecond: 3.33,
                powerWatts: 220.0,
                cadenceSPM: 168.0,
                groundContactTimeMs: 240.0
            )
            let res = core.ingest(tick)
            if res.events.contains(where: { if case .recover = $0 { return true }; return false }) {
                recoverFired = true
            }
            currentTick += 1
        }
        #expect(recoverFired == true)

        // Runner slows down to 310 s/km (speed = 1000 / 310 = 3.225 m/s) with safe HR
        var backOnTargetCount = 0
        for _ in 0..<60 {
            let tick = TelemetryTick(
                elapsedSeconds: TimeInterval(currentTick),
                heartRateBPM: 145.0,
                speedMetersPerSecond: 3.225,
                powerWatts: 210.0,
                cadenceSPM: 168.0,
                groundContactTimeMs: 240.0
            )
            let res = core.ingest(tick)
            if res.events.contains(where: { if case .backOnTarget = $0 { return true }; return false }) {
                backOnTargetCount += 1
            }
            currentTick += 1
        }

        #expect(backOnTargetCount == 1, "backOnTarget must be emitted exactly once upon entering band")
    }

    // MARK: - Crucible Timing Test (Task 3.5)

    @Test("Crucible timing test: 7,200 ticks 2-hour replay achieves median ingest < 0.1 ms")
    func testCruciblePerformance7200Ticks() {
        var core = AdaptivePacingCore(profile: standardProfile, intent: standardIntent, location: .outdoor)
        let ticks = PacingSessionFixtures.makeLongRun(tickCount: 7200, targetPaceSecPerKm: 300, heartRate: 145.0)

        var durationsMicroseconds: [Double] = []
        durationsMicroseconds.reserveCapacity(ticks.count)

        let clock = ContinuousClock()
        for tick in ticks {
            let elapsed = clock.measure {
                _ = core.ingest(tick)
            }
            let microseconds = Double(elapsed.components.attoseconds) / 1_000_000_000_000.0
                + Double(elapsed.components.seconds) * 1_000_000.0
            durationsMicroseconds.append(microseconds)
        }

        durationsMicroseconds.sort()
        let medianMicroseconds = durationsMicroseconds[durationsMicroseconds.count / 2]

        // 0.1 ms = 100.0 microseconds
        #expect(medianMicroseconds < 100.0, "Median ingest must be under 100 microseconds (0.1 ms), was \(medianMicroseconds) µs")
    }

    // MARK: - Presentation Tokens & Feedback Spec Tests

    @Test("Feedback specs: deterministically maps events to haptics, voice cues, and accent tokens")
    func testFeedbackSpecs() {
        let surge = PacingEvent.surge(deltaSecondsPerKm: 5, newTargetSecondsPerKm: 295)
        let surgeSpec = surge.feedbackSpec
        #expect(surgeSpec.haptic == .ascendingDoublePulse)
        #expect(surgeSpec.voiceCueText == "Efficiency is high—you've got reserves. Nudging target pace to 4:55.")
        #expect(surgeSpec.accentToken == .surgeTeal)

        let recoverForm = PacingEvent.recover(deltaSecondsPerKm: 9, newTargetSecondsPerKm: 309, reason: .formBreakdown)
        let formSpec = recoverForm.feedbackSpec
        #expect(formSpec.haptic == .descendingDoublePulse)
        #expect(formSpec.voiceCueText == "Cardiac drift detected. Dialing target back to 5:09 to protect your aerobic zone.")
        #expect(formSpec.accentToken == .recoverAmber)

        let recoverHR = PacingEvent.recover(deltaSecondsPerKm: 10, newTargetSecondsPerKm: 310, reason: .heartRateCeiling)
        let hrSpec = recoverHR.feedbackSpec
        #expect(hrSpec.haptic == .descendingDoublePulse)
        #expect(hrSpec.voiceCueText == "Cardiac drift detected. Dialing target back to 5:10 to protect your aerobic zone.")
        #expect(hrSpec.accentToken == .recoverAmber)

        let backOnTarget = PacingEvent.backOnTarget
        let botSpec = backOnTarget.feedbackSpec
        #expect(botSpec.haptic == .success)
        #expect(botSpec.voiceCueText == nil)
        #expect(botSpec.accentToken == .neutral)
    }

    @Test("Display state: initial factory and presentation computed properties format accurately")
    func testDisplayStatePresentationProperties() {
        let initial = PacingDisplayState.initial(targetPaceSecondsPerKm: 300, adjustmentsEnabled: true)
        #expect(initial.targetPaceFormatted == "5:00 /km")
        #expect(initial.filteredPaceFormatted == "--:--")
        #expect(initial.stateTitle == "Calibrating")
        #expect(initial.accentToken == .neutral)
        #expect(initial.refractoryCountdownFormatted == "")

        // Surge state display
        let surgeDisplay = PacingDisplayState(
            state: .surge,
            targetPaceSecondsPerKm: 295,
            filteredPaceSecondsPerKm: 294,
            filteredHeartRateBPM: 155,
            deviation: .onTarget,
            refractorySecondsRemaining: 90,
            lastReason: nil,
            adjustmentsEnabled: true,
            targetPaceFormatted: "4:55 /km",
            filteredPaceFormatted: "4:54 /km",
            filteredHeartRateFormatted: "155 BPM",
            deviationTitle: "On Target",
            calibrationProgress: nil,
            calibrationProgressFormatted: "--",
            refractoryProgress: 1.0
        )
        #expect(surgeDisplay.stateTitle == "Surge")
        #expect(surgeDisplay.accentToken == .electricBlue)
        #expect(surgeDisplay.refractoryCountdownFormatted == "1:30")

        // Recover state display with form breakdown
        let recoverDisplay = PacingDisplayState(
            state: .recover,
            targetPaceSecondsPerKm: 310,
            filteredPaceSecondsPerKm: 305,
            filteredHeartRateBPM: 160,
            deviation: .tooFast,
            refractorySecondsRemaining: 45,
            lastReason: .formBreakdown,
            adjustmentsEnabled: true,
            targetPaceFormatted: "5:10 /km",
            filteredPaceFormatted: "5:05 /km",
            filteredHeartRateFormatted: "160 BPM",
            deviationTitle: "Too Fast",
            calibrationProgress: nil,
            calibrationProgressFormatted: "--",
            refractoryProgress: 0.5
        )
        #expect(recoverDisplay.stateTitle == "Recover")
        #expect(recoverDisplay.accentToken == .vibrantGreen)
        #expect(recoverDisplay.refractoryCountdownFormatted == "0:45")
    }

    // MARK: - Pace Drift Alert Tests

    @Test("Pace drift alert: triggers after 12 consecutive seconds of .tooSlow and enforces 30s cooldown")
    func testPaceDriftAlertDebounceAndCooldown() {
        var core = AdaptivePacingCore(profile: standardProfile, intent: standardIntent, location: .outdoor)
        // Warm up and calibrate through 600s at target pace 5:00/km (3.333 m/s)
        for tick in PacingSessionFixtures.makeSteadyEasyRun(durationSeconds: 600) {
            _ = core.ingest(tick)
        }

        var driftEvents: [PacingEvent] = []
        var currentTick = 601

        // 1. Advance until the filtered short window enters .tooSlow (pace < target - tolerance)
        while currentTick < 650 {
            let tick = TelemetryTick(
                elapsedSeconds: TimeInterval(currentTick),
                heartRateBPM: 145.0,
                speedMetersPerSecond: 2.50 // ~6:40 /km -> clearly slow
            )
            let result = core.ingest(tick)
            currentTick += 1
            if result.display.deviation == .tooSlow {
                // First tick in .tooSlow
                break
            }
        }
        #expect(driftEvents.isEmpty, "First tick in .tooSlow must not emit alert")

        // 2. Next 10 ticks in .tooSlow (total 11 seconds in .tooSlow; 11s < 12s debounce)
        for _ in 1...10 {
            let tick = TelemetryTick(
                elapsedSeconds: TimeInterval(currentTick),
                heartRateBPM: 145.0,
                speedMetersPerSecond: 2.50
            )
            let result = core.ingest(tick)
            currentTick += 1
            for event in result.events {
                if case .paceDrift = event {
                    driftEvents.append(event)
                }
            }
        }
        #expect(driftEvents.isEmpty, "Debounce duration is 12s; 11s must not trigger a drift alert")

        // 3. 12th consecutive second in .tooSlow -> must emit .paceDrift(.tooSlow)
        let tick12 = TelemetryTick(
            elapsedSeconds: TimeInterval(currentTick),
            heartRateBPM: 145.0,
            speedMetersPerSecond: 2.50
        )
        let res12 = core.ingest(tick12)
        currentTick += 1
        for event in res12.events {
            if case .paceDrift(let deviation, let delta) = event {
                #expect(deviation == .tooSlow)
                #expect(delta > 0)
                driftEvents.append(event)
            }
        }
        #expect(driftEvents.count == 1, "12th consecutive second in .tooSlow must emit exactly one .paceDrift alert")

        // 4. Next 25 ticks continue in .tooSlow. Cooldown is 30s, so alerts must be suppressed
        for _ in 1...25 {
            let tick = TelemetryTick(
                elapsedSeconds: TimeInterval(currentTick),
                heartRateBPM: 145.0,
                speedMetersPerSecond: 2.50
            )
            let result = core.ingest(tick)
            currentTick += 1
            for event in result.events {
                if case .paceDrift = event {
                    driftEvents.append(event)
                }
            }
        }
        #expect(driftEvents.count == 1, "Alert must be suppressed during 30s cooldown interval")

        // 5. Remaining 5 ticks of cooldown (completing 30s cooldown) + next tick fires second alert
        for _ in 1...5 {
            let tick = TelemetryTick(
                elapsedSeconds: TimeInterval(currentTick),
                heartRateBPM: 145.0,
                speedMetersPerSecond: 2.50
            )
            let result = core.ingest(tick)
            currentTick += 1
            for event in result.events {
                if case .paceDrift = event {
                    driftEvents.append(event)
                }
            }
        }
        #expect(driftEvents.count == 2, "After 30s cooldown expires with continuous .tooSlow, a second alert must fire")
    }

    @Test("Pace drift alert: momentary fluctuation under 12 seconds resets without alert")
    func testPaceDriftResetOnTarget() {
        var core = AdaptivePacingCore(profile: standardProfile, intent: standardIntent, location: .outdoor)
        for tick in PacingSessionFixtures.makeSteadyEasyRun(durationSeconds: 600) {
            _ = core.ingest(tick)
        }

        // 6 seconds slow
        for s in 601...606 {
            let tick = TelemetryTick(elapsedSeconds: TimeInterval(s), heartRateBPM: 145.0, speedMetersPerSecond: 2.94)
            let res = core.ingest(tick)
            #expect(!res.events.contains(where: { if case .paceDrift = $0 { return true }; return false }))
        }

        // 5 seconds back on target pace (3.33 m/s) -> resets debounce timer
        for s in 607...611 {
            let tick = TelemetryTick(elapsedSeconds: TimeInterval(s), heartRateBPM: 145.0, speedMetersPerSecond: 3.33)
            let res = core.ingest(tick)
            #expect(!res.events.contains(where: { if case .paceDrift = $0 { return true }; return false }))
        }

        // Another 6 seconds slow -> total slow time is not consecutive, so zero alerts
        for s in 612...617 {
            let tick = TelemetryTick(elapsedSeconds: TimeInterval(s), heartRateBPM: 145.0, speedMetersPerSecond: 2.94)
            let res = core.ingest(tick)
            #expect(!res.events.contains(where: { if case .paceDrift = $0 { return true }; return false }))
        }
    }

    @Test("Pace drift alert: non-destructive invariance preserves target pace")
    func testPaceDriftNonDestructiveInvariance() {
        var core = AdaptivePacingCore(profile: standardProfile, intent: standardIntent, location: .outdoor)
        for tick in PacingSessionFixtures.makeSteadyEasyRun(durationSeconds: 600) {
            _ = core.ingest(tick)
        }

        let originalTarget = core.currentTargetPaceSecondsPerKm

        // Ingest 15 seconds of fast pace (3.80 m/s -> ~4:23 /km)
        for s in 601...615 {
            let tick = TelemetryTick(elapsedSeconds: TimeInterval(s), heartRateBPM: 145.0, speedMetersPerSecond: 3.80)
            let res = core.ingest(tick)
            if res.events.contains(where: { if case .paceDrift = $0 { return true }; return false }) {
                #expect(core.currentTargetPaceSecondsPerKm == originalTarget, "Target pace must remain untouched by drift alerts")
            }
        }
        #expect(core.currentTargetPaceSecondsPerKm == originalTarget)
    }

    @Test("Pace drift feedbackSpec maps .tooSlow and .tooFast to directional haptics and voice cues")
    func testPaceDriftFeedbackSpec() {
        let slowEvent = PacingEvent.paceDrift(deviation: .tooSlow, deltaSecondsPerKm: 15)
        let slowSpec = slowEvent.feedbackSpec
        #expect(slowSpec.haptic == .directionUp)
        #expect(slowSpec.voiceCueText == "Pace dropping. Pick up rhythm.")
        #expect(slowSpec.accentToken == .surgeBlue)

        let fastEvent = PacingEvent.paceDrift(deviation: .tooFast, deltaSecondsPerKm: 12)
        let fastSpec = fastEvent.feedbackSpec
        #expect(fastSpec.haptic == .directionDown)
        #expect(fastSpec.voiceCueText == "Pace high. Ease into rhythm.")
        #expect(fastSpec.accentToken == .recoverOrange)

        let onTargetEvent = PacingEvent.paceDrift(deviation: .onTarget, deltaSecondsPerKm: 0)
        let onTargetSpec = onTargetEvent.feedbackSpec
        #expect(onTargetSpec.haptic == .none)
        #expect(onTargetSpec.voiceCueText == nil)
        #expect(onTargetSpec.accentToken == .neutral)
    }
}

