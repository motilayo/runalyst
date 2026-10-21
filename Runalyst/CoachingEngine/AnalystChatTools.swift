import Foundation

// MARK: - Unified Native Tool Schemas
// swiftlint:disable identifier_name

// MARK: - Sensor & Duration Categorization Enums

public enum SensorConfidence: String, Codable, Sendable {
    case reliable
    case unreliableArtifact = "unreliable_sensor_artifact"
    case omitted
}

public enum HeartRateStatus: String, Codable, Sendable {
    case reliable
    case sensorLockAnomaly = "sensor_lock_anomaly"
    case omitted
}

public enum DurationClass: String, Codable, Sendable {
    case primer
    case short
    case standard
    case long
}

public struct DurationDetail: Codable, Sendable, Equatable {
    public let duration_class: DurationClass
    public let moving_minutes: Int
    public let total_minutes: Int

    public init(duration_class: DurationClass, moving_minutes: Int, total_minutes: Int) {
        self.duration_class = duration_class
        self.moving_minutes = moving_minutes
        self.total_minutes = total_minutes
    }
}

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

    // WORKING STATS (Pause-trimmed moving metrics - default in RunDetailView)
    public let working_stats: WorkingStatsDetail?

    // WORKOUT STATS (Gross Apple HealthKit session metrics including stopped time)
    public let workout_stats: WorkoutStatsDetail?

    // SECONDARY BACKGROUND (Blended session data - demoted so LLM doesn't confuse it)
    public let background_session_totals: BlendedTotals

    // Structured causal physiological diagnosis findings
    public let findings: [PhysiologicalFinding]

    // Verification of sensor plausibility and omission status
    public let heart_rate_confidence: SensorConfidence?
    public let heart_rate_status: HeartRateStatus?

    // Duration classification
    public let duration: DurationDetail

    // Optional legacy fields for backward compatibility
    public let duration_summary: String?
    public let physiological_verdicts: String?
    public let metric_explainers: [String: String]?

    public init(
        schema_name: String = "UNIFIED_WORKOUT_TOOL_RESPONSE",
        workout_type: String,
        date: String,
        environment: String,
        interval_scorecard: IntervalScorecard? = nil,
        reps: [IntervalRepDetail]? = nil,
        steady_state_scorecard: SteadyStateScorecard? = nil,
        splits: [SplitDetail]? = nil,
        working_stats: WorkingStatsDetail? = nil,
        workout_stats: WorkoutStatsDetail? = nil,
        background_session_totals: BlendedTotals,
        findings: [PhysiologicalFinding] = [],
        heart_rate_confidence: SensorConfidence? = nil,
        heart_rate_status: HeartRateStatus? = nil,
        duration: DurationDetail = DurationDetail(duration_class: .standard, moving_minutes: 30, total_minutes: 30),
        duration_summary: String? = nil,
        physiological_verdicts: String? = nil,
        metric_explainers: [String: String]? = nil
    ) {
        self.schema_name = schema_name
        self.workout_type = workout_type
        self.date = date
        self.environment = environment
        self.interval_scorecard = interval_scorecard
        self.reps = reps
        self.steady_state_scorecard = steady_state_scorecard
        self.splits = splits
        self.working_stats = working_stats
        self.workout_stats = workout_stats
        self.background_session_totals = background_session_totals
        self.findings = findings
        self.heart_rate_confidence = heart_rate_confidence
        self.heart_rate_status = heart_rate_status
        self.duration = duration
        self.duration_summary = duration_summary
        self.physiological_verdicts = physiological_verdicts
        self.metric_explainers = metric_explainers
    }
}

/// Delineates pause-trimmed active moving metrics from gross session totals.
public struct WorkingStatsDetail: Codable, Sendable {
    public let moving_time: String
    public let moving_pace: String
    public let working_cadence_spm: Int
    public let working_heart_rate_bpm: Int?
    public let _description: String?

    public init(
        moving_time: String,
        moving_pace: String,
        working_cadence_spm: Int,
        working_heart_rate_bpm: Int? = nil,
        _description: String? = nil
    ) {
        self.moving_time = moving_time
        self.moving_pace = moving_pace
        self.working_cadence_spm = working_cadence_spm
        self.working_heart_rate_bpm = working_heart_rate_bpm
        self._description = _description
    }
}

/// Delineates gross HealthKit session totals from active moving metrics.
public struct WorkoutStatsDetail: Codable, Sendable {
    public let total_time: String
    public let gross_pace: String
    public let raw_cadence_spm: Int
    public let raw_heart_rate_bpm: Int?
    public let _description: String?

