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

        // FoundationModels on-device generation with RAG context
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

        // Deterministic Fallback response
        let fallbackResponse = generateDeterministicResponse(for: trimmed)
        messages.append(AnalystChatMessage(sender: .analyst, text: fallbackResponse))
    }
    // MARK: - Readiness (two clocks)

    /// Readiness as of the moment this run finished. Explains *this* workout.
    var readinessAssessment: ReadinessAssessment {
        assessReadiness(asOf: runRecord.date)
    }

    /// Readiness as of right now. Drives every forward-looking answer ("am I ready", "what next").
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

    /// Last 7 days of runs (as of now), always including the run being discussed.
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

    // MARK: - Deterministic answers (Swift decides, the model only voices)

    /// Returns the fully-resolved answer for decision questions, or `nil` for open/conceptual questions.
    func decisiveAnswer(for intent: AnalystIntent) -> String? {
        let timeline = recoveryTimeline
        switch intent {
        case .proposedWorkout(let workout):
            if workout.isHard {
                return proposedHardWorkoutAnswer(workout, timeline: timeline)
            }
            let target = RunPlanTarget(
                minutes: workout.minutes,
                distanceKm: nil,
                distanceLabel: nil,
                timeframe: "today",
                mentionsZone2: false
            )
            return runPlanningAnswer(for: target, timeline: timeline)
        case let .runPlanning(target):
            return runPlanningAnswer(for: target, timeline: timeline)
        case .didNotRunToday:
            return didNotRunAnswer(timeframe: "today", timeline: timeline)
        case .didNotRunYesterday:
            return didNotRunAnswer(timeframe: "yesterday", timeline: timeline)
        case .classificationExplanation:
            return classificationExplanationAnswer()
        case .splitPerformance:
            return splitPerformanceAnswer()
        case .focusDay(let day):
            return focusDayAnswer(day: day, timeline: timeline)
        case .pushIntensity:
            if timeline.readyForHard {
                return "You're recovered, so a controlled hard effort is fine today. Aim for comfortably hard rather than all-out, focusing on a crisp turnover so the effort comes from rhythm, not overstriding."
            }
            return "Keep your effort very light today—do not push hard. \(lastHardSentence(timeline)) Your body needs recovery, so stay conversational in Zone 2 or below until \(timeline.earliestHardPhrase)."
        case .crossTraining(let activity):
            return crossTrainingAnswer(activity: activity, timeline: timeline)
        case .restDay:
            return restDayAnswer(timeline: timeline)
        case .baseFitness:
            return baseFitnessAnswer()
        case .grade:
            return gradeAnswer()
        case .calories:
            return caloriesAnswer(timeline: timeline)
        case .motivation:
            return motivationAnswer(timeline: timeline)
        case .currentDay(let target):
            return currentDayAnswer(target: target, timeline: timeline)
        case .readinessExplanation:
            return readinessExplanationAnswer()
        case .general:
            return nil
        }
    }

    private func lastHardLabel(_ run: ReadinessRunSnapshot) -> String {
        let type = run.detectedType
        if type.isEmpty || type == "Steady Effort" || type == "Mixed Effort (Review)" {
            return "hard run"
        }
        return "\(type) session"
    }

    /// Natural context for the previous hard session without regurgitating threshold percentages.
    private func lastHardSentence(_ timeline: RecoveryTimeline) -> String {
        guard let last = timeline.lastHard else {
            return "You haven't logged a hard session in the past week."
        }
        let when = RecoveryTimeline.pastPhrase(for: last.date, relativeTo: timeline.now)
        return "Your \(lastHardLabel(last)) \(when) was a demanding threshold session."
    }

    private func proposedHardWorkoutAnswer(_ workout: ProposedWorkout, timeline: RecoveryTimeline) -> String {
        if timeline.readyForHard {
            let since = timeline.hoursSinceLastHard.map { "It's been \(RecoveryTimeline.durationPhrase(hours: $0)) since your last hard session" }
                ?? "You haven't done a hard session in the past week"
            return "Yes, you're ready for the \(workout.summary). \(since), and your recovery markers look good. Keep the first couple of reps a touch controlled, then build into the rest."
        }
        var answer = "Not yet—hold the \(workout.summary) until \(timeline.earliestHardPhrase). \(lastHardSentence(timeline)) An effort like that needs adequate recovery time before your legs can absorb another round of hard reps."
        if let reason = triggerSentence(currentReadiness.triggers) {
            answer += " \(reason)"
        }
        if let cap = timeline.easyCap {
            answer += " Until then, keep runs easy and conversational, around \(cap.lowerBound)–\(cap.upperBound) minutes."
        }
        return answer
    }

    private func runPlanningAnswer(for target: RunPlanTarget, timeline: RecoveryTimeline) -> String {
        let readiness = currentReadiness
        let avgPace = runRecord.workingAvgPace > 0 ? runRecord.workingAvgPace : 360.0
        let effectiveMinutes: Int? = {
            if let mins = target.minutes { return mins }
            if let km = target.distanceKm {
                return Int((km * avgPace / 60.0).rounded())
            }
            return nil
        }()

        let isTimeframeCleared = timeline.isCleared(for: target.timeframe)
        let activeCap: ClosedRange<Int>? = isTimeframeCleared ? nil : timeline.easyCap

        guard let cap = activeCap else {
            if readiness.state == .deload {
                let note = target.distanceLabel.map { " for your \($0)" } ?? ""
                return "Yes, you can run \(target.timeframe)\(note)—keep it light. You're in a deload week, so a relaxed, conversational effort lets your body absorb the recent training."
            }
            let distPhrase = target.distanceLabel.map { "for a \($0) run" } ?? "to run"
            let minutesNote = effectiveMinutes.map { " \($0) minutes is fine." } ?? ""
            return "Yes, you're good \(distPhrase) \(target.timeframe). Your recovery markers look solid, so a normal effort fits.\(minutesNote)"
        }

        let range = "\(cap.lowerBound)–\(cap.upperBound)"

        if let minutes = effectiveMinutes, minutes > cap.upperBound {
            let label = target.distanceLabel ?? "\(minutes) minutes"
            if target.mentionsZone2 {
                return "Zone 2 is the right intensity, but a \(label) (around \(minutes) minutes) is too long for \(target.timeframe). Cap it at \(range) minutes of easy running or a brisk walk, and save the longer Zone 2 run for \(timeline.earliestHardPhrase)."
            }
            return "A \(label) is too long for \(target.timeframe)—at your pace that's about \(minutes) minutes, and while recovering, your cap is \(range) easy minutes. Save longer runs for \(timeline.earliestHardPhrase) once your recovery clock clears; if you run \(target.timeframe), keep it to a light \(range)-minute jog."
        }

        if let label = target.distanceLabel {
            return "Yes, an easy \(label) fits \(target.timeframe): keep it to \(range) minutes, conversational in Zone 2 or below. Skip any fast surges until \(timeline.earliestHardPhrase)."
        }

        return "Yes—an easy run fits \(target.timeframe): \(range) minutes, conversational, in Zone 2 or below. Skip any fast surges until \(timeline.earliestHardPhrase)."
    }

    private func didNotRunAnswer(timeframe: String, timeline: RecoveryTimeline) -> String {
        let when = RecoveryTimeline.pastPhrase(for: runRecord.date, relativeTo: timeline.now)
        let dayName = RecoveryTimeline.weekday(runRecord.date)
        return "Understood—you haven't run \(timeframe). The session being analyzed was logged \(when). Taking \(timeframe) off gives your body time to stay fresh and rebuild after that \(dayName) workout."
    }

    private func classificationExplanationAnswer() -> String {
        let type = runRecord.detectedTypeRaw.isEmpty ? "Run" : runRecord.detectedTypeRaw
        let rationale: String = {
            if runRecord.needsInclineReview == true {
                return "Your heart rate surged and cadence dropped while treadmill speed stayed flat, indicating incline intervals or hill work on the belt."
            }
            if type.contains("Mixed") {
                return "Your run showed repeated pace surges and elevated heart rate spikes, but the work and recovery durations were irregular rather than structured intervals. It was labeled Mixed Effort so you can review and refine how it was tagged."
            }
            if type.contains("Interval") {
                return "The session showed distinct, alternating phases of fast work intervals and recovery periods."
            }
            if type.contains("Steady") {
                return "Your pacing and heart rate stayed consistent throughout the run with low pace variability."
            }
            if type.contains("Progression") {
                return "Your pace accelerated steadily from the early miles to the final stretch."
            }
            return "Based on your pace variability and heart rate response throughout the session."
        }()
        return "This session was classified as \(type). \(rationale)"
    }

    private func splitPerformanceAnswer() -> String {
        let signature = runSignature ?? runRecord.signature
        let segments = signature?.phaseSegments ?? []
        let movingSegments = segments.filter { $0.avgPace > 0 }
        let workSegments = segments.filter { $0.kind == "work" && $0.avgPace > 0 }

        let targetSegments = !workSegments.isEmpty ? workSegments : movingSegments
        guard !targetSegments.isEmpty else {
            let pace = PaceFormatter.formatPace(secondsPerKilometer: runRecord.workingAvgPace)
            return "Your pace averaged \(pace) throughout this workout with steady execution."
        }

        guard let fastest = targetSegments.min(by: { $0.avgPace < $1.avgPace }),
              let slowest = targetSegments.max(by: { $0.avgPace < $1.avgPace }) else {
            let pace = PaceFormatter.formatPace(secondsPerKilometer: runRecord.workingAvgPace)
            return "Your pace averaged \(pace) throughout this workout with steady execution."
        }

        let fStart = Int(fastest.startSeconds / 60)
        let fEnd = Int(fastest.endSeconds / 60)
        let sStart = Int(slowest.startSeconds / 60)
        let sEnd = Int(slowest.endSeconds / 60)

        let fastestPace = PaceFormatter.formatPace(secondsPerKilometer: fastest.avgPace)
        let slowestPace = PaceFormatter.formatPace(secondsPerKilometer: slowest.avgPace)

        if workSegments.count >= 2 {
            let fastestIndex = (workSegments.firstIndex(where: { $0.id == fastest.id }) ?? 0) + 1
            let slowestIndex = (workSegments.firstIndex(where: { $0.id == slowest.id }) ?? 0) + 1
            return "Your fastest work rep was Rep \(fastestIndex) (min \(fStart)–\(fEnd)) at \(fastestPace) with \(Int(fastest.avgCadence)) SPM cadence. Your slowest work rep was Rep \(slowestIndex) (min \(sStart)–\(sEnd)) at \(slowestPace) with \(Int(slowest.avgHR)) BPM heart rate."
        } else {
            return "Your fastest stretch was at minutes \(fStart)–\(fEnd) at \(fastestPace). Your slowest stretch was at minutes \(sStart)–\(sEnd) at \(slowestPace)."
        }
    }

    private func focusDayAnswer(day: String, timeline: RecoveryTimeline) -> String {
        if timeline.isCleared(for: day) {
            return "For \(day), your recovery clock is cleared and you're good to go. A normal steady run or quality session fits well."
        }

        guard let cap = timeline.easyCap else {
            return "For \(day), you're recovered and good to go. A normal easy or steady run fits well."
        }
        let range = "\(cap.lowerBound)–\(cap.upperBound)"
        return "For \(day), keep your effort very light: an easy \(range)-minute conversational jog in Zone 2 or below, or complete rest. Keeping \(day) strictly easy protects your legs until your recovery clock clears."
    }

    private func gradeAnswer() -> String {
        let signature = runSignature ?? runRecord.signature
        let workPaces = signature?.phaseSegments.filter { $0.kind == "work" }.map(\.avgPace) ?? []
        let report = RunGrade.evaluate(
            RunGradeInput(
                type: runRecord.detectedTypeRaw.isEmpty ? "run" : runRecord.detectedTypeRaw,
                isHard: isHeavySession,
                percentZone4: runRecord.percentZone4,
                cadence: Int(runRecord.workingAvgCadence),
                workPaces: workPaces,
                paceDeltaVsBaseline: baselineStats.map { $0.avgPace - runRecord.workingAvgPace },
                hrDeltaVsBaseline: baselineStats.map { runRecord.workingAvgHeartRate - $0.avgHR },
                cadenceFade: readinessAssessment.triggers.contains(.cadenceFade),
                cardiacDrift: readinessAssessment.triggers.contains(.cardiacDrift)
            )
        )
        return report.sentence
    }

    private func caloriesAnswer(timeline: RecoveryTimeline) -> String {
        guard let cap = timeline.easyCap else {
            return "Calorie burn tracks mostly with duration and distance, not intensity—so a longer easy run burns more than a short hard one. You're recovered, so if burning more is the goal, extend today's easy run rather than speeding it up."
        }
        return "You're right—an easy recovery jog burns less energy than a long hard session, because calorie burn tracks mostly with duration and distance. But recovery days aren't about burning calories: they let your body repair so your next hard session, \(timeline.earliestHardPhrase), is high quality. If you want more movement today, add an easy walk—it burns energy without adding running fatigue."
    }

    private func motivationAnswer(timeline: RecoveryTimeline) -> String {
        if timeline.readyForHard {
            return "That drive is a real asset, and good news: you're recovered, so today is a good day to put it into a quality session. Go hard on the reps and truly easy on the recoveries—that contrast is where the speed comes from."
        }
        return "That drive is a real asset—hard efforts are where you sharpen your speed. But the fitness from those pushes is built while you recover; stack hard days back-to-back and you just dig a deeper hole. Your next chance to go hard is \(timeline.earliestHardPhrase)—save that energy for it."
    }

    private func currentDayAnswer(target: String, timeline: RecoveryTimeline) -> String {
        let cal = Calendar.current
        let now = timeline.now
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale(identifier: "en_US_POSIX")
        weekdayFormatter.dateFormat = "EEEE"

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "MMMM d"

        if target == "tomorrow" {
            let tomorrow = cal.date(byAdding: .day, value: 1, to: now) ?? now
            let dayName = weekdayFormatter.string(from: tomorrow)
            let dateStr = dateFormatter.string(from: tomorrow)
            if timeline.readyForHard {
                return "Tomorrow is \(dayName), \(dateStr). You're recovered and in a great spot for your training."
            } else if timeline.isCleared(for: "tomorrow") {
                return "Tomorrow is \(dayName), \(dateStr). Your recovery clock clears by tomorrow, so you'll be ready for a normal workout."
            } else {
                let cap = timeline.easyCap?.upperBound ?? 40
                return "Tomorrow is \(dayName), \(dateStr). Recovery from your recent workout will still be active, so keep tomorrow to an easy jog under \(cap) minutes or take it as a rest day."
            }
        } else if target == "yesterday" {
            let yesterday = cal.date(byAdding: .day, value: -1, to: now) ?? now
            let dayName = weekdayFormatter.string(from: yesterday)
            let dateStr = dateFormatter.string(from: yesterday)
            return "Yesterday was \(dayName), \(dateStr)."
        } else {
            let dayName = weekdayFormatter.string(from: now)
            let dateStr = dateFormatter.string(from: now)
            if timeline.readyForHard {
                return "Today is \(dayName), \(dateStr). You're fully recovered and good to go for your training."
            } else {
                let cap = timeline.easyCap?.upperBound ?? 40
                return "Today is \(dayName), \(dateStr). Your recovery clock is still active, so keep today to a light jog under \(cap) minutes or complete rest until \(timeline.earliestHardPhrase)."
            }
        }
    }

    private func readinessExplanationAnswer() -> String {
        let readiness = currentReadiness
        let ratio = readiness.acwr.map { "ACWR \(String(format: "%.2f", $0))" } ?? "not enough history yet for a reliable ACWR"
        let reason = triggerPhrase(readiness.triggers) ?? "the acute fatigue from your most recent hard workout"
        return "Your 4-week training load looks balanced (\(ratio)), but your readiness was adjusted because of \(reason). Training load measures how this week compares with the last month, while readiness looks at immediate recovery—so a hard session in the last couple of days lowers readiness even when your monthly balance is fine."
    }

    private func crossTrainingAnswer(activity: String, timeline: RecoveryTimeline) -> String {
        guard timeline.easyCap != nil else {
            return "Yes, a \(activity) is a great option today. Your recovery markers look good, so keeping the effort easy to moderate gives you a solid aerobic session while giving your running joints a break."
        }
        return "Yes, a light \(activity) is an excellent choice today. It gives your legs an active recovery flush without the ground impact of running, letting your body absorb your recent hard session. Keep the resistance and intensity light in Zone 1 or 2."
    }

    private func restDayAnswer(timeline: RecoveryTimeline) -> String {
        if timeline.readyForHard {
            return "A complete rest day is always a safe choice if you're feeling sluggish. You're recovered and ready to run when you want, but taking the day off will keep your legs fresh."
        }
        return "Yes, taking a full rest day is a smart call today. That hard session took a real toll on your body, and complete rest gives you the downtime you need to repair and absorb that training."
    }

    private func baseFitnessAnswer() -> String {
        let cad = Int(runRecord.workingAvgCadence)
        if cad >= 150 {
            return "Yes, you have built a solid base to begin 5k and 10k training. Your cadence turnover and steady pacing show good aerobic efficiency. As you shift gears, introduce faster intervals gradually—about one workout a week—while keeping the majority of your weekly volume easy and conversational so your body absorbs the work."
        } else {
            return "You're building solid endurance, but quickening your foot turnover will strengthen your base before shifting gears to 5k and 10k workouts. Bringing your cadence up toward a lighter step rhythm will make faster intervals feel easier and protect your legs as training demands increase."
        }
    }

    private func triggerPhrase(_ triggers: [ReadinessTrigger]) -> String? {
        let phrases = triggers.compactMap { trigger -> String? in
            switch trigger {
            case .consecutiveHardDays: return "hard sessions on back-to-back days"
            case .cardiacDrift: return "heart rate drifting up at a steady pace"
            case .cadenceFade: return "cadence fading late in your recent runs"
            case .acwrSpike(let ratio): return "a workload spike (\(String(format: "%.1f", ratio))× your monthly average)"
            case .mileageDeload: return nil
            }
        }
        return phrases.isEmpty ? nil : phrases.joined(separator: " and ")
    }

    private func triggerSentence(_ triggers: [ReadinessTrigger]) -> String? {
        triggerPhrase(triggers).map { "Your readiness also flags \($0)." }
    }

    // MARK: - FoundationModels

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func generateFoundationModelResponse(for userQuestion: String) async throws -> String {
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        let dataSheet = telemetryLines().joined(separator: "\n")

        let systemInstructions = """
        You are the Runalyst AI Running Analyst. You are chatting with the runner about the workout specified in the Workout Data below.

        WORKOUT DATA:
        \(dataSheet)

        GUIDELINES:
        1. USE THE DATA: Answer questions directly using the specific metrics, splits, segments, and reasons provided in the Workout Data.
        2. ANSWER SPECIFICS PRECISELY: When asked about best/worst splits, interval performance, pace, cadence, or heart rate, give the exact numbers and segment details from the data.
        3. EXPLAIN UNRECORDED DATA: If asked about a metric marked as 'Not recorded' (like vertical oscillation or GPS indoors), explain that it was not recorded for this treadmill workout because Apple Watch requires an outdoor run or an authentic footpod.
        4. EXPLAIN CLASSIFICATIONS: If asked why a workout was classified as Mixed Effort, Intervals, or Steady, explain the specific physiological and pacing reasons in the data.
        5. NO UNSOLICITED RECOVERY LECTURES: Do NOT append recovery advice, rest suggestions, or mentions of upcoming days unless the runner specifically asks about readiness, fatigue, recovery, or future workout planning.
        6. TEMPORAL ACCURACY: The workout was run on the date specified in the data. Do not confuse it with today.
        7. TONE: Direct, objective, knowledgeable running analyst. Be clear, analytical, and conversational. Never speak in generic motivational platitudes.
        Respond in \(language).
        """

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

        let groundingSource = [dataSheet, userQuestion]
            + messages.filter { $0.sender == .user }.map(\.text)

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

        if AnalystGrounding.hasUngroundedNumbers(reply, sources: groundingSource) {
            return generateDeterministicResponse(for: userQuestion)
        }
        return reply
    }
    #endif

    /// Structured workout telemetry and segment breakdown for the analyst (TN3193 token budget).
    private func telemetryLines() -> [String] {
        let env = (runRecord.isIndoor == true) ? "Indoor Treadmill" : "Outdoor Road/Trail"
        let cad = Int(runRecord.workingAvgCadence)
        let hr = Int(runRecord.workingAvgHeartRate)
        let pace = PaceFormatter.formatPace(secondsPerKilometer: runRecord.workingAvgPace)
        let type = runRecord.detectedTypeRaw.isEmpty ? "Run" : runRecord.detectedTypeRaw
        let durationMin = max(1, Int((runRecord.duration / 60.0).rounded()))
        let distanceKm = String(format: "%.1f km", runRecord.totalDistanceMeters / 1000.0)
        let now = Date()
        let todayWeekday = RecoveryTimeline.weekday(now)
        let hoursAgo = now.timeIntervalSince(runRecord.date) / 3600
        let pastPhrase = RecoveryTimeline.pastPhrase(for: runRecord.date, relativeTo: now)
        let isToday = Calendar.current.isDateInToday(runRecord.date)

        let workoutDay = RecoveryTimeline.weekday(runRecord.date)
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "MMM d"
        let workoutDateStr = dateFormatter.string(from: runRecord.date)
        let todayDateStr = dateFormatter.string(from: now)

        var lines = [
            "Workout Date: \(workoutDay), \(workoutDateStr) (\(pastPhrase), \(RecoveryTimeline.durationPhrase(hours: hoursAgo)) ago)",
            "Today's Date: \(todayWeekday), \(todayDateStr) (\(isToday ? "This workout was logged today" : "No workouts logged today; this workout is from \(pastPhrase)"))",
            "Environment: \(env) (Sensor: \(runRecord.dataSourceRaw?.capitalized ?? "Wrist accelerometer"))",
            "Classification: \(type) (confidence: \(Int(((runRecord.classificationConfidence ?? 0.85) * 100).rounded()))%)"
        ]

        let classificationRationale: String = {
            if runRecord.needsInclineReview == true {
                return "Elevated heart rate and reduced cadence while treadmill speed was flat, suggesting incline or hill intervals."
            }
            if type.contains("Mixed") {
                return "Repeated pace surges and elevated heart rate, but work/recovery periods were irregular rather than structured intervals. Flagged for review."
            }
            if type.contains("Interval") {
                return "Structured fast work intervals alternating with recovery periods."
            }
            if type.contains("Steady") {
                return "Consistent pace and controlled aerobic heart rate throughout the run."
            }
            if type.contains("Progression") {
                return "Pace steadily accelerated from early miles to late miles."
            }
            return "Assessed from pace variability and heart rate response."
        }()
        lines.append("Classification Rationale: \(classificationRationale)")

        lines.append("Duration: \(durationMin) min")
        lines.append("Distance: \(distanceKm)")
        lines.append("Working Pace: \(pace)")
        lines.append("Working Cadence: \(cad) SPM (\(cad < 150 ? "below" : "above") the 150 SPM floor)")
        lines.append("Working Heart Rate: \(hr) BPM")
        lines.append("Time at Threshold (Zone 4): \(Int((runRecord.percentZone4 * 100).rounded()))%")

        if let osc = runRecord.workingAvgVerticalOscillation {
            lines.append("Vertical Oscillation: \(String(format: "%.1f", osc)) cm")
        } else {
            lines.append("Vertical Oscillation: Not recorded (indoor treadmill without footpod)")
        }

        if let stride = runRecord.workingAvgStrideLength {
            lines.append("Stride Length: \(String(format: "%.2f", stride)) m")
        } else {
            lines.append("Stride Length: Not recorded (indoor treadmill without footpod)")
        }

        let signature = runSignature ?? runRecord.signature
        let segments = signature?.phaseSegments ?? []
        let movingSegments = segments.filter { $0.avgPace > 0 }
        let workSegments = segments.filter { $0.kind == "work" && $0.avgPace > 0 }
        let targetForExtremes = !workSegments.isEmpty ? workSegments : movingSegments

        if !segments.isEmpty {
            let fastestSeg = targetForExtremes.min(by: { $0.avgPace < $1.avgPace })
            let slowestSeg = targetForExtremes.max(by: { $0.avgPace < $1.avgPace })

            lines.append("Segments Breakdown (\(segments.count) segments):")
            var workIdx = 1
            var recIdx = 1
            for seg in segments.prefix(10) {
                let sMin = Int(seg.startSeconds / 60)
                let sSec = Int(seg.startSeconds.truncatingRemainder(dividingBy: 60))
                let eMin = Int(seg.endSeconds / 60)
                let eSec = Int(seg.endSeconds.truncatingRemainder(dividingBy: 60))
                let timeStr = String(format: "%d:%02d–%d:%02d", sMin, sSec, eMin, eSec)
                let sPace = PaceFormatter.formatPace(secondsPerKilometer: seg.avgPace)
                let label: String
                if seg.kind == "work" {
                    label = "Work Rep \(workIdx)"
                    workIdx += 1
                } else if seg.kind == "recovery" {
                    label = "Recovery \(recIdx)"
                    recIdx += 1
                } else if seg.kind == "walking" {
                    label = "Walking"
                } else {
                    label = "Steady"
                }
                var tags: [String] = []
                if seg.id == fastestSeg?.id { tags.append("FASTEST") }
                if seg.id == slowestSeg?.id { tags.append("SLOWEST") }
                let tagStr = tags.isEmpty ? "" : " [\(tags.joined(separator: ", "))]"
                lines.append("- \(label) (\(timeStr)): \(sPace), \(Int(seg.avgCadence)) SPM, \(Int(seg.avgHR)) BPM\(tagStr)")
            }
            if let f = fastestSeg {
                let fStart = Int(f.startSeconds / 60)
                let fEnd = Int(f.endSeconds / 60)
                lines.append("Fastest segment: \(PaceFormatter.formatPace(secondsPerKilometer: f.avgPace)) at min \(fStart)–\(fEnd)")
            }
            if let s = slowestSeg {
                let sStart = Int(s.startSeconds / 60)
                let sEnd = Int(s.endSeconds / 60)
                lines.append("Slowest segment: \(PaceFormatter.formatPace(secondsPerKilometer: s.avgPace)) at min \(sStart)–\(sEnd)")
            }
        }

        if let base = baselineStats {
            let paceDiffSec = Int(base.avgPace - runRecord.workingAvgPace)
            let hrDiff = hr - Int(base.avgHR)
            let cadDiff = cad - Int(base.avgCadence)
            let paceDesc = paceDiffSec >= 0 ? "\(paceDiffSec)s/km faster" : "\(abs(paceDiffSec))s/km slower"
            lines.append("Vs 30-day average: pace \(paceDesc), HR \(hrDiff >= 0 ? "+" : "")\(hrDiff) BPM, cadence \(cadDiff >= 0 ? "+" : "")\(cadDiff) SPM")
        }

        let readiness = currentReadiness
        var readinessLine = "Readiness: \(readiness.state.rawValue)"
        if let acwr = readiness.acwr {
            readinessLine += ", ACWR \(String(format: "%.2f", acwr))"
        }
        if let triggers = triggerPhrase(readiness.triggers) {
            readinessLine += ", recovery flags: \(triggers)"
        }
        lines.append(readinessLine)

        let timeline = recoveryTimeline
        if timeline.readyForHard {
            lines.append("Recovery Timeline: Cleared for hard efforts now.")
        } else if let cap = timeline.easyCap {
            lines.append("Recovery Timeline: Hard efforts cleared \(timeline.earliestHardPhrase); until then keep runs easy (\(cap.lowerBound)–\(cap.upperBound) min) or rest.")
        }

        if let drill = runRecord.insight?.drillRecommendations?.first ?? runRecord.insight?.drillRecommendation {
            lines.append("Suggested drill (mention only if asked about drills): \(drill.drillTitle)")
        }
        return lines
    }

    private func generateDeterministicResponse(for userQuestion: String) -> String {
        if let answer = decisiveAnswer(for: AnalystIntent.classify(userQuestion)) {
            return answer
        }

        let cad = Int(runRecord.workingAvgCadence)
        let hr = Int(runRecord.workingAvgHeartRate)
        let pace = PaceFormatter.formatPace(secondsPerKilometer: runRecord.workingAvgPace)
        let isIndoor = runRecord.isIndoor ?? false
        let type = runRecord.detectedTypeRaw.isEmpty ? "Run" : runRecord.detectedTypeRaw
        let lower = userQuestion.lowercased()
        let signature = runSignature ?? runRecord.signature
        let workSegments = signature?.phaseSegments.filter { $0.kind == "work" } ?? []
        let recoverySegments = signature?.phaseSegments.filter { $0.kind == "recovery" } ?? []

        // 4. Conceptual: Arm Drive / Arm Swing
        if lower.contains("arm drive") || lower.contains("arm swing") || (lower.contains("arm") && (lower.contains("help") || lower.contains("do") || lower.contains("why") || lower.contains("how"))) {
            return "Your arms act like a metronome for your legs—your feet naturally follow the tempo of your arm swing. Keeping your elbows bent around 90 degrees and driving them straight back helps you turn your feet over quicker without straining your legs, while preventing you from overreaching your stride."
        }

        // 5. Conceptual: Breathing
        if lower.contains("breath") || lower.contains("breathe") {
            return "Rhythmic breathing helps keep your heart rate calm and spreads landing impact across both legs. Try inhaling for 3 footstrikes and exhaling for 2—this odd-count pattern prevents you from always exhaling on the same foot strike, keeping your rhythm steady."
        }

        // 6. Conceptual: Posture
        if lower.contains("posture") || lower.contains("tall") || lower.contains("head") || lower.contains("shoulder") {
            return "Good running posture starts from the crown of your head: run tall with an open chest, keep your shoulders down and relaxed, and look 10 to 15 meters ahead rather than down at your feet. This opens up your airways and takes unnecessary tension out of your neck."
        }

        // 7. Performance: Degradation / Fading / Tiring out / End of run
        if lower.contains("degrad") || lower.contains("fade") || lower.contains("tiring") || lower.contains("tired") || lower.contains("end of") || lower.contains("late") || lower.contains("later") {
            if !workSegments.isEmpty {
                return "Your interval pacing held steady across your work reps without significant drop-off. Your heart rate climbed slightly during the later intervals, which is natural cardiac drift as fatigue builds—focusing on taking lighter, quicker steps late in the workout helps take stress off tired legs."
            } else {
                return "Your pace stayed consistent right through the later miles. Your heart rate rose slightly near the finish, which is normal aerobic fatigue, but you maintained your form and avoided any sudden slowdown."
            }
        }

        // 8. Weak point / Least Improved / Hardest / Room to grow
        if lower.contains("least") || lower.contains("weak") || lower.contains("struggle") || lower.contains("hardest") || lower.contains("room to grow") {
            if !recoverySegments.isEmpty {
                return "The biggest area for growth was your recovery between intervals. Your heart rate stayed elevated during rest breaks—slowing down to an easy walk or very gentle jog will let your pulse drop more so you have more pop on the work reps."
            } else if let osc = runRecord.workingAvgVerticalOscillation, osc > 9.5 {
                return "The main area with room to grow is vertical bounce. Directing more energy forward rather than bounding upward will soften ground impact and save leg fatigue."
            } else if cad < 160 {
                return "The clearest area with room to grow is foot turnover. Your feet are spending a bit longer on the ground each stride—gently quickening your step rhythm will make your effort feel lighter and take stress off your joints."
            } else {
                return "Your metrics were remarkably solid throughout this run. The main area to keep an eye on is late-run heart rate drift, keeping your early pace relaxed so you finish with plenty of energy in reserve."
            }
        }

        // 9. Most Improved / Strongest / Biggest Win
        if lower.contains("most improve") || lower.contains("biggest win") || lower.contains("best part") || lower.contains("strongest") || (lower.contains("most") && lower.contains("improve")) {
            if !workSegments.isEmpty {
                return "Your biggest win was your pacing control during work intervals. Holding a consistent, controlled rhythm on the fast segments showed great discipline and confidence."
            } else if hr <= 150 {
                return "Your standout strength was cardiovascular control—holding a steady aerobic effort showed great discipline and smart energy management."
            } else if cad >= 165 {
                return "Your standout strength was your sharp foot turnover. That quick rhythm keeps your feet landing softly under your hips, protecting your knees and shins."
            } else {
                return "Your biggest win was pacing consistency. Holding a steady rhythm without fading shows solid stamina and endurance control."
            }
        }

        // 10. Heart Rate / Effort / Intensity
        if lower.contains("effort") || lower.contains("heart rate") || lower.contains("hr") || lower.contains("intensity") || lower.contains("hard") {
            let envDetail = isIndoor
                ? " On the treadmill, where the belt enforces your speed, this shows steady cardiovascular control even without outdoor airflow."
                : " Your pacing was well-matched to your aerobic engine."
            return "Your effort was smooth and controlled.\(envDetail) You kept your intensity in a productive training zone without straining your engine."
        }

        // 11. Next Run / Tip / Focus / Technique / Form (rotated across 4 distinct, plain-language cues)
        if lower.contains("tip") || lower.contains("cue") || lower.contains("focus") || lower.contains("next run") || lower.contains("improve") || lower.contains("technique") || lower.contains("form") {
            let dist = AnalystIntent.parseDistance(userQuestion)
            let timeframe = AnalystIntent.parseTimeframe(userQuestion)
            let isCleared = recoveryTimeline.isCleared(for: timeframe)

            if let dist {
                if !isCleared && timeframe != "today" {
                    let cap = recoveryTimeline.easyCap?.upperBound ?? 40
                    return "A \(dist.label) \(timeframe) would conflict with your recovery clock after your recent hard session. If you do run \(timeframe), focus strictly on keeping it an easy, conversational recovery jog under \(cap) minutes, and save the \(dist.label) for \(recoveryTimeline.earliestHardPhrase)."
                } else if dist.label.contains("10k") || (dist.km >= 9.0 && dist.km <= 11.0) {
                    let dayContext = timeframe != "today" ? "For your 10k on \(timeframe), your recovery clock is cleared. " : "For a 10k, "
                    return "\(dayContext)Focus on settling into a relaxed, controlled rhythm through the first half rather than chasing pace early. Keep your cadence light and snappy, and let the effort build naturally so you finish strong."
                } else if dist.label.contains("5k") || (dist.km >= 4.5 && dist.km <= 6.0) {
                    let dayContext = timeframe != "today" ? "For your 5k on \(timeframe), your recovery clock is cleared. " : "For a 5k, "
                    return "\(dayContext)Focus on finding a crisp, light turnover right from the start without overstriding, keeping your shoulders relaxed and driving your elbows straight back to maintain momentum."
                } else if dist.km > 11.0 {
                    let dayContext = timeframe != "today" ? "For your \(dist.label) on \(timeframe), your recovery clock is cleared. " : "For your \(dist.label), "
                    return "\(dayContext)Focus on patient, steady pacing and rhythmic breathing, staying relaxed in your upper body so you conserve energy for the later miles."
                }
            }

            if cad < 150 {
                return "The best area to focus on is quickening your foot turnover. Aiming for lighter, quicker steps landing directly under your hips will take impact off your joints and improve your rhythm."
            }

            let coachTurnIndex = messages.filter { $0.sender == .analyst }.count % 4

            if coachTurnIndex == 0 {
                if let drill = runRecord.insight?.drillRecommendations?.first ?? runRecord.insight?.drillRecommendation {
                    let purpose = drill.drillPurpose?.lowercased() ?? "cadence efficiency"
                    return "Your foot turnover is in a healthy groove. Before your next run, warm up with \(drill.drillTitle) to build \(purpose) and get your legs feeling springy."
                } else {
                    return "Your foot turnover is in a healthy groove. Before your next run, warm up with a few light 15-second Strides to wake up your fast-twitch muscle fibers and get your legs used to quick, effortless steps."
                }
            } else if coachTurnIndex == 1 {
                return "Your cadence turnover provides a solid foundation. Focus on landing softly with your feet directly under your hips rather than reaching forward—it keeps impact light on your knees and keeps your momentum moving ahead."
            } else if coachTurnIndex == 2 {
                return "With your turnover rhythm steady, try rhythmic breathing on your next run: inhale for 3 footstrikes and exhale for 2. This steady breathing pattern keeps your heart rate calm and balances landing impact across both legs."
            } else {
                return "Your foot turnover is steady. Focus on your posture: run tall with an open chest, keep your shoulders down and relaxed, and look 10 to 15 meters ahead instead of down at your feet."
            }
        }

        // 12. Cadence / Turnover specifically
        if lower.contains("cadence") || lower.contains("turnover") || lower.contains("rhythm") || lower.contains("spm") {
            if cad >= 168 {
                return "Your cadence averaged a sharp \(cad) SPM. That quick turnover keeps your feet landing softly under your hips, protecting your knees and keeping your stride light."
            } else if cad >= 150 {
                return "Your cadence averaged \(cad) SPM—a solid baseline above the 150 floor. Building that rhythm toward 165–170 SPM over time will shorten your ground contact and make your stride feel lighter."
            } else {
                return "Your cadence averaged \(cad) SPM, which is below the 150 floor. Taking shorter, quicker steps will reduce ground impact forces and protect your joints."
            }
        }

        // 13. Pace / Speed specifically
        if lower.contains("pace") || lower.contains("speed") || lower.contains("fast") || lower.contains("slow") {
            if isIndoor {
                return "You held a steady pace of \(pace) on the treadmill. Since the treadmill belt sets your speed, your true effort is best reflected in your heart rate and cadence turnover."
            } else {
                return "Your pace averaged \(pace), showing consistent, well-managed speed across the session."
            }
        }

        // 14. Bounce / Vertical Oscillation
        if lower.contains("bounce") || lower.contains("vertical") || lower.contains("oscillation") {
            if let osc = runRecord.workingAvgVerticalOscillation {
                return "Your vertical bounce was \(String(format: "%.1f", osc)) cm. Keeping that below 9 cm ensures your energy propels you forward rather than bounding upward into the air."
            } else {
                return "Vertical oscillation wasn't recorded for this workout because it was an indoor treadmill run. Apple Watch measures vertical bounce outdoors or when paired with an authentic footpod."
            }
        }

        // 15. Stride Length / Overstride
        if lower.contains("stride") || lower.contains("overstride") || lower.contains("reach") {
            if let stride = runRecord.workingAvgStrideLength {
                return "Your average stride length was \(String(format: "%.2f", stride)) m. Focus on landing directly beneath your hips to keep impact light."
            } else {
                return "Stride length wasn't recorded for this workout because it was an indoor treadmill run without a footpod. Focus on landing your feet directly under your hips rather than reaching forward."
            }
        }

        return "You held a solid, steady rhythm throughout this run. Focusing on quick, relaxed steps beneath your hips will keep your running smooth and injury-free."
    }
}

