import Foundation
import SwiftData
import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Chat message model for the interactive AI Analyst conversation.
struct AnalystChatMessage: Identifiable, Equatable {
    let id: UUID
    let sender: MessageSender
    let text: String
    let timestamp: Date
    let attachedDrillId: PreRunDrillId?
    let attachedSession: PrescribedDailySession?
    let attachedExplainerKey: String?
    let attachedSchedule: [MicrocycleDay]?

    enum MessageSender: Equatable {
        case user
        case analyst
    }

    init(
        id: UUID = UUID(),
        sender: MessageSender,
        text: String,
        timestamp: Date = Date(),
        attachedDrillId: PreRunDrillId? = nil,
        attachedSession: PrescribedDailySession? = nil,
        attachedExplainerKey: String? = nil,
        attachedSchedule: [MicrocycleDay]? = nil
    ) {
        self.id = id
        self.sender = sender
        self.text = text
        self.timestamp = timestamp
        self.attachedDrillId = attachedDrillId
        self.attachedSession = attachedSession
        self.attachedExplainerKey = attachedExplainerKey
        self.attachedSchedule = attachedSchedule
    }
}

typealias AnalystChatSender = AnalystChatMessage.MessageSender

/// Defines the scope and framing of an AI Analyst conversation.
enum AnalystChatMode: Equatable, Sendable {
    /// Anchored to inspecting a specific historical workout.
    case runInspection
    /// Anchored globally as the athlete's macro running & recovery coach.
    case macroCoach
}

/// Actor managing the interactive RAG Analyst Chat session with FoundationModels and strict operational guardrails.
@MainActor
class AnalystChatEngine: ObservableObject {
    @Published var messages: [AnalystChatMessage] = []
    @Published var isResponding: Bool = false

    private let mode: AnalystChatMode
    private let runSignature: RunSignature?
    private let macroProfile: MacroProfile?
    private let runRecord: RunRecord

    #if canImport(FoundationModels)
    private var modelSession: Any? // LanguageModelSession on iOS 26+
    /// Tracks a drill recommended during the active conversation turn.
    var drillRecommendedThisTurn: PreRunDrillId?
    /// Tracks a prescribed daily session recommended during the active conversation turn.
    var sessionRecommendedThisTurn: PrescribedDailySession?
    /// Tracks an interactive explainer card recommended during the active conversation turn.
    var explainerRecommendedThisTurn: String?
    /// Tracks an upcoming schedule card recommended during the active conversation turn.
    var scheduleRecommendedThisTurn: [MicrocycleDay]?
    #endif

    #if DEBUG
    /// Optional closure allowing unit tests to simulate model free-speech responses and inspect system instructions.
    var modelResponder: ((_ systemInstructions: String, _ userQuestion: String) async throws -> String)?
    #endif

