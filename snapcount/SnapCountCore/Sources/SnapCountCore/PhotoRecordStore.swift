import Foundation

/// Every analyzed photo, persisted so a relaunch does not re-run recognition over the whole day.
///
/// Records hold similarity scores and photo identifiers, not embeddings or images. They are
/// still personal (which photos show her, and when), so they get the same container-only,
/// no-backup handling as enrollment.
public struct RecordLog: Sendable, Codable, Equatable {
    /// Which enrollment produced these scores. Scores against one centroid mean nothing
    /// against another, so a mismatch means every record must be recomputed.
    public var enrollmentFingerprint: String
    public var records: [PhotoRecord]

    public init(enrollmentFingerprint: String, records: [PhotoRecord] = []) {
        self.enrollmentFingerprint = enrollmentFingerprint
        self.records = records
    }
}

extension EnrolledPerson {
    /// Changes whenever the person is re-enrolled, which is the only way the centroid or the
    /// threshold can change.
    public var fingerprint: String {
        "\(id)@\(enrolledAt.timeIntervalSinceReferenceDate)"
    }
}

public struct PhotoRecordStore: Sendable {
    public let fileURL: URL

    /// How long records are kept. Long enough to cover the whole trip; the count itself only
    /// ever looks at today.
    public static let retention: TimeInterval = 30 * 86_400

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultURL(fileManager: FileManager = .default) throws -> URL {
        try EnrollmentStore.defaultURL(fileManager: fileManager)
            .deletingLastPathComponent()
            .appendingPathComponent("records.json")
    }

    /// The saved log, or an empty one if nothing is saved or it belongs to another enrollment.
    public func load(for person: EnrolledPerson) throws -> RecordLog {
        let empty = RecordLog(enrollmentFingerprint: person.fingerprint)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return empty }
        let log = try JSONDecoder().decode(RecordLog.self, from: Data(contentsOf: fileURL))
        return log.enrollmentFingerprint == person.fingerprint ? log : empty
    }

    public func save(_ log: RecordLog, now: Date = Date()) throws {
        var log = log
        let cutoff = now.addingTimeInterval(-Self.retention)
        log.records.removeAll { $0.capturedAt < cutoff }

        let data = try JSONEncoder().encode(log)
        // Not `.complete`: ingest may still be finishing a batch for a few seconds after the
        // phone locks. Scores are not biometric; the enrollment file keeps `.complete`.
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var url = fileURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    public func deleteAll() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}

/// A photo library asset reduced to what ingest planning needs. Keeps PhotoKit out of the
/// core so the planning rules are testable.
public struct LibraryAsset: Sendable, Equatable {
    public let id: String
    public let createdAt: Date

    public init(id: String, createdAt: Date) {
        self.id = id
        self.createdAt = createdAt
    }
}

/// Decides which library photos still need analyzing and which records are stale.
///
/// Record IDs are the dedupe key across sources. Library records use the asset's
/// `localIdentifier`. If a glasses capture is ever saved to the library (Phase 5d), its record
/// must take the new asset's `localIdentifier` as its ID, and ingest will then skip it here
/// rather than count the same photo twice.
public struct IngestPlan: Sendable, Equatable {
    /// Assets with no record yet, oldest first so the count climbs in the order photos were taken.
    public let toAnalyze: [LibraryAsset]
    /// Library records whose asset is gone from today's library, usually because the photo was
    /// deleted. Glasses records are never removed here.
    public let removedIDs: Set<String>

    public init(assets: [LibraryAsset], existing: [PhotoRecord], day: Date, calendar: Calendar = .current) {
        let known = Set(existing.map(\.id))
        toAnalyze = assets
            .filter { !known.contains($0.id) }
            .sorted { $0.createdAt < $1.createdAt }

        let present = Set(assets.map(\.id))
        removedIDs = Set(existing
            .filter { $0.source == .photoLibrary && calendar.isDate($0.capturedAt, inSameDayAs: day) }
            .map(\.id)
            .filter { !present.contains($0) })
    }
}
