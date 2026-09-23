import Foundation
import CoreGraphics
@testable import SnapCountCore

enum TestImages {
    /// Black square with a single white dot, positioned in upper-left-origin coordinates.
    static func imageWithDot(size: Int, dot: CGPoint, dotRadius: Int = 4) -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))

        // Flip the dot's y into the context's lower-left-origin space.
        let ctxY = CGFloat(size) - dot.y
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fillEllipse(in: CGRect(
            x: dot.x - CGFloat(dotRadius), y: ctxY - CGFloat(dotRadius),
            width: CGFloat(dotRadius * 2), height: CGFloat(dotRadius * 2)))

        return context.makeImage()!
    }

    /// Brightest pixel in upper-left-origin coordinates. Returns nil if the image is uniform.
    static func brightestPixel(in image: CGImage) -> CGPoint? {
        let w = image.width, h = image.height
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        buffer.withUnsafeMutableBytes { raw in
            let ctx = CGContext(
                data: raw.baseAddress, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }

        var best = -1, bestPoint: CGPoint?
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                let luma = Int(buffer[i]) + Int(buffer[i + 1]) + Int(buffer[i + 2])
                if luma > best { best = luma; bestPoint = CGPoint(x: x, y: y) }
            }
        }
        // A CGBitmapContext is laid out top-down in memory: buffer row 0 is the TOP of the
        // image. So the row index is already an upper-left-origin y and needs no flip.
        // (Drawing primitives like fillEllipse *do* use lower-left coords, hence the
        // asymmetry with imageWithDot above. That asymmetry is real, not a bug.)
        guard let p = bestPoint, best > 60 else { return nil }
        return p
    }
}

extension TestImages {
    /// Black square with white dots at the given upper-left-origin positions.
    static func imageWithDots(size: Int, dots: [CGPoint], dotRadius: Int = 3) -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        for dot in dots {
            let ctxY = CGFloat(size) - dot.y
            context.fillEllipse(in: CGRect(
                x: dot.x - CGFloat(dotRadius), y: ctxY - CGFloat(dotRadius),
                width: CGFloat(dotRadius * 2), height: CGFloat(dotRadius * 2)))
        }
        return context.makeImage()!
    }

    /// Mean luminance in a square window centred on an upper-left-origin point.
    static func meanLuma(in image: CGImage, around point: CGPoint, window: Int = 5) -> Double {
        let w = image.width, h = image.height
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        buffer.withUnsafeMutableBytes { raw in
            let ctx = CGContext(
                data: raw.baseAddress, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }

        var total = 0.0, count = 0
        let half = window / 2
        for dy in -half...half {
            for dx in -half...half {
                let x = Int(point.x.rounded()) + dx
                // Buffer rows run top-down, so an upper-left y is already the row index.
                let y = Int(point.y.rounded()) + dy
                guard x >= 0, x < w, y >= 0, y < h else { continue }
                let i = (y * w + x) * 4
                total += (Double(buffer[i]) + Double(buffer[i + 1]) + Double(buffer[i + 2])) / 3
                count += 1
            }
        }
        return count > 0 ? total / Double(count) : 0
    }
}

extension TestImages {
    /// Brightest pixel within a sub-rectangle, in upper-left-origin coordinates.
    /// Unlike `brightestPixel` this has no absolute threshold, so it still locates a marker
    /// that antialiasing has dimmed after a heavy downscale.
    static func brightestPixel(in image: CGImage, within region: CGRect) -> CGPoint? {
        let w = image.width, h = image.height
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        buffer.withUnsafeMutableBytes { raw in
            let ctx = CGContext(
                data: raw.baseAddress, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }

        let clipped = region.intersection(CGRect(x: 0, y: 0, width: w, height: h))
        guard !clipped.isNull else { return nil }

        var best = 0, bestPoint: CGPoint?
        for y in Int(clipped.minY)..<Int(clipped.maxY) {
            for x in Int(clipped.minX)..<Int(clipped.maxX) {
                let i = (y * w + x) * 4
                let luma = Int(buffer[i]) + Int(buffer[i + 1]) + Int(buffer[i + 2])
                if luma > best { best = luma; bestPoint = CGPoint(x: x, y: y) }
            }
        }
        return best > 0 ? bestPoint : nil
    }
}
