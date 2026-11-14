import Foundation
@testable import RunalystCore
import Testing

@Suite("Watch Companion State & Bidirectional Serialization Tests")
struct WatchCompanionStateTests {

    private let sampleProfile = AthleteCalibrationProfile(
        maxHR: 192.0,
        restingHR: 50.0,
        powerToHRTopQuartile: 1.48,
        isFallback: false
    )

    private let sampleIntent = PacingSessionIntent(
        targetPaceSecondsPerKm: 315,
        intent: .steady,
        subjectiveDistress: false,
        validForDay: "2026-11-12"
    )

    private let sampleDebrief = WatchRunDebrief(
        adaptationsBullet: "Maintained steady pace across all intervals.",
        efficiencyScoreBullet: "Aerobic decoupling remained under 3.5%.",
        formInsightBullet: "Cadence remained strictly above 168 SPM floor.",
        elapsedFormatted: "32:15",
        distanceFormatted: "6.20 km",
        averagePaceFormatted: "5:12 /km",
        averageHeartRateFormatted: "148 BPM",
        averageCadenceFormatted: "172 SPM"
    )

    private func isCalibrating(_ state: PacingState) -> Bool {
        if case .calibrating = state {
            return true
        }
        return false
    }

    private func makeDisplayState(
        state: PacingState,
        adjustmentsEnabled: Bool = true,
        filteredPace: String = "5:12 /km",
        targetPace: String = "5:15 /km",
        filteredHR: String = "148 BPM",
        filteredCadence: String = "172 SPM",
        elapsedTime: String = "18:45",
        deviationTitle: String = "On Target",
        calibrationProgress: Double? = nil
    ) -> PacingDisplayState {
        PacingDisplayState(
            state: state,
            targetPaceSecondsPerKm: 315,
            filteredPaceSecondsPerKm: 312,
            filteredHeartRateBPM: 148,
            deviation: .onTarget,
            refractorySecondsRemaining: 0,
            lastReason: nil,
            adjustmentsEnabled: adjustmentsEnabled,
            targetPaceFormatted: targetPace,
            filteredPaceFormatted: filteredPace,
            filteredHeartRateFormatted: filteredHR,
            deviationTitle: deviationTitle,
            calibrationProgress: calibrationProgress,
            calibrationProgressFormatted: calibrationProgress.map { "\(Int($0 * 100))%" } ?? "--",
            refractoryProgress: 0.0,
            filteredCadenceSPM: 172,
            filteredCadenceFormatted: filteredCadence,
            targetCadenceSPM: 170,
            targetCadenceFormatted: "170 SPM",
            isCalibrating: isCalibrating(state),
            elapsedTimeFormatted: elapsedTime,
            paceGaugeNormalizedPosition: 0.52,
            targetBandLowerNormalized: 0.44,
            targetBandUpperNormalized: 0.56,
            biometricStatusToken: .vibrantGreen,
            biometricStatusLabel: "Biometrics Nominal"
        )
    }

    // MARK: - 1. WatchPacingContext Backward Compatibility Tests

    @Test("Legacy WatchPacingContext payload without unit or voice fields decodes successfully with nil")
    func testLegacyPayloadWithoutUnitOrVoiceDecodesWithNil() throws {
        let legacyJSON = """
        {
            "schemaVersion": 1,
            "profile": {
                "maxHR": 190.0,
                "restingHR": 52.0,
                "powerToHRTopQuartile": 1.45,
                "isFallback": false
            },
            "intent": {
                "targetPaceSecondsPerKm": 300,
                "intent": "steady",
                "subjectiveDistress": false,
                "validForDay": "2026-11-12"
            },
            "isIndoorPreferred": true
        }
        """

        let data = try #require(legacyJSON.data(using: .utf8))
        let decoded = try JSONDecoder().decode(WatchPacingContext.self, from: data)

        #expect(decoded.schemaVersion == 1)
        #expect(decoded.isSupportedSchema)
        #expect(decoded.isIndoorPreferred == true)
        #expect(decoded.useMetricSystem == nil)
        #expect(decoded.watchVoiceCuesEnabled == nil)
        #expect(decoded.intent.targetPaceSecondsPerKm == 300)
    }

