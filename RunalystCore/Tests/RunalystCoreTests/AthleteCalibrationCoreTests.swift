import Foundation
@testable import RunalystCore
import Testing

@Suite("Athlete Calibration Core Tests")
struct AthleteCalibrationCoreTests {

    private let anchorDate = Date(timeIntervalSince1970: 1_700_000_000) // Deterministic fixed timestamp

    // MARK: - Max HR & Fallback Derivation Tests

    @Test("Observed max HR: 60 s sustained peak of 187 BPM yields maxHR 187 and isFallback false")
    func testObservedMaxHR() {
        let bucket = TelemetryBucket(
            timestamp: anchorDate.addingTimeInterval(-3600),
            durationSeconds: 60.0,
            distanceMeters: 200.0,
            paceSecondsPerKm: 300.0,
            cadenceSPM: 168.0,
            heartRateBPM: 187.0
        )

        let profile = AthleteCalibrationCore.makeProfile(
            buckets: [bucket],
            restingHRSamples: [],
            age: 40,
            windowEnd: anchorDate
        )

        #expect(profile.maxHR == 187.0)
        #expect(profile.isFallback == false)
    }

    @Test("Age fallback: empty history with age 40 yields maxHR 180 via Tanaka formula")
    func testAgeFallbackTanaka() {
        // Tanaka formula: 208 - 0.7 * 40 = 180.0
        let profile = AthleteCalibrationCore.makeProfile(
            buckets: [],
            restingHRSamples: [],
            age: 40,
            windowEnd: anchorDate
        )

        #expect(profile.maxHR == 180.0)
        #expect(profile.isFallback == true)

        let directFallback = AthleteCalibrationCore.fallbackProfile(age: 40)
        #expect(directFallback.maxHR == 180.0)
        #expect(directFallback.isFallback == true)
    }

    @Test("Empty-everything fallback: nil age and empty history yields maxHR 190")
    func testEmptyEverythingFallback() {
        let profile = AthleteCalibrationCore.makeProfile(
            buckets: [],
            restingHRSamples: [],
            age: nil,
            windowEnd: anchorDate
        )

        #expect(profile.maxHR == 190.0)
        #expect(profile.isFallback == true)

        let directFallback = AthleteCalibrationCore.fallbackProfile(age: nil)
        #expect(directFallback.maxHR == 190.0)
        #expect(directFallback.isFallback == true)
    }

    // MARK: - Resting HR & Power/HR Quantiles

    @Test("Derives resting HR median for odd and even sample sets")
    func testRestingHRMedian() {
        // Odd count: sorted [50, 52, 54, 56, 58] -> median 54.0
        let profileOdd = AthleteCalibrationCore.makeProfile(
            buckets: [],
            restingHRSamples: [54.0, 52.0, 58.0, 50.0, 56.0],
            age: 30,
            windowEnd: anchorDate
        )
        #expect(profileOdd.restingHR == 54.0)

        // Even count: sorted [50, 52, 54, 56] -> median (52 + 54) / 2 = 53.0
        let profileEven = AthleteCalibrationCore.makeProfile(
            buckets: [],
            restingHRSamples: [54.0, 50.0, 56.0, 52.0],
            age: 30,
            windowEnd: anchorDate
        )
        #expect(profileEven.restingHR == 53.0)
    }

    @Test("Derives 75th percentile of historical power-to-HR ratio during steady runs")
    func testPowerToHRTopQuartile() {
        // Five buckets with power/HR ratios: [1.333, 1.400, 1.500, 1.600, 1.700]
        let powers = [200.0, 210.0, 225.0, 240.0, 255.0]
        let buckets = powers.enumerated().map { index, power in
            TelemetryBucket(
                timestamp: anchorDate.addingTimeInterval(-Double((index + 1) * 3600)),
                durationSeconds: 60.0,
                distanceMeters: 200.0,
                paceSecondsPerKm: 300.0,
                cadenceSPM: 168.0,
                heartRateBPM: 150.0,
                powerWatts: power
            )
        }

        let profile = AthleteCalibrationCore.makeProfile(
            buckets: buckets,
            restingHRSamples: [],
            age: 35,
            windowEnd: anchorDate
        )

        // 75th percentile of 5 items is at index 3 -> 240 / 150 = 1.60
        guard let p75 = profile.powerToHRTopQuartile else {
            Issue.record("powerToHRTopQuartile should not be nil")
            return
        }
        #expect(abs(p75 - 1.60) < 0.001)
    }

    // MARK: - Prescription Intent Mapping Tests

    @Test("Prescription intent mapping: recovery and subjective distress map to recovery")
    func testPrescriptionMappingRecovery() {
        let recoverySpec = PlannedSessionSpec(
            title: "Easy Aerobic Recovery Flush",
            minutesLow: 30,
            minutesHigh: 40
        )
        let intentRecovery = AthleteCalibrationCore.makeIntent(spec: recoverySpec, day: "2026-11-09")
        #expect(intentRecovery.intent == .recovery)
        #expect(intentRecovery.subjectiveDistress == false)

        // Protection Mandate: Subjective distress forces recovery even with a tempo prescription
        let tempoSpec = PlannedSessionSpec(
            title: "Threshold Tempo Surges",
            minutesLow: 45,
            minutesHigh: 55
        )
        let distressIntent = AthleteCalibrationCore.makeIntent(
            spec: tempoSpec,
            subjectiveDistress: true,
            day: "2026-11-09"
        )
        #expect(distressIntent.intent == .recovery)
        #expect(distressIntent.subjectiveDistress == true)
    }

