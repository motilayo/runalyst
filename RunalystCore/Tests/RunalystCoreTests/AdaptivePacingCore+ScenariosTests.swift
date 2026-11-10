import Foundation
@testable import RunalystCore
import Testing

@Suite("Adaptive Pacing Core Scenarios Tests")
struct AdaptivePacingCoreScenariosTests {

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

    // MARK: - Recover Transition Tests

    @Test("Recover transition: sustained HR ceiling > 0.94 maxHR for 35 s emits recover event")
    func testRecoverSustainedHRCeiling() {
        var core = AdaptivePacingCore(profile: standardProfile, intent: standardIntent, location: .outdoor)

        // Baseline steady run for 600 s calibration (power 220 W, HR 145 BPM -> EF ~1.517)
        let calTicks = PacingSessionFixtures.makeSteadyEasyRun(durationSeconds: 600)
        for tick in calTicks { _ = core.ingest(tick) }

        // At tick 610, HR breaches ceiling (> 178.6 BPM) with power scaled to maintain EF (~1.513)
        // so that Efficiency Drift does not fire and HR ceiling is isolated
        var recoverEvent: PacingEvent?
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
            let result = core.ingest(tick)
            for event in result.events {
                if case .recover = event {
                    recoverEvent = event
                }
            }
            if recoverEvent != nil { break }
        }

