import XCTest
import CoreGraphics
import ImageIO
import FrameCore
import FrameKit

#if canImport(CoreGraphics)

// The helpers of the FrameKit tests.
//
// The tests only run on macOS (the target of `FrameKitTests` is added to the
// package inside `#if os(macOS)`), so the Core Graphics frameworks are always
// there. The guard keeps the file harmless when it is parsed elsewhere.

/// The files of the package the tests need.
enum Fixtures {
    /// The root of the package (the folder of `Package.swift`).
    static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // FrameKitTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // the package root
    }

    /// The folder with the sample pictures.
    static var samples: URL {
        packageRoot.appendingPathComponent("samples", isDirectory: true)
    }

    /// The url of a sample picture.
    ///
    /// The test is skipped when the file is missing (the samples are not part
    /// of every checkout).
    static func sample(_ name: String) throws -> URL {
        let url = samples.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("the sample \(name) is missing")
        }
        return url
    }

    /// A new empty folder in the temporary folder of the system.
    static func temporaryDirectory(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lightsuffer-tests-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// A picture in a top-down RGBA buffer (the first row is the top row).
struct Raster {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    /// The pixel at (x, y); (0, 0) is the top left corner.
    func pixel(x: Int, y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        let index = (y * width + x) * 4
        guard index >= 0, index + 3 < bytes.count else { return (0, 0, 0, 0) }
        return (Int(bytes[index]), Int(bytes[index + 1]), Int(bytes[index + 2]), Int(bytes[index + 3]))
    }
}

/// Draws a picture into a top-down RGBA buffer.
///
/// The buffer always has an alpha channel, so the bytes are always RGBA. The
/// color space of the picture is kept (the pixels are not converted), so the
/// buffer can be compared with another one of the same space.
func rasterize(_ image: CGImage, colorSpace: CGColorSpace? = nil) -> Raster? {
    let width = image.width
    let height = image.height
    guard width > 0, height > 0 else { return nil }
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let space = colorSpace ?? image.colorSpace
        ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
        guard let context = CGContext(
            data: raw.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: space,
            bitmapInfo: info
        ) else { return false }
        context.interpolationQuality = .none
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        // The context is flipped once, so the buffer is read from the top.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        return true
    }
    guard drawn else { return nil }
    return Raster(width: width, height: height, bytes: bytes)
}

/// The picture of the source, drawn the way the renderer draws it.
///
/// The layout must be the layout of the style `none` (no margins), so the
/// picture fills the whole buffer.
func photoRaster(_ source: LoadedImage, layout: Layout) -> Raster? {
    let width = layout.photoW
    let height = layout.photoH
    guard width > 0, height > 0 else { return nil }
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let space = FrameRenderer.renderColorSpace(source.colorSpace)
    let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
        guard let context = CGContext(
            data: raw.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: space,
            bitmapInfo: info
        ) else { return false }
        context.interpolationQuality = .none
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        // The context is flipped once, like the renderer does.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        FrameRenderer.drawPhoto(source, in: context, layout: layout)
        return true
    }
    guard drawn else { return nil }
    return Raster(width: width, height: height, bytes: bytes)
}

/// The biggest difference of the channels between the picture of the render
/// and the picture of the source.
///
/// The picture of the render is expected at (originX, originY) of the render.
func maximumDifference(
    _ rendered: Raster,
    _ reference: Raster,
    originX: Int,
    originY: Int
) -> Int {
    guard rendered.width >= reference.width + originX, rendered.height >= reference.height + originY else {
        return 255
    }
    var worst = 0
    for y in 0..<reference.height {
        for x in 0..<reference.width {
            let actual = rendered.pixel(x: x + originX, y: y + originY)
            let expected = reference.pixel(x: x, y: y)
            worst = max(worst, abs(actual.r - expected.r))
            worst = max(worst, abs(actual.g - expected.g))
            worst = max(worst, abs(actual.b - expected.b))
        }
    }
    return worst
}

/// A small test picture (a grey square with a red corner).
func makeTestImage(width: Int = 32, height: Int = 24) -> CGImage? {
    let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { return nil }
    context.setFillColor(gray: 0.5, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
    return context.makeImage()
}

/// The value of a string of the metadata of a picture (the TIFF dictionary
/// first, then the EXIF dictionary).
func metadataString(_ properties: [CFString: Any], _ key: CFString) -> String? {
    let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
    if let value = tiff[key] as? String { return value }
    let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
    if let value = exif[key] as? String { return value }
    return nil
}
#endif