    @Test("Prescription intent mapping: intervals disable adjustments in AdaptivePacingCore")
    func testPrescriptionMappingIntervals() {
        let intervalSpec = PlannedSessionSpec(
            title: "Track Intervals 6x800m",
            minutesLow: 45,
            minutesHigh: 55
        )
        let intent = AthleteCalibrationCore.makeIntent(spec: intervalSpec, day: "2026-11-09")
        #expect(intent.intent == .intervals)

        // Adaptive pacing core must disable adjustments when calibrated on intervals
        var core = AdaptivePacingCore(
            profile: AthleteCalibrationProfile(maxHR: 190, isFallback: false),
            intent: intent,
            location: .outdoor
        )
        for tick in PacingSessionFixtures.makeSteadyEasyRun(durationSeconds: 610) {
            _ = core.ingest(tick)
        }
        let latest = core.ingest(TelemetryTick(elapsedSeconds: 611, heartRateBPM: 145, speedMetersPerSecond: 3.33))
        #expect(latest.display.adjustmentsEnabled == false)
    }

    @Test("Prescription intent mapping: tempo, progression, and steady map correctly")
    func testPrescriptionMappingOtherKinds() {
        let tempoSpec = PlannedSessionSpec(title: "Marathon Pace Tempo", minutesLow: 40, minutesHigh: 50)
        #expect(AthleteCalibrationCore.makeIntent(spec: tempoSpec, day: "2026-11-09").intent == .tempo)

        let progSpec = PlannedSessionSpec(title: "Progression Long Run", minutesLow: 60, minutesHigh: 75)
        #expect(AthleteCalibrationCore.makeIntent(spec: progSpec, day: "2026-11-09").intent == .progression)

        let steadySpec = PlannedSessionSpec(title: "Steady Effort Aerobic", minutesLow: 45, minutesHigh: 50)
        #expect(AthleteCalibrationCore.makeIntent(spec: steadySpec, day: "2026-11-09").intent == .steady)

        let easySpec = PlannedSessionSpec(title: "Zone 2 Base Building", minutesLow: 45, minutesHigh: 55)
        #expect(AthleteCalibrationCore.makeIntent(spec: easySpec, day: "2026-11-09").intent == .easyAerobic)
    }

    // MARK: - WatchPacingContext Codable & Schema Tests

    @Test("WatchPacingContext Codable round-trip preserves all properties")
    func testWatchPacingContextCodableRoundTrip() throws {
        let profile = AthleteCalibrationProfile(
            maxHR: 185.0,
            restingHR: 51.0,
            powerToHRTopQuartile: 1.55,
            isFallback: false
        )
        let intent = PacingSessionIntent(
            targetPaceSecondsPerKm: 290,
            intent: .tempo,
            subjectiveDistress: false,
            validForDay: "2026-11-09"
        )
        let context = WatchPacingContext(profile: profile, intent: intent)

        #expect(context.schemaVersion == 1)
        #expect(context.isSupportedSchema == true)

        let encoder = JSONEncoder()
        let data = try encoder.encode(context)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(WatchPacingContext.self, from: data)

        #expect(decoded == context)
        #expect(decoded.schemaVersion == 1)
        #expect(decoded.profile.maxHR == 185.0)
        #expect(decoded.intent.targetPaceSecondsPerKm == 290)
        #expect(decoded.isIndoorPreferred == nil)

        // Test with explicit isIndoorPreferred: true
        let indoorContext = WatchPacingContext(profile: profile, intent: intent, isIndoorPreferred: true)
        let indoorData = try encoder.encode(indoorContext)
        let decodedIndoor = try decoder.decode(WatchPacingContext.self, from: indoorData)
        #expect(decodedIndoor == indoorContext)
        #expect(decodedIndoor.isIndoorPreferred == true)

        // Test resolution carrying through isIndoorPreferred
        let resolved = AthleteCalibrationCore.resolveWatchSession(cachedContext: indoorContext, currentDayString: "2026-11-09")
        #expect(resolved.isIndoorPreferred == true)
    }

    @Test("Forward-incompatible schema detection flags versions greater than 1 as unsupported")
    func testForwardIncompatibleSchemaDetection() {
        let profile = AthleteCalibrationProfile(maxHR: 180.0, isFallback: true)
        let intent = PacingSessionIntent(targetPaceSecondsPerKm: 300, intent: .steady, validForDay: "2026-11-09")

        let futureContext = WatchPacingContext(schemaVersion: 2, profile: profile, intent: intent)
        #expect(futureContext.schemaVersion == 2)
        #expect(futureContext.isSupportedSchema == false, "Schema version > 1 must be flagged as unsupported")
    }

    @Test("Validates session intent and context matching for declared day")
    func testDayValidationHelpers() {
        let profile = AthleteCalibrationProfile(maxHR: 180.0, isFallback: true)
        let intent = PacingSessionIntent(targetPaceSecondsPerKm: 300, intent: .steady, validForDay: "2026-11-09")
        let context = WatchPacingContext(profile: profile, intent: intent)

        #expect(AthleteCalibrationCore.isContextValidForDay(context, currentDayString: "2026-11-09") == true)
        #expect(AthleteCalibrationCore.isContextValidForDay(context, currentDayString: "2026-11-10") == false)

        #expect(AthleteCalibrationCore.isContextValidForDay(intent, currentDayString: "2026-11-09") == true)
        #expect(AthleteCalibrationCore.isContextValidForDay(intent, currentDayString: "2026-11-08") == false)

        var calendar = Calendar(identifier: .gregorian)
        guard let timeZone = TimeZone(identifier: "UTC") else {
            Issue.record("UTC timezone should be available")
            return
        }
        calendar.timeZone = timeZone
        let formatted = AthleteCalibrationCore.formatDayString(date: anchorDate, calendar: calendar)
        #expect(formatted == "2023-11-14")
    }

    // MARK: - Watch Session Resolution Tests

    @Test("WatchTargetPaceOption: exposes presets starting with Just Run followed by 240-480s steps")
    func testWatchTargetPaceOptionPresets() {
        let options = WatchTargetPaceOption.allOptions
        #expect(options.first == .justRun)
        #expect(options.first?.paceSecondsPerKm == nil)
        #expect(options.first?.label == "Just Run")

        // 240 to 480 by 15 is 17 steps + 1 (Just Run) = 18 total options
        #expect(options.count == 18)
        #expect(options[1].paceSecondsPerKm == 240)
        #expect(options[1].label == "4:00 /km")
        #expect(options.last?.paceSecondsPerKm == 480)
        #expect(options.last?.label == "8:00 /km")
    }

