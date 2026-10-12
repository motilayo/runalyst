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

        // Clean, data-grounded fallback response
        let fallbackResponse = generateDeterministicResponse(for: trimmed)
        messages.append(AnalystChatMessage(sender: .analyst, text: fallbackResponse))
    }

    // MARK: - FoundationModels

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func generateFoundationModelResponse(for userQuestion: String) async throws -> String {
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        let dataSheet = telemetryLines().joined(separator: "\n")

        let systemInstructions = """
        WORKOUT DATA SHEET:
        \(dataSheet)

        You are my personal running coach. You have access to my workout data sheet above.
        Speak directly to me ("you" / "your") like an experienced, objective running coach in a conversation—clear, direct, and data-backed, with no generic motivational platitudes and no lecturing. Never refer to me as "the runner" or in the third person.

        How to answer:
        - Answer what I ask directly, using the data sheet to back up your points.
        - When I ask about splits or intervals, cite and evaluate the actual reps, pacing, and cadence stability.
        - When I ask what a concept means (like threshold), explain the concept simply, then connect it to how I ran.
        - When I ask for insights or what to improve, give me the coaching story: what happened, why my body reacted that way, and what to adjust next time.
        - Keep your replies concise and conversational (typically 2 to 3 short paragraphs). Use clean rich text formatting with bullet points (•) and bold text (**) for key metrics. Do not format your answers as formal academic reports with markdown header hashes (###) or observation checklists.
        - Only discuss future training, recovery timelines, or readiness when I specifically ask about them. Do not append unasked readiness sign-offs or disclaimers about unrecorded sensors.
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

        let rawConf = runRecord.classificationConfidence ?? 0.85
        let confPct = rawConf > 1.0 ? Int(rawConf.rounded()) : Int((rawConf * 100).rounded())

        var lines = [
            "Workout Date: \(workoutDay), \(workoutDateStr) (\(pastPhrase), \(RecoveryTimeline.durationPhrase(hours: hoursAgo)) ago)",
            "Today's Date: \(todayWeekday), \(todayDateStr) (\(isToday ? "This workout was logged today" : "No workouts logged today; this workout is from \(pastPhrase)"))",
            "Environment: \(env) (Sensor: \(runRecord.dataSourceRaw?.capitalized ?? "Wrist accelerometer"))",
            "Classification: \(type) (confidence: \(confPct)%)"
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
        }

        if let stride = runRecord.workingAvgStrideLength {
            lines.append("Stride Length: \(String(format: "%.2f", stride)) m")
        }

        let signature = runSignature ?? runRecord.signature

        // Kilometer Splits Breakdown
        var splits = signature?.splits ?? []
        if splits.isEmpty, let segments = signature?.phaseSegments, !segments.isEmpty {
            splits = Self.synthesizeSplitsFromSegments(segments)
        }
        if !splits.isEmpty {
            lines.append("Kilometer Splits (\(splits.count) splits):")
            let fastestSplit = splits.min(by: { $0.paceSecondsPerKm < $1.paceSecondsPerKm })
            let slowestSplit = splits.max(by: { $0.paceSecondsPerKm < $1.paceSecondsPerKm })
            for split in splits {
                let splitPace = PaceFormatter.formatPace(secondsPerKilometer: split.paceSecondsPerKm)
                var tags: [String] = []
                if split.index == fastestSplit?.index { tags.append("FASTEST") }
                if split.index == slowestSplit?.index { tags.append("SLOWEST") }
                let tagStr = tags.isEmpty ? "" : " [\(tags.joined(separator: ", "))]"
                lines.append("- km \(split.index): \(splitPace), \(Int(split.avgCadence)) SPM, \(Int(split.avgHeartRate)) BPM\(tagStr)")
            }
            if let f = fastestSplit {
                lines.append("Fastest split: km \(f.index) at \(PaceFormatter.formatPace(secondsPerKilometer: f.paceSecondsPerKm))")
            }
            if let s = slowestSplit {
                lines.append("Slowest split: km \(s.index) at \(PaceFormatter.formatPace(secondsPerKilometer: s.paceSecondsPerKm))")
            }
        }

        // Segment Breakdown (Interval Reps / Surges)
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

        lines.append("[FUTURE TRAINING & RECOVERY - Reference ONLY if asked about next run, readiness, recovery, or drills]:")
        let readiness = currentReadiness
        var readinessLine = "Readiness: \(readiness.state.rawValue)"
        if let acwr = readiness.acwr {
            readinessLine += ", ACWR \(String(format: "%.2f", acwr))"
        }
        if let triggers = triggerPhrase(readiness.triggers) {
            readinessLine += ", recovery flags: \(triggers)"
        }
        lines.append("- \(readinessLine)")

        let timeline = recoveryTimeline
        if timeline.readyForHard {
            lines.append("- Recovery Timeline: Cleared for hard efforts")
        } else if let cap = timeline.easyCap {
            lines.append("- Recovery Timeline: Hard efforts cleared \(timeline.earliestHardPhrase). Easy run cap: \(cap.lowerBound)–\(cap.upperBound) min")
        }

        if let drill = runRecord.insight?.drillRecommendations?.first ?? runRecord.insight?.drillRecommendation {
            lines.append("- Suggested Drill: \(drill.drillTitle)")
        }
        return lines
    }

    // MARK: - Deterministic Fallback Response

    private func generateDeterministicResponse(for userQuestion: String) -> String {
        let q = userQuestion.lowercased().replacingOccurrences(of: "’", with: "'")

        // 1. Calendar / Day-of-week questions
        if q.contains("what day is") || q.contains("what is today's date") || q.contains("what is today") || q.contains("what is tomorrow") || q.contains("what date is") {
            return dayQueryAnswer(for: q)
        }

        // 2. Runner clarification about not running today or yesterday
        if q.contains("didn't run") || q.contains("didnt run") || q.contains("haven't run") || q.contains("havent run") || q.contains("didn't do an easy run") || q.contains("didnt do an easy run") {
            return didNotRunAnswer(for: q)
        }

        // 3. Classification explanations ("why mixed effort", "why intervals", "why steady")
        if (q.contains("why") && (q.contains("label") || q.contains("classif"))) || q.contains("why 'mixed effort'") || q.contains("why mixed effort") {
            return classificationExplanationAnswer()
        }

        // 4. Grade / rate my performance (prioritized over general split stats)
        if q.contains("grade") || q.contains("rate my") || q.contains("score my") || q.contains("evaluate my") || q.contains("how did i do") || q.contains("how did my run go") {
            return gradeAnswer(for: q)
        }

        // 5. Splits, intervals, and best/worst segments
        if q.contains("split") || q.contains("interval") || q.contains("rep") || q.contains("segment") || q.contains("fastest") || q.contains("slowest") || q.contains("best") || q.contains("worst") {
            return splitPerformanceAnswer()
        }

        // 6. Unrecorded biometrics (vertical oscillation, stride length)
        if q.contains("vertical") || q.contains("oscillation") || q.contains("bounce") {
            return verticalOscillationAnswer()
        }
        if q.contains("stride") || q.contains("overstride") {
            return strideLengthAnswer()
        }

        // 7. Readiness adjustment explanation
        if q.contains("readiness") && (q.contains("why") || q.contains("adjust") || q.contains("optimal") || q.contains("lower") || q.contains("drop")) {
            return readinessExplanationAnswer()
        }

        // 8. Calorie inquiry
        if q.contains("calorie") || q.contains("kcal") || q.contains("burn") {
            return caloriesAnswer(timeline: recoveryTimeline)
        }

        // 9. Motivation / adrenaline / love pushing hard
        if (q.contains("push") || q.contains("hard")) && (q.contains("like") || q.contains("love") || q.contains("enjoy") || q.contains("exhilarat")) {
            return motivationAnswer(timeline: recoveryTimeline)
        }

        // 10. Base fitness / 5k or 10k transition
        if q.contains("base") || (q.contains("5k") || q.contains("10k")) && (q.contains("ready") || q.contains("transition") || q.contains("shift gear") || q.contains("built")) {
            return baseFitnessAnswer()
        }

        // 11. Cross-training (bike, swim, elliptical, walk)
        if let activity = parseCrossTraining(q) {
            return crossTrainingAnswer(activity: activity, timeline: recoveryTimeline)
        }

        // 12. Rest day
        if (q.contains("rest day") || q.contains("day off") || q.contains("just rest") || q.contains("take a rest")) && !q.contains("can i run") {
            return restDayAnswer(timeline: recoveryTimeline)
        }

        // 13. How hard to push
        if q.contains("how hard") || (q.contains("push") && q.contains("should")) {
            return pushIntensityAnswer(timeline: recoveryTimeline)
        }

        // 14. Planning runs / Can I run / Focus day
        let timeframe = parseTimeframe(q)
        let dist = parseDistance(q)
        let mins = parseMinutes(q)

        let asksWhatToFocusOn = q.contains("focus on") || q.contains("focused on") || q.contains("focusing on") || q.contains("what should i focus") || q.contains("what to focus") || q.contains("keep in mind") || q.contains("pacing strategy")

        if asksWhatToFocusOn {
            return focusStrategyAnswer(timeframe: timeframe, dist: dist)
        }

        let planningKeywords = [
            "can i run", "should i run", "good for", "run tomorrow", "run today",
            "go for a", "another run", "plan", "ready for", "could i", "how soon",
            "attempt", "what if", "zone 2", "zone2", "session today"
        ]
        if planningKeywords.contains(where: { q.contains($0) }) || dist != nil || mins != nil {
            let target = RunPlanTarget(minutes: mins, distanceKm: dist?.km, distanceLabel: dist?.label, timeframe: timeframe, mentionsZone2: q.contains("zone 2") || q.contains("zone2"))
            return runPlanningAnswer(for: target, timeline: recoveryTimeline)
        }

        // 15. Form / technique / conceptual / cues
        return generalCoachingAnswer(for: q)
    }

    // MARK: - Data-Driven Answer Handlers

    private func dayQueryAnswer(for lower: String) -> String {
        let cal = Calendar.current
        let now = Date()
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale(identifier: "en_US_POSIX")
        weekdayFormatter.dateFormat = "EEEE"

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "MMMM d"

        if lower.contains("tomorrow") {
            let tomorrow = cal.date(byAdding: .day, value: 1, to: now) ?? now
            let dayName = weekdayFormatter.string(from: tomorrow)
            let dateStr = dateFormatter.string(from: tomorrow)
            return "Tomorrow is \(dayName), \(dateStr)."
        } else if lower.contains("yesterday") || lower.contains("was") {
            let yesterday = cal.date(byAdding: .day, value: -1, to: now) ?? now
            let dayName = weekdayFormatter.string(from: yesterday)
            let dateStr = dateFormatter.string(from: yesterday)
            return "Yesterday was \(dayName), \(dateStr)."
        } else {
            let dayName = weekdayFormatter.string(from: now)
            let dateStr = dateFormatter.string(from: now)
            return "Today is \(dayName), \(dateStr)."
        }
    }

    private func didNotRunAnswer(for lower: String) -> String {
        let timeline = recoveryTimeline
        let when = RecoveryTimeline.pastPhrase(for: runRecord.date, relativeTo: timeline.now)
        let dayName = RecoveryTimeline.weekday(runRecord.date)
        let timeframe = lower.contains("yesterday") ? "yesterday" : "today"
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
        var splits = signature?.splits ?? []
        if splits.isEmpty, let segments = signature?.phaseSegments, !segments.isEmpty {
            splits = Self.synthesizeSplitsFromSegments(segments)
        }

        if !splits.isEmpty {
            guard let fastest = splits.min(by: { $0.paceSecondsPerKm < $1.paceSecondsPerKm }),
                  let slowest = splits.max(by: { $0.paceSecondsPerKm < $1.paceSecondsPerKm }) else {
                let pace = PaceFormatter.formatPace(secondsPerKilometer: runRecord.workingAvgPace)
                return "Your pace averaged \(pace) throughout this workout with steady execution."
            }

            var startSec: Double = 0
            for s in splits.prefix(while: { $0.index < fastest.index }) {
                startSec += s.durationSeconds
            }
            let fStart = Int(startSec / 60)
            let fEnd = Int((startSec + fastest.durationSeconds) / 60)

            var slowStartSec: Double = 0
            for s in splits.prefix(while: { $0.index < slowest.index }) {
                slowStartSec += s.durationSeconds
            }
            let sStart = Int(slowStartSec / 60)
            let sEnd = Int((slowStartSec + slowest.durationSeconds) / 60)

            let fastestPace = PaceFormatter.formatPace(secondsPerKilometer: fastest.paceSecondsPerKm)
            let slowestPace = PaceFormatter.formatPace(secondsPerKilometer: slowest.paceSecondsPerKm)

            if splits.count >= 2 {
                return "Your fastest split was km \(fastest.index) (min \(fStart)–\(fEnd)) at \(fastestPace) with \(Int(fastest.avgCadence)) SPM cadence. Your slowest split was km \(slowest.index) (min \(sStart)–\(sEnd)) at \(slowestPace) with \(Int(slowest.avgHeartRate)) BPM heart rate."
            } else {
                return "Your split was km 1 (min \(fStart)–\(fEnd)) at \(fastestPace) with \(Int(fastest.avgCadence)) SPM."
            }
        }

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

    private func verticalOscillationAnswer() -> String {
        if let osc = runRecord.workingAvgVerticalOscillation {
            return "Your vertical bounce was \(String(format: "%.1f", osc)) cm. Keeping that below 9 cm ensures your energy propels you forward rather than bounding upward into the air."
        } else {
            return "Vertical oscillation wasn't recorded for this workout because it was an indoor treadmill run. Apple Watch measures vertical bounce outdoors or when paired with an authentic footpod."
        }
    }

    private func strideLengthAnswer() -> String {
        if let stride = runRecord.workingAvgStrideLength {
            return "Your average stride length was \(String(format: "%.2f", stride)) m. Focus on landing directly beneath your hips to keep impact light."
        } else {
            return "Stride length wasn't recorded for this workout because it was an indoor treadmill run without a footpod. Focus on landing your feet directly under your hips rather than reaching forward."
        }
    }

    private func readinessExplanationAnswer() -> String {
        let readiness = currentReadiness
        let ratio = readiness.acwr.map { "ACWR \(String(format: "%.2f", $0))" } ?? "not enough history yet for a reliable ACWR"
        let reason = triggerPhrase(readiness.triggers) ?? "the acute fatigue from your most recent hard workout"
        return "Your 4-week training load looks balanced (\(ratio)), but your readiness was adjusted because of \(reason). Training load measures how this week compares with the last month, while readiness looks at immediate recovery—so a hard session in the last couple of days lowers readiness even when your monthly balance is fine."
    }

    private func gradeAnswer(for userQuestion: String = "") -> String {
        let q = userQuestion.lowercased()
        let signature = runSignature ?? runRecord.signature

        if q.contains("split") {
            var splits = signature?.splits ?? []
            if splits.isEmpty, let segments = signature?.phaseSegments, !segments.isEmpty {
                splits = Self.synthesizeSplitsFromSegments(segments)
            }
            if !splits.isEmpty {
                return splitBySplitGrade(splits: splits)
            }
        }

        if (q.contains("rep") || q.contains("interval")) && !(signature?.phaseSegments ?? []).isEmpty {
            return repByRepGrade(segments: signature?.phaseSegments ?? [])
        }

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

    private func splitBySplitGrade(splits: [RunSplit]) -> String {
        guard !splits.isEmpty else { return gradeAnswer() }
        let workingPace = runRecord.workingAvgPace
        let fastest = splits.min(by: { $0.paceSecondsPerKm < $1.paceSecondsPerKm })
        let slowest = splits.max(by: { $0.paceSecondsPerKm < $1.paceSecondsPerKm })

        var breakdown: [String] = []
        for s in splits.prefix(8) {
            let paceStr = PaceFormatter.formatPace(secondsPerKilometer: s.paceSecondsPerKm)
            let paceDiff = workingPace - s.paceSecondsPerKm
            let letter: String
            let note: String

            if s.paceSecondsPerKm == fastest?.paceSecondsPerKm {
                letter = "A"
                note = "fastest split with sharp pace control"
            } else if s.avgCadence < 150 {
                letter = "B-"
                note = "cadence dipped to \(Int(s.avgCadence)) SPM below floor"
            } else if paceDiff >= 5 {
                letter = "A-"
                note = "strong sustained surge"
            } else if s.paceSecondsPerKm == slowest?.paceSecondsPerKm {
                letter = "B"
                note = "slowest split, pacing eased back"
            } else {
                letter = "A-"
                note = "even metronomic pacing and steady turnover"
            }
            breakdown.append("• km \(s.index) (\(paceStr), \(Int(s.avgCadence)) SPM, \(Int(s.avgHeartRate)) BPM): \(letter) — \(note)")
        }

        var result = "Here is a breakdown of your splits:\n" + breakdown.joined(separator: "\n")
        if let f = fastest, let s = slowest, splits.count >= 2 {
            let fPace = PaceFormatter.formatPace(secondsPerKilometer: f.paceSecondsPerKm)
            let sPace = PaceFormatter.formatPace(secondsPerKilometer: s.paceSecondsPerKm)
            result += "\n\nOverall split execution: A-. Fastest was km \(f.index) at \(fPace); slowest was km \(s.index) at \(sPace). Pacing discipline was disciplined across the session."
        }
        return result
    }

    private func repByRepGrade(segments: [PhaseSegment]) -> String {
        let workReps = segments.filter { $0.kind == "work" && $0.avgPace > 0 }
        guard !workReps.isEmpty else { return gradeAnswer() }
        let fastest = workReps.min(by: { $0.avgPace < $1.avgPace })
        let slowest = workReps.max(by: { $0.avgPace < $1.avgPace })

        var breakdown: [String] = []
        for (idx, rep) in workReps.prefix(6).enumerated() {
            let sMin = Int(rep.startSeconds / 60)
            let sSec = Int(rep.startSeconds.truncatingRemainder(dividingBy: 60))
            let eMin = Int(rep.endSeconds / 60)
            let eSec = Int(rep.endSeconds.truncatingRemainder(dividingBy: 60))
            let timeStr = String(format: "%d:%02d–%d:%02d", sMin, sSec, eMin, eSec)
            let paceStr = PaceFormatter.formatPace(secondsPerKilometer: rep.avgPace)

            let letter: String
            let note: String
            if rep.id == fastest?.id {
                letter = "A"
                note = "fastest rep, powerful pace pickup"
            } else if rep.avgCadence < 150 {
                letter = "B-"
                note = "cadence dipped to \(Int(rep.avgCadence)) SPM"
            } else if rep.id == slowest?.id {
                letter = "B"
                note = "slowest rep, fatigue showed in pace"
            } else {
                letter = "A-"
                note = "controlled effort with steady cadence"
            }
            breakdown.append("• Work Rep \(idx + 1) (\(timeStr), \(paceStr), \(Int(rep.avgCadence)) SPM): \(letter) — \(note)")
        }

        var result = "Here is how your work intervals graded:\n" + breakdown.joined(separator: "\n")
        if let f = fastest, workReps.count >= 2 {
            let idx = (workReps.firstIndex(where: { $0.id == f.id }) ?? 0) + 1
            result += "\n\nOverall interval execution: A-. Strongest surge was Rep \(idx) at \(PaceFormatter.formatPace(secondsPerKilometer: f.avgPace))."
        }
        return result
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

    private func baseFitnessAnswer() -> String {
        let cad = Int(runRecord.workingAvgCadence)
        if cad >= 150 {
            return "Yes, you have built a solid base to begin 5k and 10k training. Your cadence turnover of \(cad) SPM and steady pacing show good aerobic efficiency. As you shift gears, introduce faster intervals gradually—about one workout a week—while keeping the majority of your weekly volume easy and conversational so your body absorbs the work."
        } else {
            return "You're building solid endurance, but quickening your foot turnover from \(cad) SPM will strengthen your base before shifting gears to 5k and 10k workouts. Bringing your cadence up toward a lighter step rhythm will make faster intervals feel easier and protect your legs as training demands increase."
        }
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

    private func pushIntensityAnswer(timeline: RecoveryTimeline) -> String {
        if timeline.readyForHard {
            return "You're recovered, so a controlled hard effort is fine today. Aim for comfortably hard rather than all-out, focusing on a crisp turnover so the effort comes from rhythm, not overstriding."
        }
        return "Keep your effort very light today—do not push hard. Your body needs active recovery, so stay conversational in Zone 2 or below until \(timeline.earliestHardPhrase)."
    }

    private func focusStrategyAnswer(timeframe: String, dist: (km: Double, label: String)?) -> String {
        let isCleared = recoveryTimeline.isCleared(for: timeframe)

        if let dist = dist {
            if !isCleared && timeframe != "today" {
                let cap = recoveryTimeline.easyCap?.upperBound ?? 40
                return "A \(dist.label) \(timeframe) would conflict with your recovery clock after your recent hard session. If you do run \(timeframe), focus strictly on keeping it an easy, conversational recovery jog under \(cap) minutes, and save the \(dist.label) for \(recoveryTimeline.earliestHardPhrase)."
            } else if dist.label.contains("10k") || (dist.km >= 9.0 && dist.km <= 11.0) {
                let dayContext = timeframe != "today" ? "For your 10k on \(timeframe), " : "For a 10k, "
                return "\(dayContext)focus on settling into a relaxed, controlled rhythm through the first half rather than chasing pace early. Keep your cadence light and snappy, and let the effort build naturally so you finish strong."
            } else if dist.label.contains("5k") || (dist.km >= 4.5 && dist.km <= 6.0) {
                let dayContext = timeframe != "today" ? "For your 5k on \(timeframe), " : "For a 5k, "
                return "\(dayContext)focus on finding a crisp, light turnover right from the start without overstriding, keeping your shoulders relaxed and driving your elbows straight back to maintain momentum."
            }
        }

        if timeframe != "today" {
            if isCleared {
                return "For \(timeframe), your recovery clock is cleared and you're good to go. A normal easy or steady run fits well, focusing on a relaxed rhythm and steady pacing."
            } else {
                let cap = recoveryTimeline.easyCap?.upperBound ?? 40
                return "For \(timeframe), keep your effort light: an easy jog under \(cap) minutes in Zone 2 or complete rest to let your body repair."
            }
        }

        return "Focus on maintaining a crisp, light foot turnover landing softly under your hips, keeping your upper body relaxed and breathing rhythmically."
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

    private func generalCoachingAnswer(for q: String) -> String {
        let cad = Int(runRecord.workingAvgCadence)
        let hr = Int(runRecord.workingAvgHeartRate)
        let pace = PaceFormatter.formatPace(secondsPerKilometer: runRecord.workingAvgPace)
        let isIndoor = runRecord.isIndoor ?? false
        let signature = runSignature ?? runRecord.signature
        let workSegments = signature?.phaseSegments.filter { $0.kind == "work" } ?? []
        let recoverySegments = signature?.phaseSegments.filter { $0.kind == "recovery" } ?? []

        // Arm Drive / Arm Swing
        if q.contains("arm drive") || q.contains("arm swing") || (q.contains("arm") && (q.contains("help") || q.contains("do") || q.contains("why") || q.contains("how"))) {
            return "Your arms act like a metronome for your legs—your feet naturally follow the tempo of your arm swing. Keeping your elbows bent around 90 degrees and driving them straight back helps you turn your feet over quicker without straining your legs, while preventing you from overreaching your stride."
        }

        // Breathing
        if q.contains("breath") || q.contains("breathe") {
            return "Rhythmic breathing helps keep your heart rate calm and spreads landing impact across both legs. Try inhaling for 3 footstrikes and exhaling for 2—this odd-count pattern prevents you from always exhaling on the same foot strike, keeping your rhythm steady."
        }

        // Posture
        if q.contains("posture") || q.contains("tall") || q.contains("head") || q.contains("shoulder") {
            return "Good running posture starts from the crown of your head: run tall with an open chest, keep your shoulders down and relaxed, and look 10 to 15 meters ahead rather than down at your feet. This opens up your airways and takes unnecessary tension out of your neck."
        }

        // Performance: Degradation / Fading
        if q.contains("degrad") || q.contains("fade") || q.contains("tiring") || q.contains("tired") || q.contains("end of") || q.contains("late") || q.contains("later") {
            if !workSegments.isEmpty {
                return "Your interval pacing held steady across your work reps without significant drop-off. Your heart rate climbed slightly during the later intervals, which is natural cardiac drift as fatigue builds—focusing on taking lighter, quicker steps late in the workout helps take stress off tired legs."
            } else {
                return "Your pace stayed consistent right through the later miles. Your heart rate rose slightly near the finish, which is normal aerobic fatigue, but you maintained your form and avoided any sudden slowdown."
            }
        }

        // Weak point / Least Improved
        if q.contains("least") || q.contains("weak") || q.contains("struggle") || q.contains("hardest") || q.contains("room to grow") {
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

        // Most Improved / Strongest / Biggest Win
        if q.contains("most improve") || q.contains("biggest win") || q.contains("best part") || q.contains("strongest") || (q.contains("most") && q.contains("improve")) {
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

        // Heart Rate / Effort / Intensity
        if q.contains("effort") || q.contains("heart rate") || q.contains("hr") || q.contains("intensity") || q.contains("hard") {
            let envDetail = isIndoor
                ? " On the treadmill, where the belt enforces your speed, this shows steady cardiovascular control even without outdoor airflow."
                : " Your pacing was well-matched to your aerobic engine."
            return "Your effort was smooth and controlled.\(envDetail) You kept your intensity in a productive training zone without straining your engine."
        }

        // Next Run / Tip / Focus / Technique / Form
        if q.contains("tip") || q.contains("cue") || q.contains("focus") || q.contains("next run") || q.contains("improve") || q.contains("technique") || q.contains("form") {
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

        // Cadence / Turnover specifically
        if q.contains("cadence") || q.contains("turnover") || q.contains("rhythm") || q.contains("spm") {
            let signature = runSignature ?? runRecord.signature
            var splits = signature?.splits ?? []
            if splits.isEmpty, let segments = signature?.phaseSegments, !segments.isEmpty {
                splits = Self.synthesizeSplitsFromSegments(segments)
            }
            let workSegments = signature?.phaseSegments.filter { $0.kind == "work" && $0.avgPace > 0 } ?? []

            if let slowestSplit = splits.max(by: { $0.paceSecondsPerKm < $1.paceSecondsPerKm }),
               let fastestSplit = splits.min(by: { $0.paceSecondsPerKm < $1.paceSecondsPerKm }),
               splits.count >= 2,
               fastestSplit.avgCadence - slowestSplit.avgCadence >= 8 {
                let fCad = Int(fastestSplit.avgCadence)
                let sCad = Int(slowestSplit.avgCadence)
                return "Your rhythm was sharp during your faster work—holding around \(fCad) SPM on km \(fastestSplit.index). However, on km \(slowestSplit.index), your cadence dropped to \(sCad) SPM as fatigue built. That drop shows your stride lengthened and your feet spent more time on the ground. In your next session, focus on keeping that turnover light and quick even when your legs get tired."
            }

            if !workSegments.isEmpty {
                let workCad = Int(workSegments.map(\.avgCadence).reduce(0, +) / Double(workSegments.count))
                return "Your cadence averaged \(cad) SPM, with your work intervals holding a steady \(workCad) SPM. Maintaining that crisp rhythm during faster surges protects your joints and keeps your momentum fluid."
            }

            if cad >= 168 {
                return "Your cadence averaged a sharp \(cad) SPM. That quick turnover keeps your feet landing softly under your hips, protecting your knees and keeping your stride light."
            } else if cad >= 150 {
                return "Your cadence averaged \(cad) SPM—a solid baseline above the 150 floor. Building that rhythm toward 165–170 SPM over time will shorten your ground contact and make your stride feel lighter."
            } else {
                return "Your cadence averaged \(cad) SPM, which is below the 150 floor. Taking shorter, quicker steps will reduce ground impact forces and protect your joints."
            }
        }

        // Pace / Speed specifically
        if q.contains("pace") || q.contains("speed") || q.contains("fast") || q.contains("slow") {
            if isIndoor {
                return "You held a steady pace of \(pace) on the treadmill. Since the treadmill belt sets your speed, your true effort is best reflected in your heart rate and cadence turnover."
            } else {
                return "Your pace averaged \(pace), showing consistent, well-managed speed across the session."
            }
        }

        return "You held a solid, steady rhythm throughout this run. Focusing on quick, relaxed steps beneath your hips will keep your running smooth and injury-free."
    }

    // MARK: - Parsing Helpers

    private func parseDistance(_ text: String) -> (km: Double, label: String)? {
        let lower = text.lowercased()
        if lower.contains("half marathon") || lower.contains("half-marathon") {
            return (21.1, "half marathon")
        }
        if lower.contains("marathon") {
            return (42.2, "marathon")
        }
        if let match = matchRegex(in: lower, pattern: #"\b(\d+(?:\.\d+)?)\s*(?:k|km|kilometers?)\b"#) {
            let val = Double(match) ?? 10.0
            return (val, "\(match)k")
        }
        if let match = matchRegex(in: lower, pattern: #"\b(\d+(?:\.\d+)?)\s*(?:miles?|mi)\b"#) {
            let val = (Double(match) ?? 1.0) * 1.60934
            return (val, "\(match) miles")
        }
        return nil
    }

    private func parseTimeframe(_ text: String) -> String {
        let lower = text.lowercased()
        let days = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]

        for day in days {
            if lower.contains("on \(day)") || lower.contains("for \(day)") || lower.contains("this \(day)") || lower.contains("next \(day)") || lower.contains("focused on \(day)") || lower.contains("tomorrow, \(day)") {
                return day.capitalized
            }
        }

        let affirmativeDays = days.filter { day in
            guard lower.contains(day) else { return false }
            let isNegated = lower.contains("don't worry about \(day)")
                || lower.contains("dont worry about \(day)")
                || lower.contains("not \(day)")
                || lower.contains("skip \(day)")
                || lower.contains("without \(day)")
            return !isNegated
        }

        if let affirmativeDay = affirmativeDays.last?.capitalized {
            return affirmativeDay
        }

        if lower.contains("tomorrow") { return "tomorrow" }
        return "today"
    }

    private func parseCrossTraining(_ text: String) -> String? {
        let lower = text.lowercased()
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

    private func parseMinutes(_ text: String) -> Int? {
        let lower = text.lowercased()
        if lower.contains("an hour") || lower.contains("1 hour") || lower.contains("one hour") {
            return 60
        }
        if let match = matchRegex(in: lower, pattern: #"\b(\d+)\s*(?:minutes|minute|mins|min)\b"#),
           let val = Int(match) {
            return val
        }
        return nil
    }

    private func matchRegex(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let group = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[group])
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
}

// MARK: - Supporting Models

/// User's requested session parameters (e.g. "45 mins today", "10k tomorrow").
struct RunPlanTarget: Equatable, Sendable {
    let minutes: Int?
    let distanceKm: Double?
    let distanceLabel: String?
    let timeframe: String
    let mentionsZone2: Bool
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
