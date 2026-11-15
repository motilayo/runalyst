import Foundation
@testable import RunalystCore
import Testing

@Suite("Adaptive Pacing Core Watch Companion Tests")
struct AdaptivePacingCoreWatchCompanionTests {

    private let standardProfile = AthleteCalibrationProfile(
        maxHR: 190.0,
        restingHR: 52.0,
        powerToHRTopQuartile: 1.45,
        isFallback: false
    )

    private let standardIntent = PacingSessionIntent(
        targetPaceSecondsPerKm: 300,
        intent: .steady,
        subjectiveDistress: false,
        validForDay: "2026-11-12"
    )

    private func makeTick(
        second: Int,
        hr: Double = 140.0,
        speed: Double = 3.333,
        power: Double = 220.0,
        cadence: Double = 168.0,
        gct: Double = 240.0
    ) -> TelemetryTick {
        TelemetryTick(
            elapsedSeconds: TimeInterval(second),
            heartRateBPM: hr,
            speedMetersPerSecond: speed,
            powerWatts: power,
            cadenceSPM: cadence,
            groundContactTimeMs: gct
        )
    }

    // MARK: - 1. WatchRunIntent Profiles & Policies

    @Test("WatchRunIntent: configuration policies reflect sports science profiles")
    func testWatchRunIntentConfigurationProfiles() {
        let baseConfig = AdaptivePacingConfiguration.forWatchCompanion(intent: .adaptiveBase)
        #expect(baseConfig.warmupDurationSeconds == 120.0)
        #expect(baseConfig.baselineDurationSeconds == 180.0)
        #expect(baseConfig.maxCalibrationDurationSeconds == 420.0)
        #expect(baseConfig.refractoryDurationSeconds == 90.0)
        #expect(baseConfig.hrCeilingFraction == 0.92)
        #expect(baseConfig.hrSurgeCeilingFraction == 0.82)
        #expect(baseConfig.recoverEfficiencyDriftThreshold == -0.06)
        #expect(baseConfig.surgeMagnitudeFraction == 0.02)

        let pushConfig = AdaptivePacingConfiguration.forWatchCompanion(intent: .pushPerformance)
        #expect(pushConfig.warmupDurationSeconds == 120.0)
        #expect(pushConfig.baselineDurationSeconds == 180.0)
        #expect(pushConfig.maxCalibrationDurationSeconds == 420.0)
        #expect(pushConfig.refractoryDurationSeconds == 90.0)
        #expect(pushConfig.hrCeilingFraction == 0.95)
        #expect(pushConfig.hrSurgeCeilingFraction == 0.88)
        #expect(pushConfig.recoverEfficiencyDriftThreshold == -0.08)
        #expect(pushConfig.surgeMagnitudeFraction == 0.04)

        let recoveryConfig = AdaptivePacingConfiguration.forWatchCompanion(intent: .recovery)
        #expect(recoveryConfig.warmupDurationSeconds == 120.0)
        #expect(recoveryConfig.baselineDurationSeconds == 180.0)
        #expect(recoveryConfig.maxCalibrationDurationSeconds == 420.0)
        #expect(recoveryConfig.refractoryDurationSeconds == 90.0)
        #expect(recoveryConfig.hrCeilingFraction == 0.78)
        #expect(recoveryConfig.hrCeilingDurationSeconds == 20.0)
        #expect(recoveryConfig.recoverEfficiencyDriftThreshold == -0.04)

        // Title and matching
        #expect(WatchRunIntent.adaptiveBase.title == "Aerobic Base")
        #expect(WatchRunIntent.pushPerformance.title == "Push / Performance")
        #expect(WatchRunIntent.recovery.title == "Recovery")

        #expect(WatchRunIntent.matching(intentKind: .recovery) == .recovery)
        #expect(WatchRunIntent.matching(intentKind: .tempo) == .pushPerformance)
        #expect(WatchRunIntent.matching(intentKind: .progression) == .pushPerformance)
        #expect(WatchRunIntent.matching(intentKind: .intervals) == .pushPerformance)
        #expect(WatchRunIntent.matching(intentKind: .steady) == .adaptiveBase)
        #expect(WatchRunIntent.matching(intentKind: .easyAerobic) == .adaptiveBase)
    }

    @Test("WatchRunIntent.recovery: suppresses surge and triggers recover at conservative HR ceiling")
    func testRecoveryIntentSuppressesSurgeAndEnforcesConservativeHRCeiling() {
        let recoveryIntent = PacingSessionIntent(
            targetPaceSecondsPerKm: 300,
            intent: WatchRunIntent.recovery.pacingIntentKind,
            subjectiveDistress: false,
            validForDay: "2026-11-12"
        )
        let config = AdaptivePacingConfiguration.forWatchCompanion(intent: .recovery)
        var core = AdaptivePacingCore(
            profile: standardProfile,
            intent: recoveryIntent,
            location: .outdoor,
            configuration: config
        )

        // 300s calibration with high power reserves (240 W, 130 BPM -> power/HR = 1.84 > 1.45)
        let calTicks = PacingSessionFixtures.makeSteadyEasyRun(
            durationSeconds: 300,
            targetPaceSecPerKm: 300,
            heartRate: 130.0,
            power: 240.0
        )
        for tick in calTicks { _ = core.ingest(tick) }

        // Post-calibration: even with strong reserves, surge is strictly suppressed
        for s in 301...350 {
            let result = core.ingest(makeTick(second: s, hr: 130.0, power: 240.0))
            let hasSurge = result.events.contains { if case .surge = $0 { return true }; return false }
            #expect(!hasSurge, "Surge must be strictly suppressed during recovery intent")
        }

        // Conservative HR ceiling: 0.78 * 190 = 148.2 BPM. At 155 BPM for > 20s, recover triggers
        var recoverEvent: PacingEvent?
        for s in 351...385 {
            let result = core.ingest(makeTick(second: s, hr: 155.0, power: 240.0))
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
            #expect(delta > 0)
            #expect(newTarget > 300)
        }
    }

    @Test("WatchRunIntent.pushPerformance: allows surge at higher HR ceiling with 4% step headroom")
    func testPushPerformanceIntentHeadroomAndPermissiveSurge() {
        let pushIntent = PacingSessionIntent(
            targetPaceSecondsPerKm: 300,
            intent: WatchRunIntent.pushPerformance.pacingIntentKind,
            subjectiveDistress: false,
            validForDay: "2026-11-12"
        )
        let config = AdaptivePacingConfiguration.forWatchCompanion(intent: .pushPerformance)
        var core = AdaptivePacingCore(
            profile: standardProfile,
            intent: pushIntent,
            location: .outdoor,
            configuration: config
        )

        // 300s calibration at 150 BPM, 260 W (power/HR = 1.733 > 1.45)
        let calTicks = PacingSessionFixtures.makeSteadyEasyRun(
            durationSeconds: 300,
            targetPaceSecPerKm: 300,
            heartRate: 150.0,
            power: 260.0
        )
        for tick in calTicks { _ = core.ingest(tick) }

        // HR at 162 BPM (> 0.82 * 190 = 155.8, but < 0.88 * 190 = 167.2) with high power
        var surgeEvent: PacingEvent?
        for s in 301...310 {
            let result = core.ingest(makeTick(second: s, hr: 162.0, power: 285.0))
            for event in result.events {
                if case .surge = event {
                    surgeEvent = event
                }
            }
        }

        #expect(surgeEvent != nil)
        if case .surge(let delta, let newTarget) = surgeEvent {
            // 4% of 300 = 12, capped by stepLimit 10 -> -10 s/km
            #expect(delta == -10)
            #expect(newTarget == 290)
        }
    }

    // MARK: - 2. 5-Minute Calibration Choreography

