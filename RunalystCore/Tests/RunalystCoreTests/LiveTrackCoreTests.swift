import Foundation
@testable import RunalystCore
import Testing

@Suite("Live Track Core Stadium Kinematics & Pacer Tracking Tests")
struct LiveTrackCoreTests {

    private func makeDisplayState(
        state: PacingState = .tracking,
        targetPaceSecondsPerKm: Int = 300,
        filteredPaceSecondsPerKm: Int = 300,
        filteredHR: Int = 150,
        filteredCadence: Int = 180
    ) -> PacingDisplayState {
        PacingDisplayState(
            state: state,
            targetPaceSecondsPerKm: targetPaceSecondsPerKm,
            filteredPaceSecondsPerKm: filteredPaceSecondsPerKm,
            filteredHeartRateBPM: filteredHR,
            deviation: .onTarget,
            refractorySecondsRemaining: 0,
            lastReason: nil,
            adjustmentsEnabled: true,
            targetPaceFormatted: "5:00 /km",
            filteredPaceFormatted: "5:00 /km",
            filteredHeartRateFormatted: "\(filteredHR) BPM",
            deviationTitle: "On Target",
            calibrationProgress: nil,
            calibrationProgressFormatted: "--",
            refractoryProgress: 0.0,
            filteredCadenceSPM: filteredCadence,
            filteredCadenceFormatted: "\(filteredCadence) SPM",
            targetCadenceSPM: 180,
            targetCadenceFormatted: "180 SPM",
            isCalibrating: false,
            elapsedTimeFormatted: "10:00",
            paceGaugeNormalizedPosition: 0.50,
            targetBandLowerNormalized: 0.44,
            targetBandUpperNormalized: 0.56,
            biometricStatusToken: .vibrantGreen,
            biometricStatusLabel: "Cadence & HR Nominal"
        )
    }

    // MARK: - 1. 400m Lap Rollover & Distance Guard Tests

    @Test("400m lap rollover correctly evaluates lap index, distance, and progress with zero/negative guards")
    func testLapRolloverAndGuards() {
        let lap1040 = LiveTrackCalculator.lapKinematics(totalDistanceMeters: 1040.0)
        #expect(lap1040.lapNumber == 3)
        #expect(lap1040.lapDistanceMeters == 240)
        #expect(abs(lap1040.lapProgress - 0.60) < 0.0001)

        let lapZero = LiveTrackCalculator.lapKinematics(totalDistanceMeters: 0.0)
        #expect(lapZero.lapNumber == 1)
        #expect(lapZero.lapDistanceMeters == 0)
        #expect(lapZero.lapProgress == 0.0)

        let lapNegative = LiveTrackCalculator.lapKinematics(totalDistanceMeters: -45.5)
        #expect(lapNegative.lapNumber == 1)
        #expect(lapNegative.lapDistanceMeters == 0)
        #expect(lapNegative.lapProgress == 0.0)

        let lap399 = LiveTrackCalculator.lapKinematics(totalDistanceMeters: 399.9)
        #expect(lap399.lapNumber == 1)
        #expect(lap399.lapDistanceMeters == 399)
        #expect(lap399.lapProgress > 0.99)

        let lap400 = LiveTrackCalculator.lapKinematics(totalDistanceMeters: 400.0)
        #expect(lap400.lapNumber == 2)
        #expect(lap400.lapDistanceMeters == 0)
        #expect(lap400.lapProgress == 0.0)

        let lap800 = LiveTrackCalculator.lapKinematics(totalDistanceMeters: 800.0)
        #expect(lap800.lapNumber == 3)
        #expect(lap800.lapDistanceMeters == 0)
        #expect(lap800.lapProgress == 0.0)
    }

    // MARK: - 2. Ghost Target Kinematics & Suppression Tests

    @Test("Ghost kinematics calculates on-target pacing, lead, and lag deltas accurately")
    func testGhostKinematics() throws {
        let onPacer = LiveTrackCalculator.ghostKinematics(
            totalDistanceMeters: 1040.0,
            elapsedSeconds: 312,
            targetPaceSecondsPerKm: 300,
            isCalibrating: false
        )
        #expect(onPacer.ghostDeltaMeters == 0)
        #expect(onPacer.ghostDeltaLabel == "On Pacer")
        let progress = try #require(onPacer.ghostProgress)
        #expect(abs(progress - 0.60) < 0.0001)

        let lead = LiveTrackCalculator.ghostKinematics(
            totalDistanceMeters: 1065.0,
            elapsedSeconds: 312,
            targetPaceSecondsPerKm: 300,
            isCalibrating: false
        )
        #expect(lead.ghostDeltaMeters == 25)
        #expect(lead.ghostDeltaLabel == "+25m ahead")

        let lag = LiveTrackCalculator.ghostKinematics(
            totalDistanceMeters: 1015.0,
            elapsedSeconds: 312,
            targetPaceSecondsPerKm: 300,
            isCalibrating: false
        )
        #expect(lag.ghostDeltaMeters == -25)
        #expect(lag.ghostDeltaLabel == "-25m behind")
    }

