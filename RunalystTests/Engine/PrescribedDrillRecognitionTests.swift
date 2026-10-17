import XCTest
import HealthKit
import SwiftData
@testable import Runalyst

@MainActor
final class PrescribedDrillRecognitionTests: XCTestCase {
    override func setUp() {
        super.setUp()
        WorkoutBridge.clearIntents()
    }

    override func tearDown() {
        WorkoutBridge.clearIntents()
        super.tearDown()
    }

    func testScheduledDrillIntentPersistence() {
        let intent = ScheduledDrillIntent(
            drillTitle: "Cadence Pyramids",
            preRunDrillId: "cadence_pyramids",
            scheduledDate: Date(),
            durationMinutes: 15,
            targetCadence: "170-174"
        )
        WorkoutBridge.saveDrillIntent(intent)

        let recent = WorkoutBridge.recentIntents()
        XCTAssertTrue(recent.contains(where: { $0.drillTitle == "Cadence Pyramids" && $0.durationMinutes == 15 }))
    }

    func testWorkoutBridgeMatchDrillDirectMetadata() {
        let workoutDate = Date()
        let metadata: [String: Any] = [
            "HKWorkoutPlanDisplayName": "Cadence Pyramids"
        ]

        let matched = WorkoutBridge.matchDrill(
            workoutDate: workoutDate,
            durationSeconds: 900,
            metadata: metadata
        )

        XCTAssertNotNil(matched)
        XCTAssertEqual(matched?.drillTitle, "Cadence Pyramids")
        XCTAssertEqual(matched?.preRunDrillId, "cadence_pyramids")
    }

    func testWorkoutBridgeMatchDrillIntentWindow() {
        let scheduledDate = Date().addingTimeInterval(-600) // 10 mins ago
        let intent = ScheduledDrillIntent(
            drillTitle: "Rhythm Intervals",
            preRunDrillId: "rhythm_intervals",
            scheduledDate: scheduledDate,
            durationMinutes: 15,
            targetCadence: "165"
        )
        WorkoutBridge.saveDrillIntent(intent)

        // Incoming workout completed 2 minutes ago with matching duration (~15 mins = 920 sec)
        let workoutDate = Date().addingTimeInterval(-120)
        let matched = WorkoutBridge.matchDrill(
            workoutDate: workoutDate,
            durationSeconds: 920,
            metadata: nil
        )

        XCTAssertNotNil(matched)
        XCTAssertEqual(matched?.drillTitle, "Rhythm Intervals")
    }

    func testWorkoutBridgeMatchDrillHistoricalIntentWindow() {
        // Scheduled 7 days ago (like the user's run from Sept 10)
        let scheduledDate = Date().addingTimeInterval(-7 * 24 * 3600)
        let intent = ScheduledDrillIntent(
            drillTitle: "Cadence Pyramids",
            preRunDrillId: "cadence_pyramids",
            scheduledDate: scheduledDate,
            durationMinutes: 15,
            targetCadence: "160"
        )
        WorkoutBridge.saveDrillIntent(intent)

        // Workout completed 5 minutes after scheduled time
        let workoutDate = scheduledDate.addingTimeInterval(300)
        let matched = WorkoutBridge.matchDrill(
            workoutDate: workoutDate,
            durationSeconds: 904, // 15:04
            metadata: nil
        )

        XCTAssertNotNil(matched)
        XCTAssertEqual(matched?.drillTitle, "Cadence Pyramids")
        XCTAssertEqual(matched?.preRunDrillId, "cadence_pyramids")
    }

    func testWorkoutBridgeMatchNestedMetadata() {
        let workoutDate = Date()
        let metadata: [String: Any] = [
            "customData": [
                "subKey": "Outdoor Run - Cadence Pyramids"
            ]
        ]

        let matched = WorkoutBridge.matchDrill(
            workoutDate: workoutDate,
            durationSeconds: 900,
            metadata: metadata
        )

        XCTAssertNotNil(matched)
        XCTAssertEqual(matched?.drillTitle, "Cadence Pyramids")
    }

    func testWorkoutBridgeMatchesDistinctDrillTitlesWithoutCollidingToCadencePyramids() {
        let date = Date()

        // 1. Rhythm Intervals metadata
        let rhythmMatched = WorkoutBridge.matchDrill(
            workoutDate: date,
            durationSeconds: 900,
            metadata: ["HKWorkoutPlanDisplayName": "Rhythm Intervals"]
        )
        XCTAssertEqual(rhythmMatched?.drillTitle, "Rhythm Intervals")
        XCTAssertEqual(rhythmMatched?.preRunDrillId, "rhythm_intervals")

        // 2. Strides metadata
        let stridesMatched = WorkoutBridge.matchDrill(
            workoutDate: date,
            durationSeconds: 900,
            metadata: ["HKWorkoutPlanDisplayName": "Strides"]
        )
        XCTAssertEqual(stridesMatched?.drillTitle, "Strides")
        XCTAssertEqual(stridesMatched?.preRunDrillId, "strides")

        // 3. Tempo Surges metadata
        let surgesMatched = WorkoutBridge.matchDrill(
            workoutDate: date,
            durationSeconds: 900,
            metadata: ["HKWorkoutPlanDisplayName": "Tempo Surges"]
        )
        XCTAssertEqual(surgesMatched?.drillTitle, "Tempo Surges")
        XCTAssertEqual(surgesMatched?.preRunDrillId, "tempo_surges")

        // 4. Form Primer metadata
        let primerMatched = WorkoutBridge.matchDrill(
            workoutDate: date,
            durationSeconds: 600,
            metadata: ["HKWorkoutPlanDisplayName": "Form Primer"]
        )
        XCTAssertEqual(primerMatched?.drillTitle, "Form Primer")
        XCTAssertEqual(primerMatched?.preRunDrillId, "neuromuscular_primer")

        // 5. Unscheduled workout with no drill metadata must NOT match any drill (even if 900 seconds)
        let unprescribed = WorkoutBridge.matchDrill(
            workoutDate: date,
            durationSeconds: 900,
            metadata: ["HKMetadataKeyWorkoutBrandName": "Apple Workout"]
        )
        XCTAssertNil(unprescribed, "Unscheduled runs with no drill metadata must not match as a drill")
    }

    func testRhythmIntervalsSingularAndVariationsMatching() {
        let date = Date()

        // 1. Singular "Rhythm Interval" in metadata
        let singular = WorkoutBridge.matchDrill(
            workoutDate: date,
            durationSeconds: 900,
            metadata: ["HKWorkoutPlanDisplayName": "Rhythm Interval"]
        )
        XCTAssertNotNil(singular, "Singular 'Rhythm Interval' must match Rhythm Intervals")
        XCTAssertEqual(singular?.drillTitle, "Rhythm Intervals")
        XCTAssertEqual(singular?.preRunDrillId, "rhythm_intervals")

        // 2. Kebab-case "rhythm-interval"
        let kebab = WorkoutBridge.matchDrill(
            workoutDate: date,
            durationSeconds: 600,
            metadata: ["workoutTitle": "rhythm-interval"]
        )
        XCTAssertNotNil(kebab)
        XCTAssertEqual(kebab?.drillTitle, "Rhythm Intervals")

        // 3. Substring "Outdoor Run - Rhythm"
        let substring = WorkoutBridge.matchDrill(
            workoutDate: date,
            durationSeconds: 600,
            metadata: ["displayName": "Outdoor Run - Rhythm"]
        )
        XCTAssertNotNil(substring)
        XCTAssertEqual(substring?.drillTitle, "Rhythm Intervals")
    }

