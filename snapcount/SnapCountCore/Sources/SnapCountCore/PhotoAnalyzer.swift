import Foundation
import CoreGraphics

/// Runs one photo end to end: detect faces, embed them, compare against the enrolled person.
///
/// Deliberately has no opinion about where the image came from. Glasses captures and photo
/// library assets go through exactly the same path, so the count cannot disagree with itself
/// depending on source.
public struct PhotoAnalyzer: Sendable {
    let detector: FaceDetector
    let embedder: any FaceEmbedder

    /// Cosine similarity at or above which a face is considered a match.
    ///
    /// There is no universally correct value. It must be tuned against real photographs using
    /// the sweep in `ThresholdTuner`, biased toward precision: an undercount is a mildly wrong
    /// number, whereas a false positive means the app counted somebody else's child.
    public var matchThreshold: Float

    /// Used only until the enrollment has been tuned.
    public static let defaultMatchThreshold: Float = 0.65

    public init(
        detector: FaceDetector = FaceDetector(),
        embedder: any FaceEmbedder,
        matchThreshold: Float = PhotoAnalyzer.defaultMatchThreshold
    ) {
        self.detector = detector
        self.embedder = embedder
        self.matchThreshold = matchThreshold
    }

    /// Analyzes one image against one enrolled person.
    public func analyze(
        image: CGImage,
        id: String,
        source: PhotoSource,
        capturedAt: Date,
        target: EnrolledPerson
    ) async throws -> PhotoRecord {
        let faces = try await detector.detectFaces(in: image)

        var best: Float = -1
        for face in faces {
            guard let embedding = try? await embedder.embed(face.crop) else { continue }
            best = max(best, embedding.similarity(to: target.embedding))
        }

        return PhotoRecord(
            id: id,
            source: source,
            capturedAt: capturedAt,
            faceCount: faces.count,
            bestSimilarity: best,
            matched: best >= matchThreshold)
    }

    /// Per-face verdicts for a single image. Used by the review screen and the tuning sweep,
    /// where the distribution of scores matters and not just the final boolean.
    public func scoreFaces(
        image: CGImage,
        against target: EnrolledPerson
    ) async throws -> [Float] {
        let faces = try await detector.detectFaces(in: image)
        var scores: [Float] = []
        for face in faces {
            guard let embedding = try? await embedder.embed(face.crop) else { continue }
            scores.append(embedding.similarity(to: target.embedding))
        }
        return scores
    }
}

/// Rolls analyzed photos up into the number shown on the glasses.
public struct DailyTally: Sendable {
    public var calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// Photos from `day` that count toward the tally, honouring any user corrections.
    public func count(in records: [PhotoRecord], on day: Date = Date()) -> Int {
        records.filter {
            $0.countsTowardTally && calendar.isDate($0.capturedAt, inSameDayAs: day)
        }.count
    }

    /// Total photos considered that day, matched or not. The denominator in "7 of 23".
    public func total(in records: [PhotoRecord], on day: Date = Date()) -> Int {
        records.filter { calendar.isDate($0.capturedAt, inSameDayAs: day) }.count
    }

    /// Photos whose score sits close to the threshold, where the model is least confident.
    /// These are the ones worth surfacing on the review screen first.
    public func uncertain(
        in records: [PhotoRecord],
        threshold: Float,
        margin: Float = 0.08,
        on day: Date = Date()
    ) -> [PhotoRecord] {
        records
            .filter { calendar.isDate($0.capturedAt, inSameDayAs: day) }
            .filter { abs($0.bestSimilarity - threshold) <= margin }
            .sorted { abs($0.bestSimilarity - threshold) < abs($1.bestSimilarity - threshold) }
    }
}