// MARK: - Deterministic Analyst Briefing

/// What the runner is actually asking, resolved in Swift so the model never has to guess.
enum AnalystIntent: Equatable, Sendable {
    case proposedWorkout(ProposedWorkout)
    case runPlanning(RunPlanTarget)
    case didNotRunToday
    case didNotRunYesterday
    case classificationExplanation
    case splitPerformance
    case focusDay(day: String)
    case pushIntensity
    case crossTraining(activity: String)
    case restDay
    case currentDay(target: String)
    case baseFitness
    case grade
    case calories
    case motivation
    case readinessExplanation
    case general

    private static let hardWords = ["speed", "push", "interval", "tempo", "threshold", "hill", "fartlek", "sprint", "repeat", "vo2", "race", "time trial", "pyramid", "hard"]

    static func classify(_ question: String) -> AnalystIntent {
        let q = question.lowercased().replacingOccurrences(of: "’", with: "'")
        func any(_ words: [String]) -> Bool { words.contains { q.contains($0) } }

        if any(["didn't run yesterday", "didnt run yesterday", "haven't run yesterday", "havent run yesterday"]) ||
            (q.contains("yesterday") && (q.contains("didn't") || q.contains("didnt") || q.contains("haven't") || q.contains("havent"))) {
            return .didNotRunYesterday
        }

        if any(["didn't run", "didnt run", "haven't run", "havent run", "no run today", "didn't do an easy run", "didnt do an easy run", "didn't do a run", "haven't done an easy run", "havent done an easy run"]) ||
           (q.contains("today") && (q.contains("didn't") || q.contains("didnt") || q.contains("haven't") || q.contains("havent"))) {
            return .didNotRunToday
        }

        if any(["why did you label", "why is this labeled", "why was this labeled", "why did you classify", "why is this classified", "why was my run labeled", "why did you label my run", "why 'mixed effort'", "why mixed effort", "why intervals", "why steady effort"]) ||
           (q.contains("why") && (q.contains("label") || q.contains("classif"))) {
            return .classificationExplanation
        }

        if any(["best split", "worst split", "fastest split", "slowest split", "which split", "each interval", "performance evaluation for each", "split was it", "fastest segment", "slowest segment", "granularity", "specifics"]) && !q.contains("focus") {
            return .splitPerformance
        }

        if any(["what day is it", "what day is today", "what day is tomorrow", "what day of the week", "what is today", "what is tomorrow", "what day was yesterday", "what date is it", "what is today's date", "which day is today", "which day is tomorrow"]) {
            let target: String
            if q.contains("tomorrow") {
                target = "tomorrow"
            } else if q.contains("yesterday") || q.contains("was") {
                target = "yesterday"
            } else {
                target = "today"
            }
            return .currentDay(target: target)
        }

        // Technique, pacing strategy, and focus questions are coaching queries, even when they mention a day or distance.
        let asksWhatToFocusOn = any([
            "what should i focus on", "what to focus on", "what do i focus on",
            "what should my focus be", "what can i focus on", "what to keep in mind",
            "what should i keep in mind", "how should i pace", "pacing strategy"
        ])
        if asksWhatToFocusOn || any(["tip", "cue", "drill", "technique", "form", "improve"]) {
            return .general
        }

        let hasDayReference = q.contains("tomorrow") || any(["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"])
        let isDayRedirection = any(["i'm focused on", "im focused on", "i am focused on", "focusing on", "worry about", "care about", "only care", "what about", "let's focus on", "lets focus on"])
        if hasDayReference && (isDayRedirection || (q.contains("focus on") && !q.contains("what"))) {
            let day = parseTimeframe(q)
            return .focusDay(day: day == "today" ? "tomorrow" : day)
        }

        if let activity = parseCrossTraining(q) {
            return .crossTraining(activity: activity)
        }
        if any(["strong base", "built a base", "aerobic base", "base fitness", "shift gears", "5k and 10k", "5k or 10k", "5k training", "10k training", "half marathon training", "marathon training", "ready for a 5k", "ready for a 10k", "ready for 5k", "ready for 10k", "transition to 5k", "transition to 10k"]) {
            return .baseFitness
        }
        if any(["rest day", "take a rest", "day off", "take today off", "sleep in", "do nothing today", "should i rest", "can i rest", "just rest"]) && !any(["can i run", "should i run", "run today", "go for a"]) {
            return .restDay
        }
        if any(["grade", "rate my", "score my", "evaluate my", "how did i do", "how was my run", "how did my run go"]) {
            return .grade
        }
        if any(["calorie", "kcal", "burn more", "burn enough", "lose weight", "weight loss"]) {
            return .calories
        }
        let mentionsHard = any(hardWords)
        if mentionsHard && any(["exhilarat", "i like", "i love", "love the", "enjoy", "addict", "the rush", " fun"]) {
            return .motivation
        }
        if q.contains("readiness") && any(["why", "adjust", "optimal", "drop", "lower", "changed"]) {
            return .readinessExplanation
        }
        if q.contains("focus") {
            return .general
        }
        let minutes = parseMinutes(q)
        let planning = any(["ready", "brief", "workout", "next run", "tomorrow", "plan", "can i do", "should i do", "session"])
        if mentionsHard && planning && !q.contains("how hard") {
            return .proposedWorkout(ProposedWorkout(isHard: true, reps: parseReps(q), minutes: minutes))
        }
        if q.contains("how hard") || (q.contains("push") && any(["how", "should"])) {
            return .pushIntensity
        }

        let dist = parseDistance(q)
        let timeframe = parseTimeframe(q)
        let asksAboutRunning = any(["run today", "can i run", "should i run", "go for a", "another run", "session today", "next run", "should i run next", "what should i run", "ready", "tomorrow", "zone 2", "zone2", "easy run", "am i good for", "good for a", "good for it"])
        let hypothetical = (minutes != nil || dist != nil) && any(["today", "tomorrow", "what if", "could i", "can i", "should i", "if i", "good for", "run"])
        if asksAboutRunning || hypothetical {
            return .runPlanning(
                RunPlanTarget(
                    minutes: minutes,
                    distanceKm: dist?.km,
                    distanceLabel: dist?.label,
                    timeframe: timeframe,
                    mentionsZone2: q.contains("zone 2") || q.contains("zone2")
                )
            )
        }
        return .general
    }

