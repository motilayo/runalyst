import Foundation
#if canImport(FoundationModels)
import FoundationModels

// MARK: - Query Parameter Schemas

@available(iOS 26.0, *)
@Generable
struct WorkoutAnalysisQuery: Sendable {
    @Guide(description: "Specific query focus: 'verdicts', 'economy_and_efficiency', 'cadence_mechanics', 'cardiac_drift', 'splits', or 'full_telemetry'")
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

@available(iOS 26.0, *)
@Generable
struct HistoricalWorkoutQuery: Sendable {
    @Guide(description: "Search target for comparison or ranking: 'best_and_worst' (or 'arc', '30_days') to rank past 30 days workouts, or specific date (e.g. 'MM/DD'), relative term ('previous', 'last run'), or modality ('last tempo').")
    var target: String?
}

// MARK: - FoundationModels Native Tools

/// Tool providing deterministic retrospective workout telemetry, biomechanics, and physiological verdicts.
@available(iOS 26.0, *)
struct FetchWorkoutAnalysisTool: Tool {
    typealias Arguments = WorkoutAnalysisQuery
    typealias Output = String

    let name = "fetchWorkoutAnalysis"
    let description = "Retrieves deterministic overall workout telemetry and causal physiological diagnoses for this run, including total distance, duration, average pace, cadence, heart rate, cadence floor adherence, aerobic efficiency, and cardiac drift."

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
    let description = "Retrieves detailed interval workout performance, including individual rep-by-rep breakdowns (work pace, cadence, heart rate, letter grade, and observation for each repetition), recovery jog paces and heart rate drops between sets, and pace consistency across reps."

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
    let description = "Retrieves modeled biomechanical and environmental physics for this workout: treadmill belt kinetics vs road push-off, indoor heat accumulation and lack of convective cooling vs outdoor wind, hill slope resistance, and cardiac lag."

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
    let description = "Retrieves the runner's current recovery timeline, readiness to train, and the mathematically locked prescription for their upcoming workout (session type, pace band, duration band, and rationale)."

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
    let description = "Retrieves the athlete's 30-day cumulative training volume, experience level, active training goal, and height-calibrated cadence floor."

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

/// Tool providing deterministic historical workout comparison telemetry.
@available(iOS 26.0, *)
struct FetchHistoricalWorkoutTool: Tool {
    typealias Arguments = HistoricalWorkoutQuery
    typealias Output = String

    let name = "fetchHistoricalWorkout"
    let description = "Retrieves historical workout telemetry to compare against past runs, rank 30-day performances, or evaluate training progress over time."

    let provider: @MainActor @Sendable (HistoricalWorkoutQuery) async -> String

    init(provider: @escaping @MainActor @Sendable (HistoricalWorkoutQuery) async -> String) {
        self.provider = provider
    }

    init(simpleProvider: @escaping @MainActor @Sendable () async -> String) {
        self.provider = { _ in await simpleProvider() }
    }

    func call(arguments: HistoricalWorkoutQuery) async throws -> String {
        await provider(arguments)
    }
}
#endif
