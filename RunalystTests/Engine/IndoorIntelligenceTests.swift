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

        await chatEngine.sendMessage("What did I least improve on?")
        let leastResponse = chatEngine.messages.last?.text ?? ""

        await chatEngine.sendMessage("What did I most improve on?")
        let mostResponse = chatEngine.messages.last?.text ?? ""

        XCTAssertNotEqual(leastResponse, mostResponse, "Least improved and most improved must not be identical")
        XCTAssertTrue(
            leastResponse.localizedCaseInsensitiveContains("recovery") || leastResponse.localizedCaseInsensitiveContains("turnover") || leastResponse.localizedCaseInsensitiveContains("growth") || leastResponse.localizedCaseInsensitiveContains("opportunity"),
            "Least improved should identify recovery intervals or growth opportunities"
        )
        XCTAssertTrue(
            mostResponse.localizedCaseInsensitiveContains("work") || mostResponse.localizedCaseInsensitiveContains("interval") || mostResponse.localizedCaseInsensitiveContains("pace") || mostResponse.localizedCaseInsensitiveContains("win") || mostResponse.localizedCaseInsensitiveContains("strength"),
            "Most improved should highlight work interval execution, speed, or aerobic strength"
        )
    }

    @MainActor
    func testAnalystChatTurnDiversityNoRepeatedCues() async {
        let runRecord = makeTestRunRecord(isIndoor: true)
        runRecord.workingAvgCadence = 156
        runRecord.workingAvgHeartRate = 164

        let chatEngine = AnalystChatEngine(runRecord: runRecord, macroProfile: nil)

        await chatEngine.sendMessage("What should I focus on during my next run?")
        let tip1 = chatEngine.messages.last?.text ?? ""

        await chatEngine.sendMessage("Gimme one good tip for my next run")
        let tip2 = chatEngine.messages.last?.text ?? ""

        XCTAssertNotEqual(tip1, tip2, "Sequential tips across conversation turns must offer distinct cues rather than repeating verbatim")
    }

    @MainActor
    func testAnalystChatConceptualQuestionAnswersDirectlyWithoutJargon() async {
        let runRecord = makeTestRunRecord(isIndoor: true)
        let chatEngine = AnalystChatEngine(runRecord: runRecord)

        await chatEngine.sendMessage("How does arm drive help?")
        let response = chatEngine.messages.last?.text ?? ""

        XCTAssertTrue(
            response.localizedCaseInsensitiveContains("metronome") || response.localizedCaseInsensitiveContains("elbow") || response.localizedCaseInsensitiveContains("swing") || response.localizedCaseInsensitiveContains("arm"),
            "Should directly answer how arm drive works mechanically"
        )
        XCTAssertFalse(response.localizedCaseInsensitiveContains("thoracic alignment"), "Should not use stiff clinical jargon")
        XCTAssertFalse(response.localizedCaseInsensitiveContains("tactical composure"), "Should not use unnatural tactical composure jargon")
        XCTAssertFalse(response.localizedCaseInsensitiveContains("blunt that strain"), "Should not use canned blunt that strain phrase")
        XCTAssertFalse(response.localizedCaseInsensitiveContains("turnover stability"), "Should avoid awkward redundant turnover stability phrasing")
    }

    @MainActor
    func testAnalystChatPerformanceDegradationInquiry() async {
        let runRecord = makeTestRunRecord(isIndoor: true)
        let chatEngine = AnalystChatEngine(runRecord: runRecord)

        await chatEngine.sendMessage("Did you notice any degradation in my performance towards the end of my run?")
        let response = chatEngine.messages.last?.text ?? ""

        XCTAssertTrue(
            response.localizedCaseInsensitiveContains("pace") || response.localizedCaseInsensitiveContains("heart rate") || response.localizedCaseInsensitiveContains("drift") || response.localizedCaseInsensitiveContains("fatigue"),
            "Should answer performance degradation directly"
        )
        XCTAssertFalse(response.localizedCaseInsensitiveContains("tactical composure"), "Should not use canned tactical composure jargon")
        XCTAssertFalse(response.localizedCaseInsensitiveContains("subtle fatigue crept in"), "Should avoid canned clichés")
    }

    @MainActor
    func testAnalystChatCanIRunTodayInformedByReadiness() async {
        let runRecord = makeTestRunRecord(isIndoor: true)
        runRecord.detectedTypeRaw = "Intervals"
        let chatEngine = AnalystChatEngine(runRecord: runRecord)

        await chatEngine.sendMessage("Can i go for a 45min session today?")
        let response = chatEngine.messages.last?.text ?? ""

        XCTAssertTrue(
            response.localizedCaseInsensitiveContains("too long") || response.localizedCaseInsensitiveContains("20") || response.localizedCaseInsensitiveContains("recovery"),
            "Should clarify that 45 minutes is too long for recovery"
        )
        XCTAssertFalse(response.localizedCaseInsensitiveContains("You're not running"), "Must not use harsh scolding tone")
        XCTAssertFalse(response.localizedCaseInsensitiveContains("heart rate is climbing"), "Must not hallucinate present continuous climbing heart rate")
        XCTAssertFalse(response.localizedCaseInsensitiveContains("5:20"), "Must not recommend aggressive fast paces after intervals")
    }

    @MainActor
    func testAnalystChatZone2DurationFollowUpRespectsRecovery() async {
        let runRecord = makeTestRunRecord(isIndoor: true)
        runRecord.detectedTypeRaw = "Intervals"
        let chatEngine = AnalystChatEngine(runRecord: runRecord)

        await chatEngine.sendMessage("Can i go for a 45min session today?")
        await chatEngine.sendMessage("What if i did 45mins zone 2?")
        let response = chatEngine.messages.last?.text ?? ""

        XCTAssertTrue(
            response.localizedCaseInsensitiveContains("Zone 2") && response.localizedCaseInsensitiveContains("too long"),
            "Should acknowledge Zone 2 intensity while explaining 45 min is too long for recovery"
        )
        XCTAssertFalse(response.localizedCaseInsensitiveContains("You're not doing a 45-minute Zone 2"), "Must not use contradictory scolding phrasing")
        XCTAssertTrue(
            response.localizedCaseInsensitiveContains("20") || response.localizedCaseInsensitiveContains("25") || response.localizedCaseInsensitiveContains("walk"),
            "Should recommend capping at 20-25 min or walking"
        )
    }

    @MainActor
    func testAnalystChatHowHardToPushInformedByReadiness() async {
        let runRecord = makeTestRunRecord(isIndoor: true)
        runRecord.detectedTypeRaw = "Intervals"
        let chatEngine = AnalystChatEngine(runRecord: runRecord)

        await chatEngine.sendMessage("How hard should I push?")
        let response = chatEngine.messages.last?.text ?? ""

        XCTAssertTrue(
            response.localizedCaseInsensitiveContains("do not push hard") || response.localizedCaseInsensitiveContains("keep your effort very light") || response.localizedCaseInsensitiveContains("active recovery"),
            "Should directly advise against pushing hard after intervals"
        )
        XCTAssertFalse(response.localizedCaseInsensitiveContains("around 5:20/km feels right"), "Must not recommend hard tempo paces")
        XCTAssertFalse(response.localizedCaseInsensitiveContains("heart rate is climbing"), "Must not hallucinate real-time heart rate spikes")
    }

    @MainActor
    func testAnalystChatReadinessAdjustmentExplanation() async {
        let runRecord = makeTestRunRecord(isIndoor: false)
        let chatEngine = AnalystChatEngine(runRecord: runRecord)

        await chatEngine.sendMessage("If training load is optimal, why was readiness adjusted?")
        let response = chatEngine.messages.last?.text ?? ""

        XCTAssertTrue(
            response.localizedCaseInsensitiveContains("ACWR") || response.localizedCaseInsensitiveContains("training load"),
            "Should mention ACWR or training load"
        )
        XCTAssertTrue(
            response.localizedCaseInsensitiveContains("readiness") && (response.localizedCaseInsensitiveContains("immediate") || response.localizedCaseInsensitiveContains("recovery") || response.localizedCaseInsensitiveContains("acute")),
            "Should explain difference between monthly load balance and acute recovery/triggers"
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
            response.localizedCaseInsensitiveContains("grade") || response.localizedCaseInsensitiveContains("solid") || response.localizedCaseInsensitiveContains("B+") || response.localizedCaseInsensitiveContains("A-"),
            "Should directly provide a performance grade/evaluation"
        )
        XCTAssertFalse(response.localizedCaseInsensitiveContains("NEXT SESSION DIRECTIVE"), "Must never leak internal prompt headers")
        XCTAssertFalse(response.localizedCaseInsensitiveContains("Coaching Context"), "Must never leak context labels")
    }

    @MainActor
    func testAnalystChatCalorieInquiryAnswersMetabolismDirectly() async {
        let runRecord = makeTestRunRecord(isIndoor: true)
        runRecord.detectedTypeRaw = "Intervals"
        let chatEngine = AnalystChatEngine(runRecord: runRecord)

        await chatEngine.sendMessage("That feels very low calorie though")
        let response = chatEngine.messages.last?.text ?? ""

        XCTAssertTrue(
            response.localizedCaseInsensitiveContains("calorie") || response.localizedCaseInsensitiveContains("fat") || response.localizedCaseInsensitiveContains("glycogen") || response.localizedCaseInsensitiveContains("energy"),
            "Should directly answer how recovery and Zone 2 relate to caloric expenditure and metabolism"
        )
        XCTAssertFalse(response.localizedCaseInsensitiveContains("NEXT SESSION DIRECTIVE"), "Must never leak internal prompt headers")
    }

    @MainActor
    func testAnalystChatAdrenalineAndHardPushValidation() async {
        let runRecord = makeTestRunRecord(isIndoor: true)
        runRecord.detectedTypeRaw = "Intervals"
        let chatEngine = AnalystChatEngine(runRecord: runRecord)

        await chatEngine.sendMessage("But I like those hard pushes, it's exhilarating")
        let response = chatEngine.messages.last?.text ?? ""

        XCTAssertTrue(
            response.localizedCaseInsensitiveContains("drive") || response.localizedCaseInsensitiveContains("burn") || response.localizedCaseInsensitiveContains("adapts") || response.localizedCaseInsensitiveContains("rest") || response.localizedCaseInsensitiveContains("recovery"),
            "Should validate runner enthusiasm while explaining supercompensation and recovery"
        )
        XCTAssertFalse(response.localizedCaseInsensitiveContains("NEXT SESSION DIRECTIVE"), "Must never leak internal prompt headers")
    }

    @MainActor
    func testAnalystChatBaseBuildingAndRaceTransitionDirectAnswerWithoutGrade() async {
        let runRecord = makeTestRunRecord(isIndoor: true)
        runRecord.detectedTypeRaw = "Intervals"
        runRecord.workingAvgCadence = 161
        runRecord.workingAvgPace = 362
        let chatEngine = AnalystChatEngine(runRecord: runRecord)

        await chatEngine.sendMessage("Have I built a strong base? Can I shift gears to 5k and 10k training?")
        let response = chatEngine.messages.last?.text ?? ""

        XCTAssertFalse(response.localizedCaseInsensitiveContains("Grade:"), "Must not assign an unsolicited letter grade")
        XCTAssertTrue(
            response.localizedCaseInsensitiveContains("base") || response.localizedCaseInsensitiveContains("5k") || response.localizedCaseInsensitiveContains("solid"),
            "Should directly answer base building readiness"
        )
        XCTAssertTrue(
            response.localizedCaseInsensitiveContains("161") || response.localizedCaseInsensitiveContains("cadence") || response.localizedCaseInsensitiveContains("speed"),
            "Should ground answer in runner's cadence or pacing consistency"
        )
    }

    @MainActor
    func testAnalystChatCrossTrainingBikingEndorsementWithoutRunningCadence() async {
        let runRecord = makeTestRunRecord(isIndoor: true)
        runRecord.detectedTypeRaw = "Intervals"
        runRecord.workingAvgCadence = 156
        runRecord.percentZone4 = 0.73
        let chatEngine = AnalystChatEngine(runRecord: runRecord)

        await chatEngine.sendMessage("Ill just bike today")
        let response = chatEngine.messages.last?.text ?? ""

        XCTAssertTrue(
            response.localizedCaseInsensitiveContains("bike") || response.localizedCaseInsensitiveContains("recovery") || response.localizedCaseInsensitiveContains("impact"),
            "Should endorse biking as a low-impact active recovery option"
        )
        XCTAssertFalse(
            response.localizedCaseInsensitiveContains("SPM"),
            "Must never cite running cadence (SPM) when discussing biking or cross-training"
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
            response.localizedCaseInsensitiveContains("rest") || response.localizedCaseInsensitiveContains("recovery") || response.localizedCaseInsensitiveContains("repair"),
            "Should endorse taking a rest day after a hard workout"
        )
    }

    @MainActor
    func testAnalystChatDistanceInquiryTomorrowRecognizesCapAndRejectsExcessVolume() async {
        let runRecord = makeTestRunRecord(isIndoor: true)
        runRecord.detectedTypeRaw = "Intervals"
        runRecord.percentZone4 = 0.73
        let chatEngine = AnalystChatEngine(runRecord: runRecord)

        await chatEngine.sendMessage("Am I good for a 10k run tomorrow?")
        let response = chatEngine.messages.last?.text ?? ""

        XCTAssertTrue(
            response.localizedCaseInsensitiveContains("too long") || response.localizedCaseInsensitiveContains("cap"),
            "Must explain that 10k exceeds the recovery cap"
        )
        XCTAssertFalse(
            response.localizedCaseInsensitiveContains("10k tomorrow is feasible") || response.localizedCaseInsensitiveContains("10k is doable tomorrow"),
            "Must not contradict recovery by greenlighting a 10k during acute fatigue"
        )
        XCTAssertFalse(
            response.localizedCaseInsensitiveContains("today's easy run"),
            "Must not hallucinate that the runner already did an easy run today"
        )
    }

    @MainActor
    func testAnalystChatClarificationDidNotRunTodayDefusesHallucination() async {
        let runRecord = makeTestRunRecord(isIndoor: true)
        runRecord.detectedTypeRaw = "Intervals"
        let chatEngine = AnalystChatEngine(runRecord: runRecord)

        await chatEngine.sendMessage("I didn’t do an easy run today????")
        let response = chatEngine.messages.last?.text ?? ""

        XCTAssertTrue(
            response.localizedCaseInsensitiveContains("haven't run today") || response.localizedCaseInsensitiveContains("rest"),
            "Must acknowledge the runner hasn't run today and support rest"
        )
    }

    @MainActor
    func testAnalystChatFocusDayTomorrowSaturdayAnswersSpecifically() async {
        let runRecord = makeTestRunRecord(isIndoor: true)
        runRecord.detectedTypeRaw = "Intervals"
        runRecord.percentZone4 = 0.73
        let chatEngine = AnalystChatEngine(runRecord: runRecord)

        await chatEngine.sendMessage("Don’t worry about Sunday. Im focused on tomorrow, Saturday")
        let response = chatEngine.messages.last?.text ?? ""

        XCTAssertTrue(
            response.localizedCaseInsensitiveContains("Saturday") || response.localizedCaseInsensitiveContains("tomorrow"),
            "Must address Saturday specifically"
        )
        XCTAssertTrue(
            response.localizedCaseInsensitiveContains("light") || response.localizedCaseInsensitiveContains("easy") || response.localizedCaseInsensitiveContains("rest"),
            "Must advise light effort or rest for Saturday"
        )
        XCTAssertFalse(
            response.localizedCaseInsensitiveContains("heart rate today"),
            "Must not hallucinate workout telemetry today"
        )
    }

    @MainActor
    func testAnalystChatFocusOnDistanceAfterRecoveryClearanceProvidesStrategyWithoutContradiction() async {
        let runRecord = makeTestRunRecord(isIndoor: true)
        runRecord.detectedTypeRaw = "Intervals"
        runRecord.percentZone4 = 0.73
        let chatEngine = AnalystChatEngine(runRecord: runRecord)

        await chatEngine.sendMessage("How soon can I attempt a 10k run?")
        let response1 = chatEngine.messages.last?.text ?? ""
        XCTAssertTrue(
            response1.localizedCaseInsensitiveContains("too long") || response1.localizedCaseInsensitiveContains("cap"),
            "First turn should advise saving 10k for recovery clearance: \(response1)"
        )

        await chatEngine.sendMessage("If I do run 10k on Sunday, what should I focus on?")
        let response2 = chatEngine.messages.last?.text ?? ""

        XCTAssertFalse(
            response2.localizedCaseInsensitiveContains("too long for Sunday") || response2.localizedCaseInsensitiveContains("30–40-minute") || response2.localizedCaseInsensitiveContains("30-40-minute"),
            "Must not contradict recovery clearance by imposing a 30-40 min recovery cap on Sunday: \(response2)"
        )
        XCTAssertTrue(
            response2.localizedCaseInsensitiveContains("rhythm") || response2.localizedCaseInsensitiveContains("pacing") || response2.localizedCaseInsensitiveContains("cadence") || response2.localizedCaseInsensitiveContains("10k"),
            "Must provide coaching focus on rhythm/pacing/cadence for the 10k: \(response2)"
        )
    }

    @MainActor
    func testAnalystChatCurrentDayInquiriesAnswersDirectlyWithCorrectWeekday() async {
        let runRecord = makeTestRunRecord(isIndoor: true)
        runRecord.detectedTypeRaw = "Intervals"
        runRecord.percentZone4 = 0.73
        let chatEngine = AnalystChatEngine(runRecord: runRecord)

        await chatEngine.sendMessage("What day is it today?")
        let response1 = chatEngine.messages.last?.text ?? ""
        let todayName = RecoveryTimeline.weekday(Date())
        XCTAssertTrue(
            response1.localizedCaseInsensitiveContains("Today is \(todayName)"),
            "Must state current day directly: \(response1)"
        )

        await chatEngine.sendMessage("What day is it tomorrow?")
        let response2 = chatEngine.messages.last?.text ?? ""
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let tomorrowName = RecoveryTimeline.weekday(tomorrow)
        XCTAssertTrue(
            response2.localizedCaseInsensitiveContains("Tomorrow is \(tomorrowName)"),
            "Must state tomorrow directly: \(response2)"
        )
    }

    @MainActor
    func testAnalystChatNegativeMultiDayPlanningSelectsAffirmativeTargetDay() async {
        let runRecord = makeTestRunRecord(isIndoor: true)
        runRecord.date = Date().addingTimeInterval(-24 * 3600)
        runRecord.detectedTypeRaw = "Intervals"
        runRecord.percentZone4 = 0.73
        let chatEngine = AnalystChatEngine(runRecord: runRecord)

        await chatEngine.sendMessage("What if I don't run today or tomorrow? Can I still go for 10k on Sunday?")
        let response = chatEngine.messages.last?.text ?? ""

        XCTAssertTrue(
            response.localizedCaseInsensitiveContains("Yes") || response.localizedCaseInsensitiveContains("good for a 10k") || response.localizedCaseInsensitiveContains("good to"),
            "Must affirmative answer for Sunday: \(response)"
        )
        XCTAssertFalse(
            response.localizedCaseInsensitiveContains("A 10k is too long for Sunday"),
            "Must not contradict recovery clearance by saying 10k is too long for Sunday: \(response)"
        )
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
