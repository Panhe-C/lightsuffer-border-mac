import Foundation

#if canImport(CoreGraphics)
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// The errors of the image loader.
public enum ImageLoaderError: Error, CustomStringConvertible {
    case unreadable(URL)
    case empty(URL)
    case noImage(URL)

    public var description: String {
        switch self {
        case .unreadable(let url): return "cannot read the image: \(url.path)"
        case .empty(let url): return "the file has no image: \(url.path)"
        case .noImage(let url): return "cannot decode the image: \(url.path)"
        }
    }
}

/// A picture that has been read with ImageIO.
public struct LoadedImage {
    /// The file the picture comes from.
    public let url: URL
    /// The decoded pixels (still in the stored orientation).
    public let image: CGImage
    /// The size of the picture after the EXIF orientation has been applied.
    public let pixelSize: CGSize
    /// The size of the stored pixels (before the orientation).
    public let storedSize: CGSize
    /// The EXIF orientation (1...8, 1 when there is none).
    public let orientation: Int
    /// The uniform type identifier of the file ("public.jpeg", ...).
    public let uniformTypeIdentifier: String
    /// The colour space of the pixels (nil when the file has none).
    public let colorSpace: CGColorSpace?
    /// Has the picture an alpha channel?
    public let hasAlpha: Bool
    /// The bits per component of the pixels (8 or 16 usually).
    public let bitDepth: Int
    /// The properties of the file (EXIF, TIFF, GPS, IPTC...).
    public let properties: [CFString: Any]

    /// The width of the picture in pixels (after the orientation).
    public var width: Int { Int(pixelSize.width.rounded()) }
    /// The height of the picture in pixels (after the orientation).
    public var height: Int { Int(pixelSize.height.rounded()) }

    /// The transform that shows the stored pixels the right way up.
    ///
    /// It maps the stored rectangle (0, 0, storedWidth, storedHeight) of a y-up
    /// space onto the oriented rectangle (0, 0, pixelWidth, pixelHeight).
    public var orientationTransform: CGAffineTransform {
        let rawWidth = CGFloat(storedSize.width)
        let rawHeight = CGFloat(storedSize.height)
        let orientedHeight = CGFloat(pixelSize.height)
        switch orientation {
        case 2:
            return CGAffineTransform(translationX: rawWidth, y: 0).scaledBy(x: -1, y: 1)
        case 3:
            return CGAffineTransform(translationX: rawWidth, y: rawHeight).rotated(by: .pi)
        case 4:
            return CGAffineTransform(translationX: 0, y: rawHeight).scaledBy(x: 1, y: -1)
        case 5:
            return CGAffineTransform(translationX: rawHeight, y: rawWidth).rotated(by: .pi / 2).scaledBy(x: -1, y: 1)
        case 6:
            return CGAffineTransform(translationX: 0, y: orientedHeight).rotated(by: -.pi / 2)
        case 7:
            return CGAffineTransform.identity.rotated(by: -.pi / 2).scaledBy(x: -1, y: 1)
        case 8:
            return CGAffineTransform(translationX: rawHeight, y: 0).rotated(by: .pi / 2)
        default:
            return .identity
        }
    }
}

/// Reads pictures with ImageIO.
public enum ImageLoader {
    /// The file extensions the app opens.
    public static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "jpe", "heic", "heif", "png", "tif", "tiff",
    ]

    /// Reads the first picture of a file.
    public static func load(_ url: URL) throws -> LoadedImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageLoaderError.unreadable(url)
        }
        guard CGImageSourceGetCount(source) > 0 else {
            throw ImageLoaderError.empty(url)
        }
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) else {
            throw ImageLoaderError.noImage(url)
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        return LoadedImage(
            url: url,
            image: image,
            pixelSize: orientedSize(image: image, properties: properties),
            storedSize: CGSize(width: image.width, height: image.height),
            orientation: orientation(of: properties),
            uniformTypeIdentifier: uniformTypeIdentifier(of: properties, url: url),
            colorSpace: image.colorSpace,
            hasAlpha: hasAlpha(image: image, properties: properties),
            bitDepth: bitDepth(image: image, properties: properties),
            properties: properties
        )
    }

    /// A small version of the picture, with the EXIF orientation applied.
    public static func thumbnail(_ url: URL, maxPixelSize: Int) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageLoaderError.unreadable(url)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageLoaderError.noImage(url)
        }
        return image
    }

    /// The properties of the first picture of a file.
    public static func properties(of url: URL) throws -> [CFString: Any] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageLoaderError.unreadable(url)
        }
        guard CGImageSourceGetCount(source) > 0 else {
            throw ImageLoaderError.empty(url)
        }
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    }

    /// The size of the picture after the EXIF orientation has been applied.
    public static func orientedSize(image: CGImage, properties: [CFString: Any]) -> CGSize {
        let stored = CGSize(width: image.width, height: image.height)
        switch orientation(of: properties) {
        case 5, 6, 7, 8:
            return CGSize(width: stored.height, height: stored.width)
        default:
            return stored
        }
    }

    /// The EXIF orientation of a properties dictionary (1 when there is none).
    public static func orientation(of properties: [CFString: Any]) -> Int {
        let number = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return (1...8).contains(number) ? number : 1
    }

    /// The uniform type identifier of a file.
    public static func uniformTypeIdentifier(of properties: [CFString: Any], url: URL) -> String {
        if let identifier = properties[kCGImagePropertyUniformTypeIdentifier] as? String {
            return identifier
        }
        if let type = UTType(filenameExtension: url.pathExtension), type.isImage {
            return type.identifier
        }
        return UTType.jpeg.identifier
    }

    /// Has the picture an alpha channel?
    public static func hasAlpha(image: CGImage, properties: [CFString: Any]) -> Bool {
        if let flag = (properties[kCGImagePropertyHasAlpha] as? NSNumber)?.boolValue {
            return flag
        }
        switch image.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly:
            return true
        default:
            return false
        }
    }

    /// The bits per component of the pixels.
    public static func bitDepth(image: CGImage, properties: [CFString: Any]) -> Int {
        if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
           let depth = (tiff[kCGImagePropertyTIFFDepth] as? NSNumber)?.intValue, depth > 0 {
            return depth
        }
        if let depth = (properties[kCGImagePropertyDepth] as? NSNumber)?.intValue, depth > 0 {
            return depth
        }
        return image.bitsPerComponent > 0 ? image.bitsPerComponent : 8
    }
}
#endif
