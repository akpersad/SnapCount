import Foundation
import CoreML

/// The contract of the pre-converted AdaFace IR-18 model fetched by `Scripts/fetch-model.sh`.
///
/// Read from the compiled model's `metadata.json` and MIL graph rather than guessed:
/// - Input `face_image`: 112x112 Image, BGR. Core ML converts from our 32BGRA buffer.
/// - The graph scales by 2/255 and biases by -1 before the first conv, so [-1, 1]
///   normalization is baked in. Feeding pre-normalized pixels would double-normalize.
/// - Output `embedding`: Float16 MultiArray [1, 512], already L2-normalized in-graph.
public enum AdaFaceIR18 {
    /// Stored in `enrollment.json`. Changing it invalidates every saved enrollment, which is
    /// the point: embeddings from different models are not comparable.
    public static let identifier = "adaface-ir18-v1"
    public static let inputName = "face_image"
    public static let outputName = "embedding"
    public static let inputSize = 112
    public static let dimension = 512

    /// Loads the model from a compiled `.mlmodelc`, or compiles a `.mlpackage` first.
    ///
    /// The app bundle ships the compiled form (Xcode does that at build time). The compile
    /// path exists for the command-line tools and tests, which see the raw package.
    public static func embedder(
        contentsOf url: URL,
        computeUnits: MLComputeUnits = .all
    ) async throws -> CoreMLFaceEmbedder {
        let compiledURL: URL
        if url.pathExtension == "mlmodelc" {
            compiledURL = url
        } else {
            compiledURL = try await MLModel.compileModel(at: url)
        }
        return try CoreMLFaceEmbedder(
            contentsOf: compiledURL,
            identifier: identifier,
            inputName: inputName,
            outputName: outputName,
            inputSize: inputSize,
            computeUnits: computeUnits)
    }
}
