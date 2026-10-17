import Foundation
import SwiftUI
@preconcurrency import WorkoutKit
import HealthKit

#if canImport(WorkoutKit)
@available(iOS 17.0, macCatalyst 18.0, macOS 15.0, watchOS 10.0, *)
extension WorkoutScheduler.AuthorizationState: @retroactive @unchecked Sendable {}
#endif

/// The bridge between Runalyst's CoreML/AI outputs and Apple's WorkoutKit.
/// Translates `DrillPrescriptionDTO` into a native `WorkoutPlan`.
@available(iOS 17.0, *)
@MainActor
final class WorkoutBridge {

    nonisolated private static let drillIntentsKey = "recentDrillIntents"

    nonisolated public static func clearIntents() {
        UserDefaults.standard.removeObject(forKey: drillIntentsKey)
    }

    nonisolated public static func persistIntents(_ intents: [ScheduledDrillIntent]) {
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600) // Retain 30 days of intents
        let filtered = intents.filter { $0.scheduledDate >= cutoff }
        if let data = try? JSONEncoder().encode(filtered) {
            UserDefaults.standard.set(data, forKey: drillIntentsKey)
        }
    }

    nonisolated public static func markIntentMatched(workoutID: UUID, drillTitle: String, workoutDate: Date) {
        var intents = recentIntents()
        if let index = intents.firstIndex(where: {
            $0.drillTitle == drillTitle &&
            ($0.matchedWorkoutID == nil || $0.matchedWorkoutID == workoutID) &&
            abs(workoutDate.timeIntervalSince($0.scheduledDate)) <= 48 * 3600
        }) {
            intents[index].matchedWorkoutID = workoutID
            persistIntents(intents)
        }
    }

    nonisolated public static func saveDrillIntent(_ intent: ScheduledDrillIntent) {
        var intents = recentIntents()
        // If updating an intent (like marking as matched), replace the old one
        if let index = intents.firstIndex(where: { $0.scheduledDate == intent.scheduledDate && $0.drillTitle == intent.drillTitle }) {
            intents[index] = intent
        } else {
            // Supersede any pending (unmatched) intents scheduled within the last 30 minutes.
            // A newly scheduled drill overrides any accidental previous drill taps.
            intents.removeAll { $0.matchedWorkoutID == nil && abs($0.scheduledDate.timeIntervalSince(intent.scheduledDate)) < 1800 }
            intents.append(intent)
        }
        persistIntents(intents)
    }

    nonisolated public static func recentIntents() -> [ScheduledDrillIntent] {
        guard let data = UserDefaults.standard.data(forKey: drillIntentsKey),
              let intents = try? JSONDecoder().decode([ScheduledDrillIntent].self, from: data) else {
            return []
        }
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600) // Retain 30 days of intents
        return intents.filter { $0.scheduledDate >= cutoff }
    }

    nonisolated public static func isGuidedOrThirdPartySession(workout: HKWorkout? = nil, metadata: [String: Any]? = nil) -> Bool {
        let meta = metadata ?? workout?.metadata
        if let meta = meta {
            if let isFitnessPlus = meta[HKMetadataKeyAppleFitnessPlusSession] as? Bool, isFitnessPlus {
                return true
            }
            if let isFitnessPlus = meta["HKAppleFitnessPlusSession"] as? Bool, isFitnessPlus {
                return true
            }
            if let brand = (meta[HKMetadataKeyWorkoutBrandName] as? String) ?? (meta["HKWorkoutBrandName"] as? String) {
                let lower = brand.lowercased()
                if lower.contains("fitness+") || lower.contains("apple fitness") || lower.contains("peloton") || lower.contains("nike") {
                    return true
                }
            }
            let thirdPartyKeywords = ["strava", "nike", "peloton", "garmin", "runkeeper", "zwift", "coros", "trainingpeaks", "fitness+"]
            for (key, val) in meta {
                let keyLower = key.lowercased()
                for kw in thirdPartyKeywords where keyLower.contains(kw) {
                    return true
                }
                if let strVal = val as? String {
                    let strLower = strVal.lowercased()
                    for kw in thirdPartyKeywords where strLower.contains(kw) {
                        return true
                    }
                }
            }
        }
        if let workout = workout {
            let sourceName = workout.sourceRevision.source.name.lowercased()
            let bundleId = workout.sourceRevision.source.bundleIdentifier.lowercased()
            let thirdPartyKeywords = ["strava", "nike", "peloton", "garmin", "runkeeper", "zwift", "coros", "trainingpeaks"]
            for kw in thirdPartyKeywords where sourceName.contains(kw) || bundleId.contains(kw) {
                return true
            }
        }
        return false
    }

    nonisolated private static func extractAllStrings(from dict: [String: Any]?) -> [String] {
        guard let dict = dict else { return [] }
        var result: [String] = []
        for (_, val) in dict {
            if let s = val as? String {
                result.append(s)
            } else if let arr = val as? [String] {
                result.append(contentsOf: arr)
            } else if let arrOfDict = val as? [[String: Any]] {
                for d in arrOfDict {
                    result.append(contentsOf: extractAllStrings(from: d))
                }
            } else if let subDict = val as? [String: Any] {
                result.append(contentsOf: extractAllStrings(from: subDict))
            }
        }
        return result
    }

    nonisolated public static func matchDrill(
        workout: HKWorkout,
        durationSeconds: Double
    ) -> ScheduledDrillIntent? {
        return matchDrill(
            workout: workout,
            durationSeconds: durationSeconds,
            buckets: [],
            baselineCadence: nil
        )
    }

    nonisolated public static func matchDrill(
        workout: HKWorkout,
        durationSeconds: Double,
        buckets: [BucketData] = [],
        baselineCadence: Int? = nil,
        zone4Threshold: Double = 161.5,
        zone2Threshold: Double = 142.0,
        zone1Threshold: Double = 125.0,
        customWorkout: CustomWorkout? = nil,
        zoneConfig: Any? = nil
    ) -> ScheduledDrillIntent? {
        guard !isGuidedOrThirdPartySession(workout: workout, metadata: workout.metadata) else {
            return nil
        }

        let workoutDate = workout.startDate
        var allMetadataStrings: [String] = []

        // Extract metadata strings recursively from workout
        allMetadataStrings.append(contentsOf: extractAllStrings(from: workout.metadata))

        // Extract metadata strings from workout activities
        for activity in workout.workoutActivities {
            allMetadataStrings.append(contentsOf: extractAllStrings(from: activity.metadata))
        }

        // Extract metadata strings from workout events
        if let events = workout.workoutEvents {
            for event in events {
                allMetadataStrings.append(contentsOf: extractAllStrings(from: event.metadata))
            }
        }

        // 1. Direct Metadata Check (highest priority: authentic HealthKit/WorkoutKit workout title)
        for text in allMetadataStrings {
            if let resolved = PreRunDrillId.resolve(from: text) {
                return ScheduledDrillIntent(
                    drillTitle: resolved.title,
                    preRunDrillId: resolved.rawValue,
                    scheduledDate: workoutDate,
                    durationMinutes: max(1, Int(round(durationSeconds / 60.0)))
                )
            }
            for candidate in PreRunDrillId.allCases {
                let singularTitle = candidate.title.hasSuffix("s") ? String(candidate.title.dropLast()) : candidate.title
                if text.localizedCaseInsensitiveContains(candidate.title) ||
                   text.localizedCaseInsensitiveContains(singularTitle) ||
                   (!candidate.rawValue.isEmpty && text.localizedCaseInsensitiveContains(candidate.rawValue)) {
                    return ScheduledDrillIntent(
                        drillTitle: candidate.title,
                        preRunDrillId: candidate.rawValue,
                        scheduledDate: workoutDate,
                        durationMinutes: max(1, Int(round(durationSeconds / 60.0)))
                    )
                }
            }
        }

        // 2. WorkoutKit CustomWorkout Check (iOS 17+)
        if let custom = customWorkout, let name = custom.displayName {
            if let resolved = PreRunDrillId.resolve(from: name) {
                return ScheduledDrillIntent(
                    drillTitle: resolved.title,
                    preRunDrillId: resolved.rawValue,
                    scheduledDate: workoutDate,
                    durationMinutes: max(1, Int(round(durationSeconds / 60.0)))
                )
            }
            for candidate in PreRunDrillId.allCases {
                let singularTitle = candidate.title.hasSuffix("s") ? String(candidate.title.dropLast()) : candidate.title
                if name.localizedCaseInsensitiveContains(candidate.title) ||
                   name.localizedCaseInsensitiveContains(singularTitle) ||
                   (!candidate.rawValue.isEmpty && name.localizedCaseInsensitiveContains(candidate.rawValue)) {
                    return ScheduledDrillIntent(
                        drillTitle: candidate.title,
                        preRunDrillId: candidate.rawValue,
                        scheduledDate: workoutDate,
                        durationMinutes: max(1, Int(round(durationSeconds / 60.0)))
                    )
                }
            }
        }

        // 3. Structural Entities: HKWorkoutActivity & HKWorkoutEvent (Apple Watch intervals / laps)
        let thirtyDayCadence = baselineCadence ?? 155
        if workout.workoutActivities.count >= 4 {
            if let activityMatch = DrillPatternRecognizer.recognizeFromActivities(
                activities: workout.workoutActivities,
                buckets: buckets,
                baselineCadence: thirtyDayCadence
            ) {
                return ScheduledDrillIntent(
                    drillTitle: activityMatch.drillId.title,
                    preRunDrillId: activityMatch.drillId.rawValue,
                    scheduledDate: workoutDate,
                    durationMinutes: max(1, Int(round(durationSeconds / 60.0)))
                )
            }
        }

        if let events = workout.workoutEvents, events.filter({ $0.type == .lap || $0.type == .segment }).count >= 4 {
            if let eventMatch = DrillPatternRecognizer.recognizeFromEvents(
                events: events,
                buckets: buckets,
                baselineCadence: thirtyDayCadence
            ) {
                return ScheduledDrillIntent(
                    drillTitle: eventMatch.drillId.title,
                    preRunDrillId: eventMatch.drillId.rawValue,
                    scheduledDate: workoutDate,
                    durationMinutes: max(1, Int(round(durationSeconds / 60.0)))
                )
            }
        }

        // 4. Intent Heuristic Fallback (scheduled drill within 48h of workout)
        let intents = recentIntents()
        let matchingIntents = intents.filter { intent in
            if let matchedID = intent.matchedWorkoutID, matchedID != workout.uuid { return false }
            let timeDiff = workoutDate.timeIntervalSince(intent.scheduledDate)
            guard timeDiff >= -3600 && timeDiff <= 48 * 3600 else { return false }

            let expectedDuration = Double(intent.durationMinutes * 60)
            if durationSeconds > 0 {
                let minAllowed = max(180.0, expectedDuration * 0.40)
                let maxAllowed = max(expectedDuration * 2.5, expectedDuration + 1200.0)
                guard durationSeconds >= minAllowed && durationSeconds <= maxAllowed else { return false }
            }
            return true
        }

        // Prefer the most recently scheduled matching intent (user's latest intended drill)
        if let bestIntent = matchingIntents.max(by: { $0.scheduledDate < $1.scheduledDate }) {
            return bestIntent
        }

        // 5. Autonomous Biomechanical Pattern Recognition (from 15s BucketData)
        if !buckets.isEmpty {
            if let patternMatch = DrillPatternRecognizer.recognizeDrill(
                buckets: buckets,
                baselineCadence: thirtyDayCadence,
                workoutDuration: durationSeconds,
                zone4Threshold: zone4Threshold,
                zone2Threshold: zone2Threshold,
                zone1Threshold: zone1Threshold
            ) {
                return ScheduledDrillIntent(
                    drillTitle: patternMatch.drillId.title,
                    preRunDrillId: patternMatch.drillId.rawValue,
                    scheduledDate: workoutDate,
                    durationMinutes: max(1, Int(round(durationSeconds / 60.0)))
                )
            }
        }

        return nil
    }

    nonisolated public static func matchDrill(
        workoutDate: Date,
        durationSeconds: Double,
        metadata: [String: Any]? = nil,
        buckets: [BucketData] = [],
        baselineCadence: Int? = nil,
        zone4Threshold: Double = 161.5,
        zone2Threshold: Double = 142.0,
        zone1Threshold: Double = 125.0
    ) -> ScheduledDrillIntent? {
        guard !isGuidedOrThirdPartySession(metadata: metadata) else {
            return nil
        }

        let allMetadataStrings: [String] = extractAllStrings(from: metadata)

        // 1. Direct Metadata Check
        for text in allMetadataStrings {
            if let resolved = PreRunDrillId.resolve(from: text) {
                return ScheduledDrillIntent(
                    drillTitle: resolved.title,
                    preRunDrillId: resolved.rawValue,
                    scheduledDate: workoutDate,
                    durationMinutes: max(1, Int(round(durationSeconds / 60.0)))
                )
            }
            for candidate in PreRunDrillId.allCases {
                let singularTitle = candidate.title.hasSuffix("s") ? String(candidate.title.dropLast()) : candidate.title
                if text.localizedCaseInsensitiveContains(candidate.title) ||
                   text.localizedCaseInsensitiveContains(singularTitle) ||
                   (!candidate.rawValue.isEmpty && text.localizedCaseInsensitiveContains(candidate.rawValue)) {
                    return ScheduledDrillIntent(
                        drillTitle: candidate.title,
                        preRunDrillId: candidate.rawValue,
                        scheduledDate: workoutDate,
                        durationMinutes: max(1, Int(round(durationSeconds / 60.0)))
                    )
                }
            }
        }

        // 2. Intent Heuristic Fallback
        let intents = recentIntents()
        let matchingIntents = intents.filter { intent in
            if intent.matchedWorkoutID != nil { return false }
            let timeDiff = workoutDate.timeIntervalSince(intent.scheduledDate)
            guard timeDiff >= -3600 && timeDiff <= 48 * 3600 else { return false }

            let expectedDuration = Double(intent.durationMinutes * 60)
            if durationSeconds > 0 {
                let minAllowed = max(180.0, expectedDuration * 0.40)
                let maxAllowed = max(expectedDuration * 2.5, expectedDuration + 1200.0)
                guard durationSeconds >= minAllowed && durationSeconds <= maxAllowed else { return false }
            }
            return true
        }

        if let best = matchingIntents.min(by: {
            abs(workoutDate.timeIntervalSince($0.scheduledDate)) < abs(workoutDate.timeIntervalSince($1.scheduledDate))
        }) {
            return best
        }

        // 3. Autonomous Biomechanical Pattern Recognition
        if !buckets.isEmpty {
            let thirtyDayCadence = baselineCadence ?? 155
            if let patternMatch = DrillPatternRecognizer.recognizeDrill(
                buckets: buckets,
                baselineCadence: thirtyDayCadence,
                workoutDuration: durationSeconds,
                zone4Threshold: zone4Threshold,
                zone2Threshold: zone2Threshold,
                zone1Threshold: zone1Threshold
            ) {
                return ScheduledDrillIntent(
                    drillTitle: patternMatch.drillId.title,
                    preRunDrillId: patternMatch.drillId.rawValue,
                    scheduledDate: workoutDate,
                    durationMinutes: max(1, Int(round(durationSeconds / 60.0)))
                )
            }
        }

        return nil
    }

    /// Translates a DTO into a scheduled WorkoutKit plan for Apple Watch.
    func scheduleDrill(dto: DrillPrescriptionDTO) async throws {
        if await WorkoutScheduler.shared.authorizationState != .authorized {
            let status = await WorkoutScheduler.shared.requestAuthorization()
            guard status == .authorized else {
                throw NSError(domain: "WorkoutBridge", code: 1, userInfo: [NSLocalizedDescriptionKey: "WorkoutKit authorization denied."])
            }
        }

        let preRunId = PreRunDrillId(rawValue: dto.preRunDrillId ?? "") ?? .strides
        let duration = DrillDuration(rawValue: dto.durationMinutes ?? 15) ?? .fifteenMinutes
        let haptic = HapticFeedbackMode(rawValue: dto.hapticMode ?? "") ?? .on
        let readiness = ReadinessState(rawValue: dto.readinessState ?? "") ?? .productive
        let drill = PreRunDrill(
            id: preRunId,
            previousCadence: dto.previousCadence,
            targetCadence: dto.targetCadence,
            duration: duration,
            hapticMode: haptic,
            readinessState: readiness
        )
        let plan = drill.buildWorkoutPlan()

        let now = Calendar.current.dateComponents([.calendar, .timeZone, .year, .month, .day, .hour, .minute], from: Date())
        await WorkoutScheduler.shared.schedule(plan, at: now)

        let intent = ScheduledDrillIntent(
            drillTitle: drill.id.title,
            preRunDrillId: drill.id.rawValue,
            scheduledDate: Date(),
            durationMinutes: duration.rawValue,
            targetCadence: dto.targetCadence,
            matchedWorkoutID: nil
        )
        Self.saveDrillIntent(intent)
    }

    /// Links a drill to a run record without overriding its native classification
    @MainActor public static func linkDrill(
        to runRecord: RunRecord,
        drillId: PreRunDrillId,
        baselineCadence: Double? = nil
    ) {
        let allIds = PreRunDrillId.allCases.map(\.rawValue)
        let allTitles = PreRunDrillId.allCases.map(\.title)
        runRecord.framboiseTags.removeAll {
            $0.hasPrefix("drill:") ||
            $0.hasPrefix("drillIntervals:") ||
            $0.hasPrefix("drillWorkCadence:") ||
            $0.hasPrefix("drillRecCadence:") ||
            $0.hasPrefix("drillReps:") ||
            $0 == "prescribedDrill" ||
            $0 == "userLinkedDrill" ||
            $0 == "userUnlinkedDrill" ||
            allIds.contains($0) ||
            allTitles.contains($0) ||
            $0.isEmpty
        }
        runRecord.framboiseTags.append("prescribedDrill")
        runRecord.framboiseTags.append("userLinkedDrill")
        runRecord.framboiseTags.append(drillId.rawValue)
        runRecord.framboiseTags.append("drill:\(drillId.title)")

        // Resolve authentic 30-day baseline strictly prior to this workout
        let effectiveBaseline: Int = {
            if let b = baselineCadence, b > 0 {
                return Int(round(b))
            }
            if let historical = runRecord.computeHistoricalBaselineCadence(), historical > 0 {
                return Int(round(historical))
            }
            return 155
        }()

        // Purge any stale intent matching this workout and bind the new drill intent
        var intents = recentIntents()
        intents.removeAll { $0.matchedWorkoutID == runRecord.hkWorkoutID }
        let newIntent = ScheduledDrillIntent(
            drillTitle: drillId.title,
            preRunDrillId: drillId.rawValue,
            scheduledDate: runRecord.date,
            durationMinutes: max(1, Int(round(runRecord.duration / 60.0))),
            matchedWorkoutID: runRecord.hkWorkoutID
        )
        intents.append(newIntent)
        persistIntents(intents)

        // Update insight drill recommendations
        let template = DrillTemplate.template(for: drillId)
        let targetCadenceInt = template.calculateTargetCadence(effectiveBaseline)
        if let recs = runRecord.insight?.drillRecommendations, !recs.isEmpty {
            var found = false
            for rec in recs {
                if rec.drillTitle == drillId.title || rec.preRunDrillId == drillId.rawValue {
                    rec.isCompleted = true
                    found = true
                } else {
                    rec.isCompleted = false
                }
            }
            if !found {
                let newRec = DrillRecommendation(
                    drillTitle: template.title,
                    preRunDrillId: template.id.rawValue,
                    drillPurpose: template.defaultPurpose,
                    drillWork: template.defaultWork,
                    drillCues: template.generateInstructionalCue(targetCadenceInt),
                    drillEffort: template.defaultEffort,
                    drillRecovery: template.defaultRecovery,
                    targetCadence: "\(targetCadenceInt) SPM",
                    previousCadence: effectiveBaseline,
                    isCompleted: true
                )
                runRecord.insight?.drillRecommendations?.insert(newRec, at: 0)
            }
        }
        if let rec = runRecord.insight?.drillRecommendation {
            if rec.drillTitle == drillId.title || rec.preRunDrillId == drillId.rawValue {
                rec.isCompleted = true
            } else {
                rec.isCompleted = false
            }
        }

        if let parentClass = PreRunDrillId.correspondingClassification(for: drillId.title),
            runRecord.detectedTypeRaw != parentClass {
            runRecord.detectedTypeRaw = parentClass
        }

        // Recalculate interval scorecard for the newly linked drill using authentic baseline
        Task {
            if let workout = try? await HealthKitManager.shared.fetchWorkout(with: runRecord.hkWorkoutID),
               let buckets = try? await HealthKitManager.shared.fetchBucketedSamples(for: workout),
               !buckets.isEmpty {
                let oscDelta = (runRecord.workingAvgVerticalOscillation ?? 9.5) - 9.5
                let summary = DrillIntervalEvaluator.evaluate(
                    workout: workout,
                    buckets: buckets,
                    drillId: drillId,
                    baselineCadence: effectiveBaseline,
                    workoutDuration: runRecord.duration,
                    oscDelta: oscDelta
                )
                runRecord.framboiseTags.removeAll {
                    $0.hasPrefix("drillIntervals:") ||
                    $0.hasPrefix("drillWorkCadence:") ||
                    $0.hasPrefix("drillRecCadence:") ||
                    $0.hasPrefix("drillReps:")
                }
                for tag in summary.framboiseTags where !runRecord.framboiseTags.contains(tag) {
                    runRecord.framboiseTags.append(tag)
                }
                try? runRecord.modelContext?.save()
            }
        }

        try? runRecord.modelContext?.save()
    }

    /// Unlinks a drill from a run record, restoring standard classification properties
    @MainActor public static func unlinkDrill(from runRecord: RunRecord) {
        let allIds = PreRunDrillId.allCases.map(\.rawValue)
        let allTitles = PreRunDrillId.allCases.map(\.title)
        runRecord.framboiseTags.removeAll {
            $0.hasPrefix("drill:") ||
            $0.hasPrefix("drillIntervals:") ||
            $0.hasPrefix("drillWorkCadence:") ||
            $0.hasPrefix("drillRecCadence:") ||
            $0.hasPrefix("drillReps:") ||
            $0 == "prescribedDrill" ||
            $0 == "userLinkedDrill" ||
            $0 == "userUnlinkedDrill" ||
            allIds.contains($0) ||
            allTitles.contains($0) ||
            $0.isEmpty
        }
        runRecord.framboiseTags.append("userUnlinkedDrill")

        var intents = recentIntents()
        intents.removeAll { $0.matchedWorkoutID == runRecord.hkWorkoutID }
        persistIntents(intents)

        if let recs = runRecord.insight?.drillRecommendations {
            for rec in recs {
                rec.isCompleted = false
            }
        }
        if let rec = runRecord.insight?.drillRecommendation {
            rec.isCompleted = false
        }
        try? runRecord.modelContext?.save()
    }
}
