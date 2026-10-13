import XCTest
import SwiftData
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
}
