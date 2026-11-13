import Foundation
@testable import RunalystCore
import Testing

@Suite("Adaptive Pacing Cadence Drift & Milestone Tests")
struct AdaptivePacingCadenceTests {

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

    // MARK: - Baseline Locking

    @Test("Cadence baseline locking: extracts and locks cadence baseline during calibration")
    func testCadenceBaselineLockingFromCalibration() {
        var core = AdaptivePacingCore(profile: standardProfile, intent: standardIntent, location: .outdoor)
        #expect(core.currentTargetCadenceSPM == nil)

        // Steady easy run has cadence 168.0 SPM
        let ticks = PacingSessionFixtures.makeSteadyEasyRun(durationSeconds: 605)
        for tick in ticks {
            _ = core.ingest(tick)
        }

        #expect(core.currentTargetCadenceSPM == 168)
    }

    @Test("Cadence baseline locking: explicit intent overrides extracted baseline")
    func testCadenceBaselineExplicitIntent() {
        let explicitIntent = PacingSessionIntent(
            targetPaceSecondsPerKm: 300,
            intent: .steady,
            subjectiveDistress: false,
            validForDay: "2026-11-09",
            targetCadenceSPM: 175
        )
        var core = AdaptivePacingCore(profile: standardProfile, intent: explicitIntent, location: .outdoor)
        #expect(core.currentTargetCadenceSPM == 175)

        let ticks = PacingSessionFixtures.makeSteadyEasyRun(durationSeconds: 605, cadence: 165.0)
        for tick in ticks {
            _ = core.ingest(tick)
        }

        #expect(core.currentTargetCadenceSPM == 175)
    }

    @Test("Cadence baseline locking: enforces 150 SPM cadence floor if baseline is low")
    func testCadenceBaselineFloorEnforcement() {
        var core = AdaptivePacingCore(profile: standardProfile, intent: standardIntent, location: .outdoor)
        let lowCadenceTicks = PacingSessionFixtures.makeSteadyEasyRun(durationSeconds: 605, cadence: 142.0)
        for tick in lowCadenceTicks {
            _ = core.ingest(tick)
        }

        #expect(core.currentTargetCadenceSPM == 150)
    }

    // MARK: - Cadence Drift Triggering & Cooldown

    @Test("Cadence drift alert: 12s continuous debounce triggers alert and 30s cooldown suppresses duplicates")
    func testCadenceDriftDebounceAndCooldown() {
        var core = AdaptivePacingCore(profile: standardProfile, intent: standardIntent, location: .outdoor)
        for tick in PacingSessionFixtures.makeSteadyEasyRun(durationSeconds: 600, cadence: 168.0) {
            _ = core.ingest(tick)
        }
        #expect(core.currentTargetCadenceSPM == 168)

        var driftEvents: [PacingEvent] = []
        var currentTick = 601

        // 1. Advance until short-window cadence drops below 162 SPM (168 - 6)
        while currentTick < 650 {
            let tick = TelemetryTick(
                elapsedSeconds: TimeInterval(currentTick),
                heartRateBPM: 145.0,
                speedMetersPerSecond: 3.33,
                cadenceSPM: 155.0
            )
            _ = core.ingest(tick)
            currentTick += 1
            if let shortCadence = core.ringBuffer.shortWindowStats(for: .cadence),
               Double(Int(shortCadence.mean.rounded())) < Double(168) - core.configuration.cadenceDriftThresholdSPM {
                break
            }
        }
        #expect(driftEvents.isEmpty, "First tick entering cadence drop must not emit alert")

        // 2. Next 10 ticks in drop (total 11 seconds in drop; 11s < 12s debounce)
        for _ in 1...10 {
            let tick = TelemetryTick(
                elapsedSeconds: TimeInterval(currentTick),
                heartRateBPM: 145.0,
                speedMetersPerSecond: 3.33,
                cadenceSPM: 155.0
            )
            let res = core.ingest(tick)
            currentTick += 1
            for event in res.events {
                if case .cadenceDrift = event {
                    driftEvents.append(event)
                }
            }
        }
        #expect(driftEvents.isEmpty, "Debounce is 12s; 11s must not trigger cadence drift alert")

        // 3. 12th second triggers alert
        let tick12 = TelemetryTick(
            elapsedSeconds: TimeInterval(currentTick),
            heartRateBPM: 145.0,
            speedMetersPerSecond: 3.33,
            cadenceSPM: 155.0
        )
        let res12 = core.ingest(tick12)
        currentTick += 1
        for event in res12.events {
            if case .cadenceDrift(let current, let target, let delta) = event {
                #expect(current <= 162)
                #expect(target == 168)
                #expect(delta >= 6)
                driftEvents.append(event)
            }
        }
        #expect(driftEvents.count == 1, "12th consecutive second must trigger exactly one cadence drift alert")

        // 4. Next 25 ticks continue at 155 SPM. Cooldown is 30s -> suppressed
        for _ in 1...25 {
            let tick = TelemetryTick(
                elapsedSeconds: TimeInterval(currentTick),
                heartRateBPM: 145.0,
                speedMetersPerSecond: 3.33,
                cadenceSPM: 155.0
            )
            let res = core.ingest(tick)
            currentTick += 1
            for event in res.events {
                if case .cadenceDrift = event {
                    driftEvents.append(event)
                }
            }
        }
        #expect(driftEvents.count == 1, "Cadence drift alert must be suppressed during 30s cooldown")

        // 5. Next 5 ticks complete the 30s cooldown, then tick 31 fires second alert
        for _ in 1...5 {
            let tick = TelemetryTick(
                elapsedSeconds: TimeInterval(currentTick),
                heartRateBPM: 145.0,
                speedMetersPerSecond: 3.33,
                cadenceSPM: 155.0
            )
            let res = core.ingest(tick)
            currentTick += 1
            for event in res.events {
                if case .cadenceDrift = event {
                    driftEvents.append(event)
                }
            }
        }
        #expect(driftEvents.count == 2, "After 30s cooldown, next tick fires second cadence drift alert")
    }

