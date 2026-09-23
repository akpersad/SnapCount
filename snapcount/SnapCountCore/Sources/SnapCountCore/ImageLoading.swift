import Foundation
import CoreGraphics
import ImageIO

/// Decodes photos into upright, bounded-size `CGImage`s for the pipeline.
///
/// Two things matter here and both are easy to get wrong:
/// - Phone photos are usually stored sideways with an EXIF orientation tag. A plain decode
///   hands Vision a rotated image, and face detection quietly finds nothing.
/// - Full-resolution HEICs are 12-48 MP. Faces only need to survive down to a 112 px crop,
///   so decoding at full size is wasted memory and time on every photo of the day.
public enum ImageLoading {
    /// Long edge of the decoded image. Large enough that a face at `FaceDetector`'s minimum
    /// relative size still yields a crop well above 112 px.
    public static let defaultMaxPixelSize = 2048

    public static func image(at url: URL, maxPixelSize: Int = defaultMaxPixelSize) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return image(from: source, maxPixelSize: maxPixelSize)
    }

    public static func image(from data: Data, maxPixelSize: Int = defaultMaxPixelSize) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return image(from: source, maxPixelSize: maxPixelSize)
    }

    static func image(from source: CGImageSource, maxPixelSize: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,  // applies EXIF orientation
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Image files in a directory, sorted by name. Hidden files such as `.keep` are skipped.
    public static func imageFiles(in directory: URL) throws -> [URL] {
        let extensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif"]
        return try FileManager.default
            .contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            .filter { extensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