    @Test("WatchTargetPaceOption: label formats unit-aware pace in metric and imperial")
    func testWatchTargetPaceOptionUnitAwareLabel() {
        let justRun = WatchTargetPaceOption.justRun
        #expect(justRun.label(useMetric: true) == "Just Run")
        #expect(justRun.label(useMetric: false) == "Just Run")

        let zeroOption = WatchTargetPaceOption(id: "zero", paceSecondsPerKm: 0, label: "Zero")
        #expect(zeroOption.label(useMetric: true) == "Zero")
        #expect(zeroOption.label(useMetric: false) == "Zero")

        let negativeOption = WatchTargetPaceOption(id: "neg", paceSecondsPerKm: -15, label: "Neg")
        #expect(negativeOption.label(useMetric: true) == "Neg")
        #expect(negativeOption.label(useMetric: false) == "Neg")

        let pace300 = WatchTargetPaceOption(id: "300", paceSecondsPerKm: 300, label: "5:00 /km")
        #expect(pace300.label(useMetric: true) == "5:00 /km")
        // 300 * 1.609344 = 482.8 -> 483 -> 8:03 /mi
        #expect(pace300.label(useMetric: false) == "8:03 /mi")

        let pace240 = WatchTargetPaceOption(id: "240", paceSecondsPerKm: 240, label: "4:00 /km")
        #expect(pace240.label(useMetric: true) == "4:00 /km")
        // 240 * 1.609344 = 386.2 -> 386 -> 6:26 /mi
        #expect(pace240.label(useMetric: false) == "6:26 /mi")
    }

    @Test("resolveWatchSession: fresh context matching today disables target pace picker")
    func testResolveWatchSessionFreshContext() {
        let profile = AthleteCalibrationProfile(maxHR: 185.0, restingHR: 52.0, isFallback: false)
        let intent = PacingSessionIntent(targetPaceSecondsPerKm: 300, intent: .tempo, validForDay: "2026-11-09")
        let context = WatchPacingContext(profile: profile, intent: intent)

        let resolved = AthleteCalibrationCore.resolveWatchSession(
            cachedContext: context,
            currentDayString: "2026-11-09"
        )

        #expect(resolved.requiresTargetPacePicker == false)
        #expect(resolved.profile == profile)
        #expect(resolved.intent.intent == .tempo)
        #expect(resolved.intent.targetPaceSecondsPerKm == 300)
    }

    @Test("resolveWatchSession: stale context from prior day reuses profile but requires target pace picker")
    func testResolveWatchSessionStaleContext() {
        let profile = AthleteCalibrationProfile(maxHR: 185.0, restingHR: 52.0, isFallback: false)
        let intent = PacingSessionIntent(targetPaceSecondsPerKm: 290, intent: .tempo, validForDay: "2026-11-08")
        let context = WatchPacingContext(profile: profile, intent: intent)

        let resolved = AthleteCalibrationCore.resolveWatchSession(
            cachedContext: context,
            currentDayString: "2026-11-09",
            selectedTargetPaceSecondsPerKm: 315
        )

        #expect(resolved.requiresTargetPacePicker == true)
        #expect(resolved.profile == profile)
        #expect(resolved.intent.intent == .steady)
        #expect(resolved.intent.targetPaceSecondsPerKm == 315)
        #expect(resolved.intent.validForDay == "2026-11-09")
    }

    @Test("resolveWatchSession: nil context derives Tanaka fallback profile with age and requires picker")
    func testResolveWatchSessionNilContextWithAge() {
        let resolved = AthleteCalibrationCore.resolveWatchSession(
            cachedContext: nil,
            currentDayString: "2026-11-09",
            selectedTargetPaceSecondsPerKm: nil,
            fallbackAge: 40
        )

        #expect(resolved.requiresTargetPacePicker == true)
        #expect(resolved.profile.isFallback == true)
        #expect(resolved.profile.maxHR == 180.0) // 208 - 0.7 * 40
        #expect(resolved.intent.intent == .steady)
        #expect(resolved.intent.targetPaceSecondsPerKm == nil)
    }

    @Test("makeDrillIntent: maps structured drill prescription to intervals intent with cadence target")
    func testMakeDrillIntent() {
        let intent = AthleteCalibrationCore.makeDrillIntent(
            title: "Cadence Pyramids",
            drillId: "cadencePyramids",
            targetCadence: "165 SPM",
            durationMinutes: 10,
            day: "2026-11-09"
        )

        #expect(intent.intent == .intervals)
        #expect(intent.prescribedDrillTitle == "Cadence Pyramids")
        #expect(intent.prescribedDrillId == "cadencePyramids")
        #expect(intent.targetCadenceSPM == 165)
        #expect(intent.prescribedDurationMinutes == 10)
        #expect(intent.validForDay == "2026-11-09")

        let profile = AthleteCalibrationProfile(maxHR: 185.0, restingHR: 52.0, isFallback: false)
        let context = WatchPacingContext(profile: profile, intent: intent)

        let resolved = AthleteCalibrationCore.resolveWatchSession(
            cachedContext: context,
            currentDayString: "2026-11-09"
        )

        #expect(resolved.hasPrescribedDrill == true)
        #expect(resolved.prescribedDrillTitle == "Cadence Pyramids")
        #expect(resolved.targetCadenceFormatted == "165 SPM")
        #expect(resolved.durationFormatted == "10 Min")
        #expect(resolved.requiresTargetPacePicker == false)
        #expect(resolved.isPhoneSessionSynced == true)
    }

    // MARK: - Watch Companion Sync State & Presentation Tests

