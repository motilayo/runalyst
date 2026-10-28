import Foundation
import Testing
@testable import RunalystCore

@Suite("Brick 2: Pure Temporal Core Tests")
struct TemporalSnapshotCoreTests {

    @Test("TemporalSnapshotCore evaluates authentic reference timeline with absolute accuracy")
    func testEvaluateSnapshotAuthenticTimeline() {
        let (now, calendar, runs) = GoldenTemporalFixtures.makeReferenceTimeline()

        let snapshot = TemporalSnapshotCore.evaluateSnapshot(
            runs: runs,
            now: now,
            calendar: calendar
        )

        // 1. Conservation of Distance Invariant
        #expect(snapshot.thisWeek.totalDistanceKm == 9.46, "This Week volume must equal exactly 9.46 km")
        #expect(snapshot.thisWeek.workoutCount == 4, "This Week must contain exactly 4 workouts")

        // 2. Disjoint Historical Week Invariants (Matching user's authentic screenshot)
        #expect(snapshot.lastWeek.totalDistanceKm == 19.5, "Last Week volume must equal 19.5 km")
        #expect(snapshot.twoWeeksAgo.totalDistanceKm == 18.2, "2W Ago volume must equal 18.2 km")
        #expect(snapshot.threeWeeksAgo.totalDistanceKm == 0.0, "3W Ago volume has no runs in fixture")

        // 3. Rolling 7-Day Window Invariant
        #expect(snapshot.trailing7Days.totalDistanceKm == 19.5, "Trailing 7-day rolling window must equal 19.5 km")
        #expect(snapshot.trailing7Days.workoutCount == 5, "Trailing 7-day rolling window must contain 5 workouts")

        // 4. Dimensional Average Pace Invariant (467.86 s/km)
        guard let thisWeekPace = snapshot.thisWeek.dimensionalPaceSecPerKm else {
            Issue.record("This week dimensional pace should not be nil")
            return
        }
        #expect(abs(thisWeekPace - 467.86) < 0.1, "This week pace must equal 467.86 s/km (~7:48/km)")

        // 5. Duration-Weighted Cadence Invariant (155.57 SPM -> 156 SPM)
        guard let thisWeekCadence = snapshot.thisWeek.durationWeightedCadence else {
            Issue.record("This week cadence should not be nil")
            return
        }
        #expect(abs(thisWeekCadence - 155.57) < 0.1, "This week cadence must equal 155.57 SPM")
        #expect(thisWeekCadence.rounded() == 156.0, "Rounded cadence display must be 156 SPM")

        // 6. Classification Breakdown
        #expect(snapshot.thisWeek.classificationBreakdown["Easy Run"] == 2)
        #expect(snapshot.thisWeek.classificationBreakdown["Cadence Pyramids"] == 1)
        #expect(snapshot.thisWeek.classificationBreakdown["Fartlek"] == 1)
    }

    @Test("Anthropometric Cadence Floor calculation accurately adapts to runner height and pace")
    func testAnthropometricCadenceFloorCalculation() {
        // Standard runner (175 cm)
        #expect(TemporalSnapshotCore.anthropometricCadenceFloor(heightCm: 175, paceCategory: "easy") == 165)
        #expect(TemporalSnapshotCore.anthropometricCadenceFloor(heightCm: 175, paceCategory: "tempo") == 175)
        #expect(TemporalSnapshotCore.anthropometricCadenceFloor(heightCm: 175, paceCategory: "interval") == 185)

        // Shorter runner (< 163 cm)
        #expect(TemporalSnapshotCore.anthropometricCadenceFloor(heightCm: 160, paceCategory: "easy") == 175)
        #expect(TemporalSnapshotCore.anthropometricCadenceFloor(heightCm: 160, paceCategory: "tempo") == 185)

        // Taller runner (> 183 cm)
        #expect(TemporalSnapshotCore.anthropometricCadenceFloor(heightCm: 188, paceCategory: "easy") == 160)
        #expect(TemporalSnapshotCore.anthropometricCadenceFloor(heightCm: 188, paceCategory: "tempo") == 170)
        #expect(TemporalSnapshotCore.anthropometricCadenceFloor(heightCm: 188, paceCategory: "stride") == 180)
    }

    @Test("Empty workout list produces valid zero slices with no nil crashes or division by zero")
    func testEmptyRunsEvaluation() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 2
        let now = Date(timeIntervalSince1970: 1793130960)

        let snapshot = TemporalSnapshotCore.evaluateSnapshot(
            runs: [],
            now: now,
            calendar: calendar
        )

        #expect(snapshot.thisWeek.totalDistanceKm == 0.0)
        #expect(snapshot.thisWeek.totalDurationSeconds == 0.0)
        #expect(snapshot.thisWeek.workoutCount == 0)
        #expect(snapshot.thisWeek.dimensionalPaceSecPerKm == nil)
        #expect(snapshot.thisWeek.durationWeightedCadence == nil)
        #expect(snapshot.trailing7Days.totalDistanceKm == 0.0)
        #expect(snapshot.trailing7Days.activeDaysCount == 0)
        #expect(snapshot.workoutDensityTier == "Building")
    }
}
