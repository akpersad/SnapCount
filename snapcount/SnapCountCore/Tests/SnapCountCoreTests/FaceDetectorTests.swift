import Testing
import Foundation
import CoreGraphics
@testable import SnapCountCore

/// Verifies the similarity transform in `alignedCrop` actually lands the eyes on the canonical
/// ArcFace positions. If this is wrong every embedding is computed from a misaligned face, which
/// degrades matching quietly rather than failing loudly, so it is worth pinning precisely.
struct FaceDetectorAlignmentTests {

    static let detector = FaceDetector(outputSize: 112)
    static let imageSize = 300

    /// Canonical targets in output upper-left coordinates, where the eyes must end up.
    static let expectedLeft = FaceDetector.canonicalLeftEye
    static let expectedRight = FaceDetector.canonicalRightEye

    /// Runs the transform for a given pair of eye positions and asserts both land canonically.
    ///
    /// `leftEye` / `rightEye` are lower-left-origin, matching what Vision hands us.
    ///
    /// Marker radius scales with eye separation so that after alignment every case produces a
    /// similarly sized mark. Otherwise a wide-set face gets scaled down until its markers are
    /// sub-pixel and the assertion measures resampling, not geometry.
    private func assertEyesLandCanonically(
        leftEye: CGPoint,
        rightEye: CGPoint,
        _ comment: Comment,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let spacing = hypot(rightEye.x - leftEye.x, rightEye.y - leftEye.y)
        let radius = max(2, Int((spacing / 16).rounded()))

        // Convert to upper-left to draw the markers.
        let size = CGFloat(Self.imageSize)
        let dots = [
            CGPoint(x: leftEye.x, y: size - leftEye.y),
            CGPoint(x: rightEye.x, y: size - rightEye.y),
        ]
        let image = TestImages.imageWithDots(
            size: Self.imageSize, dots: dots, dotRadius: radius)

        let crop = try #require(
            Self.detector.alignedCrop(from: image, leftEye: leftEye, rightEye: rightEye),
            comment, sourceLocation: sourceLocation)

        // Search each half separately so the two markers cannot be confused for each other.
        let side = CGFloat(Self.detector.outputSize)
        let midX = (Self.expectedLeft.x + Self.expectedRight.x) / 2
        let leftHalf = CGRect(x: 0, y: 0, width: midX, height: side)
        let rightHalf = CGRect(x: midX, y: 0, width: side - midX, height: side)

        let foundLeft = try #require(
            TestImages.brightestPixel(in: crop, within: leftHalf),
            comment, sourceLocation: sourceLocation)
        let foundRight = try #require(
            TestImages.brightestPixel(in: crop, within: rightHalf),
            comment, sourceLocation: sourceLocation)

        let tolerance: CGFloat = 3
        #expect(
            hypot(foundLeft.x - Self.expectedLeft.x, foundLeft.y - Self.expectedLeft.y) <= tolerance,
            comment, sourceLocation: sourceLocation)
        #expect(
            hypot(foundRight.x - Self.expectedRight.x, foundRight.y - Self.expectedRight.y) <= tolerance,
            comment, sourceLocation: sourceLocation)
    }

    @Test("Level eyes map onto the canonical positions")
    func levelEyes() throws {
        try assertEyesLandCanonically(
            leftEye: CGPoint(x: 100, y: 180),
            rightEye: CGPoint(x: 180, y: 180),
            "level")
    }

    @Test("A rolled face is straightened onto the canonical positions")
    func rolledEyes() throws {
        // Eye line at +30 degrees.
        let left = CGPoint(x: 100, y: 140)
        let length: CGFloat = 80
        let right = CGPoint(
            x: left.x + length * cos(.pi / 6),
            y: left.y + length * sin(.pi / 6))
        try assertEyesLandCanonically(leftEye: left, rightEye: right, "+30 degrees")
    }

    @Test("A face rolled the other way is also straightened")
    func counterRolledEyes() throws {
        let left = CGPoint(x: 100, y: 160)
        let length: CGFloat = 80
        let right = CGPoint(
            x: left.x + length * cos(-.pi / 6),
            y: left.y + length * sin(-.pi / 6))
        try assertEyesLandCanonically(leftEye: left, rightEye: right, "-30 degrees")
    }

    @Test("A small distant face is scaled up to fill the canonical crop")
    func smallFace() throws {
        try assertEyesLandCanonically(
            leftEye: CGPoint(x: 140, y: 150),
            rightEye: CGPoint(x: 165, y: 150),
            "25px eye spacing")
    }

    @Test("A large close face is scaled down")
    func largeFace() throws {
        try assertEyesLandCanonically(
            leftEye: CGPoint(x: 40, y: 150),
            rightEye: CGPoint(x: 260, y: 150),
            "220px eye spacing")
    }

    @Test("Coincident eye points are rejected rather than dividing by zero")
    func degenerateEyes() {
        let image = TestImages.imageWithDots(size: Self.imageSize, dots: [])
        let crop = Self.detector.alignedCrop(
            from: image,
            leftEye: CGPoint(x: 100, y: 100),
            rightEye: CGPoint(x: 100, y: 100))
        #expect(crop == nil)
    }
}
