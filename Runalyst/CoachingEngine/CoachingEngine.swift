import Foundation
import SwiftData
import OSLog
#if canImport(FoundationModels)
import FoundationModels
#endif

private let logger = Logger(subsystem: "com.runalyzer.Runalyzer", category: "CoachingEngine")

struct BaselineStats: Sendable {
    let avgPace: Double
    let avgCadence: Double
    let avgHR: Double
    let avgOscillation: Double
    let avgStrideLength: Double?

    init(
        avgPace: Double,
        avgCadence: Double,
        avgHR: Double,
        avgOscillation: Double,
        avgStrideLength: Double? = nil
    ) {
        self.avgPace = avgPace
        self.avgCadence = avgCadence
        self.avgHR = avgHR
        self.avgOscillation = avgOscillation
        self.avgStrideLength = avgStrideLength
    }
}

struct RunDataForAI: Sendable {
    let workoutType: String
    let runnerGoal: String
    let directiveContext: String
    let paceContext: String
    let hrContext: String
    let cadenceContext: String
    let zone4Context: String
    let cvContext: String
    let slopeContext: String
    let intervalCadence: String
    let recoveryCadence: String
    let isIndoor: Bool

    init(
        workoutType: String = "Steady Effort",
        runnerGoal: String = "Base Building",
        directiveContext: String,
        paceContext: String,
        hrContext: String,
        cadenceContext: String,
        zone4Context: String,
        cvContext: String,
        slopeContext: String,
        intervalCadence: String,
        recoveryCadence: String,
        isIndoor: Bool = false
    ) {
        self.workoutType = workoutType
        self.runnerGoal = runnerGoal
        self.directiveContext = directiveContext
        self.paceContext = paceContext
        self.hrContext = hrContext
        self.cadenceContext = cadenceContext
        self.zone4Context = zone4Context
        self.cvContext = cvContext
        self.slopeContext = slopeContext
        self.intervalCadence = intervalCadence
        self.recoveryCadence = recoveryCadence
        self.isIndoor = isIndoor
    }
}

struct AggregateRunDataForAI: Sendable {
    let paceContext: String
    let hrContext: String
    let cadenceContext: String
    let zone4Context: String
    let cvContext: String
    let slopeContext: String
    let stageContext: String
    let directiveContext: String
    let efficiencyContext: String
    let fatigueContext: String
    let verticalOscillationContext: String

