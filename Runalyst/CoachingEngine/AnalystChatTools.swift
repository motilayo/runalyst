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
struct IntervalPerformanceQuery: Sendable {
    @Guide(description: "Interval focus: 'reps' for rep-by-rep execution, 'repeatability' for pace spread consistency, 'recovery' for HR drops, or 'all'")
    var focus: String?
}

@available(iOS 26.0, *)
@Generable
struct WorkoutPhysicsQuery: Sendable {
    @Guide(description: "Physics domain: 'treadmill_belt_and_thermal', 'gravitational_slope', 'cardiac_lag', 'biomechanical_forces', or 'all'")
    var domain: String?
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

    let provider: @MainActor @Sendable (WorkoutAnalysisQuery) async -> String

    init(provider: @escaping @MainActor @Sendable (WorkoutAnalysisQuery) async -> String) {
        self.provider = provider
    }

    init(simpleProvider: @escaping @MainActor @Sendable () async -> String) {
        self.provider = { _ in await simpleProvider() }
    }

    func call(arguments: WorkoutAnalysisQuery) async throws -> String {
        await provider(arguments)
    }
}

/// Tool providing discrete interval rep breakdown, work pacing repeatability, and recovery HR drops.
@available(iOS 26.0, *)
struct FetchIntervalPerformanceTool: Tool {
    typealias Arguments = IntervalPerformanceQuery
    typealias Output = String

    let name = "fetchIntervalPerformance"
    let description = "Retrieves discrete interval performance telemetry: work rep paces, cadences, heart rates, active recovery paces, recovery heart rate drops, pace repeatability across sets, and belt vs road mechanics."

    let provider: @MainActor @Sendable (IntervalPerformanceQuery) async -> String

    init(provider: @escaping @MainActor @Sendable (IntervalPerformanceQuery) async -> String) {
        self.provider = provider
    }

    init(simpleProvider: @escaping @MainActor @Sendable () async -> String) {
        self.provider = { _ in await simpleProvider() }
    }

    func call(arguments: IntervalPerformanceQuery) async throws -> String {
        await provider(arguments)
    }
}

/// Tool providing modeled physical realities: treadmill belt kinetics, thermal buildup in static room air, hill gravity, and cardiac lag.
@available(iOS 26.0, *)
struct FetchWorkoutPhysicsTool: Tool {
    typealias Arguments = WorkoutPhysicsQuery
    typealias Output = String

    let name = "fetchWorkoutPhysics"
    let description = "Retrieves modeled physical and physiological realities: treadmill belt kinetics and braking shock, indoor thermal accumulation in static room air vs outdoor convective wind cooling, gravitational resistance on hills, and cardiac lag."

    let provider: @MainActor @Sendable (WorkoutPhysicsQuery) async -> String

    init(provider: @escaping @MainActor @Sendable (WorkoutPhysicsQuery) async -> String) {
        self.provider = provider
    }

    init(simpleProvider: @escaping @MainActor @Sendable () async -> String) {
        self.provider = { _ in await simpleProvider() }
    }

    func call(arguments: WorkoutPhysicsQuery) async throws -> String {
        await provider(arguments)
    }
}

/// Tool providing prospective recovery status, rest timeline, and locked training prescriptions for upcoming sessions.
@available(iOS 26.0, *)
struct FetchReadinessAndPrescriptionTool: Tool {
    typealias Arguments = ReadinessQuery
    typealias Output = String

    let name = "fetchReadinessAndPrescription"
    let description = "Retrieves the runner's current recovery timeline, readiness state, hours of rest, and the locked training prescription for their upcoming session."

    let provider: @MainActor @Sendable (ReadinessQuery) async -> String

    init(provider: @escaping @MainActor @Sendable (ReadinessQuery) async -> String) {
        self.provider = provider
    }

    init(simpleProvider: @escaping @MainActor @Sendable () async -> String) {
        self.provider = { _ in await simpleProvider() }
    }

    func call(arguments: ReadinessQuery) async throws -> String {
        await provider(arguments)
    }
}

/// Tool providing longitudinal athlete identity, experience level, 30-day training volume, and height-calibrated cadence floors.
@available(iOS 26.0, *)
struct FetchAthleteProfileTool: Tool {
    typealias Arguments = AthleteProfileQuery
    typealias Output = String

    let name = "fetchAthleteProfile"
    let description = "Retrieves the runner's 30-day cumulative training load, athletic experience level, active training goal, and height-calibrated cadence floor."

    let provider: @MainActor @Sendable (AthleteProfileQuery) async -> String

    init(provider: @escaping @MainActor @Sendable (AthleteProfileQuery) async -> String) {
        self.provider = provider
    }

    init(simpleProvider: @escaping @MainActor @Sendable () async -> String) {
        self.provider = { _ in await simpleProvider() }
    }

    func call(arguments: AthleteProfileQuery) async throws -> String {
        await provider(arguments)
    }
}
#endif