    @Test("resolveWatchSession sets isPhoneSessionSynced correctly across missing, unsupported, stale, fresh, and applying(runIntent:)")
    func testResolveWatchSessionPhoneSyncStateAndApplyingIntent() {
        let calibratedProfile = AthleteCalibrationProfile(maxHR: 185.0, restingHR: 52.0, isFallback: false)

        // 1. Missing context -> false
        let missing = AthleteCalibrationCore.resolveWatchSession(
            cachedContext: nil,
            currentDayString: "2026-11-14"
        )
        #expect(missing.isPhoneSessionSynced == false)
        #expect(missing.applying(runIntent: .pushPerformance).isPhoneSessionSynced == false)

        // 2. Unsupported schema -> false
        let futureContext = WatchPacingContext(
            schemaVersion: 2,
            profile: calibratedProfile,
            intent: PacingSessionIntent(targetPaceSecondsPerKm: 300, intent: .steady, validForDay: "2026-11-14")
        )
        let unsupported = AthleteCalibrationCore.resolveWatchSession(
            cachedContext: futureContext,
            currentDayString: "2026-11-14"
        )
        #expect(unsupported.isPhoneSessionSynced == false)

        // 3. Stale prior-day context -> false (reuses profile, preserves false on applying)
        let staleContext = WatchPacingContext(
            profile: calibratedProfile,
            intent: PacingSessionIntent(targetPaceSecondsPerKm: 295, intent: .tempo, validForDay: "2026-11-13")
        )
        let stale = AthleteCalibrationCore.resolveWatchSession(
            cachedContext: staleContext,
            currentDayString: "2026-11-14"
        )
        #expect(stale.isPhoneSessionSynced == false)
        let staleApplied = stale.applying(runIntent: .recovery)
        #expect(staleApplied.isPhoneSessionSynced == false)
        #expect(staleApplied.intent.intent == .recovery)

        // 4. Fresh today context -> true (preserved on applying)
        let freshContext = WatchPacingContext(
            profile: calibratedProfile,
            intent: PacingSessionIntent(targetPaceSecondsPerKm: 300, intent: .steady, validForDay: "2026-11-14")
        )
        let fresh = AthleteCalibrationCore.resolveWatchSession(
            cachedContext: freshContext,
            currentDayString: "2026-11-14"
        )
        #expect(fresh.isPhoneSessionSynced == true)
        let freshApplied = fresh.applying(runIntent: .pushPerformance)
        #expect(freshApplied.isPhoneSessionSynced == true)
        #expect(freshApplied.isUserIntentOverride == true)
        #expect(freshApplied.intent.intent == .tempo)
        #expect(freshApplied.requiresTargetPacePicker == false)
    }

    @Test("WatchResolvedSessionConfig: applying(runIntent:) handles nil, matching intent, custom override, and drill override")
    func testApplyingRunIntentOverrideBehavior() {
        let calibratedProfile = AthleteCalibrationProfile(maxHR: 185.0, restingHR: 52.0, isFallback: false)
        let steadyIntent = PacingSessionIntent(targetPaceSecondsPerKm: 300, intent: .steady, validForDay: "2026-11-14")
        let syncedSession = WatchResolvedSessionConfig(
            profile: calibratedProfile,
            intent: steadyIntent,
            isPhoneSessionSynced: true
        )

        // 1. Initial state without override
        #expect(syncedSession.isUserIntentOverride == false)
        #expect(syncedSession.defaultRunIntentSelection == .adaptiveBase)
        #expect(syncedSession.sessionHeaderBadgeText == "TODAY'S SESSION")
        #expect(syncedSession.sessionTitle == "Aerobic Base")

        // 2. applying(runIntent: nil) preserves configuration
        let unadjusted = syncedSession.applying(runIntent: nil)
        #expect(unadjusted.isUserIntentOverride == false)
        #expect(unadjusted.sessionHeaderBadgeText == "TODAY'S SESSION")
        #expect(unadjusted.sessionTitle == "Aerobic Base")

        // 3. applying matching intent (.adaptiveBase -> .steady) preserves without override
        let matchingApplied = syncedSession.applying(runIntent: .adaptiveBase)
        #expect(matchingApplied.isUserIntentOverride == false)
        #expect(matchingApplied.sessionHeaderBadgeText == "TODAY'S SESSION")
        #expect(matchingApplied.sessionTitle == "Aerobic Base")

        // 4. applying different intent (.pushPerformance -> .tempo) marks user override
        let overridden = syncedSession.applying(runIntent: .pushPerformance)
        #expect(overridden.isUserIntentOverride == true)
        #expect(overridden.sessionHeaderBadgeText == "CUSTOM INTENT")
        #expect(overridden.sessionTitle == "Push / Performance")
        #expect(overridden.intent.intent == .tempo)
        #expect(overridden.intent.targetPaceSecondsPerKm == 300)
        #expect(overridden.requiresTargetPacePicker == false)

        // 5. applying different intent (.recovery)
        let recoveryOverridden = syncedSession.applying(runIntent: .recovery)
        #expect(recoveryOverridden.isUserIntentOverride == true)
        #expect(recoveryOverridden.sessionHeaderBadgeText == "CUSTOM INTENT")
        #expect(recoveryOverridden.sessionTitle == "Recovery")
        #expect(recoveryOverridden.intent.intent == .recovery)

        // 6. Prescribed drill default selection is nil
        let drillIntent = AthleteCalibrationCore.makeDrillIntent(
            title: "Rhythm Intervals",
            drillId: "rhythmIntervals",
            targetCadence: "174 SPM",
            durationMinutes: 12,
            day: "2026-11-14"
        )
        let drillConfig = WatchResolvedSessionConfig(
            profile: calibratedProfile,
            intent: drillIntent,
            isPhoneSessionSynced: true
        )
        #expect(drillConfig.hasPrescribedDrill == true)
        #expect(drillConfig.defaultRunIntentSelection == nil)
        #expect(drillConfig.sessionHeaderBadgeText == "PRESCRIBED DRILL")
        #expect(drillConfig.sessionTitle == "Rhythm Intervals")

        // 7. applying(runIntent: nil) on drill preserves drill
        let drillPreserved = drillConfig.applying(runIntent: nil)
        #expect(drillPreserved.hasPrescribedDrill == true)
        #expect(drillPreserved.isUserIntentOverride == false)
        #expect(drillPreserved.sessionHeaderBadgeText == "PRESCRIBED DRILL")
        #expect(drillPreserved.sessionTitle == "Rhythm Intervals")

        // 8. Overriding drill clears drill fields and sets CUSTOM INTENT
        let drillOverridden = drillConfig.applying(runIntent: .adaptiveBase)
        #expect(drillOverridden.hasPrescribedDrill == false)
        #expect(drillOverridden.isUserIntentOverride == true)
        #expect(drillOverridden.sessionHeaderBadgeText == "CUSTOM INTENT")
        #expect(drillOverridden.sessionTitle == "Aerobic Base")
        #expect(drillOverridden.intent.intent == .steady)
        #expect(drillOverridden.intent.prescribedDrillTitle == nil)
        #expect(drillOverridden.intent.targetCadenceSPM == nil)
        #expect(drillOverridden.intent.targetPaceSecondsPerKm == nil)
        #expect(drillOverridden.requiresTargetPacePicker == true)

        // 9. Standalone unsynced session override does NOT flag isUserIntentOverride (it was not synced)
        let standaloneSession = WatchResolvedSessionConfig(
            profile: calibratedProfile,
            intent: steadyIntent,
            isPhoneSessionSynced: false
        )
        let standaloneOverridden = standaloneSession.applying(runIntent: .pushPerformance)
        #expect(standaloneOverridden.isUserIntentOverride == false)
        #expect(standaloneOverridden.sessionHeaderBadgeText == "ADAPTIVE RUN")
        #expect(standaloneOverridden.sessionTitle == "Tempo & Performance")
    }

