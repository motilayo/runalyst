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

    enum MessageSender: Equatable {
        case user
        case analyst
    }

    init(id: UUID = UUID(), sender: MessageSender, text: String, timestamp: Date = Date()) {
        self.id = id
        self.sender = sender
        self.text = text
        self.timestamp = timestamp
    }
}

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

        setupInitialGreeting()
    }

    private func setupInitialGreeting() {
        let runType = runRecord.detectedTypeRaw.isEmpty ? "Run" : runRecord.detectedTypeRaw
        let isIndoor = runRecord.isIndoor ?? false
        let envNote = isIndoor ? "on the treadmill" : "outdoors"
        let initialGreeting = "I took a look at your \(runType) \(envNote). What would you like to explore about your form, effort, or recovery?"
        messages.append(AnalystChatMessage(sender: .analyst, text: initialGreeting))
    }

    /// Sends a runner question and generates an analyst response with RAG telemetry context and guardrails.
    func sendMessage(_ userQuestion: String) async {
        let trimmed = userQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        messages.append(AnalystChatMessage(sender: .user, text: trimmed))
        isResponding = true
        defer { isResponding = false }

        // --- Guardrail 1: Medical Boundary ---
        let lowercased = trimmed.lowercased()
        let medicalKeywords = ["pain", "hurt", "injured", "injury", "shin splint", "plantar", "achilles", "knee pain", "diagnosis", "doctor", "strain my"]
        if medicalKeywords.contains(where: { lowercased.contains($0) }) {
            let medicalReferral = "I'm an AI running coach, not a doctor or physical therapist. If you're experiencing pain or persistent soreness, please take time to rest and check in with a doctor or physical therapist."
            messages.append(AnalystChatMessage(sender: .analyst, text: medicalReferral))
            return
        }

        // --- Guardrail 2: Hardware Boundary (Indoor GPS inquiry) ---
        let gpsKeywords = ["gps", "route", "map", "elevation gain", "hills outside"]
        if (runRecord.isIndoor ?? false) && gpsKeywords.contains(where: { lowercased.contains($0) }) {
            let hardwareExplanation = "This run was recorded on a treadmill indoors. Apple Watch turns off GPS and elevation tracking indoors because there are no satellites or hills inside. We track your run using your arm swing, cadence, and heart rate instead."
            messages.append(AnalystChatMessage(sender: .analyst, text: hardwareExplanation))
            return
        }

        // --- Guardrail 3: Subjective Gear / Shoe Boundary ---
        let gearKeywords = ["shoes", "shoe", "vaporfly", "alphafly", "superblast", "hoka", "nike", "saucony", "gear to buy", "what shoes"]
        if gearKeywords.contains(where: { lowercased.contains($0) }) {
            let gearResponse = "I focus on your running form, cadence, and effort rather than specific shoe brands. The best shoe is whatever feels comfortable for you, but keeping a quick, light step under your hips does the most to protect your legs."
            messages.append(AnalystChatMessage(sender: .analyst, text: gearResponse))
            return
        }

        // Test responder hook (for unit tests / mock free speak)
        #if DEBUG
        if let responder = modelResponder {
            do {
                let systemInstructions = buildSystemInstructions()
                let responseText = try await responder(systemInstructions, trimmed)
                messages.append(AnalystChatMessage(sender: .analyst, text: responseText))
                return
            } catch {
                print("Model responder error: \(error)")
            }
        }
        #endif

        // FoundationModels on-device generation with rich Workout Data Sheet
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if SystemLanguageModel.default.isAvailable {
                do {
                    let responseText = try await generateFoundationModelResponse(for: trimmed)
                    messages.append(AnalystChatMessage(sender: .analyst, text: responseText))
                    return
                } catch {
                    print("FoundationModels chat error: \(error)")
                }
            }
        }
        #endif

        // Clean, data-grounded fallback response (offline / non-AI hardware)
        let fallbackResponse = generateDataGroundedFallback(for: trimmed)
        messages.append(AnalystChatMessage(sender: .analyst, text: fallbackResponse))
    }

    // MARK: - FoundationModels Prompt Construction

    func buildSystemInstructions() -> String {
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        let analysis = WorkoutAnalysisContext(
            runRecord: runRecord,
            runSignature: runSignature,
            macroProfile: macroProfile,
            recoveryTimeline: recoveryTimeline,
            baselineStats: baselineStats,
            runnerProfile: runnerProfile
        )
        let dataSheet = analysis.groundedPromptSummary()

        return """
        WORKOUT DATA SHEET:
        \(dataSheet)

        You are my personal running coach and exercise physiologist. You have access to my workout data sheet above.
        Speak directly to me ("you" / "your") like an experienced, objective running coach in a conversation—clear, direct, perceptive, and data-backed, with no generic motivational platitudes and no lecturing. Never refer to me as "the runner" or in the third person.

        How to answer:
        - Answer what I ask directly, using the data sheet to back up your points.
        - Athlete Identity & Persona Tone:
          • Tailor your vocabulary and depth to my Athletic Experience Level (\(analysis.runnerProfile.experienceLevel)).
            - If Novice / Beginner: explain biomechanical mechanisms clearly and provide protective, foundational pacing cues.
            - If Advanced / Veteran or Competitive: speak the language of periodization, stride economy, and rep execution with high precision.
          • Frame all training reflections around my Active Training Goal (\(analysis.runnerProfile.trainingGoal)) and Current 30-Day Training Load (\(analysis.runnerProfile.loadSummary)).
        - Calendar and temporal grounding:
          • Check "Current Date (Today)" vs "Workout Date" on the data sheet carefully. This workout may have taken place days ago.
          • NEVER refer to this workout as "today", "today's run", or "today's workout" unless the Workout Date is literally today. If the workout is from the past, refer to it accurately (e.g. "in your \(analysis.workoutWeekday) run" or "in your last session").
          • When I ask about future runs (e.g., "how long should I run?", "can I do intervals?", "should I ease up?"):
            - If Recovery Status is FULLY RECOVERED, my legs are fresh! Do not claim I am in a "recovery window" or carrying "residual strain" from a past workout.
            - Never contradict yourself (e.g. do not say "easing up is not the right approach" while also saying "you're not ready for intensity").
            - Past fatigue markers (cardiac drift, cadence drop) from days ago describe pacing execution during that past workout, NOT active fatigue preventing me from running today.
          • If I state or clarify that I didn't run today or yesterday, immediately acknowledge that fact and ground your advice in my current rest days.
        - Biomechanics, Physiology & Decoupling (The 'Why'):
          • Connect physical feeling to mechanics: explain how stride turnover (SPM), vertical bounce (cm), and stride length (m) affect heart rate and running economy.
          • Stride Archetype (\(analysis.strideArchetype)): Explain what it reveals about my movement efficiency without being dogmatic about a single cadence number (turnover is calibrated to my height).
          • Cardiac drift (+BPM in second half) is cardiovascular fatigue, dehydration, or heat—NEVER describe it as "acceleration" or speeding up.
          • Environmental & Terrain Modifiers: When elevation gain is high, hills are present, or running on hot days, heart rate naturally spikes and Efficiency Factor mathematically decreases. Interpret this as gravitational and thermal cardiovascular strain, NOT declining aerobic fitness.
        - Interval Targets & Pacing:
          • When evaluating splits or intervals, cite and evaluate actual reps, pacing, and cadence stability.
          • Never describe a wide pace spread spanning tens of seconds (e.g. 5:04–6:02/km) as "tight", "repeatable", or "metronomic", and never quote an extreme min-to-max historical spread as a target pace.
          • If suggesting an interval target pace, prescribe a tight 5–10s band (e.g. 5:10–5:15/km).
        - Workout Guidance & Drills:
          • Do NOT invent or prescribe custom structured workout routines (e.g. "45 minutes of intervals with 10 min warm-up")—the app already provides dedicated structured drills in the drills library.
          • Keep training advice focused on session intent (e.g. easy aerobic base, recovery jog, tempo surge) toward my goal of \(analysis.runnerProfile.trainingGoal), and point to relevant library drills (like Cadence Pyramids or Strides) when technique prep is needed.
        - When I ask what a concept means (like threshold), explain the concept simply, then connect it to how I ran.
        - When I ask for insights or what to improve, give me the coaching story: what happened, why my body reacted that way, and what to adjust next time.
        - Speak like an experienced, objective running coach in natural conversation (typically 1 to 3 short paragraphs).
          • Do NOT force bullet points into every response. Use bullet points ONLY when listing multiple splits, intervals, or distinct workout options. For regular coaching advice, write natural conversational sentences.
          • Do NOT repeat the same metrics or recommend the same drill across consecutive turns. Only mention technique drills when directly relevant.
        - Only discuss future training, recovery timelines, or readiness when I specifically ask about them. Do not append unasked readiness sign-offs or disclaimers about unrecorded sensors.
        Respond in \(language).
        """
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func generateFoundationModelResponse(for userQuestion: String) async throws -> String {
        let systemInstructions = buildSystemInstructions()

        let session: LanguageModelSession
        if let existing = modelSession as? LanguageModelSession {
            session = existing
        } else {
            session = LanguageModelSession(
                model: SystemLanguageModel.default,
                instructions: systemInstructions
            )
            self.modelSession = session
        }

        let reply: String
        do {
            reply = try await session.respond(to: userQuestion).content
        } catch {
            let errorDesc = "\(error)".lowercased()
            let isContextExceeded = errorDesc.contains("context") || errorDesc.contains("token") || errorDesc.contains("limit")
            guard isContextExceeded else { throw error }
            let freshSession = LanguageModelSession(
                model: SystemLanguageModel.default,
                instructions: systemInstructions
            )
            self.modelSession = freshSession
            reply = try await freshSession.respond(to: userQuestion).content
        }

        return reply
    }
    #endif

    /// Synthesizes 1,000-meter splits from phase segments if physical splits were not persisted.
    static func synthesizeSplitsFromSegments(_ segments: [PhaseSegment], splitDistanceMeters: Double = 1000.0) -> [RunSplit] {
        guard !segments.isEmpty else { return [] }
        var splits: [RunSplit] = []
        var currentSplitIndex = 1
        var accumulatedDist: Double = 0
        var splitDuration: Double = 0
        var splitHRSum: Double = 0
        var splitCadenceSum: Double = 0
        var splitWeight: Double = 0

        for seg in segments where seg.avgPace > 0 && seg.durationSeconds > 0 {
            let segDist = (seg.durationSeconds / seg.avgPace) * 1000.0
            var remainingDist = segDist

            while remainingDist > 0 {
                let needed = splitDistanceMeters - accumulatedDist
                let takeDist = min(remainingDist, needed)
                let fraction = takeDist / segDist
                let takeDur = fraction * seg.durationSeconds

                accumulatedDist += takeDist
                splitDuration += takeDur
                splitHRSum += seg.avgHR * takeDur
                splitCadenceSum += seg.avgCadence * takeDur
                splitWeight += takeDur

                remainingDist -= takeDist

                if accumulatedDist >= splitDistanceMeters {
                    let avgPace = (splitDuration / splitDistanceMeters) * 1000.0
                    let avgHR = splitWeight > 0 ? (splitHRSum / splitWeight) : seg.avgHR
                    let avgCad = splitWeight > 0 ? (splitCadenceSum / splitWeight) : seg.avgCadence

                    splits.append(RunSplit(
                        index: currentSplitIndex,
                        distanceMeters: splitDistanceMeters,
                        durationSeconds: splitDuration,
                        paceSecondsPerKm: avgPace,
                        avgHeartRate: avgHR,
                        avgCadence: avgCad,
                        elevationGainMeters: 0
                    ))

                    currentSplitIndex += 1
                    accumulatedDist = 0
                    splitDuration = 0
                    splitHRSum = 0
                    splitCadenceSum = 0
                    splitWeight = 0
                }
            }
        }

        if accumulatedDist >= 500.0 {
            let avgPace = (splitDuration / accumulatedDist) * 1000.0
            let avgHR = splitWeight > 0 ? (splitHRSum / splitWeight) : 0
            let avgCad = splitWeight > 0 ? (splitCadenceSum / splitWeight) : 0
            splits.append(RunSplit(
                index: currentSplitIndex,
                distanceMeters: accumulatedDist,
                durationSeconds: splitDuration,
                paceSecondsPerKm: avgPace,
                avgHeartRate: avgHR,
                avgCadence: avgCad,
                elevationGainMeters: 0
            ))
        }

        return splits
    }

    // MARK: - Data-Grounded Fallback Response (Offline / Non-AI Hardware)

    private func generateDataGroundedFallback(for userQuestion: String) -> String {
        let q = userQuestion.lowercased().replacingOccurrences(of: "’", with: "'")
        let analysis = WorkoutAnalysisContext(
            runRecord: runRecord,
            runSignature: runSignature,
            macroProfile: macroProfile,
            recoveryTimeline: recoveryTimeline,
            baselineStats: baselineStats
        )

        // 1. Splits, intervals, and pacing segments
        if q.contains("split") || q.contains("interval") || q.contains("rep") || q.contains("segment") || q.contains("fastest") || q.contains("slowest") {
            return analysis.formatSplitReport()
        }

        // 2. Grade and performance evaluation
        if q.contains("grade") || q.contains("rate") || q.contains("score") || q.contains("how did i do") {
            return analysis.overallGradeReport.sentence
        }

        // 3. Sensor queries (vertical oscillation, stride length)
        if q.contains("vertical") || q.contains("bounce") || q.contains("oscillation") {
            if let osc = runRecord.workingAvgVerticalOscillation {
                return "Your vertical bounce was \(String(format: "%.1f", osc)) cm."
            } else {
                return "Vertical oscillation wasn't recorded for this workout because it was an indoor treadmill run. Apple Watch measures vertical bounce outdoors or when paired with an authentic footpod."
            }
        }
        if q.contains("stride") {
            if let stride = runRecord.workingAvgStrideLength {
                return "Your average stride length was \(String(format: "%.2f", stride)) m."
            } else {
                return "Stride length wasn't recorded for this workout because it was an indoor treadmill run without a footpod."
            }
        }

        // 4. Classification explanations
        if q.contains("why") && (q.contains("label") || q.contains("classif") || q.contains("mixed")) {
            let type = runRecord.detectedTypeRaw.isEmpty ? "Run" : runRecord.detectedTypeRaw
            let reason = runRecord.needsInclineReview == true
                ? "surges and cadence drops on the treadmill indicated incline intervals."
                : "repeated pace surges and irregular work/recovery intervals."
            return "This session was classified as \(type) due to \(reason)"
        }

        // 5. Calendar / Day queries
        if q.contains("what day is") || q.contains("what is today") || q.contains("what date is") {
            return "Today is \(analysis.currentWeekday), \(analysis.currentDateFormatted)."
        }

        // 6. Runner clarification (didn't run today / yesterday)
        if q.contains("didn't run") || q.contains("didnt run") || q.contains("haven't run") || q.contains("havent run") {
            let timeframe = q.contains("yesterday") ? "yesterday" : "today"
            return "Understood—today is \(analysis.currentWeekday), and you haven't run \(timeframe). You have \(analysis.daysSinceWorkout) days of rest since your last session on \(analysis.workoutWeekday)."
        }

        // 7. Future training, recovery, and readiness
        if q.contains("can i run") || q.contains("ready") || q.contains("recovery") || q.contains("rest") || q.contains("tomorrow") || q.contains("today") || q.contains("push") || q.contains("hard") {
            if analysis.recoveryTimeline.readyForHard {
                return "Your recovery status is \(analysis.recoveryTimeline.state.rawValue): fully recovered and cleared for your next workout."
            } else {
                return "Your recovery status is \(analysis.recoveryTimeline.state.rawValue): in active recovery until \(analysis.recoveryTimeline.earliestHardPhrase)."
            }
        }

        // 8. Direct data summary
        let pace = PaceFormatter.formatPace(secondsPerKilometer: runRecord.workingAvgPace)
        let cad = Int(runRecord.workingAvgCadence)
        let hr = Int(runRecord.workingAvgHeartRate)
        return "Workout data: \(analysis.detectedType) (\(analysis.workoutWeekday), \(analysis.workoutDateFormatted)). Pace: \(pace), Cadence: \(cad) SPM, HR: \(hr) BPM."
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
                acuteLoad: profile.acuteLoad ?? 0,
                chronicWeeklyLoad: profile.chronicWeeklyLoad ?? 0,
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
