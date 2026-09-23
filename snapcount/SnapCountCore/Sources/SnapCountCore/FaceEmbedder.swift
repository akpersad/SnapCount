import Foundation
import CoreGraphics
import CoreML
import Vision

/// Turns an aligned face crop into a comparable vector.
///
/// Two implementations exist so the pipeline can be built and tuned before the Core ML model
/// is in place, and so the tuning harness can A/B them on real data.
public protocol FaceEmbedder: Sendable {
    var identifier: String { get }
    func embed(_ crop: CGImage) async throws -> FaceEmbedding
}

public enum FaceEmbedderError: Error, Sendable {
    case unsupportedElementType
    case emptyEmbedding
    case pixelBufferCreationFailed
    case modelOutputMissing(String)
}

/// Fallback embedder built on Vision's general-purpose image feature print.
///
/// Works today with no model to ship, but it is a *scene* similarity model rather than a face
/// embedding. It is notably weak at separating one young child from another, which is exactly
/// this project's hard case. Treat it as a scaffold for building the rest of the pipeline and
/// as the control arm when benchmarking the real model.
public struct VisionFeaturePrintEmbedder: FaceEmbedder {
    public let identifier = "vision-featureprint-v2"

    public init() {}

    public func embed(_ crop: CGImage) async throws -> FaceEmbedding {
        let request = GenerateImageFeaturePrintRequest()
        let observation = try await request.perform(on: crop)

        guard observation.elementType == .float || observation.elementType == .double else {
            throw FaceEmbedderError.unsupportedElementType
        }

        let values: [Float]
        if observation.elementType == .float {
            values = observation.data.withUnsafeBytes { raw in
                Array(raw.bindMemory(to: Float.self).prefix(observation.elementCount))
            }
        } else {
            values = observation.data.withUnsafeBytes { raw in
                raw.bindMemory(to: Double.self).prefix(observation.elementCount).map(Float.init)
            }
        }

        guard !values.isEmpty else { throw FaceEmbedderError.emptyEmbedding }
        return FaceEmbedding(values: values)
    }
}

/// Embedder backed by an ArcFace-convention Core ML model (AdaFace IR-18; see `AdaFaceIR18`).
///
/// `MLModel` prediction is thread-safe, so this is safe to share across the concurrent
/// per-photo work even though `MLModel` itself is not `Sendable`.
public final class CoreMLFaceEmbedder: FaceEmbedder, @unchecked Sendable {
    public let identifier: String

    private let model: MLModel
    private let inputName: String
    private let outputName: String
    private let inputSize: Int

    public init(
        model: MLModel,
        identifier: String,
        inputName: String,
        outputName: String,
        inputSize: Int = 112
    ) {
        self.model = model
        self.identifier = identifier
        self.inputName = inputName
        self.outputName = outputName
        self.inputSize = inputSize
    }

    public convenience init(
        contentsOf url: URL,
        identifier: String,
        inputName: String,
        outputName: String,
        inputSize: Int = 112,
        computeUnits: MLComputeUnits = .all
    ) throws {
        let configuration = MLModelConfiguration()
        // Explicit and local by construction. Core ML has no cloud path, but being deliberate
        // here documents the intent alongside the rest of the privacy controls.
        configuration.computeUnits = computeUnits
        let model = try MLModel(contentsOf: url, configuration: configuration)
        self.init(
            model: model,
            identifier: identifier,
            inputName: inputName,
            outputName: outputName,
            inputSize: inputSize)
    }

    public func embed(_ crop: CGImage) async throws -> FaceEmbedding {
        let buffer = try Self.pixelBuffer(from: crop, side: inputSize)
        let input = try MLDictionaryFeatureProvider(dictionary: [
            inputName: MLFeatureValue(pixelBuffer: buffer)
        ])
        let output = try await model.prediction(from: input)

        guard let array = output.featureValue(for: outputName)?.multiArrayValue else {
            throw FaceEmbedderError.modelOutputMissing(outputName)
        }

        var values = [Float](repeating: 0, count: array.count)
        for i in 0..<array.count { values[i] = array[i].floatValue }
        guard !values.isEmpty else { throw FaceEmbedderError.emptyEmbedding }
        return FaceEmbedding(values: values)
    }

    static func pixelBuffer(from image: CGImage, side: Int) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, side, side,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &buffer)

        guard status == kCVReturnSuccess, let buffer else {
            throw FaceEmbedderError.pixelBufferCreationFailed
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer),
                width: side, height: side,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue)
        else {
            throw FaceEmbedderError.pixelBufferCreationFailed
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return buffer
    }
}
