import Foundation
import CoreGraphics

/// A person the app can recognize, reduced to a single reference vector.
///
/// Reference photographs are used to compute `embedding` and are then discarded. What persists
/// is a unit vector, not an image.
public struct EnrolledPerson: Sendable, Codable, Identifiable, Equatable {
    public let id: String
    public var displayName: String
    public var embedding: FaceEmbedding
    public var enrolledAt: Date
    /// How many face crops went into the centroid. More samples across varied angles and
    /// lighting means a more robust reference.
    public var sampleCount: Int

    public init(
        id: String,
        displayName: String,
        embedding: FaceEmbedding,
        enrolledAt: Date,
        sampleCount: Int
    ) {
        self.id = id
        self.displayName = displayName
        self.embedding = embedding
        self.enrolledAt = enrolledAt
        self.sampleCount = sampleCount
    }
}

/// What the enrolled set was built with. Embeddings from different models are not comparable,
/// so this is recorded to catch a model swap that would otherwise silently produce nonsense.
public struct Enrollment: Sendable, Codable, Equatable {
    public var embedderIdentifier: String
    public var people: [EnrolledPerson]

    public init(embedderIdentifier: String, people: [EnrolledPerson] = []) {
        self.embedderIdentifier = embedderIdentifier
        self.people = people
    }

    public func person(id: String) -> EnrolledPerson? {
        people.first { $0.id == id }
    }
}

public enum EnrollmentError: Error, Sendable {
    case noUsableFaces
    case embedderMismatch(stored: String, current: String)
}

/// Persists enrollment to the app container, excluded from backup.
///
/// Backup exclusion is deliberate: an embedding is biometric data, and the default behaviour
/// would sync it to iCloud. See `docs/privacy-architecture.md`.
public struct EnrollmentStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Default location: Application Support, which is not user-visible and not shared.
    public static func defaultURL(fileManager: FileManager = .default) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true)
        let directory = base.appendingPathComponent("SnapCount", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("enrollment.json")
    }

    public func load() throws -> Enrollment? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(Enrollment.self, from: data)
    }

    public func save(_ enrollment: Enrollment) throws {
        let data = try JSONEncoder().encode(enrollment)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        try excludeFromBackup()
    }

    public func deleteAll() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    private func excludeFromBackup() throws {
        var url = fileURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}

/// Builds a reference vector for one person from a set of photographs.
public struct Enroller: Sendable {
    let detector: FaceDetector
    let embedder: any FaceEmbedder

    public init(detector: FaceDetector = FaceDetector(), embedder: any FaceEmbedder) {
        self.detector = detector
        self.embedder = embedder
    }

    /// Detects the largest face in each reference image, embeds it, and averages the results.
    ///
    /// Largest-face rather than all-faces because reference photos frequently contain other
    /// people. Averaging a sibling into the centroid would poison the reference in a way that
    /// is very hard to notice later.
    public func enroll(
        id: String,
        displayName: String,
        referenceImages: [CGImage],
        now: Date = Date()
    ) async throws -> EnrolledPerson {
        var embeddings: [FaceEmbedding] = []

        for image in referenceImages {
            let faces = try await detector.detectFaces(in: image)
            guard let largest = faces.max(by: {
                $0.boundingBox.width * $0.boundingBox.height
                    < $1.boundingBox.width * $1.boundingBox.height
            }) else { continue }

            if let embedding = try? await embedder.embed(largest.crop) {
                embeddings.append(embedding)
            }
        }

        guard let centroid = FaceEmbedding.centroid(of: embeddings) else {
            throw EnrollmentError.noUsableFaces
        }

        return EnrolledPerson(
            id: id,
            displayName: displayName,
            embedding: centroid,
            enrolledAt: now,
            sampleCount: embeddings.count)
    }
}
