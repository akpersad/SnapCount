import Foundation
import CoreGraphics

/// The result of building a reference from embeddings and tuning its threshold.
///
/// Works on embeddings, not images, so callers can decode and discard one photo at a time.
/// Holding 60 full-size photos in memory at once would not survive on a phone.
public struct EnrollmentEvaluation: Sendable {
    public enum Outcome: Sendable, Equatable {
        case tuned(ThresholdResult)
        /// Fewer than 2 reference faces, or no faces in the negatives, so there is nothing to
        /// tune against. The enrollment falls back to `PhotoAnalyzer`'s default threshold.
        case insufficientData
        /// No threshold reached the precision floor. The reference set does not separate her
        /// from other children and needs better photos.
        case notDiscriminative
    }

    /// Enrolled person, with `matchThreshold` set only when the outcome is `.tuned`.
    public let person: EnrolledPerson
    /// Leave-one-out score of each reference, in the order the references were given.
    public let genuineScores: [Float]
    /// Score of every face in the negatives against the full centroid.
    public let impostorScores: [Float]
    public let outcome: Outcome
}

public enum EnrollmentEvaluator {
    /// Builds the centroid and picks a threshold from labelled scores.
    ///
    /// Reference faces are scored **leave-one-out**: each against a centroid built from the
    /// others. Scoring a face against a centroid it helped build inflates the score and would
    /// produce an optimistic threshold.
    ///
    /// Returns nil when `references` is empty.
    public static func evaluate(
        id: String,
        displayName: String,
        references: [FaceEmbedding],
        negatives: [FaceEmbedding],
        minimumPrecision: Double = 0.98,
        now: Date = Date()
    ) -> EnrollmentEvaluation? {
        guard let centroid = FaceEmbedding.centroid(of: references) else { return nil }

        var genuine: [Float] = []
        if references.count >= 2 {
            for i in references.indices {
                var others = references
                others.remove(at: i)
                guard let looCentroid = FaceEmbedding.centroid(of: others) else { continue }
                genuine.append(references[i].similarity(to: looCentroid))
            }
        }
        let impostor = negatives.map { $0.similarity(to: centroid) }

        var person = EnrolledPerson(
            id: id,
            displayName: displayName,
            embedding: centroid,
            enrolledAt: now,
            sampleCount: references.count)

        let outcome: EnrollmentEvaluation.Outcome
        if genuine.isEmpty || impostor.isEmpty {
            outcome = .insufficientData
        } else {
            let labelled = genuine.map { LabelledScore(similarity: $0, isTarget: true) }
                + impostor.map { LabelledScore(similarity: $0, isTarget: false) }
            if let result = ThresholdTuner().recommend(
                from: labelled, minimumPrecision: minimumPrecision) {
                person.matchThreshold = result.threshold
                outcome = .tuned(result)
            } else {
                outcome = .notDiscriminative
            }
        }

        return EnrollmentEvaluation(
            person: person,
            genuineScores: genuine,
            impostorScores: impostor,
            outcome: outcome)
    }
}

extension Enroller {
    /// Every face in an image that survives filtering, with its embedding.
    ///
    /// For negatives: any stranger in frame is a chance for a false positive, so all of them
    /// are scored, not just the largest.
    public func allFaces(in image: CGImage) async throws -> [EmbeddedFace] {
        var results: [EmbeddedFace] = []
        for face in try await detector.detectFaces(in: image) {
            if let embedding = try? await embedder.embed(face.crop) {
                results.append(EmbeddedFace(face: face, embedding: embedding))
            }
        }
        return results
    }

    public func allFaceEmbeddings(in image: CGImage) async throws -> [FaceEmbedding] {
        try await allFaces(in: image).map(\.embedding)
    }
}
