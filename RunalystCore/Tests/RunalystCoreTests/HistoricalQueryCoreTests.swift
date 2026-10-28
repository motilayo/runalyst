import Foundation
@testable import RunalystCore
import Testing

@Suite("Historical Query Core Tests")
struct HistoricalQueryCoreTests {

    @Test("Parses query criteria accurately")
    func testQueryParsing() {
        let criteria = HistoricalQueryCriteriaCore.parse(from: "fastest outdoor 2026")
        #expect(criteria.environment == .outdoor)
        #expect(criteria.metric == .efficiencyFactor)
        #expect(criteria.direction == .descending)
        #expect(criteria.targetYear == 2026)
    }

    @Test("Filters and sorts historical candidates")
    func testFilterAndSort() {
        let now = Date()
        let run1 = HistoricalCandidateSampleCore(
            id: UUID(),
            date: now.addingTimeInterval(-86400),
            durationSeconds: 1800,
            distanceMeters: 5000,
            paceSecondsPerKm: 360,
            cadenceSPM: 165,
            heartRateBPM: 150,
            isIndoor: false
        )
        let run2 = HistoricalCandidateSampleCore(
            id: UUID(),
            date: now.addingTimeInterval(-172800),
            durationSeconds: 1800,
            distanceMeters: 6000,
            paceSecondsPerKm: 300,
            cadenceSPM: 172,
            heartRateBPM: 155,
            isIndoor: true
        )

        let outdoorOnly = HistoricalQueryCore.filterAndSort(
            candidates: [run1, run2],
            criteria: HistoricalQueryCriteriaCore(environment: .outdoor)
        )

        #expect(outdoorOnly.count == 1)
        #expect(outdoorOnly.first?.id == run1.id)
    }

    @Test("Parses comparison targets from query string")
    func testComparisonTargetParsing() {
        let targets = HistoricalQueryCore.parseComparisonTargets(from: "compare my last outdoor run vs my last indoor run")
        #expect(targets != nil)
        #expect(targets?.targetA == "outdoor")
        #expect(targets?.targetB == "indoor")
    }
}
