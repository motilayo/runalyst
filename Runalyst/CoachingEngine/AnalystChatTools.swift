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

    // WORKING STATS (Pause-trimmed moving metrics - default in RunDetailView)
    public let working_stats: WorkingStatsDetail?

    // WORKOUT STATS (Gross Apple HealthKit session metrics including stopped time)
    public let workout_stats: WorkoutStatsDetail?

    // SECONDARY BACKGROUND (Blended session data - demoted so LLM doesn't confuse it)
    public let background_session_totals: BlendedTotals

    // Indisputable causal physiological diagnoses computed locally in Swift
    public let physiological_verdicts: String

    // Verification of sensor plausibility and omission status
    public let heart_rate_confidence: String?
    public let heart_rate_status: String?

    // Duration boundary tagging
    public let duration_summary: String?

    // Canonical compact explainer dictionary grounding the metrics present in this run
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
        physiological_verdicts: String,
        heart_rate_confidence: String? = nil,
        heart_rate_status: String? = nil,
        duration_summary: String? = nil,
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
        self.physiological_verdicts = physiological_verdicts
        self.heart_rate_confidence = heart_rate_confidence
        self.heart_rate_status = heart_rate_status
        self.duration_summary = duration_summary
        self.metric_explainers = metric_explainers
    }
}

/// Delineates pause-trimmed active moving metrics from gross session totals.
public struct WorkingStatsDetail: Codable, Sendable {
    public let moving_time: String
    public let moving_pace: String
    public let working_cadence_spm: Int
    public let working_heart_rate_bpm: Int?
    public let _description: String

