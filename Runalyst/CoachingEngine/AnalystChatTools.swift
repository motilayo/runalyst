import Foundation

// MARK: - Unified Native Tool Schemas
// swiftlint:disable identifier_name

/// The definitive structure returned to the LLM on workout analysis tool call.
public struct UnifiedWorkoutToolResponse: Codable, Sendable {
    public let schema_name: String
    public let workout_type: String
    public let date: String
    public let environment: String

    // PRIMARY OBJECT FOR INTERVALS (LLM reads this first when workout_type == "Intervals")
    public let interval_scorecard: IntervalScorecard?

    // THE REP ARRAY (Persisted in session memory for deep-dive turns)
    public let reps: [IntervalRepDetail]?

    // PRIMARY OBJECT FOR STEADY-STATE RUNS (When not intervals)
    public let steady_state_scorecard: SteadyStateScorecard?

    // THE SPLITS ARRAY (For continuous/steady-state runs)
    public let splits: [SplitDetail]?

    // SECONDARY BACKGROUND (Blended session data - demoted so LLM doesn't confuse it)
    public let background_session_totals: BlendedTotals

    // Indisputable causal physiological diagnoses computed locally in Swift
    public let physiological_verdicts: String

    // Verification of sensor plausibility and omission status
    public let heart_rate_confidence: String?
    public let heart_rate_status: String?

    public init(
        schema_name: String = "UNIFIED_WORKOUT_TOOL_RESPONSE",
        workout_type: String,
        date: String,
        environment: String,
        interval_scorecard: IntervalScorecard? = nil,
        reps: [IntervalRepDetail]? = nil,
        steady_state_scorecard: SteadyStateScorecard? = nil,
        splits: [SplitDetail]? = nil,
        background_session_totals: BlendedTotals,
        physiological_verdicts: String,
        heart_rate_confidence: String? = nil,
        heart_rate_status: String? = nil
    ) {
        self.schema_name = schema_name
        self.workout_type = workout_type
        self.date = date
        self.environment = environment
        self.interval_scorecard = interval_scorecard
        self.reps = reps
        self.steady_state_scorecard = steady_state_scorecard
        self.splits = splits
        self.background_session_totals = background_session_totals
        self.physiological_verdicts = physiological_verdicts
        self.heart_rate_confidence = heart_rate_confidence
        self.heart_rate_status = heart_rate_status
    }
}

public struct IntervalScorecard: Codable, Sendable {
    public let active_work_pace: String     // "5:42/km" (The true workload)
    public let active_turnover_spm: Int     // 162 (The true active cadence)
    public let average_hr_drop: Int         // -4 (Heat-blunted)
    public let total_work_reps: Int         // 9
    public let session_grade: String        // "A"
    public let pacing_consistency: String?  // "Disciplined consistency (tight spread)"
    public let active_avg_heart_rate_bpm: Int?
    public let heart_rate_status: String?
    public let cadence_floor_status: String?

    public init(
        active_work_pace: String,
        active_turnover_spm: Int,
        average_hr_drop: Int,
        total_work_reps: Int,
        session_grade: String,
        pacing_consistency: String? = nil,
        active_avg_heart_rate_bpm: Int? = nil,
        heart_rate_status: String? = nil,
        cadence_floor_status: String? = nil
    ) {
        self.active_work_pace = active_work_pace
        self.active_turnover_spm = active_turnover_spm
        self.average_hr_drop = average_hr_drop
        self.total_work_reps = total_work_reps
        self.session_grade = session_grade
        self.pacing_consistency = pacing_consistency
        self.active_avg_heart_rate_bpm = active_avg_heart_rate_bpm
        self.heart_rate_status = heart_rate_status
        self.cadence_floor_status = cadence_floor_status
    }
}

public struct IntervalRepDetail: Codable, Sendable {
    public let rep_number: Int              // 1 through 9
    public let work_pace: String            // "5:42/km"
    public let work_cadence_spm: Int        // 162
    public let rep_grade: String            // "A", "A-", "A+"
    public let recovery_pace: String        // "7:15/km"
    public let recovery_hr_drop_bpm: Int?
    public let work_heart_rate_bpm: Int?
    public let heart_rate_status: String?
    public let observation: String?

    public init(
        rep_number: Int,
        work_pace: String,
        work_cadence_spm: Int,
        rep_grade: String,
        recovery_pace: String,
        recovery_hr_drop_bpm: Int? = nil,
        work_heart_rate_bpm: Int? = nil,
        heart_rate_status: String? = nil,
        observation: String? = nil
    ) {
        self.rep_number = rep_number
        self.work_pace = work_pace
        self.work_cadence_spm = work_cadence_spm
        self.rep_grade = rep_grade
        self.recovery_pace = recovery_pace
        self.recovery_hr_drop_bpm = recovery_hr_drop_bpm
        self.work_heart_rate_bpm = work_heart_rate_bpm
        self.heart_rate_status = heart_rate_status
        self.observation = observation
    }
}

