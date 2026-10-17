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
    let attachedExplainerKey: String?

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
        attachedExplainerKey: String? = nil
    ) {
        self.id = id
        self.sender = sender
        self.text = text
        self.timestamp = timestamp
        self.attachedDrillId = attachedDrillId
        self.attachedExplainerKey = attachedExplainerKey
    }
}

typealias AnalystChatSender = AnalystChatMessage.MessageSender

/// Actor managing the interactive RAG Analyst Chat session with FoundationModels and strict operational guardrails.
@MainActor
class AnalystChatEngine: ObservableObject {
    @Published var messages: [AnalystChatMessage] = []
    @Published var isResponding: Bool = false

    private let runSignature: RunSignature?
    private let macroProfile: MacroProfile?
    private let runRecord: RunRecord

    #if canImport(FoundationModels)
    private var modelSession: Any? // LanguageModelSession on iOS 26+
    /// Tracks a drill or session card recommended during the active conversation turn.
    var drillRecommendedThisTurn: PreRunDrillId?
    /// Tracks an interactive explainer card recommended during the active conversation turn.
    var explainerRecommendedThisTurn: String?
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

    init(runRecord: RunRecord, runSignature: RunSignature? = nil, macroProfile: MacroProfile? = nil) {
        self.runRecord = runRecord
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
            self.explainerRecommendedThisTurn = nil
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
                    messages.append(AnalystChatMessage(sender: .analyst, text: responseText, attachedDrillId: drillRecommendedThisTurn, attachedExplainerKey: explainerRecommendedThisTurn))
                    return
                } catch {
                    print("Model responder error: \(error)")
                }
            }
            #endif
            if SystemLanguageModel.default.isAvailable {
                do {
                    let responseText = try await generateFoundationModelResponse(for: trimmed)
                    messages.append(AnalystChatMessage(sender: .analyst, text: responseText, attachedDrillId: drillRecommendedThisTurn, attachedExplainerKey: explainerRecommendedThisTurn))
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
        let temporalGrounding = daysDiff == 0
            ? "Workout took place today."
            : "Workout took place on \(dateStr) (\(daysDiff)d ago)."

        let useMetric = (UserDefaults.standard.object(forKey: "useMetricSystem") as? Bool) ?? true
        let unitSystem = useMetric ? "Metric (min/km, km)" : "Imperial (min/mi, mi)"

        return """
        You are Runalyst—an intelligent, conversational running coach. Speak directly to the runner with warmth and encouragement.

        CONTEXT:
        Reviewing: \(runType) (\(envNote)). \(temporalGrounding)
        Units: \(unitSystem).

        RULES:
        • Call tools only when relevant. Max 1 card per turn. Never call `executeCoachAction` for off-topic queries.
        • `inspectWorkout`: moving vs gross stats, splits, intervals, reps, physics, metric definitions.
        • `manageTrainingState`: 'readiness' (set `userReportedDistress: true` if ill/injured), 'history', or 'athlete_profile'.
        • `executeCoachAction`: 'update_goal' for race plans (outline Base, Build, Peak, Taper; explain daily readiness; no drill cards); 'display_drill' for workouts to do now; 'display_explainer' to show a metric card; 'export_to_watch'; 'record_feedback'.
        • Formatting: Rich text. Use standard units (SPM, min/km, min/mi). Never use Markdown or LaTeX.
        • Medical Safety: Prioritize rest on pain/illness, state AI disclaimer, urge medical care.
        • Outside Running: For off-topic chat, warmly refocus on training. Never force drills.
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

                if verdict != "MANDATORY_REST_HEALTH_OVERRIDE",
                   let resolvedSession = PreRunDrillId.resolve(from: rx.nextSessionName) {
                    self.drillRecommendedThisTurn = resolvedSession
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

                let response = ReadinessToolResponse(
                    schema_name: "READINESS_AND_PRESCRIPTION_RESPONSE",
                    readiness_verdict: verdict,
                    recovery_status: recoveryStatus,
                    prescribed_session_name: rx.nextSessionName,
                    intensity_category: humanIntensity,
                    prescribed_pace_band: rx.prescribedPaceBand,
                    prescribed_duration_band: rx.prescribedDurationBand,
                    prescribed_cadence_band: rx.prescribedCadenceBand,
                    session_rationale: rx.sessionRationale,
                    guidance_notes: guidance
                )

                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
                if let data = try? encoder.encode(response),
                   let json = String(data: data, encoding: .utf8) {
                    return json
                }
                return "{\"intensity_category\":\"\(humanIntensity)\",\"prescribed_pace_band\":\"\(rx.prescribedPaceBand)\",\"prescribed_session_name\":\"\(rx.nextSessionName)\",\"readiness_verdict\":\"\(verdict)\"}"

            case .history:
                let context = self.runRecord.modelContext
                switch query.historyScope ?? .compare {
                case .performanceArc:
                    return HistoricalRunMatcher.analyzePerformanceArc(relativeTo: self.runRecord, in: context).structuredTelemetryFacts
                case .recentRuns:
                    return HistoricalRunMatcher.listRecentRuns(relativeTo: self.runRecord, in: context)
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
}
