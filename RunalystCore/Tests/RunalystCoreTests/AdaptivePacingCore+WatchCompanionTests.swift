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
        #expect(metricSurgeSpec.voiceCueText == "Surge 4:50.")

        let imperialSurgeSpec = surge.feedbackSpec(useMetricSystem: false)
        #expect(imperialSurgeSpec.voiceCueText == "Surge 7:47.")

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
        #expect(spec.voiceCueText == "Quick steps.")

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
        #expect(metricSpec.voiceCueText == "Ease to 5:09.")

        let imperialSpec = rec.feedbackSpec(useMetricSystem: false)
        #expect(imperialSpec.voiceCueText == "Ease to 8:17.")
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
        #expect(metricDebrief.efficiencyScoreBullet == "Held baseline efficiency for all 30 minutes.")
        #expect(metricDebrief.formInsightBullet == "Cadence stayed rock-solid at 168 spm across the run.")
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
        #expect(metric.efficiencyScoreBullet == "Held baseline efficiency for 20 minutes before cardiac drift.")
        #expect(metric.formInsightBullet == "Cadence stayed rock-solid at 168 spm until kilometer 4.")
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
        #expect(imperial.efficiencyScoreBullet == "Held baseline efficiency for 20 minutes before cardiac drift.")
        // 4000 m / 1609.344 = 2.485 -> 2 mi
        #expect(imperial.formInsightBullet == "Cadence stayed rock-solid at 168 spm until mile 2.")
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

    @Test("WatchRunDebrief: 5-second 0.00 km run with 1 spm noise filters out noise and debriefs accurately")
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
        #expect(debrief.formInsightBullet == "Cadence stayed rock-solid at 150 spm across the run.")
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
            configuration: .forWatchCompanion(intent: .adaptiveBase)
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
        #expect(debrief.formInsightBullet == "Cadence stayed rock-solid at 168 spm until kilometer 4.")
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
        #expect(metric.formInsightBullet == "Cadence stayed rock-solid at 168 spm across the run.")

        // Metric: >= 1000m emits "until kilometer"
        core.solidCadenceUntilDistanceMeters = 1000.0
        let metricAt1Km = core.buildRunDebrief(elapsedSeconds: 600, totalDistanceMeters: 2000.0, useMetricSystem: true)
        #expect(metricAt1Km.formInsightBullet == "Cadence stayed rock-solid at 168 spm until kilometer 1.")

        // Imperial: < 1609.344m falls back to "across the run"
        core.solidCadenceUntilDistanceMeters = 1500.0
        let imperialSubMile = core.buildRunDebrief(elapsedSeconds: 600, totalDistanceMeters: 2000.0, useMetricSystem: false)
        #expect(imperialSubMile.formInsightBullet == "Cadence stayed rock-solid at 168 spm across the run.")

        // Imperial: >= 1609.344m emits "until mile"
        core.solidCadenceUntilDistanceMeters = 1610.0
        let imperialAt1Mile = core.buildRunDebrief(elapsedSeconds: 600, totalDistanceMeters: 2000.0, useMetricSystem: false)
        #expect(imperialAt1Mile.formInsightBullet == "Cadence stayed rock-solid at 168 spm until mile 1.")
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
}