    @Test("5-Minute Calibration: first tick emits calibrationStarted, quiet phase during ticks 1..299")
    func testCalibrationStartAudioCueAndQuietPhase() {
        let config = AdaptivePacingConfiguration.forWatchCompanion(intent: .adaptiveBase)
        var core = AdaptivePacingCore(
            profile: standardProfile,
            intent: standardIntent,
            location: .outdoor,
            configuration: config
        )

        // Tick 1: Emits .calibrationStarted exactly once
        let res1 = core.ingest(makeTick(second: 1))
        #expect(res1.events.count == 1)
        #expect(res1.events.first == .calibrationStarted)

        let startSpec = res1.events[0].feedbackSpec(useMetricSystem: true)
        #expect(startSpec.haptic == .none)
        #expect(startSpec.voiceCueText == "Reading baseline.")
        #expect(startSpec.accentToken == .calibratingBlue)

        // Ticks 2..299: Zero nagging events, valid normalized display state
        for s in 2...299 {
            let res = core.ingest(makeTick(second: s))
            #expect(res.events.isEmpty, "Tick \(s) emitted unexpected events during calibration")
            #expect(res.display.isCalibrating == true)
            #expect(res.display.biometricStatusToken == .calibratingBlue)
            #expect(res.display.biometricStatusLabel == "Calibrating")
            #expect(res.display.paceGaugeNormalizedPosition >= 0.0 && res.display.paceGaugeNormalizedPosition <= 1.0)
            #expect(res.display.targetBandLowerNormalized >= 0.0 && res.display.targetBandLowerNormalized <= 1.0)
            #expect(res.display.targetBandUpperNormalized >= 0.0 && res.display.targetBandUpperNormalized <= 1.0)

            if s == 60 {
                #expect(res.display.elapsedTimeFormatted == "1:00")
            } else if s == 299 {
                #expect(res.display.elapsedTimeFormatted == "4:59")
            }
        }
    }

    @Test("5-Minute Calibration: locks baselines at 300s, unit-aware audio cue in km and mi")
    func testCalibrationCompleteLocksBaselinesAt300s() {
        let config = AdaptivePacingConfiguration.forWatchCompanion(intent: .adaptiveBase)
        var core = AdaptivePacingCore(
            profile: standardProfile,
            intent: standardIntent,
            location: .outdoor,
            configuration: config
        )

        for s in 1...299 {
            _ = core.ingest(makeTick(second: s))
        }

        // Tick 300: Locks baseline and emits calibrationComplete
        let res300 = core.ingest(makeTick(second: 300))
        #expect(res300.events.count == 1)

        guard let completeEvent = res300.events.first else {
            Issue.record("Expected calibrationComplete event at tick 300")
            return
        }

        if case .calibrationComplete(let target, let adjustmentsEnabled) = completeEvent {
            #expect(target == 300)
            #expect(adjustmentsEnabled == true)
        } else {
            Issue.record("Expected .calibrationComplete, got \(completeEvent)")
        }

        #expect(core.currentTargetCadenceSPM == 168)

        // Metric voice cue
        let metricSpec = completeEvent.feedbackSpec(useMetricSystem: true)
        #expect(metricSpec.haptic == .success)
        #expect(metricSpec.accentToken == .electricBlue)
        #expect(metricSpec.voiceCueText == "Target 5:00.")

        // Imperial voice cue (300 s/km * 1.609344 = 482.8 -> 483 s/mi = 8:03)
        let imperialSpec = completeEvent.feedbackSpec(useMetricSystem: false)
        #expect(imperialSpec.haptic == .success)
        #expect(imperialSpec.accentToken == .electricBlue)
        #expect(imperialSpec.voiceCueText == "Target 8:03.")

        // Post-calibration display state at tick 301
        let res301 = core.ingest(makeTick(second: 301))
        #expect(res301.display.isCalibrating == false)
        #expect(res301.display.biometricStatusToken == .electricBlue)
        #expect(res301.display.biometricStatusLabel == "Locked In")
    }

    // MARK: - 3. Surge & Zone Lock-In Confirmation

    @Test("Surge & Zone Lock-In: ascending double-pulse surge, subtle tap lock-in confirmation, 90s refractory")
    func testSurgeTriggerAndLockInConfirmationChoreography() {
        let config = AdaptivePacingConfiguration.forWatchCompanion(intent: .pushPerformance)
        let pushIntent = PacingSessionIntent(
            targetPaceSecondsPerKm: 300,
            intent: WatchRunIntent.pushPerformance.pacingIntentKind,
            subjectiveDistress: false,
            validForDay: "2026-11-12"
        )
        var core = AdaptivePacingCore(
            profile: standardProfile,
            intent: pushIntent,
            location: .outdoor,
            configuration: config
        )

        // 300s calibration at 300 s/km, 140 BPM, 260 W (power/HR = 1.857 > 1.45)
        let calTicks = PacingSessionFixtures.makeSteadyEasyRun(
            durationSeconds: 300,
            targetPaceSecPerKm: 300,
            heartRate: 140.0,
            cadence: 168.0,
            power: 260.0
        )
        for tick in calTicks { _ = core.ingest(tick) }

        // Tick 310: Evaluates surge with high efficiency reserves
        var surgeEvent: PacingEvent?
        for s in 301...310 {
            let res = core.ingest(makeTick(second: s, hr: 140.0, speed: 3.333, power: 260.0))
            if let event = res.events.first(where: { if case .surge = $0 { return true }; return false }) {
                surgeEvent = event
            }
        }

        #expect(surgeEvent != nil)
        guard let surge = surgeEvent, case .surge(let delta, let newTarget) = surge else {
            Issue.record("Expected .surge event at tick 310")
            return
        }

        // 4% of 300 = 12 capped at 10 s/km -> new target 290 s/km (4:50)
        #expect(delta == -10)
        #expect(newTarget == 290)

        let metricSurgeSpec = surge.feedbackSpec(useMetricSystem: true)
        #expect(metricSurgeSpec.haptic == .ascendingDoublePulse)
        #expect(metricSurgeSpec.accentToken == .surgeTeal)
        #expect(metricSurgeSpec.voiceCueText == nil)

        let imperialSurgeSpec = surge.feedbackSpec(useMetricSystem: false)
        #expect(imperialSurgeSpec.voiceCueText == nil)

        #expect(core.awaitingSurgeLockInTargetSecondsPerKm == 290)
        #expect(core.refractorySecondsRemaining == 90)

        // Ticks 311..314: Runner is still at 300 s/km (tolerance band for 290 is 284..296, so 300 is too slow)
        for s in 311...314 {
            let res = core.ingest(makeTick(second: s, hr: 140.0, speed: 3.333, power: 260.0))
            let hasLockIn = res.events.contains { if case .surgeLockedIn = $0 { return true }; return false }
            #expect(!hasLockIn, "Must not lock in while pace is outside target tolerance")
        }

        // Runner accelerates to 3.448 m/s (~290 s/km). After rolling short window settles into 284..296:
        var lockInEvent: PacingEvent?
        for s in 315...330 {
            let res = core.ingest(makeTick(second: s, hr: 142.0, speed: 3.448, power: 265.0, cadence: 170.0))
            if let event = res.events.first(where: { if case .surgeLockedIn = $0 { return true }; return false }) {
                lockInEvent = event
                break
            }
        }

        #expect(lockInEvent != nil)
        if case .surgeLockedIn(let lockedTarget) = lockInEvent {
            #expect(lockedTarget == 290)
            let lockSpec = lockInEvent?.feedbackSpec(useMetricSystem: true)
            #expect(lockSpec?.haptic == .subtleConfirmation)
            #expect(lockSpec?.voiceCueText == nil)
            #expect(lockSpec?.accentToken == .surgeTeal)
        }

        #expect(core.awaitingSurgeLockInTargetSecondsPerKm == nil)

        // Subsequent ticks 331..340: Must not re-emit .surgeLockedIn
        for s in 331...340 {
            let res = core.ingest(makeTick(second: s, hr: 142.0, speed: 3.448, power: 265.0, cadence: 170.0))
            let hasLockIn = res.events.contains { if case .surgeLockedIn = $0 { return true }; return false }
            #expect(!hasLockIn, "Must not re-emit surgeLockedIn after already locked in")
        }

        // Refractory cooldown blocks adjustments during 90s cooldown
        #expect(core.refractorySecondsRemaining > 0)
    }

    // MARK: - 4. Two-Step Form & Fatigue Catch

    @Test("Two-step Form Catch: first breakdown emits formCheck without slowing target pace")
    func testTwoStepFormCheckDoesNotSlowTargetPace() {
        let config = AdaptivePacingConfiguration.forWatchCompanion(intent: .adaptiveBase)
        var core = AdaptivePacingCore(
            profile: standardProfile,
            intent: standardIntent,
            location: .outdoor,
            configuration: config
        )

        // 300s calibration with baseline GCT 240 ms, cadence 168 SPM
        let calTicks = PacingSessionFixtures.makeSteadyEasyRun(durationSeconds: 300)
        for tick in calTicks { _ = core.ingest(tick) }

        // Form collapse from 301 onward (GCT 262 ms = +9.1%, cadence 160 SPM = -8 SPM)
        // Evaluated at tick 330 (first evaluation after 30s short window)
        var formCheckEvent: PacingEvent?
        for s in 301...330 {
            let res = core.ingest(makeTick(second: s, hr: 145.0, cadence: 160.0, gct: 262.0))
            if let event = res.events.first(where: { if case .formCheck = $0 { return true }; return false }) {
                formCheckEvent = event
            }
        }

        #expect(formCheckEvent != nil)
        guard let fc = formCheckEvent, case .formCheck(let currentCadence, let targetCadence) = fc else {
            Issue.record("Expected .formCheck event at tick 330")
            return
        }

        #expect(currentCadence == 160)
        #expect(targetCadence == 168)

        let spec = fc.feedbackSpec(useMetricSystem: true)
        #expect(spec.haptic == .threeQuickLightTaps)
        #expect(spec.accentToken == .recoverAmber)
        #expect(spec.voiceCueText == nil)

        // Non-destructive: target pace MUST NOT be slowed by first form check
        #expect(core.currentTargetPaceSecondsPerKm == 300)
        #expect(core.state != .recover)
    }

