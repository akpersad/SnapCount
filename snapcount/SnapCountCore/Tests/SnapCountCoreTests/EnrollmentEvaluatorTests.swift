import Testing
import Foundation
@testable import SnapCountCore

struct EnrollmentEvaluatorTests {

    /// Unit vectors clustered tightly around the first axis: one person, varied photos.
    static let her: [FaceEmbedding] = [
        FaceEmbedding(values: [1.00, 0.10, 0.00]),
        FaceEmbedding(values: [1.00, 0.00, 0.10]),
        FaceEmbedding(values: [1.00, -0.10, 0.00]),
        FaceEmbedding(values: [1.00, 0.00, -0.10]),
    ]

    /// Other children, well away from her cluster.
    static let others: [FaceEmbedding] = [
        FaceEmbedding(values: [0.20, 1.00, 0.00]),
        FaceEmbedding(values: [0.10, 0.00, 1.00]),
        FaceEmbedding(values: [0.00, 0.70, 0.70]),
    ]

    @Test("Separable sets are tuned and the threshold lands on the person")
    func tuned() throws {
        let evaluation = try #require(EnrollmentEvaluator.evaluate(
            id: "d", displayName: "D", references: Self.her, negatives: Self.others))
        guard case .tuned(let result) = evaluation.outcome else {
            Issue.record("expected .tuned, got \(evaluation.outcome)")
            return
        }
        #expect(result.falsePositives == 0)
        #expect(evaluation.person.matchThreshold == result.threshold)
        #expect(evaluation.person.sampleCount == 4)
        #expect(evaluation.genuineScores.count == 4)
        #expect(evaluation.impostorScores.count == 3)
    }

    @Test("Genuine scores are leave-one-out, so they are lower than in-sample scores")
    func leaveOneOut() throws {
        let evaluation = try #require(EnrollmentEvaluator.evaluate(
            id: "d", displayName: "D", references: Self.her, negatives: Self.others))
        let centroid = evaluation.person.embedding
        for (i, score) in evaluation.genuineScores.enumerated() {
            #expect(score < Self.her[i].similarity(to: centroid))
        }
    }

    @Test("No negatives means nothing to tune against, and no threshold is stored")
    func noNegatives() throws {
        let evaluation = try #require(EnrollmentEvaluator.evaluate(
            id: "d", displayName: "D", references: Self.her, negatives: []))
        #expect(evaluation.outcome == .insufficientData)
        #expect(evaluation.person.matchThreshold == nil)
    }

    @Test("A single reference cannot be scored leave-one-out")
    func singleReference() throws {
        let evaluation = try #require(EnrollmentEvaluator.evaluate(
            id: "d", displayName: "D", references: [Self.her[0]], negatives: Self.others))
        #expect(evaluation.outcome == .insufficientData)
        #expect(evaluation.genuineScores.isEmpty)
    }

    @Test("A stranger identical to her makes the set not discriminative")
    func notDiscriminative() throws {
        // Every one of her photos has a twin in the negatives, so any cut that keeps her also
        // keeps an impostor and precision can never reach the floor.
        let evaluation = try #require(EnrollmentEvaluator.evaluate(
            id: "d", displayName: "D", references: Self.her, negatives: Self.her))
        #expect(evaluation.outcome == .notDiscriminative)
        #expect(evaluation.person.matchThreshold == nil)
    }

    @Test("No references yields nil")
    func empty() {
        #expect(EnrollmentEvaluator.evaluate(
            id: "d", displayName: "D", references: [], negatives: Self.others) == nil)
    }
}