    @Test("Ghost kinematics suppresses progress and delta during calibration or when target pace is nil/non-positive")
    func testGhostKinematicsSuppression() {
        let calibrating = LiveTrackCalculator.ghostKinematics(
            totalDistanceMeters: 500.0,
            elapsedSeconds: 150,
            targetPaceSecondsPerKm: 300,
            isCalibrating: true
        )
        #expect(calibrating.ghostProgress == nil)
        #expect(calibrating.ghostDeltaMeters == nil)
        #expect(calibrating.ghostDeltaLabel == "Calibrating")

        let noTarget = LiveTrackCalculator.ghostKinematics(
            totalDistanceMeters: 500.0,
            elapsedSeconds: 150,
            targetPaceSecondsPerKm: nil,
            isCalibrating: false
        )
        #expect(noTarget.ghostProgress == nil)
        #expect(noTarget.ghostDeltaMeters == nil)
        #expect(noTarget.ghostDeltaLabel == "--")

        let invalidTarget = LiveTrackCalculator.ghostKinematics(
            totalDistanceMeters: 500.0,
            elapsedSeconds: 150,
            targetPaceSecondsPerKm: 0,
            isCalibrating: false
        )
        #expect(invalidTarget.ghostProgress == nil)
        #expect(invalidTarget.ghostDeltaMeters == nil)
        #expect(invalidTarget.ghostDeltaLabel == "--")
    }

    // MARK: - 3. Metric vs Imperial Formatting Parity Tests

    @Test("Metric vs Imperial formatting parity across LiveTrackSnapshot and WatchLiveRunSnapshot")
    func testMetricVsImperialFormattingParity() {
        let mileMeters = 1609.344

        let metricDist = LiveTrackCalculator.formatTotalDistance(meters: mileMeters, useMetricSystem: true)
        let imperialDist = LiveTrackCalculator.formatTotalDistance(meters: mileMeters, useMetricSystem: false)
        #expect(metricDist == "1.61 km")
        #expect(imperialDist == "1.00 mi")

        let metricSnapshot = LiveTrackCalculator.calculateSnapshot(
            totalDistanceMeters: mileMeters,
            elapsedSeconds: 480,
            lapElapsedSeconds: 60,
            cadenceSPM: 180,
            targetPaceSecondsPerKm: 300,
            isCalibrating: false,
            isPaused: false,
            statusToken: .vibrantGreen,
            useMetricSystem: true
        )
        #expect(metricSnapshot.totalDistanceFormatted == "1.61 km")
        #expect(metricSnapshot.lapHeaderLabel == "Lap 5 • 9/400m")
        #expect(metricSnapshot.lapElapsedFormatted == "1:00")

        let imperialSnapshot = LiveTrackCalculator.calculateSnapshot(
            totalDistanceMeters: mileMeters,
            elapsedSeconds: 480,
            lapElapsedSeconds: 60,
            cadenceSPM: 180,
            targetPaceSecondsPerKm: 300,
            isCalibrating: false,
            isPaused: false,
            statusToken: .vibrantGreen,
            useMetricSystem: false
        )
        #expect(imperialSnapshot.totalDistanceFormatted == "1.00 mi")
        #expect(imperialSnapshot.lapHeaderLabel == "Lap 5 • 9/400m")

        let displayState = makeDisplayState()
        let watchMetric = WatchLiveRunSnapshot.from(
            displayState: displayState,
            location: .outdoor,
            runIntent: .adaptiveBase,
            useMetricSystem: true,
            trackSnapshot: metricSnapshot,
            updatedAtEpochSeconds: 1000.0
        )
        #expect(watchMetric.trackSnapshot?.totalDistanceFormatted == "1.61 km")

        let watchImperial = WatchLiveRunSnapshot.from(
            displayState: displayState,
            location: .outdoor,
            runIntent: .adaptiveBase,
            useMetricSystem: false,
            trackSnapshot: imperialSnapshot,
            updatedAtEpochSeconds: 1000.0
        )
        #expect(watchImperial.trackSnapshot?.totalDistanceFormatted == "1.00 mi")
    }

