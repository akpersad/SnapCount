import Foundation
import Observation
import Photos
import UIKit
import SnapCountCore

/// Counts today's photos from both sources (WORKPLAN Phases 4 and 5d). Enumerates the photo
/// library and the glasses captures in `CaptureStore`, runs every photo without a record
/// through one `PhotoAnalyzer`, and keeps the results in a `PhotoRecordStore` so each photo is
/// analyzed once.
///
/// Reruns whenever the library changes, a capture arrives, the app returns to the foreground,
/// or the day rolls over, so a new photo lands in the count within seconds.
@MainActor
@Observable
final class LibraryIngest {
    enum Access: Equatable {
        case unknown, full, limited, denied
    }

    private(set) var access: Access = .unknown
    private(set) var records: [PhotoRecord] = []
    /// Non-nil while a scan is working through new photos.
    private(set) var progress: (done: Int, total: Int)?
    /// Photos from today that are only in iCloud. Never downloaded, by design.
    private(set) var cloudOnlyCount = 0
    /// Photos from today that failed to decode or analyze. Not recorded, so the next scan
    /// retries them rather than a transient error permanently dropping a photo of her.
    private(set) var failedCount = 0
    private(set) var lastError: String?

    private var analyzer: PhotoAnalyzer?
    private var person: EnrolledPerson?
    private var store: PhotoRecordStore?
    private let captures: CaptureStore? = try? CaptureStore(directory: CaptureStore.defaultDirectory())
    private var scanTask: Task<Void, Never>?
    private var rescanRequested = false
    private var observer: LibraryObserver?
    /// Bumped by `stop()` so a cancelled scan cannot touch the state of the one that replaced it.
    private var generation = 0

    private let tally = DailyTally()

    var todayCount: Int { tally.count(in: records) }
    var todayTotal: Int { tally.total(in: records) }
    var isScanning: Bool { progress != nil }

    /// Starts counting for `person`, or stops if nil. Safe to call repeatedly; only a change of
    /// enrollment resets anything.
    func configure(embedder: CoreMLFaceEmbedder?, person: EnrolledPerson?) {
        guard let embedder, let person else {
            stop()
            return
        }
        guard person.fingerprint != self.person?.fingerprint else { return }

        stop()
        self.person = person
        analyzer = PhotoAnalyzer(
            embedder: embedder,
            matchThreshold: person.matchThreshold ?? PhotoAnalyzer.defaultMatchThreshold)
        do {
            let store = try PhotoRecordStore(fileURL: PhotoRecordStore.defaultURL())
            self.store = store
            records = try store.load(for: person).records
        } catch {
            records = []
            lastError = error.localizedDescription
        }
        refreshAccess()
        if access == .full || access == .limited { startObserving() }
        requestScan()
    }

    /// Asks for photo access. Only called from an explicit tap, never on launch.
    func requestAccess() async {
        _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        refreshAccess()
        if access == .full || access == .limited {
            startObserving()
            requestScan()
        }
    }

    /// Queues a scan. If one is running, it goes around once more when it finishes, so a photo
    /// taken mid-scan is never missed.
    func requestScan() {
        guard analyzer != nil else { return }
        refreshAccess()
        if scanTask != nil {
            rescanRequested = true
            return
        }
        let generation = generation
        scanTask = Task { await runScans(generation) }
    }

    /// Keeps a glasses capture and counts it. The file is written before anything else, so a
    /// photo is never lost even if analysis fails or no one is enrolled yet.
    func addCapture(_ data: Data, capturedAt: Date = Date()) throws {
        guard let captures else { throw CocoaError(.fileWriteUnknown) }
        try captures.save(data, capturedAt: capturedAt)
        requestScan()
    }

    func clearRecords() {
        stop()
        try? PhotoRecordStore(fileURL: PhotoRecordStore.defaultURL()).deleteAll()
    }

    private func stop() {
        generation += 1
        scanTask?.cancel()
        scanTask = nil
        rescanRequested = false
        progress = nil
        observer = nil
        analyzer = nil
        person = nil
        store = nil
        records = []
        cloudOnlyCount = 0
        failedCount = 0
    }