    static func parseDistance(_ q: String) -> (km: Double, label: String)? {
        let lower = q.lowercased()
        if lower.contains("half marathon") || lower.contains("half-marathon") {
            return (21.1, "half marathon")
        }
        if lower.contains("marathon") {
            return (42.2, "marathon")
        }
        if let match = matchFirst(in: lower, pattern: #"\b(\d+(?:\.\d+)?)\s*(?:k|km|kilometers?)\b"#) {
            let val = Double(match) ?? 10.0
            return (val, "\(match)k")
        }
        if let match = matchFirst(in: lower, pattern: #"\b(\d+(?:\.\d+)?)\s*(?:miles?|mi)\b"#) {
            let val = (Double(match) ?? 1.0) * 1.60934
            return (val, "\(match) miles")
        }
        return nil
    }

    static func parseTimeframe(_ q: String) -> String {
        let lower = q.lowercased()
        let days = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]

        // 1. Look for targeted day prepositions: "on sunday", "for sunday", "this sunday", "next sunday"
        for day in days {
            if lower.contains("on \(day)") || lower.contains("for \(day)") || lower.contains("this \(day)") || lower.contains("next \(day)") {
                return day.capitalized
            }
        }
        if lower.contains("on tomorrow") || lower.contains("for tomorrow") {
            return "tomorrow"
        }

