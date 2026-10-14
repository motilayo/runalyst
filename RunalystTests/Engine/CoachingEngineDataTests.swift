import XCTest
import SwiftData
#if canImport(FoundationModels)
import FoundationModels
#endif
@testable import Runalyst

@MainActor
final class CoachingEngineDataTests: XCTestCase {
    func testRunDataForAIInitialization() {
        let runData = RunDataForAI(
            workoutType: "Tempo Run",
            runnerGoal: "Sub-20 5K",
            directiveContext: "The runner is overstriding (low cadence).",
            paceContext: "Current: 5:00/km, Baseline: 5:15/km",
            hrContext: "Current: 155 BPM, Baseline: 150 BPM",
            cadenceContext: "Current: 148 SPM, Baseline: 156 SPM",
            zone4Context: "20% in Zone 4",
            cvContext: "0.045",
            slopeContext: "0.012",
            intervalCadence: "162",
            recoveryCadence: "150"
        )

        XCTAssertEqual(runData.workoutType, "Tempo Run")
        XCTAssertEqual(runData.runnerGoal, "Sub-20 5K")
        XCTAssertEqual(runData.intervalCadence, "162")
        XCTAssertEqual(runData.recoveryCadence, "150")
        XCTAssertTrue(runData.directiveContext.contains("overstriding"))
        XCTAssertTrue(runData.paceContext.contains("5:00/km"))
        XCTAssertTrue(runData.hrContext.contains("155 BPM"))
        XCTAssertTrue(runData.cadenceContext.contains("148 SPM"))
        XCTAssertTrue(runData.zone4Context.contains("20%"))
        XCTAssertTrue(runData.cvContext.contains("0.045"))
        XCTAssertTrue(runData.slopeContext.contains("0.012"))
    }

    func testAggregateRunDataForAIInitialization() {
        let aggData = AggregateRunDataForAI(
            paceContext: "5:10/km",
            hrContext: "148 BPM",
            cadenceContext: "162 SPM",
            zone4Context: "15%",
            cvContext: "0.035",
            slopeContext: "-0.010",
            stageContext: "Stage 2: Aerobic Expansion"
        )

        XCTAssertEqual(aggData.stageContext, "Stage 2: Aerobic Expansion")
    }

    func testBaselineStatsInitialization() {
        let stats = BaselineStats(avgPace: 300, avgCadence: 165, avgHR: 145, avgOscillation: 9.5)
        XCTAssertEqual(stats.avgPace, 300)
        XCTAssertEqual(stats.avgCadence, 165)
        XCTAssertEqual(stats.avgHR, 145)
        XCTAssertEqual(stats.avgOscillation, 9.5)
        XCTAssertNil(stats.avgStrideLength)

        let statsWithStride = BaselineStats(avgPace: 300, avgCadence: 165, avgHR: 145, avgOscillation: 9.5, avgStrideLength: 1.18)
        XCTAssertEqual(statsWithStride.avgStrideLength, 1.18)
    }