public struct SteadyStateScorecard: Codable, Sendable {
    public let avg_pace: String
    public let avg_turnover_spm: Int
    public let avg_heart_rate_bpm: Int?
    public let heart_rate_status: String?
    public let session_grade: String
    public let pacing_trend: String
    public let cadence_floor_status: String
    public let fastest_split: String?
    public let slowest_split: String?

    public init(
        avg_pace: String,
        avg_turnover_spm: Int,
        avg_heart_rate_bpm: Int? = nil,
        heart_rate_status: String? = nil,
        session_grade: String,
        pacing_trend: String,
        cadence_floor_status: String,
        fastest_split: String? = nil,
        slowest_split: String? = nil
    ) {
        self.avg_pace = avg_pace
        self.avg_turnover_spm = avg_turnover_spm
        self.avg_heart_rate_bpm = avg_heart_rate_bpm
        self.heart_rate_status = heart_rate_status
        self.session_grade = session_grade
        self.pacing_trend = pacing_trend
        self.cadence_floor_status = cadence_floor_status
        self.fastest_split = fastest_split
        self.slowest_split = slowest_split
    }
}

public struct SplitDetail: Codable, Sendable {
    public let split_index: Int
    public let pace: String
    public let cadence_spm: Int
    public let heart_rate_bpm: Int?
    public let heart_rate_status: String?
    public let grade: String
    public let observation: String

    public init(
        split_index: Int,
        pace: String,
        cadence_spm: Int,
        heart_rate_bpm: Int? = nil,
        heart_rate_status: String? = nil,
        grade: String,
        observation: String
    ) {
        self.split_index = split_index
        self.pace = pace
        self.cadence_spm = cadence_spm
        self.heart_rate_bpm = heart_rate_bpm
        self.heart_rate_status = heart_rate_status
        self.grade = grade
        self.observation = observation
    }
}

public struct BlendedTotals: Codable, Sendable {
    public let _description: String
    public let total_distance: String
    public let total_duration: String
    public let blended_session_avg_pace: String
    public let blended_session_avg_cadence_spm: Int
    public let blended_session_avg_heart_rate_bpm: Int?
    public let heart_rate_status: String?
    public let height_cadence_floor_spm: Int
    public let aerobic_efficiency_factor: String?
    public let cardiac_drift: String?
    public let stride_archetype: String?

    public init(
        _description: String = "Contains blended averages for the entire session (warm-up, work bouts, recovery jogs, and cooldown combined). SECONDARY: Do NOT cite these as the interval workload or active pace.",
        total_distance: String,
        total_duration: String,
        blended_session_avg_pace: String,
        blended_session_avg_cadence_spm: Int,
        blended_session_avg_heart_rate_bpm: Int? = nil,
        heart_rate_status: String? = nil,
        height_cadence_floor_spm: Int,
        aerobic_efficiency_factor: String? = nil,
        cardiac_drift: String? = nil,
        stride_archetype: String? = nil
    ) {
        self._description = _description
        self.total_distance = total_distance
        self.total_duration = total_duration
        self.blended_session_avg_pace = blended_session_avg_pace
        self.blended_session_avg_cadence_spm = blended_session_avg_cadence_spm
        self.blended_session_avg_heart_rate_bpm = blended_session_avg_heart_rate_bpm
        self.heart_rate_status = heart_rate_status
        self.height_cadence_floor_spm = height_cadence_floor_spm
        self.aerobic_efficiency_factor = aerobic_efficiency_factor
        self.cardiac_drift = cardiac_drift
        self.stride_archetype = stride_archetype
    }
}

/// The definitive structure returned to the LLM on readiness and prescription tool call.
public struct ReadinessToolResponse: Codable, Sendable {
    public let schema_name: String
    public let readiness_verdict: String
    public let recovery_status: String
    public let prescribed_session_name: String
    public let intensity_category: String
    public let prescribed_pace_band: String
    public let prescribed_duration_band: String
    public let prescribed_cadence_band: String
    public let session_rationale: String
    public let coaching_directive: String

    public init(
        schema_name: String = "READINESS_AND_PRESCRIPTION_RESPONSE",
        readiness_verdict: String,
        recovery_status: String,
        prescribed_session_name: String,
        intensity_category: String,
        prescribed_pace_band: String,
        prescribed_duration_band: String,
        prescribed_cadence_band: String,
        session_rationale: String,
        coaching_directive: String
    ) {
        self.schema_name = schema_name
        self.readiness_verdict = readiness_verdict
        self.recovery_status = recovery_status
        self.prescribed_session_name = prescribed_session_name
        self.intensity_category = intensity_category
        self.prescribed_pace_band = prescribed_pace_band
        self.prescribed_duration_band = prescribed_duration_band
        self.prescribed_cadence_band = prescribed_cadence_band
        self.session_rationale = session_rationale
        self.coaching_directive = coaching_directive
    }
}
// swiftlint:enable identifier_name

