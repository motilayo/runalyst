import Foundation
import Testing
@testable import RunalystCore

@Suite("TreadmillKinematicsCore Crucible Tests")
struct TreadmillKinematicsCoreTests {

    @Test("Median pace filtering clamps extreme 25% outliers")
    func medianPaceFilteringClampsOutliers() {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let rawPaces = [300.0, 302.0, 298.0, 600.0, 301.0, 299.0] // 600.0 is an extreme sensor artifact

        var buckets: [TelemetryBucket] = []
        for (i, p) in rawPaces.enumerated() {
            buckets.append(TelemetryBucket(
                timestamp: baseDate.addingTimeInterval(Double(i) * 30.0),
                durationSeconds: 30.0,
                distanceMeters: (30.0 / p) * 1000.0,
                paceSecondsPerKm: p,
                cadenceSPM: 165.0,
                heartRateBPM: 150.0
            ))
        }

        let smoothed = TreadmillKinematicsCore.applyWristPaceSmoothing(buckets: buckets)

        #expect(smoothed.count == rawPaces.count)

        // The 600.0 spike must be clamped to within 25% of the overall median (~300.5 * 1.25 = ~375.6)
        let clampedSpike = smoothed[3].paceSecondsPerKm
        #expect(clampedSpike <= 300.5 * 1.25 + 1.0)
        #expect(clampedSpike >= 300.5 * 0.75 - 1.0)
    }

    @Test("Calibration mutation is detected and bucket distances are reconciled")
    func calibrationMutationDetectionAndReconciliation() {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

        // 10 buckets of 30s = 300s total, distance = 10 * 80m = 800m
        var buckets: [TelemetryBucket] = []
        for i in 0..<10 {
            buckets.append(TelemetryBucket(
                timestamp: baseDate.addingTimeInterval(Double(i) * 30.0),
                durationSeconds: 30.0,
                distanceMeters: 80.0,
                paceSecondsPerKm: 375.0,
                cadenceSPM: 160.0,
                heartRateBPM: 145.0
            ))
        }

        // Runner calibrated workout on Watch to 1,000 meters (mutation delta = 200m > 5m)
        let authenticDistance = 1000.0
        let (isMutated, delta, _) = TreadmillKinematicsCore.detectCalibrationMutation(
            reportedDistanceMeters: 800.0,
            authenticDistanceMeters: authenticDistance,
            reportedDurationSeconds: 300.0,
            authenticDurationSeconds: 300.0
        )

        #expect(isMutated == true)
        #expect(abs(delta - 200.0) < 0.001)

        let reconciled = TreadmillKinematicsCore.reconcileBucketDistances(
            buckets: buckets,
            authenticTotalDistanceMeters: authenticDistance
        )

        let reconciledTotalDist = reconciled.map(\.distanceMeters).reduce(0.0, +)
        #expect(abs(reconciledTotalDist - 1000.0) < 0.001)

        // Each bucket scaled from 80m to 100m, so pace updated from 375.0 to 300.0 s/km
        for b in reconciled {
            #expect(abs(b.distanceMeters - 100.0) < 0.001)
            #expect(abs(b.paceSecondsPerKm - 300.0) < 0.001)
        }
    }

    @Test("Incline review triggers deterministically on heart rate strain decoupling")
    func inclineReviewFlaggingOnDecoupling() {
        // Indoor uncalibrated run with flat pace (CV = 0.02 < 0.045), high HR strain (CV = 0.12 > 0.075),
        // and cadence decay (-0.01 < -0.005)
        let shouldFlagIndoor = TreadmillKinematicsCore.shouldFlagForInclineReview(
            isIndoor: true,
            isGymKit: false,
            hrCV: 0.12,
            paceCV: 0.02,
            cadenceSlope: -0.01
        )
        #expect(shouldFlagIndoor == true)

        // Outdoor runs must never flag for treadmill incline review
        let shouldFlagOutdoor = TreadmillKinematicsCore.shouldFlagForInclineReview(
            isIndoor: false,
            isGymKit: false,
            hrCV: 0.12,
            paceCV: 0.02,
            cadenceSlope: -0.01
        )
        #expect(shouldFlagOutdoor == false)

        // GymKit runs have hardware incline telemetry, so no heuristic review is needed
        let shouldFlagGymKit = TreadmillKinematicsCore.shouldFlagForInclineReview(
            isIndoor: true,
            isGymKit: true,
            hrCV: 0.12,
            paceCV: 0.02,
            cadenceSlope: -0.01
        )
        #expect(shouldFlagGymKit == false)
    }

    @Test("ProcessIndoorRun integrates filtering, reconciliation, and effective metrics")
    func processIndoorRunIntegration() {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        var buckets: [TelemetryBucket] = []

        for i in 0..<10 {
            buckets.append(TelemetryBucket(
                timestamp: baseDate.addingTimeInterval(Double(i) * 30.0),
                durationSeconds: 30.0,
                distanceMeters: 80.0,
                paceSecondsPerKm: 375.0,
                cadenceSPM: 160.0,
                heartRateBPM: 145.0
            ))
        }

        let result = TreadmillKinematicsCore.processIndoorRun(
            buckets: buckets,
            isIndoor: true,
            isGymKit: false,
            authenticTotalDistanceMeters: 1000.0,
            authenticDurationSeconds: 300.0,
            rawPaceCV: 0.02,
            rawPaceSlope: -0.05,
            hrCV: 0.09,
            cadenceSlope: -0.008
        )

        #expect(result.isCalibrationMutated == true)
        #expect(abs(result.distanceDeltaMeters - 200.0) < 0.001)
        #expect(result.needsInclineReview == true)
        #expect(result.effectiveCV == 0.035)
        #expect(result.effectiveSlope == 0.0)

        let totalDist = result.smoothedBuckets.map(\.distanceMeters).reduce(0.0, +)
        #expect(abs(totalDist - 1000.0) < 0.001)
    }
}
