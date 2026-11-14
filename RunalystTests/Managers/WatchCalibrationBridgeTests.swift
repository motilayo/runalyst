import AVFoundation
import RunalystCore
@testable import Runalyst
import WatchConnectivity
import XCTest

@MainActor
final class WatchCalibrationBridgeTests: XCTestCase {

    func testPreservePrescribedDrillIntentAcrossLaunchWatchWorkout() async {
        let bridge = WatchCalibrationBridge.shared

        let dto = DrillPrescriptionDTO(
            title: "Cadence Pyramids",
            preRunDrillId: "cadencePyramids",
            purpose: "Form reset",
            targetCadence: "165-170",
            previousCadence: 160,
            durationMinutes: 10,
            isIndoor: false
        )

        bridge.publishDrillIntent(dto: dto)

        guard let initialContext = bridge.lastPublishedContext else {
            XCTFail("Expected lastPublishedContext to be non-nil after publishDrillIntent")
            return
        }

        XCTAssertEqual(initialContext.intent.prescribedDrillTitle, "Cadence Pyramids")
        XCTAssertEqual(initialContext.intent.prescribedDrillId, "cadencePyramids")
        XCTAssertEqual(initialContext.intent.intent, .intervals)
        XCTAssertEqual(initialContext.intent.prescribedDurationMinutes, 10)

        // Launch companion workout with indoor override
        await bridge.launchWatchWorkout(isIndoor: true)

        guard let preservedContext = bridge.lastPublishedContext else {
            XCTFail("Expected lastPublishedContext to be preserved after launchWatchWorkout")
            return
        }

        XCTAssertEqual(preservedContext.intent.prescribedDrillTitle, "Cadence Pyramids")
        XCTAssertEqual(preservedContext.intent.prescribedDrillId, "cadencePyramids")
        XCTAssertEqual(preservedContext.intent.intent, .intervals)
        XCTAssertEqual(preservedContext.intent.prescribedDurationMinutes, 10)
        XCTAssertEqual(preservedContext.isIndoorPreferred, true)
    }

    func testPreserveLastPublishedContextOnRequestContextSync() async throws {
        let bridge = WatchCalibrationBridge.shared

        let dto = DrillPrescriptionDTO(
            title: "Tempo Surges",
            preRunDrillId: "tempoSurges",
            purpose: "Neuromuscular priming",
            targetCadence: "172-176",
            previousCadence: 168,
            durationMinutes: 15,
            isIndoor: true
        )

        bridge.publishDrillIntent(dto: dto)
        let publishedBefore = bridge.lastPublishedContext
        XCTAssertNotNil(publishedBefore)

        let message: [String: Any] = [
            "remoteCommand": WatchRemoteCommand.requestContextSync.rawValue
        ]

        let replyExpectation = expectation(description: "ReplyHandler called for requestContextSync")
        var capturedReply: [String: Any]?

        bridge.session(WCSession.default, didReceiveMessage: message) { reply in
            capturedReply = reply
            replyExpectation.fulfill()
        }

        await fulfillment(of: [replyExpectation], timeout: 2.0)

        XCTAssertEqual(capturedReply?["status"] as? String, "ok")
        guard let data = capturedReply?["pacingContext"] as? Data else {
            XCTFail("Expected pacingContext data in reply")
            return
        }

        let repliedContext = try JSONDecoder().decode(WatchPacingContext.self, from: data)
        XCTAssertEqual(repliedContext.intent.prescribedDrillTitle, "Tempo Surges")
        XCTAssertEqual(repliedContext.intent.intent, .intervals)
        XCTAssertEqual(bridge.lastPublishedContext?.intent.prescribedDrillTitle, "Tempo Surges")
    }