    public init(
        total_time: String,
        gross_pace: String,
        raw_cadence_spm: Int,
        raw_heart_rate_bpm: Int? = nil,
        _description: String? = nil
    ) {
        self.total_time = total_time
        self.gross_pace = gross_pace
        self.raw_cadence_spm = raw_cadence_spm
        self.raw_heart_rate_bpm = raw_heart_rate_bpm
        self._description = _description
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
    public let flags: [String]
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
        flags: [String] = [],
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
        self.flags = flags
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
    public let flags: [String]
    public let observation: String?

    public init(
        split_index: Int,
        pace: String,
        cadence_spm: Int,
        heart_rate_bpm: Int? = nil,
        heart_rate_status: String? = nil,
        grade: String,
        flags: [String] = [],
        observation: String? = nil
    ) {
        self.split_index = split_index
        self.pace = pace
        self.cadence_spm = cadence_spm
        self.heart_rate_bpm = heart_rate_bpm
        self.heart_rate_status = heart_rate_status
        self.grade = grade
        self.flags = flags
        self.observation = observation
    }
}

public struct BlendedTotals: Codable, Sendable {
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
    public let _description: String?

    public init(
        _description: String? = nil,
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

public struct HistoricalRunSummary: Codable, Sendable, Equatable {
    public let date: String
    public let weekday: String
    public let classification: String
    public let environment: String
    public let distance_km: Double
    public let duration_minutes: Int
    public let pace: String
    public let cadence_spm: Int
    public let heart_rate_bpm: Int?
    public let efficiency_factor: Double?

    public init(
        date: String,
        weekday: String,
        classification: String,
        environment: String,
        distance_km: Double,
        duration_minutes: Int,
        pace: String,
        cadence_spm: Int,
        heart_rate_bpm: Int? = nil,
        efficiency_factor: Double? = nil
    ) {
        self.date = date
        self.weekday = weekday
        self.classification = classification
        self.environment = environment
        self.distance_km = distance_km
        self.duration_minutes = duration_minutes
        self.pace = pace
        self.cadence_spm = cadence_spm
        self.heart_rate_bpm = heart_rate_bpm
        self.efficiency_factor = efficiency_factor
    }
}

// MARK: - Orthogonal Domain Entities (Zero Scripted Dialogue)

public struct CompletedWorkoutSummary: Codable, Sendable, Equatable {
    public let type: String
    public let minutes: Double
    public let distance: Double
    public let unit: String
    public let grade: String?
    public let targetMet: Bool?
    public let avgHeartRate: Int?
    public let avgCadence: Int?

    public init(
        type: String,
        minutes: Double,
        distance: Double,
        unit: String,
        grade: String? = nil,
        targetMet: Bool? = nil,
        avgHeartRate: Int? = nil,
        avgCadence: Int? = nil
    ) {
        self.type = type
        self.minutes = minutes
        self.distance = distance
        self.unit = unit
        self.grade = grade
        self.targetMet = targetMet
        self.avgHeartRate = avgHeartRate
        self.avgCadence = avgCadence
    }
}

public struct ScheduleDay: Codable, Sendable, Equatable {
    public enum RelativeDay: String, Codable, Sendable {
        case today
        case tomorrow
        case past
        case future
    }
    public enum CompletionStatus: String, Codable, Sendable {
        case completed
        case partial
        case pending
        case missed
        case upcoming
    }

    public let date: String
    public let weekday: String
    public let relative: RelativeDay
    public let completion: CompletionStatus
    public let completed: [CompletedWorkoutSummary]
    public let planned: PlannedSession

    public init(
        date: String,
        weekday: String,
        relative: RelativeDay,
        completion: CompletionStatus,
        completed: [CompletedWorkoutSummary],
        planned: PlannedSession
    ) {
        self.date = date
        self.weekday = weekday
        self.relative = relative
        self.completion = completion
        self.completed = completed
        self.planned = planned
    }
}

public struct ReadinessFacts: Codable, Sendable, Equatable {
    public let readiness_state: String
    public let acwr: Double?
    public let streak_days: Int
    public let streak_limit: Int
    public let last_48h_minutes: Double
    public let weekly_avg_minutes: Double
    public let volume_ratio_48h: Double
    public let volume_threshold: Double
    public let hr_shift_bpm: Double
    public let today_minutes: Double
    public let today_target_minutes: Int
    public let today_completion_percent: Int
    public let second_run_advisable: Bool
    public let limiting_factors: [String]
    public let experience_level: String
    public let training_goal: String
    public let cadence_floor_spm: Int

    public init(
        readiness_state: String,
        acwr: Double?,
        streak_days: Int,
        streak_limit: Int,
        last_48h_minutes: Double,
        weekly_avg_minutes: Double,
        volume_ratio_48h: Double,
        volume_threshold: Double,
        hr_shift_bpm: Double,
        today_minutes: Double,
        today_target_minutes: Int,
        today_completion_percent: Int,
        second_run_advisable: Bool,
        limiting_factors: [String],
        experience_level: String,
        training_goal: String,
        cadence_floor_spm: Int
    ) {
        self.readiness_state = readiness_state
        self.acwr = acwr
        self.streak_days = streak_days
        self.streak_limit = streak_limit
        self.last_48h_minutes = last_48h_minutes
        self.weekly_avg_minutes = weekly_avg_minutes
        self.volume_ratio_48h = volume_ratio_48h
        self.volume_threshold = volume_threshold
        self.hr_shift_bpm = hr_shift_bpm
        self.today_minutes = today_minutes
        self.today_target_minutes = today_target_minutes
        self.today_completion_percent = today_completion_percent
        self.second_run_advisable = second_run_advisable
        self.limiting_factors = limiting_factors
        self.experience_level = experience_level
        self.training_goal = training_goal
        self.cadence_floor_spm = cadence_floor_spm
    }
}
// swiftlint:enable identifier_name

#if canImport(FoundationModels)
import FoundationModels

// MARK: - Native Tool Enums & Schemas

@available(iOS 26.0, *)
@Generable
public enum TrainingGoal: String, Sendable {
    case baseBuilding = "Base Building"
    case fiveK = "5K Race"
    case tenK = "10K Race"
    case halfMarathon = "Half Marathon"
    case marathon = "Marathon"
    case justForFun = "Just for Fun"
    case injuryRecovery = "Injury Recovery"
}

@available(iOS 26.0, *)
@Generable
public enum HistoryScope: String, Sendable {
    case compare = "compare"
    case performanceArc = "performance_arc"
    case recentRuns = "recent_runs"
    case lookup = "lookup"
}

@available(iOS 26.0, *)
@Generable
public enum CoachActionType: String, Sendable {
    case displaySession = "display_session"
    case displaySchedule = "display_schedule"
    case displayDrill = "display_drill"
    case displayExplainer = "display_explainer"
    case exportToWatch = "export_to_watch"
    case updateGoal = "update_goal"
    case recordFeedback = "record_feedback"
}

@available(iOS 26.0, *)
@Generable
public struct GetTrainingScheduleQuery: Sendable {
    @Guide(description: "Start of schedule window in ISO format 'yyyy-MM-dd' (e.g. '2026-10-20').")
    public var from: String

    @Guide(description: "Optional end of schedule window in ISO format 'yyyy-MM-dd'. If omitted, defaults to the 'from' date.")
    public var to: String?

    public init(from: String, to: String? = nil) {
        self.from = from
        self.to = to
    }
}

@available(iOS 26.0, *)
@Generable
public struct GetReadinessAndWorkloadQuery: Sendable {
    @Guide(description: "Set to true if runner reports pain, illness, extreme fatigue, or injury.")
    public var userReportedDistress: Bool?

    public init(userReportedDistress: Bool? = nil) {
        self.userReportedDistress = userReportedDistress
    }
}

@available(iOS 26.0, *)
@Generable
public struct QueryWorkoutHistoryQuery: Sendable {
    @Guide(description: "Scope: 'compare' diffs against target run; 'performance_arc' ranks past 30 days; 'recent_runs' lists recent workouts; 'lookup' finds specific run.")
    public var scope: HistoryScope

    @Guide(description: "Past run to lookup or compare: 'oldest', 'previous', 'longest', 'fastest', or a date like 'March 21, 2025'.")
    public var target: String?

    @Guide(description: "Optional second past run to compare target against.")
    public var compareWith: String?

    public init(scope: HistoryScope, target: String? = nil, compareWith: String? = nil) {
        self.scope = scope
        self.target = target
        self.compareWith = compareWith
    }
}

@available(iOS 26.0, *)
@Generable
public struct InspectWorkoutQuery: Sendable {
    public init() {}
}

@available(iOS 26.0, *)
@Generable
public struct ExecuteCoachActionQuery: Sendable {
    @Guide(description: "Action: 'display_schedule' to show training schedule card; 'display_session' for single session; 'display_drill' for interactive drill card; 'display_explainer' for metric concept; 'update_goal' to adjust goal; 'export_to_watch' to schedule workout; 'record_feedback' to save feedback.")
    public var action: CoachActionType

    @Guide(description: "Start date in 'yyyy-MM-dd' format for display_schedule.")
    public var from: String?

    @Guide(description: "End date in 'yyyy-MM-dd' format for display_schedule.")
    public var to: String?

    @Guide(description: "New goal for 'update_goal'.")
    public var goal: TrainingGoal?

    @Guide(description: "Payload: canonical drill id ('cadence_pyramids', 'rhythm_intervals', 'tempo_surges', 'strides') for 'display_drill' and 'export_to_watch'; metric key for 'display_explainer'; subjective notes for 'record_feedback'.")
    public var payload: String?

    public init(
        action: CoachActionType,
        from: String? = nil,
        to: String? = nil,
        goal: TrainingGoal? = nil,
        payload: String? = nil
    ) {
        self.action = action
        self.from = from
        self.to = to
        self.goal = goal
        self.payload = payload
    }
}

// MARK: - FoundationModels Orthogonal Native Tools

/// Queries the athlete's training calendar over any timeline interval.
@available(iOS 26.0, *)
public struct GetTrainingScheduleTool: Tool {
    public typealias Arguments = GetTrainingScheduleQuery
    public typealias Output = String

    public let name = "getTrainingSchedule"
    public let description = "Queries planned workouts and completed activity across any calendar date range (ISO 'yyyy-MM-dd'). Returns completion status, logged sessions, and planned prescriptions."

    let provider: @MainActor @Sendable (GetTrainingScheduleQuery) async -> String

    public init(provider: @escaping @MainActor @Sendable (GetTrainingScheduleQuery) async -> String) {
        self.provider = provider
    }

    public func call(arguments: GetTrainingScheduleQuery) async throws -> String {
        await provider(arguments)
    }
}

/// Queries biological recovery, ACWR, volume compression, and second-run safety.
@available(iOS 26.0, *)
public struct GetReadinessAndWorkloadTool: Tool {
    public typealias Arguments = GetReadinessAndWorkloadQuery
    public typealias Output = String

    public let name = "getReadinessAndWorkload"
    public let description = "Queries physiological recovery, ACWR, 48h volume compression, cardiac decoupling, and same-day workload capacity."

    let provider: @MainActor @Sendable (GetReadinessAndWorkloadQuery) async -> String

    public init(provider: @escaping @MainActor @Sendable (GetReadinessAndWorkloadQuery) async -> String) {
        self.provider = provider
    }

    public func call(arguments: GetReadinessAndWorkloadQuery) async throws -> String {
        await provider(arguments)
    }
}

/// Compares workouts or retrieves historical performance arcs.
@available(iOS 26.0, *)
public struct QueryWorkoutHistoryTool: Tool {
    public typealias Arguments = QueryWorkoutHistoryQuery
    public typealias Output = String

    public let name = "queryWorkoutHistory"
    public let description = "Queries historical workout data: compares current run with past runs, ranks 30-day performance arc, or looks up specific runs."

    let provider: @MainActor @Sendable (QueryWorkoutHistoryQuery) async -> String

    public init(provider: @escaping @MainActor @Sendable (QueryWorkoutHistoryQuery) async -> String) {
        self.provider = provider
    }

    public func call(arguments: QueryWorkoutHistoryQuery) async throws -> String {
        await provider(arguments)
    }
}

/// Inspects moving vs gross telemetry for the active workout.
@available(iOS 26.0, *)
public struct InspectWorkoutTool: Tool {
    public typealias Arguments = InspectWorkoutQuery
    public typealias Output = String

    public let name = "inspectWorkout"
    public let description = "Inspects the current workout. Returns moving stats vs gross stats, splits, intervals, reps, and physical findings."

    let provider: @MainActor @Sendable (InspectWorkoutQuery) async -> String

    public init(provider: @escaping @MainActor @Sendable (InspectWorkoutQuery) async -> String) {
        self.provider = provider
    }

    public init(simpleProvider: @escaping @MainActor @Sendable () async -> String) {
        self.provider = { _ in await simpleProvider() }
    }

    public func call(arguments: InspectWorkoutQuery) async throws -> String {
        await provider(arguments)
    }
}

/// Executes interactive coaching actions and presents visual UI cards.
@available(iOS 26.0, *)
public struct ExecuteCoachActionTool: Tool {
    public typealias Arguments = ExecuteCoachActionQuery
    public typealias Output = String

    public let name = "executeCoachAction"
    public let description = "Executes coaching actions: 'display_schedule' to present schedule card (from..to); 'display_drill' for drill card; 'display_explainer' for metric concept card; 'update_goal' to adjust goal; 'export_to_watch' to schedule workout; 'record_feedback' to save feedback."

    let provider: @MainActor @Sendable (ExecuteCoachActionQuery) async -> String

    public init(provider: @escaping @MainActor @Sendable (ExecuteCoachActionQuery) async -> String) {
        self.provider = provider
    }

    public func call(arguments: ExecuteCoachActionQuery) async throws -> String {
        await provider(arguments)
    }
}

#endif