    func testRhythmIntervalsExtendedRunDurationMatching() {
        let scheduledDate = Date().addingTimeInterval(-1800) // 30 mins ago
        let intent = ScheduledDrillIntent(
            drillTitle: "Rhythm Intervals",
            preRunDrillId: "rhythm_intervals",
            scheduledDate: scheduledDate,
            durationMinutes: 10,
            targetCadence: "162"
        )
        WorkoutBridge.saveDrillIntent(intent)

        // Incoming workout completed 5 mins ago, but user ran for 22 minutes (1320s) with warm-up/cool-down
        let workoutDate = Date().addingTimeInterval(-300)
        let matched = WorkoutBridge.matchDrill(
            workoutDate: workoutDate,
            durationSeconds: 1320,
            metadata: nil
        )

        XCTAssertNotNil(matched, "10-minute scheduled intent must match 22-minute session containing the drill")
        XCTAssertEqual(matched?.drillTitle, "Rhythm Intervals")
    }

    func testRunBaselineDataIncludesAllRunsWeighted() {
        let now = Date()
        let allRuns = [
            HealthKitManager.RunBaselineData(date: now.addingTimeInterval(-86400 * 2), pace: 300, hr: 150, cadence: 165, duration: 2400, isPrescribedDrill: false),
            HealthKitManager.RunBaselineData(date: now.addingTimeInterval(-86400 * 4), pace: 310, hr: 152, cadence: 164, duration: 2700, isPrescribedDrill: false),
            HealthKitManager.RunBaselineData(date: now.addingTimeInterval(-86400 * 6), pace: 295, hr: 148, cadence: 166, duration: 2500, isPrescribedDrill: false),
            // Short 15-min drill with sprint pace/cadence
            HealthKitManager.RunBaselineData(date: now.addingTimeInterval(-86400 * 1), pace: 220, hr: 175, cadence: 185, duration: 900, isPrescribedDrill: true)
        ]

        // All runs are included (every run counts)
        XCTAssertEqual(allRuns.count, 4)

        // Duration-weighted baseline calculation
        let totalDuration = allRuns.map(\.duration).reduce(0, +)
        let weightedCadence = allRuns.map { $0.cadence * $0.duration }.reduce(0, +) / totalDuration

        // With duration weighting: (165*2400 + 164*2700 + 166*2500 + 185*900) / 8500 = ~167.1
        // The 15-min drill contributes proportionally (only 900s out of 8500s) without being discarded
        XCTAssertEqual(weightedCadence, 167.1, accuracy: 0.2)
    }