    // MARK: - 4. Stride Frequency Animation Tests

    @Test("strideFrequencyHz clamps to [1.5, 4.0] and returns 0.0 when paused or idle")
    func testStrideFrequencyClampingAndPausing() {
        #expect(LiveTrackCalculator.strideFrequencyHz(cadenceSPM: 180, isPaused: true) == 0.0)

        #expect(LiveTrackCalculator.strideFrequencyHz(cadenceSPM: nil, isPaused: false) == 0.0)
        #expect(LiveTrackCalculator.strideFrequencyHz(cadenceSPM: 0, isPaused: false) == 0.0)
        #expect(LiveTrackCalculator.strideFrequencyHz(cadenceSPM: -20, isPaused: false) == 0.0)

        #expect(LiveTrackCalculator.strideFrequencyHz(cadenceSPM: 60, isPaused: false) == 1.5)
        #expect(LiveTrackCalculator.strideFrequencyHz(cadenceSPM: 90, isPaused: false) == 1.5)

        #expect(LiveTrackCalculator.strideFrequencyHz(cadenceSPM: 120, isPaused: false) == 2.0)
        #expect(LiveTrackCalculator.strideFrequencyHz(cadenceSPM: 180, isPaused: false) == 3.0)
        #expect(abs(LiveTrackCalculator.strideFrequencyHz(cadenceSPM: 168, isPaused: false) - 2.8) < 0.0001)

        #expect(LiveTrackCalculator.strideFrequencyHz(cadenceSPM: 240, isPaused: false) == 4.0)
        #expect(LiveTrackCalculator.strideFrequencyHz(cadenceSPM: 300, isPaused: false) == 4.0)
    }

    // MARK: - 5. Track Oval Geometry & Symmetry Tests

    @Test("trackOvalPoint maintains stadium geometry, clockwise traversal, and apex symmetry")
    func testTrackOvalGeometryAndSymmetry() {
        let p0 = LiveTrackCore.trackOvalPoint(progress: 0.0)
        #expect(abs(p0.x - 0.50) < 0.001)
        #expect(abs(p0.y - 0.08) < 0.001)

        let pRightApex = LiveTrackCore.trackOvalPoint(progress: 0.25)
        #expect(abs(pRightApex.x - 0.92) < 0.001)
        #expect(abs(pRightApex.y - 0.50) < 0.001)

        let p200m = LiveTrackCore.trackOvalPoint(progress: 0.50)
        #expect(abs(p200m.x - 0.50) < 0.001)
        #expect(abs(p200m.y - 0.92) < 0.001)

        let pLeftApex = LiveTrackCore.trackOvalPoint(progress: 0.75)
        #expect(abs(pLeftApex.x - 0.08) < 0.001)
        #expect(abs(pLeftApex.y - 0.50) < 0.001)

        let p1 = LiveTrackCore.trackOvalPoint(progress: 1.0)
        #expect(abs(p1.x - p0.x) < 0.001)
        #expect(abs(p1.y - p0.y) < 0.001)

        let pNegHalf = LiveTrackCore.trackOvalPoint(progress: -0.50)
        #expect(abs(pNegHalf.x - p200m.x) < 0.001)
        #expect(abs(pNegHalf.y - p200m.y) < 0.001)

        let pExtraLap = LiveTrackCore.trackOvalPoint(progress: 1.25)
        #expect(abs(pExtraLap.x - pRightApex.x) < 0.001)
        #expect(abs(pExtraLap.y - pRightApex.y) < 0.001)
    }

    // MARK: - 6. Biometric Palette RGB Distinctness Tests

    @Test("paletteRGB produces distinct colors across all PacingAccentToken cases")
    func testPaletteRGBDistinctness() {
        let allTokens = PacingAccentToken.allCases
        #expect(allTokens.count == 9)

        let calibrating = LiveTrackCore.paletteRGB(for: .calibratingBlue)
        let electric = LiveTrackCore.paletteRGB(for: .electricBlue)
        #expect(calibrating != electric)

        let recoverAmber = LiveTrackCore.paletteRGB(for: .recoverAmber)
        let recoverOrange = LiveTrackCore.paletteRGB(for: .recoverOrange)
        #expect(recoverAmber != recoverOrange)

        for i in 0..<allTokens.count {
            for j in (i + 1)..<allTokens.count {
                let tokenA = allTokens[i]
                let tokenB = allTokens[j]
                let rgbA = LiveTrackCore.paletteRGB(for: tokenA)
                let rgbB = LiveTrackCore.paletteRGB(for: tokenB)
                #expect(rgbA != rgbB, "Tokens \(tokenA) and \(tokenB) must have distinct RGB palettes")
            }
        }

        for token in allTokens {
            let rgb = LiveTrackCore.paletteRGB(for: token)
            #expect(rgb.red >= 0.0 && rgb.red <= 1.0)
            #expect(rgb.green >= 0.0 && rgb.green <= 1.0)
            #expect(rgb.blue >= 0.0 && rgb.blue <= 1.0)
        }
    }

