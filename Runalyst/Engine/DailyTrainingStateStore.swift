import Foundation
import SwiftData
import RunalystCore

/// Thread-safe snapshot container holding the immutable `DailyTrainingState` for the active day.
/// Prevents cross-surface calculation drift between `DashboardView`, `WorkoutsView`, and `AnalystChatTools`.
@MainActor
final class DailyTrainingStateStore {
    static let shared = DailyTrainingStateStore()

    private struct CacheKey: Equatable {
        let dayStart: Date
        let runsFingerprint: String
        let activeGoal: String
        let experienceLevel: String
        let useMetric: Bool
        let userHeightCm: Double
    }

    private var cachedKey: CacheKey?
    private var cachedState: DailyTrainingState?

    private init() {}

    /// Resolves the current daily training state, reusing the locked snapshot when valid.
    func resolveState(
        runRecords: [RunRecord],
        activeGoal: String = "Base Building",
        experienceLevel: String = "Intermediate",
        useMetric: Bool = true,
        userHeightCm: Double = 175.0,
        now: Date = Date()
    ) -> DailyTrainingState {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        let fingerprint = Self.computeFingerprint(runs: runRecords)

        let key = CacheKey(
            dayStart: dayStart,
            runsFingerprint: fingerprint,
            activeGoal: activeGoal,
            experienceLevel: experienceLevel,
            useMetric: useMetric,
            userHeightCm: userHeightCm
        )

        if let cachedKey, cachedKey == key, let cachedState {
            return cachedState
        }

        let freshState = SessionSynthesisEngine.evaluateDailyState(
            runRecords: runRecords,
            activeGoal: activeGoal,
            experienceLevel: experienceLevel,
            useMetric: useMetric,
            userHeightCm: userHeightCm,
            now: now
        )

        self.cachedKey = key
        self.cachedState = freshState
        return freshState
    }

    /// Explicitly invalidates the cached snapshot when a workout is ingested, deleted, or settings change.
    func invalidate() {
        cachedKey = nil
        cachedState = nil
    }

    static func computeFingerprint(runs: [RunRecord]) -> String {
        let active = runs.filter { !$0.isDeleted }
        guard let first = active.first else { return "empty" }
        var hasher = Hasher()
        hasher.combine(active.count)
        let cal = Calendar.current
        let thirtyDaysAgo = cal.date(byAdding: .day, value: -30, to: Date()) ?? Date().addingTimeInterval(-30 * 86400)
        for r in active where r.date >= thirtyDaysAgo {
            hasher.combine(r.id)
            hasher.combine(r.date.timeIntervalSince1970)
            hasher.combine(Int(r.duration))
            hasher.combine(r.isIndoor ?? false)
            hasher.combine(r.detectedTypeRaw)
            hasher.combine(r.classificationProvenanceRaw ?? "")
            hasher.combine(r.prescribedDrillName ?? "")
            hasher.combine(r.framboiseTags.joined(separator: ","))
        }
        return "\(active.count)-\(first.id.uuidString)-\(hasher.finalize())"
    }
}