#if canImport(FoundationModels)
import FoundationModels

// MARK: - Query Parameter Schemas

@available(iOS 26.0, *)
@Generable
struct WorkoutAnalysisQuery: Sendable {
    @Guide(description: "Specific query focus: 'intervals', 'reps', 'performance', 'verdicts', 'economy_and_efficiency', 'cadence_mechanics', 'cardiac_drift', 'splits', or 'full_telemetry'")
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

    @Guide(description: "Pass true if the runner mentions illness, pain, exhaustion, injury, or poor sleep in their prompt.")
    var userReportedDistress: Bool?
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
    @Guide(description: "Search target for comparison or ranking: 'outdoor' (for last outdoor run), 'indoor' (for treadmill), 'best_and_worst' (or 'arc', '30_days') to rank past 30 days workouts, or specific date (e.g. 'September 30' or 'MM/DD'), relative term ('previous', 'last run'), or modality ('tempo', 'intervals').")
    var target: String?

    @Guide(description: "Optional second workout target to compare against target. For example, if target is 'last indoor run', set compareWith to 'last outdoor run' or 'September 30' to get exact Swift mathematical comparison deltas between the two.")
    var compareWith: String?
}

@available(iOS 26.0, *)
@Generable
struct WorkoutMathQuery: Sendable {
    @Guide(description: "Mathematical operation to perform: 'pace_delta' (e.g. between '6:25' and '6:14'), 'distance_delta' (e.g. between '6.64' and '5.09'), 'heart_rate_delta' (e.g. between '147' and '157'), 'cadence_delta' (e.g. between '156' and '152'), 'difference' (valueA - valueB), or 'percentage_change'.")
    var operation: String

    @Guide(description: "First value or primary metric string (e.g. '6:25', '6.64', '156', '147')")
    var valueA: String

    @Guide(description: "Second value or baseline metric string (e.g. '6:14', '5.09', '152', '157')")
    var valueB: String

    @Guide(description: "Optional metric type: 'pace' (min:sec/km or min:sec/mi), 'heart_rate' (BPM), 'cadence' (SPM), 'distance' (km or mi), 'duration' (minutes or seconds)")
    var metricType: String?
}

// MARK: - FoundationModels Native Tools

/// Tool providing deterministic retrospective workout telemetry, biomechanics, and physiological verdicts.
@available(iOS 26.0, *)
struct FetchWorkoutTelemetryTool: Tool {
    typealias Arguments = WorkoutAnalysisQuery
    typealias Output = String

    let name = "fetchWorkoutTelemetry"
    let description = "Retrieves deterministic overall workout telemetry for this run. For interval workouts, delivers the primary interval_scorecard and complete reps array (work pace, cadence, HR, and grade) as the primary workload, with blended session totals demoted. For continuous runs, delivers kilometer splits and steady pacing metrics."

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

/// Tool providing deterministic retrospective workout telemetry, biomechanics, and physiological verdicts.
@available(iOS 26.0, *)
struct FetchWorkoutAnalysisTool: Tool {
    typealias Arguments = WorkoutAnalysisQuery
    typealias Output = String

    let name = "fetchWorkoutAnalysis"
    let description = "Retrieves deterministic overall workout telemetry for this run. For interval workouts, delivers the primary interval_scorecard and complete reps array (work pace, cadence, HR, and grade) as the primary workload, with blended session totals demoted. For continuous runs, delivers kilometer splits and steady pacing metrics."

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
    let description = "Retrieves historical workout telemetry from the athlete's recorded history (such as past outdoor runs, treadmill sessions, specific dates, or 30-day rankings) and calculates exact mathematical comparisons and telemetry deltas against the current run."

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

/// Tool providing deterministic running math calculations: pace deltas, distance gaps, heart rate changes, and percentages.
@available(iOS 26.0, *)
struct ComputeWorkoutMathTool: Tool {
    typealias Arguments = WorkoutMathQuery
    typealias Output = String

    let name = "computeWorkoutMath"
    let description = "Calculates exact deterministic running math: pace deltas (seconds/km and percentage differences), distance deltas with consistent precision, heart rate gaps, cadence differences, and percentage changes between any two workout metrics. Call this instead of calculating numbers mentally."

    let provider: @MainActor @Sendable (WorkoutMathQuery) async -> String

    init(provider: @escaping @MainActor @Sendable (WorkoutMathQuery) async -> String) {
        self.provider = provider
    }

    func call(arguments: WorkoutMathQuery) async throws -> String {
        await provider(arguments)
    }
}
#endif
