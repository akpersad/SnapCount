import Foundation
import Observation
import SnapCountCore

/// App-wide state: the loaded model and the saved enrollment. Screens read from here rather
/// than each loading their own copy of a 50 MB model.
@MainActor
@Observable
final class AppModel {
    private(set) var embedder: CoreMLFaceEmbedder?
    private(set) var modelStatus: Status = .checking

    private(set) var enrollment: Enrollment?
    private(set) var enrollmentStatus: Status = .checking

    /// The one person being counted, if enrollment is valid for the current model.
    var person: EnrolledPerson? {
        guard let enrollment, enrollment.embedderIdentifier == AdaFaceIR18.identifier else {
            return nil
        }
        return enrollment.people.first
    }

    func load() async {
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

    func save(_ person: EnrolledPerson) throws {
        let enrollment = Enrollment(embedderIdentifier: AdaFaceIR18.identifier, people: [person])
        try Self.store().save(enrollment)
        reloadEnrollment()
    }

    func deleteEnrollment() throws {
        try Self.store().deleteAll()
        reloadEnrollment()
    }

    private func reloadEnrollment() {
        do {
            enrollment = try Self.store().load()
        } catch {
            enrollment = nil
            enrollmentStatus = .problem(error.localizedDescription)
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
