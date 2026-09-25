import Foundation
import Observation
import SnapCountCore

/// App-wide state: the loaded model, the saved enrollment, and today's count. Screens read
/// from here rather than each loading their own copy of a 50 MB model.
@MainActor
@Observable
final class AppModel {
    private(set) var embedder: CoreMLFaceEmbedder?
    private(set) var modelStatus: Status = .checking

    private(set) var enrollment: Enrollment?
    private(set) var enrollmentStatus: Status = .checking

    let library = LibraryIngest()
    let glasses = GlassesController()

    /// The one person being counted, if enrollment is valid for the current model.
    var person: EnrolledPerson? {
        guard let enrollment, enrollment.embedderIdentifier == AdaFaceIR18.identifier else {
            return nil
        }
        return enrollment.people.first
    }

    /// Runs from the first screen's `.task`, which is after `PrivacyChecks` in `SnapCountApp.init`.
    /// Not from `init`: `@State` initializers run before the App's `init` body.
    func load() async {
        configureGlassesOnce()
        if embedder == nil {
            do {
                embedder = try await RecognitionModel.loadEmbedder()
                modelStatus = .ready("Ready")
            } catch {
                modelStatus = .problem(error.localizedDescription)
            }
        }
        reloadEnrollment()
    }

    private var glassesConfigured = false

    private func configureGlassesOnce() {
        guard !glassesConfigured else { return }
        glassesConfigured = true
        glasses.configure()
        glasses.onPhoto = { [weak self] data in try self?.library.addCapture(data) }
        observeHUD()
    }

    /// The Meta AI app can relaunch SnapCount through its URL before the first screen appears,
    /// so this configures the SDK itself if needed. `PrivacyChecks` has run by then either way.
    func handle(_ url: URL) async {
        configureGlassesOnce()
        await glasses.handle(url)
    }

    /// Keeps the glasses HUD in step with the count. Re-arms itself after every change.
    private func observeHUD() {
        // Only the inputs are read inside tracking, so the HUD's own state cannot re-trigger it.
        let (count, name, checking) = withObservationTracking {
            (library.todayCount, person?.displayName, library.isScanning)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeHUD() }
        }
        glasses.updateHUD(count: count, name: name, checking: checking)
    }

    func save(_ person: EnrolledPerson) throws {
        let enrollment = Enrollment(embedderIdentifier: AdaFaceIR18.identifier, people: [person])
        try Self.store().save(enrollment)
        reloadEnrollment()
    }

    func deleteEnrollment() throws {
        try Self.store().deleteAll()
        // Records say which photos show her. They go with the enrollment.
        library.clearRecords()
        reloadEnrollment()
    }

    private func reloadEnrollment() {
        do {
            enrollment = try Self.store().load()
        } catch {
            enrollment = nil
            enrollmentStatus = .problem(error.localizedDescription)
            library.configure(embedder: embedder, person: nil)
            return
        }

        if let enrollment, enrollment.embedderIdentifier != AdaFaceIR18.identifier {
            // Embeddings from another model are not comparable. Counting with them would
            // produce confident nonsense, so treat this as not enrolled.
            enrollmentStatus = .problem("Made with an older model. Set up again.")
        } else if let person {
            enrollmentStatus = .ready("\(person.displayName), \(person.sampleCount) photos")
        } else {
            enrollmentStatus = .problem("Not set up yet")
        }
        library.configure(embedder: embedder, person: person)
    }

    private static func store() throws -> EnrollmentStore {
        try EnrollmentStore(fileURL: EnrollmentStore.defaultURL())
    }
}

enum Status: Equatable {
    case checking
    case ready(String)
    case problem(String)
}
