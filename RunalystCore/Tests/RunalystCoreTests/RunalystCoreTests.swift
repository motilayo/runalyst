import Foundation
import Testing
@testable import RunalystCore

@Suite("TheMold Crucible Invariant Tests")
struct TheMoldTests {

    @Test("TelemetryBucket correctly stores primitives and calculates speed")
    func telemetryBucketCalculations() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let bucket = TelemetryBucket(
            timestamp: now,
            durationSeconds: 60.0,
            distanceMeters: 200.0,
            paceSecondsPerKm: 300.0,
            cadenceSPM: 165.0,
            heartRateBPM: 145.0,
            groundContactTimeMs: 240.0,
            verticalOscillationCm: 8.5,
            strideLengthMeters: 1.15,
            elevationGainMeters: 1.2
        )

        #expect(bucket.timestamp == now)
        #expect(bucket.distanceMeters == 200.0)
        #expect(bucket.durationSeconds == 60.0)
        #expect(bucket.speedMetersPerSecond == 200.0 / 60.0)
        #expect(bucket.cadenceSPM == 165.0)
        #expect(bucket.heartRateBPM == 145.0)
        #expect(bucket.groundContactTimeMs == 240.0)
        #expect(bucket.verticalOscillationCm == 8.5)
        #expect(bucket.strideLengthMeters == 1.15)
        #expect(bucket.elevationGainMeters == 1.2)
    }

    @Test("WorkingStats calculates derived biomechanical economy and ratios")
    func workingStatsCalculations() throws {
        let stats = WorkingStats(
            workingDistanceMeters: 5000.0,
            workingDurationSeconds: 1500.0,
            workingAvgPaceSecondsPerKm: 300.0,
            workingAvgCadenceSPM: 168.0,
            workingAvgHeartRateBPM: 150.0,
            workingAvgVerticalOscillationCm: 9.0,
            workingAvgStrideLengthMeters: 1.18,
            workingAvgGroundContactTimeMs: 235.0,
            rawTotalDistanceMeters: 5100.0,
            rawTotalDurationSeconds: 1600.0,
            rawAvgPaceSecondsPerKm: 313.7,
            rawAvgCadenceSPM: 164.0,
            rawAvgHeartRateBPM: 148.0,
            paceCV: 0.045,
            paceSlope: -0.012,
            percentZone4: 0.15,
            deadStopsCount: 2,
            isIndoor: false,
            needsInclineReview: false,
            detectedClassification: "Steady Effort",
            framboiseTags: ["consistentPace"]
        )

        // Speed: 60,000 / 300 = 200 m/min
        #expect(stats.speedMetersPerMinute == 200.0)
        // Efficiency Factor: 200 / 150 = 1.3333...
        let ef = try #require(stats.efficiencyFactor)
        #expect(abs(ef - (200.0 / 150.0)) < 0.001)

        // Vertical Ratio: 9.0 cm / 1.18 m = 7.627...
        let vr = try #require(stats.verticalRatio)
        #expect(abs(vr - (9.0 / 1.18)) < 0.001)

        #expect(!stats.isHeartRateSensorLowConfidence)
    }

    @Test("SubjectiveDistressSignal verifies safety overrides")
    func subjectiveDistressSignals() throws {
        #expect(SubjectiveDistressSignal.acuteFatigue.requiresSafetyOverride)
        #expect(SubjectiveDistressSignal.jointPain.requiresSafetyOverride)
        #expect(SubjectiveDistressSignal.illnessDeload.requiresSafetyOverride)
        #expect(SubjectiveDistressSignal.mechanicalBreakdown.requiresSafetyOverride)

        #expect(!SubjectiveDistressSignal.muscleSoreness.requiresSafetyOverride)
        #expect(!SubjectiveDistressSignal.thermalExhaustion.requiresSafetyOverride)
    }

    @Test("RunDirective verifies goal overrides and drill titles")
    func runDirectives() throws {
        let recovery = RunDirective.easyAerobicRecovery(pacingBand: .zone1Recovery, maxDurationMinutes: 30.0)
        #expect(recovery.priorityOverridesGoal)
        #expect(recovery.associatedDrillTitle == nil)

        let pyramids = RunDirective.cadencePyramids(targetFloorSPM: 155, targetCeilingSPM: 170, durationMinutes: 10.0)
        #expect(!pyramids.priorityOverridesGoal)
        #expect(pyramids.associatedDrillTitle == "Cadence Pyramids")

        let strides = RunDirective.strides(repetitions: 5, targetSPM: 180)
        #expect(!strides.priorityOverridesGoal)
        #expect(strides.associatedDrillTitle == "Strides")
    }

    @Test("Codable roundtrip preserves Mold ingots bit-for-bit")
    func codableRoundtrip() throws {
        let original = TelemetryBucket(
            timestamp: Date(timeIntervalSince1970: 1_700_000_123),
            durationSeconds: 30.0,
            distanceMeters: 100.0,
            paceSecondsPerKm: 300.0,
            cadenceSPM: 160.0,
            heartRateBPM: 140.0,
            groundContactTimeMs: 250.0,
            verticalOscillationCm: 8.0,
            strideLengthMeters: 1.1,
            elevationGainMeters: 0.5
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TelemetryBucket.self, from: encoded)
        #expect(original == decoded)
    }
}