    func testSparseRunBiometricGuardrail() async throws {
        if #available(iOS 26.0, *) {
            let schema = Schema([RunRecord.self, CoachingInsight.self, DrillRecommendation.self, TrainingCorrection.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            let container = try ModelContainer(for: schema, configurations: [config])

            let runId: PersistentIdentifier = {
                let context = container.mainContext
                let sparseRun = RunRecord(
                    hkWorkoutID: UUID(),
                    date: Date(),
                    totalDistanceMeters: 5000,
                    duration: 2700,
                    rawAvgPace: 540,
                    rawAvgHeartRate: 0,
                    rawAvgCadence: 0,
                    workingAvgPace: 540,
                    workingAvgCadence: 0,
                    workingAvgHeartRate: 0,
                    workingAvgVerticalOscillation: nil,
                    rawAvgVerticalOscillation: nil,
                    workingDistanceMeters: 5000,
                    workingDurationSeconds: 2700,
                    paceCV: 0.04,
                    paceSlope: 0.0,
                    percentZone4: 0.0,
                    detectedTypeRaw: "Easy Run",
                    framboiseTags: []
                )
                context.insert(sparseRun)
                try? context.save()
                return sparseRun.persistentModelID
            }()

            let analyzer = RunAnalyzerActor(modelContainer: container)
            await analyzer.generateAnalysis(for: runId)

            let fetched = container.mainContext.model(for: runId) as? RunRecord
            XCTAssertNil(fetched?.insight, "Runs lacking cadence and heart rate should not generate an AI insight")
        }
    }

    func testWorkoutEvaluationModalityMapping() {
        let intervalRun = RunRecord(
            hkWorkoutID: UUID(),
            date: Date(),
            totalDistanceMeters: 5000,
            duration: 1500,
            rawAvgPace: 300,
            rawAvgHeartRate: 165,
            rawAvgCadence: 175,
            workingAvgPace: 300,
            workingAvgCadence: 175,
            workingAvgHeartRate: 165,
            workingAvgVerticalOscillation: 8.0,
            rawAvgVerticalOscillation: 8.0,
            workingDistanceMeters: 5000,
            workingDurationSeconds: 1500,
            paceCV: 0.15,
            paceSlope: 0.0,
            percentZone4: 0.40,
            detectedTypeRaw: "Intervals",
            framboiseTags: []
        )
        XCTAssertEqual(intervalRun.evaluationModality, WorkoutEvaluationModality.intervals)

        let easyRun = RunRecord(
            hkWorkoutID: UUID(),
            date: Date(),
            totalDistanceMeters: 5000,
            duration: 1800,
            rawAvgPace: 360,
            rawAvgHeartRate: 135,
            rawAvgCadence: 160,
            workingAvgPace: 360,
            workingAvgCadence: 160,
            workingAvgHeartRate: 135,
            workingAvgVerticalOscillation: 8.0,
            rawAvgVerticalOscillation: 8.0,
            workingDistanceMeters: 5000,
            workingDurationSeconds: 1800,
            paceCV: 0.03,
            paceSlope: 0.0,
            percentZone4: 0.0,
            detectedTypeRaw: "Easy Run",
            framboiseTags: []
        )
        XCTAssertEqual(easyRun.evaluationModality, WorkoutEvaluationModality.aerobicBase)

        let progressionRun = RunRecord(
            hkWorkoutID: UUID(),
            date: Date(),
            totalDistanceMeters: 5000,
            duration: 1600,
            rawAvgPace: 320,
            rawAvgHeartRate: 155,
            rawAvgCadence: 168,
            workingAvgPace: 320,
            workingAvgCadence: 168,
            workingAvgHeartRate: 155,
            workingAvgVerticalOscillation: 8.0,
            rawAvgVerticalOscillation: 8.0,
            workingDistanceMeters: 5000,
            workingDurationSeconds: 1600,
            paceCV: 0.08,
            paceSlope: -0.05,
            percentZone4: 0.20,
            detectedTypeRaw: "Progression Run",
            framboiseTags: []
        )
        XCTAssertEqual(progressionRun.evaluationModality, WorkoutEvaluationModality.progression)

        let steadyRun = RunRecord(
            hkWorkoutID: UUID(),
            date: Date(),
            totalDistanceMeters: 5000,
            duration: 1500,
            rawAvgPace: 300,
            rawAvgHeartRate: 158,
            rawAvgCadence: 170,
            workingAvgPace: 300,
            workingAvgCadence: 170,
            workingAvgHeartRate: 158,
            workingAvgVerticalOscillation: 8.0,
            rawAvgVerticalOscillation: 8.0,
            workingDistanceMeters: 5000,
            workingDurationSeconds: 1500,
            paceCV: 0.02,
            paceSlope: 0.0,
            percentZone4: 0.25,
            detectedTypeRaw: "Steady Effort",
            framboiseTags: []
        )
        XCTAssertEqual(steadyRun.evaluationModality, WorkoutEvaluationModality.steadySplits)
    }

    func testIntervalRepEvaluationAndRecoveryDrop() {
        let run = RunRecord(
            hkWorkoutID: UUID(),
            date: Date(),
            totalDistanceMeters: 4000,
            duration: 1200,
            rawAvgPace: 270,
            rawAvgHeartRate: 160,
            rawAvgCadence: 174,
            workingAvgPace: 270,
            workingAvgCadence: 174,
            workingAvgHeartRate: 160,
            workingAvgVerticalOscillation: 8.2,
            rawAvgVerticalOscillation: 8.2,
            workingDistanceMeters: 4000,
            workingDurationSeconds: 1200,
            paceCV: 0.18,
            paceSlope: 0.0,
            percentZone4: 0.45,
            detectedTypeRaw: "Intervals",
            framboiseTags: []
        )

        let phases = [
            PhaseSegment(startSeconds: 0, endSeconds: 180, kind: "work", avgPace: 240, avgCadence: 180, avgHR: 172),
            PhaseSegment(startSeconds: 180, endSeconds: 270, kind: "recovery", avgPace: 360, avgCadence: 152, avgHR: 145),
            PhaseSegment(startSeconds: 270, endSeconds: 450, kind: "work", avgPace: 245, avgCadence: 178, avgHR: 176),
            PhaseSegment(startSeconds: 450, endSeconds: 540, kind: "recovery", avgPace: 365, avgCadence: 150, avgHR: 148)
        ]

        let sig = RunSignature(
            classification: "Intervals",
            confidence: 0.95,
            probabilities: ["Intervals": 0.95],
            anomalies: [],
            cadenceFloor: 150,
            phaseSegments: phases,
            dataSource: "wrist",
            isIndoor: false,
            needsInclineReview: false,
            splits: []
        )

        let timeline = RecoveryTimeline(
            now: Date(),
            lastHard: nil,
            hardSessionsLast72h: 0,
            requiredHours: 48,
            state: .productive
        )

        let ctx = WorkoutAnalysisContext(
            runRecord: run,
            runSignature: sig,
            macroProfile: nil,
            recoveryTimeline: timeline
        )
        XCTAssertEqual(ctx.evaluationModality, WorkoutEvaluationModality.intervals)
        XCTAssertEqual(ctx.intervalEvaluations.count, 2)

        let rep1 = ctx.intervalEvaluations[0]
        XCTAssertEqual(rep1.repIndex, 1)
        XCTAssertEqual(rep1.workCadence, 180)
        XCTAssertEqual(rep1.workHeartRate, 172)
        XCTAssertEqual(rep1.recoveryHeartRate, 145)
        XCTAssertEqual(rep1.recoveryHeartRateDrop, 27) // 172 - 145 = 27 BPM drop
        XCTAssertTrue(rep1.letterGrade.contains("A"))

        let rep2 = ctx.intervalEvaluations[1]
        XCTAssertEqual(rep2.repIndex, 2)
        XCTAssertEqual(rep2.recoveryHeartRateDrop, 28) // 176 - 148 = 28 BPM drop

        let report = ctx.formatPerformanceReport()
        XCTAssertTrue(report.contains("Here is the breakdown of your intervals:"))
        XCTAssertTrue(report.contains("Rep 1"))
        XCTAssertTrue(report.contains("Recovery 1"))
        XCTAssertTrue(report.contains("HR dropped -27 BPM"))
    }

    func testAerobicBaseSplitEvaluationRubric() {
        let run = RunRecord(
            hkWorkoutID: UUID(),
            date: Date(),
            totalDistanceMeters: 3000,
            duration: 1080,
            rawAvgPace: 360,
            rawAvgHeartRate: 135,
            rawAvgCadence: 162,
            workingAvgPace: 360,
            workingAvgCadence: 162,
            workingAvgHeartRate: 135,
            workingAvgVerticalOscillation: 8.0,
            rawAvgVerticalOscillation: 8.0,
            workingDistanceMeters: 3000,
            workingDurationSeconds: 1080,
            paceCV: 0.02,
            paceSlope: 0.0,
            percentZone4: 0.0,
            detectedTypeRaw: "Zone 2",
            framboiseTags: []
        )

        let splits = [
            RunSplit(index: 1, distanceMeters: 1000, durationSeconds: 362, paceSecondsPerKm: 362, avgHeartRate: 132, avgCadence: 162, elevationGainMeters: 2),
            RunSplit(index: 2, distanceMeters: 1000, durationSeconds: 358, paceSecondsPerKm: 358, avgHeartRate: 135, avgCadence: 163, elevationGainMeters: 3),
            RunSplit(index: 3, distanceMeters: 1000, durationSeconds: 360, paceSecondsPerKm: 360, avgHeartRate: 136, avgCadence: 161, elevationGainMeters: 2)
        ]

        let sig = RunSignature(
            classification: "Zone 2",
            confidence: 0.98,
            probabilities: ["Zone 2": 0.98],
            anomalies: [],
            cadenceFloor: 150,
            phaseSegments: [],
            dataSource: "wrist",
            isIndoor: false,
            needsInclineReview: false,
            splits: splits
        )

        let timeline = RecoveryTimeline(
            now: Date(),
            lastHard: nil,
            hardSessionsLast72h: 0,
            requiredHours: 48,
            state: .productive
        )

        let ctx = WorkoutAnalysisContext(
            runRecord: run,
            runSignature: sig,
            macroProfile: nil,
            recoveryTimeline: timeline
        )
        XCTAssertEqual(ctx.evaluationModality, WorkoutEvaluationModality.aerobicBase)
        XCTAssertEqual(ctx.splitEvaluations.count, 3)

        let report = ctx.formatPerformanceReport()
        XCTAssertTrue(report.contains("Here is the breakdown of your Zone 2 aerobic splits:"))
        XCTAssertTrue(report.contains("disciplined aerobic rhythm"))
    }

    func testUnprescribedTenIntervalSetsGradingAndNoTruncation() {
        let run = RunRecord(
            hkWorkoutID: UUID(),
            date: Date(),
            totalDistanceMeters: 6000,
            duration: 2400,
            rawAvgPace: 280,
            rawAvgHeartRate: 155,
            rawAvgCadence: 168,
            workingAvgPace: 280,
            workingAvgCadence: 168,
            workingAvgHeartRate: 155,
            workingAvgVerticalOscillation: 8.0,
            rawAvgVerticalOscillation: 8.0,
            workingDistanceMeters: 6000,
            workingDurationSeconds: 2400,
            paceCV: 0.15,
            paceSlope: 0.0,
            percentZone4: 0.40,
            detectedTypeRaw: "Intervals",
            framboiseTags: []
        )

        var phases: [PhaseSegment] = []
        for i in 1...10 {
            let startW = Double((i - 1) * 240)
            let endW = startW + 120.0
            let pace = 235.0 + Double(i * 2) // small variance
            phases.append(PhaseSegment(startSeconds: startW, endSeconds: endW, kind: "work", avgPace: pace, avgCadence: 176, avgHR: 168))

            let startR = endW
            let endR = startR + 120.0
            phases.append(PhaseSegment(startSeconds: startR, endSeconds: endR, kind: "recovery", avgPace: 380, avgCadence: 148, avgHR: 140))
        }

        let sig = RunSignature(
            classification: "Intervals",
            confidence: 0.95,
            probabilities: ["Intervals": 0.95],
            anomalies: [],
            cadenceFloor: 150,
            phaseSegments: phases,
            dataSource: "wrist",
            isIndoor: false,
            needsInclineReview: false,
            splits: []
        )

        let timeline = RecoveryTimeline(
            now: Date(),
            lastHard: nil,
            hardSessionsLast72h: 0,
            requiredHours: 48,
            state: .productive
        )

        let ctx = WorkoutAnalysisContext(
            runRecord: run,
            runSignature: sig,
            macroProfile: nil,
            recoveryTimeline: timeline
        )

        XCTAssertEqual(ctx.evaluationModality, WorkoutEvaluationModality.intervals)
        XCTAssertEqual(ctx.intervalEvaluations.count, 10)

        // Verify each rep is individually graded
        for rep in ctx.intervalEvaluations {
            XCTAssertFalse(rep.letterGrade.isEmpty)
            XCTAssertEqual(rep.recoveryHeartRateDrop, 28) // 168 - 140 = 28 BPM drop
            XCTAssertFalse(rep.observation.isEmpty)
        }

        // Verify formatting includes all 10 reps (no cutoff at 8)
        let report = ctx.formatPerformanceReport()
        XCTAssertTrue(report.contains("Rep 1 "))
        XCTAssertTrue(report.contains("Rep 9 "))
        XCTAssertTrue(report.contains("Rep 10 "))
        XCTAssertTrue(report.contains("Recovery 10"))

        let promptSummary = ctx.groundedPromptSummary(turnContext: nil)
        XCTAssertTrue(promptSummary.contains("Rep 1 "))
        XCTAssertTrue(promptSummary.contains("Rep 9 "))
        XCTAssertTrue(promptSummary.contains("Rep 10 "))
    }

    func testHistoricalRunMatcherAndComparison() throws {
        let schema = Schema([RunRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt

        // Create September 14 run
        var sep14Comps = DateComponents()
        sep14Comps.year = 2026
        sep14Comps.month = 9
        sep14Comps.day = 14
        sep14Comps.hour = 8
        guard let sep14Date = calendar.date(from: sep14Comps) else {
            XCTFail("Failed to build sep14Date")
            return
        }

        let sep14Run = RunRecord(
            hkWorkoutID: UUID(),
            date: sep14Date,
            totalDistanceMeters: 4500,
            duration: 1800,
            rawAvgPace: 400.0,
            rawAvgHeartRate: 152.0,
            rawAvgCadence: 150.0,
            workingAvgPace: 400.0,
            workingAvgCadence: 150.0,
            workingAvgHeartRate: 152.0,
            workingDistanceMeters: 4500,
            workingDurationSeconds: 1800,
            paceCV: 0.05,
            paceSlope: 0.0,
            percentZone4: 0.10,
            detectedTypeRaw: "Steady Effort"
        )
        context.insert(sep14Run)

        // Create October 13 run (Current run: Intervals, 6:25/km, 156 SPM, 147 BPM)
        var oct13Comps = DateComponents()
        oct13Comps.year = 2026
        oct13Comps.month = 10
        oct13Comps.day = 13
        oct13Comps.hour = 7
        guard let oct13Date = calendar.date(from: oct13Comps) else {
            XCTFail("Failed to build oct13Date")
            return
        }

        let currentRun = RunRecord(
            hkWorkoutID: UUID(),
            date: oct13Date,
            totalDistanceMeters: 4680,
            duration: 1800,
            rawAvgPace: 385.0,
            rawAvgHeartRate: 147.0,
            rawAvgCadence: 156.0,
            workingAvgPace: 385.0,
            workingAvgCadence: 156.0,
            workingAvgHeartRate: 147.0,
            workingDistanceMeters: 4680,
            workingDurationSeconds: 1800,
            paceCV: 0.12,
            paceSlope: 0.0,
            percentZone4: 0.30,
            detectedTypeRaw: "Intervals"
        )
        context.insert(currentRun)
        try context.save()

        // 1. Test finding by date query
        let matched = try XCTUnwrap(HistoricalRunMatcher.findRun(matching: "Compare this run to my September 14 run", relativeTo: currentRun, in: context))
        XCTAssertEqual(matched.id, sep14Run.id)

        // 2. Test comparison math
        let comparison = HistoricalRunMatcher.compare(current: currentRun, with: sep14Run)
        XCTAssertEqual(comparison.paceDeltaSeconds, 15) // 400 - 385 = 15s faster
        XCTAssertEqual(comparison.cadenceDelta, 6)      // 156 - 150 = +6 SPM
        XCTAssertEqual(comparison.heartRateDelta, -5)   // 147 - 152 = -5 BPM

        XCTAssertTrue(comparison.structuredTelemetryFacts.contains("6:25/km"))
        XCTAssertTrue(comparison.structuredTelemetryFacts.contains("6:40/km"))
        XCTAssertTrue(comparison.structuredTelemetryFacts.contains("156 SPM"))
        XCTAssertTrue(comparison.structuredTelemetryFacts.contains("150 SPM"))
        XCTAssertTrue(comparison.structuredTelemetryFacts.contains("147 BPM"))
        XCTAssertTrue(comparison.structuredTelemetryFacts.contains("152 BPM"))
        XCTAssertTrue(comparison.structuredTelemetryFacts.contains("September 14"))
        XCTAssertTrue(comparison.structuredTelemetryFacts.contains("15s/km faster"))
        XCTAssertTrue(comparison.structuredTelemetryFacts.contains("+6 SPM"))
        XCTAssertTrue(comparison.structuredTelemetryFacts.contains("5 BPM lower") || comparison.structuredTelemetryFacts.contains("-5 BPM"))

        // 3. Test negative delta formatting (no double negatives, e.g. "6 SPM lower turnover", not "-6 SPM")
        let reverseComparison = HistoricalRunMatcher.compare(current: sep14Run, with: currentRun)
        XCTAssertEqual(reverseComparison.cadenceDelta, -6)
        XCTAssertTrue(reverseComparison.structuredTelemetryFacts.contains("6 SPM lower turnover in current run"))
        XCTAssertFalse(reverseComparison.structuredTelemetryFacts.contains("-6 SPM lower turnover"))

        // 4. Test natural language comparison summary
        XCTAssertTrue(comparison.coachingComparisonSummary.contains("Comparing your"))
        XCTAssertTrue(comparison.coachingComparisonSummary.contains("15s/km faster"))
        XCTAssertTrue(comparison.coachingComparisonSummary.contains("+6 SPM higher turnover"))

        // 5. Test 30-Day Performance Arc Analysis
        let arc = HistoricalRunMatcher.analyzePerformanceArc(relativeTo: currentRun, in: context)
        XCTAssertEqual(arc.totalRunsInPast30Days, 2)
        XCTAssertNotNil(arc.bestRun)
        XCTAssertNotNil(arc.worstRun)
        XCTAssertEqual(arc.bestRun?.cadenceSPM, 156)
        XCTAssertEqual(arc.worstRun?.cadenceSPM, 150)
        XCTAssertTrue(arc.structuredTelemetryFacts.contains("156 SPM"))
        XCTAssertTrue(arc.structuredTelemetryFacts.contains("150 SPM"))
        XCTAssertFalse(arc.structuredTelemetryFacts.contains("/km cadence"), "Must never output /km cadence")
        XCTAssertFalse(arc.coachingArcSummary.contains("/km cadence"), "Coaching summary must never output /km cadence")
        XCTAssertTrue(arc.coachingArcSummary.contains("156 SPM"))

        // 6. Test superlative matching ("best run", "worst run")
        let bestMatch = try XCTUnwrap(HistoricalRunMatcher.findRun(matching: "compare to my best run", relativeTo: sep14Run, in: context))
        XCTAssertEqual(bestMatch.id, currentRun.id)

        let worstMatch = try XCTUnwrap(HistoricalRunMatcher.findRun(matching: "compare to my worst performance", relativeTo: currentRun, in: context))
        XCTAssertEqual(worstMatch.id, sep14Run.id)

        // 7. Test AnalystFallbackResponder 30-day best/worst performance intent
        let chatEngine = AnalystChatEngine(runRecord: currentRun)
        let analysis = chatEngine.makeAnalysisContext()

        let fallbackArcResponse = AnalystFallbackResponder.generateResponse(
            for: "In the past 30 days, which run was my best performance? Which was my worst performance?",
            analysis: analysis,
            runRecord: currentRun
        )
        XCTAssertTrue(fallbackArcResponse.contains("best performance"))
        XCTAssertTrue(fallbackArcResponse.contains("toughest session"))
        XCTAssertTrue(fallbackArcResponse.contains("156 SPM"))
        XCTAssertFalse(fallbackArcResponse.contains("/km cadence"), "Fallback must never write /km cadence")
    }
}
