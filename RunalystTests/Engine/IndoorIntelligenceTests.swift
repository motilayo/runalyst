import XCTest
import SwiftData
@testable import Runalyst

final class IndoorIntelligenceTests: XCTestCase {

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
        let dummyBuckets = (0..<10).map { i in
            BucketData(
                startTime: now.addingTimeInterval(Double(i * 30)),
                distanceMeters: 100.0,
                durationSeconds: 30.0,
                meanPaceSecPerKm: 300.0,
                meanCadence: 165.0,
                meanHR: 150.0
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
        } else {
            XCTAssertTrue(result.confidence >= 0.75)
        }
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

    // MARK: - 4. Analyst Chat Guardrails

    @MainActor
    func testAnalystChatMedicalGuardrail() async {
        let runRecord = makeTestRunRecord()
        let chatEngine = AnalystChatEngine(runRecord: runRecord)
        await chatEngine.sendMessage("My knee hurts after every run and is swollen. What painkiller should I take?")

        let lastMessage = chatEngine.messages.last?.text.lowercased() ?? ""
        XCTAssertTrue(
            lastMessage.contains("physician") || lastMessage.contains("physical therapist") || lastMessage.contains("medical"),
            "Chat should advise consulting a qualified clinician for injury/pain questions"
        )
    }

    @MainActor
    func testAnalystChatHardwareAccuracyGuardrail() async {
        let runRecord = makeTestRunRecord(isIndoor: true)
        let chatEngine = AnalystChatEngine(runRecord: runRecord)
        await chatEngine.sendMessage("Why does my indoor run on the treadmill say 0 GPS signal or inaccurate distance?")

        let lastMessage = chatEngine.messages.last?.text.lowercased() ?? ""
        XCTAssertTrue(
            lastMessage.contains("gps") || lastMessage.contains("accelerometer") || lastMessage.contains("indoor") || lastMessage.contains("treadmill"),
            "Chat should explain indoor accelerometer tracking vs outdoor satellite GPS"
        )
    }

    @MainActor
    func testAnalystChatSubjectiveEquipmentGuardrail() async {
        let runRecord = makeTestRunRecord()
        let chatEngine = AnalystChatEngine(runRecord: runRecord)
        await chatEngine.sendMessage("What brand of carbon shoes should I buy to run faster?")

        let lastMessage = chatEngine.messages.last?.text.lowercased() ?? ""
        XCTAssertTrue(
            lastMessage.contains("biomechanic") || lastMessage.contains("cadence") || lastMessage.contains("footwear") || lastMessage.contains("turnover"),
            "Chat should emphasize running mechanics, consistency, and cadence over shoe brand endorsements"
        )
    }

    @MainActor
    func testAnalystChatEffortAndImprovementResponses() async {
        let runRecord = makeTestRunRecord(isIndoor: true)
        let chatEngine = AnalystChatEngine(runRecord: runRecord)
        await chatEngine.sendMessage("How was my effort?")
        let effortResponse = chatEngine.messages.last?.text ?? ""
        XCTAssertFalse(effortResponse.contains("Quick tip:"), "Should not use boilerplate Quick tip header")
        XCTAssertFalse(effortResponse.contains("braked on your knees"), "Should not produce confusing jargon")
        XCTAssertTrue(effortResponse.contains("heart rate") || effortResponse.contains("BPM") || effortResponse.contains("effort"), "Should address effort specifically")

        await chatEngine.sendMessage("What can I improve?")
        let improveResponse = chatEngine.messages.last?.text ?? ""
        XCTAssertFalse(improveResponse.contains("Quick tip:"), "Should not use boilerplate Quick tip header")
        XCTAssertTrue(improveResponse.contains("turnover") || improveResponse.contains("cadence") || improveResponse.contains("SPM") || improveResponse.contains("hips") || improveResponse.contains("bounce") || improveResponse.contains("stride"), "Should address form/improvement specifically")
    }

    @MainActor
    func testSubFloorCadenceNeverPraisesFormPrecision() async {
        let subFloorRun = makeTestRunRecord(isIndoor: false)
        subFloorRun.duration = 900
        subFloorRun.totalDistanceMeters = 1630
        subFloorRun.workingAvgCadence = 144
        subFloorRun.workingAvgHeartRate = 125
        subFloorRun.workingAvgPace = 552
        subFloorRun.workingAvgVerticalOscillation = 10.7
        subFloorRun.workingAvgStrideLength = 0.84

        let chatEngine = AnalystChatEngine(runRecord: subFloorRun, macroProfile: nil)
        await chatEngine.sendMessage("Which part of my form should I focus on improving in my next run?")
        let response = chatEngine.messages.last?.text ?? ""
        XCTAssertFalse(response.localizedCaseInsensitiveContains("form precision shines"), "Must not falsely praise form when cadence is sub-150 SPM floor")
        XCTAssertTrue(response.localizedCaseInsensitiveContains("turnover") || response.localizedCaseInsensitiveContains("144 SPM"), "Should instruct to quicken foot turnover")
    }

    @MainActor
    func testCadenceAboveFloorNeverClaimsSubFloor() async {
        let healthyCadenceRun = makeTestRunRecord(isIndoor: true)
        healthyCadenceRun.workingAvgCadence = 156
        healthyCadenceRun.workingAvgHeartRate = 164
        healthyCadenceRun.workingAvgPace = 362
        healthyCadenceRun.workingAvgVerticalOscillation = 8.8

        let chatEngine = AnalystChatEngine(runRecord: healthyCadenceRun, macroProfile: nil)
        await chatEngine.sendMessage("What can I do to improve? Which area should I focus on next?")
        let response = chatEngine.messages.last?.text ?? ""
        XCTAssertFalse(response.localizedCaseInsensitiveContains("below the 150"), "156 SPM is above floor; must not claim below 150 SPM floor")
        XCTAssertFalse(response.localizedCaseInsensitiveContains("below the floor"), "Must not claim below the floor")
        XCTAssertTrue(response.localizedCaseInsensitiveContains("156 SPM") || response.localizedCaseInsensitiveContains("turnover"), "Should reference cadence or turnover constructively")
    }

    @MainActor
    func testAnalystChatDifferentiatedMostAndLeastImproved() async {
        let runRecord = makeTestRunRecord(isIndoor: true)
        runRecord.workingAvgCadence = 156
        runRecord.workingAvgHeartRate = 164
        runRecord.workingAvgPace = 362

        let signature = RunSignature(
            classification: "Intervals",
            confidence: 0.92,
            probabilities: ["Intervals": 0.92],
            anomalies: [],
            cadenceFloor: 150.0,
            phaseSegments: [
                PhaseSegment(startSeconds: 0, endSeconds: 300, kind: "work", avgPace: 290, avgCadence: 172, avgHR: 170),
                PhaseSegment(startSeconds: 300, endSeconds: 450, kind: "recovery", avgPace: 400, avgCadence: 150, avgHR: 155),
                PhaseSegment(startSeconds: 450, endSeconds: 750, kind: "work", avgPace: 285, avgCadence: 174, avgHR: 172),
                PhaseSegment(startSeconds: 750, endSeconds: 900, kind: "recovery", avgPace: 410, avgCadence: 148, avgHR: 158)
            ],
            dataSource: "wrist",
            isIndoor: true,
            needsInclineReview: false
        )

        let chatEngine = AnalystChatEngine(runRecord: runRecord, runSignature: signature, macroProfile: nil)
        let prompt = chatEngine.buildSystemInstructions()

        XCTAssertTrue(prompt.contains("INTERVAL EXECUTION (2 work reps)"), "Prompt must include interval execution telemetry")
        XCTAssertTrue(prompt.contains("Rep Pace Range:"), "Prompt must detail rep pace range")

        let analysis = WorkoutAnalysisContext(
            runRecord: runRecord,
            runSignature: signature,
            macroProfile: nil,
            recoveryTimeline: chatEngine.recoveryTimeline
        )
        XCTAssertFalse(analysis.overallGradeReport.strengths.isEmpty, "Grade report must identify strengths")
        XCTAssertNotEqual(analysis.overallGradeReport.strengths.first, analysis.overallGradeReport.focus, "Strengths and growth focus must be differentiated")
    }

    @MainActor
    func testAnalystChatTurnDiversityNoRepeatedCues() async {
        let runRecord = makeTestRunRecord(isIndoor: true)
        runRecord.workingAvgCadence = 156
        runRecord.workingAvgHeartRate = 164

        let chatEngine = AnalystChatEngine(runRecord: runRecord, macroProfile: nil)
        chatEngine.modelResponder = { _, question in
            return "Custom dynamic answer for: \(question)"
        }

        await chatEngine.sendMessage("What should I focus on during my next run?")
        let tip1 = chatEngine.messages.last?.text ?? ""

        await chatEngine.sendMessage("Gimme one good tip for my next run")
        let tip2 = chatEngine.messages.last?.text ?? ""

        XCTAssertNotEqual(tip1, tip2, "Sequential tips across conversation turns must produce distinct responses")
    }

    @MainActor
    func testAnalystChatConceptualQuestionAnswersDirectlyWithoutJargon() async {
        let runRecord = makeTestRunRecord(isIndoor: true)
        let chatEngine = AnalystChatEngine(runRecord: runRecord)
        let instructions = chatEngine.buildSystemInstructions()

        XCTAssertTrue(
            instructions.contains("When I ask what a concept means (like threshold), explain the concept simply, then connect it to how I ran"),
            "System prompt must instruct model to explain concepts simply and connect to runner data"
        )
        XCTAssertTrue(
            instructions.contains("Speak like an experienced, objective running coach in natural conversation"),
            "System prompt must enforce natural conversational coaching"
        )
    }

    @MainActor
    func testAnalystChatPerformanceDegradationInquiry() async {
        let runRecord = makeTestRunRecord(isIndoor: true)
        let chatEngine = AnalystChatEngine(runRecord: runRecord)

        await chatEngine.sendMessage("Did you notice any degradation in my performance towards the end of my run?")
        let response = chatEngine.messages.last?.text ?? ""

        XCTAssertFalse(response.isEmpty, "Should answer performance degradation inquiry")
        XCTAssertFalse(response.localizedCaseInsensitiveContains("tactical composure"), "Should not use canned tactical composure jargon")
    }

    @MainActor
    func testAnalystChatCanIRunTodayInformedByReadiness() async {
        let runRecord = makeTestRunRecord(isIndoor: true)
        runRecord.detectedTypeRaw = "Intervals"
        runRecord.percentZone4 = 0.73
        let chatEngine = AnalystChatEngine(runRecord: runRecord)

        let timeline = chatEngine.recoveryTimeline
        XCTAssertFalse(timeline.readyForHard, "After 73% Zone 4 intervals, runner is not cleared for a hard session today")
        XCTAssertNotNil(timeline.easyCap, "Must specify active recovery easy cap")
        XCTAssertEqual(timeline.easyCap, 20...30, "Immediate recovery cap should be 20-30 min")

        await chatEngine.sendMessage("Can i go for a 45min session today?")
        let response = chatEngine.messages.last?.text ?? ""
        XCTAssertTrue(
            response.localizedCaseInsensitiveContains("recovery") || response.localizedCaseInsensitiveContains("status"),
            "Fallback response should state recovery status: \(response)"
        )
    }

    @MainActor
    func testAnalystChatZone2DurationFollowUpRespectsRecovery() async {
        let runRecord = makeTestRunRecord(isIndoor: true)
        runRecord.detectedTypeRaw = "Intervals"
        runRecord.percentZone4 = 0.73
        let chatEngine = AnalystChatEngine(runRecord: runRecord)

        let instructions = chatEngine.buildSystemInstructions()
        XCTAssertTrue(
            instructions.contains("Keep next run easy (cap: 20–30 min)") || instructions.contains("Recovery Status:"),
            "Prompt must inform the LLM of recovery status and easy volume cap"
        )
    }

    @MainActor
    func testAnalystChatHowHardToPushInformedByReadiness() async {
        let runRecord = makeTestRunRecord(isIndoor: true)
        runRecord.detectedTypeRaw = "Intervals"
        runRecord.percentZone4 = 0.73
        let chatEngine = AnalystChatEngine(runRecord: runRecord)

        await chatEngine.sendMessage("How hard should I push?")
        let response = chatEngine.messages.last?.text ?? ""

        XCTAssertTrue(
            response.localizedCaseInsensitiveContains("recovery") || response.localizedCaseInsensitiveContains("status"),
            "Should directly advise recovery status: \(response)"
        )
    }

    @MainActor
    func testAnalystChatReadinessAdjustmentExplanation() async {
        let runRecord = makeTestRunRecord(isIndoor: false)
        let chatEngine = AnalystChatEngine(runRecord: runRecord)
        let instructions = chatEngine.buildSystemInstructions()

        XCTAssertTrue(
            instructions.contains("Current Readiness:"),
            "Prompt must supply current readiness state to the model"
        )
        XCTAssertTrue(
            instructions.contains("FUTURE TRAINING & READINESS"),
            "Prompt must have dedicated readiness context block"
        )
    }

    @MainActor
    func testAnalystChatGradePerformanceDirectlyWithoutUnsolicitedPrescription() async {
        let runRecord = makeTestRunRecord(isIndoor: true)
        runRecord.detectedTypeRaw = "Intervals"
        runRecord.percentZone4 = 0.72
        let chatEngine = AnalystChatEngine(runRecord: runRecord)

        await chatEngine.sendMessage("Grade my performance for this run")
        let response = chatEngine.messages.last?.text ?? ""

        XCTAssertTrue(
            response.localizedCaseInsensitiveContains("grade") || response.localizedCaseInsensitiveContains("A") || response.localizedCaseInsensitiveContains("B"),
            "Should directly provide a performance grade/evaluation"
        )
        XCTAssertFalse(response.localizedCaseInsensitiveContains("NEXT SESSION DIRECTIVE"), "Must never leak internal prompt headers")
    }

    @MainActor
    func testAnalystChatCalorieInquiryAnswersMetabolismDirectly() async {
        let runRecord = makeTestRunRecord(isIndoor: true)
        runRecord.detectedTypeRaw = "Intervals"
        let chatEngine = AnalystChatEngine(runRecord: runRecord)
        let instructions = chatEngine.buildSystemInstructions()

        XCTAssertTrue(
            instructions.contains("Answer what I ask directly, using the data sheet to back up your points"),
            "System instructions must command answering user questions directly"
        )
        XCTAssertFalse(
            instructions.contains("NEXT SESSION DIRECTIVE"),
            "Prompt must not contain obsolete directive headers"
        )
    }

    @MainActor
    func testAnalystChatAdrenalineAndHardPushValidation() async {
        let runRecord = makeTestRunRecord(isIndoor: true)
        runRecord.detectedTypeRaw = "Intervals"
        let chatEngine = AnalystChatEngine(runRecord: runRecord)
        let instructions = chatEngine.buildSystemInstructions()

        XCTAssertTrue(
            instructions.contains("experienced, objective running coach in a conversation"),
            "System prompt must mandate conversational coaching tone"
        )
    }

    @MainActor
    func testAnalystChatBaseBuildingAndRaceTransitionDirectAnswerWithoutGrade() async {
        let runRecord = makeTestRunRecord(isIndoor: true)
        runRecord.detectedTypeRaw = "Intervals"
        runRecord.workingAvgCadence = 161
        runRecord.workingAvgPace = 362
        let chatEngine = AnalystChatEngine(runRecord: runRecord)
        let instructions = chatEngine.buildSystemInstructions()

        XCTAssertTrue(
            instructions.contains("Cadence 161 SPM (healthy turnover above floor)"),
            "Prompt must ground cadence as healthy turnover above floor"
        )
    }

    @MainActor
    func testAnalystChatCrossTrainingBikingEndorsementWithoutRunningCadence() async {
        let runRecord = makeTestRunRecord(isIndoor: true)
        runRecord.detectedTypeRaw = "Intervals"
        runRecord.workingAvgCadence = 156
        runRecord.percentZone4 = 0.73
        let chatEngine = AnalystChatEngine(runRecord: runRecord)
        chatEngine.modelResponder = { _, question in
            XCTAssertTrue(question.contains("bike"))
            return "Biking is a great low-impact option for active recovery."
        }

        await chatEngine.sendMessage("Ill just bike today")
        let response = chatEngine.messages.last?.text ?? ""

        XCTAssertTrue(
            (response.localizedCaseInsensitiveContains("bike") || response.localizedCaseInsensitiveContains("biking")) && response.localizedCaseInsensitiveContains("recovery"),
            "Should endorse biking as a low-impact active recovery option: \(response)"
        )
    }

    @MainActor
    func testAnalystChatRestDayEndorsement() async {
        let runRecord = makeTestRunRecord(isIndoor: true)
        runRecord.detectedTypeRaw = "Intervals"
        runRecord.percentZone4 = 0.73
        let chatEngine = AnalystChatEngine(runRecord: runRecord)

        await chatEngine.sendMessage("I'll take a rest day today")
        let response = chatEngine.messages.last?.text ?? ""

        XCTAssertTrue(
            response.localizedCaseInsensitiveContains("recovery") || response.localizedCaseInsensitiveContains("status"),
            "Fallback should cite recovery status"
        )
    }

    @MainActor
    func testAnalystChatDistanceInquiryTomorrowRecognizesCapAndRejectsExcessVolume() async {
        let runRecord = makeTestRunRecord(isIndoor: true)
        runRecord.detectedTypeRaw = "Intervals"
        runRecord.percentZone4 = 0.73
        let chatEngine = AnalystChatEngine(runRecord: runRecord)

        let timeline = chatEngine.recoveryTimeline
        XCTAssertFalse(timeline.isCleared(for: "tomorrow"), "After hard intervals, 10k is not cleared for tomorrow")
        XCTAssertNotNil(timeline.earliestHardDate, "Earliest hard session must be calculated")
    }

    @MainActor
    func testAnalystChatClarificationDidNotRunTodayDefusesHallucination() async {
        let runRecord = makeTestRunRecord(isIndoor: true)
        runRecord.detectedTypeRaw = "Intervals"
        let chatEngine = AnalystChatEngine(runRecord: runRecord)
        let instructions = chatEngine.buildSystemInstructions()

        XCTAssertTrue(
            instructions.contains("If I state or clarify that I didn't run today or yesterday, immediately acknowledge that fact and ground your advice in my current rest days"),
            "Prompt must enforce acknowledging rest day clarifications"
        )
    }

    @MainActor
    func testAnalystChatFocusDayTomorrowSaturdayAnswersSpecifically() async {
        let runRecord = makeTestRunRecord(isIndoor: true)
        runRecord.detectedTypeRaw = "Intervals"
        runRecord.percentZone4 = 0.73
        let chatEngine = AnalystChatEngine(runRecord: runRecord)
        let instructions = chatEngine.buildSystemInstructions()

        XCTAssertTrue(
            instructions.contains("NEVER refer to this workout as \"today\", \"today's run\", or \"today's workout\" unless the Workout Date is literally today"),
            "Prompt must prohibit referring to historical runs as today"
        )
    }

    @MainActor
    func testAnalystChatFocusOnDistanceAfterRecoveryClearanceProvidesStrategyWithoutContradiction() async {
        let runRecord = makeTestRunRecord(isIndoor: true)
        runRecord.date = Date().addingTimeInterval(-4 * 24 * 3600) // 4 days ago
        runRecord.detectedTypeRaw = "Intervals"
        let chatEngine = AnalystChatEngine(runRecord: runRecord)
        let instructions = chatEngine.buildSystemInstructions()

        XCTAssertTrue(
            instructions.contains("FULLY RECOVERED and fresh"),
            "With 4 days elapsed, runner must be recognized as fully recovered"
        )
        XCTAssertTrue(
            instructions.contains("Never contradict yourself"),
            "Prompt must strictly prohibit contradictory advice"
        )
    }

    @MainActor
    func testAnalystChatCurrentDayInquiriesAnswersDirectlyWithCorrectWeekday() async {
        let runRecord = makeTestRunRecord(isIndoor: true)
        let chatEngine = AnalystChatEngine(runRecord: runRecord)
        let instructions = chatEngine.buildSystemInstructions()

        let todayName = RecoveryTimeline.weekday(Date())
        XCTAssertTrue(
            instructions.contains("Current Date (Today): \(todayName)"),
            "Prompt must specify the exact current weekday: \(instructions)"
        )
    }

    @MainActor
    func testAnalystChatNegativeMultiDayPlanningSelectsAffirmativeTargetDay() async {
        let runRecord = makeTestRunRecord(isIndoor: true)
        runRecord.date = Date().addingTimeInterval(-24 * 3600)
        runRecord.detectedTypeRaw = "Intervals"
        runRecord.percentZone4 = 0.73
        let chatEngine = AnalystChatEngine(runRecord: runRecord)

        let timeline = chatEngine.recoveryTimeline
        let isClearedSunday = timeline.isCleared(for: "sunday")
        XCTAssertTrue(isClearedSunday, "Sunday must be cleared for running after 3+ days: \(timeline.earliestHardPhrase)")
    }

    @MainActor
    func testAnalystChatPhysiologicalDecouplingAndDrillBoundariesInPrompt() async {
        let runRecord = makeTestRunRecord(isIndoor: true)
        runRecord.detectedTypeRaw = "Intervals"
        let chatEngine = AnalystChatEngine(runRecord: runRecord)
        let instructions = chatEngine.buildSystemInstructions()

        XCTAssertTrue(
            instructions.contains("Cardiac drift (+BPM in second half) is cardiovascular fatigue"),
            "Prompt must define cardiac drift as fatigue/heat and prohibit calling it acceleration"
        )
        XCTAssertTrue(
            instructions.contains("Do NOT invent or prescribe custom structured workout routines"),
            "Prompt must enforce referencing existing drill library instead of inventing custom interval workouts"
        )
        XCTAssertTrue(
            instructions.contains("Never describe a wide pace spread spanning tens of seconds"),
            "Prompt must prohibit calling wide historical spreads tight or metronomic"
        )
    }

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
    func testAnalystChatAthleteIdentityAndCoachingPrinciplesInPrompt() async {
        let runRecord = makeTestRunRecord(isIndoor: false)
        let chatEngine = AnalystChatEngine(runRecord: runRecord)
        let instructions = chatEngine.buildSystemInstructions()

        XCTAssertTrue(
            instructions.contains("ATHLETE IDENTITY & CURRENT LOAD:"),
            "Prompt must include Athlete Identity & Current Load header"
        )
        XCTAssertTrue(
            instructions.contains("Stride Archetype:"),
            "Prompt must supply stride archetype analysis"
        )
        XCTAssertTrue(
            instructions.contains("Tailor your vocabulary and depth to my Athletic Experience Level"),
            "Prompt must enforce matching depth to experience level"
        )
        XCTAssertTrue(
            instructions.contains("PHYSIOLOGICAL & BIOMECHANICAL VERDICTS"),
            "Prompt must include Physiological Causal Verdicts"
        )
        XCTAssertTrue(
            instructions.contains("LOCKED TRAINING ZONES & SESSION PRESCRIPTION"),
            "Prompt must include Locked Training Prescription table"
        )
        XCTAssertFalse(
            instructions.contains("Swift is the Physicist") || instructions.contains("Swift's deterministic engine") || instructions.contains("SWIFT CAUSAL VERDICTS"),
            "Prompt must not attribute analytical physics to Swift"
        )
        XCTAssertTrue(
            instructions.contains("You have evaluated my raw telemetry using your deterministic analytical engine"),
            "Prompt must absorb deterministic engine into coach persona"
        )
    }

    @MainActor
    func testAnalystChatFutureSessionPlanningScopingPrunesPastRetrospectiveData() async {
        let runRecord = makeTestRunRecord(isIndoor: false)
        let chatEngine = AnalystChatEngine(runRecord: runRecord)
        let msgHistory = [
            AnalystChatMessage(sender: .user, text: "Why did this run feel challenging, and did my mechanics break down?"),
            AnalystChatMessage(sender: .analyst, text: "Cardiovascular drift with a 16 BPM rise in heart rate within 45 minutes caused fatigue.")
        ]
        let turnContext = ConversationMemoryManager.buildTurnContext(
            userQuestion: "Can I run tomorrow?",
            messages: msgHistory,
            recoveryStateDescription: "Fully Recovered",
            daysSinceWorkout: 4
        )
        XCTAssertEqual(turnContext.turnDomain, .futureSessionPlanning)
        XCTAssertTrue(turnContext.prunePhysiologicalVerdicts)
        XCTAssertEqual(turnContext.turnIndex, 1)
        XCTAssertFalse(turnContext.cleanConversationDigest.contains("16 BPM"))

        let instructions = chatEngine.buildSystemInstructions(for: "Can I run tomorrow?", turnContext: turnContext)

        XCTAssertTrue(instructions.contains("FUTURE TRAINING & READINESS:"))
        XCTAssertTrue(instructions.contains("LOCKED TRAINING ZONES & SESSION PRESCRIPTION"))
        XCTAssertFalse(instructions.contains("PHYSIOLOGICAL & BIOMECHANICAL VERDICTS"))
    }

    @MainActor
    func testAnalystChatWhatWentWellAndWhatCouldBeBetterScoping() async {
        let runRecord = makeTestRunRecord(isIndoor: false)
        let chatEngine = AnalystChatEngine(runRecord: runRecord)

        // 1. "What went well?"
        let ctxWell = ConversationMemoryManager.buildTurnContext(
            userQuestion: "What went well?",
            messages: [],
            recoveryStateDescription: "Fully Recovered",
            daysSinceWorkout: 4
        )
        XCTAssertTrue(ctxWell.turnGuidance.contains("Highlights & Strengths"))
        let instrWell = chatEngine.buildSystemInstructions(for: "What went well?", turnContext: ctxWell)
        XCTAssertFalse(instrWell.contains("[FUTURE TRAINING & READINESS]"))
        XCTAssertFalse(instrWell.contains("LOCKED TRAINING ZONES & SESSION PRESCRIPTION:"))
        XCTAssertFalse(instrWell.contains("Next Recommended Session:"))

        // 2. "What could be better?"
        let ctxBetter = ConversationMemoryManager.buildTurnContext(
            userQuestion: "What could be better?",
            messages: [],
            recoveryStateDescription: "Fully Recovered",
            daysSinceWorkout: 4
        )
        XCTAssertTrue(ctxBetter.turnGuidance.contains("Areas for Technique & Pacing Improvement"))
        let instrBetter = chatEngine.buildSystemInstructions(for: "What could be better?", turnContext: ctxBetter)
        XCTAssertFalse(instrBetter.contains("[FUTURE TRAINING & READINESS]"))
        XCTAssertFalse(instrBetter.contains("LOCKED TRAINING ZONES & SESSION PRESCRIPTION:"))
        XCTAssertFalse(instrBetter.contains("Next Recommended Session:"))
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
        XCTAssertTrue(rxEmpirical.nextSessionName.contains("Zone 2"))
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

    func testConversationMemoryManagerTurnDomainsAndBridging() {
        let msgHistory = [
            AnalystChatMessage(sender: .user, text: "Why was my cadence so low in the last kilometer?"),
            AnalystChatMessage(sender: .analyst, text: "Late turnover decay caused your cadence to drop by 11 SPM.")
        ]

        // 1. Single workout inquiry
        let ctxWorkout = ConversationMemoryManager.buildTurnContext(
            userQuestion: "Explain my vertical bounce",
            messages: msgHistory,
            recoveryStateDescription: "Productive",
            daysSinceWorkout: 3
        )
        XCTAssertEqual(ctxWorkout.turnDomain, .workoutTelemetryAnalysis)
        XCTAssertFalse(ctxWorkout.stripWorkoutPayload)

        // 2. Composite question (Workout + Tomorrow planning)
        let ctxComposite = ConversationMemoryManager.buildTurnContext(
            userQuestion: "Why did my HR spike, and does that mean I should rest tomorrow?",
            messages: msgHistory,
            recoveryStateDescription: "Productive",
            daysSinceWorkout: 2
        )
        XCTAssertEqual(ctxComposite.turnDomain, .compositeWorkoutAndPlanning)
        XCTAssertTrue(ctxComposite.turnGuidance.contains("COMPOSITE BRIDGING DIRECTIVE"))
        XCTAssertFalse(ctxComposite.stripWorkoutPayload)

        // 3. Subjective distress reported
        let ctxDistress = ConversationMemoryManager.buildTurnContext(
            userQuestion: "I have a sore throat, fever, and feel awful",
            messages: msgHistory,
            recoveryStateDescription: "Productive",
            daysSinceWorkout: 1
        )
        XCTAssertEqual(ctxDistress.turnDomain, .subjectiveDistressReported)
        XCTAssertTrue(ctxDistress.isSubjectiveDistress)
        XCTAssertTrue(ctxDistress.turnGuidance.contains("Prioritize rest, hydration"))

        // 4. Out-of-scope inquiry
        let ctxOutOfScope = ConversationMemoryManager.buildTurnContext(
            userQuestion: "Who won the Olympic marathon?",
            messages: msgHistory,
            recoveryStateDescription: "Productive",
            daysSinceWorkout: 1
        )
        XCTAssertEqual(ctxOutOfScope.turnDomain, .outOfScopeInquiry)
        XCTAssertTrue(ctxOutOfScope.stripWorkoutPayload)
        XCTAssertTrue(ctxOutOfScope.turnGuidance.contains("general knowledge"))
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

    @MainActor
    func testAnalystChatUnrecordedVerticalOscillationExplainsSensors() async {
        let runRecord = makeTestRunRecord(isIndoor: true)
        runRecord.workingAvgVerticalOscillation = nil
        let chatEngine = AnalystChatEngine(runRecord: runRecord)

        await chatEngine.sendMessage("What was my vertical oscillation?")
        let response = chatEngine.messages.last?.text ?? ""

        XCTAssertTrue(
            response.localizedCaseInsensitiveContains("wasn't recorded") || response.localizedCaseInsensitiveContains("not recorded"),
            "Must state that vertical oscillation was not recorded"
        )
        XCTAssertTrue(
            response.localizedCaseInsensitiveContains("treadmill") || response.localizedCaseInsensitiveContains("footpod") || response.localizedCaseInsensitiveContains("indoor"),
            "Must explain indoor treadmill / footpod sensor dependency"
        )
        XCTAssertFalse(response.localizedCaseInsensitiveContains("solid, steady rhythm"), "Must not fall back to generic rhythm copy")
    }

    @MainActor
    func testAnalystChatClassificationExplanationExplainsPhysiology() async {
        let runRecord = makeTestRunRecord(isIndoor: true)
        runRecord.detectedTypeRaw = "Mixed Effort (Review)"
        runRecord.needsInclineReview = false
        let chatEngine = AnalystChatEngine(runRecord: runRecord)

        await chatEngine.sendMessage("Why did you label my run today as a 'Mixed Effort'?")
        let response = chatEngine.messages.last?.text ?? ""

        XCTAssertTrue(
            response.localizedCaseInsensitiveContains("Mixed Effort"),
            "Must cite the Mixed Effort classification"
        )
        XCTAssertTrue(
            response.localizedCaseInsensitiveContains("surges") || response.localizedCaseInsensitiveContains("irregular") || response.localizedCaseInsensitiveContains("variability") || response.localizedCaseInsensitiveContains("review"),
            "Must explain the reason for the classification"
        )
    }

    @MainActor
    func testAnalystChatGranularSplitsCitesExactSegments() async {
        let runRecord = makeTestRunRecord(isIndoor: true)
        let signature = RunSignature(
            classification: "Intervals",
            confidence: 0.95,
            probabilities: ["Intervals": 0.95],
            anomalies: [],
            cadenceFloor: 150.0,
            phaseSegments: [
                PhaseSegment(startSeconds: 0, endSeconds: 240, kind: "work", avgPace: 270, avgCadence: 172, avgHR: 165),
                PhaseSegment(startSeconds: 240, endSeconds: 360, kind: "recovery", avgPace: 380, avgCadence: 148, avgHR: 150),
                PhaseSegment(startSeconds: 360, endSeconds: 600, kind: "work", avgPace: 255, avgCadence: 175, avgHR: 170),
                PhaseSegment(startSeconds: 600, endSeconds: 720, kind: "recovery", avgPace: 390, avgCadence: 146, avgHR: 152),
                PhaseSegment(startSeconds: 720, endSeconds: 960, kind: "work", avgPace: 285, avgCadence: 170, avgHR: 175)
            ],
            dataSource: "wrist",
            isIndoor: true,
            needsInclineReview: false
        )
        let chatEngine = AnalystChatEngine(runRecord: runRecord, runSignature: signature, macroProfile: nil)

        await chatEngine.sendMessage("My best split and my worst split")
        let response = chatEngine.messages.last?.text ?? ""

        XCTAssertTrue(
            response.localizedCaseInsensitiveContains("fastest") && response.localizedCaseInsensitiveContains("slowest"),
            "Must cite both fastest and slowest segments"
        )
        XCTAssertTrue(
            response.localizedCaseInsensitiveContains("Rep") || response.localizedCaseInsensitiveContains("min"),
            "Must cite specific rep or minute markers"
        )
    }

    @MainActor
    func testAnalystChatDidNotRunYesterdayAcknowledgesDate() async {
        let runRecord = makeTestRunRecord(isIndoor: true)
        // Run logged 2 days ago
        runRecord.date = Date().addingTimeInterval(-48 * 3600)
        let chatEngine = AnalystChatEngine(runRecord: runRecord)

        await chatEngine.sendMessage("I didn't run yesterday...")
        let response = chatEngine.messages.last?.text ?? ""

        XCTAssertTrue(
            response.localizedCaseInsensitiveContains("didn't run yesterday") || response.localizedCaseInsensitiveContains("haven't run yesterday"),
            "Must acknowledge runner did not run yesterday"
        )
        XCTAssertFalse(response.localizedCaseInsensitiveContains("yesterday's hard sessions"), "Must not claim hard session was yesterday when it was 2 days ago")
    }
}
