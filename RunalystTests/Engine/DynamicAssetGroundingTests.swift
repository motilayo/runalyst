import XCTest
import SwiftData
#if canImport(FoundationModels)
import FoundationModels
#endif
@testable import Runalyst

@MainActor
final class DynamicAssetGroundingTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(true, forKey: "useMetricSystem")
    }

    // MARK: - AC-1: Centralized Asset Library & Canonical Resolution

    func testAssetResolutionAcrossKeysAndAliases() {
        // Direct canonical keys
        XCTAssertEqual(CoachingAssetLibrary.resolve(key: "cadence_floor")?.key, "cadence_floor")
        XCTAssertEqual(CoachingAssetLibrary.resolve(key: "efficiency_factor")?.key, "efficiency_factor")
        XCTAssertEqual(CoachingAssetLibrary.resolve(key: "cardiac_drift")?.key, "cardiac_drift")
        XCTAssertEqual(CoachingAssetLibrary.resolve(key: "treadmill_physics")?.key, "treadmill_physics")
        XCTAssertEqual(CoachingAssetLibrary.resolve(key: "recovery_timeline")?.key, "recovery_timeline")
        XCTAssertEqual(CoachingAssetLibrary.resolve(key: "working_stats")?.key, "working_stats")

        // Aliases with spaces, hyphens, and mixed casing
        XCTAssertEqual(CoachingAssetLibrary.resolve(key: "Bounce")?.key, "vertical_oscillation")
        XCTAssertEqual(CoachingAssetLibrary.resolve(key: "vert. osc.")?.key, "vertical_oscillation")
        XCTAssertEqual(CoachingAssetLibrary.resolve(key: "vertical oscillation")?.key, "vertical_oscillation")
        XCTAssertEqual(CoachingAssetLibrary.resolve(key: "Height-Cadence-Floor")?.key, "cadence_floor")
        XCTAssertEqual(CoachingAssetLibrary.resolve(key: "aerobic efficiency")?.key, "efficiency_factor")
        XCTAssertEqual(CoachingAssetLibrary.resolve(key: "Drift")?.key, "cardiac_drift")
        XCTAssertEqual(CoachingAssetLibrary.resolve(key: "GCT")?.key, "ground_contact_time")
        XCTAssertEqual(CoachingAssetLibrary.resolve(key: "Pace CV")?.key, "pacing_consistency")
        XCTAssertEqual(CoachingAssetLibrary.resolve(key: "overstride")?.key, "overstriding")
        XCTAssertEqual(CoachingAssetLibrary.resolve(key: "indoor physics")?.key, "treadmill_physics")
        XCTAssertEqual(CoachingAssetLibrary.resolve(key: "Zone 1 HR")?.key, "zone_1_hr")
        XCTAssertEqual(CoachingAssetLibrary.resolve(key: "Zone 2 HR")?.key, "zone_2_hr")
    }

    func testTokenEfficiencyOfCompactSummaries() {
        for asset in CoachingAssetLibrary.allAssets {
            XCTAssertFalse(asset.compactSummary.isEmpty, "Compact summary for \(asset.key) must not be empty")
            // Apple TN3193 token conservation: compact summaries should stay under 250 characters (~30-40 words)
            XCTAssertLessThanOrEqual(
                asset.compactSummary.count,
                250,
                "Asset \(asset.key) compact summary is too long (\(asset.compactSummary.count) chars), risking 4,096 token limit!"
            )
        }
    }

    func testMetricDetailExplainerDelegatesToCoachingAssetLibrary() {
        let bounceWorking = MetricDetailExplainer.explainer(for: "vertical oscillation", isWorkoutStats: false)
        let bounceWorkout = MetricDetailExplainer.explainer(for: "vertical oscillation", isWorkoutStats: true)

        XCTAssertTrue(bounceWorking.title.contains("Bounce"))
        XCTAssertTrue(bounceWorking.modeContext.contains("Working Stats"))
        XCTAssertTrue(bounceWorkout.modeContext.contains("Workout Stats"))
        XCTAssertFalse(bounceWorking.overview.isEmpty)
        XCTAssertFalse(bounceWorking.whyItMatters.isEmpty)
        XCTAssertFalse(bounceWorking.targetRange.isEmpty)

        // Non-standard unknown metric fallback
        let custom = MetricDetailExplainer.explainer(for: "Custom Unknown Metric", isWorkoutStats: false)
        XCTAssertEqual(custom.title, "Custom Unknown Metric")
        XCTAssertTrue(custom.overview.contains("tracked by Apple Health"))
    }

    func testExplainerInfoCreationForSheetPresentation() {
        let info = CoachingAssetLibrary.explainerInfo(for: "cadence_floor", userMetricDisplay: "155 SPM Floor")
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.title, "Height-Calibrated Cadence Floor")
        XCTAssertEqual(info?.userMetricDisplay, "155 SPM Floor")
        XCTAssertNotNil(info?.modeContext)
        XCTAssertNotNil(info?.whyItMatters)
        XCTAssertNotNil(info?.targetRange)
    }

    // MARK: - AC-2: 3-Tool Facade Payload Grounding

    func testDynamicSelectionOfWorkoutExplainers() {
        // Outdoor run with efficiency factor and cardiac drift
        let outdoorExplainers = CoachingAssetLibrary.selectExplainers(
            features: CoachingAssetLibrary.WorkoutFeatureSet(
                isIndoor: false,
                hasCardiacDrift: true,
                hasEfficiencyFactor: true,
                hasVerticalOscillation: true,
                hasGroundContactTime: true,
                hasStrideLength: false,
                isIntervals: false
            )
        )

        XCTAssertNotNil(outdoorExplainers["working_stats"])
        XCTAssertNotNil(outdoorExplainers["cadence_floor"])
        XCTAssertNotNil(outdoorExplainers["cardiac_drift"])
        XCTAssertNotNil(outdoorExplainers["efficiency_factor"])
        XCTAssertNotNil(outdoorExplainers["vertical_oscillation"])
        XCTAssertNil(outdoorExplainers["treadmill_physics"], "Outdoor run must not include treadmill physics")

        // Indoor treadmill run
        let indoorExplainers = CoachingAssetLibrary.selectExplainers(
            features: CoachingAssetLibrary.WorkoutFeatureSet(
                isIndoor: true,
                hasCardiacDrift: false,
                hasEfficiencyFactor: false,
                hasVerticalOscillation: false,
                hasGroundContactTime: false,
                hasStrideLength: false,
                isIntervals: false
            )
        )

        XCTAssertNotNil(indoorExplainers["working_stats"])
        XCTAssertNotNil(indoorExplainers["cadence_floor"])
        XCTAssertNotNil(indoorExplainers["treadmill_physics"], "Indoor run must include treadmill physics")
        XCTAssertNil(indoorExplainers["cardiac_drift"])
    }

    func testReadinessGuidanceNotes() {
        // Normal ready state
        let readyNotes = CoachingAssetLibrary.readinessGuidance(for: "CLEARED_FOR_TRAINING", isDistress: false)
        XCTAssertNotNil(readyNotes["recovery_policy"])
        XCTAssertNotNil(readyNotes["aerobic_zone_guidelines"])
        XCTAssertNotNil(readyNotes["load_progression"])
        XCTAssertNil(readyNotes["medical_boundary"])

        // Subjective distress or mandatory rest
        let distressNotes = CoachingAssetLibrary.readinessGuidance(for: "MANDATORY_REST_HEALTH_OVERRIDE", isDistress: true)
        XCTAssertNotNil(distressNotes["recovery_policy"])
        XCTAssertNotNil(distressNotes["medical_boundary"])
        XCTAssertTrue(distressNotes["medical_boundary"]?.contains("physical therapist") == true)
        XCTAssertNil(distressNotes["aerobic_zone_guidelines"])
    }

    func testUnifiedWorkoutToolResponseJSONRoundTrip() throws {
        let response = UnifiedWorkoutToolResponse(
            schema_name: "UNIFIED_WORKOUT_TOOL_RESPONSE",
            workout_type: "Steady Effort",
            date: "Thursday, Oct 16",
            environment: "Outdoors (road/track)",
            background_session_totals: BlendedTotals(
                total_distance: "5.0 km",
                total_duration: "30 min",
                blended_session_avg_pace: "6:00/km",
                blended_session_avg_cadence_spm: 165,
                height_cadence_floor_spm: 155
            ),
            physiological_verdicts: "Steady aerobic state confirmed.",
            metric_explainers: [
                "cadence_floor": "Anatomical threshold calculated from height.",
                "working_stats": "Pause-trimmed active moving telemetry."
            ]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(response)
        let jsonStr = String(data: data, encoding: .utf8)

        XCTAssertNotNil(jsonStr)
        XCTAssertTrue(jsonStr?.contains("metric_explainers") == true)
        XCTAssertTrue(jsonStr?.contains("cadence_floor") == true)
        XCTAssertTrue(jsonStr?.contains("working_stats") == true)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(UnifiedWorkoutToolResponse.self, from: data)
        XCTAssertEqual(decoded.metric_explainers?["cadence_floor"], "Anatomical threshold calculated from height.")
    }

    func testReadinessToolResponseJSONRoundTrip() throws {
        let response = ReadinessToolResponse(
            schema_name: "READINESS_AND_PRESCRIPTION_RESPONSE",
            readiness_verdict: "CLEARED_FOR_TRAINING",
            recovery_status: "Fully recovered.",
            prescribed_session_name: "Zone 2 Steady Run",
            intensity_category: "Zone 2 Aerobic Base",
            prescribed_pace_band: "5:45 - 6:05 /km",
            prescribed_duration_band: "35 - 45 min",
            prescribed_cadence_band: "160 - 166 SPM",
            session_rationale: "Build aerobic base.",
            guidance_notes: [
                "recovery_policy": "48 hours between hard sessions."
            ]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(response)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ReadinessToolResponse.self, from: data)

        XCTAssertEqual(decoded.guidance_notes?["recovery_policy"], "48 hours between hard sessions.")
    }

    // MARK: - AC-3: Execute Coach Action .displayExplainer

    func testExecuteCoachActionDisplayExplainerSetsEngineTurnState() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RunRecord.self, configurations: config)
        let context = container.mainContext

        let run = RunRecord(
            hkWorkoutID: UUID(),
            date: Date(),
            totalDistanceMeters: 5000,
            duration: 1800,
            rawAvgPace: 360,
            rawAvgHeartRate: 145,
            rawAvgCadence: 160,
            workingAvgPace: 360,
            workingAvgCadence: 160,
            workingAvgHeartRate: 145,
            workingDistanceMeters: 5000,
            workingDurationSeconds: 1800,
            paceCV: 0.05,
            paceSlope: 0.0,
            percentZone4: 0.20,
            detectedTypeRaw: "Steady Effort"
        )
        context.insert(run)
        try context.save()

        let engine = AnalystChatEngine(runRecord: run)

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            // 1. Verify ExecuteCoachActionTool with .displayExplainer produces correct JSON and key
            let coachActionTool = ExecuteCoachActionTool { query in
                switch query.action {
                case .displayExplainer:
                    let rawKey = query.payload?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let asset = CoachingAssetLibrary.resolve(key: rawKey) ?? CoachingAssetLibrary.defaultAsset(for: rawKey)
                    engine.explainerRecommendedThisTurn = asset.key
                    return "{\"status\":\"interactive_explainer_card_displayed\",\"explainer_key\":\"\(asset.key)\",\"title\":\"\(asset.title)\"}"
                default:
                    return "{}"
                }
            }

            let toolResult = try await coachActionTool.call(arguments: ExecuteCoachActionQuery(action: .displayExplainer, payload: "efficiency_factor"))
            XCTAssertTrue(toolResult.contains("interactive_explainer_card_displayed"))
            XCTAssertTrue(toolResult.contains("efficiency_factor"))
            XCTAssertEqual(engine.explainerRecommendedThisTurn, "efficiency_factor")

            // 2. Verify engine turn cycle: when tool executes during turn, explainer attaches to analyst message
            engine.modelResponder = { (instructions: String, _: String) async throws -> String in
                XCTAssertTrue(instructions.contains("display_explainer"))
                // Model calls executeCoachAction during turn:
                let query = ExecuteCoachActionQuery(action: .displayExplainer, payload: "efficiency_factor")
                _ = try await coachActionTool.call(arguments: query)
                return "Your aerobic efficiency factor was 1.15 m/beat today, showing strong cardiovascular economy."
            }

            await engine.sendMessage("What is efficiency factor?")

            let lastMsg = try XCTUnwrap(engine.messages.last)
            XCTAssertEqual(lastMsg.sender, AnalystChatSender.analyst)
            XCTAssertEqual(lastMsg.attachedExplainerKey, "efficiency_factor")
        }
        #endif
    }

    func testAnalystChatMessageInitializationWithAttachedExplainerKey() {
        let msg = AnalystChatMessage(
            sender: AnalystChatSender.analyst,
            text: "Here is your cadence floor definition.",
            attachedExplainerKey: "cadence_floor"
        )

        XCTAssertEqual(msg.sender, AnalystChatSender.analyst)
        XCTAssertEqual(msg.attachedExplainerKey, "cadence_floor")
        XCTAssertNil(msg.attachedDrillId)
    }
}
