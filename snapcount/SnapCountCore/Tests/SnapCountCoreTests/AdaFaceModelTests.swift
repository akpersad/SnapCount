import Testing
import Foundation
import CoreGraphics
@testable import SnapCountCore

/// Exercises the real AdaFace model. Skipped when the model has not been fetched, so a fresh
/// clone still tests green; run `Scripts/fetch-model.sh` to enable.
enum ModelFixtures {
    static let modelsDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // SnapCountCoreTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // SnapCountCore
        .deletingLastPathComponent()  // snapcount
        .appendingPathComponent("Models")

    static let modelURL = modelsDirectory.appendingPathComponent("AdaFace_IR18.mlpackage")

    /// Public-domain official portraits named `person_n.jpg`. Adults, so this proves the
    /// model and preprocessing are wired correctly, not that it separates children. That is
    /// what the tuning run over the real reference photos is for.
    static let sanityFacesDirectory = modelsDirectory.appendingPathComponent("SanityFaces")

    static var modelAvailable: Bool {
        FileManager.default.fileExists(atPath: modelURL.path)
    }

    static var sanityFacesAvailable: Bool {
        modelAvailable && FileManager.default.fileExists(atPath: sanityFacesDirectory.path)
    }
}

@Suite(.enabled(if: ModelFixtures.modelAvailable, "AdaFace model not fetched"))
struct AdaFaceModelTests {

    @Test("Produces a 512-d unit-length embedding")
    func embeddingShape() async throws {
        let embedder = try await AdaFaceIR18.embedder(contentsOf: ModelFixtures.modelURL)
        let crop = TestImages.imageWithDot(size: 112, dot: CGPoint(x: 56, y: 56), dotRadius: 20)
        let embedding = try await embedder.embed(crop)

        #expect(embedding.dimension == AdaFaceIR18.dimension)
        let norm = embedding.values.reduce(0) { $0 + $1 * $1 }.squareRoot()
        #expect(abs(norm - 1) < 1e-3)
        #expect(!embedding.values.contains { $0.isNaN })
    }

    @Test("The same crop embeds identically twice")
    func deterministic() async throws {
        let embedder = try await AdaFaceIR18.embedder(contentsOf: ModelFixtures.modelURL)
        let crop = TestImages.imageWithDot(size: 112, dot: CGPoint(x: 40, y: 60), dotRadius: 12)
        let a = try await embedder.embed(crop)
        let b = try await embedder.embed(crop)
        #expect(a.similarity(to: b) > 0.999)
    }

    @Test(
        "Two photos of the same person outscore every pair of different people",
        .enabled(if: ModelFixtures.sanityFacesAvailable, "Sanity portraits not present"))
    func samePersonBeatsDifferentPeople() async throws {
        let enroller = Enroller(
            embedder: try await AdaFaceIR18.embedder(contentsOf: ModelFixtures.modelURL))

        var embeddings: [(person: String, embedding: FaceEmbedding)] = []
        for url in try ImageLoading.imageFiles(in: ModelFixtures.sanityFacesDirectory) {
            let image = try #require(ImageLoading.image(at: url))
            let embedding = try #require(
                try await enroller.largestFaceEmbedding(in: image),
                "No usable face in \(url.lastPathComponent)")
            let person = String(url.deletingPathExtension().lastPathComponent.split(separator: "_")[0])
            embeddings.append((person, embedding))
        }

        var genuine: [Float] = [], impostor: [Float] = []
        for i in embeddings.indices {
            for j in embeddings.indices where j > i {
                let score = embeddings[i].embedding.similarity(to: embeddings[j].embedding)
                if embeddings[i].person == embeddings[j].person {
                    genuine.append(score)
                } else {
                    impostor.append(score)
                }
            }
        }

        let minGenuine = try #require(genuine.min())
        let maxImpostor = try #require(impostor.max())
        print("AdaFace sanity: genuine \(genuine.sorted()), max impostor \(maxImpostor)")
        #expect(minGenuine > maxImpostor)
    }
}
