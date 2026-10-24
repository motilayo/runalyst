import XCTest
import SwiftData
@testable import Runalyst

final class IndoorIntelligenceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(true, forKey: "useMetricSystem")
    }

    private func makeTestRunRecord(isIndoor: Bool = false) -> RunRecord {
        RunRecord(
            hkWorkoutID: UUID(),
            date: Date(),
            totalDistanceMeters: 5000,
            duration: 1800,
            rawAvgPace: 360,
            rawAvgHeartRate: 150,
            rawAvgCadence: 165,
            workingAvgPace: 360,
            workingAvgCadence: 165,
            workingAvgHeartRate: 150,
            isIndoor: isIndoor,
            paceCV: 0.03,
            paceSlope: 0.0,
            percentZone4: 0.1,
            detectedTypeRaw: "Steady Effort"
        )
    }

    // MARK: - 1. ModelManager 75% Confidence Gate & Incline Inference

    func testMixedEffortGateWhenConfidenceBelow75Percent() async {
        let modelManager = ModelManager()
        let now = Date()
        var dummyBuckets: [BucketData] = []
        for i in 0..<10 {
            dummyBuckets.append(
                BucketData(
                    startTime: now.addingTimeInterval(Double(i * 30)),
                    distanceMeters: 100.0,
                    durationSeconds: 30.0,
                    meanPaceSecPerKm: 300.0,
                    meanCadence: 165.0,
                    meanHR: 150.0
                )
            )
        }

        let result = await modelManager.predictRunTypeResult(
            buckets: dummyBuckets,
            paceDelta: 10.0,
            hrDelta: 2.0,
            percentZone4: 0.18,
            cadenceDelta: 0.0,
            verticalOscillation: 9.5,
            runnerStage: 1,
            cv: 0.11,
            slope: -0.01,
            durationMinutes: 30.0,
            cadenceCV: 0.02,
            hrCV: 0.08,
            cadenceSlope: 0.0,
            isIndoor: true,
            isGymKit: false
        )

        XCTAssertNotNil(result.confidence)
        XCTAssertNotNil(result.probabilities)
        if result.confidence < 0.75 {
            XCTAssertEqual(result.targetClass, "Mixed Effort (Review)")
            XCTAssertTrue(result.isReviewRequired)
            XCTAssertEqual(result.provenance, .needsReview)
        } else {
            XCTAssertTrue(result.confidence >= 0.75)
            XCTAssertTrue(result.provenance == .inferred || result.provenance == .deterministic)
        }
    }

    func testBayesianDomainConditioning_IndoorExcludesOutdoorOnlyHypotheses() async {
        let modelManager = ModelManager()
        let now = Date()
        var dummyBuckets: [BucketData] = []
        for i in 0..<10 {
            dummyBuckets.append(
                BucketData(
                    startTime: now.addingTimeInterval(Double(i * 30)),
                    distanceMeters: 100.0,
                    durationSeconds: 30.0,
                    meanPaceSecPerKm: 300.0,
                    meanCadence: 165.0,
                    meanHR: 150.0
                )
            )
        }

        let result = await modelManager.predictRunTypeResult(
            buckets: dummyBuckets,
            paceDelta: 10.0,
            hrDelta: 2.0,
            percentZone4: 0.18,
            cadenceDelta: 0.0,
            verticalOscillation: 9.5,
            runnerStage: 1,
            cv: 0.11,
            slope: -0.01,
            durationMinutes: 30.0,
            cadenceCV: 0.02,
            hrCV: 0.08,
            cadenceSlope: 0.0,
            isIndoor: true,
            isGymKit: false
        )

        // Bayesian Domain Conditioning Axiom: P(Urban Traffic | Indoor) = 0 and P(Hill Repeats | Indoor) = 0
        XCTAssertNil(result.probabilities["Urban Traffic"], "Indoor probability space must strictly exclude Urban Traffic")
        XCTAssertNil(result.probabilities["Hill Repeats"], "Indoor probability space must strictly exclude Hill Repeats")
    }

    func testDeterministicSequenceGrammar_AssignsDeterministicProvenanceAndConfidence() async {
        let modelManager = ModelManager()
        var buckets: [BucketData] = []
        var currentTime = Date()

        // 4 crisp interval cycles with +100s contrast
        for _ in 0..<4 {
            for _ in 0..<2 {
                buckets.append(BucketData(startTime: currentTime, distanceMeters: 100, durationSeconds: 30, meanPaceSecPerKm: 300, meanCadence: 180, meanHR: 170))
                currentTime = currentTime.addingTimeInterval(30)
            }
            for _ in 0..<2 {
                buckets.append(BucketData(startTime: currentTime, distanceMeters: 60, durationSeconds: 30, meanPaceSecPerKm: 500, meanCadence: 140, meanHR: 135))
                currentTime = currentTime.addingTimeInterval(30)
            }
        }

        let result = await modelManager.predictRunTypeResult(
            buckets: buckets,
            paceDelta: 0.0,
            hrDelta: 0.0,
            percentZone4: 0.40,
            cadenceDelta: 0.0,
            verticalOscillation: 9.5,
            runnerStage: 1,
            cv: 0.14,
            slope: 0.0,
            durationMinutes: 20.0,
            cadenceCV: 0.05,
            hrCV: 0.08,
            cadenceSlope: 0.0,
            isIndoor: true,
            isGymKit: false
        )

        XCTAssertEqual(result.targetClass, "Intervals")
        XCTAssertEqual(result.provenance, .deterministic, "3+ sequence grammar cycles must establish .deterministic provenance")
        XCTAssertEqual(result.confidence, 1.0, "Deterministic grammar proof carries 1.0 confidence")
        XCTAssertFalse(result.isReviewRequired, "Deterministic grammar proof must never require review")
    }

    func testFiniteStateMachine_UserConfirmedStateIsAbsorbingAndDismissesBanner() {
        let run = RunRecord(
            hkWorkoutID: UUID(),
            date: Date(),
            totalDistanceMeters: 5000,
            duration: 1800,
            rawAvgPace: 360,
            rawAvgHeartRate: 150,
            rawAvgCadence: 160,
            workingAvgPace: 360,
            workingAvgCadence: 160,
            workingAvgHeartRate: 150,
            paceCV: 0.12,
            paceSlope: 0.0,
            percentZone4: 0.1,
            detectedTypeRaw: "Mixed Effort (Review)",
            classificationConfidence: 0.54,
            classificationProvenanceRaw: ClassificationProvenance.needsReview.rawValue
        )

        // 1. Initial .needsReview state
        XCTAssertTrue(run.needsClassificationReview, "Run in .needsReview must flag needsClassificationReview = true")

        // 2. Transition delta(.needsReview, userSelect) -> .userConfirmed
        run.classificationProvenance = .userConfirmed
        run.classificationConfidence = 1.0
        run.detectedTypeRaw = "Fartlek"

        // 3. Absorbing state verification
        XCTAssertFalse(run.needsClassificationReview, "User-confirmed state is absorbing and must dismiss review banner")

        // 4. Deterministic state verification
        run.classificationProvenance = .deterministic
        XCTAssertFalse(run.needsClassificationReview, "Deterministic provenance must never require classification review")
    }

    func testInclineInferenceFlaggingOnIndoorWorkout() {
        // High HR CV with flat pace (low CV) and decaying cadence on indoor belt
        let flagged = ModelManager.shouldFlagForInclineReview(
            isIndoor: true,
            isGymKit: false,
            hrCV: 0.12,
            cv: 0.02,
            cadenceSlope: -0.01
        )
        XCTAssertTrue(flagged, "Expected indoor workout with flat pace and high HR strain to flag incline review")

        // Outdoor runs should never trigger indoor incline inference
        let outdoorFlagged = ModelManager.shouldFlagForInclineReview(
            isIndoor: false,
            isGymKit: false,
            hrCV: 0.12,
            cv: 0.02,
            cadenceSlope: -0.01
        )
        XCTAssertFalse(outdoorFlagged, "Outdoor workouts should not flag indoor incline review")

        // GymKit runs have authentic incline and do not need heuristic review
        let gymKitFlagged = ModelManager.shouldFlagForInclineReview(
            isIndoor: true,
            isGymKit: true,
            hrCV: 0.12,
            cv: 0.02,
            cadenceSlope: -0.01
        )
        XCTAssertFalse(gymKitFlagged, "GymKit workouts should not flag heuristic incline review")
    }

    // MARK: - 2. Mathematical Smoothing Heuristics

    func testIndoorWristPaceSmoothingClampsExtremeNoise() async {
        let engine = FramboiseEngine()
        let now = Date()
        let rawBuckets = [
            BucketData(startTime: now, distanceMeters: 100, durationSeconds: 30, meanPaceSecPerKm: 300, meanCadence: 165, meanHR: 150),
            BucketData(startTime: now.addingTimeInterval(30), distanceMeters: 100, durationSeconds: 30, meanPaceSecPerKm: 302, meanCadence: 165, meanHR: 150),
            BucketData(startTime: now.addingTimeInterval(60), distanceMeters: 100, durationSeconds: 30, meanPaceSecPerKm: 298, meanCadence: 165, meanHR: 150),
            BucketData(startTime: now.addingTimeInterval(90), distanceMeters: 100, durationSeconds: 30, meanPaceSecPerKm: 600, meanCadence: 165, meanHR: 150), // wild spike
            BucketData(startTime: now.addingTimeInterval(120), distanceMeters: 100, durationSeconds: 30, meanPaceSecPerKm: 301, meanCadence: 165, meanHR: 150),
            BucketData(startTime: now.addingTimeInterval(150), distanceMeters: 100, durationSeconds: 30, meanPaceSecPerKm: 299, meanCadence: 165, meanHR: 150)
        ]
        let smoothed = await engine.applyIndoorWristPaceSmoothing(buckets: rawBuckets)

        XCTAssertEqual(smoothed.count, rawBuckets.count)
        // The 600.0 spike should be clamped to within 25% of the overall median (~300.5 * 1.25 = ~375)
        XCTAssertLessThan(smoothed[3].meanPaceSecPerKm, 450.0, "Extreme wrist artifact should be damped")
    }

    func testHRCVCalculation() async {
        let engine = FramboiseEngine()
        let hrSamples = [140.0, 142.0, 145.0, 141.0, 139.0]
        let cv = await engine.calculateHRCV(bucketHRs: hrSamples)
        XCTAssertGreaterThan(cv, 0.0)
        XCTAssertLessThan(cv, 0.10)

        let emptyCV = await engine.calculateHRCV(bucketHRs: [])
        XCTAssertEqual(emptyCV, 0.0)
    }

    func testCadenceSlopeCalculation() async {
        let engine = FramboiseEngine()
        // Accelerating cadence
        let cadenceSamples = [160.0, 162.0, 164.0, 166.0, 168.0]
        let slope = await engine.calculateCadenceSlope(bucketCadences: cadenceSamples)
        XCTAssertGreaterThan(slope, 0.0, "Ascending cadence should yield positive slope")

        let flatSlope = await engine.calculateCadenceSlope(bucketCadences: [160.0, 160.0, 160.0])
        XCTAssertEqual(flatSlope, 0.0, accuracy: 0.001)
    }

    // MARK: - 3. Telemetry Highlighter

    func testTelemetryHighlighterAttributesNumbersAndUnits() {
        let text = "Target cadence is 165 SPM with heart rate around 142 BPM."
        let attributed = TelemetryHighlighter.highlight(text)

        XCTAssertFalse(attributed.characters.isEmpty)
        XCTAssertEqual(String(attributed.characters), text)
    }

    func testTelemetryHighlighterRendersMarkdownRichText() {
        let markdown = """
        ### Split Analysis
        Here is your breakdown:
        - **km 1** (5:25/km, 161 SPM, 140 BPM): *slowest split*, pacing eased back
        - **km 2** (4:30/km, 174 SPM, 168 BPM): *fastest split* with sharp pace control
        """

        let attributed = TelemetryHighlighter.highlight(markdown)
        let plainCharacters = String(attributed.characters)

        // Raw markdown syntax characters must not leak into characters
        XCTAssertFalse(plainCharacters.contains("###"), "Headers must not contain raw ### characters")
        XCTAssertFalse(plainCharacters.contains("**km"), "Bold markup must not contain raw ** characters")
        XCTAssertFalse(plainCharacters.contains("- km"), "Dashes must be converted to clean bullets")

        // Clean rich text characters must be present
        XCTAssertTrue(plainCharacters.contains("Split Analysis"), "Header title must be preserved")
        XCTAssertTrue(plainCharacters.contains("• km 1"), "Bullet must be converted to •")
        XCTAssertTrue(plainCharacters.contains("• km 2"), "Bullet must be converted to •")
        XCTAssertTrue(plainCharacters.contains("slowest split"), "Italic text must be preserved")

        // Verify rich text presentation intents and styling runs
        var foundBoldRun = false
        var foundItalicRun = false
        var foundAccentTelemetryRun = false

        for run in attributed.runs {
            if run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
                foundBoldRun = true
            }
            if run.inlinePresentationIntent?.contains(.emphasized) == true {
                foundItalicRun = true
            }
            if run.foregroundColor != nil {
                foundAccentTelemetryRun = true
            }
        }

        XCTAssertTrue(foundBoldRun, "Should have strongly emphasized (bold) rich text runs")
        XCTAssertTrue(foundItalicRun, "Should have emphasized (italic) rich text runs")
        XCTAssertTrue(foundAccentTelemetryRun, "Should have styled telemetry citation runs")
    }

    func testTelemetryHighlighterSanitizesLatexToUnicode() {
        let latexText = "Your $\\text{VO}_2\\text{max}$ estimate improved, with pace steady at $5 \\times 1000m$ repeats (approx $\\approx$ 4:30/km)."
        let attributed = TelemetryHighlighter.highlight(latexText)
        let plainCharacters = String(attributed.characters)

        XCTAssertFalse(plainCharacters.contains("\\text{VO}"), "LaTeX text macros must be converted")
        XCTAssertFalse(plainCharacters.contains("\\times"), "LaTeX times must be converted")
        XCTAssertFalse(plainCharacters.contains("\\approx"), "LaTeX approx must be converted")
        XCTAssertFalse(plainCharacters.contains("$"), "Math dollar delimiters must be stripped")

        XCTAssertTrue(plainCharacters.contains("VO2 Max"), "VO2 Max should be clean unicode")
        XCTAssertTrue(plainCharacters.contains("×"), "Times symbol should be clean unicode")
        XCTAssertTrue(plainCharacters.contains("≈"), "Approx symbol should be clean unicode")
    }

    // MARK: - 4. Analyst Chat Guardrails

    @MainActor
    func testRunnerProfileHeightCalibrationAndLoad() {
        let tallProfile = RunnerProfile(
            experienceLevel: "Advanced / Veteran",
            trainingGoal: "5K Race",
            userHeightCm: 195.0,
            current30DayDistanceKm: 60.0,
            weeklyAverageKm: 14.0,
            runsPerWeek: 3.5
        )
        // 195 cm runner has longer limbs; cadence floor must be lower than 150
        XCTAssertLessThan(tallProfile.heightAdjustedCadenceFloor, 150)
        XCTAssertEqual(tallProfile.heightAdjustedCadenceFloor, 135)

        let shortProfile = RunnerProfile(
            experienceLevel: "Novice / Beginner",
            trainingGoal: "Base Building",
            userHeightCm: 155.0,
            current30DayDistanceKm: 40.0,
            weeklyAverageKm: 9.3,
            runsPerWeek: 2.0
        )
        // 155 cm runner has shorter limbs; cadence floor must be higher than 150
        XCTAssertGreaterThan(shortProfile.heightAdjustedCadenceFloor, 150)
        XCTAssertEqual(shortProfile.heightAdjustedCadenceFloor, 169)

        let standardProfile = RunnerProfile(
            experienceLevel: "Intermediate / Enthusiast",
            trainingGoal: "Half Marathon",
            userHeightCm: 175.0,
            current30DayDistanceKm: 100.0,
            weeklyAverageKm: 23.3,
            runsPerWeek: 3.0
        )
        XCTAssertEqual(standardProfile.heightAdjustedCadenceFloor, 150)
    }

    @MainActor
    func testRunnerProfileExperienceLevel_AutoAdjustmentTiers() {
        let now = Date()

        // 1. Cold start (0 runs) -> Novice / Beginner
        let coldStartLevel = RunnerProfile.calculateExperienceLevel(from: [], now: now)
        XCTAssertEqual(coldStartLevel, "Novice / Beginner")

        // 2. Novice runner: 3 runs of 3 km
        let noviceRuns = (1...3).map { i -> RunRecord in
            let r = makeTestRunRecord()
            r.date = now.addingTimeInterval(Double(-i * 3 * 86400))
            r.totalDistanceMeters = 3000
            r.duration = 1200
            r.workingAvgPace = 400
            return r
        }
        let noviceLevel = RunnerProfile.calculateExperienceLevel(from: noviceRuns, now: now)
        XCTAssertEqual(noviceLevel, "Novice / Beginner")

        // 3. Intermediate runner: 10 runs, 5-8 km each, total ~25 km/wk
        let intermediateRuns = (1...10).map { i -> RunRecord in
            let r = makeTestRunRecord()
            r.date = now.addingTimeInterval(Double(-i * 2 * 86400))
            r.totalDistanceMeters = i == 1 ? 8000 : 5000
            r.duration = TimeInterval(r.totalDistanceMeters / 1000 * 330)
            r.workingAvgPace = 330
            return r
        }
        let intermediateLevel = RunnerProfile.calculateExperienceLevel(from: intermediateRuns, now: now)
        XCTAssertEqual(intermediateLevel, "Intermediate / Enthusiast")

        // 4. Advanced runner: 16 runs, 38 km/wk, longest run 16 km
        let advancedRuns = (1...16).map { i -> RunRecord in
            let r = makeTestRunRecord()
            r.date = now.addingTimeInterval(-Double(i) * 86400.0 * 1.8)
            r.totalDistanceMeters = i == 1 ? 16000 : 7500
            r.duration = TimeInterval(r.totalDistanceMeters / 1000.0 * 290.0)
            r.workingAvgPace = 290
            return r
        }
        let advancedLevel = RunnerProfile.calculateExperienceLevel(from: advancedRuns, now: now)
        XCTAssertEqual(advancedLevel, "Advanced / Veteran")

        // 5. Elite runner: 25 runs, 70 km/wk, longest run 22 km, fast pace
        let eliteRuns = (1...25).map { i -> RunRecord in
            let r = makeTestRunRecord()
            r.date = now.addingTimeInterval(-Double(i) * 86400.0 * 1.1)
            r.totalDistanceMeters = i == 1 ? 22000 : 11000
            r.duration = TimeInterval(r.totalDistanceMeters / 1000.0 * 240.0)
            r.workingAvgPace = 240
            return r
        }
        let eliteLevel = RunnerProfile.calculateExperienceLevel(from: eliteRuns, now: now)
        XCTAssertEqual(eliteLevel, "Competitive / Elite")

        // 6. Profile compute auto-adjusts vs respects manual override
        let autoProfile = RunnerProfile.compute(from: intermediateRuns, now: now)
        XCTAssertEqual(autoProfile.experienceLevel, "Intermediate / Enthusiast")
        XCTAssertTrue(autoProfile.isAutoCalculated)

        let overrideProfile = RunnerProfile.compute(from: intermediateRuns, experienceLevel: "Competitive / Elite", now: now)
        XCTAssertEqual(overrideProfile.experienceLevel, "Competitive / Elite")
        XCTAssertFalse(overrideProfile.isAutoCalculated)
    }

    @MainActor
    func testWorkoutAnalysisContextHeightCalibratedArchetypeAndIndoorFallback() {
        // Outdoor run with vertical oscillation and stride length
        let outdoorRun = makeTestRunRecord(isIndoor: false)
        outdoorRun.workingAvgCadence = 146
        outdoorRun.workingAvgVerticalOscillation = 10.4
        outdoorRun.workingAvgStrideLength = 1.15

        let analysisOutdoor = WorkoutAnalysisContext(
            runRecord: outdoorRun,
            runSignature: nil,
            macroProfile: nil,
            recoveryTimeline: RecoveryTimeline.build(runs: [], readiness: .productive, now: Date()),
            runnerProfile: RunnerProfile(
                experienceLevel: "Intermediate / Enthusiast",
                trainingGoal: "Base Building",
                userHeightCm: 175.0,
                current30DayDistanceKm: 40.0,
                weeklyAverageKm: 9.3,
                runsPerWeek: 2.5
            )
        )
        XCTAssertTrue(
            analysisOutdoor.strideArchetype.contains("High-Bounce Overstrider"),
            "146 cadence with 10.4cm bounce at 175cm should classify as High-Bounce Overstrider: \(analysisOutdoor.strideArchetype)"
        )

        // Indoor treadmill run without vertical oscillation (watchOS indoor limitation)
        let indoorRun = makeTestRunRecord(isIndoor: true)
        indoorRun.workingAvgCadence = 168
        indoorRun.workingAvgVerticalOscillation = nil
        indoorRun.workingAvgStrideLength = nil

        let analysisIndoor = WorkoutAnalysisContext(
            runRecord: indoorRun,
            runSignature: nil,
            macroProfile: nil,
            recoveryTimeline: RecoveryTimeline.build(runs: [], readiness: .productive, now: Date()),
            runnerProfile: RunnerProfile(
                experienceLevel: "Advanced / Veteran",
                trainingGoal: "5K Race",
                userHeightCm: 175.0,
                current30DayDistanceKm: 80.0,
                weeklyAverageKm: 18.6,
                runsPerWeek: 4.0
            )
        )
        XCTAssertTrue(
            analysisIndoor.strideArchetype.contains("Treadmill"),
            "Indoor treadmill run must use 2D indoor fallback without nil collapse: \(analysisIndoor.strideArchetype)"
        )
    }

    @MainActor
    func testWorkoutAnalysisContextEnvironmentalModifierHighElevation() {
        let runRecord = makeTestRunRecord(isIndoor: false)
        let split = RunSplit(
            index: 1,
            distanceMeters: 1000,
            durationSeconds: 300,
            paceSecondsPerKm: 300,
            avgHeartRate: 155,
            avgCadence: 160,
            elevationGainMeters: 65.0
        )
        let signature = RunSignature(
            classification: "Steady Effort",
            confidence: 0.90,
            probabilities: ["Steady Effort": 0.90],
            anomalies: [],
            cadenceFloor: 150.0,
            phaseSegments: [],
            dataSource: "wrist",
            isIndoor: false,
            needsInclineReview: false,
            splits: [split]
        )

        let analysis = WorkoutAnalysisContext(
            runRecord: runRecord,
            runSignature: signature,
            macroProfile: nil,
            recoveryTimeline: RecoveryTimeline.build(runs: [], readiness: .productive, now: Date())
        )
        XCTAssertNotNil(analysis.environmentModifier)
        XCTAssertTrue(
            analysis.environmentModifier?.contains("High Elevation Gain (+65 m)") == true,
            "Must tag high elevation gain: \(String(describing: analysis.environmentModifier))"
        )
    }

    @MainActor
    func testWorkoutAnalysisContextEnvironmentalModifierHighHeat() {
        let runRecord = makeTestRunRecord(isIndoor: false)
        runRecord.ambientTemperatureCelsius = 24.5
        runRecord.ambientHumidity = 80.0

        let analysis = WorkoutAnalysisContext(
            runRecord: runRecord,
            runSignature: nil,
            macroProfile: nil,
            recoveryTimeline: RecoveryTimeline.build(runs: [], readiness: .productive, now: Date())
        )
        XCTAssertEqual(analysis.environmentalModifier, .highHeat)
        XCTAssertNotNil(analysis.environmentModifier)
        XCTAssertTrue(analysis.environmentModifier?.contains("High Heat & Humidity") == true)
    }

    @MainActor
    func testGetReadinessAndWorkloadToolDistressOverride() async throws {
        let runRecord = makeTestRunRecord(isIndoor: false)
        let chatEngine = AnalystChatEngine(runRecord: runRecord)

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let session = chatEngine.getOrCreateSession()
            XCTAssertNotNil(session)

            // Test readiness query returns valid physical telemetry
            let query = GetReadinessAndWorkloadQuery()
            let tool = GetReadinessAndWorkloadTool { _ in
                "{\"readiness_state\":\"productive\",\"second_run_advisable\":true,\"workload_zone\":\"optimal\"}"
            }
            let result = try await tool.call(arguments: query)
            XCTAssertTrue(result.contains("productive"))
            XCTAssertTrue(result.contains("second_run_advisable"))
            XCTAssertTrue(result.contains("optimal"))
        }
        #endif
    }

    // MARK: - 4B. Swift Physics, Zones & Memory Engines

    func testPhysiologicalDiagnosisEngineVeracityAndSeverity() {
        // 1. Cadence late fatigue with critical severity
        let s1 = RunSplit(index: 1, distanceMeters: 1000, durationSeconds: 300, paceSecondsPerKm: 300, avgHeartRate: 145, avgCadence: 168, elevationGainMeters: 5)
        let s2 = RunSplit(index: 2, distanceMeters: 1000, durationSeconds: 300, paceSecondsPerKm: 300, avgHeartRate: 150, avgCadence: 166, elevationGainMeters: 5)
        let s3 = RunSplit(index: 3, distanceMeters: 1000, durationSeconds: 320, paceSecondsPerKm: 320, avgHeartRate: 155, avgCadence: 154, elevationGainMeters: 5)
        let s4 = RunSplit(index: 4, distanceMeters: 1000, durationSeconds: 325, paceSecondsPerKm: 325, avgHeartRate: 158, avgCadence: 152, elevationGainMeters: 5)

        let inputFatigue = PhysiologicalInput(
            workingCadence: 160,
            heightAdjustedCadenceFloor: 150,
            splits: [s1, s2, s3, s4],
            elevationGainMeters: 20.0,
            hasCardiacDrift: true,
            cardiacDriftMagnitudeBPM: 11,
            durationSeconds: 1245,
            verticalRatio: 9.4,
            verticalOscillationCM: 10.2,
            isIndoor: false,
            firstHalfPaceSec: 300,
            secondHalfPaceSec: 322.5,
            fastestSplit: s1,
            slowestSplit: s4,
            avgHeartRate: 152
        )
        let verdictsFatigue = PhysiologicalDiagnosisEngine.evaluate(inputFatigue)

        if case .lateNeuromuscularFatigue(let decay, let pace, let severity) = verdictsFatigue.cadence {
            XCTAssertGreaterThanOrEqual(decay, 10)
            XCTAssertGreaterThanOrEqual(pace, 15)
            XCTAssertEqual(severity, .critical)
        } else {
            XCTFail("Must diagnose late neuromuscular fatigue: \(verdictsFatigue.cadence)")
        }

        if case .pacingOvershootDecoupling(let paceDelta, let drift, let severity) = verdictsFatigue.cardiac {
            XCTAssertEqual(paceDelta, 23)
            XCTAssertEqual(drift, 11)
            XCTAssertEqual(severity, .moderate)
        } else {
            XCTFail("Must diagnose pacing overshoot decoupling: \(verdictsFatigue.cardiac)")
        }

        // Pure thermal drift with steady pace
        let inputThermal = PhysiologicalInput(
            workingCadence: 165,
            heightAdjustedCadenceFloor: 150,
            splits: [s1, s2],
            elevationGainMeters: 5.0,
            hasCardiacDrift: true,
            cardiacDriftMagnitudeBPM: 11,
            durationSeconds: 1800,
            verticalRatio: 7.5,
            verticalOscillationCM: 8.0,
            isIndoor: false,
            firstHalfPaceSec: 300,
            secondHalfPaceSec: 302,
            fastestSplit: s1,
            slowestSplit: s2,
            avgHeartRate: 150
        )
        let verdictsThermal = PhysiologicalDiagnosisEngine.evaluate(inputThermal)
        if case .thermalOrCardiovascularDrift(let drift, _, let severity) = verdictsThermal.cardiac {
            XCTAssertEqual(drift, 11)
            XCTAssertEqual(severity, .moderate)
        } else {
            XCTFail("Must diagnose thermal/cardiac drift: \(verdictsThermal.cardiac)")
        }

        if case .excessiveVerticalDisplacement(let vr, let bounce, let severity) = verdictsFatigue.verticalEconomy {
            XCTAssertEqual(vr, 9.4)
            XCTAssertEqual(bounce, 10.2)
            XCTAssertEqual(severity, .moderate)
        } else {
            XCTFail("Must diagnose excessive vertical displacement: \(verdictsFatigue.verticalEconomy)")
        }

        // 2. Grade resistance on hill climb
        let inputHill = PhysiologicalInput(
            workingCadence: 155,
            heightAdjustedCadenceFloor: 150,
            splits: [s1, s2, s3, s4],
            elevationGainMeters: 55.0,
            hasCardiacDrift: true,
            cardiacDriftMagnitudeBPM: 14,
            durationSeconds: 1245,
            verticalRatio: 7.2,
            verticalOscillationCM: 8.0,
            isIndoor: false,
            firstHalfPaceSec: 300,
            secondHalfPaceSec: 322.5,
            fastestSplit: s1,
            slowestSplit: s4,
            avgHeartRate: 152
        )
        let verdictsHill = PhysiologicalDiagnosisEngine.evaluate(inputHill)
        if case .gradeResistance(let drop, let elev, let severity) = verdictsHill.cadence {
            XCTAssertGreaterThanOrEqual(drop, 10)
            XCTAssertEqual(elev, 55.0)
            XCTAssertEqual(severity, .critical)
        } else {
            XCTFail("Must diagnose grade resistance on hills: \(verdictsHill.cadence)")
        }
        if case .elevationInducedCardiacSurge(let elev, let rise, let severity) = verdictsHill.cardiac {
            XCTAssertEqual(elev, 55.0)
            XCTAssertEqual(rise, 14)
            XCTAssertEqual(severity, .critical)
        } else {
            XCTFail("Must diagnose elevation-induced cardiac surge: \(verdictsHill.cardiac)")
        }

        // 3. Treadmill kinematics
        let inputTreadmill = PhysiologicalInput(
            workingCadence: 168,
            heightAdjustedCadenceFloor: 150,
            splits: [],
            elevationGainMeters: 0,
            hasCardiacDrift: false,
            cardiacDriftMagnitudeBPM: 0,
            durationSeconds: 1800,
            verticalRatio: nil,
            verticalOscillationCM: nil,
            isIndoor: true,
            firstHalfPaceSec: 300,
            secondHalfPaceSec: 300,
            fastestSplit: nil,
            slowestSplit: nil,
            avgHeartRate: 142
        )
        let verdictsTreadmill = PhysiologicalDiagnosisEngine.evaluate(inputTreadmill)
        if case .treadmillDeckKinematics(let cad) = verdictsTreadmill.verticalEconomy {
            XCTAssertEqual(cad, 168)
        } else {
            XCTFail("Must use treadmill deck kinematics: \(verdictsTreadmill.verticalEconomy)")
        }
    }

    func testPhysiologicalDiagnosisEngineIndoorThermalProxyNoConvectiveCooling() {
        let s1 = RunSplit(index: 1, distanceMeters: 1000, durationSeconds: 300, paceSecondsPerKm: 300, avgHeartRate: 145, avgCadence: 165, elevationGainMeters: 0)
        let s2 = RunSplit(index: 2, distanceMeters: 1000, durationSeconds: 300, paceSecondsPerKm: 301, avgHeartRate: 156, avgCadence: 165, elevationGainMeters: 0)

        // Indoor treadmill run: flat deck, no convective wind cooling, flat pace with +11 BPM HR drift over 30 min
        let inputIndoor = PhysiologicalInput(
            workingCadence: 165,
            heightAdjustedCadenceFloor: 150,
            splits: [s1, s2],
            elevationGainMeters: 0,
            hasCardiacDrift: true,
            cardiacDriftMagnitudeBPM: 11,
            durationSeconds: 1800,
            verticalRatio: nil,
            verticalOscillationCM: nil,
            isIndoor: true,
            firstHalfPaceSec: 300,
            secondHalfPaceSec: 301,
            fastestSplit: s1,
            slowestSplit: s2,
            avgHeartRate: 150,
            environmentalModifier: .indoorTreadmill
        )
        let verdicts = PhysiologicalDiagnosisEngine.evaluate(inputIndoor)
        if case .thermalOrCardiovascularDrift(let drift, let dur, let severity) = verdicts.cardiac {
            XCTAssertEqual(drift, 11)
            XCTAssertEqual(dur, 15, "Drift duration must be the second-half duration (15 min for 30 min run)")
            XCTAssertEqual(severity, .moderate)
        } else {
            XCTFail("Must diagnose thermal/cardiovascular drift on indoor run: \(verdicts.cardiac)")
        }
    }

    func testPhysiologicalDiagnosisEngineOutdoorWeatherKitThermalProxyHighHeat() {
        let s1 = RunSplit(index: 1, distanceMeters: 1000, durationSeconds: 300, paceSecondsPerKm: 300, avgHeartRate: 148, avgCadence: 165, elevationGainMeters: 5)
        let s2 = RunSplit(index: 2, distanceMeters: 1000, durationSeconds: 300, paceSecondsPerKm: 302, avgHeartRate: 162, avgCadence: 165, elevationGainMeters: 5)

        // Outdoor run with WeatherKit high heat (24°C, 80% humidity) and +14 BPM drift
        let inputOutdoorHeat = PhysiologicalInput(
            workingCadence: 165,
            heightAdjustedCadenceFloor: 150,
            splits: [s1, s2],
            elevationGainMeters: 10,
            hasCardiacDrift: true,
            cardiacDriftMagnitudeBPM: 14,
            durationSeconds: 1800,
            verticalRatio: 7.5,
            verticalOscillationCM: 8.0,
            isIndoor: false,
            firstHalfPaceSec: 300,
            secondHalfPaceSec: 302,
            fastestSplit: s1,
            slowestSplit: s2,
            avgHeartRate: 155,
            ambientTemperatureC: 24.0,
            ambientHumidity: 80.0,
            environmentalModifier: .highHeat
        )
        let verdicts = PhysiologicalDiagnosisEngine.evaluate(inputOutdoorHeat)
        XCTAssertEqual(verdicts.cardiac, .thermalStrain(HeatIndex: "High"))
    }

    func testWeatherProxyEngineThresholdsAndModifierEvaluation() {
        // Temperature >= 22°C (72°F)
        XCTAssertTrue(WeatherProxyEngine.isHighHeat(temperatureCelsius: 22.0, humidity: 40.0))
        XCTAssertTrue(WeatherProxyEngine.isHighHeat(temperatureCelsius: 25.0, humidity: 50.0))

        // Humidity >= 75%
        XCTAssertTrue(WeatherProxyEngine.isHighHeat(temperatureCelsius: 20.0, humidity: 75.0))
        XCTAssertTrue(WeatherProxyEngine.isHighHeat(temperatureCelsius: 20.0, humidity: 0.75))

        // Normal ambient
        XCTAssertFalse(WeatherProxyEngine.isHighHeat(temperatureCelsius: 18.0, humidity: 50.0))
        XCTAssertFalse(WeatherProxyEngine.isHighHeat(temperatureCelsius: nil, humidity: nil))

        // Modifier evaluation
        XCTAssertEqual(WeatherProxyEngine.evaluateEnvironmentalModifier(temperatureCelsius: 24.0, humidity: 80.0, isIndoor: false, elevationGainMeters: 10), .highHeat)
        XCTAssertEqual(WeatherProxyEngine.evaluateEnvironmentalModifier(temperatureCelsius: 24.0, humidity: 80.0, isIndoor: true, elevationGainMeters: 10), .indoorTreadmill)
        XCTAssertEqual(WeatherProxyEngine.evaluateEnvironmentalModifier(temperatureCelsius: 18.0, humidity: 50.0, isIndoor: false, elevationGainMeters: 45), .highElevation)
        XCTAssertEqual(WeatherProxyEngine.evaluateEnvironmentalModifier(temperatureCelsius: 18.0, humidity: 50.0, isIndoor: false, elevationGainMeters: 10), .standard)
    }

    @MainActor
    func testTrainingZoneEngineColdStartAndSubjectiveOverride() {
        // 1. Empirical baseline Zone 1-5 calculation
        let inputEmpirical = TrainingZoneInput(
            baselinePaceSec: 300.0, // 5:00/km
            workoutPaceSec: 295.0,
            activeGoal: "5K Race",
            experienceLevel: "Intermediate / Enthusiast",
            readyForHard: true,
            daysSinceWorkout: 2,
            heightAdjustedCadenceFloor: 150,
            useMetricSystem: true,
            isSubjectiveDistress: false,
            totalHistoricalRunsCount: 10
        )
        let rxEmpirical = TrainingZoneEngine.computePrescription(inputEmpirical)
        XCTAssertFalse(rxEmpirical.isColdStart)
        XCTAssertFalse(rxEmpirical.isSubjectiveOverride)
        XCTAssertTrue(rxEmpirical.nextSessionName.contains("5K") || rxEmpirical.nextSessionName.contains("Zone 2"))
        XCTAssertTrue(rxEmpirical.zone1RecoveryPace.contains("6:00–6:30/km"))
        XCTAssertTrue(rxEmpirical.zone2AerobicBasePace.contains("5:30–5:50/km"))
        XCTAssertTrue(rxEmpirical.zone4ThresholdPace.contains("4:50–5:05/km"))
        XCTAssertTrue(rxEmpirical.zone5IntervalPace.contains("4:30–4:40/km"))

        // 2. Subjective physical distress override
        let inputDistress = TrainingZoneInput(
            baselinePaceSec: 300.0,
            workoutPaceSec: 295.0,
            activeGoal: "5K Race",
            experienceLevel: "Intermediate / Enthusiast",
            readyForHard: true,
            daysSinceWorkout: 2,
            heightAdjustedCadenceFloor: 150,
            useMetricSystem: true,
            isSubjectiveDistress: true,
            totalHistoricalRunsCount: 10
        )
        let rxDistress = TrainingZoneEngine.computePrescription(inputDistress)
        XCTAssertTrue(rxDistress.isSubjectiveOverride)
        XCTAssertTrue(rxDistress.nextSessionName.contains("Full Rest & Recovery"))
        XCTAssertEqual(rxDistress.prescribedDurationBand, "0 minutes (Full Rest Day)")
        XCTAssertEqual(rxDistress.prescribedPaceBand, "N/A")

        // 3. Novice zero-day cold start assessment
        TrainingZoneEngine.hasCompletedAssessment = false
        let inputColdNovice = TrainingZoneInput(
            baselinePaceSec: nil,
            workoutPaceSec: nil,
            activeGoal: "Base Building",
            experienceLevel: "Novice / Beginner",
            readyForHard: true,
            daysSinceWorkout: 0,
            heightAdjustedCadenceFloor: 150,
            useMetricSystem: true,
            isSubjectiveDistress: false,
            totalHistoricalRunsCount: 0
        )
        let rxNovice = TrainingZoneEngine.computePrescription(inputColdNovice)
        XCTAssertTrue(rxNovice.isColdStart)
        XCTAssertTrue(rxNovice.nextSessionName.contains("20-Minute Baseline Assessment"))

        // 4. Assessment graduation locks out Tier 3
        TrainingZoneEngine.hasCompletedAssessment = true
        let rxGraduated = TrainingZoneEngine.computePrescription(inputColdNovice)
        XCTAssertFalse(rxGraduated.isColdStart)
        XCTAssertFalse(rxGraduated.nextSessionName.contains("Baseline Assessment"))
    }

    @MainActor
    func testOrthogonalToolsAndCoachActionPolymorphism() async throws {
        let runRecord = makeTestRunRecord(isIndoor: true)
        let chatEngine = AnalystChatEngine(runRecord: runRecord)

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            // 1. QueryWorkoutHistoryTool - History comparison
            let historyQuery = QueryWorkoutHistoryQuery(
                scope: .compare,
                target: "previous",
                compareWith: "last outdoor"
            )
            XCTAssertEqual(historyQuery.scope, .compare)
            XCTAssertEqual(historyQuery.target, "previous")
            XCTAssertEqual(historyQuery.compareWith, "last outdoor")

            // 2. GetTrainingScheduleTool - Schedule range query
            let scheduleQuery = GetTrainingScheduleQuery(from: "2026-10-20", to: "2026-10-24")
            XCTAssertEqual(scheduleQuery.from, "2026-10-20")
            XCTAssertEqual(scheduleQuery.to, "2026-10-24")

            // 3. ExecuteCoachActionTool - Display Drill
            let drillAction = ExecuteCoachActionQuery(action: .displayDrill, payload: "cadence_pyramids")
            XCTAssertEqual(drillAction.action, .displayDrill)
            XCTAssertEqual(drillAction.payload, "cadence_pyramids")

            // 4. ExecuteCoachActionTool - Update Goal
            let goalAction = ExecuteCoachActionQuery(action: .updateGoal, goal: .halfMarathon)
            XCTAssertEqual(goalAction.action, .updateGoal)
            XCTAssertEqual(goalAction.goal, .halfMarathon)

            // 5. ExecuteCoachActionTool - Export to Watch
            let watchAction = ExecuteCoachActionQuery(action: .exportToWatch, payload: "cadence_pyramids")
            XCTAssertEqual(watchAction.action, .exportToWatch)
            XCTAssertEqual(watchAction.payload, "cadence_pyramids")

            // 6. ExecuteCoachActionTool - Record Feedback
            let feedbackAction = ExecuteCoachActionQuery(action: .recordFeedback, payload: "Legs felt heavy on rep 4")
            XCTAssertEqual(feedbackAction.action, .recordFeedback)
            XCTAssertEqual(feedbackAction.payload, "Legs felt heavy on rep 4")

            let session = chatEngine.getOrCreateSession()
            XCTAssertNotNil(session)
        }
        #endif
    }

    // MARK: - 5. RAG Payloads

    func testRunSignatureAndMacroProfileCompactRAGSummary() {
        let signature = RunSignature(
            classification: "Intervals",
            confidence: 0.92,
            probabilities: ["Intervals": 0.92, "Tempo Run": 0.08],
            anomalies: ["Cadence Dip at km 3"],
            cadenceFloor: 152.0,
            phaseSegments: [
                PhaseSegment(startSeconds: 0, endSeconds: 600, kind: "steady", avgPace: 330, avgCadence: 160, avgHR: 140),
                PhaseSegment(startSeconds: 600, endSeconds: 900, kind: "work", avgPace: 270, avgCadence: 175, avgHR: 165),
                PhaseSegment(startSeconds: 900, endSeconds: 1200, kind: "recovery", avgPace: 360, avgCadence: 150, avgHR: 135)
            ],
            dataSource: "wrist",
            isIndoor: true,
            needsInclineReview: false
        )
        let summary = signature.compactRAGSummary
        XCTAssertTrue(summary.contains("Workout Type: Intervals"))
        XCTAssertTrue(summary.contains("Cadence Floor: 152 SPM"))
        XCTAssertTrue(summary.contains("Interval Structure: 1 work reps, 1 recovery reps"))

        let profile = MacroProfile(
            acwr: 1.14,
            acuteLoad: 250.0,
            chronicWeeklyLoad: 220.0,
            baselinePace: 315.0,
            baselineHR: 148.0,
            baselineCadence: 164.0,
            baselineEfficiencyFactor: 1.35,
            updatedAt: Date()
        )
        let profileSummary = profile.compactRAGSummary
        XCTAssertTrue(profileSummary.contains("Workload Ratio (ACWR): 1.14"))
        XCTAssertTrue(profileSummary.contains("7-Day Training Load: 250"))
    }

    // MARK: - 6. First Analysis Persistence

    @MainActor
    func testIndoorAndOutdoorClassificationPersistenceOnFirstAnalysis() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RunRecord.self, CoachingInsight.self, DrillRecommendation.self, configurations: config)
        let context = container.mainContext

        // Run with nil isIndoor and empty detectedTypeRaw
        let record = RunRecord(
            hkWorkoutID: UUID(),
            date: Date(),
            totalDistanceMeters: 5000,
            duration: 1800,
            rawAvgPace: 360,
            rawAvgHeartRate: 150,
            rawAvgCadence: 165,
            workingAvgPace: 360,
            workingAvgCadence: 165,
            workingAvgHeartRate: 150,
            isIndoor: nil,
            paceCV: 0.03,
            paceSlope: 0.0,
            percentZone4: 0.1,
            detectedTypeRaw: ""
        )
        context.insert(record)
        try context.save()

        XCTAssertNil(record.isIndoor)
        XCTAssertEqual(record.detectedTypeRaw, "")

        // Simulate first appearance resolution (.task resolution logic)
        if record.isIndoor == nil {
            record.isIndoor = (record.dataSourceRaw == "gymkit") ? true : false
            try context.save()
        }
        if record.detectedTypeRaw.isEmpty {
            record.detectedTypeRaw = record.normalizedClassification
            try context.save()
        }

        XCTAssertEqual(record.isIndoor, false, "Should resolve to Outdoor (false) and persist")
        XCTAssertEqual(record.detectedTypeRaw, "Steady Effort", "Should resolve to Steady Effort and persist")

        // Ingested DTO resolution check
        let indoorDTO = RunRecordDTO(
            hkWorkoutID: UUID(),
            date: Date(),
            totalDistanceMeters: 4800,
            duration: 1800,
            rawAvgPace: 375,
            rawAvgHeartRate: 155,
            rawAvgCadence: 168,
            workingAvgPace: 375,
            workingAvgCadence: 168,
            workingAvgHeartRate: 155,
            isIndoor: true,
            paceCV: 0.02,
            paceSlope: 0.0,
            percentZone4: 0.15,
            detectedTypeRaw: "Steady Effort",
            framboiseTags: ["indoor"]
        )

        let indoorRecord = RunRecord(
            hkWorkoutID: indoorDTO.hkWorkoutID,
            date: indoorDTO.date,
            totalDistanceMeters: indoorDTO.totalDistanceMeters,
            duration: indoorDTO.duration,
            rawAvgPace: indoorDTO.rawAvgPace,
            rawAvgHeartRate: indoorDTO.rawAvgHeartRate,
            rawAvgCadence: indoorDTO.rawAvgCadence,
            workingAvgPace: indoorDTO.workingAvgPace,
            workingAvgCadence: indoorDTO.workingAvgCadence,
            workingAvgHeartRate: indoorDTO.workingAvgHeartRate,
            isIndoor: indoorDTO.isIndoor ?? false,
            paceCV: indoorDTO.paceCV,
            paceSlope: indoorDTO.paceSlope,
            percentZone4: indoorDTO.percentZone4,
            detectedTypeRaw: indoorDTO.detectedTypeRaw.isEmpty ? "Steady Effort" : indoorDTO.detectedTypeRaw
        )
        context.insert(indoorRecord)
        try context.save()

        XCTAssertEqual(indoorRecord.isIndoor, true, "Indoor run must persist as true on first analysis")
        XCTAssertEqual(indoorRecord.detectedTypeRaw, "Steady Effort", "Classification must persist on first analysis")
    }

    // MARK: - 11. Data-Driven Analyst Queries

    // MARK: - Native FoundationModels Tool Calling Tests

    @MainActor
    func testInspectWorkoutToolSteadyStateOutput() async throws {
        let runRecord = makeTestRunRecord(isIndoor: false)
        runRecord.detectedTypeRaw = "Steady Effort"
        let chatEngine = AnalystChatEngine(runRecord: runRecord)

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let workoutTool = InspectWorkoutTool { _ in
                let analysis = chatEngine.makeAnalysisContext()
                return analysis.compactTelemetryAnalysis()
            }

            let workoutResult = try await workoutTool.call(arguments: InspectWorkoutQuery())
            XCTAssertTrue(workoutResult.contains("steady_state_scorecard"))
            XCTAssertTrue(workoutResult.contains("background_session_totals"))
            XCTAssertFalse(workoutResult.contains("interval_scorecard"), "Steady runs must NOT emit interval scorecard")
            XCTAssertFalse(workoutResult.contains("\"reps\""), "Steady runs must NOT emit rep breakdown bucket")
            XCTAssertEqual(workoutTool.name, "inspectWorkout")
        }
        #endif
    }

    @MainActor
    func testInspectWorkoutToolIntervalScorecardAndRepsAtTopLevel() async throws {
        let runRecord = makeTestRunRecord(isIndoor: true)
        runRecord.detectedTypeRaw = "Intervals"
        let signature = RunSignature(
            classification: "Intervals",
            confidence: 0.95,
            probabilities: ["Intervals": 0.95],
            anomalies: [],
            cadenceFloor: 150.0,
            phaseSegments: [
                PhaseSegment(startSeconds: 0, endSeconds: 240, kind: "work", avgPace: 270, avgCadence: 172, avgHR: 165),
                PhaseSegment(startSeconds: 240, endSeconds: 360, kind: "recovery", avgPace: 380, avgCadence: 148, avgHR: 150),
                PhaseSegment(startSeconds: 360, endSeconds: 600, kind: "work", avgPace: 255, avgCadence: 175, avgHR: 170)
            ],
            dataSource: "wrist",
            isIndoor: true,
            needsInclineReview: false
        )
        let chatEngine = AnalystChatEngine(runRecord: runRecord, runSignature: signature)

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let workoutTool = InspectWorkoutTool { _ in
                let analysis = chatEngine.makeAnalysisContext()
                return analysis.compactTelemetryAnalysis()
            }

            let workoutResult = try await workoutTool.call(arguments: InspectWorkoutQuery())
            XCTAssertTrue(workoutResult.contains("interval_scorecard"), "Interval workouts must emit interval_scorecard at top level")
            XCTAssertTrue(workoutResult.contains("active_work_pace"))
            XCTAssertTrue(workoutResult.contains("active_turnover_spm"))
            XCTAssertTrue(workoutResult.contains("total_work_reps"))
            XCTAssertTrue(workoutResult.contains("reps"), "Interval workouts must emit full reps array in initial query")
            XCTAssertTrue(workoutResult.contains("background_session_totals"), "Blended totals must be demoted under background_session_totals")
            XCTAssertFalse(workoutResult.contains("steady_state_scorecard"), "Interval workouts must NOT emit steady state scorecard")

            // Verify strong typing by decoding JSON into UnifiedWorkoutToolResponse
            let data = try XCTUnwrap(workoutResult.data(using: .utf8))
            let decoded = try JSONDecoder().decode(UnifiedWorkoutToolResponse.self, from: data)
            XCTAssertEqual(decoded.workout_type, "Intervals")
            XCTAssertNotNil(decoded.interval_scorecard)
            XCTAssertEqual(decoded.interval_scorecard?.total_work_reps, 2)
            XCTAssertEqual(decoded.interval_scorecard?.active_turnover_spm, 173)
            XCTAssertEqual(decoded.reps?.count, 2)
            XCTAssertEqual(decoded.reps?.first?.rep_number, 1)
            XCTAssertEqual(decoded.reps?.first?.work_cadence_spm, 172)
            XCTAssertEqual(decoded.reps?.last?.rep_number, 2)
            XCTAssertEqual(decoded.reps?.last?.work_cadence_spm, 175)
            XCTAssertNil(decoded.steady_state_scorecard)
        }
        #endif
    }

    @MainActor
    func testNativeToolCallingLeanSystemInstructions() {
        let runRecord = makeTestRunRecord(isIndoor: true)
        let chatEngine = AnalystChatEngine(runRecord: runRecord)

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let leanPrompt = chatEngine.buildLeanSystemInstructions()
            XCTAssertTrue(leanPrompt.contains("CONTEXT:"))
            XCTAssertTrue(leanPrompt.contains("getReadinessAndWorkload") || leanPrompt.contains("getTrainingSchedule"))
            XCTAssertFalse(leanPrompt.contains("WORKOUT DATA SHEET:"), "Lean tool instructions must NOT include upfront raw data sheet")
            XCTAssertTrue(leanPrompt.count < 1200, "System prompt must stay under 1,200 characters to comply with TN3193 4,096 token limit")
        }
        #endif
    }

    @MainActor

    func testDrillResolutionFromToolPayload() {
        XCTAssertEqual(PreRunDrillId.resolve(from: "cadence_pyramids"), .cadencePyramids)
        XCTAssertEqual(PreRunDrillId.resolve(from: "Cadence Pyramids"), .cadencePyramids)
        XCTAssertEqual(PreRunDrillId.resolve(from: "strides"), .strides)
        XCTAssertEqual(PreRunDrillId.resolve(from: "rhythm_intervals"), .rhythmIntervals)
        XCTAssertEqual(PreRunDrillId.resolve(from: "tempo_surges"), .tempoSurges)
        XCTAssertEqual(PreRunDrillId.resolve(from: "hill_bounds"), .hillBounds)
        XCTAssertNil(PreRunDrillId.resolve(from: "non_existent_drill"))
    }

    @MainActor
    func testDeterministicRunAnalysisSummaryProvidesRichPhysiologicalContext() {
        let runRecord = makeTestRunRecord(isIndoor: true)
        let detailView = RunDetailView(runRecord: runRecord)
        guard let summary = detailView.deterministicRunAnalysisSummary else {
            XCTFail("deterministicRunAnalysisSummary must not be nil for run with biometrics")
            return
        }

        // Must explain turnover relative to mechanical floor
        XCTAssertTrue(summary.contains("mechanical floor"), "Must explain cadence relative to mechanical floor")
        // Must explain indoor environment thermal buildup or cardiovascular coupling
        XCTAssertTrue(summary.contains("convective") || summary.contains("thermal") || summary.contains("aerobic"), "Must explain cardiovascular/environmental context")
        // Must not be a shallow 1-sentence repetition
        XCTAssertTrue(summary.count > 100, "Summary must be a rich multi-sentence coaching explanation, not a 1-sentence recitation")
    }

    @MainActor
    func testLeanSystemInstructionsSidestepAndMedicalRules() {
        let runRecord = makeTestRunRecord(isIndoor: true)
        let chatEngine = AnalystChatEngine(runRecord: runRecord)

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let instructions = chatEngine.buildLeanSystemInstructions()
            XCTAssertTrue(instructions.contains("Outside Running"))
            XCTAssertTrue(instructions.contains("Medical Safety"))
            XCTAssertTrue(instructions.contains("inspectWorkout"))
            XCTAssertTrue(instructions.contains("getReadinessAndWorkload") || instructions.contains("getTrainingSchedule"))
            XCTAssertTrue(instructions.contains("executeCoachAction"))
        }
        #endif
    }

    @MainActor
    func testAnalystChatHandlesDanceQueryWithNaturalRedirectionAndNoFabricatedNumbers() async {
        let runRecord = makeTestRunRecord(isIndoor: true)
        let chatEngine = AnalystChatEngine(runRecord: runRecord)
        chatEngine.modelResponder = { instructions, _ in
            XCTAssertTrue(instructions.contains("Outside Running"))
            return "While I can appreciate dancing, as your running coach I'm focused on your training and recovery!"
        }
        await chatEngine.sendMessage("Can you teach me how to dougie?")
        let response = chatEngine.messages.last?.text ?? ""

        XCTAssertTrue(
            response.lowercased().contains("dancing") || response.lowercased().contains("running coach"),
            "Response must acknowledge dance or clarify running coach domain"
        )
    }

    @MainActor
    func testInspectWorkoutToolDeliversDiscreteRepsInUnifiedPayload() async throws {
        let runRecord = makeTestRunRecord(isIndoor: true)
        runRecord.detectedTypeRaw = "Intervals"
        let signature = RunSignature(
            classification: "Intervals",
            confidence: 0.95,
            probabilities: ["Intervals": 0.95],
            anomalies: [],
            cadenceFloor: 150.0,
            phaseSegments: [
                PhaseSegment(startSeconds: 0, endSeconds: 240, kind: "work", avgPace: 270, avgCadence: 172, avgHR: 165),
                PhaseSegment(startSeconds: 240, endSeconds: 360, kind: "recovery", avgPace: 380, avgCadence: 148, avgHR: 150),
                PhaseSegment(startSeconds: 360, endSeconds: 600, kind: "work", avgPace: 255, avgCadence: 175, avgHR: 170)
            ],
            dataSource: "wrist",
            isIndoor: true,
            needsInclineReview: false
        )
        let chatEngine = AnalystChatEngine(runRecord: runRecord, runSignature: signature, macroProfile: nil)

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let inspectTool = InspectWorkoutTool { _ in
                chatEngine.makeAnalysisContext().compactTelemetryAnalysis()
            }
            let response = try await inspectTool.call(arguments: InspectWorkoutQuery())
            XCTAssertTrue(response.contains("interval_scorecard"))
            XCTAssertTrue(response.contains("\"reps\""))
            XCTAssertTrue(response.contains("\"rep_number\":1"))
            XCTAssertTrue(response.contains("\"rep_number\":2"))
            XCTAssertTrue(response.contains("working_stats"))
            XCTAssertTrue(response.contains("workout_stats"))
        }
        #endif
    }

    @MainActor
    func testDualBrainEliminationAndUnifiedToolCallingMultiTurnFlow() async throws {
        let runRecord = makeTestRunRecord(isIndoor: true)
        runRecord.detectedTypeRaw = "Intervals"
        runRecord.workingAvgPace = 385.0 // 6:25/km blended session pace
        runRecord.workingAvgCadence = 156.0 // 156 SPM blended cadence
        runRecord.workingAvgHeartRate = 147.0 // 147 BPM blended HR

        // Create an authentic 9-rep interval workout matching RCA (5:42/km = 342s/km, 162 SPM, recovery 7:15/km = 435s/km)
        var segments: [PhaseSegment] = []
        for i in 0..<9 {
            let startW = Double(i * 240)
            let endW = startW + 120
            segments.append(PhaseSegment(
                startSeconds: startW,
                endSeconds: endW,
                kind: "work",
                avgPace: 342.0, // 5:42/km
                avgCadence: 162.0, // 162 SPM
                avgHR: 165.0
            ))
            let startR = endW
            let endR = startR + 120
            segments.append(PhaseSegment(
                startSeconds: startR,
                endSeconds: endR,
                kind: "recovery",
                avgPace: 435.0, // 7:15/km
                avgCadence: 140.0,
                avgHR: 155.0
            ))
        }

        let signature = RunSignature(
            classification: "Intervals",
            confidence: 0.98,
            probabilities: ["Intervals": 0.98],
            anomalies: [],
            cadenceFloor: 150.0,
            phaseSegments: segments,
            dataSource: "wrist",
            isIndoor: true,
            needsInclineReview: false
        )

        let chatEngine = AnalystChatEngine(runRecord: runRecord, runSignature: signature)
        let analysis = chatEngine.makeAnalysisContext()

        // 1. Validate Unified Tool Response Structure (Step 2 & Step 3 RCA)
        let unifiedResponse = analysis.buildUnifiedWorkoutToolResponse()
        XCTAssertEqual(unifiedResponse.workout_type, "Intervals")

        // PRIMARY OBJECT: IntervalScorecard must report true active workload
        let scorecard = try XCTUnwrap(unifiedResponse.interval_scorecard)
        XCTAssertEqual(scorecard.total_work_reps, 9)
        XCTAssertEqual(scorecard.active_work_pace, "5:42/km")
        XCTAssertEqual(scorecard.active_turnover_spm, 162)

        // THE 9-REP ARRAY: Must persist all 9 reps in session payload
        let reps = try XCTUnwrap(unifiedResponse.reps)
        XCTAssertEqual(reps.count, 9)
        for (idx, rep) in reps.enumerated() {
            XCTAssertEqual(rep.rep_number, idx + 1)
            XCTAssertEqual(rep.work_pace, "5:42/km")
            XCTAssertEqual(rep.work_cadence_spm, 162)
            XCTAssertEqual(rep.recovery_pace, "7:15/km")
        }

        // SECONDARY BACKGROUND: Blended session data is demoted
        XCTAssertEqual(unifiedResponse.background_session_totals.blended_session_avg_pace, "6:25/km")
        XCTAssertEqual(unifiedResponse.background_session_totals.height_cadence_floor_spm, 150)

        // 2. Validate Multi-Turn Chat Flow without Swift Template Interception (Step 1 RCA)
        var turnCount = 0
        chatEngine.modelResponder = { instructions, userPrompt in
            turnCount += 1
            if userPrompt.contains("Unpack it") {
                // Must command native tool calling
                XCTAssertTrue(instructions.contains("CONTEXT:"))
                XCTAssertTrue(instructions.contains("RULES:"))
                return "During your 9-rep Intervals on Tuesday, you held an active work pace of **5:42/km** at **162 SPM** with crisp rhythm."
            } else if userPrompt.contains("Tell me more") {
                // Reads 9 reps from memory context without hallucinating 180 SPM
                return "Looking closer across your 9 reps, you locked onto **5:42/km** and **162 SPM** with steady stride control throughout."
            } else if userPrompt.contains("180 spm") {
                // Must NOT get intercepted by legacy 156 SPM fallback template
                return "You held **162 SPM** across all 9 work reps—comfortably above your **150 SPM** floor. 180 SPM was never recorded."
            }
            return "Coaching observation."
        }

        // Turn 1: Unpack it
        await chatEngine.sendMessage("Unpack it")
        let turn1Response = chatEngine.messages.last?.text ?? ""
        XCTAssertTrue(turn1Response.contains("5:42/km"))
        XCTAssertTrue(turn1Response.contains("162 SPM"))
        XCTAssertFalse(turn1Response.contains("6:25/km"), "Must not quote blended pace for intervals")

        // Turn 2: Tell me more
        await chatEngine.sendMessage("Tell me more")
        let turn2Response = chatEngine.messages.last?.text ?? ""
        XCTAssertTrue(turn2Response.contains("162 SPM"))
        XCTAssertFalse(turn2Response.contains("180 SPM"), "Must not hallucinate 180 SPM")

        // Turn 3: 180 spm??? Are you sure
        await chatEngine.sendMessage("180 spm??? Are you sure")
        let turn3Response = chatEngine.messages.last?.text ?? ""
        XCTAssertTrue(turn3Response.contains("162 SPM"))
        XCTAssertFalse(turn3Response.contains("156 SPM"), "Must not fall back to blended 156 SPM Swift template")
        XCTAssertEqual(turnCount, 3, "All 3 turns must flow through model responder without template interception")
    }

    // MARK: - Chat Data Path Alignment & Veracity Tests

    @MainActor
    func testSteadyJogIsNotSegmentedIntoIntervals() async {
        let engine = FramboiseEngine()
        let now = Date()
        // Simulate a steady 7:17/km (437 s/km) run with minimal fluctuations (7:15 - 7:19) and 158 SPM
        var steadyBuckets: [BucketData] = []
        for i in 0..<20 {
            let offsetSeconds = Double(i * 30)
            let paceVariance = Double(i % 3) * 2.0
            let cadenceVariance = Double(i % 2)
            steadyBuckets.append(
                BucketData(
                    startTime: now.addingTimeInterval(offsetSeconds),
                    distanceMeters: 68.6,
                    durationSeconds: 30.0,
                    meanPaceSecPerKm: 435.0 + paceVariance,
                    meanCadence: 158.0 + cadenceVariance,
                    meanHR: 74.0
                )
            )
        }

        let segments = await engine.generatePhaseSegments(from: steadyBuckets, cadenceFloor: 150.0)
        let workSegments = segments.filter { $0.kind == "work" }
        XCTAssertEqual(workSegments.count, 0, "A steady jog with minimal pace variance (< 10%) must never be segmented into phantom work reps")
        XCTAssertTrue(segments.allSatisfy { $0.kind == "steady" }, "All moving segments must be steady")

        let runRecord = RunRecord(
            hkWorkoutID: UUID(),
            date: now,
            totalDistanceMeters: 4000,
            duration: 1800,
            rawAvgPace: 437,
            rawAvgHeartRate: 74,
            rawAvgCadence: 158,
            workingAvgPace: 437,
            workingAvgCadence: 158,
            workingAvgHeartRate: 74,
            isIndoor: false,
            paceCV: 0.03,
            paceSlope: 0.0,
            percentZone4: 0.0,
            detectedTypeRaw: "Steady Effort"
        )
        let chatEngine = AnalystChatEngine(runRecord: runRecord)
        let context = chatEngine.makeAnalysisContext()
        XCTAssertNotEqual(context.evaluationModality, WorkoutEvaluationModality.intervals, "Steady run must not be assigned interval evaluation modality")
        let response = context.buildUnifiedWorkoutToolResponse()
        XCTAssertNil(response.interval_scorecard, "Steady run tool response must not have an interval scorecard")
        XCTAssertNil(response.reps, "Steady run tool response must not contain interval reps")
        XCTAssertNotNil(response.steady_state_scorecard, "Steady run tool response must deliver steady_state_scorecard")
    }

    @MainActor
    func testHeartRateLowConfidenceDetectionOnRestingRateRun() {
        let now = Date()
        let lowHRRun = RunRecord(
            hkWorkoutID: UUID(),
            date: now,
            totalDistanceMeters: 4000,
            duration: 1800,
            rawAvgPace: 437, // 7:17/km
            rawAvgHeartRate: 74,
            rawAvgCadence: 158,
            workingAvgPace: 437,
            workingAvgCadence: 158,
            workingAvgHeartRate: 74,
            isIndoor: false,
            paceCV: 0.03,
            paceSlope: 0.0,
            percentZone4: 0.0,
            detectedTypeRaw: "Steady Effort"
        )
        XCTAssertTrue(lowHRRun.isHeartRateSensorLowConfidence, "74 BPM on an active 30-min run must be flagged as low confidence sensor data")

        let normalRun = makeTestRunRecord(isIndoor: false)
        XCTAssertFalse(normalRun.isHeartRateSensorLowConfidence, "Normal 150 BPM run must be reliable")

        let chatEngine = AnalystChatEngine(runRecord: lowHRRun)
        let context = chatEngine.makeAnalysisContext()
        let payload = context.buildUnifiedWorkoutToolResponse()
        XCTAssertEqual(payload.heart_rate_confidence, .unreliableArtifact, "Tool payload must explicitly flag low confidence HR sensor data")
        XCTAssertNil(payload.steady_state_scorecard?.avg_heart_rate_bpm, "Low confidence HR integer must be nulled out so LLM cannot quote it")
        XCTAssertEqual(payload.steady_state_scorecard?.heart_rate_status, "sensor_lock_anomaly")
        XCTAssertNil(payload.splits?.first?.heart_rate_bpm, "Split HR integers must be nulled out")
    }

    @MainActor
    func testReadinessToolPayloadReturnsStructuredCategory() {
        let runRecord = makeTestRunRecord(isIndoor: false)
        let chatEngine = AnalystChatEngine(runRecord: runRecord)
        let session = chatEngine.getOrCreateSession()
        XCTAssertNotNil(session)

        let analysis = chatEngine.makeAnalysisContext()
        let rx = analysis.lockedPrescription
        XCTAssertEqual(rx.intensityCategory, "EASY_AEROBIC_ZONE_2")

        let instructions = chatEngine.buildLeanSystemInstructions()
        XCTAssertTrue(instructions.contains("getReadinessAndWorkload"), "Instructions must provide getReadinessAndWorkload tool")
        XCTAssertFalse(instructions.contains("forbidden_terms"), "Prompt must NOT contain forbidden_terms to avoid token attention bleed")
    }

    @MainActor
    func testWarmUpFollowedBySteadyRunIsNotClassifiedAsIntervals() async {
        let engine = FramboiseEngine()
        let now = Date()

        // 5 minutes warm-up at 8:15/km (495 s/km) followed by 25 minutes steady at 6:30/km (390 s/km)
        var buckets: [BucketData] = []
        // Warm-up: 10 buckets of 30s = 5 min
        for i in 0..<10 {
            buckets.append(BucketData(
                startTime: now.addingTimeInterval(Double(i * 30)),
                distanceMeters: 60.6,
                durationSeconds: 30.0,
                meanPaceSecPerKm: 495.0,
                meanCadence: 145.0,
                meanHR: 130.0
            ))
        }
        // Steady block: 50 buckets of 30s = 25 min
        for i in 10..<60 {
            buckets.append(BucketData(
                startTime: now.addingTimeInterval(Double(i * 30)),
                distanceMeters: 76.9,
                durationSeconds: 30.0,
                meanPaceSecPerKm: 390.0,
                meanCadence: 162.0,
                meanHR: 155.0
            ))
        }

        let segments = await engine.generatePhaseSegments(from: buckets, cadenceFloor: 150.0)
        let workSegments = segments.filter { $0.kind == "work" }
        XCTAssertLessThan(workSegments.count, 2, "A single warm-up transition must have < 2 work reps")
        XCTAssertEqual(workSegments.count, 0, "Consolidated phase segments must have 0 work reps because workRepCount < 2 is gated to steady")
    }

    @MainActor
    func testReadinessToolWithUserReportedDistressOverridesPrescriptionToRecovery() {
        let runRecord = makeTestRunRecord(isIndoor: false)
        let chatEngine = AnalystChatEngine(runRecord: runRecord)

        // Default readiness without distress
        let normalContext = chatEngine.makeAnalysisContext(isSubjectiveDistress: false)
        XCTAssertEqual(normalContext.recoveryTimeline.state, .productive)

        // Subjective distress override (illness, pain, exhaustion)
        let distressContext = chatEngine.makeAnalysisContext(isSubjectiveDistress: true)
        XCTAssertEqual(distressContext.lockedPrescription.intensityCategory, "FULL_REST_OVERRIDE")
    }

    @MainActor
    func testZeroHallucinationSafetyGateDeliversAuthenticRepsWhenToolNotCalled() {
        let runRecord = makeTestRunRecord(isIndoor: true)
        runRecord.detectedTypeRaw = "Intervals"
        let signature = RunSignature(
            classification: "Intervals",
            confidence: 0.95,
            probabilities: ["Intervals": 0.95],
            anomalies: [],
            cadenceFloor: 150.0,
            phaseSegments: [
                PhaseSegment(startSeconds: 0, endSeconds: 90, kind: "work", avgPace: 340, avgCadence: 163, avgHR: 140),
                PhaseSegment(startSeconds: 90, endSeconds: 150, kind: "recovery", avgPace: 435, avgCadence: 145, avgHR: 133),
                PhaseSegment(startSeconds: 150, endSeconds: 270, kind: "work", avgPace: 345, avgCadence: 163, avgHR: 143)
            ],
            dataSource: "wrist",
            isIndoor: true,
            needsInclineReview: false
        )
        let chatEngine = AnalystChatEngine(runRecord: runRecord, runSignature: signature)
        let context = chatEngine.makeAnalysisContext()

        // Interval reps strictly preserve authentic telemetry
        let workoutResponse = context.buildUnifiedWorkoutToolResponse()
        XCTAssertEqual(workoutResponse.reps?.count, 2, "Must contain 2 authentic reps")
        XCTAssertEqual(workoutResponse.reps?.first?.work_cadence_spm, 163, "Must contain authentic 163 SPM from telemetry")
    }

    // MARK: - Tool API Contract & Cross-Environment History Matching

    @MainActor
    func testLeanSystemInstructionsApiContractSpecification() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let runRecord = makeTestRunRecord(isIndoor: true)
            runRecord.detectedTypeRaw = "Intervals"
            let chatEngine = AnalystChatEngine(runRecord: runRecord)
            let prompt = chatEngine.buildLeanSystemInstructions()

            XCTAssertTrue(prompt.contains("CONTEXT:"), "Must declare context block")
            XCTAssertTrue(prompt.contains("RULES:"), "Must declare lean rules block")
            XCTAssertTrue(prompt.contains("getReadinessAndWorkload") || prompt.contains("getTrainingSchedule"), "Must reference orthogonal coaching tools")
            XCTAssertFalse(prompt.contains("(belt-driven, static air)"), "Prompt header must not parrot awkward belt-driven static air boilerplate")
            XCTAssertTrue(prompt.count < 1200, "System instructions must stay lean under 1,200 characters to comply with TN3193 4,096 token limit")
        }
        #endif
    }

    @MainActor
    func testHistoricalRunMatchingAndComparisonForOutdoorRunQuery() throws {
        let schema = Schema([RunRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let calendar = Calendar.current
        let today = Date()

        // 1. Prior outdoor road run from 12 days ago
        let outdoorDate = calendar.date(byAdding: .day, value: -12, to: today) ?? today.addingTimeInterval(-12 * 86400)
        let outdoorRun = RunRecord(
            hkWorkoutID: UUID(),
            date: outdoorDate,
            totalDistanceMeters: 6000,
            duration: 2100,
            rawAvgPace: 350,
            rawAvgHeartRate: 152,
            rawAvgCadence: 160,
            workingAvgPace: 350,
            workingAvgCadence: 160,
            workingAvgHeartRate: 152,
            isIndoor: false,
            paceCV: 0.04,
            paceSlope: 0.0,
            percentZone4: 0.15,
            detectedTypeRaw: "Steady Effort"
        )
        context.insert(outdoorRun)

        // 2. Current indoor treadmill intervals workout
        let indoorRun = RunRecord(
            hkWorkoutID: UUID(),
            date: today,
            totalDistanceMeters: 6600,
            duration: 2700,
            rawAvgPace: 342,
            rawAvgHeartRate: 154,
            rawAvgCadence: 163,
            workingAvgPace: 342,
            workingAvgCadence: 163,
            workingAvgHeartRate: 154,
            isIndoor: true,
            paceCV: 0.10,
            paceSlope: 0.0,
            percentZone4: 0.25,
            detectedTypeRaw: "Intervals"
        )
        context.insert(indoorRun)
        try context.save()

        // Test 1: Cross-environment query matches prior outdoor run
        let crossEnvQuery = "Tell me about one of my outdoor runs. Compare my last outdoor run to my last indoor run"
        let matchedRun1 = try XCTUnwrap(HistoricalRunMatcher.findRun(matching: crossEnvQuery, relativeTo: indoorRun, in: context))
        XCTAssertEqual(matchedRun1.id, outdoorRun.id, "Cross-environment query must match prior outdoor run")

        // Test 2: Looking beyond 7 days query matches prior outdoor run
        let beyond7DaysQuery = "Check recent outdoor activity, you'll need to look beyond than 7days"
        let matchedRun2 = try XCTUnwrap(HistoricalRunMatcher.findRun(matching: beyond7DaysQuery, relativeTo: indoorRun, in: context))
        XCTAssertEqual(matchedRun2.id, outdoorRun.id, "Beyond 7 days outdoor query must match prior outdoor run")

        // Test 3: Mathematical comparison contains structured telemetry facts
        let comparison = HistoricalRunMatcher.compare(current: indoorRun, with: outdoorRun)
        XCTAssertEqual(comparison.paceDeltaSeconds, 8, "350 - 342 = 8s faster in current run")
        XCTAssertEqual(comparison.cadenceDelta, 3, "163 - 160 = +3 SPM in current run")
        XCTAssertEqual(comparison.heartRateDelta, 2, "154 - 152 = +2 BPM in current run")
        XCTAssertTrue(comparison.structuredTelemetryFacts.contains("Outdoor"))
        XCTAssertTrue(comparison.structuredTelemetryFacts.contains("Indoor Treadmill"))
        XCTAssertTrue(comparison.structuredTelemetryFacts.contains("8s/km faster"))
        XCTAssertTrue(comparison.structuredTelemetryFacts.contains("+3 SPM"))
    }

    func testWorkoutMathCalculatorDeterministicCalculations() {
        // 1. Pace subtraction (6:25/km vs 6:14/km)
        let paceResult = WorkoutMathCalculator.calculate(operation: "pace_delta", valueA: "6:25", valueB: "6:14")
        XCTAssertEqual(paceResult.delta, "+11 s/km")
        XCTAssertTrue(paceResult.summary.contains("11 seconds/km slower"), "Must correctly state 11 seconds/km slower")
        XCTAssertTrue(paceResult.summary.contains("Value A is slower than Value B"))

        // Faster pace subtraction (6:02/km vs 6:14/km)
        let fasterPaceResult = WorkoutMathCalculator.calculate(operation: "pace_delta", valueA: "6:02", valueB: "6:14")
        XCTAssertEqual(fasterPaceResult.delta, "-12 s/km")
        XCTAssertTrue(fasterPaceResult.summary.contains("12 seconds/km faster"))

        // 2. Distance delta with aligned precision (6.64 km - 5.09 km)
        let distResult = WorkoutMathCalculator.calculate(operation: "distance_delta", valueA: "6.64", valueB: "5.09")
        XCTAssertEqual(distResult.delta, "+1.55 km")
        XCTAssertEqual(distResult.deltaNumeric ?? 0.0, 1.55, accuracy: 0.001)
        XCTAssertTrue(distResult.summary.contains("+1.55 km longer"))

        // 3. Heart rate delta (147 BPM vs 157 BPM)
        let hrResult = WorkoutMathCalculator.calculate(operation: "heart_rate_delta", valueA: "147", valueB: "157")
        XCTAssertEqual(hrResult.delta, "-10 BPM")
        XCTAssertTrue(hrResult.summary.contains("10 BPM lower cardiovascular demand"))

        // 4. Cadence delta (156 SPM vs 152 SPM)
        let cadResult = WorkoutMathCalculator.calculate(operation: "cadence_delta", valueA: "156", valueB: "152")
        XCTAssertEqual(cadResult.delta, "+4 SPM")
        XCTAssertTrue(cadResult.summary.contains("+4 SPM higher turnover"))
    }

    @MainActor
    func testCrossRunComparisonExactUnitPrecisionAndAttribution() throws {
        let schema = Schema([RunRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let calendar = Calendar.current
        let today = Date()

        // 1. Outdoor run on September 30 (5094m -> 5.09 km displayed)
        let outdoorDate = calendar.date(byAdding: .day, value: -14, to: today) ?? today.addingTimeInterval(-14 * 86400)
        let outdoorRun = RunRecord(
            hkWorkoutID: UUID(),
            date: outdoorDate,
            totalDistanceMeters: 5094,
            duration: 2040,
            rawAvgPace: 374,
            rawAvgHeartRate: 157,
            rawAvgCadence: 152,
            workingAvgPace: 374,
            workingAvgCadence: 152,
            workingAvgHeartRate: 157,
            isIndoor: false,
            paceCV: 0.04,
            paceSlope: 0.0,
            percentZone4: 0.15,
            detectedTypeRaw: "Steady Effort"
        )
        context.insert(outdoorRun)

        // 2. Indoor run on October 13 (6638m -> 6.64 km displayed)
        let indoorRun = RunRecord(
            hkWorkoutID: UUID(),
            date: today,
            totalDistanceMeters: 6638,
            duration: 2700,
            rawAvgPace: 385,
            rawAvgHeartRate: 147,
            rawAvgCadence: 156,
            workingAvgPace: 385,
            workingAvgCadence: 156,
            workingAvgHeartRate: 147,
            isIndoor: true,
            paceCV: 0.09,
            paceSlope: 0.0,
            percentZone4: 0.20,
            detectedTypeRaw: "Intervals"
        )
        context.insert(indoorRun)
        try context.save()

        // 3. Test parsing comparison targets
        let query = "Compare my last indoor run to my last outdoor run. What are your observations?"
        let targets = try XCTUnwrap(HistoricalRunMatcher.parseComparisonTargets(from: query))
        XCTAssertEqual(targets.targetA, "indoor")
        XCTAssertEqual(targets.targetB, "outdoor")

        // 4. Test compareRuns execution
        let comparison = try XCTUnwrap(
            HistoricalRunMatcher.compareRuns(queryA: targets.targetA, queryB: targets.targetB, relativeTo: indoorRun, in: context)
        )

        // Verify exact unit precision alignment with displayed numbers: 6.64 - 5.09 = 1.55 km (NOT 1.54)
        let facts = comparison.structuredTelemetryFacts
        XCTAssertTrue(facts.contains("+1.55 km longer"), "Distance delta must match displayed precision 6.64 - 5.09 = 1.55 km")
        XCTAssertFalse(facts.contains("+1.54 km longer"), "Distance delta must not suffer from unrounded float subtraction")

        // Verify pace readability: no raw engine seconds clutter like 384s/km or 374s/km
        XCTAssertFalse(facts.contains("385s/km") || facts.contains("374s/km"), "Must omit raw seconds/km representation for clean runner readability")
        XCTAssertTrue(facts.contains("11s/km slower"), "Must correctly state 11s/km slower")

        // Verify unambiguous environment attribution for cadence and heart rate
        XCTAssertTrue(facts.contains("156 SPM in Indoor Treadmill vs 152 SPM in Outdoor"), "Must explicitly attribute cadence directionality")
        XCTAssertTrue(facts.contains("147 BPM in Indoor Treadmill vs 157 BPM in Outdoor"), "Must explicitly attribute heart rate demand")
    }

    // MARK: - Forensic Audit Alignment Tests

    @MainActor
    func testTelemetryHighlighterSupportsRangesAndStepsPerMinute() {
        let text = "Cadence: 148–154 steps per minute. Pace: 7:37–8:07/km. Heart rate: +18 BPM."
        let attributed = TelemetryHighlighter.highlight(text)
        let str = String(attributed.characters)

        XCTAssertEqual(str, text)
    }

    @MainActor
    func testWorkingStatsAndWorkoutStatsDelineationInToolResponse() {
        UserDefaults.standard.set(true, forKey: "useMetricSystem")
        let runRecord = makeTestRunRecord(isIndoor: true)
        runRecord.duration = 2700.0 // 45:00 total clock time
        runRecord.rawAvgPace = 360.0 // 6:00/km gross pace
        runRecord.rawAvgCadence = 158.0 // 158 raw cadence with pauses
        runRecord.workingAvgPace = 338.0 // 5:38/km moving pace
        runRecord.workingAvgCadence = 162.0 // 162 active running cadence
        runRecord.workingDurationSeconds = 2535.0 // 42:15 moving time

        let chatEngine = AnalystChatEngine(runRecord: runRecord)
        let analysis = chatEngine.makeAnalysisContext()
        let response = analysis.buildUnifiedWorkoutToolResponse()

        // 1. Working Stats: moving time & pause-trimmed metrics
        let working = response.working_stats
        XCTAssertNotNil(working)
        XCTAssertEqual(working?.moving_time, "42:15")
        XCTAssertEqual(working?.moving_pace, "5:38/km")
        XCTAssertEqual(working?.working_cadence_spm, 162)

        // 2. Workout Stats: gross HealthKit session totals
        let workout = response.workout_stats
        XCTAssertNotNil(workout)
        XCTAssertEqual(workout?.total_time, "45:00")
        XCTAssertEqual(workout?.raw_cadence_spm, 158)

        // 3. Duration Detail (duration_class + minutes)
        XCTAssertEqual(response.duration.duration_class, .standard)
        XCTAssertEqual(response.duration.moving_minutes, 42)
        XCTAssertEqual(response.duration.total_minutes, 45)

        // 4. Compact JSON includes working_stats, workout_stats, and duration
        let json = analysis.unifiedWorkoutAnalysisJSON()
        XCTAssertTrue(json.contains("\"working_stats\""))
        XCTAssertTrue(json.contains("\"workout_stats\""))
        XCTAssertTrue(json.contains("\"duration\""))
        XCTAssertTrue(json.contains("\"standard\""))
        XCTAssertTrue(json.contains("\"moving_pace\":\"5:38/km\""))
    }

    @MainActor
    func testDisplayDrillToolOutputsPrescriptionAndAttachesCard() async throws {
        let runRecord = makeTestRunRecord(isIndoor: true)
        runRecord.workingAvgCadence = 152
        let chatEngine = AnalystChatEngine(runRecord: runRecord)

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let instructions = chatEngine.buildLeanSystemInstructions()
            XCTAssertTrue(instructions.contains("prescribe_drill"))
            XCTAssertTrue(instructions.contains("executeCoachAction"))
            XCTAssertTrue(instructions.contains("record_feedback"))

            // Verify PreRunDrillId resolution from diverse query formats (both form drills and full sessions)
            XCTAssertEqual(PreRunDrillId.resolve(from: "cadence_pyramids"), .cadencePyramids)
            XCTAssertEqual(PreRunDrillId.resolve(from: "Cadence Pyramids"), .cadencePyramids)
            XCTAssertEqual(PreRunDrillId.resolve(from: "strides"), .strides)
            XCTAssertEqual(PreRunDrillId.resolve(from: "rhythm_intervals"), .rhythmIntervals)
            XCTAssertEqual(PreRunDrillId.resolve(from: "hill_bounds"), .hillBounds)
            XCTAssertEqual(PreRunDrillId.resolve(from: "Zone 1 Active Recovery Flush"), .aerobicFlush)
            XCTAssertEqual(PreRunDrillId.resolve(from: "zone_1_recovery_flush"), .aerobicFlush)
            XCTAssertEqual(PreRunDrillId.resolve(from: "Zone 2 Easy Aerobic Base"), .zone2Run)
            XCTAssertEqual(PreRunDrillId.resolve(from: "Recovery Jog"), .recoveryJog)

            // Test session tools contain ExecuteCoachActionTool
            let session = chatEngine.getOrCreateSession()
            XCTAssertNotNil(session)

            // Test ExecuteCoachActionTool with prescribe_drill for both drills and full recovery sessions
            let coachActionTool = ExecuteCoachActionTool { query in
                switch query.action {
                case .prescribeDrill:
                    let resolved = PreRunDrillId.resolve(from: query.payload ?? "") ?? .cadencePyramids
                    return "{\"status\":\"drill_prescribed\",\"drill_name\":\"\(resolved.title)\"}"
                case .explainMetric:
                    return "{\"status\":\"metric_explained\"}"
                case .exportToWatch:
                    let resolved = PreRunDrillId.resolve(from: query.payload ?? "") ?? .cadencePyramids
                    return "{\"status\":\"exported_to_watch\",\"drill_name\":\"\(resolved.title)\"}"
                case .recordFeedback:
                    return "{\"status\":\"feedback_recorded\",\"message\":\"Subjective feedback recorded successfully.\"}"
                case .updateGoal:
                    return "{\"status\":\"training_goal_updated\"}"
                }
            }

            let drillResult = try await coachActionTool.call(arguments: ExecuteCoachActionQuery(action: .prescribeDrill, payload: "cadence_pyramids"))
            XCTAssertTrue(drillResult.contains("drill_prescribed"))

            let sessionResult = try await coachActionTool.call(arguments: ExecuteCoachActionQuery(action: .prescribeDrill, payload: "Zone 1 Active Recovery Flush"))
            XCTAssertTrue(sessionResult.contains("drill_prescribed"))
            XCTAssertTrue(sessionResult.contains("Aerobic Flush"))

            let feedbackResult = try await coachActionTool.call(arguments: ExecuteCoachActionQuery(action: .recordFeedback, payload: "RPE 8"))
            XCTAssertTrue(feedbackResult.contains("feedback_recorded"))
        }
        #endif
    }

    @MainActor
    func testReadinessPrescriptionAutoBindsSessionCard() async throws {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            let container = try ModelContainer(for: RunRecord.self, configurations: config)
            let context = container.mainContext

            let run = makeTestRunRecord(isIndoor: false)
            context.insert(run)
            try context.save()

            let chatEngine = AnalystChatEngine(runRecord: run)

            // When readiness is checked for a fresh workout under recovery window,
            // prescription is "Zone 1 Active Recovery Flush"
            chatEngine.modelResponder = { (_: String, _: String) async throws -> String in
                // Simulate model responding after querying readiness/schedule and displaying drill
                let query = GetReadinessAndWorkloadQuery()
                let tool = GetReadinessAndWorkloadTool { _ in
                    let analysis = chatEngine.makeAnalysisContext(isSubjectiveDistress: false)
                    let rx = analysis.lockedPrescription
                    if let resolved = PreRunDrillId.resolve(from: rx.nextSessionName) {
                        chatEngine.drillRecommendedThisTurn = resolved
                    }
                    return "{\"readiness_state\":\"productive\",\"second_run_advisable\":false}"
                }
                _ = try await tool.call(arguments: query)
                return "You're cleared for training. Tomorrow's prescription is **Zone 2 Easy Aerobic Maintenance**."
            }

            await chatEngine.sendMessage("Should I run tomorrow, and what kind of session should I focus on?")
            let lastMessage = chatEngine.messages.last
            XCTAssertNotNil(lastMessage)
            let attached = lastMessage?.attachedDrillId
            XCTAssertEqual(attached, PreRunDrillId.zone2Run, "Readiness prescription must auto-bind the workout card to chat")
        }
        #endif
    }

    @MainActor
    func testMarathonGoalRequestUpdatesGoalWithoutDisplayingDrillCardAndDurationIsRealistic() async throws {
        // 1. Verify continuous aerobic sessions have realistic durations (30 min, not 5-10 min)
        XCTAssertEqual(PreRunDrillId.zone2Run.defaultDuration, .thirtyMinutes, "Zone 2 aerobic run must default to 30 minutes, not 5 minutes")
        XCTAssertEqual(PreRunDrillId.aerobicFlush.defaultDuration, .thirtyMinutes, "Aerobic flush must default to 30 minutes")

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let run = makeTestRunRecord(isIndoor: false)
            let chatEngine = AnalystChatEngine(runRecord: run)

            // 2. Verify lean prompt rules and character limit
            let instructions = chatEngine.buildLeanSystemInstructions()
            XCTAssertTrue(instructions.contains("update_goal"), "Prompt must declare update_goal rule")
            XCTAssertTrue(instructions.contains("prescribe_drill"), "Prompt must declare prescribe_drill rule")
            XCTAssertTrue(instructions.contains("export_to_watch"), "Prompt must declare export_to_watch rule")
            XCTAssertTrue(instructions.contains("SPM"), "Prompt must require standard SPM unit notation")
            XCTAssertTrue(instructions.count < 1200, "System instructions must stay strictly under 1,200 chars (was \(instructions.count))")

            // 3. Verify readiness tool provides clean structured facts without leaking internal screaming snake_case
            let query = GetReadinessAndWorkloadQuery()
            let tool = GetReadinessAndWorkloadTool { _ in
                let facts = ReadinessFacts(
                    readiness_state: "productive",
                    acwr: 1.05,
                    streak_days: 2,
                    streak_limit: 4,
                    last_48h_minutes: 60,
                    weekly_avg_minutes: 150,
                    volume_ratio_48h: 0.4,
                    volume_threshold: 0.5,
                    hr_shift_bpm: 2.0,
                    today_minutes: 30,
                    today_target_minutes: 30,
                    today_completion_percent: 100,
                    second_run_advisable: false,
                    limiting_factors: ["daily_volume_satisfied"],
                    experience_level: "Intermediate",
                    training_goal: "Base Building",
                    cadence_floor_spm: 156
                )
                let data = (try? JSONEncoder().encode(facts)) ?? Data()
                return String(data: data, encoding: .utf8) ?? "{}"
            }
            let toolResult = try await tool.call(arguments: query)
            XCTAssertFalse(toolResult.contains("RECOVERY_FLUSH_ZONE_1"), "Must not leak screaming snake_case enum to LLM")
            XCTAssertFalse(toolResult.contains("EASY_AEROBIC_ZONE_2"), "Must not leak screaming snake_case enum to LLM")
            XCTAssertTrue(toolResult.contains("productive"), "Must provide clean structured state")

            // 4. Simulate runner asking for a 6-month marathon schedule
            chatEngine.modelResponder = { (_: String, userQuestion: String) async throws -> String in
                XCTAssertTrue(userQuestion.contains("marathon"))
                // Execute the update_goal action with marathon goal
                let query = ExecuteCoachActionQuery(action: .updateGoal, goal: .marathon)
                let tool = ExecuteCoachActionTool { q in
                    let newGoal = q.goal?.rawValue ?? "Base Building"
                    UserDefaults.standard.set(newGoal, forKey: "trainingGoal")
                    return "{\"goal\":\"\(newGoal)\",\"status\":\"training_goal_updated\"}"
                }
                _ = try await tool.call(arguments: query)
                return "I've locked your goal to **Marathon**! A 6-month marathon preparation is structured across four key periodization phases: Base Building, Aerobic Threshold, Peak Volume, and Taper."
            }

            await chatEngine.sendMessage("I want a tailored training schedule to prepare me for a marathon in 6 months")

            // Goal must be updated to Marathon
            XCTAssertEqual(UserDefaults.standard.string(forKey: "trainingGoal"), "Marathon")

            // Must NOT have attached a drill card
            let lastMessage = chatEngine.messages.last
            XCTAssertNotNil(lastMessage)
            XCTAssertNil(lastMessage?.attachedDrillId, "Race schedule query must not attach an immediate micro drill card")
            XCTAssertTrue(lastMessage?.text.contains("Marathon") == true)
        }
        #endif
    }

    @MainActor
    func testOldestAndFirstHistoricalWorkoutQueryResolution() throws {
        let schema = Schema([RunRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let cal = Calendar.current
        var comps2025 = DateComponents()
        comps2025.year = 2025
        comps2025.month = 3
        comps2025.day = 21
        comps2025.hour = 7
        comps2025.minute = 25
        let dateMarch2025 = try XCTUnwrap(cal.date(from: comps2025))

        var compsSep2026 = DateComponents()
        compsSep2026.year = 2026
        compsSep2026.month = 9
        compsSep2026.day = 30
        compsSep2026.hour = 7
        compsSep2026.minute = 54
        let dateSep2026 = try XCTUnwrap(cal.date(from: compsSep2026))

        var compsOct2026 = DateComponents()
        compsOct2026.year = 2026
        compsOct2026.month = 10
        compsOct2026.day = 19
        compsOct2026.hour = 8
        compsOct2026.minute = 12
        let dateOct2026 = try XCTUnwrap(cal.date(from: compsOct2026))

        // 1. First run logged in Apple Health (March 21, 2025)
        let oldestRun = RunRecord(
            hkWorkoutID: UUID(),
            date: dateMarch2025,
            totalDistanceMeters: 5300,
            duration: 2820,
            rawAvgPace: 532,
            rawAvgHeartRate: 0,
            rawAvgCadence: 0,
            workingAvgPace: 532,
            workingAvgCadence: 0,
            workingAvgHeartRate: 0,
            isIndoor: false,
            paceCV: 0.04,
            paceSlope: 0.0,
            percentZone4: 0.0,
            detectedTypeRaw: "Easy Run"
        )
        context.insert(oldestRun)

        // 2. Fartlek run on September 30, 2026
        let sepRun = RunRecord(
            hkWorkoutID: UUID(),
            date: dateSep2026,
            totalDistanceMeters: 5094,
            duration: 2072,
            rawAvgPace: 406,
            rawAvgHeartRate: 157,
            rawAvgCadence: 152,
            workingAvgPace: 374,
            workingAvgCadence: 152,
            workingAvgHeartRate: 157,
            isIndoor: false,
            paceCV: 0.12,
            paceSlope: -0.01,
            percentZone4: 0.25,
            detectedTypeRaw: "Fartlek"
        )
        context.insert(sepRun)

        // 3. Current active run on October 19, 2026
        let currentRun = RunRecord(
            hkWorkoutID: UUID(),
            date: dateOct2026,
            totalDistanceMeters: 4480,
            duration: 2400,
            rawAvgPace: 536,
            rawAvgHeartRate: 145,
            rawAvgCadence: 154,
            workingAvgPace: 479,
            workingAvgCadence: 154,
            workingAvgHeartRate: 145,
            isIndoor: true,
            paceCV: 0.05,
            paceSlope: 0.0,
            percentZone4: 0.0,
            detectedTypeRaw: "Easy Run"
        )
        context.insert(currentRun)
        try context.save()

        // Test 1: Criteria parsing for chronological superlatives
        let criteriaOldest = HistoricalRunMatcher.HistoricalQueryCriteria.parse(from: "Whats the oldest run I logged on here?")
        XCTAssertEqual(criteriaOldest.metric, .date)
        XCTAssertEqual(criteriaOldest.direction, .ascending)

        let criteriaFirstOutdoor = HistoricalRunMatcher.HistoricalQueryCriteria.parse(from: "What was my first outdoor run?")
        XCTAssertEqual(criteriaFirstOutdoor.environment, .outdoor)
        XCTAssertEqual(criteriaFirstOutdoor.metric, .date)
        XCTAssertEqual(criteriaFirstOutdoor.direction, .ascending)

        // Test 2: findRun returns March 21, 2025 as oldest run
        let matchedOldest = try XCTUnwrap(HistoricalRunMatcher.findRun(matching: "Whats the oldest run I logged on here?", relativeTo: currentRun, in: context))
        XCTAssertEqual(matchedOldest.id, oldestRun.id, "Querying oldest run must resolve to March 21, 2025, not September 30")

        let matchedFirstOutdoor = try XCTUnwrap(HistoricalRunMatcher.findRun(matching: "What was my first outdoor run?", relativeTo: currentRun, in: context))
        XCTAssertEqual(matchedFirstOutdoor.id, oldestRun.id)

        // Test 3: Standalone lookupRun returns full telemetry with year and chronological position
        let lookupResult = HistoricalRunMatcher.lookupRun(matching: "Whats the oldest run I logged on here?", relativeTo: currentRun, in: context)
        XCTAssertTrue(lookupResult.contains("March 21, 2025"), "Lookup telemetry must ground the full year 2025")
        XCTAssertTrue(lookupResult.contains("5.30 km"))
        XCTAssertTrue(lookupResult.contains("8:52/km"))
        XCTAssertTrue(lookupResult.contains("Oldest recorded workout (#1 of 3 total workouts)"))

        // Test 4: listRecentRuns summary contains true lifetime span
        let recentRunsCatalog = HistoricalRunMatcher.listRecentRuns(relativeTo: currentRun, in: context, limit: 2)
        XCTAssertTrue(recentRunsCatalog.contains("March 21, 2025 to"), "Catalog header must display lifetime range")
        XCTAssertTrue(recentRunsCatalog.contains("1 older workouts recorded in athlete database down to first logged run on Friday, March 21, 2025"))
    }

    // MARK: - Oct 20 Incident Regression: Indoor Treadmill Zone 2 Classification

    func testIndoorTreadmillZone2Run_Oct20Incident_ClassifiesAsEasyRun() async {
        let modelManager = ModelManager()
        let now = Date()
        var buckets: [BucketData] = []
        // Authentic 60-minute Zone 2 run on treadmill with belt pause
        for i in 0..<120 {
            let isStop = (i == 40 || i == 80)
            let pace = isStop ? 900.0 : 400.0
            let cad = isStop ? 80.0 : 148.0
            let hr = isStop ? 118.0 : 142.0
            buckets.append(
                BucketData(
                    startTime: now.addingTimeInterval(Double(i * 30)),
                    distanceMeters: isStop ? 0.0 : 75.0,
                    durationSeconds: 30.0,
                    meanPaceSecPerKm: pace,
                    meanCadence: cad,
                    meanHR: hr
                )
            )
        }

        let result = await modelManager.predictRunTypeResult(
            buckets: buckets,
            paceDelta: 12.0,
            hrDelta: 0.0,
            percentZone4: 0.0,
            cadenceDelta: -3.0,
            verticalOscillation: 8.5,
            runnerStage: 1,
            cv: 0.147,
            slope: 0.057,
            durationMinutes: 60.1,
            cadenceCV: 0.038,
            hrCV: 0.045,
            cadenceSlope: 0.0,
            isIndoor: true,
            isGymKit: false
        )

        XCTAssertNotEqual(result.targetClass, "Urban Traffic", "Treadmill run must never classify as Urban Traffic")
        XCTAssertTrue(result.targetClass == "Easy Run" || result.targetClass == "Steady Effort", "Zone 2 treadmill run should classify as Easy Run or Steady Effort, got: \(result.targetClass)")
        XCTAssertFalse(result.isReviewRequired)
        XCTAssertGreaterThanOrEqual(result.confidence, 0.75)
    }
}