    @Test("WatchResolvedSessionConfig badges and CTA reflect synced, calibrated, standalone fallback, and drill states")
    func testCompanionStatusBadgesAndPrimaryCTA() {
        let calibratedProfile = AthleteCalibrationProfile(maxHR: 186.0, restingHR: 50.0, isFallback: false)
        let fallbackProfile = AthleteCalibrationProfile(maxHR: 180.0, restingHR: nil, isFallback: true)
        let steadyIntent = PacingSessionIntent(targetPaceSecondsPerKm: 300, intent: .steady, validForDay: "2026-11-14")
        let drillIntent = AthleteCalibrationCore.makeDrillIntent(
            title: "Rhythm Intervals",
            drillId: "rhythmIntervals",
            targetCadence: "174 SPM",
            durationMinutes: 12,
            day: "2026-11-14"
        )

        // Synced non-drill (even with fallback profile -> TODAY'S PLAN)
        let syncedFallback = WatchResolvedSessionConfig(
            profile: fallbackProfile,
            intent: steadyIntent,
            isPhoneSessionSynced: true
        )
        #expect(syncedFallback.companionStatusBadgeText == "TODAY'S PLAN")
        #expect(syncedFallback.sessionHeaderBadgeText == "TODAY'S SESSION")
        #expect(syncedFallback.primaryCtaTitle == "Start Run")

        // Calibrated profile, not synced (e.g. stale day)
        let calibratedNotSynced = WatchResolvedSessionConfig(
            profile: calibratedProfile,
            intent: steadyIntent,
            isPhoneSessionSynced: false
        )
        #expect(calibratedNotSynced.companionStatusBadgeText == "CALIBRATED PROFILE")
        #expect(calibratedNotSynced.sessionHeaderBadgeText == "ADAPTIVE RUN")
        #expect(calibratedNotSynced.primaryCtaTitle == "Start Run")

        // Fallback profile, not synced
        let standaloneFallback = WatchResolvedSessionConfig(
            profile: fallbackProfile,
            intent: steadyIntent,
            isPhoneSessionSynced: false
        )
        #expect(standaloneFallback.companionStatusBadgeText == "STANDALONE READY")
        #expect(standaloneFallback.sessionHeaderBadgeText == "ADAPTIVE RUN")
        #expect(standaloneFallback.primaryCtaTitle == "Start Run")

        // Prescribed drill takes priority on header, title, subtitle, cadence, and CTA
        let drillConfig = WatchResolvedSessionConfig(
            profile: calibratedProfile,
            intent: drillIntent,
            isPhoneSessionSynced: true
        )
        #expect(drillConfig.companionStatusBadgeText == "TODAY'S PLAN")
        #expect(drillConfig.sessionHeaderBadgeText == "PRESCRIBED DRILL")
        #expect(drillConfig.sessionTitle == "Rhythm Intervals")
        #expect(drillConfig.sessionSubtitle == "Pre-run neuromuscular primer")
        #expect(drillConfig.targetCadencePillText == "174 SPM")
        #expect(drillConfig.primaryCtaTitle == "Start Drill")

        // Drill while not synced still shows PRESCRIBED DRILL and Start Drill
        let unsyncedDrillConfig = WatchResolvedSessionConfig(
            profile: calibratedProfile,
            intent: drillIntent,
            isPhoneSessionSynced: false
        )
        #expect(unsyncedDrillConfig.sessionHeaderBadgeText == "PRESCRIBED DRILL")
        #expect(unsyncedDrillConfig.primaryCtaTitle == "Start Drill")
    }

    @Test("WatchResolvedSessionConfig maps all 6 PacingIntentKind cases to sessionTitle and sessionSubtitle")
    func testSessionTitleAndSubtitleForAllPacingIntentKinds() {
        let profile = AthleteCalibrationProfile(maxHR: 185.0, restingHR: 52.0, isFallback: false)
        let expected: [(PacingIntentKind, String, String)] = [
            (.recovery, "Easy Recovery", "Low-strain cardiac recovery"),
            (.easyAerobic, "Easy Aerobic Base", "Conversational aerobic foundation"),
            (.steady, "Aerobic Base", "Aerobic rhythm & cadence stability"),
            (.tempo, "Tempo & Performance", "Controlled threshold effort"),
            (.progression, "Progression Run", "Steady finish acceleration"),
            (.intervals, "Rhythm Intervals", "High-turnover speed repeats")
        ]

        for (kind, title, subtitle) in expected {
            let intent = PacingSessionIntent(targetPaceSecondsPerKm: 300, intent: kind, validForDay: "2026-11-14")
            let config = WatchResolvedSessionConfig(profile: profile, intent: intent, isPhoneSessionSynced: true)
            #expect(config.sessionTitle == title)
            #expect(config.sessionSubtitle == subtitle)
        }
    }