@Suite("TrainingZoneCore Tests")
struct TrainingZoneCoreTests {

    @Test("Calculates deterministic 5-zone pacing matrix")
    func zoneMatrixCalculation() throws {
        let anchorPace = 360.0 // 6:00/km
        let matrix = TrainingZoneCore.calculateZones(anchorPaceSecPerKm: anchorPace, activeGoal: "5K Race")

        // Z1 Recovery: anchor + 60s to anchor + 90s (420s to 450s => 7:00–7:30/km)
        #expect(matrix.zone1Recovery.lowSecPerKm == 420.0)
        #expect(matrix.zone1Recovery.highSecPerKm == 450.0)
        #expect(matrix.zone1Recovery.formatted(useMetric: true) == "7:00–7:30/km")

        // Z2 Aerobic Base: anchor + 30s to anchor + 50s (390s to 410s => 6:30–6:50/km)
        #expect(matrix.zone2AerobicBase.lowSecPerKm == 390.0)
        #expect(matrix.zone2AerobicBase.highSecPerKm == 410.0)
        #expect(matrix.zone2AerobicBase.formatted(useMetric: true) == "6:30–6:50/km")

        // Z4 Threshold: anchor - 10s to anchor + 5s (350s to 365s => 5:50–6:05/km)
        #expect(matrix.zone4Threshold.lowSecPerKm == 350.0)
        #expect(matrix.zone4Threshold.highSecPerKm == 365.0)

        // Z5 Goal-specific (5K): anchor - 30s to anchor - 20s (330s to 340s => 5:30–5:40/km)
        #expect(matrix.zone5Interval.lowSecPerKm == 330.0)
        #expect(matrix.zone5Interval.highSecPerKm == 340.0)
    }

    @Test("Default anchor paces match athletic maturity tiers")
    func defaultAnchorPaces() throws {
        #expect(TrainingZoneCore.defaultPaceForExperience("Elite") == 255.0)
        #expect(TrainingZoneCore.defaultPaceForExperience("Advanced") == 290.0)
        #expect(TrainingZoneCore.defaultPaceForExperience("Intermediate") == 340.0)
        #expect(TrainingZoneCore.defaultPaceForExperience("Novice") == 400.0)
    }
}

@Suite("GoalBenchmarkCore Tests")
struct GoalBenchmarkCoreTests {

    @Test("Accurately evaluates volume status without premature onTrack classification")
    func goalBenchmarkVolumeStatus() throws {
        // 10K target is 25.0 to 42.0 km/wk
        let underBenchmark = GoalBenchmarkCore.evaluate(
            goal: "10K Race",
            currentWeeklyKm: 20.3,
            longestRunKm: 8.0,
            userHeightCm: 175.0
        )
        #expect(underBenchmark.weeklyVolumeStatus == .building)
        #expect(abs(underBenchmark.volumeGapKm - 4.7) < 0.001)

        let onTrackBenchmark = GoalBenchmarkCore.evaluate(
            goal: "10K Race",
            currentWeeklyKm: 30.0,
            longestRunKm: 12.0,
            userHeightCm: 175.0
        )
        #expect(onTrackBenchmark.weeklyVolumeStatus == .onTrack)
        #expect(onTrackBenchmark.volumeGapKm == 0.0)

        let exceedingBenchmark = GoalBenchmarkCore.evaluate(
            goal: "10K Race",
            currentWeeklyKm: 45.0,
            longestRunKm: 16.0,
            userHeightCm: 175.0
        )
        #expect(exceedingBenchmark.weeklyVolumeStatus == .exceeding)
        #expect(exceedingBenchmark.volumeGapKm == 0.0)
    }
}