    // MARK: - 7. LiveTrackAccumulator Rolling Window & Lap Split Tests

    @Test("LiveTrackAccumulator prunes 480s window and downsamples <= 24 points over 600 samples")
    func testAccumulatorPruningAndDownsampling() {
        var accumulator = LiveTrackAccumulator()

        accumulator.recordSample(
            elapsedSeconds: 0, distanceMeters: 0.0,
            paceSecondsPerKm: 300, heartRateBPM: 140, cadenceSPM: 170
        )
        #expect(accumulator.rawSamples.count == 1)

        for t in 1...500 {
            let dist = Double(t) * 3.33
            accumulator.recordSample(
                elapsedSeconds: t,
                distanceMeters: dist,
                paceSecondsPerKm: 300 + (t % 10),
                heartRateBPM: 140 + (t % 20),
                cadenceSPM: 175,
                targetPaceSecondsPerKm: 300
            )
        }

        let oldestElapsed = accumulator.rawSamples.first?.elapsedSeconds ?? 0
        #expect(oldestElapsed >= 20)
        #expect(accumulator.rawSamples.count > 24)

        let summary = accumulator.makeTrajectorySummary(targetPaceSecondsPerKm: 300)
        #expect(summary.points.count <= 24)
        #expect(summary.points.count == 24)
        #expect(summary.windowLabel == "Last 8 min")

        #expect(summary.corridorLowerY >= 0.0 && summary.corridorLowerY <= 0.50)
        #expect(summary.corridorUpperY >= 0.50 && summary.corridorUpperY <= 1.0)

        for pt in summary.points {
            #expect(pt.paceNormalizedY >= 0.0 && pt.paceNormalizedY <= 1.0)
            if let hrY = pt.hrNormalizedY {
                #expect(hrY >= 0.0 && hrY <= 1.0)
            }
        }
    }

    @Test("LiveTrackAccumulator retains latest <= 4 track lap splits across 6 completed laps")
    func testAccumulatorLapSplitRetention() {
        var accumulator = LiveTrackAccumulator()

        accumulator.recordSample(
            elapsedSeconds: 120, distanceMeters: 405.0,
            paceSecondsPerKm: 300, heartRateBPM: 145, cadenceSPM: 172,
            targetPaceSecondsPerKm: 300
        )
        #expect(accumulator.completedLapSplits.count == 1)
        #expect(accumulator.completedLapSplits[0].lapNumber == 1)

        accumulator.recordSample(
            elapsedSeconds: 240, distanceMeters: 810.0,
            paceSecondsPerKm: 300, heartRateBPM: 150, cadenceSPM: 174,
            targetPaceSecondsPerKm: 300
        )
        #expect(accumulator.completedLapSplits.count == 2)
        #expect(accumulator.completedLapSplits[1].lapNumber == 2)

        accumulator.recordSample(
            elapsedSeconds: 360, distanceMeters: 1215.0,
            paceSecondsPerKm: 300, heartRateBPM: 155, cadenceSPM: 174,
            targetPaceSecondsPerKm: 300
        )
        #expect(accumulator.completedLapSplits.count == 3)

        accumulator.recordSample(
            elapsedSeconds: 480, distanceMeters: 1620.0,
            paceSecondsPerKm: 300, heartRateBPM: 158, cadenceSPM: 176,
            targetPaceSecondsPerKm: 300
        )
        #expect(accumulator.completedLapSplits.count == 4)

        accumulator.recordSample(
            elapsedSeconds: 600, distanceMeters: 2025.0,
            paceSecondsPerKm: 300, heartRateBPM: 160, cadenceSPM: 178,
            targetPaceSecondsPerKm: 300
        )
        #expect(accumulator.completedLapSplits.count == 4)
        #expect(accumulator.completedLapSplits.map(\.lapNumber) == [2, 3, 4, 5])

        accumulator.recordSample(
            elapsedSeconds: 720, distanceMeters: 2430.0,
            paceSecondsPerKm: 300, heartRateBPM: 162, cadenceSPM: 180,
            targetPaceSecondsPerKm: 300
        )
        #expect(accumulator.completedLapSplits.count == 4)
        #expect(accumulator.completedLapSplits.map(\.lapNumber) == [3, 4, 5, 6])
    }