    @Test("WatchResolvedSessionConfig formats target pace in metric, imperial, and Adaptive fallback, plus cadence & aerobic ceiling pills")
    func testTargetPaceCadenceAndAerobicCeilingPills() {
        let profileWithResting = AthleteCalibrationProfile(maxHR: 190.0, restingHR: 50.0, isFallback: false)
        let profileWithoutResting = AthleteCalibrationProfile(maxHR: 190.0, restingHR: nil, isFallback: true)
        let profileInvalidResting = AthleteCalibrationProfile(maxHR: 180.0, restingHR: 0.0, isFallback: false)
        let profileInvertedResting = AthleteCalibrationProfile(maxHR: 180.0, restingHR: 190.0, isFallback: false)

        // 300 s/km -> 5:00 /km, 300 * 1.60934 = 482.802 -> 483 s/mi = 8:03 /mi
        let pacedIntent = PacingSessionIntent(targetPaceSecondsPerKm: 300, intent: .steady, validForDay: "2026-11-14")
        let pacedConfig = WatchResolvedSessionConfig(profile: profileWithResting, intent: pacedIntent)
        #expect(pacedConfig.targetPaceFormatted() == "5:00 /km")
        #expect(pacedConfig.targetPaceFormatted(useMetric: true) == "5:00 /km")
        #expect(pacedConfig.targetPaceFormatted(useMetric: false) == "8:03 /mi")
        #expect(pacedConfig.targetCadencePillText == "Adaptive")

        // Karvonen 78% HRR: 50 + 0.78 * (190 - 50) = 50 + 109.2 = 159.2 -> 159
        #expect(pacedConfig.aerobicCeilingPillText == "<159 BPM")

        // Nil, zero, and negative target pace -> Adaptive
        let nilPaceConfig = WatchResolvedSessionConfig(
            profile: profileWithoutResting,
            intent: PacingSessionIntent(targetPaceSecondsPerKm: nil, intent: .steady, validForDay: "2026-11-14")
        )
        #expect(nilPaceConfig.targetPaceFormatted(useMetric: true) == "Adaptive")
        #expect(nilPaceConfig.targetPaceFormatted(useMetric: false) == "Adaptive")
        // MaxHR fallback 78%: 190 * 0.78 = 148.2 -> 148
        #expect(nilPaceConfig.aerobicCeilingPillText == "<148 BPM")

        let zeroPaceConfig = WatchResolvedSessionConfig(
            profile: profileInvalidResting,
            intent: PacingSessionIntent(targetPaceSecondsPerKm: 0, intent: .steady, validForDay: "2026-11-14")
        )
        #expect(zeroPaceConfig.targetPaceFormatted(useMetric: true) == "Adaptive")
        // 180 * 0.78 = 140.4 -> 140
        #expect(zeroPaceConfig.aerobicCeilingPillText == "<140 BPM")

        let negativePaceConfig = WatchResolvedSessionConfig(
            profile: profileInvertedResting,
            intent: PacingSessionIntent(targetPaceSecondsPerKm: -15, intent: .steady, validForDay: "2026-11-14")
        )
        #expect(negativePaceConfig.targetPaceFormatted(useMetric: false) == "Adaptive")
        #expect(negativePaceConfig.aerobicCeilingPillText == "<140 BPM")
    }

    @Test("WatchRunDebrief exposes companion sync badge and subtitle")
    func testWatchRunDebriefCompanionSyncPresentation() {
        let debrief = WatchRunDebrief(
            adaptationsBullet: "Held steady baseline pacing throughout.",
            efficiencyScoreBullet: "Stayed in live aerobic band for all 30 minutes.",
            formInsightBullet: "Held steady 168 SPM turnover across the run.",
            elapsedFormatted: "30:00",
            distanceFormatted: "6.00 km",
            averagePaceFormatted: "5:00 /km",
            averageHeartRateFormatted: "145 BPM",
            averageCadenceFormatted: "168 SPM"
        )

        #expect(debrief.companionSyncBadgeText == "RUN COMPLETE")
        #expect(debrief.companionSyncSubtitle == "Saved to Apple Health")
    }

    @Test("WatchRunDebrief: compact hero formatters extract numerical tokens and units with fallbacks")
    func testWatchRunDebriefCompactHeroFormatters() {
        // Populated metric debrief
        let metricDebrief = WatchRunDebrief(
            adaptationsBullet: "Held steady baseline pacing throughout.",
            efficiencyScoreBullet: "Stayed in live aerobic band for all 30 minutes.",
            formInsightBullet: "Held steady 172 SPM turnover across the run.",
            elapsedFormatted: "32:15",
            distanceFormatted: "6.20 km",
            averagePaceFormatted: "5:17 /km",
            averageHeartRateFormatted: "152 BPM",
            averageCadenceFormatted: "172 SPM"
        )
        #expect(metricDebrief.primaryDistanceValue == "6.20")
        #expect(metricDebrief.distanceUnitLabel == "KM")
        #expect(metricDebrief.compactPaceValue == "5:17")
        #expect(metricDebrief.compactHeartRateValue == "152")
        #expect(metricDebrief.compactCadenceValue == "172")

        // Populated imperial debrief
        let imperialDebrief = WatchRunDebrief(
            adaptationsBullet: "Held steady baseline pacing throughout.",
            efficiencyScoreBullet: "Stayed in live aerobic band for all 30 minutes.",
            formInsightBullet: "Held steady 168 SPM turnover across the run.",
            elapsedFormatted: "32:15",
            distanceFormatted: "3.85 mi",
            averagePaceFormatted: "8:30 /mi",
            averageHeartRateFormatted: "150 BPM",
            averageCadenceFormatted: "168 SPM"
        )
        #expect(imperialDebrief.primaryDistanceValue == "3.85")
        #expect(imperialDebrief.distanceUnitLabel == "MI")
        #expect(imperialDebrief.compactPaceValue == "8:30")
        #expect(imperialDebrief.compactHeartRateValue == "150")
        #expect(imperialDebrief.compactCadenceValue == "168")

        // Fallback debrief
        let fallbackDebrief = WatchRunDebrief(
            adaptationsBullet: "Ended before baseline pacing lock.",
            efficiencyScoreBullet: "Ended before baseline calibration completed.",
            formInsightBullet: "Insufficient cadence data recorded.",
            elapsedFormatted: "0:04",
            distanceFormatted: "--",
            averagePaceFormatted: "--:--",
            averageHeartRateFormatted: "--",
            averageCadenceFormatted: "--"
        )
        #expect(fallbackDebrief.primaryDistanceValue == "--")
        #expect(fallbackDebrief.distanceUnitLabel == "")
        #expect(fallbackDebrief.compactPaceValue == "--:--")
        #expect(fallbackDebrief.compactHeartRateValue == "--")
        #expect(fallbackDebrief.compactCadenceValue == "--")
    }