        // 2. If a specific weekday is present, check if tomorrow/today were negated or mentioned alongside
        let mentionedDay = days.first { lower.contains($0) }?.capitalized
        let negatesOther = lower.contains("don't") || lower.contains("dont") || lower.contains("not") || lower.contains("skip") || lower.contains("rest") || lower.contains("instead")
        if let mentionedDay, negatesOther || !lower.contains("tomorrow") {
            return mentionedDay
        }

        // 3. Fallbacks
        if lower.contains("tomorrow") { return "tomorrow" }
        if let mentionedDay { return mentionedDay }
        return "today"
    }

    private static func matchFirst(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let group = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[group])
    }

    static func parseCrossTraining(_ q: String) -> String? {
        let lower = q.lowercased()
        if lower.contains("bike") || lower.contains("cycling") || lower.contains("cycle") || lower.contains("spin") {
            return "bike ride"
        }
        if lower.contains("swim") {
            return "swim"
        }
        if lower.contains("elliptical") {
            return "elliptical session"
        }
        if lower.contains("rowing") || lower.contains("rower") {
            return "rowing session"
        }
        if (lower.contains("walk") || lower.contains("walking") || lower.contains("hike")) &&
            (lower.contains("today") || lower.contains("tomorrow") || lower.contains("instead") || lower.contains("just walk") || lower.contains("go for a walk")) {
            return "walk"
        }
        if lower.contains("cross train") || lower.contains("cross-train") || lower.contains("crosstrain") {
            return "cross-training session"
        }
        return nil
    }

    /// Largest explicit session length in the message ("30mins", "45 min", "an hour").
    static func parseMinutes(_ q: String) -> Int? {
        var values = matches(in: q, pattern: #"(\d+)\s*(?:minutes|minute|mins|min)\b"#)
        if q.contains("an hour") || q.contains("1 hour") || q.contains("one hour") {
            values.append(60)
        }
        return values.max()
    }

    /// Rep count such as "11 hard speed pushes", "6x", "8 reps".
    static func parseReps(_ q: String) -> Int? {
        matches(in: q, pattern: #"(\d+)\s*(?:x\b|×|hard|speed|push|rep|interval|sprint|hill)"#).first
    }

    private static func matches(in text: String, pattern: String) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let group = Range(match.range(at: 1), in: text) else { return nil }
            return Int(text[group])
        }
    }
}

