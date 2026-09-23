import Foundation
import CoreGraphics
import Vision

/// Finds faces in an image and returns aligned, square crops ready for embedding.
///
/// Uses Apple Vision, which runs entirely on-device. No model ships for this stage and
/// nothing leaves the process.
///
/// Alignment is done with a similarity transform that maps the two detected eye centers onto
/// the canonical ArcFace reference positions. That is the preprocessing the whole ArcFace-
/// convention family is trained with, AdaFace included, so matching it is worth real accuracy.
/// It also avoids depending on
/// Vision's `roll` sign convention, which is not documented clearly enough to trust blind.
public struct FaceDetector: Sendable {

    /// Faces below this quality are discarded before we spend an embedding on them.
    /// Vision's capture-quality score is a rough proxy for blur, lighting, and pose. Tuned low
    /// on purpose: on a moving ship with a moving child, most frames are imperfect.
    public var minimumCaptureQuality: Float

    /// Faces smaller than this fraction of the image's shorter edge are ignored. Filters out
    /// background strangers, which on a crowded ship is most of the faces in frame.
    public var minimumRelativeSize: CGFloat

    /// Faces turned further than this from camera-facing are discarded. Embeddings degrade
    /// sharply in profile, and a bad embedding is worse than none because it yields a
    /// confident wrong answer rather than an abstention.
    public var maximumYawDegrees: Double

    /// Align crops onto canonical eye positions when landmarks are available. Falls back to a
    /// plain padded square when they are not.
    public var alignsToLandmarks: Bool

    /// Padding beyond Vision's tight box, used only by the unaligned fallback path.
    public var cropPadding: CGFloat

    /// Edge length of the square crop handed to the embedder. 112 is the input size shared by
    /// the ArcFace-convention models: MobileFaceNet, ArcFace, and AdaFace.
    public var outputSize: Int

    public init(
        minimumCaptureQuality: Float = 0.25,
        minimumRelativeSize: CGFloat = 0.06,
        maximumYawDegrees: Double = 45,
        alignsToLandmarks: Bool = true,
        cropPadding: CGFloat = 0.25,
        outputSize: Int = 112
    ) {
        self.minimumCaptureQuality = minimumCaptureQuality
        self.minimumRelativeSize = minimumRelativeSize
        self.maximumYawDegrees = maximumYawDegrees
        self.alignsToLandmarks = alignsToLandmarks
        self.cropPadding = cropPadding
        self.outputSize = outputSize
    }

    /// Canonical ArcFace eye positions for a 112x112 crop, in upper-left-origin coordinates.
    /// Scaled proportionally if `outputSize` differs.
    static let canonicalLeftEye = CGPoint(x: 38.2946, y: 51.6963)
    static let canonicalRightEye = CGPoint(x: 73.5318, y: 51.5014)
    static let canonicalSize: CGFloat = 112

    public func detectFaces(in image: CGImage) async throws -> [DetectedFace] {
        // The capture-quality request yields boxes, quality, and pose in a single pass.
        let qualityRequest = DetectFaceCaptureQualityRequest()
        let observations = try await qualityRequest.perform(on: image)

        let imageSize = CGSize(width: image.width, height: image.height)
        let shortEdge = min(imageSize.width, imageSize.height)

        // Cheap filters first so landmark detection only runs on faces we might actually use.
        var survivors: [(observation: FaceObservation, quality: Float, box: CGRect)] = []
        for observation in observations {
            let quality = observation.captureQuality?.score ?? 0
            guard quality >= minimumCaptureQuality else { continue }

            let yawDegrees = abs(observation.yaw.converted(to: .degrees).value)
            guard yawDegrees <= maximumYawDegrees else { continue }

            let box = observation.boundingBox.toImageCoordinates(imageSize, origin: .upperLeft)
            guard min(box.width, box.height) >= shortEdge * minimumRelativeSize else { continue }

            survivors.append((observation, quality, box))
        }
        guard !survivors.isEmpty else { return [] }

        var landmarked: [FaceObservation] = []
        if alignsToLandmarks {
            var landmarkRequest = DetectFaceLandmarksRequest()
            landmarkRequest.inputFaceObservations = survivors.map(\.observation)
            landmarked = (try? await landmarkRequest.perform(on: image)) ?? []
        }

        var results: [DetectedFace] = []
        for (index, survivor) in survivors.enumerated() {
            // Landmark results come back positionally aligned with the input observations.
            let landmarks = index < landmarked.count ? landmarked[index].landmarks : nil
            let eyes = landmarks.flatMap { eyeCenters(from: $0, imageSize: imageSize) }

            let crop: CGImage?
            if let eyes {
                crop = alignedCrop(from: image, leftEye: eyes.left, rightEye: eyes.right)
            } else {
                crop = paddedSquareCrop(from: image, around: survivor.box)
            }

            guard let crop else { continue }
            results.append(
                DetectedFace(
                    boundingBox: survivor.box,
                    captureQuality: survivor.quality,
                    crop: crop))
        }
        return results
    }