    @Test("Cadence drift alert: momentary drop resets debounce accumulator")
    func testCadenceDriftRecoveryResetsDebounce() {
        var core = AdaptivePacingCore(profile: standardProfile, intent: standardIntent, location: .outdoor)
        for tick in PacingSessionFixtures.makeSteadyEasyRun(durationSeconds: 600, cadence: 168.0) {
            _ = core.ingest(tick)
        }

        var currentTick = 601
        // Advance until short-window cadence drops below 162 SPM
        while currentTick < 650 {
            let tick = TelemetryTick(
                elapsedSeconds: TimeInterval(currentTick),
                heartRateBPM: 145.0,
                speedMetersPerSecond: 3.33,
                cadenceSPM: 155.0
            )
            _ = core.ingest(tick)
            currentTick += 1
            if let shortCadence = core.ringBuffer.shortWindowStats(for: .cadence),
               Double(Int(shortCadence.mean.rounded())) < Double(168) - core.configuration.cadenceDriftThresholdSPM {
                break
            }
        }

        // 5 seconds in drop
        for _ in 1...5 {
            let tick = TelemetryTick(
                elapsedSeconds: TimeInterval(currentTick),
                heartRateBPM: 145.0,
                speedMetersPerSecond: 3.33,
                cadenceSPM: 155.0
            )
            _ = core.ingest(tick)
            currentTick += 1
        }

        // Recover to 180 SPM (healthy) until short-window cadence is above 162
        while currentTick < 700 {
            let recoverTick = TelemetryTick(
                elapsedSeconds: TimeInterval(currentTick),
                heartRateBPM: 145.0,
                speedMetersPerSecond: 3.33,
                cadenceSPM: 180.0
            )
            _ = core.ingest(recoverTick)
            currentTick += 1
            if let shortCadence = core.ringBuffer.shortWindowStats(for: .cadence),
               Double(Int(shortCadence.mean.rounded())) >= Double(168) - core.configuration.cadenceDriftThresholdSPM {
                break
            }
        }

        // Drop again for 8 seconds: must NOT trigger because previous debounce was reset
        var driftEvents: [PacingEvent] = []
        for _ in 1...8 {
            let tick = TelemetryTick(
                elapsedSeconds: TimeInterval(currentTick),
                heartRateBPM: 145.0,
                speedMetersPerSecond: 3.33,
                cadenceSPM: 155.0
            )
            let res = core.ingest(tick)
            currentTick += 1
            for event in res.events {
                if case .cadenceDrift = event {
                    driftEvents.append(event)
                }
            }
        }
        #expect(driftEvents.isEmpty, "Reset accumulator prevents premature triggering")
    }