    @Test("Two-step Form Catch: sustained degradation escalates to recover dial-back at second evaluation")
    func testSustainedFormBreakdownEscalatesToRecover() {
        let config = AdaptivePacingConfiguration.forWatchCompanion(intent: .adaptiveBase)
        var core = AdaptivePacingCore(
            profile: standardProfile,
            intent: standardIntent,
            location: .outdoor,
            configuration: config
        )

        let calTicks = PacingSessionFixtures.makeSteadyEasyRun(durationSeconds: 300)
        for tick in calTicks { _ = core.ingest(tick) }

        // Form collapse evaluated at 330 (formCheck) and 340 (recover)
        var recoverEvent: PacingEvent?
        for s in 301...340 {
            let res = core.ingest(makeTick(second: s, hr: 145.0, cadence: 160.0, gct: 262.0))
            if let event = res.events.first(where: { if case .recover = $0 { return true }; return false }) {
                recoverEvent = event
            }
        }

        #expect(recoverEvent != nil)
        guard let rec = recoverEvent, case .recover(let delta, let newTarget, let reason) = rec else {
            Issue.record("Expected .recover event on second consecutive form breakdown")
            return
        }

        #expect(reason == .formBreakdown)
        // 3% of 300 = 9 s/km dial-back -> new target 309 s/km (5:09)
        #expect(delta == 9)
        #expect(newTarget == 309)
        #expect(core.currentTargetPaceSecondsPerKm == 309)
        #expect(core.state == .recover)
        #expect(core.refractorySecondsRemaining == 90)

        let metricSpec = rec.feedbackSpec(useMetricSystem: true)
        #expect(metricSpec.haptic == .descendingDoublePulse)
        #expect(metricSpec.accentToken == .recoverAmber)
        #expect(metricSpec.voiceCueText == nil)

        let imperialSpec = rec.feedbackSpec(useMetricSystem: false)
        #expect(imperialSpec.voiceCueText == nil)
    }

    @Test("Fatigue Catch: sustained cardiac drift triggers recover with descending double-pulse")
    func testCardiacDriftTriggersRecover() {
        // High top quartile power/HR threshold suppresses surge triggers during steady running
        let driftProfile = AthleteCalibrationProfile(
            maxHR: 190.0,
            restingHR: 52.0,
            powerToHRTopQuartile: 2.50,
            isFallback: false
        )
        let config = AdaptivePacingConfiguration.forWatchCompanion(intent: .adaptiveBase)
        var core = AdaptivePacingCore(
            profile: driftProfile,
            intent: standardIntent,
            location: .outdoor,
            configuration: config
        )

        let calTicks = PacingSessionFixtures.makeSteadyEasyRun(durationSeconds: 300, power: 180.0)
        for tick in calTicks { _ = core.ingest(tick) }

        // HR ceiling breach (> 0.92 * 190 = 174.8 BPM) from tick 310 onward
        var recoverEvent: PacingEvent?
        for s in 301...380 {
            let hr: Double = (s >= 310) ? 185.0 : 145.0
            let power: Double = (s >= 310) ? 280.0 : 180.0
            let res = core.ingest(makeTick(second: s, hr: hr, power: power))
            if let event = res.events.first(where: { if case .recover = $0 { return true }; return false }) {
                recoverEvent = event
                break
            }
        }

        #expect(recoverEvent != nil)
        if case .recover(let delta, let newTarget, let reason) = recoverEvent {
            #expect(reason == .heartRateCeiling)
            #expect(delta == 10) // 5% of 300 = 15, capped at 10
            #expect(newTarget == 310)
        }
        #expect(core.firstDriftElapsedSeconds != nil)
    }

    // MARK: - 5. Post-Run WatchRunDebrief

    @Test("WatchRunDebrief: steady run with zero adjustments produces clean 3-bullet takeaway")
    func testWatchRunDebriefSteadyRun() {
        // High top quartile power/HR threshold suppresses surge triggers during steady run
        let steadyProfile = AthleteCalibrationProfile(
            maxHR: 190.0,
            restingHR: 52.0,
            powerToHRTopQuartile: 2.50,
            isFallback: false
        )
        var core = AdaptivePacingCore(
            profile: steadyProfile,
            intent: standardIntent,
            location: .outdoor,
            configuration: .forWatchCompanion(intent: .adaptiveBase)
        )

        let ticks = PacingSessionFixtures.makeSteadyEasyRun(
            durationSeconds: 1800,
            targetPaceSecPerKm: 300,
            heartRate: 145.0,
            cadence: 168.0,
            power: 180.0
        )
        for tick in ticks {
            _ = core.ingest(tick, totalDistanceMeters: (tick.elapsedSeconds / 1800.0) * 6000.0)
        }

        // Metric debrief
        let metricDebrief = core.buildRunDebrief(
            elapsedSeconds: 1800,
            totalDistanceMeters: 6000.0,
            useMetricSystem: true
        )
        #expect(metricDebrief.adaptationsBullet == "Held steady baseline pacing throughout.")
        #expect(metricDebrief.efficiencyScoreBullet == "Stayed in live aerobic band for all 30 minutes.")
        #expect(metricDebrief.formInsightBullet == "Held steady 168 SPM turnover across the run.")
        #expect(metricDebrief.elapsedFormatted == "30:00")
        #expect(metricDebrief.distanceFormatted == "6.00 km")
        #expect(metricDebrief.averagePaceFormatted == "5:00 /km")
        #expect(metricDebrief.averageHeartRateFormatted == "145 BPM")
        #expect(metricDebrief.averageCadenceFormatted == "168 SPM")

        // Imperial debrief
        let imperialDebrief = core.buildRunDebrief(
            elapsedSeconds: 1800,
            totalDistanceMeters: 6000.0,
            useMetricSystem: false
        )
        #expect(imperialDebrief.distanceFormatted == "3.73 mi")
        #expect(imperialDebrief.averagePaceFormatted == "8:03 /mi")
    }

    @Test("WatchRunDebrief: adaptations, drift onset, and cadence drop format accurately in km and mi")
    func testWatchRunDebriefWithSurgesRecoveriesAndDrift() {
        var core = AdaptivePacingCore(
            profile: standardProfile,
            intent: standardIntent,
            location: .outdoor,
            configuration: .forWatchCompanion(intent: .adaptiveBase)
        )

        // Populate accumulators reflecting active adaptations session
        core.surgeCount = 2
        core.peakSurgeDeltaSecondsPerKm = 6
        core.recoveryAdjustmentCount = 1
        core.firstDriftElapsedSeconds = 1200.0 // 20 minutes
        core.cadenceBaselineSPM = 168
        core.solidCadenceUntilDistanceMeters = 4000.0 // 4.0 km / 2.485 mi
        core.latestTotalDistanceMeters = 6000.0
        core.totalPaceSumSecondsPerKm = 300.0 * 1800.0
        core.paceSampleCount = 1800
        core.totalHRSum = 152.0 * 1800.0
        core.hrSampleCount = 1800
        core.totalCadenceSum = 168.0 * 1800.0
        core.cadenceSampleCount = 1800

        // Metric review
        let metric = core.buildRunDebrief(
            elapsedSeconds: 1800,
            totalDistanceMeters: 6000.0,
            useMetricSystem: true
        )
        #expect(metric.adaptationsBullet == "2 surges (+6s/km peak), 1 recovery adjustment.")
        #expect(metric.efficiencyScoreBullet == "Stayed in live aerobic band for 20 minutes before recovery shift.")
        #expect(metric.formInsightBullet == "Held steady 168 SPM turnover until kilometer 4.")
        #expect(metric.distanceFormatted == "6.00 km")
        #expect(metric.averagePaceFormatted == "5:00 /km")
        #expect(metric.averageHeartRateFormatted == "152 BPM")
        #expect(metric.averageCadenceFormatted == "168 SPM")

        // Imperial review
        let imperial = core.buildRunDebrief(
            elapsedSeconds: 1800,
            totalDistanceMeters: 6000.0,
            useMetricSystem: false
        )
        // 6 s/km * 1.609344 = 9.65 -> 10 s/mi
        #expect(imperial.adaptationsBullet == "2 surges (+10s/mi peak), 1 recovery adjustment.")
        #expect(imperial.efficiencyScoreBullet == "Stayed in live aerobic band for 20 minutes before recovery shift.")
        // 4000 m / 1609.344 = 2.485 -> 2 mi
        #expect(imperial.formInsightBullet == "Held steady 168 SPM turnover until mile 2.")
        #expect(imperial.distanceFormatted == "3.73 mi")
        #expect(imperial.averagePaceFormatted == "8:03 /mi")
    }

