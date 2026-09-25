import Foundation
import Observation
import PhotosUI
import SwiftUI
import UIKit
import SnapCountCore

/// Builds a reference and tunes its threshold from two sets of picked photos, entirely on
/// the phone. This is option (a) from WORKPLAN open question 8: the app does not depend on
/// the Mac CLI.
///
/// Photos are decoded, embedded, and dropped one at a time. What survives the run is a set of
/// 112 px face crops held in memory for the results screen, and the embeddings. Nothing is
/// written to disk until the user taps Save, and then only the centroid and threshold.
@MainActor
@Observable
final class EnrollmentFlow {
    enum Phase {
        case idle
        case analyzing(done: Int, total: Int)
        case finished(EnrollmentResult)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private var task: Task<Void, Never>?

    func start(
        name: String,
        references: [PhotosPickerItem],
        negatives: [PhotosPickerItem],
        embedder: CoreMLFaceEmbedder
    ) {
        task?.cancel()
        let processor = EnrollmentProcessor(enroller: Enroller(embedder: embedder))
        let total = references.count + negatives.count
        phase = .analyzing(done: 0, total: total)

        task = Task {
            var done = 0
            var referenceFaces: [ScoredFace] = []
            var unusableReferences = 0
            var negativeFaces: [ScoredFace] = []

            for item in references {
                if Task.isCancelled { return }
                if let face = await processor.largestFace(in: item) {
                    referenceFaces.append(face)
                } else {
                    unusableReferences += 1
                }
                done += 1
                phase = .analyzing(done: done, total: total)
            }
            for item in negatives {
                if Task.isCancelled { return }
                negativeFaces += await processor.allFaces(in: item)
                done += 1
                phase = .analyzing(done: done, total: total)
            }

            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let evaluation = EnrollmentEvaluator.evaluate(
                id: "daughter",
                displayName: trimmedName,
                references: referenceFaces.map(\.embedding),
                negatives: negativeFaces.map(\.embedding)
            ) else {
                phase = .failed(
                    "No usable face was found in any of the photos. Pick clear, front-facing photos where the face is large in the frame.")
                return
            }

            for i in referenceFaces.indices where i < evaluation.genuineScores.count {
                referenceFaces[i].score = evaluation.genuineScores[i]
            }
            for i in negativeFaces.indices {
                negativeFaces[i].score = evaluation.impostorScores[i]
            }

            phase = .finished(EnrollmentResult(
                evaluation: evaluation,
                referencePhotoCount: references.count,
                unusableReferences: unusableReferences,
                negativePhotoCount: negatives.count,
                referenceFaces: referenceFaces,
                negativeFaces: negativeFaces))
        }
    }

    func reset() {
        task?.cancel()
        task = nil
        phase = .idle
    }
}

/// A face crop kept only for display on the results screen.
struct ScoredFace: Identifiable, Sendable {
    let id = UUID()
    let crop: UIImage
    let embedding: FaceEmbedding
    var score: Float?
}

struct EnrollmentResult {
    let evaluation: EnrollmentEvaluation
    let referencePhotoCount: Int
    let unusableReferences: Int
    let negativePhotoCount: Int
    let referenceFaces: [ScoredFace]
    let negativeFaces: [ScoredFace]

    /// Her photos that look least like the rest. Worth replacing if far below the others.
    var weakestReferences: [ScoredFace] {
        Array(referenceFaces.filter { $0.score != nil }
            .sorted { $0.score! < $1.score! }
            .prefix(3))
    }

    /// The strangers closest to her. These are the false positives to worry about.
    var closestNegatives: [ScoredFace] {
        Array(negativeFaces.sorted { ($0.score ?? -1) > ($1.score ?? -1) }.prefix(3))
    }
}

/// The heavy per-photo work, kept off the main actor.
struct EnrollmentProcessor: Sendable {
    let enroller: Enroller

    nonisolated func largestFace(in item: PhotosPickerItem) async -> ScoredFace? {
        guard let image = await image(for: item),
              let face = try? await enroller.largestFace(in: image)
        else { return nil }
        return ScoredFace(crop: UIImage(cgImage: face.face.crop), embedding: face.embedding)
    }

    nonisolated func allFaces(in item: PhotosPickerItem) async -> [ScoredFace] {
        guard let image = await image(for: item),
              let faces = try? await enroller.allFaces(in: image)
        else { return [] }
        return faces.map { ScoredFace(crop: UIImage(cgImage: $0.face.crop), embedding: $0.embedding) }
    }

    /// Loads the original file bytes and decodes them upright and downscaled. If the photo is
    /// only in iCloud, Photos downloads it first, which is one more reason to enroll on land.
    private nonisolated func image(for item: PhotosPickerItem) async -> CGImage? {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        return ImageLoading.image(from: data)
    }
}