    func testRejectStaleLiveSnapshot() {
        let bridge = WatchCalibrationBridge.shared
        let now = Date().timeIntervalSince1970

        let staleSnapshot = WatchLiveRunSnapshot(
            schemaVersion: 1,
            phase: .running,
            location: .outdoor,
            runIntent: .adaptiveBase,
            prescribedDrillTitle: nil,
            stateTitle: "Running",
            biometricStatusLabel: "Nominal",
            biometricStatusToken: .vibrantGreen,
            filteredPaceFormatted: "5:00 /km",
            targetPaceFormatted: "5:00 /km",
            filteredHeartRateFormatted: "150 BPM",
            filteredCadenceFormatted: "170 SPM",
            elapsedTimeFormatted: "10:00",
            deviationTitle: "On Pace",
            paceGaugeNormalizedPosition: 0.5,
            targetBandLowerNormalized: 0.45,
            targetBandUpperNormalized: 0.55,
            calibrationProgress: nil,
            completedDebrief: nil,
            updatedAtEpochSeconds: now - 90.0
        )

        XCTAssertTrue(staleSnapshot.isStale(at: now))

        guard let staleData = try? JSONEncoder().encode(staleSnapshot) else {
            XCTFail("Failed to encode snapshot")
            return
        }

        bridge.handleReceivedLiveSnapshotData(staleData)

        if let current = bridge.latestWatchSnapshot {
            XCTAssertNotEqual(current.updatedAtEpochSeconds, staleSnapshot.updatedAtEpochSeconds)
        }
    }

    func testAcceptFreshLiveSnapshotAndStalenessClear() {
        let bridge = WatchCalibrationBridge.shared
        let now = Date().timeIntervalSince1970

        let freshSnapshot = WatchLiveRunSnapshot(
            schemaVersion: 1,
            phase: .running,
            location: .indoor,
            runIntent: .pushPerformance,
            prescribedDrillTitle: nil,
            stateTitle: "Running",
            biometricStatusLabel: "Nominal",
            biometricStatusToken: .vibrantGreen,
            filteredPaceFormatted: "5:10 /km",
            targetPaceFormatted: "5:15 /km",
            filteredHeartRateFormatted: "145 BPM",
            filteredCadenceFormatted: "172 SPM",
            elapsedTimeFormatted: "05:00",
            deviationTitle: "On Pace",
            paceGaugeNormalizedPosition: 0.5,
            targetBandLowerNormalized: 0.45,
            targetBandUpperNormalized: 0.55,
            calibrationProgress: nil,
            completedDebrief: nil,
            updatedAtEpochSeconds: now - 5.0
        )

        XCTAssertFalse(freshSnapshot.isStale(at: now))

        guard let freshData = try? JSONEncoder().encode(freshSnapshot) else {
            XCTFail("Failed to encode snapshot")
            return
        }

        bridge.handleReceivedLiveSnapshotData(freshData)
        XCTAssertEqual(bridge.latestWatchSnapshot?.updatedAtEpochSeconds, freshSnapshot.updatedAtEpochSeconds)

        let wasStaleEarly = bridge.refreshStalenessIfNeeded(now: Date(timeIntervalSince1970: now + 10.0))
        XCTAssertFalse(wasStaleEarly)
        XCTAssertNotNil(bridge.latestWatchSnapshot)

        let wasStaleLate = bridge.refreshStalenessIfNeeded(now: Date(timeIntervalSince1970: now + 60.0))
        XCTAssertTrue(wasStaleLate)
        XCTAssertNil(bridge.latestWatchSnapshot)
    }

    func testCompanionVoiceRelayCancelSafety() {
        let relay = CompanionVoiceRelay.shared
        let dummyUtterance = AVSpeechUtterance(string: "Test speech")

        relay.speechSynthesizer(AVSpeechSynthesizer(), didCancel: dummyUtterance)
        relay.speechSynthesizer(AVSpeechSynthesizer(), didFinish: dummyUtterance)
    }