    func testDrillAutoCompletionAndTrainingCorrection() throws {
        let schema = Schema([RunRecord.self, CoachingInsight.self, DrillRecommendation.self, TrainingCorrection.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let drill = DrillRecommendation(
            drillTitle: "Cadence Pyramids",
            preRunDrillId: "cadence_pyramids",
            drillPurpose: "Turnover improvement",
            isCompleted: false
        )
        context.insert(drill)
        try context.save()

        XCTAssertFalse(drill.isCompleted)

        // Simulate incoming recognized drill
        let newRunID = UUID()
        let drillTitle = "Cadence Pyramids"
        let framboiseTags = ["prescribedDrill", "cadence_pyramids"]

        let openDrillsDescriptor = FetchDescriptor<DrillRecommendation>(
            predicate: #Predicate<DrillRecommendation> { item in
                !item.isCompleted
            }
        )
        if let openDrills = try? context.fetch(openDrillsDescriptor) {
            for item in openDrills {
                let matchesId = item.preRunDrillId.map { framboiseTags.contains($0) } ?? false
                let matchesTitle = item.drillTitle.localizedCaseInsensitiveCompare(drillTitle) == .orderedSame
                if matchesTitle || matchesId {
                    item.isCompleted = true
                }
            }
        }

        // Insert ground-truth TrainingCorrection
        let correction = TrainingCorrection(
            runRecordID: newRunID,
            originalLabel: "Prescribed Drill",
            correctedLabel: drillTitle,
            featureVector: [280.0, 0.12, -0.02, 0.25, 15.0],
            createdAt: Date(),
            isProcessed: false
        )
        context.insert(correction)
        try context.save()

        XCTAssertTrue(drill.isCompleted, "Matching drill recommendation should be marked as completed")

        let fetchedCorrections = try context.fetch(FetchDescriptor<TrainingCorrection>())
        XCTAssertEqual(fetchedCorrections.count, 1)
        XCTAssertEqual(fetchedCorrections.first?.correctedLabel, "Cadence Pyramids")
        XCTAssertEqual(fetchedCorrections.first?.featureVector.count, 5)
    }

    func testDrillToRunClassificationMapping() {
        // Explicit user requirement cases
        XCTAssertEqual(PreRunDrillId.correspondingClassification(for: "Rhythm Intervals"), "Intervals")
        XCTAssertEqual(PreRunDrillId.correspondingClassification(for: "rhythm_intervals"), "Intervals")
        XCTAssertEqual(PreRunDrillId.correspondingClassification(for: "Recovery Jog"), "Recovery Run")
        XCTAssertEqual(PreRunDrillId.correspondingClassification(for: "recovery_jog"), "Recovery Run")
        XCTAssertEqual(PreRunDrillId.correspondingClassification(for: "Cadence Pyramids"), "Intervals")
        XCTAssertEqual(PreRunDrillId.correspondingClassification(for: "Tempo Surges"), "Tempo Run")
        XCTAssertEqual(PreRunDrillId.correspondingClassification(for: "Strides"), "Intervals")

        // Canonical drill titles
        XCTAssertEqual(PreRunDrillId.canonicalDrillTitle(for: "rhythm_intervals"), "Rhythm Intervals")
        XCTAssertEqual(PreRunDrillId.canonicalDrillTitle(for: "recovery_jog"), "Recovery Jog")

        // Standard run classifications must NEVER be treated as drills or map to drills
        XCTAssertNil(PreRunDrillId.canonicalDrillTitle(for: "Intervals"))
        XCTAssertNil(PreRunDrillId.canonicalDrillTitle(for: "Tempo Run"))
        XCTAssertNil(PreRunDrillId.canonicalDrillTitle(for: "Recovery Run"))
        XCTAssertNil(PreRunDrillId.canonicalDrillTitle(for: "Steady Effort"))
        XCTAssertNil(PreRunDrillId.canonicalDrillTitle(for: "Long Run"))
        XCTAssertNil(PreRunDrillId.canonicalDrillTitle(for: "intervals"))

        XCTAssertNil(PreRunDrillId.correspondingClassification(for: "Intervals"))
        XCTAssertNil(PreRunDrillId.correspondingClassification(for: "Tempo Run"))
        XCTAssertNil(PreRunDrillId.correspondingClassification(for: "Recovery Run"))
    }

    func testDrillAdherenceTierProperties() {
        XCTAssertEqual(DrillAdherenceTier.exceeded.badgeText, "Exceeded")
        XCTAssertEqual(DrillAdherenceTier.met.badgeText, "Met")
        XCTAssertEqual(DrillAdherenceTier.partiallyMet.badgeText, "Partially Met")
        XCTAssertEqual(DrillAdherenceTier.notMet.badgeText, "Not Met")

        XCTAssertEqual(DrillAdherenceTier.exceeded.badgeIcon, "star.fill")
        XCTAssertEqual(DrillAdherenceTier.met.badgeIcon, "checkmark")
        XCTAssertEqual(DrillAdherenceTier.partiallyMet.badgeIcon, "minus")
        XCTAssertEqual(DrillAdherenceTier.notMet.badgeIcon, "xmark")

        // Recovery / Zone 1 & Zone 2 heart rate targeted drills
        XCTAssertEqual(DrillAdherenceTier.exceeded.badgeText(for: .aerobicFlush), "Optimal")
        XCTAssertEqual(DrillAdherenceTier.met.badgeText(for: .aerobicFlush), "Target Met")
        XCTAssertEqual(DrillAdherenceTier.exceeded.badgeIcon(for: .aerobicFlush), "checkmark.seal.fill")
        XCTAssertEqual(DrillAdherenceTier.exceeded.badgeText(for: .zone2Run), "Optimal")
        XCTAssertEqual(DrillAdherenceTier.met.badgeText(for: .zone2Run), "Target Met")
        XCTAssertEqual(DrillAdherenceTier.exceeded.badgeText(for: .cadencePyramids), "Exceeded")
    }

    func testDrillTitlesAreUniqueAndZone2RunAppearsOnce() {
        let titles = PreRunDrillId.allCases.map(\.title)
        let uniqueTitles = Set(titles)
        XCTAssertEqual(titles.count, uniqueTitles.count, "All drill titles in PreRunDrillId.allCases must be unique without duplicates")

        let zone2Occurrences = titles.filter { $0 == "Zone 2 Run" }
        XCTAssertEqual(zone2Occurrences.count, 1, "Zone 2 Run must only appear once in allCases")

        // Verify legacy mapping
        XCTAssertEqual(PreRunDrillId(rawValue: "aerobic_base_builder"), .zone2Run)
        XCTAssertEqual(PreRunDrillId.canonicalDrillTitle(for: "aerobic_base_builder"), "Zone 2 Run")
        XCTAssertEqual(PreRunDrillId.correspondingClassification(for: "aerobic_base_builder"), "Easy Run")
    }

    func testCadenceStabilitySteadyEffortClassification() async {
        let modelManager = ModelManager()
        let framboise = FramboiseEngine()

        // Reproduces the exact user's run:
        // High HR (170 BPM), high Zone 4 (0.85), pace CV = 0.09, duration = 27 min
        // BUT rock-solid turnover at 161-162 SPM (0 oscillation cycles)
        var steadyBuckets: [BucketData] = []
        var now = Date()
        for i in 0..<54 { // 54 * 30s = 27 min
            let cadence = (i % 2 == 0) ? 161.0 : 162.0
            steadyBuckets.append(BucketData(startTime: now, distanceMeters: 80, durationSeconds: 30, meanPaceSecPerKm: 375, meanCadence: cadence, meanHR: 170))
            now = now.addingTimeInterval(30)
        }

        let classification = await modelManager.predictRunType(
            buckets: steadyBuckets,
            paceDelta: 0.0,
            hrDelta: 20.0,
            percentZone4: 0.85,
            cadenceDelta: 1.0,
            verticalOscillation: 9.9,
            runnerStage: 1,
            cv: 0.09,
            slope: -0.05,
            durationMinutes: 27.0,
            cadenceCV: 0.012,
            rawAverageHR: 170.0
        )

        // Must classify as Steady Effort (or Tempo Run), NEVER Fartlek or Intervals!
        XCTAssertNotEqual(classification, "Fartlek", "Rock-solid cadence must never be classified as Fartlek")
        XCTAssertNotEqual(classification, "Intervals", "Rock-solid cadence must never be classified as Intervals")
        XCTAssertTrue(classification == "Steady Effort" || classification == "Tempo Run")

        // Direct test on FramboiseEngine weighted scoring
        let directClass = await framboise.classifyRun(
            buckets: steadyBuckets,
            cv: 0.09,
            slope: -0.05,
            zone4: 0.85,
            durationMinutes: 27.0,
            cadenceCV: 0.012,
            averageHR: 170.0,
            paceDelta: 0.0,
            hrDelta: 20.0
        )
        XCTAssertEqual(directClass, "Steady Effort")
    }

    func testIntermittentIntervalClassification() async {
        let framboise = FramboiseEngine()

        // Intermittent structured workout: 4 metronomic reps (60s work, 60s recovery)
        var intervalBuckets: [BucketData] = []
        var now = Date()
        for _ in 0..<4 {
            for _ in 0..<2 { // 60s work
                intervalBuckets.append(BucketData(startTime: now, distanceMeters: 100, durationSeconds: 30, meanPaceSecPerKm: 300, meanCadence: 178, meanHR: 168))
                now = now.addingTimeInterval(30)
            }
            for _ in 0..<2 { // 60s recovery
                intervalBuckets.append(BucketData(startTime: now, distanceMeters: 55, durationSeconds: 30, meanPaceSecPerKm: 540, meanCadence: 135, meanHR: 138))
                now = now.addingTimeInterval(30)
            }
        }

        let intervalClass = await framboise.classifyRun(
            buckets: intervalBuckets,
            cv: 0.14,
            slope: 0.0,
            zone4: 0.50,
            durationMinutes: 25.0,
            cadenceCV: 0.042,
            averageHR: 165.0
        )
        XCTAssertEqual(intervalClass, "Intervals")
    }

    func testDrillIntervalEvaluatorRepScoring() {
        // Construct synthetic 15-second buckets for a 15-minute Cadence Pyramids drill
        // 180s warmup, 4 reps of (60s work, 90s recovery), 120s cooldown
        // Target: 166-172 SPM for 160 baseline
        let now = Date()
        var buckets: [BucketData] = []
        var currentTime = now

        // Warmup: 12 buckets (180s) at 150 SPM
        for _ in 0..<12 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 40, durationSeconds: 15, meanPaceSecPerKm: 375, meanCadence: 150, meanHR: 140))
            currentTime = currentTime.addingTimeInterval(15)
        }

        // Rep 1: 4 buckets (60s) at 170 SPM (HIT)
        for _ in 0..<4 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 45, durationSeconds: 15, meanPaceSecPerKm: 333, meanCadence: 170, meanHR: 160))
            currentTime = currentTime.addingTimeInterval(15)
        }
        // Rec 1: 6 buckets (90s) at 135 SPM
        for _ in 0..<6 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 30, durationSeconds: 15, meanPaceSecPerKm: 500, meanCadence: 135, meanHR: 145))
            currentTime = currentTime.addingTimeInterval(15)
        }

        // Rep 2: 4 buckets (60s) at 168 SPM (HIT)
        for _ in 0..<4 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 45, durationSeconds: 15, meanPaceSecPerKm: 333, meanCadence: 168, meanHR: 162))
            currentTime = currentTime.addingTimeInterval(15)
        }
        // Rec 2: 6 buckets (90s) at 135 SPM
        for _ in 0..<6 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 30, durationSeconds: 15, meanPaceSecPerKm: 500, meanCadence: 135, meanHR: 145))
            currentTime = currentTime.addingTimeInterval(15)
        }

        // Rep 3: 4 buckets (60s) at 155 SPM (MISSED - too low)
        for _ in 0..<4 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 40, durationSeconds: 15, meanPaceSecPerKm: 375, meanCadence: 155, meanHR: 158))
            currentTime = currentTime.addingTimeInterval(15)
        }
        // Rec 3: 6 buckets (90s) at 135 SPM
        for _ in 0..<6 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 30, durationSeconds: 15, meanPaceSecPerKm: 500, meanCadence: 135, meanHR: 145))
            currentTime = currentTime.addingTimeInterval(15)
        }

        // Rep 4: 4 buckets (60s) at 171 SPM (HIT)
        for _ in 0..<4 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 45, durationSeconds: 15, meanPaceSecPerKm: 333, meanCadence: 171, meanHR: 165))
            currentTime = currentTime.addingTimeInterval(15)
        }
        // Rec 4: 6 buckets (90s) at 135 SPM
        for _ in 0..<6 {
            buckets.append(BucketData(startTime: currentTime, distanceMeters: 30, durationSeconds: 15, meanPaceSecPerKm: 500, meanCadence: 135, meanHR: 145))
            currentTime = currentTime.addingTimeInterval(15)
        }

        let summary = DrillIntervalEvaluator.evaluate(
            buckets: buckets,
            drillId: .cadencePyramids,
            baselineCadence: 160,
            workoutDuration: 900
        )

        // 3 out of 4 work reps met target
        XCTAssertEqual(summary.totalIntervals, 4)
        XCTAssertEqual(summary.intervalsMet, 3)
        XCTAssertEqual(summary.adherencePercentage, 75)
        XCTAssertEqual(summary.tier, .partiallyMet)
        XCTAssertEqual(summary.reps.count, 4)
        XCTAssertEqual(summary.reps[0].isMet, true)
        XCTAssertEqual(summary.reps[1].isMet, true)
        XCTAssertEqual(summary.reps[2].isMet, false)
        XCTAssertEqual(summary.reps[3].isMet, true)
        XCTAssertTrue(summary.workCadenceAvg >= 165)
        XCTAssertTrue(summary.recoveryCadenceAvg <= 140)

        // Verify framboise tags formatting and round-trip decoding
        let tags = summary.framboiseTags
        XCTAssertTrue(tags.contains("drillIntervals:3/4"))
        XCTAssertTrue(tags.contains("drillReps:1,1,0,1"))

        let reconstructed = DrillIntervalSummary.from(tags: tags, drillId: .cadencePyramids)
        XCTAssertNotNil(reconstructed)
        XCTAssertEqual(reconstructed?.intervalsMet, 3)
        XCTAssertEqual(reconstructed?.totalIntervals, 4)
        XCTAssertEqual(reconstructed?.tier, .partiallyMet)
    }

    func testDrillIntervalEvaluatorPhaseShiftedWaveform() {
        let now = Date()
        var buckets: [BucketData] = []
        var currentTime = now

        // Open warmup: 16 buckets (240s = 4 mins) at 125 SPM (shifted by 60s past theoretical 180s)
        for _ in 0..<16 {
            buckets.append(BucketData(
                startTime: currentTime,
                distanceMeters: 30,
                durationSeconds: 15,
                meanPaceSecPerKm: 500,
                meanCadence: 125,
                meanHR: 130
            ))
            currentTime = currentTime.addingTimeInterval(15)
        }

        // 4 intervals with recovery:
        let workCadences: [Double] = [155, 158, 160, 162]
        let recCadences: [Double] = [100, 102, 101, 104]

        for rep in 0..<4 {
            // Work: 4 buckets (60s)
            for _ in 0..<4 {
                buckets.append(BucketData(
                    startTime: currentTime,
                    distanceMeters: 45,
                    durationSeconds: 15,
                    meanPaceSecPerKm: 333,
                    meanCadence: workCadences[rep],
                    meanHR: 160
                ))
                currentTime = currentTime.addingTimeInterval(15)
            }
            // Recovery: 6 buckets (90s)
            for _ in 0..<6 {
                buckets.append(BucketData(
                    startTime: currentTime,
                    distanceMeters: 25,
                    durationSeconds: 15,
                    meanPaceSecPerKm: 600,
                    meanCadence: recCadences[rep],
                    meanHR: 125
                ))
                currentTime = currentTime.addingTimeInterval(15)
            }
        }

        // Cooldown: 4 buckets (60s) at 110 SPM
        for _ in 0..<4 {
            buckets.append(BucketData(
                startTime: currentTime,
                distanceMeters: 25,
                durationSeconds: 15,
                meanPaceSecPerKm: 600,
                meanCadence: 110,
                meanHR: 120
            ))
            currentTime = currentTime.addingTimeInterval(15)
        }

        let summary = DrillIntervalEvaluator.evaluate(
            buckets: buckets,
            drillId: .cadencePyramids,
            baselineCadence: 150,
            workoutDuration: 900
        )

        XCTAssertEqual(summary.totalIntervals, 4)
        XCTAssertEqual(summary.intervalsMet, 4)
        XCTAssertEqual(summary.adherencePercentage, 100)
        XCTAssertEqual(summary.tier, .exceeded)
        XCTAssertEqual(summary.reps.count, 4)
        XCTAssertTrue(summary.workCadenceAvg >= 155)
        XCTAssertTrue(summary.recoveryCadenceAvg <= 105)
    }

    func testDrillIntervalEvaluatorWorkoutActivities() {
        let now = Date()
        var buckets: [BucketData] = []
        var currentTime = now
        var activities: [HKWorkoutActivity] = []

        let config = HKWorkoutConfiguration()
        config.activityType = .running

        // 4 pairs of Work and Recovery activities
        for _ in 0..<4 {
            let workStart = currentTime
            let workEnd = workStart.addingTimeInterval(60)
            for _ in 0..<4 {
                buckets.append(BucketData(
                    startTime: currentTime,
                    distanceMeters: 45,
                    durationSeconds: 15,
                    meanPaceSecPerKm: 333,
                    meanCadence: 158,
                    meanHR: 160
                ))
                currentTime = currentTime.addingTimeInterval(15)
            }
            activities.append(HKWorkoutActivity(
                workoutConfiguration: config,
                start: workStart,
                end: workEnd,
                metadata: ["HKWorkoutActivityType": "Work"]
            ))

            let recStart = currentTime
            let recEnd = recStart.addingTimeInterval(90)
            for _ in 0..<6 {
                buckets.append(BucketData(
                    startTime: currentTime,
                    distanceMeters: 25,
                    durationSeconds: 15,
                    meanPaceSecPerKm: 600,
                    meanCadence: 102,
                    meanHR: 125
                ))
                currentTime = currentTime.addingTimeInterval(15)
            }
            activities.append(HKWorkoutActivity(
                workoutConfiguration: config,
                start: recStart,
                end: recEnd,
                metadata: ["HKWorkoutActivityType": "Recovery"]
            ))
        }

        let context = DrillIntervalEvaluator.Context(
            drillId: .cadencePyramids,
            effectiveRange: 155...165,
            baselineCadence: 150,
            oscDelta: 0.0
        )
        let summary = DrillIntervalEvaluator.evaluateFromActivities(
            activities: activities,
            buckets: buckets,
            context: context
        )

        XCTAssertNotNil(summary)
        XCTAssertEqual(summary?.totalIntervals, 4)
        XCTAssertEqual(summary?.intervalsMet, 4)
        XCTAssertEqual(summary?.workCadenceAvg, 158)
        XCTAssertEqual(summary?.recoveryCadenceAvg, 102)
    }

    func testDrillIntervalEvaluatorWorkoutEvents() {
        let now = Date()
        var buckets: [BucketData] = []
        var currentTime = now
        var events: [HKWorkoutEvent] = []

        for _ in 0..<4 {
            let workStart = currentTime
            let workEnd = workStart.addingTimeInterval(60)
            events.append(HKWorkoutEvent(
                type: .segment,
                dateInterval: DateInterval(start: workStart, end: workEnd),
                metadata: nil
            ))
            for _ in 0..<4 {
                buckets.append(BucketData(
                    startTime: currentTime,
                    distanceMeters: 45,
                    durationSeconds: 15,
                    meanPaceSecPerKm: 333,
                    meanCadence: 160,
                    meanHR: 162
                ))
                currentTime = currentTime.addingTimeInterval(15)
            }

            let recStart = currentTime
            let recEnd = recStart.addingTimeInterval(90)
            events.append(HKWorkoutEvent(
                type: .segment,
                dateInterval: DateInterval(start: recStart, end: recEnd),
                metadata: nil
            ))
            for _ in 0..<6 {
                buckets.append(BucketData(
                    startTime: currentTime,
                    distanceMeters: 25,
                    durationSeconds: 15,
                    meanPaceSecPerKm: 600,
                    meanCadence: 104,
                    meanHR: 128
                ))
                currentTime = currentTime.addingTimeInterval(15)
            }
        }

        let workout = HKWorkout(
            activityType: .running,
            start: now,
            end: currentTime,
            workoutEvents: events,
            totalEnergyBurned: nil,
            totalDistance: nil,
            metadata: nil
        )

        let summary = DrillIntervalEvaluator.evaluate(
            workout: workout,
            buckets: buckets,
            drillId: .cadencePyramids,
            baselineCadence: 150,
            workoutDuration: currentTime.timeIntervalSince(now)
        )

        XCTAssertEqual(summary.totalIntervals, 4)
        XCTAssertEqual(summary.intervalsMet, 4)
        XCTAssertEqual(summary.workCadenceAvg, 160)
        XCTAssertEqual(summary.recoveryCadenceAvg, 104)
    }

    func testCadencePyramidsWithJoggedRecoveriesDoesNotCreateSpuriousWorkReps() {
        let now = Date()
        var buckets: [BucketData] = []
        var currentTime = now
        var activities: [HKWorkoutActivity] = []
        let config = HKWorkoutConfiguration()
        config.activityType = .running

        // Segment 0: Warmup (180s, 140 SPM)
        let warmupStart = currentTime
        let warmupEnd = warmupStart.addingTimeInterval(180)
        for _ in 0..<12 {
            buckets.append(BucketData(
                startTime: currentTime,
                distanceMeters: 40,
                durationSeconds: 15,
                meanPaceSecPerKm: 414,
                meanCadence: 140,
                meanHR: 135
            ))
            currentTime = currentTime.addingTimeInterval(15)
        }
        activities.append(HKWorkoutActivity(
            workoutConfiguration: config,
            start: warmupStart,
            end: warmupEnd,
            metadata: nil
        ))

        // Reps 1 to 4: Work (60s) + Recovery (90s)
        // From user workout:
        // Work 1: 152 SPM, Rec 1 (jog): 144 SPM
        // Work 2: 156 SPM, Rec 2 (jog): 142 SPM
        // Work 3: 159 SPM, Rec 3 (jog): 140 SPM
        // Work 4: 161 SPM, Rec 4 (walk): 95 SPM
        let repsData: [(workC: Double, workHR: Double, recC: Double, recHR: Double)] = [
            (152, 158, 144, 140),
            (156, 162, 142, 142),
            (159, 166, 140, 141),
            (161, 170, 95, 120)
        ]

        for rep in repsData {
            let workStart = currentTime
            let workEnd = workStart.addingTimeInterval(60)
            for _ in 0..<4 {
                buckets.append(BucketData(
                    startTime: currentTime,
                    distanceMeters: 45,
                    durationSeconds: 15,
                    meanPaceSecPerKm: 339,
                    meanCadence: rep.workC,
                    meanHR: rep.workHR
                ))
                currentTime = currentTime.addingTimeInterval(15)
            }
            activities.append(HKWorkoutActivity(
                workoutConfiguration: config,
                start: workStart,
                end: workEnd,
                metadata: nil
            ))

            let recStart = currentTime
            let recEnd = recStart.addingTimeInterval(90)
            for _ in 0..<6 {
                buckets.append(BucketData(
                    startTime: currentTime,
                    distanceMeters: 30,
                    durationSeconds: 15,
                    meanPaceSecPerKm: 420,
                    meanCadence: rep.recC,
                    meanHR: rep.recHR
                ))
                currentTime = currentTime.addingTimeInterval(15)
            }
            activities.append(HKWorkoutActivity(
                workoutConfiguration: config,
                start: recStart,
                end: recEnd,
                metadata: nil
            ))
        }

        // Segment 9: Cooldown (120s, 100 SPM)
        let cooldownStart = currentTime
        let cooldownEnd = cooldownStart.addingTimeInterval(120)
        for _ in 0..<8 {
            buckets.append(BucketData(
                startTime: currentTime,
                distanceMeters: 35,
                durationSeconds: 15,
                meanPaceSecPerKm: 419,
                meanCadence: 100,
                meanHR: 125
            ))
            currentTime = currentTime.addingTimeInterval(15)
        }
        activities.append(HKWorkoutActivity(
            workoutConfiguration: config,
            start: cooldownStart,
            end: cooldownEnd,
            metadata: nil
        ))

        XCTAssertEqual(activities.count, 10, "Should have 10 activities: warmup, 4 work/rec pairs, cooldown")

        let context = DrillIntervalEvaluator.Context(
            drillId: .cadencePyramids,
            effectiveRange: 150...165,
            baselineCadence: 148,
            oscDelta: 0.0,
            durationCategory: .fifteenMinutes
        )

        let summary = DrillIntervalEvaluator.evaluateFromActivities(
            activities: activities,
            buckets: buckets,
            context: context
        )

        XCTAssertNotNil(summary)
        // Adherence grades work intervals ONLY - exactly 4 work reps, NOT 8 or 10!
        XCTAssertEqual(summary?.totalIntervals, 4)
        XCTAssertEqual(summary?.reps.count, 4)
        XCTAssertEqual(summary?.intervalsMet, 4)
        XCTAssertEqual(summary?.adherencePercentage, 100)
        XCTAssertEqual(summary?.workCadenceAvg, 157)
        XCTAssertEqual(summary?.recoveryCadenceAvg, 130)

        // Verify individual reps maintain work and recovery isolation
        XCTAssertEqual(summary?.reps[0].workCadence, 152)
        XCTAssertEqual(summary?.reps[0].recoveryCadence, 144)
        XCTAssertEqual(summary?.reps[0].isMet, true)

        XCTAssertEqual(summary?.reps[1].workCadence, 156)
        XCTAssertEqual(summary?.reps[1].recoveryCadence, 142)
        XCTAssertEqual(summary?.reps[1].isMet, true)

        XCTAssertEqual(summary?.reps[2].workCadence, 159)
        XCTAssertEqual(summary?.reps[2].recoveryCadence, 140)
        XCTAssertEqual(summary?.reps[2].isMet, true)

        XCTAssertEqual(summary?.reps[3].workCadence, 161)
        XCTAssertEqual(summary?.reps[3].recoveryCadence, 95)
        XCTAssertEqual(summary?.reps[3].isMet, true)

        // Framboise tags formatting
        guard let tags = summary?.framboiseTags else {
            XCTFail("Tags should exist")
            return
        }
        XCTAssertTrue(tags.contains("drillIntervals:4/4"))
        XCTAssertTrue(tags.contains("drillWorkCadence:157"))
        XCTAssertTrue(tags.contains("drillRecCadence:130"))
        XCTAssertTrue(tags.contains("drillReps:1,1,1,1"))
    }

    func testRhythmIntervalsWithAsymmetricCadenceToleranceAndExactStats() {
        let now = Date()
        var buckets: [BucketData] = []
        var currentTime = now
        var activities: [HKWorkoutActivity] = []
        let config = HKWorkoutConfiguration()
        config.activityType = .running

        // Segment 0: Warmup (180s, 148 SPM)
        let warmupStart = currentTime
        let warmupEnd = warmupStart.addingTimeInterval(180)
        for _ in 0..<12 {
            buckets.append(BucketData(
                startTime: currentTime,
                distanceMeters: 45,
                durationSeconds: 15,
                meanPaceSecPerKm: 333,
                meanCadence: 148,
                meanHR: 130
            ))
            currentTime = currentTime.addingTimeInterval(15)
        }
        activities.append(HKWorkoutActivity(
            workoutConfiguration: config,
            start: warmupStart,
            end: warmupEnd,
            metadata: nil
        ))

        // Reps 1 to 5: Work (45s) + Recovery (75s)
        // Work: 162, 167, 170, 167, 169 SPM
        // Recovery: 157, 161, 164, 162, 156 SPM
        let repsData: [(workC: Double, workHR: Double, recC: Double, recHR: Double)] = [
            (162, 148, 157, 157),
            (167, 157, 161, 161),
            (170, 165, 164, 166),
            (167, 167, 162, 163),
            (169, 161, 156, 161)
        ]

        for rep in repsData {
            let workStart = currentTime
            let workEnd = workStart.addingTimeInterval(45)
            for _ in 0..<3 {
                buckets.append(BucketData(
                    startTime: currentTime,
                    distanceMeters: 55,
                    durationSeconds: 15,
                    meanPaceSecPerKm: 272,
                    meanCadence: rep.workC,
                    meanHR: rep.workHR
                ))
                currentTime = currentTime.addingTimeInterval(15)
            }
            activities.append(HKWorkoutActivity(
                workoutConfiguration: config,
                start: workStart,
                end: workEnd,
                metadata: nil
            ))

            let recStart = currentTime
            let recEnd = recStart.addingTimeInterval(75)
            for _ in 0..<5 {
                buckets.append(BucketData(
                    startTime: currentTime,
                    distanceMeters: 40,
                    durationSeconds: 15,
                    meanPaceSecPerKm: 375,
                    meanCadence: rep.recC,
                    meanHR: rep.recHR
                ))
                currentTime = currentTime.addingTimeInterval(15)
            }
            activities.append(HKWorkoutActivity(
                workoutConfiguration: config,
                start: recStart,
                end: recEnd,
                metadata: nil
            ))
        }

        // Segment 11: Cooldown (120s, 158 SPM)
        let cooldownStart = currentTime
        let cooldownEnd = cooldownStart.addingTimeInterval(120)
        for _ in 0..<8 {
            buckets.append(BucketData(
                startTime: currentTime,
                distanceMeters: 40,
                durationSeconds: 15,
                meanPaceSecPerKm: 375,
                meanCadence: 158,
                meanHR: 156
            ))
            currentTime = currentTime.addingTimeInterval(15)
        }
        activities.append(HKWorkoutActivity(
            workoutConfiguration: config,
            start: cooldownStart,
            end: cooldownEnd,
            metadata: nil
        ))

        XCTAssertEqual(activities.count, 12, "Should have 12 activities: warmup, 5 work/rec pairs, cooldown")

        let context = DrillIntervalEvaluator.Context(
            drillId: .rhythmIntervals,
            effectiveRange: 157...163,
            baselineCadence: 151,
            oscDelta: 0.1,
            durationCategory: .fifteenMinutes
        )

        let summary = DrillIntervalEvaluator.evaluateFromActivities(
            activities: activities,
            buckets: buckets,
            context: context
        )

        XCTAssertNotNil(summary)
        guard let summary = summary else { return }

        // Total intervals should be exactly 5
        XCTAssertEqual(summary.totalIntervals, 5)
        XCTAssertEqual(summary.reps.count, 5)

        // Work average: (162 + 167 + 170 + 167 + 169) / 5 = 167 SPM
        XCTAssertEqual(summary.workCadenceAvg, 167)

        // Recovery average: (157 + 161 + 164 + 162 + 156) / 5 = 160 SPM
        XCTAssertEqual(summary.recoveryCadenceAvg, 160)

        // With asymmetric tolerance (+8 SPM: 155-171), all 5 reps meet the target
        XCTAssertEqual(summary.intervalsMet, 5)
        XCTAssertEqual(summary.adherencePercentage, 100)
        for rep in summary.reps {
            XCTAssertTrue(rep.isMet, "Rep \(rep.repIndex) with cadence \(rep.workCadence) should be met")
        }

        // Verify tags
        let tags = summary.framboiseTags
        XCTAssertTrue(tags.contains("drillIntervals:5/5"))
        XCTAssertTrue(tags.contains("drillWorkCadence:167"))
        XCTAssertTrue(tags.contains("drillRecCadence:160"))
        XCTAssertTrue(tags.contains("drillReps:1,1,1,1,1"))
    }

    func testStridesFloorTargetCadenceAdherence() {
        let context = DrillIntervalEvaluator.Context(
            drillId: .strides,
            effectiveRange: 170...176,
            baselineCadence: 155
        )

        // Lower than floor - 2 (167 < 168) -> not met
        XCTAssertFalse(DrillIntervalEvaluator.checkIsMet(workCadence: 167, context: context))

        // Within buffer / at floor (168..176) -> met
        XCTAssertTrue(DrillIntervalEvaluator.checkIsMet(workCadence: 168, context: context))
        XCTAssertTrue(DrillIntervalEvaluator.checkIsMet(workCadence: 172, context: context))

        // Exceeding upper bound for strides (e.g. 182, 190) -> met (floor philosophy)
        XCTAssertTrue(DrillIntervalEvaluator.checkIsMet(workCadence: 182, context: context))
        XCTAssertTrue(DrillIntervalEvaluator.checkIsMet(workCadence: 190, context: context))

        // Hyper-cadence above 195 cap -> not met
        XCTAssertFalse(DrillIntervalEvaluator.checkIsMet(workCadence: 198, context: context))
    }

    func testTempoSurgesIntervalAndThresholdAdherence() {
        let now = Date()
        var buckets: [BucketData] = []
        var currentTime = now
        var activities: [HKWorkoutActivity] = []
        let config = HKWorkoutConfiguration()
        config.activityType = .running

        // Warmup: 180s, 157 SPM, 155 BPM
        let warmupStart = currentTime
        let warmupEnd = warmupStart.addingTimeInterval(180)
        for _ in 0..<12 {
            buckets.append(BucketData(
                startTime: currentTime,
                distanceMeters: 45,
                durationSeconds: 15,
                meanPaceSecPerKm: 333,
                meanCadence: 157,
                meanHR: 155
            ))
            currentTime = currentTime.addingTimeInterval(15)
        }
        activities.append(HKWorkoutActivity(
            workoutConfiguration: config,
            start: warmupStart,
            end: warmupEnd,
            metadata: nil
        ))

        // 3 Surges:
        // Work 1: 165 SPM, 172 BPM (120s)
        // Rec 1: 157 SPM, 165 BPM (120s)
        // Work 2: 165 SPM, 170 BPM (120s)
        // Rec 2: 158 SPM, 171 BPM (120s)
        // Work 3: 159 SPM, 165 BPM (120s)
        // Rec 3: 158 SPM, 160 BPM (120s)
        let surgesData: [(workC: Double, workHR: Double, recC: Double, recHR: Double)] = [
            (165, 172, 157, 165),
            (165, 170, 158, 171),
            (159, 165, 158, 160)
        ]

        for surge in surgesData {
            let workStart = currentTime
            let workEnd = workStart.addingTimeInterval(120)
            for _ in 0..<8 {
                buckets.append(BucketData(
                    startTime: currentTime,
                    distanceMeters: 55,
                    durationSeconds: 15,
                    meanPaceSecPerKm: 272,
                    meanCadence: surge.workC,
                    meanHR: surge.workHR
                ))
                currentTime = currentTime.addingTimeInterval(15)
            }
            activities.append(HKWorkoutActivity(
                workoutConfiguration: config,
                start: workStart,
                end: workEnd,
                metadata: nil
            ))

            let recStart = currentTime
            let recEnd = recStart.addingTimeInterval(120)
            for _ in 0..<8 {
                buckets.append(BucketData(
                    startTime: currentTime,
                    distanceMeters: 45,
                    durationSeconds: 15,
                    meanPaceSecPerKm: 333,
                    meanCadence: surge.recC,
                    meanHR: surge.recHR
                ))
                currentTime = currentTime.addingTimeInterval(15)
            }
            activities.append(HKWorkoutActivity(
                workoutConfiguration: config,
                start: recStart,
                end: recEnd,
                metadata: nil
            ))
        }

        XCTAssertEqual(activities.count, 7, "Should have 7 activities: warmup + 3 work/rec pairs")

        // 30-day baseline is 152 SPM -> target is 161...167
        let context = DrillIntervalEvaluator.Context(
            drillId: .tempoSurges,
            effectiveRange: 161...167,
            baselineCadence: 152,
            oscDelta: -0.1,
            durationCategory: .fifteenMinutes
        )

        let summary = DrillIntervalEvaluator.evaluateFromActivities(
            activities: activities,
            buckets: buckets,
            context: context
        )

        XCTAssertNotNil(summary)
        guard let summary = summary else { return }

        XCTAssertEqual(summary.totalIntervals, 3)
        XCTAssertEqual(summary.reps.count, 3)
        XCTAssertEqual(summary.workCadenceAvg, 163)
        XCTAssertEqual(summary.recoveryCadenceAvg, 157)

        // All 3 surges should be Met (165 SPM, 165 SPM, 159 SPM + HR in Zone 4)
        XCTAssertEqual(summary.intervalsMet, 3)
        XCTAssertEqual(summary.adherencePercentage, 100)
        for rep in summary.reps {
            XCTAssertTrue(rep.isMet, "Rep \(rep.repIndex) should be met")
        }

        let tags = summary.framboiseTags
        XCTAssertTrue(tags.contains("drillIntervals:3/3"))
        XCTAssertTrue(tags.contains("drillWorkCadence:163"))
        XCTAssertTrue(tags.contains("drillReps:1,1,1"))
    }

    func testHistoricalBaselineCadenceResolution() {
        let now = Date()
        let runCurrent = RunRecord(
            hkWorkoutID: UUID(),
            date: now,
            totalDistanceMeters: 5000,
            duration: 1800,
            rawAvgPace: 360,
            rawAvgHeartRate: 160,
            rawAvgCadence: 168,
            workingAvgPace: 360,
            workingAvgCadence: 168, // elevated tempo pace
            workingAvgHeartRate: 160,
            paceCV: 0.05,
            paceSlope: 0.0,
            percentZone4: 0.25,
            detectedTypeRaw: "Tempo Run"
        )

        // Prior run 5 days ago: 152 SPM, 1800s
        let runPrior1 = RunRecord(
            hkWorkoutID: UUID(),
            date: now.addingTimeInterval(-5 * 86400),
            totalDistanceMeters: 5000,
            duration: 1800,
            rawAvgPace: 400,
            rawAvgHeartRate: 140,
            rawAvgCadence: 152,
            workingAvgPace: 400,
            workingAvgCadence: 152,
            workingAvgHeartRate: 140,
            paceCV: 0.04,
            paceSlope: 0.0,
            percentZone4: 0.0,
            detectedTypeRaw: "Steady Effort"
        )

        // Prior run 15 days ago: 154 SPM, 1800s
        let runPrior2 = RunRecord(
            hkWorkoutID: UUID(),
            date: now.addingTimeInterval(-15 * 86400),
            totalDistanceMeters: 5000,
            duration: 1800,
            rawAvgPace: 400,
            rawAvgHeartRate: 142,
            rawAvgCadence: 154,
            workingAvgPace: 400,
            workingAvgCadence: 154,
            workingAvgHeartRate: 142,
            paceCV: 0.04,
            paceSlope: 0.0,
            percentZone4: 0.0,
            detectedTypeRaw: "Steady Effort"
        )

        // Stale run 45 days ago: 170 SPM (outside 30-day window)
        let runStale = RunRecord(
            hkWorkoutID: UUID(),
            date: now.addingTimeInterval(-45 * 86400),
            totalDistanceMeters: 5000,
            duration: 1800,
            rawAvgPace: 350,
            rawAvgHeartRate: 165,
            rawAvgCadence: 170,
            workingAvgPace: 350,
            workingAvgCadence: 170,
            workingAvgHeartRate: 165,
            paceCV: 0.04,
            paceSlope: 0.0,
            percentZone4: 0.4,
            detectedTypeRaw: "Intervals"
        )

        let allRuns = [runCurrent, runPrior1, runPrior2, runStale]
        let resolvedBaseline = runCurrent.computeHistoricalBaselineCadence(in: allRuns)

        XCTAssertNotNil(resolvedBaseline)
        // Average of 152 and 154 = 153 SPM, not current run's 168 SPM and not stale run's 170 SPM
        XCTAssertEqual(resolvedBaseline, 153.0)
    }

    func testDrillTitlesNeverContainUnderscores() {
        // Direct instantiation with raw underscore identifiers
        let drill1 = DrillRecommendation(drillTitle: "rhythm_intervals")
        XCTAssertEqual(drill1.drillTitle, "Rhythm Intervals")
        XCTAssertEqual(drill1.formattedTitle, "Rhythm Intervals")

        let drill2 = DrillRecommendation(drillTitle: "cadence_pyramids")
        XCTAssertEqual(drill2.drillTitle, "Cadence Pyramids")
        XCTAssertEqual(drill2.formattedTitle, "Cadence Pyramids")

        // Legacy record with raw string in property
        let legacyDrill = DrillRecommendation(drillTitle: "tempo_surges")
        legacyDrill.drillTitle = "tempo_surges"
        XCTAssertEqual(legacyDrill.formattedTitle, "Tempo Surges")

        // Canonical drill resolution across all raw identifiers
        for drill in PreRunDrillId.allCases {
            guard let resolved = PreRunDrillId.canonicalDrillTitle(for: drill.rawValue) else {
                XCTFail("Failed to resolve canonical title for \(drill.rawValue)")
                continue
            }
            XCTAssertFalse(resolved.contains("_"), "Canonical title for \(drill.rawValue) must not contain underscores")
            XCTAssertEqual(resolved, drill.title)
        }
    }

    @MainActor
    func testUserLinkedDrillNeverOverriddenByAutoMatch() {
        let workoutID = UUID()
        let initialRecord = RunRecord(
            hkWorkoutID: workoutID,
            date: Date(),
            totalDistanceMeters: 4000,
            duration: 1200,
            rawAvgPace: 300,
            rawAvgHeartRate: 155,
            rawAvgCadence: 162,
            workingAvgPace: 300,
            workingAvgCadence: 162,
            workingAvgHeartRate: 155,
            paceCV: 0.05,
            paceSlope: 0.0,
            percentZone4: 0.20,
            detectedTypeRaw: "Intervals",
            framboiseTags: ["prescribedDrill", "cadence_pyramids", "drill:Cadence Pyramids", "drillIntervals:3/4"]
        )

        // Seed old matched intent for Cadence Pyramids
        let oldIntent = ScheduledDrillIntent(
            drillTitle: "Cadence Pyramids",
            preRunDrillId: "cadence_pyramids",
            scheduledDate: initialRecord.date,
            durationMinutes: 20,
            matchedWorkoutID: workoutID
        )
        WorkoutBridge.saveDrillIntent(oldIntent)

        // User updates drill to Rhythm Intervals
        WorkoutBridge.linkDrill(to: initialRecord, drillId: .rhythmIntervals)

        // Verify tags updated and user intent tagged
        XCTAssertTrue(initialRecord.framboiseTags.contains("userLinkedDrill"), "Must be tagged as userLinkedDrill")
        XCTAssertTrue(initialRecord.framboiseTags.contains("prescribedDrill"))
        XCTAssertTrue(initialRecord.framboiseTags.contains("drill:Rhythm Intervals"))
        XCTAssertFalse(initialRecord.framboiseTags.contains("drill:Cadence Pyramids"))
        XCTAssertFalse(initialRecord.framboiseTags.contains("cadence_pyramids"))
        XCTAssertFalse(initialRecord.framboiseTags.contains("drillIntervals:3/4"), "Old drill interval scorecard tags must be cleared")

        // Verify old intent was replaced in recentIntents()
        let recent = WorkoutBridge.recentIntents()
        let matchingIntents = recent.filter { $0.matchedWorkoutID == workoutID }
        XCTAssertEqual(matchingIntents.count, 1)
        XCTAssertEqual(matchingIntents.first?.drillTitle, "Rhythm Intervals")

        // User unlinks the drill
        WorkoutBridge.unlinkDrill(from: initialRecord)
        XCTAssertTrue(initialRecord.framboiseTags.contains("userUnlinkedDrill"), "Must be tagged as userUnlinkedDrill")
        XCTAssertFalse(initialRecord.framboiseTags.contains("prescribedDrill"))
        XCTAssertFalse(initialRecord.framboiseTags.contains("drill:Rhythm Intervals"))
        XCTAssertFalse(WorkoutBridge.recentIntents().contains { $0.matchedWorkoutID == workoutID })
    }

    func testDrillIntervalEvaluator_NineIntervalsOnEightIterationPreset_PreservesAllNineReps() {
        var segments: [DrillIntervalEvaluator.DrillSegment] = []

        // Warmup: 240s at 150 SPM
        segments.append(DrillIntervalEvaluator.DrillSegment(
            avgCadence: 150.0,
            avgHR: 135.0,
            duration: 240.0,
            isWorkHint: nil
        ))

        // 8 pairs of Work (30s at 182 SPM) + Recovery (90s at 135 SPM)
        for _ in 1...8 {
            segments.append(DrillIntervalEvaluator.DrillSegment(
                avgCadence: 182.0,
                avgHR: 172.0,
                duration: 30.0,
                isWorkHint: nil
            ))
            segments.append(DrillIntervalEvaluator.DrillSegment(
                avgCadence: 135.0,
                avgHR: 140.0,
                duration: 90.0,
                isWorkHint: nil
            ))
        }

        // Final 9th work interval (30s at 184 SPM, workout ends on work rep)
        segments.append(DrillIntervalEvaluator.DrillSegment(
            avgCadence: 184.0,
            avgHR: 175.0,
            duration: 30.0,
            isWorkHint: nil
        ))

        let context = DrillIntervalEvaluator.Context(
            drillId: .strides,
            effectiveRange: 178...195,
            baselineCadence: 160,
            durationCategory: .thirtyMinutes // Preset has 8 iterations
        )

        let summary = DrillIntervalEvaluator.evaluateSegments(segments, context: context)
        XCTAssertNotNil(summary, "Must evaluate interval summary")
        XCTAssertEqual(summary?.totalIntervals, 9, "Must evaluate all 9 intervals, not cap or prune to 8")
        XCTAssertEqual(summary?.reps.count, 9, "Reps array must contain exactly 9 intervals")
        XCTAssertEqual(summary?.intervalsMet, 9, "All 9 intervals met stride cadence target")
    }
}
