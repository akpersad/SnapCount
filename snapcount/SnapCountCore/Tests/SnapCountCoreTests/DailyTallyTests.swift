import Testing
import Foundation
@testable import SnapCountCore

struct DailyTallyTests {

    static let today = Date(timeIntervalSince1970: 1_790_000_000)
    static var yesterday: Date { today.addingTimeInterval(-86_400) }

    static func record(
        _ id: String,
        matched: Bool,
        similarity: Float = 0.7,
        at date: Date = DailyTallyTests.today,
        override: Bool? = nil
    ) -> PhotoRecord {
        PhotoRecord(
            id: id, source: .glasses, capturedAt: date,
            faceCount: 1, bestSimilarity: similarity,
            matched: matched, userOverride: override)
    }

    @Test("Counts only matched photos from the given day")
    func countsMatchesToday() {
        let records = [
            Self.record("a", matched: true),
            Self.record("b", matched: false),
            Self.record("c", matched: true),
            Self.record("d", matched: true, at: Self.yesterday),
        ]
        #expect(DailyTally().count(in: records, on: Self.today) == 2)
        #expect(DailyTally().total(in: records, on: Self.today) == 3)
    }

    @Test("A user correction overrides the model in both directions")
    func userOverrideWins() {
        let records = [
            Self.record("a", matched: false, override: true),
            Self.record("b", matched: true, override: false),
        ]
        #expect(DailyTally().count(in: records, on: Self.today) == 1)
    }

    @Test("Uncertain photos are the ones nearest the threshold, closest first")
    func uncertainOrdering() {
        let records = [
            Self.record("far-high", matched: true, similarity: 0.95),
            Self.record("near-high", matched: true, similarity: 0.68),
            Self.record("near-low", matched: false, similarity: 0.63),
            Self.record("far-low", matched: false, similarity: 0.10),
        ]
        let uncertain = DailyTally().uncertain(
            in: records, threshold: 0.65, margin: 0.08, on: Self.today)
        // near-low is 0.02 from the threshold, near-high is 0.03, so near-low sorts first.
        #expect(uncertain.map(\.id) == ["near-low", "near-high"])
    }

    @Test("An empty day counts zero")
    func emptyDay() {
        #expect(DailyTally().count(in: [], on: Self.today) == 0)
    }
}