    private func refreshAccess() {
        access = switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized: .full
        case .limited: .limited
        case .denied, .restricted: .denied
        default: .unknown
        }
    }

    private func startObserving() {
        guard observer == nil else { return }
        observer = LibraryObserver { [weak self] in
            Task { @MainActor in self?.requestScan() }
        }
    }

    private func runScans(_ generation: Int) async {
        // Lets a scan that is already underway finish if the user switches apps.
        let background = UIApplication.shared.beginBackgroundTask(withName: "SnapCount library scan")
        defer {
            UIApplication.shared.endBackgroundTask(background)
            if generation == self.generation {
                scanTask = nil
                progress = nil
            }
        }

        repeat {
            rescanRequested = false
            await scanOnce(generation)
        } while rescanRequested && generation == self.generation
    }

    private func scanOnce(_ generation: Int) async {
        guard let analyzer, let person, let store else { return }
        let day = Date()
        let worker = LibraryWorker(captures: captures)
        let libraryReadable = access == .full || access == .limited
        let libraryAssets = libraryReadable ? await worker.assets(on: day) : []
        guard generation == self.generation else { return }
        let captureAssets = captures?.assets(on: day) ?? []
        // Without library access, leave library records out of the plan so they are not
        // mistaken for deleted photos.
        let plan = IngestPlan(
            assets: libraryAssets + captureAssets,
            existing: libraryReadable ? records : records.filter { $0.source != .photoLibrary },
            day: day)

        if !plan.removedIDs.isEmpty {
            records.removeAll { plan.removedIDs.contains($0.id) }
            save(store, person)
        }
        guard !plan.toAnalyze.isEmpty else {
            cloudOnlyCount = 0
            failedCount = 0
            return
        }

        var cloudOnly = 0
        var failed = 0
        progress = (0, plan.toAnalyze.count)
        for (index, asset) in plan.toAnalyze.enumerated() {
            let outcome = await worker.analyze(asset, with: analyzer, target: person)
            guard generation == self.generation else { return }
            switch outcome {
            case .record(let record):
                records.append(record)
            case .notOnDevice:
                cloudOnly += 1
            case .failed:
                failed += 1
            }
            progress = (index + 1, plan.toAnalyze.count)
            if (index + 1).isMultiple(of: 10) { save(store, person) }
        }
        cloudOnlyCount = cloudOnly
        failedCount = failed
        save(store, person)
    }

    private func save(_ store: PhotoRecordStore, _ person: EnrolledPerson) {
        do {
            try store.save(RecordLog(enrollmentFingerprint: person.fingerprint, records: records))
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}

/// The PhotoKit side, kept off the main actor. Works in `localIdentifier` strings because
/// `PHAsset` is not `Sendable`.
struct LibraryWorker: Sendable {
    let captures: CaptureStore?

    enum Outcome: Sendable {
        case record(PhotoRecord)
        case notOnDevice
        case failed
    }

    /// Today's still photos. Screenshots are skipped: they are not photos of anyone, and a
    /// screenshot of a photo of her would count twice.
    nonisolated func assets(on day: Date, calendar: Calendar = .current) async -> [LibraryAsset] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }

        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "mediaType == %d AND creationDate >= %@ AND creationDate < %@ AND NOT ((mediaSubtypes & %d) != 0)",
            PHAssetMediaType.image.rawValue, start as NSDate, end as NSDate,
            PHAssetMediaSubtype.photoScreenshot.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        var assets: [LibraryAsset] = []
        PHAsset.fetchAssets(with: options).enumerateObjects { asset, _, _ in
            if let created = asset.creationDate {
                assets.append(LibraryAsset(id: asset.localIdentifier, createdAt: created))
            }
        }
        return assets
    }

    nonisolated func analyze(
        _ asset: LibraryAsset,
        with analyzer: PhotoAnalyzer,
        target: EnrolledPerson
    ) async -> Outcome {
        let data: Data?
        switch asset.source {
        case .photoLibrary:
            data = await imageData(for: asset.id)
        case .glasses:
            data = captures?.fileURL(for: asset.id).flatMap { try? Data(contentsOf: $0) }
        }
        guard let data else { return asset.source == .photoLibrary ? .notOnDevice : .failed }
        guard let image = ImageLoading.image(from: data),
              let record = try? await analyzer.analyze(
                image: image, id: asset.id, source: asset.source,
                capturedAt: asset.createdAt, target: target)
        else { return .failed }
        return .record(record)
    }

    /// The photo's bytes, only if they are already on the phone.
    ///
    /// `isNetworkAccessAllowed = false` is load-bearing: with iCloud Photos on, a request that
    /// allows network would quietly download originals, which is both egress and, at sea, a
    /// metered connection. Photos taken on this phone today are always local.
    private nonisolated func imageData(for id: String) async -> Data? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
            return nil
        }
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .highQualityFormat
        options.version = .current

        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
    }
}

/// Bridges PhotoKit change notifications, which arrive on an arbitrary queue.
private final class LibraryObserver: NSObject, PHPhotoLibraryChangeObserver, @unchecked Sendable {
    private let onChange: @Sendable () -> Void

    init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        super.init()
        PHPhotoLibrary.shared().register(self)
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        onChange()
    }
}
