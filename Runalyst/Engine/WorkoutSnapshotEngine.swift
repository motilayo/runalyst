import Foundation
import SwiftData
import RunalystCore

/// The Foundry persistence and snapshot engine for Runalyst.
///
/// Bridges SwiftData `RunRecord` instances to `TemporalSnapshotCore`, ensuring
/// that all views, AI coaching engines, and Apple Watch exports consume the exact same
/// temporal aggregates without duplicate on-the-fly math.
@MainActor
final class WorkoutSnapshotEngine {
    static let shared = WorkoutSnapshotEngine()

    private struct CacheKey: Equatable {
        let dayStart: Date
        let runsFingerprint: String
        let firstWeekday: Int
    }

    private var cachedKey: CacheKey?
    private var cachedSnapshot: TemporalSnapshotReport?

    private init() {}

    /// Canonical calendar for temporal aggregations (Monday = 2 default per CONSTITUTION.md).
    static var defaultCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US_POSIX")
        cal.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        cal.firstWeekday = 2 // Monday start
        return cal
    }

    /// Resolves the current temporal snapshot report, reusing the cached snapshot when valid.
    func resolveSnapshot(
        runs: [RunRecord],
        now: Date = Date(),
        calendar: Calendar? = nil
    ) -> TemporalSnapshotReport {
        let cal = calendar ?? Self.defaultCalendar
        let dayStart = cal.startOfDay(for: now)
        let fingerprint = Self.computeFingerprint(runs: runs)

        let key = CacheKey(
            dayStart: dayStart,
            runsFingerprint: fingerprint,
            firstWeekday: cal.firstWeekday
        )

        if let cachedKey, cachedKey == key, let cachedSnapshot {
            return cachedSnapshot
        }

        let activeRuns = runs.filter { !$0.isDeleted }
        let volumeSamples = activeRuns.map { $0.toVolumeRunSample() }

        let freshSnapshot = TemporalSnapshotCore.evaluateSnapshot(
            runs: volumeSamples,
            now: now,
            calendar: cal
        )

        self.cachedKey = key
        self.cachedSnapshot = freshSnapshot
        return freshSnapshot
    }

    /// Explicitly invalidates the cached snapshot when a workout is ingested, deleted, or calibrated.
    func invalidate() {
        cachedKey = nil
        cachedSnapshot = nil
    }

    /// Computes a lightweight fingerprint across active runs to detect additions, deletions, or distance calibrations.
    static func computeFingerprint(runs: [RunRecord]) -> String {
        let active = runs.filter { !$0.isDeleted }
        guard let first = active.first else { return "empty" }

        var hasher = Hasher()
        hasher.combine(active.count)

        // Hash key attributes of the most recent 35 runs
        for run in active.prefix(35) {
            hasher.combine(run.id)
            hasher.combine(run.date.timeIntervalSince1970)
            hasher.combine(Int(run.totalDistanceMeters.rounded()))
            hasher.combine(Int(run.duration.rounded()))
            hasher.combine(Int(run.workingAvgCadence.rounded()))
            hasher.combine(run.isIndoor ?? false)
            hasher.combine(run.detectedTypeRaw)
        }

        return "\(active.count)-\(first.id.uuidString)-\(hasher.finalize())"
    }
}