/// User's requested session parameters (e.g. "45 mins today", "10k tomorrow").
struct RunPlanTarget: Equatable, Sendable {
    let minutes: Int?
    let distanceKm: Double?
    let distanceLabel: String?
    let timeframe: String
    let mentionsZone2: Bool
}

/// A workout the runner describes and asks about ("11 hard speed pushes, 30 mins").
struct ProposedWorkout: Equatable, Sendable {
    let isHard: Bool
    let reps: Int?
    let minutes: Int?

    var summary: String {
        switch (reps, minutes) {
        case let (reps?, minutes?): return "\(reps)-rep, \(minutes)-minute speed session"
        case let (reps?, nil): return "\(reps)-rep speed session"
        case let (nil, minutes?): return "\(minutes)-minute hard session"
        default: return "hard session"
        }
    }
}

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

    /// Evaluates whether the athlete's recovery clock will have cleared for a given day or timeframe.
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

    /// Easy-run duration band (minutes) while still recovering; `nil` once recovered.
    var easyCap: ClosedRange<Int>? {
        guard !readyForHard else { return nil }
        guard let hours = hoursSinceLastHard else { return 20...30 }
        return hours < 24 ? 20...30 : 30...40
    }

    var earliestHardPhrase: String {
        guard let date = earliestHardDate else { return "now" }
        return Self.futurePhrase(for: date, relativeTo: now)
    }

    // MARK: Phrasing (en_US_POSIX per project rules)

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
    let paceDeltaVsBaseline: Double?   // positive = faster than 30-day average (s/km)
    let hrDeltaVsBaseline: Double?     // positive = higher than 30-day average (BPM)
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

/// Detects numbers in a model reply that appear nowhere in the grounding sources.
enum AnalystGrounding {
    static func numbers(in text: String) -> Set<Int> {
        guard let regex = try? NSRegularExpression(pattern: #"\d+"#) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return Set(regex.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).flatMap { Int(text[$0]) }
        })
    }

    static func hasUngroundedNumbers(_ reply: String, sources: [String]) -> Bool {
        let allowed = sources.reduce(into: Set<Int>(0...20)) { $0.formUnion(numbers(in: $1)) }
        return !numbers(in: reply).isSubset(of: allowed)
    }
}
