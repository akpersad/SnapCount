import Testing
import Foundation
@testable import SnapCountCore

struct FaceEmbeddingTests {

    @Test("Initialization normalizes to unit length")
    func normalizes() {
        let e = FaceEmbedding(values: [3, 4])
        #expect(abs(e.values[0] - 0.6) < 1e-6)
        #expect(abs(e.values[1] - 0.8) < 1e-6)
    }

    @Test("Identical vectors have similarity 1")
    func identical() {
        let a = FaceEmbedding(values: [1, 2, 3])
        #expect(abs(a.similarity(to: a) - 1) < 1e-5)
    }

    @Test("Orthogonal vectors have similarity 0")
    func orthogonal() {
        let a = FaceEmbedding(values: [1, 0])
        let b = FaceEmbedding(values: [0, 1])
        #expect(abs(a.similarity(to: b)) < 1e-6)
    }

    @Test("Opposite vectors have similarity -1")
    func opposite() {
        let a = FaceEmbedding(values: [1, 0])
        let b = FaceEmbedding(values: [-1, 0])
        #expect(abs(a.similarity(to: b) + 1) < 1e-6)
    }

    @Test("Mismatched dimensions never report a match")
    func mismatchedDimensions() {
        let a = FaceEmbedding(values: [1, 0])
        let b = FaceEmbedding(values: [1, 0, 0])
        // -1 is the floor, so this can never cross a sane threshold.
        #expect(a.similarity(to: b) == -1)
    }

    @Test("A zero vector does not divide by zero")
    func zeroVector() {
        let e = FaceEmbedding(values: [0, 0, 0])
        #expect(e.values == [0, 0, 0])
        #expect(!e.values.contains { $0.isNaN })
    }

    @Test("Centroid averages then renormalizes")
    func centroid() throws {
        let a = FaceEmbedding(values: [1, 0])
        let b = FaceEmbedding(values: [0, 1])
        let c = try #require(FaceEmbedding.centroid(of: [a, b]))
        // Mean is (0.5, 0.5), which normalizes to (0.707, 0.707).
        #expect(abs(c.values[0] - 0.7071068) < 1e-5)
        #expect(abs(c.values[1] - 0.7071068) < 1e-5)
    }

    @Test("Centroid rejects mixed dimensions rather than producing garbage")
    func centroidMixedDimensions() {
        let a = FaceEmbedding(values: [1, 0])
        let b = FaceEmbedding(values: [1, 0, 0])
        #expect(FaceEmbedding.centroid(of: [a, b]) == nil)
    }

    @Test("Centroid of nothing is nil")
    func centroidEmpty() {
        #expect(FaceEmbedding.centroid(of: []) == nil)
    }
}