    @Test("PacingDisplayState: unit-aware pace formatting and compact values")
    func testPacingDisplayStateUnitAwarePaceFormatting() {
        let initial = PacingDisplayState.initial()
        #expect(initial.filteredPaceFormatted(useMetric: true) == "--:--")
        #expect(initial.filteredPaceFormatted(useMetric: false) == "--:--")
        #expect(initial.targetPaceFormatted(useMetric: true) == "--:--")
        #expect(initial.targetPaceFormatted(useMetric: false) == "--:--")
        #expect(initial.compactFilteredPaceValue(useMetric: true) == "--:--")
        #expect(initial.compactFilteredPaceValue(useMetric: false) == "--:--")
        #expect(initial.compactTargetPaceValue(useMetric: true) == "--:--")
        #expect(initial.compactTargetPaceValue(useMetric: false) == "--:--")

        let customDisplay = PacingDisplayState(
            state: .tracking,
            targetPaceSecondsPerKm: 300,
            filteredPaceSecondsPerKm: 302,
            filteredHeartRateBPM: 145,
            deviation: .onTarget,
            refractorySecondsRemaining: 0,
            lastReason: nil,
            adjustmentsEnabled: true,
            targetPaceFormatted: "5:00 /km",
            filteredPaceFormatted: "5:02 /km",
            filteredHeartRateFormatted: "145 BPM",
            deviationTitle: "On Target",
            calibrationProgress: nil,
            calibrationProgressFormatted: "--",
            refractoryProgress: 0.0
        )

        // Target pace: 300 s/km -> 5:00 /km, 483 s/mi -> 8:03 /mi
        #expect(customDisplay.targetPaceFormatted(useMetric: true) == "5:00 /km")
        #expect(customDisplay.targetPaceFormatted(useMetric: false) == "8:03 /mi")
        #expect(customDisplay.compactTargetPaceValue(useMetric: true) == "5:00")
        #expect(customDisplay.compactTargetPaceValue(useMetric: false) == "8:03")
        #expect(customDisplay.compactTargetPaceValue == "5:00")

        // Filtered pace: 302 s/km -> 5:02 /km, 302 * 1.609344 = 486.02 -> 486 -> 8:06 /mi
        #expect(customDisplay.filteredPaceFormatted(useMetric: true) == "5:02 /km")
        #expect(customDisplay.filteredPaceFormatted(useMetric: false) == "8:06 /mi")
        #expect(customDisplay.compactFilteredPaceValue(useMetric: true) == "5:02")
        #expect(customDisplay.compactFilteredPaceValue(useMetric: false) == "8:06")
        #expect(customDisplay.compactFilteredPaceValue == "5:02")

        // Pace unit labels
        #expect(customDisplay.paceUnitLabel(useMetric: true) == "/KM")
        #expect(customDisplay.paceUnitLabel(useMetric: false) == "/MI")

        // Non-positive / zero checks
        let zeroDisplay = PacingDisplayState(
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
            refractoryProgress: 0.0
        )
        #expect(zeroDisplay.targetPaceFormatted(useMetric: true) == "--:--")
        #expect(zeroDisplay.targetPaceFormatted(useMetric: false) == "--:--")
        #expect(zeroDisplay.filteredPaceFormatted(useMetric: true) == "--:--")
        #expect(zeroDisplay.filteredPaceFormatted(useMetric: false) == "--:--")
        #expect(zeroDisplay.compactTargetPaceValue(useMetric: true) == "--:--")
        #expect(zeroDisplay.compactTargetPaceValue(useMetric: false) == "--:--")
        #expect(zeroDisplay.compactFilteredPaceValue(useMetric: true) == "--:--")
        #expect(zeroDisplay.compactFilteredPaceValue(useMetric: false) == "--:--")
    }

