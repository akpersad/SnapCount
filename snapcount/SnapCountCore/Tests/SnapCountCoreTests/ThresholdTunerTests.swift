import Testing
import Foundation
@testable import SnapCountCore

struct ThresholdTunerTests {

    /// Cleanly separable: targets score high, non-targets low.
    static let separable: [LabelledScore] = [
        .init(similarity: 0.90, isTarget: true),
        .init(similarity: 0.85, isTarget: true),
        .init(similarity: 0.80, isTarget: true),
        .init(similarity: 0.30, isTarget: false),
        .init(similarity: 0.25, isTarget: false),
        .init(similarity: 0.20, isTarget: false),
    ]

    @Test("A perfectly separable set yields perfect precision and recall")
    func separableSet() throws {
        let result = try #require(ThresholdTuner().recommend(from: Self.separable))
        #expect(result.precision == 1.0)
        #expect(result.recall == 1.0)
        // The cut must sit between the two clusters.
        #expect(result.threshold > 0.30)
        #expect(result.threshold <= 0.80)
    }

    @Test("Precision is favoured over recall when the classes overlap")
    func overlappingSet() throws {
        let overlapping: [LabelledScore] = [
            .init(similarity: 0.90, isTarget: true),
            .init(similarity: 0.70, isTarget: true),
            .init(similarity: 0.68, isTarget: false),  // an impostor scoring high
            .init(similarity: 0.20, isTarget: false),
        ]
        let result = try #require(
            ThresholdTuner().recommend(from: overlapping, minimumPrecision: 0.99))
        // The cut has to clear the impostor at 0.68 without losing the genuine 0.70, so it
        // lands in the narrow gap between them. Precision is protected at no cost to recall.
        #expect(result.threshold > 0.68)
        #expect(result.threshold <= 0.70)
        #expect(result.falsePositives == 0)
        #expect(result.falseNegatives == 0)
    }

    @Test("A wide gap yields a cut in its middle, not hugging the worst impostor")
    func plateauMidpoint() throws {
        // Every cut from 0.31 to 0.80 is perfect on this data. Picking 0.31 would leave no
        // margin for an unseen impostor scoring 0.35; the middle leaves margin both ways.
        let result = try #require(ThresholdTuner().recommend(from: Self.separable))
        #expect(abs(result.threshold - 0.555) < 0.011)
    }

    @Test("An indiscriminate reference returns nil rather than a bad threshold")
    func inseparableSet() {
        let inseparable: [LabelledScore] = [
            .init(similarity: 0.80, isTarget: false),
            .init(similarity: 0.79, isTarget: true),
            .init(similarity: 0.78, isTarget: false),
        ]
        // No cut reaches 98% precision, so the honest answer is "this reference is not usable".
        #expect(ThresholdTuner().recommend(from: inseparable, minimumPrecision: 0.98) == nil)
    }

    @Test("An empty sweep is empty rather than crashing")
    func emptyInput() {
        #expect(ThresholdTuner().sweep([]).isEmpty)
    }
}
