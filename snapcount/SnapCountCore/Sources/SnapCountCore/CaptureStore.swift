import Foundation

/// Photos taken with the glasses, kept as files in the app container.
///
/// Not written to the Photos library: that would put them in iCloud Photos sync (see
/// `docs/privacy-architecture.md`, section 5). Excluded from backup for the same reason. These
/// are the only copy, so the app never deletes them; exporting is a separate, explicit action.
///
/// The capture time is encoded in the file name so listing a day needs no metadata reads, and
/// the record ID is `glasses/<file name>` so it can never collide with a PhotoKit identifier.
public struct CaptureStore: Sendable {
    public let directory: URL

    static let idPrefix = "glasses/"

    public init(directory: URL) {
        self.directory = directory
    }

    public static func defaultDirectory(fileManager: FileManager = .default) throws -> URL {
        try EnrollmentStore.defaultURL(fileManager: fileManager)
            .deletingLastPathComponent()
            .appendingPathComponent("Captures", isDirectory: true)
    }

    /// Writes one capture and returns its record ID.
    @discardableResult
    public func save(_ data: Data, capturedAt: Date = Date(), fileExtension: String = "jpg") throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try excludeFromBackup(directory)

        let millis = Int64((capturedAt.timeIntervalSince1970 * 1000).rounded())
        let name = "\(millis)-\(UUID().uuidString.prefix(8)).\(fileExtension)"
        let url = directory.appendingPathComponent(name)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try excludeFromBackup(url)
        return Self.idPrefix + name
    }

    /// Captures taken on `day`, as ingest assets.
    public func assets(on day: Date, calendar: Calendar = .current) -> [LibraryAsset] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.compactMap { name in
            guard let date = Self.captureDate(fromFileName: name),
                  calendar.isDate(date, inSameDayAs: day)
            else { return nil }
            return LibraryAsset(id: Self.idPrefix + name, createdAt: date, source: .glasses)
        }
    }

    /// The file behind a record ID, or nil if the ID is not a capture.
    public func fileURL(for id: String) -> URL? {
        guard id.hasPrefix(Self.idPrefix) else { return nil }
        let name = String(id.dropFirst(Self.idPrefix.count))
        // IDs come from our own file names, but never let one walk out of the directory.
        guard !name.contains("/"), !name.hasPrefix(".") else { return nil }
        return directory.appendingPathComponent(name)
    }

    public var count: Int {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { Self.captureDate(fromFileName: $0) != nil }
            .count
    }

    static func captureDate(fromFileName name: String) -> Date? {
        guard let millis = name.split(separator: "-").first.flatMap({ Int64($0) }) else { return nil }
        return Date(timeIntervalSince1970: Double(millis) / 1000)
    }

    private func excludeFromBackup(_ url: URL) throws {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}