    @Test("PacingDisplayState: splitProgressFraction calculates metric and imperial progress with calibration fallback")
    func testSplitProgressFraction() {
        // Zero / nil distance default
        let zeroDistance = PacingDisplayState.initial()
        #expect(zeroDistance.splitProgressFraction(useMetric: true) == 0.0)
        #expect(zeroDistance.splitProgressFraction(useMetric: false) == 0.0)

        // Calibration fallback when no distance
        let calibratingDisplay = PacingDisplayState(
            state: .calibrating(progress: 0.65),
            targetPaceSecondsPerKm: 300,
            filteredPaceSecondsPerKm: nil,
            filteredHeartRateBPM: nil,
            deviation: .unknown,
            refractorySecondsRemaining: 0,
            lastReason: nil,
            adjustmentsEnabled: true,
            targetPaceFormatted: "5:00 /km",
            filteredPaceFormatted: "--:--",
            filteredHeartRateFormatted: "--",
            deviationTitle: "--",
            calibrationProgress: 0.65,
            calibrationProgressFormatted: "65%",
            refractoryProgress: 0.0,
            isCalibrating: true
        )
        #expect(calibratingDisplay.splitProgressFraction(useMetric: true) == 0.65)
        #expect(calibratingDisplay.splitProgressFraction(useMetric: false) == 0.65)

        // Metric distance tests: 620 m -> 0.62, 1340 m -> 0.34
        let display620 = PacingDisplayState(
            state: .tracking,
            targetPaceSecondsPerKm: 300,
            filteredPaceSecondsPerKm: 300,
            filteredHeartRateBPM: 140,
            deviation: .onTarget,
            refractorySecondsRemaining: 0,
            lastReason: nil,
            adjustmentsEnabled: true,
            targetPaceFormatted: "5:00 /km",
            filteredPaceFormatted: "5:00 /km",
            filteredHeartRateFormatted: "140 BPM",
            deviationTitle: "On Target",
            calibrationProgress: nil,
            calibrationProgressFormatted: "--",
            refractoryProgress: 0.0,
            totalDistanceMeters: 620.0
        )
        let progress620 = display620.splitProgressFraction(useMetric: true)
        #expect(abs(progress620 - 0.62) < 0.001)

        let display1340 = PacingDisplayState(
            state: .tracking,
            targetPaceSecondsPerKm: 300,
            filteredPaceSecondsPerKm: 300,
            filteredHeartRateBPM: 140,
            deviation: .onTarget,
            refractorySecondsRemaining: 0,
            lastReason: nil,
            adjustmentsEnabled: true,
            targetPaceFormatted: "5:00 /km",
            filteredPaceFormatted: "5:00 /km",
            filteredHeartRateFormatted: "140 BPM",
            deviationTitle: "On Target",
            calibrationProgress: nil,
            calibrationProgressFormatted: "--",
            refractoryProgress: 0.0,
            totalDistanceMeters: 1340.0
        )
        let progress1340 = display1340.splitProgressFraction(useMetric: true)
        #expect(abs(progress1340 - 0.34) < 0.001)

        // Imperial distance test: 804.672 m -> 0.50 (half of 1,609.344)
        let displayMileHalf = PacingDisplayState(
            state: .tracking,
            targetPaceSecondsPerKm: 300,
            filteredPaceSecondsPerKm: 300,
            filteredHeartRateBPM: 140,
            deviation: .onTarget,
            refractorySecondsRemaining: 0,
            lastReason: nil,
            adjustmentsEnabled: true,
            targetPaceFormatted: "5:00 /km",
            filteredPaceFormatted: "5:00 /km",
            filteredHeartRateFormatted: "140 BPM",
            deviationTitle: "On Target",
            calibrationProgress: nil,
            calibrationProgressFormatted: "--",
            refractoryProgress: 0.0,
            totalDistanceMeters: 804.672
        )
        let progressImperial = displayMileHalf.splitProgressFraction(useMetric: false)
        #expect(abs(progressImperial - 0.50) < 0.001)
    }

    @Test("PacingDisplayState: bezelPerimeterPoint calculates clockwise rounded-rectangle coordinates")
    func testBezelPerimeterPoint() {
        let width = 200.0
        let height = 240.0
        let inset = 2.5
        let cornerRadius = 38.0

        // At progress = 0.0: 12 o'clock center top (width / 2, inset)
        let startPoint = PacingDisplayState.bezelPerimeterPoint(
            progress: 0.0,
            width: width,
            height: height,
            cornerRadius: cornerRadius,
            inset: inset
        )
        #expect(abs(startPoint.x - (width / 2.0)) < 0.001)
        #expect(abs(startPoint.y - inset) < 0.001)

        // At progress = 0.5: 6 o'clock center bottom (width / 2, height - inset)
        let bottomPoint = PacingDisplayState.bezelPerimeterPoint(
            progress: 0.5,
            width: width,
            height: height,
            cornerRadius: cornerRadius,
            inset: inset
        )
        #expect(abs(bottomPoint.x - (width / 2.0)) < 0.001)
        #expect(abs(bottomPoint.y - (height - inset)) < 0.001)

        // At progress = 1.0: wraps back to (width / 2, inset)
        let endPoint = PacingDisplayState.bezelPerimeterPoint(
            progress: 1.0,
            width: width,
            height: height,
            cornerRadius: cornerRadius,
            inset: inset
        )
        #expect(abs(endPoint.x - (width / 2.0)) < 0.001)
        #expect(abs(endPoint.y - inset) < 0.001)

        // Clamping check: < 0.0 maps to 0.0, > 1.0 maps to 1.0
        let underflow = PacingDisplayState.bezelPerimeterPoint(
            progress: -0.5,
            width: width,
            height: height,
            cornerRadius: cornerRadius,
            inset: inset
        )
        #expect(abs(underflow.x - startPoint.x) < 0.001)
        #expect(abs(underflow.y - startPoint.y) < 0.001)

        let overflow = PacingDisplayState.bezelPerimeterPoint(
            progress: 1.5,
            width: width,
            height: height,
            cornerRadius: cornerRadius,
            inset: inset
        )
        #expect(abs(overflow.x - endPoint.x) < 0.001)
        #expect(abs(overflow.y - endPoint.y) < 0.001)

        // Symmetric square checks: 0.25 is right edge mid, 0.75 is left edge mid
        let squareSize = 200.0
        let rightPoint = PacingDisplayState.bezelPerimeterPoint(
            progress: 0.25,
            width: squareSize,
            height: squareSize,
            cornerRadius: cornerRadius,
            inset: inset
        )
        #expect(abs(rightPoint.x - (squareSize - inset)) < 0.001)
        #expect(abs(rightPoint.y - (squareSize / 2.0)) < 0.001)

        let leftPoint = PacingDisplayState.bezelPerimeterPoint(
            progress: 0.75,
            width: squareSize,
            height: squareSize,
            cornerRadius: cornerRadius,
            inset: inset
        )
        #expect(abs(leftPoint.x - inset) < 0.001)
        #expect(abs(leftPoint.y - (squareSize / 2.0)) < 0.001)
    }
}