    private var baselineStats: (avgPace: Double, avgCadence: Double, avgHR: Double)? {
        guard let context = runRecord.modelContext,
              let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: runRecord.date) else {
            return nil
        }
        let targetDate = runRecord.date
        let descriptor = FetchDescriptor<RunRecord>(
            predicate: #Predicate<RunRecord> { $0.date >= thirtyDaysAgo && $0.date < targetDate }
        )
        guard let prior = try? context.fetch(descriptor), !prior.isEmpty else { return nil }
        let validPaces = prior.map(\.workingAvgPace).filter { $0 > 0 }
        let validCads = prior.map(\.workingAvgCadence).filter { $0 > 0 }
        let validHRs = prior.map(\.workingAvgHeartRate).filter { $0 > 0 }
        guard !validPaces.isEmpty, !validCads.isEmpty, !validHRs.isEmpty else { return nil }
        return (
            avgPace: validPaces.reduce(0, +) / Double(validPaces.count),
            avgCadence: validCads.reduce(0, +) / Double(validCads.count),
            avgHR: validHRs.reduce(0, +) / Double(validHRs.count)
        )
    }

    init(
        runRecord: RunRecord,
        mode: AnalystChatMode = .runInspection,
        runSignature: RunSignature? = nil,
        macroProfile: MacroProfile? = nil
    ) {
        self.runRecord = runRecord
        self.mode = mode
        self.runSignature = runSignature ?? runRecord.signature
        self.macroProfile = macroProfile ?? MacroProfile.load()
    }

    /// Sends a runner question and generates an analyst response with RAG telemetry context and guardrails.
    func sendMessage(_ userQuestion: String) async {
        let trimmed = userQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        messages.append(AnalystChatMessage(sender: .user, text: trimmed))
        isResponding = true
        defer { isResponding = false }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            self.drillRecommendedThisTurn = nil
            self.sessionRecommendedThisTurn = nil
            self.explainerRecommendedThisTurn = nil
            self.scheduleRecommendedThisTurn = nil
        }
        #endif

        // FoundationModels: the runner's message goes straight to the session.
        // Lean instructions + native tools only. No Swift intent parsing or output rewriting—
        // the model reads the tool spec and decides what to call.
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            #if DEBUG
            if let responder = modelResponder {
                do {
                    let responseText = try await responder(buildLeanSystemInstructions(), trimmed)
                    messages.append(AnalystChatMessage(sender: .analyst, text: responseText, attachedDrillId: drillRecommendedThisTurn, attachedSession: sessionRecommendedThisTurn, attachedExplainerKey: explainerRecommendedThisTurn, attachedSchedule: scheduleRecommendedThisTurn))
                    return
                } catch {
                    print("Model responder error: \(error)")
                }
            }
            #endif
            if SystemLanguageModel.default.isAvailable {
                do {
                    let responseText = try await generateFoundationModelResponse(for: trimmed)
                    messages.append(AnalystChatMessage(sender: .analyst, text: responseText, attachedDrillId: drillRecommendedThisTurn, attachedSession: sessionRecommendedThisTurn, attachedExplainerKey: explainerRecommendedThisTurn, attachedSchedule: scheduleRecommendedThisTurn))
                    return
                } catch {
                    print("FoundationModels chat error: \(error)")
                    self.modelSession = nil
                }
            }
        }
        #endif

        // No simulated coach: if the on-device model can't answer, say so honestly.
        messages.append(AnalystChatMessage(sender: .analyst, text: systemUnavailableMessage()))
    }

    // MARK: - Analysis Context Factory

    func makeAnalysisContext(isSubjectiveDistress: Bool = false) -> WorkoutAnalysisContext {
        let totalRuns = (try? runRecord.modelContext?.fetchCount(FetchDescriptor<RunRecord>())) ?? 1
        return WorkoutAnalysisContext(
            runRecord: runRecord,
            runSignature: runSignature,
            macroProfile: macroProfile,
            recoveryTimeline: recoveryTimeline,
            baselineStats: baselineStats,
            runnerProfile: runnerProfile,
            isSubjectiveDistress: isSubjectiveDistress,
            totalHistoricalRunsCount: totalRuns
        )
    }

    // MARK: - System Instructions

    #if canImport(FoundationModels)
    /// Context only: which run, which units, which language, and the medical boundary.
    /// Tool semantics live in each `Tool.description` / `@Guide`; facts live in tool payloads.
    @available(iOS 26.0, *)
    func buildLeanSystemInstructions() -> String {
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        let runType = runRecord.detectedTypeRaw.isEmpty ? "Run" : runRecord.detectedTypeRaw
        let envNote = (runRecord.isIndoor ?? false) ? "Indoor Treadmill" : "Outdoors"

        let cal = Calendar.current
        let daysDiff = cal.dateComponents([.day], from: cal.startOfDay(for: runRecord.date), to: cal.startOfDay(for: Date())).day ?? 0
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "EEE, MMM d"
        let dateStr = df.string(from: runRecord.date)

        let todayDF = DateFormatter()
        todayDF.locale = Locale(identifier: "en_US_POSIX")
        todayDF.dateFormat = "EEEE, MMM d"
        let todayStr = todayDF.string(from: Date())

        let useMetric = (UserDefaults.standard.object(forKey: "useMetricSystem") as? Bool) ?? true
        let unitSystem = useMetric ? "Metric (min/km, km)" : "Imperial (min/mi, mi)"

        let contextBlock: String

        if mode == .macroCoach {
            let allRuns = (try? runRecord.modelContext?.fetch(FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? [runRecord]
            let activeGoal = UserDefaults.standard.string(forKey: "trainingGoal") ?? "Base Building"
            let profile = RunnerProfile.compute(from: allRuns)
            let dailyState = SessionSynthesisEngine.evaluateDailyState(
                runRecords: allRuns,
                activeGoal: activeGoal,
                experienceLevel: profile.experienceLevel,
                useMetric: useMetric,
                userHeightCm: profile.userHeightCm,
                now: Date()
            )

            switch dailyState {
            case .preRun(let session):
                contextBlock = "Scope: Macro AI Coach. Today: \(todayStr).\nAthlete State: Pre-Run (no workouts logged today).\nNext Prescribed Session: TODAY — \(session.sessionTitle) (\(session.durationBand), \(session.paceBand)) with \(session.primerDrillTitle) primer."
            case .completedToday(let completedRun, let tomorrowSession):
                contextBlock = "Scope: Macro AI Coach. Today: \(todayStr).\nAthlete State: Completed Today (\(completedRun.workoutType) \(completedRun.distanceFormatted), Grade \(completedRun.letterGrade)). Daily load banked.\nNext Prescribed Session: TOMORROW — \(tomorrowSession.sessionTitle) (\(tomorrowSession.durationBand), \(tomorrowSession.paceBand))."
            }
        } else {
            let temporalGrounding = daysDiff == 0 ? "Today" : "\(dateStr) (\(daysDiff)d ago)"
            contextBlock = "Scope: Workout Inspection.\nReviewing: \(runType) (\(envNote), \(temporalGrounding))."
        }

        return """
        You are Runalyst—an intelligent, conversational running coach. Speak directly to the runner with warmth and encouragement.

        CONTEXT:
        \(contextBlock)
        Units: \(unitSystem).

        RULES:
        • NEXT RUN: If unrun today, next run is TODAY. If run today, next run is TOMORROW. Surface card via `executeCoachAction`.
        • Tools: Call to fetch telemetry, manage athlete state, or trigger cards.
        • `inspectWorkout`: moving/gross stats, splits, intervals, reps, physics.
        • `manageTrainingState`: 'readiness' (set userReportedDistress: true on pain/illness), 'weekly_schedule', 'today_workload', 'history', 'athlete_profile'.
        • `executeCoachAction`: 'display_session' (next run card), 'display_schedule' (weekly schedule card), 'display_drill', 'display_explainer', 'update_goal', 'export_to_watch', 'record_feedback'.
        • Formatting: Rich text. Standard units (SPM, min/km, min/mi). Never use Markdown or LaTeX.
        • Medical Safety: Prioritize rest on pain/illness, state AI disclaimer, urge medical care.
        • Outside Running: Warmly refocus on training. Never force drills.
        • Never hallucinate unverified telemetry.

        Respond in \(language).
        """
    }

    @available(iOS 26.0, *)
    func getOrCreateSession() -> LanguageModelSession {
        if let existing = modelSession as? LanguageModelSession {
            return existing
        }

        let inspectWorkoutTool = InspectWorkoutTool { [weak self] _ in
            guard let self else { return "" }
            return self.makeAnalysisContext().compactTelemetryAnalysis()
        }

        let manageTrainingTool = ManageTrainingStateTool { [weak self] query in
            guard let self else { return "" }
            switch query.focus {
            case .readiness:
                let isDistress = query.userReportedDistress == true
                let analysis = self.makeAnalysisContext(isSubjectiveDistress: isDistress)
                let rx = analysis.lockedPrescription
                let isReady = analysis.recoveryTimeline.readyForHard && !isDistress

                let verdict: String
                let recoveryStatus: String

                if isDistress || rx.isSubjectiveOverride {
                    verdict = "MANDATORY_REST_HEALTH_OVERRIDE"
                    recoveryStatus = "Runner reported illness, pain, or distress. Training suspended until symptoms resolve."
                } else if isReady {
                    verdict = "CLEARED_FOR_TRAINING"
                    recoveryStatus = "Fully recovered."
                } else {
                    verdict = "CLEARED_FOR_LIGHT_RECOVERY_ONLY"
                    recoveryStatus = "Light movement only until \(analysis.recoveryTimeline.earliestHardPhrase)."
                }

                // Deterministically evaluate the runner's daily session state
                let allRuns = (try? self.runRecord.modelContext?.fetch(FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? [self.runRecord]
                let activeGoal = UserDefaults.standard.string(forKey: "trainingGoal") ?? "Base Building"
                let profile = RunnerProfile.compute(from: allRuns)
                let useMetric = (UserDefaults.standard.object(forKey: "useMetricSystem") as? Bool) ?? true

                let dailyState = SessionSynthesisEngine.evaluateDailyState(
                    runRecords: allRuns,
                    activeGoal: activeGoal,
                    experienceLevel: profile.experienceLevel,
                    useMetric: useMetric,
                    userHeightCm: profile.userHeightCm,
                    now: Date()
                )

                let nextTiming: String
                let sessionName: String
                let durationBand: String
                let paceBand: String
                let cadenceBand: String
                let rationale: String
                let primerName: String?

                switch dailyState {
                case .preRun(let session):
                    nextTiming = "TODAY (Runner has NOT logged a run today. Today's proposed session IS the next run)"
                    sessionName = session.sessionTitle
                    durationBand = session.durationBand
                    paceBand = session.paceBand
                    cadenceBand = "≥ \(session.cadenceFloor) SPM"
                    rationale = session.groundedRationale
                    primerName = session.primerDrillTitle
                case .completedToday(let completedRun, let tomorrowSession):
                    nextTiming = "TOMORROW (Runner already banked today's workout: \(completedRun.workoutType) \(completedRun.distanceFormatted). Next run is tomorrow)"
                    sessionName = tomorrowSession.sessionTitle
                    durationBand = tomorrowSession.durationBand
                    paceBand = tomorrowSession.paceBand
                    cadenceBand = "≥ \(tomorrowSession.cadenceFloor) SPM"
                    rationale = tomorrowSession.groundedRationale
                    primerName = tomorrowSession.primerDrillTitle
                }

                let humanIntensity: String
                switch rx.intensityCategory {
                case "RECOVERY_FLUSH_ZONE_1":
                    humanIntensity = "Zone 1 Active Recovery"
                case "EASY_AEROBIC_ZONE_2":
                    humanIntensity = "Zone 2 Aerobic Base"
                case "FULL_REST_OVERRIDE":
                    humanIntensity = "Full Rest"
                case "EASY_AEROBIC_ASSESSMENT":
                    humanIntensity = "Aerobic Assessment"
                default:
                    humanIntensity = rx.intensityCategory.replacingOccurrences(of: "_", with: " ").capitalized
                }

                let guidance = CoachingAssetLibrary.readinessGuidance(for: verdict, isDistress: isDistress || rx.isSubjectiveOverride)
                let upcomingSchedule = self.buildUpcomingWeeklySchedule(dailyState: dailyState, contextDate: Date())
                let todayWorkload = self.buildTodayWorkloadEvaluation(allRuns: allRuns, profile: profile, activeGoal: activeGoal, useMetric: useMetric)

                let response = ReadinessToolResponse(
                    schema_name: "READINESS_AND_PRESCRIPTION_RESPONSE",
                    readiness_verdict: verdict,
                    recovery_status: recoveryStatus,
                    next_run_timing: nextTiming,
                    prescribed_session_name: sessionName,
                    primer_drill_name: primerName,
                    intensity_category: humanIntensity,
                    prescribed_pace_band: paceBand,
                    prescribed_duration_band: durationBand,
                    prescribed_cadence_band: cadenceBand,
                    session_rationale: rationale,
                    guidance_notes: guidance,
                    upcoming_weekly_schedule: upcomingSchedule,
                    today_workload_evaluation: todayWorkload
                )

                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
                if let data = try? encoder.encode(response),
                   let json = String(data: data, encoding: .utf8) {
                    return json
                }
                return "{\"intensity_category\":\"\(humanIntensity)\",\"prescribed_pace_band\":\"\(paceBand)\",\"prescribed_session_name\":\"\(sessionName)\",\"next_run_timing\":\"\(nextTiming)\",\"readiness_verdict\":\"\(verdict)\"}"

            case .weeklySchedule:
                let allRuns = (try? self.runRecord.modelContext?.fetch(FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? [self.runRecord]
                let activeGoal = UserDefaults.standard.string(forKey: "trainingGoal") ?? "Base Building"
                let profile = RunnerProfile.compute(from: allRuns)
                let useMetric = (UserDefaults.standard.object(forKey: "useMetricSystem") as? Bool) ?? true
                let dailyState = SessionSynthesisEngine.evaluateDailyState(
                    runRecords: allRuns,
                    activeGoal: activeGoal,
                    experienceLevel: profile.experienceLevel,
                    useMetric: useMetric,
                    userHeightCm: profile.userHeightCm,
                    now: Date()
                )
                let upcomingSchedule = self.buildUpcomingWeeklySchedule(dailyState: dailyState, contextDate: Date())
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
                if let data = try? encoder.encode(upcomingSchedule),
                   let json = String(data: data, encoding: .utf8) {
                    return "{\"active_goal\":\"\(activeGoal)\",\"schema_name\":\"WEEKLY_SCHEDULE_RESPONSE\",\"upcoming_schedule\":\(json)}"
                }
                return "{\"active_goal\":\"\(activeGoal)\",\"schema_name\":\"WEEKLY_SCHEDULE_RESPONSE\"}"

            case .todayWorkload:
                let allRuns = (try? self.runRecord.modelContext?.fetch(FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? [self.runRecord]
                let activeGoal = UserDefaults.standard.string(forKey: "trainingGoal") ?? "Base Building"
                let profile = RunnerProfile.compute(from: allRuns)
                let useMetric = (UserDefaults.standard.object(forKey: "useMetricSystem") as? Bool) ?? true
                let evaluation = self.buildTodayWorkloadEvaluation(allRuns: allRuns, profile: profile, activeGoal: activeGoal, useMetric: useMetric)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
                if let data = try? encoder.encode(evaluation),
                   let json = String(data: data, encoding: .utf8) {
                    return json
                }
                return "{\"has_done_sufficient_work_today\":\(evaluation.has_done_sufficient_work_today),\"sufficiency_verdict\":\"\(evaluation.sufficiency_verdict)\"}"

            case .history:
                let context = self.runRecord.modelContext
                switch query.historyScope ?? .compare {
                case .performanceArc:
                    return HistoricalRunMatcher.analyzePerformanceArc(relativeTo: self.runRecord, in: context).structuredTelemetryFacts
                case .recentRuns:
                    return HistoricalRunMatcher.listRecentRuns(relativeTo: self.runRecord, in: context)
                case .lookup:
                    let target = query.historyTarget.flatMap { $0.isEmpty ? nil : $0 } ?? "oldest"
                    return HistoricalRunMatcher.lookupRun(matching: target, relativeTo: self.runRecord, in: context)
                case .compare:
                    let target = query.historyTarget.flatMap { $0.isEmpty ? nil : $0 } ?? "previous"
                    if let other = query.historyCompareWith, !other.isEmpty,
                       let comparison = HistoricalRunMatcher.compareRuns(queryA: target, queryB: other, relativeTo: self.runRecord, in: context) {
                        return comparison.structuredTelemetryFacts
                    }
                    guard let prior = HistoricalRunMatcher.findRun(matching: target, relativeTo: self.runRecord, in: context) else {
                        return "{\"status\":\"no_matching_run\",\"target\":\"\(target)\"}"
                    }
                    return HistoricalRunMatcher.compare(current: self.runRecord, with: prior).structuredTelemetryFacts
                }

            case .athleteProfile:
                let profile = self.runnerProfile
                return """
                ATHLETE PROFILE:
                - Experience Level: \(profile.experienceLevel)
                - Training Goal: \(profile.trainingGoal)
                - 30-Day Load: \(profile.loadSummary)
                - Height-Calibrated Cadence Floor: \(profile.heightAdjustedCadenceFloor) SPM
                """
            }
        }

        let coachActionTool = ExecuteCoachActionTool { [weak self] query in
            guard let self else { return "" }
            switch query.action {
            case .displaySession:
                let allRuns = (try? self.runRecord.modelContext?.fetch(FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? [self.runRecord]
                let activeGoal = UserDefaults.standard.string(forKey: "trainingGoal") ?? "Base Building"
                let profile = RunnerProfile.compute(from: allRuns)
                let useMetric = (UserDefaults.standard.object(forKey: "useMetricSystem") as? Bool) ?? true
                let dailyState = SessionSynthesisEngine.evaluateDailyState(
                    runRecords: allRuns,
                    activeGoal: activeGoal,
                    experienceLevel: profile.experienceLevel,
                    useMetric: useMetric,
                    userHeightCm: profile.userHeightCm,
                    now: Date()
                )
                let sessionToAttach: PrescribedDailySession?
                switch dailyState {
                case .preRun(let session):
                    sessionToAttach = session
                case .completedToday(_, let tomorrowSession):
                    sessionToAttach = tomorrowSession
                }
                self.sessionRecommendedThisTurn = sessionToAttach
                let title = sessionToAttach?.sessionTitle ?? "Upcoming Workout"
                return "{\"session_title\":\"\(title)\",\"status\":\"session_card_displayed\"}"

            case .displaySchedule:
                let allRuns = (try? self.runRecord.modelContext?.fetch(FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? [self.runRecord]
                let activeGoal = UserDefaults.standard.string(forKey: "trainingGoal") ?? "Base Building"
                let profile = RunnerProfile.compute(from: allRuns)
                let useMetric = (UserDefaults.standard.object(forKey: "useMetricSystem") as? Bool) ?? true
                let dailyState = SessionSynthesisEngine.evaluateDailyState(
                    runRecords: allRuns,
                    activeGoal: activeGoal,
                    experienceLevel: profile.experienceLevel,
                    useMetric: useMetric,
                    userHeightCm: profile.userHeightCm,
                    now: Date()
                )
                let scheduleDays = self.buildMicrocycleForChat(dailyState: dailyState, contextDate: Date())
                self.scheduleRecommendedThisTurn = scheduleDays
                return "{\"days_count\":\(scheduleDays.count),\"status\":\"schedule_card_displayed\"}"

            case .displayDrill:
                let resolved = PreRunDrillId.resolve(from: query.payload ?? "") ?? .cadencePyramids
                self.drillRecommendedThisTurn = resolved

                let template = DrillTemplate.template(for: resolved)
                let baseCadence = Int(self.runRecord.workingAvgCadence) > 0 ? Int(self.runRecord.workingAvgCadence) : 155
                let target = template.calculateTargetCadence(baseCadence)
                let cue = template.generateInstructionalCue(target)

                let dto: [String: String] = [
                    "status": "interactive_drill_card_displayed",
                    "drill_id": resolved.rawValue,
                    "drill_name": resolved.title,
                    "purpose": template.defaultPurpose,
                    "target_cadence": target,
                    "instructional_cue": cue,
                    "duration_minutes": "\(resolved.defaultDuration.rawValue) min"
                ]
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
                if let data = try? encoder.encode(dto), let str = String(data: data, encoding: .utf8) {
                    return str
                }
                return "{\"drill_name\":\"\(resolved.title)\",\"status\":\"interactive_drill_card_displayed\"}"

            case .exportToWatch:
                let resolved = PreRunDrillId.resolve(from: query.payload ?? "") ?? .cadencePyramids
                let template = DrillTemplate.template(for: resolved)
                let baseCadence = Int(self.runRecord.workingAvgCadence) > 0 ? Int(self.runRecord.workingAvgCadence) : 155
                let target = template.calculateTargetCadence(baseCadence)
                let dto = DrillPrescriptionDTO(
                    title: template.title,
                    preRunDrillId: resolved.rawValue,
                    purpose: template.defaultPurpose,
                    targetCadence: target,
                    previousCadence: baseCadence
                )
                Task {
                    let bridge = WorkoutBridge()
                    try? await bridge.scheduleDrill(dto: dto)
                }
                return "{\"drill_name\":\"\(resolved.title)\",\"message\":\"Scheduled \(resolved.title) to Apple Watch.\",\"status\":\"exported_to_watch\"}"

            case .updateGoal:
                var newGoal = query.payload?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Base Building"
                let lower = newGoal.lowercased()
                if lower.contains("marathon") && !lower.contains("half") {
                    newGoal = "Marathon"
                } else if lower.contains("half") {
                    newGoal = "Half Marathon"
                } else if lower.contains("10k") {
                    newGoal = "10K Race"
                } else if lower.contains("5k") {
                    newGoal = "5K Race"
                } else if lower.contains("base") {
                    newGoal = "Base Building"
                } else if lower.contains("fun") {
                    newGoal = "Just for Fun"
                }
                UserDefaults.standard.set(newGoal, forKey: "trainingGoal")
                return "{\"status\":\"training_goal_updated\",\"goal\":\"\(newGoal)\",\"message\":\"Training goal updated to \(newGoal).\"}"

            case .displayExplainer:
                let rawKey = query.payload?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let asset = CoachingAssetLibrary.resolve(key: rawKey) ?? CoachingAssetLibrary.defaultAsset(for: rawKey)
                self.explainerRecommendedThisTurn = asset.key

                let dto: [String: String] = [
                    "status": "interactive_explainer_card_displayed",
                    "explainer_key": asset.key,
                    "title": asset.title,
                    "domain": asset.domain.rawValue,
                    "compact_definition": asset.compactSummary
                ]
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
                if let data = try? encoder.encode(dto), let str = String(data: data, encoding: .utf8) {
                    return str
                }
                return "{\"explainer_key\":\"\(asset.key)\",\"status\":\"interactive_explainer_card_displayed\",\"title\":\"\(asset.title)\"}"

            case .recordFeedback:
                let feedback = query.payload ?? ""
                if !feedback.isEmpty {
                    self.runRecord.framboiseTags.append("feedback:\(feedback.prefix(40))")
                    try? self.runRecord.modelContext?.save()
                }
                return "{\"status\":\"feedback_recorded\",\"feedback\":\"\(feedback)\",\"message\":\"Subjective feedback recorded successfully.\"}"
            }
        }

        let tools: [any Tool] = [inspectWorkoutTool, manageTrainingTool, coachActionTool]
        let instructions = buildLeanSystemInstructions()
        let session = LanguageModelSession(
            model: SystemLanguageModel.default,
            tools: tools,
            instructions: instructions
        )
        self.modelSession = session
        return session
    }

    @available(iOS 26.0, *)
    private func generateFoundationModelResponse(for userQuestion: String) async throws -> String {
        // One session per chat so the model remembers what it already said.
        // Only start fresh when the transcript genuinely overflows the context window.
        do {
            let response = try await getOrCreateSession().respond(to: userQuestion)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            self.modelSession = nil
            let retry = try await getOrCreateSession().respond(to: userQuestion)
            return retry.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    #endif

    /// Synthesizes 1,000-meter splits from phase segments if physical splits were not persisted.
    nonisolated static func synthesizeSplitsFromSegments(_ segments: [PhaseSegment], splitDistanceMeters: Double = 1000.0) -> [RunSplit] {
        RunSplit.synthesize(from: segments, splitDistanceMeters: splitDistanceMeters)
    }

    // MARK: - Honest System Status (No Fake Canned Responses)

    private func systemUnavailableMessage() -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if !SystemLanguageModel.default.isAvailable {
                return "AI Coach interactive conversation requires Apple Intelligence on iOS 26 or later. Please ensure Apple Intelligence is enabled in Settings."
            }
        }
        #endif
        return "I'm having trouble analyzing this run right now. Please try asking again in a moment."
    }

    // MARK: - Readiness & Recovery Timeline

    var readinessAssessment: ReadinessAssessment {
        assessReadiness(asOf: runRecord.date)
    }

    var currentReadiness: ReadinessAssessment {
        assessReadiness(asOf: Date())
    }

    private func assessReadiness(asOf date: Date) -> ReadinessAssessment {
        if let context = runRecord.modelContext {
            return ReadinessEvaluator.assess(context: context, now: date)
        }
        if let profile = macroProfile {
            let state: ReadinessState = (profile.acwr ?? 1.0) > 1.4 ? .acuteFatigue : .productive
            return ReadinessAssessment(
                state: state,
                triggers: [],
                acuteLoad: profile.acuteLoad,
                chronicWeeklyLoad: profile.chronicWeeklyLoad,
                acwr: profile.acwr,
                mileageDropFraction: nil
            )
        }
        return ReadinessAssessment.productive
    }

    var isHeavySession: Bool {
        ReadinessRunSnapshot(run: runRecord).isHardSession
    }

    private var recentSnapshots: [ReadinessRunSnapshot] {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        var snapshots: [ReadinessRunSnapshot] = []
        if let context = runRecord.modelContext {
            let descriptor = FetchDescriptor<RunRecord>(
                predicate: #Predicate<RunRecord> { $0.date >= cutoff },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            snapshots = (try? context.fetch(descriptor))?.map(ReadinessRunSnapshot.init(run:)) ?? []
        }
        if !snapshots.contains(where: { $0.date == runRecord.date }) {
            snapshots.append(ReadinessRunSnapshot(run: runRecord))
        }
        return snapshots
    }

    var recoveryTimeline: RecoveryTimeline {
        RecoveryTimeline.build(runs: recentSnapshots, readiness: currentReadiness, now: Date())
    }

    var runnerProfile: RunnerProfile {
        var historicalRuns: [RunRecord] = []
        if let context = runRecord.modelContext {
            let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
            let desc = FetchDescriptor<RunRecord>(predicate: #Predicate<RunRecord> { $0.date >= cutoff })
            historicalRuns = (try? context.fetch(desc)) ?? []
        }
        if !historicalRuns.contains(where: { $0.date == runRecord.date }) {
            historicalRuns.append(runRecord)
        }
        return RunnerProfile.compute(from: historicalRuns, now: Date())
    }

    private func buildUpcomingWeeklySchedule(
        dailyState: DailyTrainingState,
        contextDate: Date
    ) -> [ScheduledDaySummary] {
        var days: [ScheduledDaySummary] = []
        let cal = Calendar.current
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "EEEE"

        switch dailyState {
        case .preRun(let session):
            days.append(ScheduledDaySummary(
                day_name: "Today",
                session_title: session.sessionTitle,
                duration_band: session.durationBand,
                target_pace_or_effort: session.paceBand,
                is_rest_day: session.isRestDay,
                rationale: session.groundedRationale
            ))
            for day in session.microcycle {
                let parsed = parseScheduleTitle(day.sessionTitle)
                days.append(ScheduledDaySummary(
                    day_name: day.dayLabel,
                    session_title: parsed.name,
                    duration_band: parsed.detail ?? (day.isRestDay ? "0 Min" : "30–45 Min"),
                    target_pace_or_effort: day.isRestDay ? "Rest" : "Zone 2 Base",
                    is_rest_day: day.isRestDay,
                    rationale: day.isRestDay ? "Consolidate adaptations" : "Aerobic progression"
                ))
            }
        case .completedToday(_, let tomorrowSession):
            let tomorrow = cal.date(byAdding: .day, value: 1, to: contextDate) ?? contextDate
            let tomorrowDayName = df.string(from: tomorrow)
            days.append(ScheduledDaySummary(
                day_name: tomorrowDayName,
                session_title: tomorrowSession.sessionTitle,
                duration_band: tomorrowSession.durationBand,
                target_pace_or_effort: tomorrowSession.paceBand,
                is_rest_day: tomorrowSession.isRestDay,
                rationale: tomorrowSession.groundedRationale
            ))
            for day in tomorrowSession.microcycle {
                let parsed = parseScheduleTitle(day.sessionTitle)
                days.append(ScheduledDaySummary(
                    day_name: day.dayLabel,
                    session_title: parsed.name,
                    duration_band: parsed.detail ?? (day.isRestDay ? "0 Min" : "30–45 Min"),
                    target_pace_or_effort: day.isRestDay ? "Rest" : "Zone 2 Base",
                    is_rest_day: day.isRestDay,
                    rationale: day.isRestDay ? "Consolidate adaptations" : "Aerobic progression"
                ))
            }
        }
        return days
    }

    private func buildMicrocycleForChat(
        dailyState: DailyTrainingState,
        contextDate: Date
    ) -> [MicrocycleDay] {
        var result: [MicrocycleDay] = []
        let cal = Calendar.current
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "EEE"

        switch dailyState {
        case .preRun(let session):
            result.append(MicrocycleDay(
                id: "today-\(session.sessionTitle)",
                dayLabel: "Today",
                sessionTitle: "\(session.sessionTitle) • \(session.durationBand)",
                iconName: session.isRestDay ? "bed.double.fill" : "figure.run",
                isRestDay: session.isRestDay
            ))
            result.append(contentsOf: session.microcycle)
        case .completedToday(_, let tomorrowSession):
            let tomorrow = cal.date(byAdding: .day, value: 1, to: contextDate) ?? contextDate
            let tomorrowDayStr = df.string(from: tomorrow)
            result.append(MicrocycleDay(
                id: "tomorrow-\(tomorrowSession.sessionTitle)",
                dayLabel: tomorrowDayStr,
                sessionTitle: "\(tomorrowSession.sessionTitle) • \(tomorrowSession.durationBand)",
                iconName: tomorrowSession.isRestDay ? "bed.double.fill" : "figure.run",
                isRestDay: tomorrowSession.isRestDay
            ))
            result.append(contentsOf: tomorrowSession.microcycle)
        }
        return result
    }

    private func parseScheduleTitle(_ title: String) -> (name: String, detail: String?) {
        if title.contains(" • ") {
            let parts = title.components(separatedBy: " • ")
            return (parts[0], parts.count > 1 ? parts[1] : nil)
        }
        return (title, nil)
    }

    private func buildTodayWorkloadEvaluation(
        allRuns: [RunRecord],
        profile: RunnerProfile,
        activeGoal: String,
        useMetric: Bool
    ) -> TodayWorkloadEvaluation {
        let cal = Calendar.current
        let todayRuns = allRuns.filter { cal.isDateInToday($0.date) && !$0.isDeleted }
            .sorted(by: { $0.date < $1.date })

        let totalDurationSec = todayRuns.reduce(0.0) { $0 + $1.duration }
        let totalDistanceMeters = todayRuns.reduce(0.0) {
            $0 + ($1.totalDistanceMeters > 0 ? $1.totalDistanceMeters : $1.effectiveWorkingDistanceMeters)
        }

        let durMin = Int(totalDurationSec) / 60
        let durSec = Int(totalDurationSec) % 60
        let totalDurStr = String(format: "%d:%02d", durMin, durSec)

        let totalDistStr = useMetric
            ? String(format: "%.2f km", totalDistanceMeters / 1000.0)
            : String(format: "%.2f mi", totalDistanceMeters / 1609.344)

        let (dailyBand, targetMinutes) = SessionSynthesisEngine.aerobicDurationForExperience(profile.experienceLevel)
        let completedMinutes = Int(round(totalDurationSec / 60.0))
        let completionPercent = targetMinutes > 0 ? Int(round(Double(completedMinutes) / Double(targetMinutes) * 100.0)) : 100

        let streakSummary = StreakAndVolumeSummary.evaluate(
            runs: allRuns,
            experienceLevel: profile.experienceLevel,
            trainingGoal: activeGoal,
            now: Date()
        )

        let workingHRs = todayRuns.map(\.workingAvgHeartRate).filter { $0 > 0 }
        let avgHR = workingHRs.isEmpty ? 0 : Int(round(workingHRs.reduce(0, +) / Double(workingHRs.count)))

        let breakdown: [String] = todayRuns.map { run in
            let rDurMin = Int(run.duration) / 60
            let rDurSec = Int(run.duration) % 60
            let rDurStr = String(format: "%d:%02d", rDurMin, rDurSec)
            let distVal = run.totalDistanceMeters > 0 ? run.totalDistanceMeters : run.effectiveWorkingDistanceMeters
            let rDistStr = useMetric
                ? String(format: "%.2f km", distVal / 1000.0)
                : String(format: "%.2f mi", distVal / 1609.344)
            let hrNote = run.workingAvgHeartRate > 0 ? ", \(Int(round(run.workingAvgHeartRate))) BPM HR" : ""
            let cadNote = run.workingAvgCadence > 0 ? ", \(Int(round(run.workingAvgCadence))) SPM" : ""
            let prefix = run.isIndoor == true ? "Indoor " : ""
            return "\(rDurStr) (\(rDistStr)) \(prefix)\(run.normalizedClassification)\(hrNote)\(cadNote)"
        }

        let ratioPct = Int(round(streakSummary.volumeRatio48h * 100.0))
        let strainSummary = "48h volume: \(Int(round(streakSummary.last48hDurationMinutes))) min (\(ratioPct)% of 4-week baseline) across \(streakSummary.consecutiveRunDays) consecutive days; working HR: \(avgHR > 0 ? "\(avgHR) BPM" : "Nominal")"

        let hasDoneSufficient: Bool
        let shouldRunAgain: Bool
        let verdict: String
        let prescription: String

        if todayRuns.isEmpty {
            hasDoneSufficient = false
            shouldRunAgain = true
            verdict = "NO_WORK_BANKED_TODAY"
            prescription = "No sessions logged yet today. Today's primary workout is ready to start."
        } else if todayRuns.count == 1 && (todayRuns[0].duration <= 1320 && (todayRuns[0].prescribedDrillName != nil || todayRuns[0].totalDistanceMeters <= 2000)) {
            hasDoneSufficient = false
            shouldRunAgain = true
            verdict = "PRIMER_COMPLETE_READY_FOR_MAIN_RUN"
            prescription = "Primer complete (\(breakdown[0])). Ready for Today's Main Run."
        } else if completionPercent >= 80 || streakSummary.shouldRecommendRestDay || streakSummary.volumeRatio48h >= 0.50 {
            hasDoneSufficient = true
            shouldRunAgain = false
            verdict = "DAILY_WORKLOAD_SUFFICIENT_REST_RECOMMENDED"
            prescription = "Sufficient work completed today (\(totalDurStr) / \(totalDistStr) across \(todayRuns.count) session\(todayRuns.count > 1 ? "s" : "") = \(completionPercent)% of your \(dailyBand) daily target). A second run today is counterproductive and increases injury risk. If you want additional movement, limit it to 15–20 min of non-impact walking or mobility."
        } else {
            hasDoneSufficient = false
            shouldRunAgain = true
            verdict = "PARTIAL_VOLUME_SUPPLEMENTAL_ALLOWED"
            let remainingMin = max(15, targetMinutes - completedMinutes)
            prescription = "Partial volume logged today (\(totalDurStr) / \(completionPercent)% of daily target). An optional \(remainingMin)-min easy Zone 1–2 flush jog is permitted if feeling fresh."
        }

        return TodayWorkloadEvaluation(
            sessions_completed_today_count: todayRuns.count,
            completed_sessions_summary: breakdown,
            total_duration_today: totalDurStr,
            total_distance_today: totalDistStr,
            daily_target_duration_band: dailyBand,
            daily_target_completion_percent: completionPercent,
            acute_load_and_strain_factors: strainSummary,
            has_done_sufficient_work_today: hasDoneSufficient,
            should_run_again_today: shouldRunAgain,
            sufficiency_verdict: verdict,
            second_run_or_supplemental_prescription: prescription
        )
    }
}