    @Test("Cadence drift alert: absolute floor of 150 SPM triggers even with low target")
    func testCadenceDriftAbsoluteFloor() {
        let lowTargetIntent = PacingSessionIntent(
            targetPaceSecondsPerKm: 300,
            intent: .steady,
            subjectiveDistress: false,
            validForDay: "2026-11-09",
            targetCadenceSPM: 152
        )
        var core = AdaptivePacingCore(profile: standardProfile, intent: lowTargetIntent, location: .outdoor)
        for tick in PacingSessionFixtures.makeSteadyEasyRun(durationSeconds: 600, cadence: 152.0) {
            _ = core.ingest(tick)
        }

        // Running at 145 SPM (below 150 SPM absolute floor)
        var currentTick = 601
        while currentTick < 650 {
            let tick = TelemetryTick(
                elapsedSeconds: TimeInterval(currentTick),
                heartRateBPM: 145.0,
                speedMetersPerSecond: 3.33,
                cadenceSPM: 145.0
            )
            _ = core.ingest(tick)
            currentTick += 1
            if let shortCadence = core.ringBuffer.shortWindowStats(for: .cadence),
               Int(shortCadence.mean.rounded()) < core.configuration.cadenceFloorSPM {
                break
            }
        }

        // 11 more seconds (total 12 seconds in floor violation)
        var driftEvents: [PacingEvent] = []
        for _ in 1...11 {
            let tick = TelemetryTick(
                elapsedSeconds: TimeInterval(currentTick),
                heartRateBPM: 145.0,
                speedMetersPerSecond: 3.33,
                cadenceSPM: 145.0
            )
            let res = core.ingest(tick)
            currentTick += 1
            for event in res.events {
                if case .cadenceDrift = event {
                    driftEvents.append(event)
                }
            }
        }
        #expect(driftEvents.count == 1, "Dropping below 150 SPM floor triggers cadence drift alert")
    }

    // MARK: - Presentation & Feedback Specs

    @Test("Feedback specifications for cadenceDrift and splitMilestone")
    func testFeedbackSpecifications() {
        let cadenceEvent = PacingEvent.cadenceDrift(currentCadenceSPM: 158, targetCadenceSPM: 168, deltaSPM: 10)
        let cadenceSpec = cadenceEvent.feedbackSpec
        #expect(cadenceSpec.haptic == .retry)
        #expect(cadenceSpec.voiceCueText == nil)
        #expect(cadenceSpec.accentToken == .vibrantGreen)

        let splitEvent = PacingEvent.splitMilestone(splitIndex: 5, splitPaceSecondsPerKm: 285)
        let splitSpec = splitEvent.feedbackSpec
        #expect(splitSpec.haptic == .success)
        #expect(splitSpec.voiceCueText == "Kilometer 5, 4:45.")
        #expect(splitSpec.accentToken == .electricBlue)
    }

    @Test("PacingDisplayState exposes formatted and numerical cadence")
    func testDisplayStateCadenceExposure() {
        let display = PacingDisplayState.initial(
            targetPaceSecondsPerKm: 300,
            adjustmentsEnabled: true,
            targetCadenceSPM: 170
        )
        #expect(display.targetCadenceSPM == 170)
        #expect(display.targetCadenceFormatted == "170 SPM")
        #expect(display.filteredCadenceSPM == nil)
        #expect(display.filteredCadenceFormatted == "--")

        var core = AdaptivePacingCore(profile: standardProfile, intent: standardIntent, location: .outdoor)
        let ticks = PacingSessionFixtures.makeSteadyEasyRun(durationSeconds: 610, cadence: 168.0)
        var lastDisplay: PacingDisplayState?
        for tick in ticks {
            let res = core.ingest(tick)
            lastDisplay = res.display
        }

        #expect(lastDisplay?.targetCadenceSPM == 168)
        #expect(lastDisplay?.targetCadenceFormatted == "168 SPM")
        #expect(lastDisplay?.filteredCadenceSPM == 168)
        #expect(lastDisplay?.filteredCadenceFormatted == "168 SPM")
    }
}