    init(
        paceContext: String,
        hrContext: String,
        cadenceContext: String,
        zone4Context: String,
        cvContext: String,
        slopeContext: String,
        stageContext: String,
        directiveContext: String = "",
        efficiencyContext: String = "",
        fatigueContext: String = "",
        verticalOscillationContext: String = ""
    ) {
        self.paceContext = paceContext
        self.hrContext = hrContext
        self.cadenceContext = cadenceContext
        self.zone4Context = zone4Context
        self.cvContext = cvContext
        self.slopeContext = slopeContext
        self.stageContext = stageContext
        self.directiveContext = directiveContext
        self.efficiencyContext = efficiencyContext
        self.fatigueContext = fatigueContext
        self.verticalOscillationContext = verticalOscillationContext
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct DashboardFatigueInsight {
    @Guide(description: "Constrain strictly to a 2–4 word title capturing the primary coaching takeaway (e.g. 'Ready For Speed', 'Active Recovery Needed', 'On Track For Goal', 'Time To Step Up').")
    var headline: String

    @Guide(description: "Write 1 to 4 flowing, natural sentences in plain English like an experienced personal running coach speaking directly to the runner. Follow the directive and connect to their stated goal. Zero numbers.")
    var body: String
}

@available(iOS 26.0, *)
@Generable
struct SuggestedDrill {
    @Guide(description: "A clear, human-friendly drill name without underscores (e.g. 'Rhythm Intervals', 'Cadence Pyramids', 'Strides').")
    var drillTitle: String

    @Guide(description: "Must be exactly one of: cadence_pyramids, rhythm_intervals, tempo_surges, strides, neuromuscular_primer, aerobic_flush, fartlek_primer, hill_bounds, recovery_jog")
    var preRunDrillId: String

    @Guide(description: "1 concise sentence explaining why this drill addresses the runner's specific focus area based on the coaching directive.")
    var drillPurpose: String

    @Guide(description: "A single somatic form or breathing cue to focus on during the drill (e.g. 'Arms at 90 degrees, gentle grip, drop your shoulders and let your arms propel you', 'Quick, light foot turnover underneath your hips'). Never include SPM numbers, reps, or workout intervals.")
    var drillCues: String
}

@available(iOS 26.0, *)
@Generable
struct RunInsight {
    @Guide(description: "A concise 2–4 word title capturing the run's theme (e.g. 'Strong Cadence Rhythm', 'Aerobic Efficiency Win'). Forbid full sentences, punctuation-heavy titles, numbers, and digits.")
    var headline: String

    @Guide(description: "A warm, cohesive 2–3 sentence coaching analysis. Commend improvements or consistency, highlight where form or efficiency has room to grow, and introduce the drill. Do not recite numbers, digits, or somatic drill cues.")
    var observation: String

    @Guide(description: "One targeted short pre-run technique drill by default, with an optional second drill only when it directly reinforces the primary Swift directive. The drills together must take about 5 to 10 minutes. Do not prescribe stretches, warm-ups, cooldowns, or a full running workout. MAX 2 DRILLS.")
    var drills: [SuggestedDrill]
}

@available(iOS 26.0, *)
@MainActor
class CoachingEngine {
    static let shared = CoachingEngine()

    var inFlightTasks: [PersistentIdentifier: Task<Void, Never>] = [:]

    private init() {}

    func requestAnalysis(for runRecord: RunRecord, force: Bool = false) async {
        let runId = runRecord.persistentModelID
        guard let container = runRecord.modelContext?.container else { return }

        if let existingTask = inFlightTasks[runId] {
            _ = await existingTask.value
            return
        }

        if force, let oldInsight = runRecord.insight {
            runRecord.modelContext?.delete(oldInsight)
            runRecord.insight = nil
            try? runRecord.modelContext?.save()
        }

        let task = Task.detached {
            let analyzer = RunAnalyzerActor(modelContainer: container)
            await analyzer.generateAnalysis(for: runId, force: force)
        }

        inFlightTasks[runId] = task
        _ = await task.value
        inFlightTasks[runId] = nil
    }

    func generateInsight(for runData: RunDataForAI) async throws -> RunInsight {
        guard SystemLanguageModel.default.isAvailable else {
            throw NSError(domain: "CoachingEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Foundation Models are not available on this device."])
        }

        let language = Locale.current.language.languageCode?.identifier ?? "en"

        let instructions = """
        You possess the Mind of an Analyst and the Voice of a Coach.
        Objectively analyze telemetry to assess mechanical efficiency and biological cost (The Mind),
        and translate those findings into conversational, empathetic biomechanical cues speaking directly to the athlete using "you" and "your" (The Voice).

        Strict coaching rules:
        1. Commend genuine aerobic or mechanical improvements. Follow the DIRECTIVE for cadence: if marked BELOW the 150 SPM floor, NEVER praise turnover or form precision; instead, critique the slow turnover and instruct the runner to lighten their foot strike. If marked above floor, never claim it is below floor.
        2. Highlight where form or efficiency has room to grow according to the directive and telemetry (e.g. overstriding, high vertical bounce, cardiac drift, or stride collapse).
        3. Never praise treadmill runners for "perfect pacing consistency" (the belt enforced it); evaluate biological cost and turnover stability instead.
        4. Recommend a targeted pre-run drill following the directive.
        5. Speak warmly and naturally like an experienced personal running coach (in the encouraging style of Apple Fitness+) in 2–3 cohesive sentences. Zero numbers or digits in the observation.
        6. Human Coaching Voice: Strictly avoid dense academic, clinical kinesiology, or laboratory jargon (never use "neuromuscular", "fast-twitch motor units", "effort calibration", "cardiovascular decoupling", or "metabolic demands"). Use natural, visceral runner language: "leg turnover", "rhythm", "spring in your step", "holding your pace", "quick, light feet".
        Respond entirely in \(language).
        """

        let session = LanguageModelSession(
            model: SystemLanguageModel.default,
            instructions: instructions
        )

        let useMetric = UserDefaults.standard.bool(forKey: "useMetricSystem")
        let unitContext = useMetric ? "Pace is in min/km." : "Pace is in min/mi."

        var promptTemplate = """
        How was my run coach?
        Speak directly using "you" and "your"
        [RUN_DATA_START]
        WORKOUT_TYPE: {{WORKOUT_TYPE}}
        ENVIRONMENT: {{ENVIRONMENT}}
        RUNNER_GOAL: {{RUNNER_GOAL}}
        DIRECTIVE: {{DIRECTIVE_CONTEXT}}
        TARGET_DRILL_CADENCES:
        - INTERVAL_CADENCE: {{INTERVAL_CADENCE}}
        - RECOVERY_CADENCE: {{RECOVERY_CADENCE}}

        --- CARDIOVASCULAR EFFICIENCY ---
        HEART_RATE_BPM: {{HR_CONTEXT}}
        ZONE4_PERCENT: {{ZONE4_CONTEXT}}

        --- RUNNING ECONOMY & FORM ---
        CADENCE_SPM: {{CADENCE_CONTEXT}}
        PACE: {{PACE_CONTEXT}}
        \(unitContext)

        --- PACING DYNAMICS ---
        PACE_VARIABILITY: {{CV_CONTEXT}}
        PACE_SLOPE: {{SLOPE_CONTEXT}}
        \(unitContext)

        [RUN_DATA_END]
        """

        promptTemplate = promptTemplate.replacingOccurrences(of: "{{WORKOUT_TYPE}}", with: runData.workoutType)
        promptTemplate = promptTemplate.replacingOccurrences(of: "{{ENVIRONMENT}}", with: runData.isIndoor ? "Indoor Treadmill" : "Outdoor")
        promptTemplate = promptTemplate.replacingOccurrences(of: "{{RUNNER_GOAL}}", with: runData.runnerGoal)
        promptTemplate = promptTemplate.replacingOccurrences(of: "{{INTERVAL_CADENCE}}", with: runData.intervalCadence)
        promptTemplate = promptTemplate.replacingOccurrences(of: "{{RECOVERY_CADENCE}}", with: runData.recoveryCadence)
        promptTemplate = promptTemplate.replacingOccurrences(of: "{{DIRECTIVE_CONTEXT}}", with: runData.directiveContext)
        promptTemplate = promptTemplate.replacingOccurrences(of: "{{PACE_CONTEXT}}", with: runData.paceContext)
        promptTemplate = promptTemplate.replacingOccurrences(of: "{{HR_CONTEXT}}", with: runData.hrContext)
        promptTemplate = promptTemplate.replacingOccurrences(of: "{{CADENCE_CONTEXT}}", with: runData.cadenceContext)
        promptTemplate = promptTemplate.replacingOccurrences(of: "{{ZONE4_CONTEXT}}", with: runData.zone4Context)
        promptTemplate = promptTemplate.replacingOccurrences(of: "{{CV_CONTEXT}}", with: runData.cvContext)
        promptTemplate = promptTemplate.replacingOccurrences(of: "{{SLOPE_CONTEXT}}", with: runData.slopeContext)

        let prompt = promptTemplate

        do {
            let insightContent = try await ModelInferenceSerializer.shared.run {
                let response = try await session.respond(to: prompt, generating: RunInsight.self)
                return response.content
            }
            return insightContent
        } catch {
            logger.error("FoundationModels Generation Error: \(error.localizedDescription)")
            return RunInsight(
                headline: String(localized: "Run Analyzed Successfully"),
                observation: String(localized: "Your run data has been processed. Stay consistent to build a stronger baseline over the next 30 days."),
                drills: [SuggestedDrill(
                    drillTitle: String(localized: "Strides"),
                    preRunDrillId: "strides",
                    drillPurpose: String(localized: "Builds turnover and neural recruitment."),
                    drillCues: String(localized: "Arms at 90 degrees, gentle grip, drop your shoulders and let your arms propel you.")
                )]
            )
        }
    }
    func generateDashboardInsight(for timeFrame: String, runData: AggregateRunDataForAI) async throws -> DashboardFatigueInsight {
        // All-Time view disables LLM inference entirely; relies on native Apple Charts and volume milestone badges.
        if timeFrame == "All Time" {
            return DashboardFatigueInsight(
                headline: String(localized: "Lifetime Milestones"),
                body: String(localized: "Review your lifetime volume, personal records, and progression trends below.")
            )
        }

        guard SystemLanguageModel.default.isAvailable else {
            throw NSError(domain: "CoachingEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Foundation Models are not available on this device."])
        }

        let language = Locale.current.language.languageCode?.identifier ?? "en"
        let trainingGoal = UserDefaults.standard.string(forKey: "trainingGoal") ?? "Base Building"

        let instructions: String
        let promptTemplate: String

        if timeFrame == "7 Days" {
            instructions = """
            persona: personal_running_coach
            rules:
            - You are an experienced, trusted personal running coach speaking directly to the runner ("you").
            - Write in natural, concise, plain English. Avoid robotic phrasing, dramatic metaphors, or philosophical lecturing.
            - Purpose: Deliver an immediate coaching verdict and clear action for what to do next.
            - Direct Verdict & Action: Lead immediately with the core directive in the very first sentence (e.g. advise full rest, easy recovery jog, or specific session).
            - Follow with exactly one brief physiological reason or tactical focus cue in the second sentence.
            - strictly_follow_the_DIRECTIVE_for_tone_and_drill_selection.
            - Strict Length: exactly 2 concise, impactful sentences (maximum 40 words total).
            - Zero Numbers: no specific metrics, target paces, BPM numbers, or times.
            - Respond entirely in \(language).
            """

            promptTemplate = """
            Coach this runner on what session to do next and what to focus on improving, based on their recent 7-day training and stated goal.
            [AGGREGATE_DATA_START]
            GOAL: \(trainingGoal)
            TIMEFRAME: 7 Days (Immediate Next Run & Focus)
            DIRECTIVE: {{DIRECTIVE_CONTEXT}}
            CADENCE_TURNOVER: {{CADENCE_CONTEXT}}
            CARDIAC_LOAD: {{HR_CONTEXT}}, {{ZONE4_CONTEXT}}
            [AGGREGATE_DATA_END]
            """
        } else {
            // 30 Days: Goal Readiness & Trajectory
            instructions = """
            persona: personal_running_coach
            rules:
            - You are an experienced, trusted personal running coach speaking directly to the runner ("you").
            - Write in natural, flowing, plain English. Avoid robotic phrasing, dramatic metaphors, or philosophical lecturing.
            - Purpose: Gauge how close the runner is to their stated goal or how ready they are to chase it based on 30-day performance.
            - Clearly tell the runner whether they are on track for their goal, need to step it up because they have more to give, or need to ease up because they are overworking and declining.
            - Connect their 30-day consistency and efficiency directly to their stated goal.
            - strictly_follow_the_DIRECTIVE_for_tone_and_drill_selection.
            - Strict Length: exactly 1 to 4 flowing sentences.
            - Zero Numbers: no specific metrics, target paces, BPM numbers, or times.
            - Respond entirely in \(language).
            """

            promptTemplate = """
            Evaluate 30-day goal readiness and trajectory for this runner toward their stated goal.
            [AGGREGATE_DATA_START]
            GOAL: \(trainingGoal)
            TIMEFRAME: 30 Days (Goal Readiness & Trajectory)
            DIRECTIVE: {{DIRECTIVE_CONTEXT}}
            EFFICIENCY_FACTOR: {{EFFICIENCY_CONTEXT}}
            BIOMECHANICS: {{OSCILLATION_CONTEXT}}, {{CADENCE_CONTEXT}}
            CARDIAC_COST: {{HR_CONTEXT}}, {{PACE_CONTEXT}}
            PACING_TRENDS: {{SLOPE_CONTEXT}}
            [AGGREGATE_DATA_END]
            """
        }

        let session = LanguageModelSession(
            model: SystemLanguageModel.default,
            instructions: instructions
        )

        var filledPrompt = promptTemplate
        filledPrompt = filledPrompt.replacingOccurrences(of: "{{DIRECTIVE_CONTEXT}}", with: runData.directiveContext)
        filledPrompt = filledPrompt.replacingOccurrences(of: "{{FATIGUE_CONTEXT}}", with: runData.fatigueContext)
        filledPrompt = filledPrompt.replacingOccurrences(of: "{{EFFICIENCY_CONTEXT}}", with: runData.efficiencyContext)
        filledPrompt = filledPrompt.replacingOccurrences(of: "{{OSCILLATION_CONTEXT}}", with: runData.verticalOscillationContext)
        filledPrompt = filledPrompt.replacingOccurrences(of: "{{STAGE_CONTEXT}}", with: runData.stageContext)
        filledPrompt = filledPrompt.replacingOccurrences(of: "{{PACE_CONTEXT}}", with: runData.paceContext)
        filledPrompt = filledPrompt.replacingOccurrences(of: "{{HR_CONTEXT}}", with: runData.hrContext)
        filledPrompt = filledPrompt.replacingOccurrences(of: "{{CADENCE_CONTEXT}}", with: runData.cadenceContext)
        filledPrompt = filledPrompt.replacingOccurrences(of: "{{ZONE4_CONTEXT}}", with: runData.zone4Context)
        filledPrompt = filledPrompt.replacingOccurrences(of: "{{CV_CONTEXT}}", with: runData.cvContext)
        filledPrompt = filledPrompt.replacingOccurrences(of: "{{SLOPE_CONTEXT}}", with: runData.slopeContext)

        let dashboardPrompt = filledPrompt

        do {
            let insightContent = try await ModelInferenceSerializer.shared.run {
                let response = try await session.respond(to: dashboardPrompt, generating: DashboardFatigueInsight.self)
                return response.content
            }
            return insightContent
        } catch {
            logger.error("FoundationModels Generation Error: \(error.localizedDescription)")
            let fallbackHeadline = (timeFrame == "7 Days") ? String(localized: "Ready for Next Run") : String(localized: "On Track for Goal")
            let fallbackBody = (timeFrame == "7 Days")
                ? String(localized: "Your recent runs show solid consistency. For your next run, focus on keeping your effort controlled and your turnover light.")
                : String(localized: "Your 30-day training shows steady progression toward your goal. Keep building on this foundation with consistent weekly volume.")
            return DashboardFatigueInsight(
                headline: fallbackHeadline,
                body: fallbackBody
            )
        }
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
private actor ModelInferenceSerializer {
    static let shared = ModelInferenceSerializer()
    private var queue: [(CheckedContinuation<Void, Never>)] = []
    private var isExecuting = false

    func run<T: Sendable>(_ work: @Sendable () async throws -> T) async throws -> T {
        if isExecuting {
            await withCheckedContinuation { continuation in
                queue.append(continuation)
            }
        }
        isExecuting = true
        defer {
            isExecuting = false
            if !queue.isEmpty {
                let next = queue.removeFirst()
                next.resume()
            }
        }
        return try await work()
    }
}
#endif
#else
@available(iOS 26.0, *)
struct DashboardFatigueInsight: Sendable {
    var headline: String
    var body: String
}

@available(iOS 26.0, *)
struct SuggestedDrill: Sendable {
    var drillTitle: String
    var preRunDrillId: String
    var drillPurpose: String
    var drillCues: String
}

@available(iOS 26.0, *)
struct RunInsight: Sendable {
    var headline: String
    var observation: String
    var drills: [SuggestedDrill]
}

@available(iOS 26.0, *)
@MainActor
class CoachingEngine {
    static let shared = CoachingEngine()

    var inFlightTasks: [PersistentIdentifier: Task<Void, Never>] = [:]

    private init() {}

    func requestAnalysis(for runRecord: RunRecord, force: Bool = false) async {
        let runId = runRecord.persistentModelID
        guard let container = runRecord.modelContext?.container else { return }

        if let existingTask = inFlightTasks[runId] {
            _ = await existingTask.value
            return
        }

        if force, let oldInsight = runRecord.insight {
            runRecord.modelContext?.delete(oldInsight)
            runRecord.insight = nil
            try? runRecord.modelContext?.save()
        }

        let task = Task.detached {
            let analyzer = RunAnalyzerActor(modelContainer: container)
            await analyzer.generateAnalysis(for: runId, force: force)
        }

        inFlightTasks[runId] = task
        _ = await task.value
        inFlightTasks[runId] = nil
    }

    func generateInsight(for runData: RunDataForAI) async throws -> RunInsight {
        RunInsight(
            headline: String(localized: "Run Analyzed Successfully"),
            observation: String(localized: "Your run data has been processed. Stay consistent to build a stronger baseline over the next 30 days."),
            drills: [SuggestedDrill(
                drillTitle: String(localized: "Strides"),
                preRunDrillId: "strides",
                drillPurpose: String(localized: "Builds turnover and neural recruitment."),
                drillCues: String(localized: "Arms at 90 degrees, gentle grip, drop your shoulders and let your arms propel you.")
            )]
        )
    }

    func generateDashboardInsight(for timeFrame: String, runData: AggregateRunDataForAI) async throws -> DashboardFatigueInsight {
        if timeFrame == "7 Days" {
            return DashboardFatigueInsight(
                headline: String(localized: "Ready for Next Run"),
                body: String(localized: "Your recent runs show solid consistency. For your next run, focus on keeping your effort controlled and your turnover light.")
            )
        } else if timeFrame == "30 Days" {
            return DashboardFatigueInsight(
                headline: String(localized: "On Track for Goal"),
                body: String(localized: "Your 30-day training shows steady progression toward your goal. Keep building on this foundation with consistent weekly volume.")
            )
        } else {
            return DashboardFatigueInsight(
                headline: String(localized: "Lifetime Milestones"),
                body: String(localized: "Review your lifetime volume, personal records, and progression trends below.")
            )
        }
    }
}
#endif