    @Test("WatchRunDebrief: prioritizes true elapsed/distance average pace over unweighted sample sum")
    func testWatchRunDebriefPrioritizesTrueElapsedDistanceAveragePace() {
        var core = AdaptivePacingCore(
            profile: standardProfile,
            intent: standardIntent,
            location: .outdoor,
            configuration: .forWatchCompanion(intent: .adaptiveBase)
        )

        // Skewed instantaneous pace samples: arithmetic mean = 514 s/km (8:34 /km)
        core.totalPaceSumSecondsPerKm = 514.0 * 1800.0
        core.paceSampleCount = 1800

        // True elapsed time = 2568s, true distance = 5150.0m -> 2568 / 5.15 = 498.64 s/km (8:19 /km)
        let metric = core.buildRunDebrief(
            elapsedSeconds: 2568,
            totalDistanceMeters: 5150.0,
            useMetricSystem: true
        )
        // Must reflect true elapsed/distance pace (8:19 /km), NOT unweighted sample mean (8:34 /km)
        #expect(metric.averagePaceFormatted == "8:19 /km")

        let imperial = core.buildRunDebrief(
            elapsedSeconds: 2568,
            totalDistanceMeters: 5150.0,
            useMetricSystem: false
        )
        // 498.64 * 1.609344 = 802.48 -> 802s -> 13:22 /mi
        #expect(imperial.averagePaceFormatted == "13:22 /mi")

        // Fallback when distance <= 0: uses unweighted sample average (8:34 /km)
        let fallbackMetric = core.buildRunDebrief(
            elapsedSeconds: 2568,
            totalDistanceMeters: 0.0,
            useMetricSystem: true
        )
        #expect(fallbackMetric.averagePaceFormatted == "8:34 /km")

        // Fallback when neither is available
        core.paceSampleCount = 0
        let emptyDebrief = core.buildRunDebrief(
            elapsedSeconds: 0,
            totalDistanceMeters: 0.0,
            useMetricSystem: true
        )
        #expect(emptyDebrief.averagePaceFormatted == "--:--")
    }

    @Test("WatchRunDebrief: 5-second 0.00 km run with 1 SPM noise filters out noise and debriefs accurately")
    func testWatchRunDebriefShortRunNoiseCadence() {
        var core = AdaptivePacingCore(
            profile: standardProfile,
            intent: standardIntent,
            location: .outdoor,
            configuration: .forWatchCompanion(intent: .adaptiveBase)
        )

        // 5 seconds standing still with pedometer noise (1 SPM, 0 m/s speed)
        for s in 1...5 {
            let tick = TelemetryTick(
                elapsedSeconds: TimeInterval(s),
                heartRateBPM: 78.0,
                speedMetersPerSecond: 0.0,
                cadenceSPM: 1.0
            )
            _ = core.ingest(tick, totalDistanceMeters: 0.0)
        }

        #expect(core.cadenceSampleCount == 0, "1 SPM noise must not be accumulated as valid running cadence")

        let debrief = core.buildRunDebrief(
            elapsedSeconds: 5.0,
            totalDistanceMeters: 0.0,
            useMetricSystem: true
        )

        #expect(debrief.adaptationsBullet == "Ended before baseline pacing lock.")
        #expect(debrief.efficiencyScoreBullet == "Ended before baseline calibration completed.")
        #expect(debrief.formInsightBullet == "Insufficient cadence data recorded.")
        #expect(debrief.elapsedFormatted == "0:05")
        #expect(debrief.distanceFormatted == "0.00 km")
        #expect(debrief.averagePaceFormatted == "--:--")
        #expect(debrief.averageCadenceFormatted == "--")
    }

    @Test("WatchRunDebrief: sub-10m tiny distance or excessive pace duration returns dashed pace without spike")
    func testWatchRunDebriefTinyDistancePaceSpikeGuard() {
        let core = AdaptivePacingCore(
            profile: standardProfile,
            intent: standardIntent,
            location: .outdoor,
            configuration: .forWatchCompanion(intent: .adaptiveBase)
        )

        // 1. Sub-10m tiny distance (0.5m in 5s) without pace samples -> "--:--"
        let sub10mDebrief = core.buildRunDebrief(
            elapsedSeconds: 5.0,
            totalDistanceMeters: 0.5,
            useMetricSystem: true
        )
        #expect(sub10mDebrief.averagePaceFormatted == "--:--")

        // 2. Sub-10m with elapsed < 5s -> "--:--"
        let shortElapsedDebrief = core.buildRunDebrief(
            elapsedSeconds: 4.0,
            totalDistanceMeters: 0.5,
            useMetricSystem: true
        )
        #expect(shortElapsedDebrief.averagePaceFormatted == "--:--")

        // 3. Distance >= 10m but computed secPerKm > 1800.0 (30:00 /km) -> "--:--"
        // e.g. 10m in 20s = 20 / 0.01 = 2000 s/km > 1800 s/km
        let extremeSlowDebrief = core.buildRunDebrief(
            elapsedSeconds: 20.0,
            totalDistanceMeters: 10.0,
            useMetricSystem: true
        )
        #expect(extremeSlowDebrief.averagePaceFormatted == "--:--")

        // 4. Valid running distance and pace (100m in 30s = 300 s/km -> 5:00 /km)
        let validDebrief = core.buildRunDebrief(
            elapsedSeconds: 30.0,
            totalDistanceMeters: 100.0,
            useMetricSystem: true
        )
        #expect(validDebrief.averagePaceFormatted == "5:00 /km")
    }

    @Test("WatchRunDebrief: 1-minute drift onset uses singular minute grammar")
    func testWatchRunDebriefOneMinuteDriftGrammar() {
        var core = AdaptivePacingCore(
            profile: standardProfile,
            intent: standardIntent,
            location: .outdoor,
            configuration: .forWatchCompanion(intent: .adaptiveBase)
        )
        core.firstDriftElapsedSeconds = 60.0 // Exactly 1 minute

        let debrief = core.buildRunDebrief(
            elapsedSeconds: 300.0,
            totalDistanceMeters: 1000.0,
            useMetricSystem: true
        )
        #expect(debrief.efficiencyScoreBullet == "Stayed in live aerobic band for 1 minute before recovery shift.")
    }

    @Test("WatchRunDebrief: warmup at low cadence followed by solid cadence produces across the run insight")
    func testWatchRunDebriefWarmupThenSolidCadence() {
        var core = AdaptivePacingCore(
            profile: standardProfile,
            intent: PacingSessionIntent(
                targetPaceSecondsPerKm: 300,
                intent: .steady,
                subjectiveDistress: false,
                validForDay: "2026-11-12",
                targetCadenceSPM: 150
            ),
            location: .outdoor,
            configuration: .forWatchCompanion(intent: .adaptiveBase)
        )
        core.state = .tracking
        core.cadenceBaselineSPM = 150

        // Warmup: 40 seconds at 135 SPM (below 150 floor)
        var currentDist = 0.0
        for s in 1...40 {
            currentDist += 3.33
            let tick = TelemetryTick(
                elapsedSeconds: TimeInterval(s),
                heartRateBPM: 140.0,
                speedMetersPerSecond: 3.33,
                cadenceSPM: 135.0
            )
            _ = core.ingest(tick, totalDistanceMeters: currentDist)
        }

        // Must NOT record solidCadenceUntilDistanceMeters during initial warmup before solid cadence was established
        #expect(core.solidCadenceUntilDistanceMeters == nil)
        #expect(!core.hasEstablishedSolidCadence)

        // Solid running: settles into 150 SPM for remainder of the run (100 ticks)
        for s in 41...140 {
            currentDist += 3.33
            let tick = TelemetryTick(
                elapsedSeconds: TimeInterval(s),
                heartRateBPM: 145.0,
                speedMetersPerSecond: 3.33,
                cadenceSPM: 150.0
            )
            _ = core.ingest(tick, totalDistanceMeters: currentDist)
        }

        #expect(core.hasEstablishedSolidCadence)
        #expect(core.solidCadenceUntilDistanceMeters == nil)

        let debrief = core.buildRunDebrief(
            elapsedSeconds: 140,
            totalDistanceMeters: 5150.0,
            useMetricSystem: true
        )
        // Must NOT emit "until kilometer 1." — must report across the run
        #expect(debrief.formInsightBullet == "Held steady 150 SPM turnover across the run.")
    }

