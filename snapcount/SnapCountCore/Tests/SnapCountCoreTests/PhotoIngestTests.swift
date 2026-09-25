import Testing
import Foundation
@testable import SnapCountCore

struct PhotoIngestTests {

    static let today = Date(timeIntervalSince1970: 1_790_000_000)
    static var yesterday: Date { today.addingTimeInterval(-86_400) }

    static func record(_ id: String, source: PhotoSource = .photoLibrary, at date: Date = today) -> PhotoRecord {
        PhotoRecord(
            id: id, source: source, capturedAt: date,
            faceCount: 1, bestSimilarity: 0.7, matched: true)
    }

    static func person(enrolledAt: Date = today) -> EnrolledPerson {
        EnrolledPerson(
            id: "daughter", displayName: "Test",
            embedding: FaceEmbedding(values: [1, 0]),
            enrolledAt: enrolledAt, sampleCount: 10, matchThreshold: 0.5)
    }

    static func temporaryStore() -> PhotoRecordStore {
        PhotoRecordStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("records-\(UUID().uuidString).json"))
    }

    @Test("Only assets without a record are analyzed, oldest first")
    func analyzesOnlyNewAssets() {
        let assets = [
            LibraryAsset(id: "c", createdAt: Self.today.addingTimeInterval(30)),
            LibraryAsset(id: "a", createdAt: Self.today),
            LibraryAsset(id: "b", createdAt: Self.today.addingTimeInterval(10)),
        ]
        let plan = IngestPlan(assets: assets, existing: [Self.record("a")], day: Self.today)
        #expect(plan.toAnalyze.map(\.id) == ["b", "c"])
    }

    @Test("A glasses capture saved to the library is not counted twice")
    func dedupesAgainstGlasses() {
        let assets = [LibraryAsset(id: "saved-capture", createdAt: Self.today)]
        let existing = [Self.record("saved-capture", source: .glasses)]
        let plan = IngestPlan(assets: assets, existing: existing, day: Self.today)
        #expect(plan.toAnalyze.isEmpty)
    }

    @Test("Deleted library photos drop out; glasses and older records stay")
    func removesDeletedLibraryPhotos() {
        let existing = [
            Self.record("kept"),
            Self.record("deleted"),
            Self.record("capture", source: .glasses),
            Self.record("yesterday", at: Self.yesterday),
        ]
        let assets = [LibraryAsset(id: "kept", createdAt: Self.today)]
        let plan = IngestPlan(assets: assets, existing: existing, day: Self.today)
        #expect(plan.removedIDs == ["deleted"])
    }

    @Test("Records round-trip and are discarded after re-enrollment")
    func storeRoundTripAndInvalidation() throws {
        let store = Self.temporaryStore()
        defer { try? store.deleteAll() }
        let person = Self.person()

        try store.save(RecordLog(enrollmentFingerprint: person.fingerprint, records: [Self.record("a")]), now: Self.today)
        #expect(try store.load(for: person).records.map(\.id) == ["a"])

        let reenrolled = Self.person(enrolledAt: Self.today.addingTimeInterval(60))
        #expect(try store.load(for: reenrolled).records.isEmpty)
    }

    @Test("Records past retention are pruned on save")
    func prunesOldRecords() throws {
        let store = Self.temporaryStore()
        defer { try? store.deleteAll() }
        let person = Self.person()
        let old = Self.record("old", at: Self.today.addingTimeInterval(-PhotoRecordStore.retention - 1))

        try store.save(RecordLog(enrollmentFingerprint: person.fingerprint, records: [old, Self.record("new")]), now: Self.today)
        #expect(try store.load(for: person).records.map(\.id) == ["new"])
    }
}

struct CaptureStoreTests {

    static func temporaryStore() -> CaptureStore {
        CaptureStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("captures-\(UUID().uuidString)", isDirectory: true))
    }

    @Test("A saved capture is listed for its day, with its time, and resolves back to its file")
    func roundTrip() throws {
        let store = Self.temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let takenAt = PhotoIngestTests.today

        let id = try store.save(Data([1, 2, 3]), capturedAt: takenAt)
        let assets = store.assets(on: takenAt)

        #expect(assets.map(\.id) == [id])
        #expect(assets.first?.source == .glasses)
        #expect(abs(assets.first!.createdAt.timeIntervalSince(takenAt)) < 0.001)
        #expect(store.assets(on: PhotoIngestTests.yesterday).isEmpty)
        #expect(try Data(contentsOf: #require(store.fileURL(for: id))) == Data([1, 2, 3]))
    }

    @Test("Capture files are excluded from backup")
    func excludedFromBackup() throws {
        let store = Self.temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let url = try #require(store.fileURL(for: store.save(Data([0]))))
        #expect(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    @Test("Library IDs and path tricks do not resolve to capture files")
    func rejectsForeignIDs() {
        let store = Self.temporaryStore()
        #expect(store.fileURL(for: "ABC-123/L0/001") == nil)
        #expect(store.fileURL(for: "glasses/../records.json") == nil)
    }

    @Test("Captures are planned alongside library photos, and never removed as deleted")
    func plannedWithLibrary() {
        let day = PhotoIngestTests.today
        let capture = LibraryAsset(id: "glasses/1-a.jpg", createdAt: day, source: .glasses)
        let photo = LibraryAsset(id: "lib", createdAt: day.addingTimeInterval(5))
        let analyzedCapture = PhotoIngestTests.record("glasses/0-b.jpg", source: .glasses)

        let plan = IngestPlan(assets: [photo, capture], existing: [analyzedCapture], day: day)
        #expect(plan.toAnalyze.map(\.id) == ["glasses/1-a.jpg", "lib"])
        #expect(plan.removedIDs.isEmpty)
    }
}