    @Test("WatchPacingContext preserves unit and voice preferences across round-trip serialization")
    func testModernPayloadRoundTripPreservesExplicitUnitAndVoicePreferences() throws {
        let context = WatchPacingContext(
            profile: sampleProfile,
            intent: sampleIntent,
            isIndoorPreferred: false,
            useMetricSystem: false,
            watchVoiceCuesEnabled: true
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(context)
        let decoded = try JSONDecoder().decode(WatchPacingContext.self, from: data)

        #expect(decoded == context)
        #expect(decoded.useMetricSystem == false)
        #expect(decoded.watchVoiceCuesEnabled == true)
        #expect(decoded.isIndoorPreferred == false)
        #expect(decoded.schemaVersion == WatchPacingContext.currentSchemaVersion)
    }

    @Test("WatchPacingContext with metric true and voice cues disabled round-trips correctly")
    func testMetricAndVoiceCuesDisabledRoundTrip() throws {
        let context = WatchPacingContext(
            profile: sampleProfile,
            intent: sampleIntent,
            isIndoorPreferred: true,
            useMetricSystem: true,
            watchVoiceCuesEnabled: false
        )

        let data = try JSONEncoder().encode(context)
        let decoded = try JSONDecoder().decode(WatchPacingContext.self, from: data)

        #expect(decoded == context)
        #expect(decoded.useMetricSystem == true)
        #expect(decoded.watchVoiceCuesEnabled == false)
        #expect(decoded.isIndoorPreferred == true)
    }

    // MARK: - 2. WatchLiveRunSnapshot Phase Mapping Tests

    @Test("Phase mapping: calibrating state maps to .calibrating with active workout true")
    func testPhaseMappingCalibrating() {
        let display = makeDisplayState(
            state: .calibrating(progress: 0.45),
            calibrationProgress: 0.45
        )
        let snapshot = WatchLiveRunSnapshot.from(
            displayState: display,
            location: .outdoor,
            runIntent: .adaptiveBase,
            isPaused: false,
            isCompleted: false,
            updatedAtEpochSeconds: 100.0
        )

        #expect(snapshot.phase == WatchCompanionPhase.calibrating)
        #expect(snapshot.isActiveWorkout == true)
        #expect(snapshot.stateTitle == "Calibrating")
        #expect(snapshot.headerTitle == "Adaptive Base")
        #expect(snapshot.calibrationProgress == 0.45)
        #expect(snapshot.completedDebrief == nil)
    }

    @Test("Phase mapping: tracking state maps to .running with active workout true")
    func testPhaseMappingTracking() {
        let display = makeDisplayState(state: .tracking)
        let snapshot = WatchLiveRunSnapshot.from(
            displayState: display,
            location: .outdoor,
            runIntent: .adaptiveBase,
            isPaused: false,
            isCompleted: false,
            updatedAtEpochSeconds: 200.0
        )

        #expect(snapshot.phase == .running)
        #expect(snapshot.isActiveWorkout == true)
        #expect(snapshot.stateTitle == "Adaptive Pacing")
        #expect(snapshot.headerTitle == "Adaptive Base")

        let monitorDisplay = makeDisplayState(state: .tracking, adjustmentsEnabled: false)
        let monitorSnapshot = WatchLiveRunSnapshot.from(
            displayState: monitorDisplay,
            location: .outdoor,
            runIntent: .adaptiveBase,
            updatedAtEpochSeconds: 201.0
        )
        #expect(monitorSnapshot.stateTitle == "Monitor Only")
    }

    @Test("Phase mapping: surge state maps to .surge with active workout true")
    func testPhaseMappingSurge() {
        let display = makeDisplayState(state: .surge)
        let snapshot = WatchLiveRunSnapshot.from(
            displayState: display,
            location: .outdoor,
            runIntent: .pushPerformance,
            isPaused: false,
            isCompleted: false,
            updatedAtEpochSeconds: 300.0
        )

        #expect(snapshot.phase == .surge)
        #expect(snapshot.isActiveWorkout == true)
        #expect(snapshot.stateTitle == "Surge")
        #expect(snapshot.headerTitle == "Push / Performance")
    }

    @Test("Phase mapping: recover state maps to .recover with active workout true")
    func testPhaseMappingRecover() {
        let display = makeDisplayState(state: .recover)
        let snapshot = WatchLiveRunSnapshot.from(
            displayState: display,
            location: .indoor,
            runIntent: .recovery,
            isPaused: false,
            isCompleted: false,
            updatedAtEpochSeconds: 400.0
        )

        #expect(snapshot.phase == .recover)
        #expect(snapshot.isActiveWorkout == true)
        #expect(snapshot.stateTitle == "Recover")
        #expect(snapshot.headerTitle == "Recovery")
    }

    @Test("Phase mapping: paused workout maps to .paused, isActiveWorkout true, headerTitle 'Apple Watch Paused'")
    func testPhaseMappingPaused() {
        let display = makeDisplayState(state: .tracking)
        let snapshot = WatchLiveRunSnapshot.from(
            displayState: display,
            location: .outdoor,
            runIntent: .adaptiveBase,
            prescribedDrillTitle: "Cadence Pyramids",
            isPaused: true,
            isCompleted: false,
            updatedAtEpochSeconds: 500.0
        )

        #expect(snapshot.phase == .paused)
        #expect(snapshot.isActiveWorkout == true)
        #expect(snapshot.stateTitle == "Paused")
        #expect(snapshot.headerTitle == "Apple Watch Paused")
    }

    @Test("Phase mapping: completed workout maps to .completed, isActiveWorkout false, preserves debrief 3-bullet fields")
    func testPhaseMappingCompletedWithDebrief() {
        let display = makeDisplayState(state: .tracking)
        let snapshot = WatchLiveRunSnapshot.from(
            displayState: display,
            location: .outdoor,
            runIntent: .adaptiveBase,
            prescribedDrillTitle: "Cadence Pyramids",
            isPaused: false,
            isCompleted: true,
            completedDebrief: sampleDebrief,
            updatedAtEpochSeconds: 600.0
        )

        #expect(snapshot.phase == .completed)
        #expect(snapshot.isActiveWorkout == false)
        #expect(snapshot.stateTitle == "Completed")
        #expect(snapshot.headerTitle == "Coach's Takeaway")

        let debrief = snapshot.completedDebrief
        #expect(debrief != nil)
        #expect(debrief?.adaptationsBullet == "Maintained steady pace across all intervals.")
        #expect(debrief?.efficiencyScoreBullet == "Aerobic decoupling remained under 3.5%.")
        #expect(debrief?.formInsightBullet == "Cadence remained strictly above 168 SPM floor.")
        #expect(debrief?.elapsedFormatted == "32:15")
        #expect(debrief?.distanceFormatted == "6.20 km")
    }

    @Test("Prescribed drill title surfaces in headerTitle during active run but yields to completed and paused")
    func testPrescribedDrillTitleHeaderPrecedence() {
        let display = makeDisplayState(state: .tracking)

        // Active run with prescribed title -> surfaces prescribed title
        let activeSnapshot = WatchLiveRunSnapshot.from(
            displayState: display,
            location: .outdoor,
            runIntent: .adaptiveBase,
            prescribedDrillTitle: "Tempo Surges",
            isPaused: false,
            isCompleted: false,
            updatedAtEpochSeconds: 10.0
        )
        #expect(activeSnapshot.headerTitle == "Tempo Surges")

        // Paused run -> surfaces Apple Watch Paused
        let pausedSnapshot = WatchLiveRunSnapshot.from(
            displayState: display,
            location: .outdoor,
            runIntent: .adaptiveBase,
            prescribedDrillTitle: "Tempo Surges",
            isPaused: true,
            isCompleted: false,
            updatedAtEpochSeconds: 11.0
        )
        #expect(pausedSnapshot.headerTitle == "Apple Watch Paused")

        // Completed run -> surfaces Coach's Takeaway
        let completedSnapshot = WatchLiveRunSnapshot.from(
            displayState: display,
            location: .outdoor,
            runIntent: .adaptiveBase,
            prescribedDrillTitle: "Tempo Surges",
            isPaused: false,
            isCompleted: true,
            completedDebrief: sampleDebrief,
            updatedAtEpochSeconds: 12.0
        )
        #expect(completedSnapshot.headerTitle == "Coach's Takeaway")
    }

    @Test("PacingDisplayState makeLiveSnapshot extension matches static factory output")
    func testMakeLiveSnapshotExtensionParity() {
        let display = makeDisplayState(state: .tracking)
        let fromFactory = WatchLiveRunSnapshot.from(
            displayState: display,
            location: .indoor,
            runIntent: .recovery,
            prescribedDrillTitle: "Shakeout",
            isPaused: false,
            isCompleted: false,
            completedDebrief: nil,
            updatedAtEpochSeconds: 777.0
        )
        let fromExtension = display.makeLiveSnapshot(
            location: .indoor,
            runIntent: .recovery,
            prescribedDrillTitle: "Shakeout",
            isPaused: false,
            isCompleted: false,
            completedDebrief: nil,
            updatedAtEpochSeconds: 777.0
        )

        #expect(fromFactory == fromExtension)
    }

    // MARK: - 3. WatchLiveRunSnapshot Codable Round-Trip & Subtitle Tests

    @Test("WatchLiveRunSnapshot Codable round-trip preserves all properties")
    func testSnapshotCodableRoundTrip() throws {
        let display = makeDisplayState(state: .tracking, calibrationProgress: nil)
        let original = WatchLiveRunSnapshot.from(
            displayState: display,
            location: .outdoor,
            runIntent: .adaptiveBase,
            prescribedDrillTitle: "Cadence Pyramids",
            isPaused: false,
            isCompleted: true,
            completedDebrief: sampleDebrief,
            updatedAtEpochSeconds: 1731420000.0
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(WatchLiveRunSnapshot.self, from: data)

        #expect(decoded == original)
        #expect(decoded.schemaVersion == WatchLiveRunSnapshot.currentSchemaVersion)
        #expect(decoded.isSupportedSchema)
        #expect(decoded.phase == .completed)
        #expect(decoded.location == .outdoor)
        #expect(decoded.runIntent == .adaptiveBase)
        #expect(decoded.prescribedDrillTitle == "Cadence Pyramids")
        #expect(decoded.headerTitle == "Coach's Takeaway")
        #expect(decoded.intentAndLocationSubtitle == "Adaptive Base • Outdoor")
        #expect(decoded.completedDebrief?.formInsightBullet == sampleDebrief.formInsightBullet)
        #expect(decoded.updatedAtEpochSeconds == 1731420000.0)
    }

    @Test("WatchLiveRunSnapshot.idle produces correct non-active defaults")
    func testIdleSnapshotFactoryDefaults() {
        let idle = WatchLiveRunSnapshot.idle(location: .indoor, runIntent: .recovery, updatedAtEpochSeconds: 50.0)

        #expect(idle.phase == .idle)
        #expect(idle.isActiveWorkout == false)
        #expect(idle.stateTitle == "Ready")
        #expect(idle.elapsedTimeFormatted == "0:00")
        #expect(idle.filteredPaceFormatted == "--")
        #expect(idle.targetPaceFormatted == "--")
        #expect(idle.filteredHeartRateFormatted == "--")
        #expect(idle.filteredCadenceFormatted == "--")
        #expect(idle.calibrationProgress == nil)
        #expect(idle.completedDebrief == nil)
        #expect(idle.headerTitle == "Recovery")
        #expect(idle.intentAndLocationSubtitle == "Recovery • Indoor")
        #expect(idle.updatedAtEpochSeconds == 50.0)
    }

    @Test("intentAndLocationSubtitle formats intent and environment across all variations")
    func testIntentAndLocationSubtitleFormatting() {
        let cases: [(WatchRunIntent, PacingLocation, String)] = [
            (.adaptiveBase, .outdoor, "Adaptive Base • Outdoor"),
            (.adaptiveBase, .indoor, "Adaptive Base • Indoor"),
            (.pushPerformance, .outdoor, "Push / Performance • Outdoor"),
            (.pushPerformance, .indoor, "Push / Performance • Indoor"),
            (.recovery, .outdoor, "Recovery • Outdoor"),
            (.recovery, .indoor, "Recovery • Indoor")
        ]

        for (intent, location, expected) in cases {
            let snapshot = WatchLiveRunSnapshot.idle(location: location, runIntent: intent)
            #expect(snapshot.intentAndLocationSubtitle == expected)
            #expect(location.title == (location == .outdoor ? "Outdoor" : "Indoor"))
        }
    }

    // MARK: - 4. WatchRemoteCommand Enum Tests

    @Test("WatchRemoteCommand enum raw values match cross-platform wire contracts")
    func testWatchRemoteCommandRawValues() {
        #expect(WatchRemoteCommand.pauseWorkout.rawValue == "pauseWorkout")
        #expect(WatchRemoteCommand.resumeWorkout.rawValue == "resumeWorkout")
        #expect(WatchRemoteCommand.endWorkout.rawValue == "endWorkout")
        #expect(WatchRemoteCommand.toggleVoiceCues.rawValue == "toggleVoiceCues")
        #expect(WatchRemoteCommand.requestContextSync.rawValue == "requestContextSync")
        #expect(WatchRemoteCommand.allCases.count == 5)
    }

    @Test("WatchRemoteCommand enum titles provide clean human-readable action descriptions")
    func testWatchRemoteCommandTitles() {
        #expect(WatchRemoteCommand.pauseWorkout.title == "Pause Workout")
        #expect(WatchRemoteCommand.resumeWorkout.title == "Resume Workout")
        #expect(WatchRemoteCommand.endWorkout.title == "End Workout")
        #expect(WatchRemoteCommand.toggleVoiceCues.title == "Toggle Voice Cues")
        #expect(WatchRemoteCommand.requestContextSync.title == "Request Context Sync")
    }

    @Test("WatchRemoteCommand Codable round-trip preserves all cases")
    func testWatchRemoteCommandCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for command in WatchRemoteCommand.allCases {
            let data = try encoder.encode(command)
            let decoded = try decoder.decode(WatchRemoteCommand.self, from: data)
            #expect(decoded == command)
        }
    }

    // MARK: - 5. WatchLiveRunSnapshot Freshness & Staleness

    @Test("WatchLiveRunSnapshot: isStale detects stale telemetry for active runs but never for paused or completed")
    func testWatchLiveRunSnapshotStaleness() {
        let activeSnapshot = WatchLiveRunSnapshot.from(
            displayState: makeDisplayState(state: .tracking),
            location: .outdoor,
            runIntent: .adaptiveBase,
            updatedAtEpochSeconds: 1000.0
        )
        #expect(activeSnapshot.phase == .running)
        #expect(activeSnapshot.isPaused == false)
        #expect(activeSnapshot.isStale(at: 1040.0) == false)
        #expect(activeSnapshot.isStale(at: 1045.0) == false)
        #expect(activeSnapshot.isStale(at: 1046.0) == true)
        #expect(activeSnapshot.isStale(at: 1015.0, maxAgeSeconds: 10.0) == true)

        let pausedSnapshot = WatchLiveRunSnapshot.from(
            displayState: makeDisplayState(state: .tracking),
            location: .outdoor,
            runIntent: .adaptiveBase,
            isPaused: true,
            updatedAtEpochSeconds: 1000.0
        )
        #expect(pausedSnapshot.phase == .paused)
        #expect(pausedSnapshot.isPaused == true)
        #expect(pausedSnapshot.isStale(at: 2000.0) == false)

        let completedSnapshot = WatchLiveRunSnapshot.from(
            displayState: makeDisplayState(state: .tracking),
            location: .outdoor,
            runIntent: .adaptiveBase,
            isCompleted: true,
            updatedAtEpochSeconds: 1000.0
        )
        #expect(completedSnapshot.phase == .completed)
        #expect(completedSnapshot.isPaused == false)
        #expect(completedSnapshot.isStale(at: 2000.0) == false)
    }
}