    /// Mean of each eye region's points, in lower-left-origin coordinates, ordered by x.
    ///
    /// Ordering by x rather than trusting Vision's left/right labels keeps this independent of
    /// which perspective those labels use. Valid for |roll| < 90 degrees, which covers real
    /// photographs; beyond that the capture-quality filter has almost certainly dropped the face.
    func eyeCenters(
        from landmarks: FaceObservation.Landmarks2D,
        imageSize: CGSize
    ) -> (left: CGPoint, right: CGPoint)? {
        let a = landmarks.leftEye.pointsInImageCoordinates(imageSize, origin: .lowerLeft)
        let b = landmarks.rightEye.pointsInImageCoordinates(imageSize, origin: .lowerLeft)
        guard let centerA = centroid(of: a), let centerB = centroid(of: b) else { return nil }
        return centerA.x <= centerB.x ? (centerA, centerB) : (centerB, centerA)
    }

    private func centroid(of points: [CGPoint]) -> CGPoint? {
        guard !points.isEmpty else { return nil }
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }

    /// Maps the two eye centers onto canonical positions with a similarity transform, so the
    /// crop is scaled, rotated, and translated in a single resampling step.
    ///
    /// Eye points are in lower-left-origin coordinates, matching CGContext.
    func alignedCrop(from image: CGImage, leftEye: CGPoint, rightEye: CGPoint) -> CGImage? {
        let scaleToOutput = CGFloat(outputSize) / Self.canonicalSize
        // Flip the canonical points into the context's lower-left-origin space.
        let destLeft = CGPoint(
            x: Self.canonicalLeftEye.x * scaleToOutput,
            y: (Self.canonicalSize - Self.canonicalLeftEye.y) * scaleToOutput)
        let destRight = CGPoint(
            x: Self.canonicalRightEye.x * scaleToOutput,
            y: (Self.canonicalSize - Self.canonicalRightEye.y) * scaleToOutput)

        let sourceVector = CGVector(dx: rightEye.x - leftEye.x, dy: rightEye.y - leftEye.y)
        let destVector = CGVector(dx: destRight.x - destLeft.x, dy: destRight.y - destLeft.y)

        let sourceLength = (sourceVector.dx * sourceVector.dx + sourceVector.dy * sourceVector.dy).squareRoot()
        guard sourceLength > 1e-6 else { return nil }
        let destLength = (destVector.dx * destVector.dx + destVector.dy * destVector.dy).squareRoot()

        let scale = destLength / sourceLength
        let angle = atan2(destVector.dy, destVector.dx) - atan2(sourceVector.dy, sourceVector.dx)

        // Translation that puts the scaled, rotated left eye exactly on its canonical spot.
        let rotatedScaledLeft = CGPoint(
            x: scale * (leftEye.x * cos(angle) - leftEye.y * sin(angle)),
            y: scale * (leftEye.x * sin(angle) + leftEye.y * cos(angle)))
        let translation = CGPoint(
            x: destLeft.x - rotatedScaledLeft.x,
            y: destLeft.y - rotatedScaledLeft.y)

        guard let context = makeContext() else { return nil }
        context.translateBy(x: translation.x, y: translation.y)
        context.rotate(by: angle)
        context.scaleBy(x: scale, y: scale)
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)))
        return context.makeImage()
    }

    /// Fallback when landmarks are unavailable: a padded square around the box, no rotation.
    func paddedSquareCrop(from image: CGImage, around box: CGRect) -> CGImage? {
        let side = max(box.width, box.height) * (1 + cropPadding)
        guard side >= 1 else { return nil }

        let centerX = box.midX
        let centerY = CGFloat(image.height) - box.midY  // upper-left -> lower-left origin

        guard let context = makeContext() else { return nil }
        let scale = CGFloat(outputSize) / side
        let half = CGFloat(outputSize) / 2

        context.translateBy(x: half, y: half)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -centerX, y: -centerY)
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)))
        return context.makeImage()
    }

    private func makeContext() -> CGContext? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        guard let context = CGContext(
            data: nil,
            width: outputSize,
            height: outputSize,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        return context
    }
}