    @Test("WatchRunDebrief: solid cadence drop after establishment records distance only after debounce")
    func testWatchRunDebriefSolidCadenceDropAfterEstablishment() {
        var core = AdaptivePacingCore(
            profile: standardProfile,
            intent: PacingSessionIntent(
                targetPaceSecondsPerKm: 300,
                intent: .steady,
                subjectiveDistress: false,
                validForDay: "2026-11-12",
                targetCadenceSPM: 168
            ),
            location: .outdoor,
            configuration: .forWatchCompanion(intent: .adaptiveBase, cadenceFloorSPM: 140)
        )
        core.state = .tracking
        core.cadenceBaselineSPM = 168

        // Establish solid cadence in tracking (35 seconds of healthy 168 SPM)
        var currentDist = 0.0
        for s in 1...35 {
            currentDist += 3.33
            let tick = TelemetryTick(
                elapsedSeconds: TimeInterval(s),
                heartRateBPM: 145.0,
                speedMetersPerSecond: 3.33,
                cadenceSPM: 168.0
            )
            _ = core.ingest(tick, totalDistanceMeters: currentDist)
        }
        #expect(core.hasEstablishedSolidCadence)
        #expect(core.solidCadenceUntilDistanceMeters == nil)

        // Now drop cadence to 140 SPM.
        // Advance until the 30-second rolling window drops below threshold (168 - 6 = 162 SPM)
        var currentTick = 36
        currentDist = 4000.0
        while currentTick < 100 {
            currentDist += 3.33
            let tick = TelemetryTick(
                elapsedSeconds: TimeInterval(currentTick),
                heartRateBPM: 145.0,
                speedMetersPerSecond: 3.33,
                cadenceSPM: 140.0
            )
            _ = core.ingest(tick, totalDistanceMeters: currentDist)
            currentTick += 1
            if let shortCadence = core.ringBuffer.shortWindowStats(for: .cadence),
               Double(Int(shortCadence.mean.rounded())) < Double(168) - core.configuration.cadenceDriftThresholdSPM {
                break
            }
        }

        // Next 10 ticks in drop (total 11s < 12s debounce)
        for _ in 1...10 {
            currentDist += 3.33
            let tick = TelemetryTick(
                elapsedSeconds: TimeInterval(currentTick),
                heartRateBPM: 145.0,
                speedMetersPerSecond: 3.33,
                cadenceSPM: 140.0
            )
            _ = core.ingest(tick, totalDistanceMeters: currentDist)
            currentTick += 1
        }
        #expect(core.solidCadenceUntilDistanceMeters == nil, "11s of drift must not set solidCadenceUntilDistanceMeters")

        // 12th tick triggers debounce threshold
        currentDist += 3.33
        let tick12 = TelemetryTick(
            elapsedSeconds: TimeInterval(currentTick),
            heartRateBPM: 145.0,
            speedMetersPerSecond: 3.33,
            cadenceSPM: 140.0
        )
        _ = core.ingest(tick12, totalDistanceMeters: currentDist)
        currentTick += 1
        #expect(core.solidCadenceUntilDistanceMeters != nil)

        let debrief = core.buildRunDebrief(
            elapsedSeconds: TimeInterval(currentTick),
            totalDistanceMeters: 5000.0,
            useMetricSystem: true
        )
        #expect(debrief.formInsightBullet == "Held steady 168 SPM turnover until kilometer 4.")
    }

    @Test("WatchRunDebrief: sub-1km solid cadence distance falls back to across the run")
    func testWatchRunDebriefSub1KmFallback() {
        var core = AdaptivePacingCore(
            profile: standardProfile,
            intent: standardIntent,
            location: .outdoor,
            configuration: .forWatchCompanion(intent: .adaptiveBase)
        )
        core.cadenceBaselineSPM = 168

        // Metric: < 1000m falls back to "across the run"
        core.solidCadenceUntilDistanceMeters = 850.0
        let metric = core.buildRunDebrief(elapsedSeconds: 600, totalDistanceMeters: 2000.0, useMetricSystem: true)
        #expect(metric.formInsightBullet == "Held steady 168 SPM turnover across the run.")

        // Metric: >= 1000m emits "until kilometer"
        core.solidCadenceUntilDistanceMeters = 1000.0
        let metricAt1Km = core.buildRunDebrief(elapsedSeconds: 600, totalDistanceMeters: 2000.0, useMetricSystem: true)
        #expect(metricAt1Km.formInsightBullet == "Held steady 168 SPM turnover until kilometer 1.")

        // Imperial: < 1609.344m falls back to "across the run"
        core.solidCadenceUntilDistanceMeters = 1500.0
        let imperialSubMile = core.buildRunDebrief(elapsedSeconds: 600, totalDistanceMeters: 2000.0, useMetricSystem: false)
        #expect(imperialSubMile.formInsightBullet == "Held steady 168 SPM turnover across the run.")

        // Imperial: >= 1609.344m emits "until mile"
        core.solidCadenceUntilDistanceMeters = 1610.0
        let imperialAt1Mile = core.buildRunDebrief(elapsedSeconds: 600, totalDistanceMeters: 2000.0, useMetricSystem: false)
        #expect(imperialAt1Mile.formInsightBullet == "Held steady 168 SPM turnover until mile 1.")
    }

    // MARK: - 6. Watch Voice Delivery Target Resolution