    func testPublishContextFlattensRunBucketsAndPreservesSpecFloorAndDuration() {
        let bridge = WatchCalibrationBridge.shared
        defer {
            UserDefaults.standard.removeObject(forKey: "runnerAge")
            UserDefaults.standard.removeObject(forKey: "cachedRestingHRSamples")
        }
        UserDefaults.standard.set(30, forKey: "runnerAge")
        UserDefaults.standard.set([52.0, 54.0, 50.0], forKey: "cachedRestingHRSamples")

        let now = Date()
        let bucket1 = BucketData(
            startTime: now.addingTimeInterval(-1800),
            distanceMeters: 250.0,
            durationSeconds: 60.0,
            meanPaceSecPerKm: 240.0,
            meanCadence: 175.0,
            meanHR: 194.0
        )
        let bucket2 = BucketData(
            startTime: now.addingTimeInterval(-1740),
            distanceMeters: 250.0,
            durationSeconds: 60.0,
            meanPaceSecPerKm: 240.0,
            meanCadence: 174.0,
            meanHR: 196.0
        )
        let bucket3 = BucketData(
            startTime: now.addingTimeInterval(-1680),
            distanceMeters: 250.0,
            durationSeconds: 60.0,
            meanPaceSecPerKm: 240.0,
            meanCadence: 176.0,
            meanHR: 193.0
        )

        let run = RunRecord(
            id: UUID(),
            hkWorkoutID: UUID(),
            date: now.addingTimeInterval(-1800),
            totalDistanceMeters: 5000.0,
            duration: 1800.0,
            rawAvgPace: 360.0,
            rawAvgHeartRate: 155.0,
            rawAvgCadence: 168.0,
            workingAvgPace: 360.0,
            workingAvgCadence: 168.0,
            workingAvgHeartRate: 155.0,
            paceCV: 0.05,
            paceSlope: 0.0,
            percentZone4: 0.1,
            detectedTypeRaw: "Steady Effort",
            buckets: [bucket1, bucket2, bucket3]
        )

        let spec = PlannedSessionSpec(
            kind: "run",
            intent: .train,
            title: "Zone 2 Easy Aerobic Base",
            minutesLow: 30,
            minutesHigh: 45,
            paceBand: "5:30 - 6:00 /km",
            hrCap: "HR: < 152 BPM",
            cadenceFloor: 162
        )

        bridge.publishContext(
            runs: [run],
            spec: spec,
            now: now
        )

        guard let context = bridge.lastPublishedContext else {
            XCTFail("Expected non-nil lastPublishedContext")
            return
        }

        XCTAssertEqual(context.profile.maxHR, 196.0)
        XCTAssertFalse(context.profile.isFallback)
        XCTAssertEqual(context.intent.targetCadenceSPM, 162)
        XCTAssertEqual(context.intent.prescribedDurationMinutes, 45)
    }

    func testPublishContextCalibratesFromPersistedRunSignatureWithoutBuckets() {
        let bridge = WatchCalibrationBridge.shared
        defer {
            UserDefaults.standard.removeObject(forKey: "runnerAge")
            UserDefaults.standard.removeObject(forKey: "cachedRestingHRSamples")
        }
        UserDefaults.standard.set(30, forKey: "runnerAge")
        UserDefaults.standard.set([52.0, 54.0, 50.0], forKey: "cachedRestingHRSamples")

        let now = Date()
        let signature = RunSignature(
            classification: "Steady Effort",
            confidence: 0.95,
            probabilities: ["Steady Effort": 0.95],
            anomalies: [],
            cadenceFloor: 162.0,
            phaseSegments: [],
            dataSource: "wrist",
            isIndoor: false,
            needsInclineReview: false,
            splits: [],
            peakHeartRateBPM: 196.0
        )

        let run = RunRecord(
            id: UUID(),
            hkWorkoutID: UUID(),
            date: now.addingTimeInterval(-1800),
            totalDistanceMeters: 5000.0,
            duration: 1800.0,
            rawAvgPace: 360.0,
            rawAvgHeartRate: 155.0,
            rawAvgCadence: 168.0,
            workingAvgPace: 360.0,
            workingAvgCadence: 168.0,
            workingAvgHeartRate: 155.0,
            paceCV: 0.05,
            paceSlope: 0.0,
            percentZone4: 0.1,
            detectedTypeRaw: "Steady Effort",
            buckets: []
        )
        run.signature = signature

        let spec = PlannedSessionSpec(
            kind: "run",
            intent: .train,
            title: "Zone 2 Easy Aerobic Base",
            minutesLow: 30,
            minutesHigh: 45,
            paceBand: "5:30 - 6:00 /km",
            hrCap: "HR: < 152 BPM",
            cadenceFloor: 162
        )

        bridge.publishContext(
            runs: [run],
            spec: spec,
            now: now
        )

        guard let context = bridge.lastPublishedContext else {
            XCTFail("Expected non-nil lastPublishedContext")
            return
        }

        XCTAssertEqual(context.profile.maxHR, 196.0)
        XCTAssertFalse(context.profile.isFallback)
        XCTAssertEqual(context.intent.targetCadenceSPM, 162)
        XCTAssertEqual(context.intent.prescribedDurationMinutes, 45)
    }
}
