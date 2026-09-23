import Foundation
import SnapCountCore

/// Locates and loads the embedding model bundled with the app.
enum RecognitionModel {
    /// Xcode compiles the `.mlpackage` into this at build time.
    static var bundledURL: URL? {
        Bundle.main.url(forResource: "AdaFace_IR18", withExtension: "mlmodelc")
    }

    static func loadEmbedder() async throws -> CoreMLFaceEmbedder {
        guard let url = bundledURL else { throw RecognitionModelError.notBundled }
        return try await AdaFaceIR18.embedder(contentsOf: url)
    }
}

enum RecognitionModelError: LocalizedError {
    case notBundled

    var errorDescription: String? {
        switch self {
        case .notBundled:
            "The recognition model is missing from this build. Run Scripts/fetch-model.sh and rebuild."
        }
    }
}