        #expect(recoverEvent != nil)
        if case .recover(let delta, let newTarget, let reason) = recoverEvent {
            #expect(reason == .heartRateCeiling)
            // 5% of 300 = 15, capped by stepLimit 10
            #expect(delta == 10)
            #expect(newTarget == 310)
        }
    }

    @Test("Recover transition: brief HR spike of 25 s does not emit recover event")
    func testRecoverBriefHRCeilingNoEvent() {
        var core = AdaptivePacingCore(profile: standardProfile, intent: standardIntent, location: .outdoor)
        let calTicks = PacingSessionFixtures.makeSteadyEasyRun(durationSeconds: 600)
        for tick in calTicks { _ = core.ingest(tick) }

        // Spike for 25 s (from 665 to 689)
        var adjustments: [PacingEvent] = []
        for s in 601...720 {
            let hr: Double = (s >= 665 && s <= 689) ? 185.0 : 150.0
            let tick = TelemetryTick(
                elapsedSeconds: TimeInterval(s),
                heartRateBPM: hr,
                speedMetersPerSecond: 3.33,
                powerWatts: 220.0,
                cadenceSPM: 168.0,
                groundContactTimeMs: 240.0
            )
            let result = core.ingest(tick)
            adjustments.append(contentsOf: result.events.filter {
                if case .recover = $0 { return true }
                return false
            })
        }

        #expect(adjustments.isEmpty, "Brief 25 s spike must not trigger recover")
    }

    @Test("Recover transition: 2 consecutive form breakdown evaluations emit recover event")
    func testRecoverFormBreakdown() {
        var core = AdaptivePacingCore(profile: standardProfile, intent: standardIntent, location: .outdoor)
        let calTicks = PacingSessionFixtures.makeSteadyEasyRun(durationSeconds: 600)
        for tick in calTicks { _ = core.ingest(tick) }

        // Form collapse from 601 onward (GCT 262 ms = +9.1%, Cadence 160 = -8 SPM)
        // Evaluated at tick 630 (1st breakdown) and tick 640 (2nd consecutive -> triggers recover)
        var recoverEvent: PacingEvent?
        for s in 601...650 {
            let tick = TelemetryTick(
                elapsedSeconds: TimeInterval(s),
                heartRateBPM: 145.0,
                speedMetersPerSecond: 3.33,
                powerWatts: 220.0,
                cadenceSPM: 160.0,
                groundContactTimeMs: 262.0
            )
            let result = core.ingest(tick)
            for event in result.events {
                if case .recover = event {
                    recoverEvent = event
                }
            }
            if recoverEvent != nil { break }
        }

        #expect(recoverEvent != nil)
        if case .recover(let delta, let newTarget, let reason) = recoverEvent {
            #expect(reason == .formBreakdown)
            // 3% of 300 = 9 s/km
            #expect(delta == 9)
            #expect(newTarget == 309)
        }
    }

    @Test("Recover transition: progressive efficiency drift <= -0.06 emits recover event")
    func testRecoverEfficiencyDrift() {
        var core = AdaptivePacingCore(profile: standardProfile, intent: standardIntent, location: .outdoor)
        let calTicks = PacingSessionFixtures.makeSteadyEasyRun(durationSeconds: 600)
        for tick in calTicks { _ = core.ingest(tick) }

        // Cardiac drift: HR rises from 145 to 165 at same speed/power
        var recoverEvent: PacingEvent?
        for s in 601...900 {
            let progress = Double(s - 600) / 300.0
            let hr = 145.0 + progress * 20.0
            let tick = TelemetryTick(
                elapsedSeconds: TimeInterval(s),
                heartRateBPM: hr,
                speedMetersPerSecond: 3.33,
                powerWatts: 220.0,
                cadenceSPM: 168.0,
                groundContactTimeMs: 240.0
            )
            let result = core.ingest(tick)
            for event in result.events {
                if case .recover = event {
                    recoverEvent = event
                }
            }
            if recoverEvent != nil { break }
        }

        #expect(recoverEvent != nil)
        if case .recover(_, _, let reason) = recoverEvent {
            #expect(reason == .efficiencyDrift)
        }
    }

    @Test("Recover transition: compound triggers select compound reason and 8% magnitude")
    func testRecoverCompoundTrigger() {
        var core = AdaptivePacingCore(profile: standardProfile, intent: standardIntent, location: .outdoor)
        let calTicks = PacingSessionFixtures.makeSteadyEasyRun(durationSeconds: 600)
        for tick in calTicks { _ = core.ingest(tick) }

        // HR spike starts at 601; form collapse starts at 615 so both align at tick 660 evaluation
        var recoverEvent: PacingEvent?
        for s in 601...680 {
            let hr: Double = 186.0
            let gct: Double = (s >= 615) ? 265.0 : 240.0
            let cad: Double = (s >= 615) ? 158.0 : 168.0

            let tick = TelemetryTick(
                elapsedSeconds: TimeInterval(s),
                heartRateBPM: hr,
                speedMetersPerSecond: 3.33,
                powerWatts: 280.0,
                cadenceSPM: cad,
                groundContactTimeMs: gct
            )
            let result = core.ingest(tick)
            for event in result.events {
                if case .recover = event {
                    recoverEvent = event
                }
            }
            if recoverEvent != nil { break }
        }

        #expect(recoverEvent != nil)
        if case .recover(let delta, _, let reason) = recoverEvent {
            #expect(reason == .compound)
            // 8% of 300 = 24 s/km, capped at 10
            #expect(delta == 10)
        }
    }

    // MARK: - Surge & Protection Gate Tests

    @Test("Surge protection gates: locked out on recovery intent, fallback profile, and subjective distress")
    func testSurgeLockouts() {
        let surgeReadyProfile = AthleteCalibrationProfile(
            maxHR: 190.0,
            powerToHRTopQuartile: 1.45,
            isFallback: false
        )

        // Gate 1: Recovery intent
        let recoveryIntent = PacingSessionIntent(targetPaceSecondsPerKm: 300, intent: .recovery, validForDay: "2026-11-09")
        var coreRecovery = AdaptivePacingCore(profile: surgeReadyProfile, intent: recoveryIntent, location: .outdoor)
        for tick in PacingSessionFixtures.makeSteadyEasyRun(durationSeconds: 700, heartRate: 135.0, power: 240.0) {
            let res = coreRecovery.ingest(tick)
            #expect(!res.events.contains { if case .surge = $0 { return true }; return false })
        }

        // Gate 2: Fallback profile
        let fallbackProf = AthleteCalibrationProfile(maxHR: 180.0, isFallback: true)
        let tempoIntent = PacingSessionIntent(targetPaceSecondsPerKm: 270, intent: .tempo, validForDay: "2026-11-09")
        var coreFallback = AdaptivePacingCore(profile: fallbackProf, intent: tempoIntent, location: .outdoor)
        for tick in PacingSessionFixtures.makeSteadyEasyRun(durationSeconds: 700, heartRate: 135.0, power: 240.0) {
            let res = coreFallback.ingest(tick)
            #expect(!res.events.contains { if case .surge = $0 { return true }; return false })
        }

        // Gate 3: Subjective distress
        let distressIntent = PacingSessionIntent(
            targetPaceSecondsPerKm: 270,
            intent: .tempo,
            subjectiveDistress: true,
            validForDay: "2026-11-09"
        )
        var coreDistress = AdaptivePacingCore(profile: surgeReadyProfile, intent: distressIntent, location: .outdoor)
        for tick in PacingSessionFixtures.makeSteadyEasyRun(durationSeconds: 700, heartRate: 135.0, power: 240.0) {
            let res = coreDistress.ingest(tick)
            #expect(!res.events.contains { if case .surge = $0 { return true }; return false })
        }
    }

    @Test("Valid surge: tempo run with strong aerobic reserve emits surge of -5 s/km")
    func testValidSurgeOnTempo() {
        let tempoProfile = AthleteCalibrationProfile(
            maxHR: 190.0,
            powerToHRTopQuartile: 1.45,
            isFallback: false
        )
        let tempoIntent = PacingSessionIntent(
            targetPaceSecondsPerKm: 270,
            intent: .tempo,
            validForDay: "2026-11-09"
        )
        var core = AdaptivePacingCore(profile: tempoProfile, intent: tempoIntent, location: .outdoor)

        // Calibration with power 240 W, HR 145 BPM (power/HR = 1.655 > 1.45, HR = 145 < 0.82 * 190 = 155.8)
        let ticks = PacingSessionFixtures.makeSteadyEasyRun(
            durationSeconds: 650,
            targetPaceSecPerKm: 270,
            heartRate: 145.0,
            cadence: 172.0,
            power: 240.0
        )

        var surgeEvent: PacingEvent?
        for tick in ticks {
            let result = core.ingest(tick)
            for event in result.events {
                if case .surge = event {
                    surgeEvent = event
                }
            }
        }

        #expect(surgeEvent != nil)
        if case .surge(let delta, let newTarget) = surgeEvent {
            // 2% of 270 = 5.4 -> 5 s/km speedup (-5)
            #expect(delta == -5)
            #expect(newTarget == 265)
        }
    }
}
