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
            baselineStats: baselineStats
        )
        let dataSheet = analysis.groundedPromptSummary()

        return """
        WORKOUT DATA SHEET:
        \(dataSheet)

        You are my personal running coach. You have access to my workout data sheet above.
        Speak directly to me ("you" / "your") like an experienced, objective running coach in a conversation—clear, direct, and data-backed, with no generic motivational platitudes and no lecturing. Never refer to me as "the runner" or in the third person.

        How to answer:
        - Answer what I ask directly, using the data sheet to back up your points.
        - Calendar and temporal grounding:
          • Check "Current Date (Today)" vs "Workout Date" on the data sheet carefully. This workout may have taken place days ago.
          • NEVER refer to this workout as "today", "today's run", or "today's workout" unless the Workout Date is literally today. If the workout is from the past, refer to it accurately (e.g. "in your \(analysis.workoutWeekday) run" or "in your last session").
          • When I ask about future runs (e.g., "how long should I run?", "can I do intervals?", "should I ease up?"):
            - If Recovery Status is FULLY RECOVERED, my legs are fresh! Do not claim I am in a "recovery window" or carrying "residual strain" from a past workout.
            - Never contradict yourself (e.g. do not say "easing up is not the right approach" while also saying "you're not ready for intensity").
            - Past fatigue markers (cardiac drift, cadence drop) from days ago describe pacing execution during that past workout, NOT active fatigue preventing me from running today.
          • If I state or clarify that I didn't run today or yesterday, immediately acknowledge that fact and ground your advice in my current rest days.
        - When I ask about splits or intervals, cite and evaluate the actual reps, pacing, and cadence stability.
        - When I ask what a concept means (like threshold), explain the concept simply, then connect it to how I ran.
        - When I ask for insights or what to improve, give me the coaching story: what happened, why my body reacted that way, and what to adjust next time.
        - Speak like an experienced, objective running coach in natural conversation (typically 1 to 3 short paragraphs).
          • Do NOT force bullet points into every response. Use bullet points ONLY when listing multiple splits, intervals, or distinct workout options. For regular coaching advice, write natural conversational sentences.
          • Do NOT repeat the same metrics or recommend the same drill in every turn. Only mention technique drills when directly relevant.
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
}

// MARK: - Supporting Models

/// Deterministic recovery clock: when the runner can absorb another hard session.
struct RecoveryTimeline: Equatable, Sendable {
    let now: Date
    let lastHard: ReadinessRunSnapshot?
    let hardSessionsLast72h: Int
    let requiredHours: Double
    let state: ReadinessState

    static func build(runs: [ReadinessRunSnapshot], readiness: ReadinessAssessment, now: Date) -> RecoveryTimeline {
        let hard = runs
            .filter { $0.date <= now && $0.isHardSession }
            .sorted { $0.date > $1.date }
        let recentCount = hard.filter { now.timeIntervalSince($0.date) <= 72 * 3600 }.count
        var required: Double = 48
        if let last = hard.first, last.percentZone4 >= 0.6 { required = 72 }
        if recentCount >= 2 { required = 72 }
        if readiness.state == .acuteFatigue { required = max(required, 72) }
        return RecoveryTimeline(
            now: now,
            lastHard: hard.first,
            hardSessionsLast72h: recentCount,
            requiredHours: required,
            state: readiness.state
        )
    }

    var hoursSinceLastHard: Double? {
        lastHard.map { now.timeIntervalSince($0.date) / 3600 }
    }

    var earliestHardDate: Date? {
        guard let lastHard else {
            return state == .acuteFatigue ? now.addingTimeInterval(24 * 3600) : nil
        }
        let byRecovery = lastHard.date.addingTimeInterval(requiredHours * 3600)
        if state == .acuteFatigue && byRecovery <= now {
            return now.addingTimeInterval(24 * 3600)
        }
        return byRecovery
    }

    var readyForHard: Bool {
        guard let earliest = earliestHardDate else { return true }
        return earliest <= now
    }

    func isCleared(for timeframe: String) -> Bool {
        guard let earliest = earliestHardDate else { return true }
        let lower = timeframe.lowercased()
        if lower == "today" {
            return readyForHard
        }
        let cal = Calendar.current
        let targetDate: Date? = {
            if lower == "tomorrow" {
                return cal.date(byAdding: .day, value: 1, to: now)
            }
            let days = ["sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7]
            guard let targetWeekday = days.first(where: { lower.contains($0.key) })?.value else { return nil }
            let currentWeekday = cal.component(.weekday, from: now)
            var diff = targetWeekday - currentWeekday
            if diff <= 0 { diff += 7 }
            return cal.date(byAdding: .day, value: diff, to: now)
        }()
        guard let targetDate else { return readyForHard }
        return cal.startOfDay(for: targetDate) >= cal.startOfDay(for: earliest)
    }

    var easyCap: ClosedRange<Int>? {
        guard !readyForHard else { return nil }
        guard let hours = hoursSinceLastHard else { return 20...30 }
        return hours < 24 ? 20...30 : 30...40
    }

    var earliestHardPhrase: String {
        guard let date = earliestHardDate else { return "now" }
        return Self.futurePhrase(for: date, relativeTo: now)
    }

    static func weekday(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    private static func partOfDay(_ date: Date, calendar: Calendar) -> String {
        let hour = calendar.component(.hour, from: date)
        if hour < 12 { return "morning" }
        if hour < 17 { return "afternoon" }
        return "evening"
    }

    static func futurePhrase(for date: Date, relativeTo now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "later today" }
        let part = partOfDay(date, calendar: calendar)
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "tomorrow \(part)"
        }
        return "\(weekday(date)) \(part)"
    }

    static func pastPhrase(for date: Date, relativeTo now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "earlier today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "yesterday"
        }
        if now.timeIntervalSince(date) < 6 * 24 * 3600 {
            return "on \(weekday(date))"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        return "on \(formatter.string(from: date))"
    }

    static func durationPhrase(hours: Double) -> String {
        if hours < 1 { return "under an hour" }
        if hours < 36 { return "\(Int(hours.rounded())) hours" }
        return "\(Int((hours / 24).rounded())) days"
    }
}

/// Input metrics for deterministic performance grading.
struct RunGradeInput {
    let type: String
    let isHard: Bool
    let percentZone4: Double
    let cadence: Int
    let workPaces: [Double]
    let paceDeltaVsBaseline: Double?
    let hrDeltaVsBaseline: Double?
    let cadenceFade: Bool
    let cardiacDrift: Bool
}

/// Formatted report card from deterministic grading.
struct RunGradeReport {
    let grade: String
    let strengths: [String]
    let focus: String?
    let type: String

    var sentence: String {
        var text = "I'd grade this \(type) a \(grade)."
        if !strengths.isEmpty {
            text += " The highlights: \(strengths.prefix(2).joined(separator: ", and "))."
        }
        if let focus {
            text += " The one thing to work on: \(focus)."
        } else {
            text += " There's no obvious weak spot here—keep doing what you're doing."
        }
        return text
    }
}

/// Deterministic performance grade built from the run's own telemetry.
enum RunGrade {
    static func evaluate(_ input: RunGradeInput) -> RunGradeReport {
        var score = 95
        var strengths: [String] = []
        var focuses: [String] = []
        if input.cadence < 150 {
            score -= 10
            focuses.append("your foot turnover was on the slower side—aim for quicker, lighter steps")
        } else if input.cadence >= 165 {
            strengths.append("quick, efficient foot turnover")
        } else {
            strengths.append("a solid, consistent cadence baseline")
        }

        if input.isHard {
            if input.percentZone4 >= 0.5 {
                strengths.insert("you committed fully to the hard work intervals", at: 0)
            }
            if input.workPaces.count >= 2, let first = input.workPaces.first, let last = input.workPaces.last, first > 0 {
                let fade = (last - first) / first
                let paces = input.workPaces
                let spread = ((paces.max() ?? first) - (paces.min() ?? first)) / first
                if fade > 0.05 {
                    score -= 10
                    focuses.append("your last rep faded noticeably—start the early reps a little more controlled")
                } else if spread < 0.03 {
                    strengths.append("evenly paced reps from first to last")
                }
            }
        } else if input.percentZone4 > 0.25 {
            score -= 10
            focuses.append("too much of this easy run crept into threshold intensity—slow down to keep easy days truly easy")
        }

        if input.cadenceFade {
            score -= 6
            focuses.append("your cadence faded late in the run")
        }
        if input.cardiacDrift && !input.isHard {
            score -= 6
            focuses.append("your heart rate drifted up while your pace held steady, a sign of fatigue or heat")
        }

        if let paceDelta = input.paceDeltaVsBaseline, let hrDelta = input.hrDeltaVsBaseline {
            if paceDelta > 5 && hrDelta <= 2 {
                score += 3
                strengths.insert("you ran faster than your 30-day average without raising your heart rate", at: 0)
            } else if paceDelta < -5 && hrDelta > 5 {
                score -= 6
                focuses.append("you were slower than your 30-day average at a higher heart rate, pointing to accumulated fatigue")
            }
        }

        return RunGradeReport(grade: letter(for: min(100, score)), strengths: strengths, focus: focuses.first, type: input.type)
    }

    static func letter(for score: Int) -> String {
        switch score {
        case 93...: return "A"
        case 88..<93: return "A-"
        case 83..<88: return "B+"
        case 78..<83: return "B"
        case 73..<78: return "B-"
        default: return "C+"
        }
    }
}