    @Test("WatchVoiceDeliveryTarget: resolves routing based on bluetooth headphones and companion reachability")
    func testWatchVoiceDeliveryTargetResolutionTruthTable() {
        // 1. Bluetooth headphones connected to Watch -> always .watchLocal
        #expect(
            WatchVoiceDeliveryTarget.resolve(
                watchHasBluetoothHeadphoneRoute: true,
                isCompanionReachable: true
            ) == .watchLocal
        )
        #expect(
            WatchVoiceDeliveryTarget.resolve(
                watchHasBluetoothHeadphoneRoute: true,
                isCompanionReachable: false
            ) == .watchLocal
        )

        // 2. No Bluetooth headphones on Watch, companion phone reachable -> relay
        #expect(
            WatchVoiceDeliveryTarget.resolve(
                watchHasBluetoothHeadphoneRoute: false,
                isCompanionReachable: true
            ) == .companionRelayWithLocalFallback
        )

        // 3. No Bluetooth headphones on Watch, companion phone not reachable -> fallback to .watchLocal
        #expect(
            WatchVoiceDeliveryTarget.resolve(
                watchHasBluetoothHeadphoneRoute: false,
                isCompanionReachable: false
            ) == .watchLocal
        )
    }

    // MARK: - 7. Task 4.2 Comprehensive Scenario Tests

    @Test("Scenario (a): 4-day-off Monday 10K treadmill session opens cadenceReset -> thresholdSurge -> cooldownFloor silently with debrief and live snapshot")
    func testMondayTreadmillSessionCadenceResetThresholdSurgeCooldownFloor() {
        let readinessHint = WatchReadinessHint(
            daysSinceLastRun: 4,
            recentWalkMeters48h: 12000.0,
            hadRecentCadenceFade: false,
            hadRecentBounce: false,
            calibratedCadenceFloorSPM: 165,
            isClearedForQuality: true
        )
        let intent = PacingSessionIntent(
            targetPaceSecondsPerKm: 300,
            intent: .steady,
            subjectiveDistress: false,
            validForDay: "2026-11-16",
            targetCadenceSPM: 165,
            readinessHint: readinessHint
        )
        let config = AdaptivePacingConfiguration.forWatchCompanion(intent: .adaptiveBase)
        var core = AdaptivePacingCore(
            profile: standardProfile,
            intent: intent,
            location: .indoor,
            configuration: config
        )

        var allEmittedEvents: [PacingEvent] = []
        var latestSnapshot: WatchLiveRunSnapshot?

        // Phase 1: Minutes 0-5 (300 seconds) Calibration.
        // Stiff cadence at 158 SPM (< 165 floor), comfortable aerobic HR at 135 BPM, steady power 190 W (< topQuartile 1.45).
        for second in 1...300 {
            let tick = makeTick(
                second: second,
                hr: 135.0,
                speed: 3.333,
                power: 190.0,
                cadence: 158.0
            )
            let result = core.ingest(tick, totalDistanceMeters: Double(second) * 3.333)
            allEmittedEvents.append(contentsOf: result.events)

            if second == 300 {
                // Calibration complete: verify cadenceReset block opened
                let blockEvent = result.events.first {
                    if case .adaptiveBlockChanged(let block) = $0, block.kind == .cadenceReset { return true }
                    return false
                }
                #expect(blockEvent != nil, "Cadence reset block must open at calibration completion")
                #expect(core.activeBlock.kind == .cadenceReset)
                #expect(core.activeBlock.remainingSeconds == 180)
                #expect(core.cadenceResetCount == 1)
                #expect(result.display.activeBlockBadge?.contains("CADENCE 158->164") == true)
                #expect(result.display.activeBlockRemainingFormatted == "3:00")
                #expect(result.display.activeTactileCue?.mode == .cadenceMetronome)

                // Verify WatchLiveRunSnapshot forwards activeBlockBadge, activeBlockRemainingFormatted, and activeTactileCue
                let snapshot = result.display.makeLiveSnapshot(
                    location: .indoor,
                    runIntent: .adaptiveBase,
                    updatedAtEpochSeconds: Double(second)
                )
                #expect(snapshot.activeBlockBadge == result.display.activeBlockBadge)
                #expect(snapshot.activeBlockRemainingFormatted == result.display.activeBlockRemainingFormatted)
                #expect(snapshot.activeTactileCue == result.display.activeTactileCue)
                latestSnapshot = snapshot
            }
        }
        #expect(latestSnapshot != nil)

        // Phase 2: Cadence Reset running for 179 seconds (seconds 301 to 479).
        // Runner engages with block target (164 SPM), HR nominal at 135 BPM, power 190 W.
        for second in 301...479 {
            let tick = makeTick(
                second: second,
                hr: 135.0,
                speed: 3.333,
                power: 190.0,
                cadence: 164.0
            )
            let result = core.ingest(tick, totalDistanceMeters: Double(second) * 3.333)
            allEmittedEvents.append(contentsOf: result.events)
        }

        // Tick 480: Cadence reset block finishes (remaining reaches 0) -> activeBlock dissolves to .none,
        // and 60s post-reset cooldown begins.
        let tick480 = makeTick(
            second: 480,
            hr: 135.0,
            speed: 3.333,
            power: 190.0,
            cadence: 164.0
        )
        let result480 = core.ingest(tick480, totalDistanceMeters: 480.0 * 3.333)
        allEmittedEvents.append(contentsOf: result480.events)
        #expect(core.activeBlock.kind == .none)

        // Phase 3: Post-cadence reset cooldown (59 seconds, seconds 481 to 539).
        // Cadence settles at 166 SPM (>= 165 floor), HR 135 BPM, power 190 W.
        for second in 481...539 {
            let tick = makeTick(
                second: second,
                hr: 135.0,
                speed: 3.333,
                power: 190.0,
                cadence: 166.0
            )
            let result = core.ingest(tick, totalDistanceMeters: Double(second) * 3.333)
            allEmittedEvents.append(contentsOf: result.events)
        }

        // Phase 4: Tick 540 cooldown expires (60 ticks elapsed) -> thresholdSurge block opens!
        // Runner is warm, legs unlocked (cadence 166 >= floor), HR 135 BPM (< 0.82 * maxHR), cleared for quality.
        let tick540 = makeTick(
            second: 540,
            hr: 135.0,
            speed: 3.333,
            power: 190.0,
            cadence: 166.0
        )
        let result540 = core.ingest(tick540, totalDistanceMeters: 540.0 * 3.333)
        allEmittedEvents.append(contentsOf: result540.events)

        let thresholdBlockEvent = result540.events.first {
            if case .adaptiveBlockChanged(let block) = $0, block.kind == .thresholdSurge { return true }
            return false
        }
        #expect(thresholdBlockEvent != nil, "Threshold surge block must open after post-reset cooldown")
        #expect(core.activeBlock.kind == .thresholdSurge)
        #expect(core.activeBlock.remainingSeconds == 240)
        #expect(core.thresholdBlockCount == 1)
        #expect(result540.display.activeBlockBadge?.contains("THRESHOLD") == true)
        #expect(result540.display.activeBlockRemainingFormatted == "4:00")
        #expect(result540.display.activeTactileCue?.mode == .effortUp)

        // Phase 5: Threshold surge running for 239 seconds (seconds 541 to 779).
        // Runner pushes into surge: speed = 3.5 m/s, power = 230 W, HR = 145 BPM (< 0.88 * maxHR).
        for second in 541...779 {
            let tick = makeTick(
                second: second,
                hr: 145.0,
                speed: 3.5,
                power: 230.0,
                cadence: 170.0
            )
            let result = core.ingest(tick, totalDistanceMeters: Double(second) * 3.5)
            allEmittedEvents.append(contentsOf: result.events)
        }

        // At tick 780 (240th second of threshold block), transition to cooldownFloor automatically occurs
        let tick780 = makeTick(
            second: 780,
            hr: 145.0,
            speed: 3.5,
            power: 230.0,
            cadence: 170.0
        )
        let result780 = core.ingest(tick780, totalDistanceMeters: 780.0 * 3.5)
        allEmittedEvents.append(contentsOf: result780.events)

        #expect(core.activeBlock.kind == .cooldownFloor)
        #expect(core.activeBlock.remainingSeconds == 120)
        #expect(result780.display.activeBlockRemainingFormatted == "2:00")
        #expect(core.activeBlockBadgeTitle?.contains("COOLDOWN") == true)

        // Phase 6: Cooldown floor running for 119 seconds (seconds 781 to 899).
        // Runner floats back down to steady effort: speed = 3.333 m/s, HR = 135 BPM, cadence = 165 SPM.
        for second in 781...899 {
            let tick = makeTick(
                second: second,
                hr: 135.0,
                speed: 3.333,
                power: 190.0,
                cadence: 165.0
            )
            let result = core.ingest(tick, totalDistanceMeters: Double(second) * 3.333)
            allEmittedEvents.append(contentsOf: result.events)
        }

        // Tick 900: Cooldown floor completes (remaining reaches 0) -> activeBlock dissolves to .none
        let tick900 = makeTick(
            second: 900,
            hr: 135.0,
            speed: 3.333,
            power: 190.0,
            cadence: 165.0
        )
        let result900 = core.ingest(tick900, totalDistanceMeters: 900.0 * 3.333)
        allEmittedEvents.append(contentsOf: result900.events)
        #expect(core.activeBlock.kind == .none)

        // Phase 7: Verify Silent Voice Cue Policy across all drift, form, block, surge, and recover cues
        for event in allEmittedEvents {
            let spec = event.feedbackSpec(useMetricSystem: true)
            switch event {
            case .adaptiveBlockChanged, .surge, .surgeLockedIn, .recover, .formCheck, .paceDrift, .cadenceDrift:
                #expect(spec.voiceCueText == nil, "Event \(event) must have voiceCueText == nil")
            default:
                break
            }
        }

        // Phase 8: Verify Post-Run Debrief surfaces executed blocks in adaptationsBullet
        let debrief = core.buildRunDebrief(
            elapsedSeconds: 901.0,
            totalDistanceMeters: 3000.0,
            useMetricSystem: true
        )
        #expect(debrief.adaptationsBullet.contains("1 cadence reset block"))
        #expect(debrief.adaptationsBullet.contains("1 threshold block"))
        #expect(!debrief.adaptationsBullet.contains("Held steady baseline pacing throughout."))
    }

    @Test("Scenario (b): .adaptiveBase preserves iPhone .tempo intent vs Watch .recovery blocking surges and triggering .effortEase")
    func testAdaptiveBasePreservesTempoVsRecoveryBlocksSurgesAndTriggersEffortEase() {
        let hint = WatchReadinessHint(
            daysSinceLastRun: 1,
            recentWalkMeters48h: 6000.0,
            hadRecentCadenceFade: false,
            hadRecentBounce: false,
            calibratedCadenceFloorSPM: 168,
            isClearedForQuality: true
        )
        let iphoneIntent = PacingSessionIntent(
            targetPaceSecondsPerKm: 270,
            intent: .tempo,
            subjectiveDistress: false,
            validForDay: "2026-11-16",
            readinessHint: hint
        )
        let sessionConfig = WatchResolvedSessionConfig(
            profile: standardProfile,
            intent: iphoneIntent,
            requiresTargetPacePicker: true
        )

        // 1. .adaptiveBase preserves iPhone .tempo intent & readinessHint and retires pace picker
        let resolvedBase = sessionConfig.applying(runIntent: .adaptiveBase)
        #expect(resolvedBase.intent.intent == .tempo)
        #expect(resolvedBase.intent.readinessHint == hint)
        #expect(resolvedBase.requiresTargetPacePicker == false)

        // 2. Watch .recovery enforces .recovery intent and clears target pace picker
        let resolvedRecovery = sessionConfig.applying(runIntent: .recovery)
        #expect(resolvedRecovery.intent.intent == .recovery)
        #expect(resolvedRecovery.requiresTargetPacePicker == false)

        // 3. Running with .recovery blocks all surges even under high power/HR reserves
        let recoveryConfig = AdaptivePacingConfiguration.forWatchCompanion(intent: .recovery)
        var recoveryCore = AdaptivePacingCore(
            profile: standardProfile,
            intent: resolvedRecovery.intent,
            location: .outdoor,
            configuration: recoveryConfig
        )

        // 300s calibration at low HR (125 BPM) and high power (250 W)
        let calTicks = PacingSessionFixtures.makeSteadyEasyRun(
            durationSeconds: 300,
            targetPaceSecPerKm: 300,
            heartRate: 125.0,
            power: 250.0
        )
        for tick in calTicks { _ = recoveryCore.ingest(tick) }

        // Post-calibration: confirm surges and threshold blocks are strictly blocked
        for s in 301...360 {
            let tick = makeTick(second: s, hr: 125.0, power: 250.0)
            let result = recoveryCore.ingest(tick)
            let hasSurge = result.events.contains {
                if case .surge = $0 { return true }
                if case .adaptiveBlockChanged(let b) = $0, b.kind == .thresholdSurge { return true }
                return false
            }
            #expect(!hasSurge, "Surges must never fire during recovery intent")
        }
        #expect(recoveryCore.surgeCount == 0)
        #expect(recoveryCore.thresholdBlockCount == 0)

        // 4. When sustained HR >= 0.78 * maxHR (0.78 * 190.0 = 148.2 BPM) for >= 20 seconds, .effortEase triggers
        var effortEaseTriggered = false
        for s in 361...405 {
            let tick = makeTick(second: s, hr: 155.0, power: 200.0)
            let result = recoveryCore.ingest(tick)
            for event in result.events {
                if case .adaptiveBlockChanged(let block) = event, block.kind == .effortEase {
                    effortEaseTriggered = true
                    #expect(block.remainingSeconds == 120)
                    #expect(block.displayBadgeText.contains("EASE EFFORT"))
                    let spec = event.feedbackSpec(useMetricSystem: true)
                    #expect(spec.voiceCueText == nil)
                    #expect(spec.accentToken == .recoverAmber)
                }
            }
            if effortEaseTriggered { break }
        }
        #expect(effortEaseTriggered, "Effort ease block must trigger when sustained HR >= 0.78 * maxHR for >= 20s")
        #expect(recoveryCore.effortEaseCount == 1)
    }

    @Test("Scenario (c): Physiological mid-block abort -> effortEase + 480s lockout, 60s behavioral non-adoption dissolve + 300s -> 600s backoff, and 2-backoff per-run cap")
    func testBlockAbortsNonAdoptionAndSessionCap() {
        var tracker = AdaptiveBlockBackoffTracker()

        #expect(tracker.backoffCount == 0)
        #expect(tracker.canProposeUpwardBlock == true)
        #expect(tracker.isUpwardBlocksExhausted == false)

        // 1. Physiological mid-block abort -> records abort, sets 480s lockout
        tracker.recordPhysiologicalAbort()
        #expect(tracker.backoffCount == 1)
        #expect(tracker.upwardLockoutRemainingSeconds == 480.0)
        #expect(tracker.canProposeUpwardBlock == false)
        #expect(tracker.isUpwardBlocksExhausted == false)

        // Fast-forward 480 seconds
        for _ in 0..<480 {
            tracker.tick()
        }
        #expect(tracker.upwardLockoutRemainingSeconds == 0.0)
        #expect(tracker.canProposeUpwardBlock == true)

        // 2. Behavioral non-adoption dissolve after 60s -> doubles cooldown (300s -> 600s), sets 600s lockout
        tracker.recordBehavioralNonAdoption()
        #expect(tracker.backoffCount == 2)
        #expect(tracker.currentProposalCooldownSeconds == 600.0)
        #expect(tracker.upwardLockoutRemainingSeconds == 600.0)

        // 3. Per-run cap: backoffCount reached 2, so upward blocks are permanently exhausted
        #expect(tracker.isUpwardBlocksExhausted == true)
        #expect(tracker.canProposeUpwardBlock == false)

        // Even after ticking down the 600s lockout to 0, upward proposals remain permanently blocked
        for _ in 0..<600 {
            tracker.tick()
        }
        #expect(tracker.upwardLockoutRemainingSeconds == 0.0)
        #expect(tracker.canProposeUpwardBlock == false, "Can propose upward block must remain false once session cap is hit")

        // Live engine verification with watch companion calibration (300s lock-in):
        let intent = PacingSessionIntent(
            targetPaceSecondsPerKm: 300,
            intent: .tempo,
            subjectiveDistress: false,
            validForDay: "2026-11-16"
        )
        let config = AdaptivePacingConfiguration.forWatchCompanion(intent: .pushPerformance)
        var core = AdaptivePacingCore(
            profile: standardProfile,
            intent: intent,
            location: .indoor,
            configuration: config
        )

        // 300s calibration at 145 BPM, 190 W
        for s in 1...300 {
            _ = core.ingest(makeTick(second: s, hr: 145.0, speed: 3.333, power: 190.0, cadence: 168.0))
        }

        // At tick 300, tempo run opens thresholdSurge block!
        #expect(core.activeBlock.kind == .thresholdSurge)

        // Inject physiological spike mid-block: HR breaches 0.88 * maxHR (0.88 * 190 = 167.2 BPM, say 180 BPM)
        var abortEventEmitted = false
        var abortTick = 301
        for s in 301...325 {
            let result = core.ingest(makeTick(second: s, hr: 180.0, speed: 3.333, power: 190.0, cadence: 168.0))
            for event in result.events {
                if case .adaptiveBlockChanged(let b) = event, b.kind == .effortEase {
                    abortEventEmitted = true
                    abortTick = s
                }
            }
            if abortEventEmitted { break }
        }

        #expect(abortEventEmitted)
        #expect(core.activeBlock.kind == .effortEase)
        #expect(core.blockBackoffCount == 1)
        #expect(core.blockBackoffTracker.canProposeUpwardBlock == false)
        #expect(core.blockBackoffTracker.upwardLockoutRemainingSeconds >= 475.0)

        // Fast-forward lockout: effortEase clears after 120s, and at endLockoutTick lockout reaches 0 and opens thresholdSurge
        let endLockoutTick = abortTick + Int(core.blockBackoffTracker.upwardLockoutRemainingSeconds)
        for s in (abortTick + 1)...endLockoutTick {
            _ = core.ingest(makeTick(second: s, hr: 140.0, speed: 3.333, power: 190.0, cadence: 168.0))
        }
        #expect(core.activeBlock.kind == .thresholdSurge, "New threshold block proposes once lockout elapses")

        // Behavioral non-adoption: runner stays strictly at baseline (speed: 3.333, power: 190, HR: 140) for 60 seconds
        var dissolveEmitted = false
        for s in (endLockoutTick + 1)...(endLockoutTick + 65) {
            let res = core.ingest(makeTick(second: s, hr: 140.0, speed: 3.333, power: 190.0, cadence: 168.0))
            for event in res.events {
                if case .adaptiveBlockChanged(let b) = event, b.kind == .none {
                    dissolveEmitted = true
                }
            }
            if dissolveEmitted { break }
        }

        #expect(dissolveEmitted, "Ignored block must dissolve silently after 60s of non-adoption")
        #expect(core.activeBlock.kind == .none)
        #expect(core.blockBackoffCount == 2)
        #expect(core.blockBackoffTracker.isUpwardBlocksExhausted == true)
        #expect(core.blockBackoffTracker.canProposeUpwardBlock == false)

        // Debrief confirms 2 block backoffs
        let debrief = core.buildRunDebrief(elapsedSeconds: Double(endLockoutTick + 65), totalDistanceMeters: 3000.0)
        #expect(debrief.adaptationsBullet.contains("2 block backoffs"))
    }

    @Test("Scenario (d): .indoor +/-25% outlier speed clamping around 30s median & suppression of false outdoor-offset pace drift when HR & cadence are on-target")
    func testIndoorSpeedOutlierClampingAndFalsePaceDriftSuppression() {
        let intent = PacingSessionIntent(
            targetPaceSecondsPerKm: 300,
            intent: .steady,
            subjectiveDistress: false,
            validForDay: "2026-11-16",
            targetCadenceSPM: 170
        )
        let config = AdaptivePacingConfiguration.forWatchCompanion(intent: .adaptiveBase)
        var core = AdaptivePacingCore(
            profile: standardProfile,
            intent: intent,
            location: .indoor,
            configuration: config
        )

        // Part 1: Feed 30 seconds of steady treadmill speed at 3.0 m/s (5:33 /km)
        for s in 1...30 {
            _ = core.ingest(makeTick(second: s, hr: 140.0, speed: 3.0, power: 200.0, cadence: 168.0))
        }

        let medianSpeed = core.ringBuffer.medianSpeed(windowSeconds: 30.0)
        #expect(medianSpeed != nil)
        if let median = medianSpeed {
            #expect(abs(median - 3.0) < 0.05)
        }

        // Test clamping of high spike (e.g. 5.0 m/s = +66% jump)
        let clampedHigh = core.ringBuffer.clampedIndoorSpeed(5.0, windowSeconds: 30.0, toleranceFraction: 0.25)
        #expect(clampedHigh != nil)
        if let high = clampedHigh {
            #expect(abs(high - 3.75) < 0.05, "5.0 m/s must be clamped to 3.0 * 1.25 = 3.75 m/s")
        }

        // Test clamping of low drop (e.g. 1.0 m/s = -66% drop)
        let clampedLow = core.ringBuffer.clampedIndoorSpeed(1.0, windowSeconds: 30.0, toleranceFraction: 0.25)
        #expect(clampedLow != nil)
        if let low = clampedLow {
            #expect(abs(low - 2.25) < 0.05, "1.0 m/s must be clamped to 3.0 * 0.75 = 2.25 m/s")
        }

        // Ingest the 5.0 m/s sample and confirm ringBuffer tick was clamped before Kalman step
        _ = core.ingest(makeTick(second: 31, hr: 140.0, speed: 5.0, power: 200.0, cadence: 168.0))
        let conditionedSpeed = core.ringBuffer.latestTick?.speedMetersPerSecond
        #expect(conditionedSpeed != nil)
        if let cond = conditionedSpeed {
            #expect(cond < 4.0, "Conditioned indoor speed must be conditioned from clamped 3.75 m/s, never 5.0 m/s")
        }

        // Part 2: False outdoor-offset pace drift suppression.
        // Runner continues calibration and reaches tracking at second 300.
        for s in 32...300 {
            _ = core.ingest(makeTick(second: s, hr: 140.0, speed: 2.94, power: 200.0, cadence: 170.0))
        }

        // Now tracking: outdoor target is 300 s/km (5:00 /km), but uncalibrated wrist speed reads 2.94 m/s (340 s/km).
        // This is a 40 s/km (13%) offset. In outdoor GPS mode, this would trigger .paceDrift(tooSlow).
        // But on treadmill, HR (140 BPM < 174.8 ceiling) and IMU cadence (170 SPM >= 150 floor) are healthy.
        for s in 301...330 {
            let res = core.ingest(makeTick(second: s, hr: 140.0, speed: 2.94, power: 200.0, cadence: 170.0))
            let paceDriftEvent = res.events.first {
                if case .paceDrift = $0 { return true }
                return false
            }
            #expect(paceDriftEvent == nil, "Indoor pace drift alerts must be suppressed when HR and cadence are healthy")
            #expect(core.paceDriftDeviation == .onTarget)
            #expect(core.paceDriftContinuousSeconds == 0.0)
        }
    }

    // MARK: - 8. PacingDisplayState Compact Metric Properties

    @Test("PacingDisplayState: compact metrics format populated values and nil placeholders correctly")
    func testPacingDisplayStateCompactMetrics() {
        // 1. Initial / Unpopulated state
        let initialDisplay = PacingDisplayState.initial()
        #expect(initialDisplay.compactFilteredPaceValue == "--:--")
        #expect(initialDisplay.compactTargetPaceValue == "--:--")
        #expect(initialDisplay.compactHeartRateValue == "--")
        #expect(initialDisplay.compactCadenceValue == "--")

        // 2. Populated display state
        let populatedDisplay = PacingDisplayState(
            state: .tracking,
            targetPaceSecondsPerKm: 300,
            filteredPaceSecondsPerKm: 302,
            filteredHeartRateBPM: 148,
            deviation: .onTarget,
            refractorySecondsRemaining: 0,
            lastReason: nil,
            adjustmentsEnabled: true,
            targetPaceFormatted: "5:00 /km",
            filteredPaceFormatted: "5:02 /km",
            filteredHeartRateFormatted: "148 BPM",
            deviationTitle: "On Pace",
            calibrationProgress: nil,
            calibrationProgressFormatted: "100%",
            refractoryProgress: 0.0,
            filteredCadenceSPM: 172,
            filteredCadenceFormatted: "172 SPM"
        )
        #expect(populatedDisplay.compactFilteredPaceValue == "5:02")
        #expect(populatedDisplay.compactTargetPaceValue == "5:00")
        #expect(populatedDisplay.compactHeartRateValue == "148")
        #expect(populatedDisplay.compactCadenceValue == "172")

        // 3. Negative / Zero pace edge cases fallback to "--:--"
        let zeroPaceDisplay = PacingDisplayState(
            state: .tracking,
            targetPaceSecondsPerKm: 0,
            filteredPaceSecondsPerKm: -10,
            filteredHeartRateBPM: nil,
            deviation: .unknown,
            refractorySecondsRemaining: 0,
            lastReason: nil,
            adjustmentsEnabled: true,
            targetPaceFormatted: "--:--",
            filteredPaceFormatted: "--:--",
            filteredHeartRateFormatted: "--",
            deviationTitle: "--",
            calibrationProgress: nil,
            calibrationProgressFormatted: "--",
            refractoryProgress: 0.0,
            filteredCadenceSPM: nil,
            filteredCadenceFormatted: "--"
        )
        #expect(zeroPaceDisplay.compactFilteredPaceValue == "--:--")
        #expect(zeroPaceDisplay.compactTargetPaceValue == "--:--")
    }

    @Test("AdaptivePacingConfiguration and AdaptivePacingCore apply cadenceFloorSPM and intent targetCadenceSPM")
    func testCadenceFloorAndTargetCadenceApplication() {
        // forWatchCompanion with explicit cadenceFloorSPM overrides default 150
        let configWithFloor = AdaptivePacingConfiguration.forWatchCompanion(intent: .adaptiveBase, cadenceFloorSPM: 165)
        #expect(configWithFloor.cadenceFloorSPM == 165)

        // forWatchCompanion without cadenceFloorSPM preserves default 150
        let configDefault = AdaptivePacingConfiguration.forWatchCompanion(intent: .adaptiveBase)
        #expect(configDefault.cadenceFloorSPM == 150)

        // AdaptivePacingCore init: when intent has targetCadenceSPM > 0 and config has default floor (150),
        // floor is promoted to targetCadenceSPM
        let profile = AthleteCalibrationProfile(maxHR: 185, restingHR: 52, isFallback: false)
        let intentWithCadence = PacingSessionIntent(
            targetPaceSecondsPerKm: 300,
            intent: .steady,
            validForDay: "2026-11-14",
            targetCadenceSPM: 172
        )
        let corePromoted = AdaptivePacingCore(
            profile: profile,
            intent: intentWithCadence,
            location: .outdoor,
            configuration: .standard // cadenceFloorSPM == 150
        )
        #expect(corePromoted.configuration.cadenceFloorSPM == 172)

        // When config already had custom floor != 150, it is preserved
        var customConfig = AdaptivePacingConfiguration.standard
        customConfig.cadenceFloorSPM = 160
        let corePreserved = AdaptivePacingCore(
            profile: profile,
            intent: intentWithCadence,
            location: .outdoor,
            configuration: customConfig
        )
        #expect(corePreserved.configuration.cadenceFloorSPM == 160)
    }
}