    // MARK: - 8. Backward-Compatible JSON Decoding & Display Mode Tests

    @Test("WatchLiveRunSnapshot decodes legacy V1 JSON payloads omitting trackSnapshot and trajectorySummary as nil")
    func testLegacySnapshotPayloadDecoding() throws {
        let legacyV1JSON = """
        {
            "schemaVersion": 1,
            "phase": "running",
            "location": "outdoor",
            "runIntent": "adaptiveBase",
            "stateTitle": "Adaptive Pacing",
            "biometricStatusLabel": "Biometrics Nominal",
            "biometricStatusToken": "vibrantGreen",
            "filteredPaceFormatted": "5:12 /km",
            "targetPaceFormatted": "5:15 /km",
            "filteredHeartRateFormatted": "148 BPM",
            "filteredCadenceFormatted": "172 SPM",
            "elapsedTimeFormatted": "14:28",
            "deviationTitle": "On Target",
            "paceGaugeNormalizedPosition": 0.52,
            "targetBandLowerNormalized": 0.44,
            "targetBandUpperNormalized": 0.56,
            "updatedAtEpochSeconds": 1700000000.0
        }
        """

        let data = try #require(legacyV1JSON.data(using: .utf8))
        let decoded = try JSONDecoder().decode(WatchLiveRunSnapshot.self, from: data)

        #expect(decoded.schemaVersion == 1)
        #expect(decoded.phase == .running)
        #expect(decoded.stateTitle == "Adaptive Pacing")
        #expect(decoded.trackSnapshot == nil)
        #expect(decoded.trajectorySummary == nil)
    }

    @Test("WatchLiveRunSnapshot with trackSnapshot and trajectorySummary round-trips Codable with full fidelity")
    func testFullSnapshotCodableRoundTrip() throws {
        let trackSnapshot = LiveTrackCalculator.calculateSnapshot(
            totalDistanceMeters: 1040.0,
            elapsedSeconds: 312,
            lapElapsedSeconds: 72,
            cadenceSPM: 174,
            targetPaceSecondsPerKm: 300,
            isCalibrating: false,
            isPaused: false,
            statusToken: .vibrantGreen,
            useMetricSystem: true
        )
        let trajectorySummary = LiveTrajectorySummary(
            points: [
                LiveTrajectoryPoint(elapsedSeconds: 60, paceNormalizedY: 0.52, hrNormalizedY: 0.48),
                LiveTrajectoryPoint(elapsedSeconds: 120, paceNormalizedY: 0.50, hrNormalizedY: 0.50)
            ],
            corridorLowerY: 0.42,
            corridorUpperY: 0.58,
            recentLapSplits: [
                TrackLapSplit(lapNumber: 1, splitSeconds: 120, splitFormatted: "2:00", onTarget: true),
                TrackLapSplit(lapNumber: 2, splitSeconds: 120, splitFormatted: "2:00", onTarget: true)
            ]
        )

        let original = WatchLiveRunSnapshot.from(
            displayState: makeDisplayState(),
            location: .outdoor,
            runIntent: .adaptiveBase,
            trackSnapshot: trackSnapshot,
            trajectorySummary: trajectorySummary,
            updatedAtEpochSeconds: 1700000500.0
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(WatchLiveRunSnapshot.self, from: data)

        #expect(decoded == original)
        #expect(decoded.trackSnapshot?.lapNumber == 3)
        #expect(decoded.trackSnapshot?.lapDistanceMeters == 240)
        #expect(decoded.trajectorySummary?.points.count == 2)
        #expect(decoded.trajectorySummary?.recentLapSplits.count == 2)
    }

    @Test("LiveActivityDisplayMode cycles track -> metrics -> chart -> track with correct titles")
    func testLiveActivityDisplayModeCycle() {
        #expect(LiveActivityDisplayMode.allCases.count == 3)
        #expect(LiveActivityDisplayMode.track.nextMode == .metrics)
        #expect(LiveActivityDisplayMode.metrics.nextMode == .chart)
        #expect(LiveActivityDisplayMode.chart.nextMode == .track)

        #expect(LiveActivityDisplayMode.track.title == "Track")
        #expect(LiveActivityDisplayMode.metrics.title == "Metrics")
        #expect(LiveActivityDisplayMode.chart.title == "Chart")
    }
}
