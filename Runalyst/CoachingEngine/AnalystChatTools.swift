import Foundation
#if canImport(FoundationModels)
import FoundationModels

// MARK: - Query Parameter Schemas

@available(iOS 26.0, *)
@Generable
struct WorkoutAnalysisQuery: Sendable {
    @Guide(description: "Specific query focus: 'verdicts', 'cadence_mechanics', 'cardiac_drift', 'splits', or 'full_telemetry'")
    var focus: String?
}

@available(iOS 26.0, *)
@Generable
struct ReadinessQuery: Sendable {
    @Guide(description: "Planning query focus: 'tomorrow_readiness', 'locked_prescription', or 'recovery_status'")
    var focus: String?
}

@available(iOS 26.0, *)
@Generable
struct AthleteProfileQuery: Sendable {
    @Guide(description: "Profile aspect: 'experience_level', 'training_load', or 'cadence_floor'")
    var aspect: String?
}

// MARK: - FoundationModels Native Tools

/// Tool providing deterministic retrospective workout telemetry, biomechanics, and physiological verdicts.
@available(iOS 26.0, *)
struct FetchWorkoutAnalysisTool: Tool {
    typealias Arguments = WorkoutAnalysisQuery
    typealias Output = String

    let name = "fetchWorkoutAnalysis"
    let description = "Retrieves deterministic biomechanical and physiological analysis of the user's specific workout, including heart rate drift, cadence floor adherence, pacing consistency, and causal verdicts."

    let provider: @MainActor @Sendable () async -> String

    func call(arguments: WorkoutAnalysisQuery) async throws -> String {
        await provider()
    }
}

/// Tool providing prospective recovery status, rest timeline, and locked training prescriptions for upcoming sessions.
@available(iOS 26.0, *)
struct FetchReadinessAndPrescriptionTool: Tool {
    typealias Arguments = ReadinessQuery
    typealias Output = String

    let name = "fetchReadinessAndPrescription"
    let description = "Retrieves the runner's current recovery timeline, readiness state, hours of rest, and the locked training prescription for their upcoming session."

    let provider: @MainActor @Sendable () async -> String

    func call(arguments: ReadinessQuery) async throws -> String {
        await provider()
    }
}

/// Tool providing longitudinal athlete identity, experience level, 30-day training volume, and height-calibrated cadence floors.
@available(iOS 26.0, *)
struct FetchAthleteProfileTool: Tool {
    typealias Arguments = AthleteProfileQuery
    typealias Output = String

    let name = "fetchAthleteProfile"
    let description = "Retrieves the runner's 30-day cumulative training load, athletic experience level, active training goal, and height-calibrated cadence floor."

    let provider: @MainActor @Sendable () async -> String

    func call(arguments: AthleteProfileQuery) async throws -> String {
        await provider()
    }
}
#endif
