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
                case .backOnTarget:
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
        #expect(surgeSpec.haptic == .directionUp)
        #expect(surgeSpec.voiceCueText == "Target pace up. Quicken your steps.")
        #expect(surgeSpec.accentToken == .electricBlue)

        let recoverForm = PacingEvent.recover(deltaSecondsPerKm: 9, newTargetSecondsPerKm: 309, reason: .formBreakdown)
        let formSpec = recoverForm.feedbackSpec
        #expect(formSpec.haptic == .retry)
        #expect(formSpec.voiceCueText == "Cadence dropping. Short, quick steps.")
        #expect(formSpec.accentToken == .vibrantGreen)

        let recoverHR = PacingEvent.recover(deltaSecondsPerKm: 10, newTargetSecondsPerKm: 310, reason: .heartRateCeiling)
        let hrSpec = recoverHR.feedbackSpec
        #expect(hrSpec.haptic == .directionDown)
        #expect(hrSpec.voiceCueText == "Heart rate drifting. Ease the pace.")
        #expect(hrSpec.accentToken == .neonPink)

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
}