    public init(
        moving_time: String,
        moving_pace: String,
        working_cadence_spm: Int,
        working_heart_rate_bpm: Int? = nil,
        _description: String = "Active moving metrics with pauses, red lights, and walking breaks filtered out."
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
    public let _description: String

    public init(
        total_time: String,
        gross_pace: String,
        raw_cadence_spm: Int,
        raw_heart_rate_bpm: Int? = nil,
        _description: String = "Gross HealthKit session totals from start to finish including stopped time and walking."
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
    public let observation: String?

    public init(
        split_index: Int,
        pace: String,
        cadence_spm: Int,
        heart_rate_bpm: Int? = nil,
        heart_rate_status: String? = nil,
        grade: String,
        observation: String? = nil
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
        _description: String = "Whole-session averages including warm-up, recoveries, and cooldown.",
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

public struct ScheduledDaySummary: Codable, Sendable {
    public let day_name: String
    public let session_title: String
    public let duration_band: String
    public let target_pace_or_effort: String
    public let is_rest_day: Bool
    public let rationale: String

    public init(
        day_name: String,
        session_title: String,
        duration_band: String,
        target_pace_or_effort: String,
        is_rest_day: Bool,
        rationale: String
    ) {
        self.day_name = day_name
        self.session_title = session_title
        self.duration_band = duration_band
        self.target_pace_or_effort = target_pace_or_effort
        self.is_rest_day = is_rest_day
        self.rationale = rationale
    }
}

public struct TodayWorkloadEvaluation: Codable, Sendable {
    public let sessions_completed_today_count: Int
    public let completed_sessions_summary: [String]
    public let total_duration_today: String
    public let total_distance_today: String
    public let daily_target_duration_band: String
    public let daily_target_completion_percent: Int
    public let acute_load_and_strain_factors: String
    public let has_done_sufficient_work_today: Bool
    public let should_run_again_today: Bool
    public let sufficiency_verdict: String
    public let second_run_or_supplemental_prescription: String

    public init(
        sessions_completed_today_count: Int,
        completed_sessions_summary: [String],
        total_duration_today: String,
        total_distance_today: String,
        daily_target_duration_band: String,
        daily_target_completion_percent: Int,
        acute_load_and_strain_factors: String,
        has_done_sufficient_work_today: Bool,
        should_run_again_today: Bool,
        sufficiency_verdict: String,
        second_run_or_supplemental_prescription: String
    ) {
        self.sessions_completed_today_count = sessions_completed_today_count
        self.completed_sessions_summary = completed_sessions_summary
        self.total_duration_today = total_duration_today
        self.total_distance_today = total_distance_today
        self.daily_target_duration_band = daily_target_duration_band
        self.daily_target_completion_percent = daily_target_completion_percent
        self.acute_load_and_strain_factors = acute_load_and_strain_factors
        self.has_done_sufficient_work_today = has_done_sufficient_work_today
        self.should_run_again_today = should_run_again_today
        self.sufficiency_verdict = sufficiency_verdict
        self.second_run_or_supplemental_prescription = second_run_or_supplemental_prescription
    }
}

/// The definitive structure returned to the LLM on readiness and prescription tool call.
public struct ReadinessToolResponse: Codable, Sendable {
    public let schema_name: String
    public let readiness_verdict: String
    public let recovery_status: String
    public let next_run_timing: String?
    public let prescribed_session_name: String
    public let primer_drill_name: String?
    public let intensity_category: String
    public let prescribed_pace_band: String
    public let prescribed_duration_band: String
    public let prescribed_cadence_band: String
    public let session_rationale: String
    public let guidance_notes: [String: String]?
    public let upcoming_weekly_schedule: [ScheduledDaySummary]?
    public let today_workload_evaluation: TodayWorkloadEvaluation?

    public init(
        schema_name: String = "READINESS_AND_PRESCRIPTION_RESPONSE",
        readiness_verdict: String,
        recovery_status: String,
        next_run_timing: String? = nil,
        prescribed_session_name: String,
        primer_drill_name: String? = nil,
        intensity_category: String,
        prescribed_pace_band: String,
        prescribed_duration_band: String,
        prescribed_cadence_band: String,
        session_rationale: String,
        guidance_notes: [String: String]? = nil,
        upcoming_weekly_schedule: [ScheduledDaySummary]? = nil,
        today_workload_evaluation: TodayWorkloadEvaluation? = nil
    ) {
        self.schema_name = schema_name
        self.readiness_verdict = readiness_verdict
        self.recovery_status = recovery_status
        self.next_run_timing = next_run_timing
        self.prescribed_session_name = prescribed_session_name
        self.primer_drill_name = primer_drill_name
        self.intensity_category = intensity_category
        self.prescribed_pace_band = prescribed_pace_band
        self.prescribed_duration_band = prescribed_duration_band
        self.prescribed_cadence_band = prescribed_cadence_band
        self.session_rationale = session_rationale
        self.guidance_notes = guidance_notes
        self.upcoming_weekly_schedule = upcoming_weekly_schedule
        self.today_workload_evaluation = today_workload_evaluation
    }
}
// swiftlint:enable identifier_name

#if canImport(FoundationModels)
import FoundationModels

// MARK: - Consolidated Native Tool Enums & Schemas

@available(iOS 26.0, *)
@Generable
public enum TrainingFocus: String, Sendable {
    case readiness = "readiness"
    case history = "history"
    case athleteProfile = "athlete_profile"
    case weeklySchedule = "weekly_schedule"
    case todayWorkload = "today_workload"
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
public struct InspectWorkoutQuery: Sendable {
    public init() {}
}

@available(iOS 26.0, *)
@Generable
public struct ManageTrainingStateQuery: Sendable {
    @Guide(description: "Focus: 'readiness' for recovery and tomorrow's prescription; 'weekly_schedule' for the upcoming multi-day schedule; 'today_workload' for evaluating whether today's workload is sufficient and if a second run is advisable; 'history' for mathematical comparisons or lookups with past runs; 'athlete_profile' for load and cadence floor.")
    public var focus: TrainingFocus

    @Guide(description: "Set to true if the runner mentions illness, pain, exhaustion, injury, or severe distress.")
    public var userReportedDistress: Bool?

    @Guide(description: "History scope: 'lookup' retrieves specific historical runs by criteria (e.g. oldest run, longest run, March 2025); 'compare' diffs the current run against historyTarget; 'performance_arc' ranks the past 30 days best to worst; 'recent_runs' lists recent workouts.")
    public var historyScope: HistoryScope?

    @Guide(description: "Past run to lookup or compare: 'oldest', 'first', 'previous', 'longest', 'fastest', 'last outdoor', 'last indoor', a modality like 'tempo', or a date like 'March 21, 2025'.")
    public var historyTarget: String?

    @Guide(description: "Optional second past run; when set, historyTarget is compared against this run instead of the current one.")
    public var historyCompareWith: String?

    public init(
        focus: TrainingFocus,
        userReportedDistress: Bool? = nil,
        historyScope: HistoryScope? = nil,
        historyTarget: String? = nil,
        historyCompareWith: String? = nil
    ) {
        self.focus = focus
        self.userReportedDistress = userReportedDistress
        self.historyScope = historyScope
        self.historyTarget = historyTarget
        self.historyCompareWith = historyCompareWith
    }
}

@available(iOS 26.0, *)
@Generable
public struct ExecuteCoachActionQuery: Sendable {
    @Guide(description: "Action: 'display_session' to present the interactive next single workout session card; 'display_schedule' to present the upcoming weekly training schedule card; 'display_drill' to present an interactive drill card; 'display_explainer' to present an educational concept card explaining a biomechanical or physiological metric (e.g. cadence floor, cardiac drift, efficiency factor); 'update_goal' to adjust training goal; 'export_to_watch' to schedule a workout to Apple Watch; 'record_feedback' to save subjective feedback.")
    public var action: CoachActionType

    @Guide(description: "Payload: workout or drill name (e.g. 'cadence_pyramids', 'strides') for 'display_drill' and 'export_to_watch'; metric or concept key (e.g. 'cadence_floor', 'cardiac_drift', 'efficiency_factor') for 'display_explainer'; race goal (e.g. 'Base Building', '5K', 'Marathon') for 'update_goal'; subjective notes for 'record_feedback'.")
    public var payload: String?

    public init(action: CoachActionType, payload: String? = nil) {
        self.action = action
        self.payload = payload
    }
}

// MARK: - FoundationModels Native Tools

/// Consolidated tool returning full unified workout telemetry without fragmentation.
@available(iOS 26.0, *)
public struct InspectWorkoutTool: Tool {
    public typealias Arguments = InspectWorkoutQuery
    public typealias Output = String

    public let name = "inspectWorkout"
    public let description = "Inspects the current workout. Returns the complete unified telemetry payload: moving stats vs gross workout stats, splits, interval scorecard, individual reps, physics, and physiological diagnoses."

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

/// Consolidated tool managing readiness, historical comparisons, and athlete profile state.
@available(iOS 26.0, *)
public struct ManageTrainingStateTool: Tool {
    public typealias Arguments = ManageTrainingStateQuery
    public typealias Output = String

    public let name = "manageTrainingState"
    public let description = "Manages athlete training state across three foci: 'readiness' (recovery timeline and locked prescription for tomorrow), 'history' (mathematical comparisons against past runs or performance arcs), and 'athlete_profile' (experience level, 30-day load, and cadence floor)."

    let provider: @MainActor @Sendable (ManageTrainingStateQuery) async -> String

    public init(provider: @escaping @MainActor @Sendable (ManageTrainingStateQuery) async -> String) {
        self.provider = provider
    }

    public func call(arguments: ManageTrainingStateQuery) async throws -> String {
        await provider(arguments)
    }
}

/// Consolidated tool executing interactive coaching actions.
@available(iOS 26.0, *)
public struct ExecuteCoachActionTool: Tool {
    public typealias Arguments = ExecuteCoachActionQuery
    public typealias Output = String

    public let name = "executeCoachAction"
    public let description = "Executes coaching actions: 'display_session' to show the next workout session card; 'display_drill' to show a drill card; 'display_explainer' to show a metric explainer card; 'update_goal' to adjust training goal; 'export_to_watch' to schedule a workout to Apple Watch; 'record_feedback' to save subjective feedback."

    let provider: @MainActor @Sendable (ExecuteCoachActionQuery) async -> String

    public init(provider: @escaping @MainActor @Sendable (ExecuteCoachActionQuery) async -> String) {
        self.provider = provider
    }

    public func call(arguments: ExecuteCoachActionQuery) async throws -> String {
        await provider(arguments)
    }
}

#endif
