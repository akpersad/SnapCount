import Foundation
import CoreGraphics

/// An L2-normalized face embedding, comparable by cosine similarity.
///
/// This is biometric data. It is not trivially reversible to an image, but it gets the same
/// handling a photo would: app container only, excluded from backup, never transmitted.
public struct FaceEmbedding: Sendable, Codable, Equatable {
    public let values: [Float]

    public init(values: [Float]) {
        self.values = Self.l2Normalized(values)
    }

    public var dimension: Int { values.count }

    /// Cosine similarity in [-1, 1]. Both operands are unit vectors, so this is a plain dot product.
    public func similarity(to other: FaceEmbedding) -> Float {
        guard values.count == other.values.count else { return -1 }
        var sum: Float = 0
        for i in values.indices { sum += values[i] * other.values[i] }
        return sum
    }

    static func l2Normalized(_ v: [Float]) -> [Float] {
        var sumSq: Float = 0
        for x in v { sumSq += x * x }
        let norm = sumSq.squareRoot()
        guard norm > 1e-9 else { return v }
        return v.map { $0 / norm }
    }

    /// Mean of several embeddings, renormalized. This is how an enrollment set collapses
    /// into a single reference vector.
    public static func centroid(of embeddings: [FaceEmbedding]) -> FaceEmbedding? {
        guard let first = embeddings.first else { return nil }
        let dim = first.dimension
        guard embeddings.allSatisfy({ $0.dimension == dim }) else { return nil }

        var acc = [Float](repeating: 0, count: dim)
        for e in embeddings {
            for i in 0..<dim { acc[i] += e.values[i] }
        }
        let n = Float(embeddings.count)
        return FaceEmbedding(values: acc.map { $0 / n })
    }
}

/// A face located in an image, with the crop already extracted.
public struct DetectedFace: @unchecked Sendable {
    /// Bounding box in image pixel coordinates, origin upper-left.
    public let boundingBox: CGRect
    /// Confidence that this crop is good enough to identify from, in [0, 1]. Low values mean
    /// blurry, badly lit, or steeply angled. Used to skip wasted embedding work.
    public let captureQuality: Float
    public let crop: CGImage

    public init(boundingBox: CGRect, captureQuality: Float, crop: CGImage) {
        self.boundingBox = boundingBox
        self.captureQuality = captureQuality
        self.crop = crop
    }
}

/// The verdict for one face against one enrolled person.
public struct FaceMatch: Sendable, Equatable {
    public let personID: String
    public let similarity: Float
    public let isMatch: Bool

    public init(personID: String, similarity: Float, isMatch: Bool) {
        self.personID = personID
        self.similarity = similarity
        self.isMatch = isMatch
    }
}

/// Where a photo came from. Both sources feed the same pipeline.
public enum PhotoSource: String, Sendable, Codable {
    case glasses
    case photoLibrary
}

/// One analyzed photo. This is what gets persisted and counted.
public struct PhotoRecord: Sendable, Codable, Identifiable, Equatable {
    public let id: String
    public let source: PhotoSource
    public let capturedAt: Date
    public let faceCount: Int
    /// Best similarity seen across all faces in the photo, against the target person.
    public let bestSimilarity: Float
    public let matched: Bool
    /// Set when the user corrects the automatic verdict on the review screen. Overrides `matched`.
    public var userOverride: Bool?

    public var countsTowardTally: Bool { userOverride ?? matched }

    public init(
        id: String,
        source: PhotoSource,
        capturedAt: Date,
        faceCount: Int,
        bestSimilarity: Float,
        matched: Bool,
        userOverride: Bool? = nil
    ) {
        self.id = id
        self.source = source
        self.capturedAt = capturedAt
        self.faceCount = faceCount
        self.bestSimilarity = bestSimilarity
        self.matched = matched
        self.userOverride = userOverride
    }
}
