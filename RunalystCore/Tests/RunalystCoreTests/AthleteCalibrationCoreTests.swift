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
    }

    // MARK: - WatchReadinessHint & Intent Preservation Tests

    @Test("WatchReadinessHint: initializes with defaults and round-trips Codable cleanly")
    func testWatchReadinessHintCodable() throws {
        let hint = WatchReadinessHint(
            daysSinceLastRun: 3,
            recentWalkMeters48h: 6200.0,
            hadRecentCadenceFade: true,
            hadRecentBounce: false,
            calibratedCadenceFloorSPM: 160,
            isClearedForQuality: true
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(hint)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(WatchReadinessHint.self, from: data)

        #expect(decoded == hint)
        #expect(decoded.daysSinceLastRun == 3)
        #expect(decoded.recentWalkMeters48h == 6200.0)
        #expect(decoded.hadRecentCadenceFade == true)
        #expect(decoded.hadRecentBounce == false)
        #expect(decoded.calibratedCadenceFloorSPM == 160)
        #expect(decoded.isClearedForQuality == true)
    }

    @Test("PacingSessionIntent: decodes legacy JSON missing readinessHint gracefully")
    func testLegacyPacingSessionIntentDecoding() throws {
        let legacyJSON = """
        {
            "targetPaceSecondsPerKm": 300,
            "intent": "tempo",
            "subjectiveDistress": false,
            "validForDay": "2026-11-14"
        }
        """

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(PacingSessionIntent.self, from: Data(legacyJSON.utf8))

        #expect(decoded.intent == .tempo)
        #expect(decoded.targetPaceSecondsPerKm == 300)
        #expect(decoded.validForDay == "2026-11-14")
        #expect(decoded.readinessHint == nil)
    }

    @Test("AthleteCalibrationCore.makeIntent preserves readinessHint")
    func testMakeIntentPreservesReadinessHint() {
        let hint = WatchReadinessHint(daysSinceLastRun: 2, isClearedForQuality: true)
        let intent = AthleteCalibrationCore.makeIntent(
            spec: nil,
            subjectiveDistress: false,
            day: "2026-11-14",
            targetPaceSecondsPerKm: 310,
            readinessHint: hint
        )

        #expect(intent.readinessHint == hint)
        #expect(intent.targetPaceSecondsPerKm == 310)
        #expect(intent.intent == .steady)
    }

    @Test("resolveWatchSession and applying(runIntent:) preserve intent and readiness hint")
    func testApplyingRunIntentPreservesAdaptiveBaseAndReadinessHint() {
        let hint = WatchReadinessHint(daysSinceLastRun: 2, calibratedCadenceFloorSPM: 158, isClearedForQuality: true)
        let profile = AthleteCalibrationProfile(maxHR: 185.0, restingHR: 52.0, isFallback: false)
        let intent = PacingSessionIntent(
            targetPaceSecondsPerKm: 290,
            intent: .tempo,
            subjectiveDistress: false,
            validForDay: "2026-11-14",
            readinessHint: hint
        )
        let context = WatchPacingContext(profile: profile, intent: intent)

        let resolved = AthleteCalibrationCore.resolveWatchSession(cachedContext: context, currentDayString: "2026-11-14")
        #expect(resolved.intent.intent == .tempo)
        #expect(resolved.intent.readinessHint == hint)

        // 1. .adaptiveBase preserves synthesized intent (.tempo) and readinessHint
        let adaptiveBaseResolved = resolved.applying(runIntent: .adaptiveBase)
        #expect(adaptiveBaseResolved.intent.intent == .tempo)
        #expect(adaptiveBaseResolved.intent.readinessHint == hint)
        #expect(adaptiveBaseResolved.requiresTargetPacePicker == false)

        // 2. .recovery forces .recovery while preserving readinessHint
        let recoveryResolved = resolved.applying(runIntent: .recovery)
        #expect(recoveryResolved.intent.intent == .recovery)
        #expect(recoveryResolved.intent.readinessHint == hint)
        #expect(recoveryResolved.requiresTargetPacePicker == false)

        // 3. .pushPerformance sets .tempo when subjectiveDistress is false
        let pushResolved = resolved.applying(runIntent: .pushPerformance)
        #expect(pushResolved.intent.intent == .tempo)
        #expect(pushResolved.intent.readinessHint == hint)
        #expect(pushResolved.requiresTargetPacePicker == false)

        // 4. .pushPerformance respects subjectiveDistress override to .recovery
        let distressIntent = PacingSessionIntent(
            targetPaceSecondsPerKm: 320,
            intent: .recovery,
            subjectiveDistress: true,
            validForDay: "2026-11-14",
            readinessHint: hint
        )
        let distressContext = WatchPacingContext(profile: profile, intent: distressIntent)
        let distressResolved = AthleteCalibrationCore.resolveWatchSession(cachedContext: distressContext, currentDayString: "2026-11-14")
        let pushWithDistress = distressResolved.applying(runIntent: .pushPerformance)
        #expect(pushWithDistress.intent.intent == .recovery)
        #expect(pushWithDistress.intent.readinessHint == hint)
        #expect(pushWithDistress.requiresTargetPacePicker == false)
    }
}
