import Foundation

#if canImport(CoreGraphics)
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// The format of an exported picture.
public enum ExportFormat: String, CaseIterable, Codable {
    /// The format of the source picture.
    case sameAsSource
    case jpeg
    case heic
    case tiff
    case png

    /// The label of the format in the export panel.
    public var displayName: String {
        switch self {
        case .sameAsSource: return "与原图相同"
        case .jpeg: return "JPEG"
        case .heic: return "HEIC"
        case .tiff: return "TIFF"
        case .png: return "PNG"
        }
    }

    /// The file extension of the format.
    public var fileExtension: String {
        switch self {
        case .sameAsSource: return "jpg"
        case .jpeg: return "jpg"
        case .heic: return "heic"
        case .tiff: return "tiff"
        case .png: return "png"
        }
    }

    /// The uniform type identifier of the format.
    public var uniformTypeIdentifier: String {
        switch self {
        case .sameAsSource: return UTType.jpeg.identifier
        case .jpeg: return UTType.jpeg.identifier
        case .heic: return UTType.heic.identifier
        case .tiff: return UTType.tiff.identifier
        case .png: return UTType.png.identifier
        }
    }

    /// Does the format support a lossy quality?
    public var supportsQuality: Bool {
        self == .jpeg || self == .heic
    }

    /// The format of a source picture.
    public static func format(ofSourceType identifier: String) -> ExportFormat {
        let type = UTType(identifier: identifier)
        if let type = type, type.conforms(to: UTType.heic) { return .heic }
        if let type = type, type.conforms(to: UTType.jpeg) { return .jpeg }
        if let type = type, type.conforms(to: UTType.png) { return .png }
        if let type = type, type.conforms(to: UTType.tiff) { return .tiff }
        switch (identifier as NSString).pathExtension.lowercased() {
        case "heic", "heif": return .heic
        case "png": return .png
        case "tif", "tiff": return .tiff
        default: return .jpeg
        }
    }
}

/// The errors of the exporter.
public enum ImageExporterError: Error, CustomStringConvertible {
    case cannotCreate(URL)
    case cannotWrite(URL)
    case unknownFormat(String)

    public var description: String {
        switch self {
        case .cannotCreate(let url): return "cannot create the image file: \(url.path)"
        case .cannotWrite(let url): return "cannot write the image file: \(url.path)"
        case .unknownFormat(let name): return "unknown image format: \(name)"
        }
    }
}

/// Writes the framed picture with ImageIO.
public enum ImageExporter {
    /// The default suffix of the file name.
    public static let defaultSuffix = "_frame"

    /// The options of an export.
    public struct Options {
        /// The format of the file.
        public var format: ExportFormat
        /// The lossy quality (0.5...1.0); only JPEG and HEIC use it.
        public var quality: Double
        /// The suffix of the file name (between the name and the extension).
        public var suffix: String
        /// The folder of the file; nil means next to the source.
        public var outputDirectory: URL?

        public init(
            format: ExportFormat = .sameAsSource,
            quality: Double = 0.9,
            suffix: String = ImageExporter.defaultSuffix,
            outputDirectory: URL? = nil
        ) {
            self.format = format
            self.quality = min(1, max(0.1, quality))
            self.suffix = suffix
            self.outputDirectory = outputDirectory
        }
    }

    /// Writes the picture and returns the file it wrote.
    ///
    /// The name of the file is `<name><suffix>.<ext>`; an existing file is
    /// never overwritten (the name gets `_2`, `_3`, ...).
    public static func export(
        image: CGImage,
        source: LoadedImage?,
        options: Options = Options()
    ) throws -> URL {
        let format = options.format == .sameAsSource
            ? ExportFormat.format(ofSourceType: source?.uniformTypeIdentifier ?? UTType.jpeg.identifier)
            : options.format
        let directory: URL
        if let folder = options.outputDirectory {
            directory = folder
        } else if let source = source {
            directory = source.url.deletingLastPathComponent()
        } else {
            directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = uniqueURL(
            in: directory,
            name: source?.url.deletingLastPathComponent().lastPathComponent ?? "picture",
            suffix: options.suffix,
            format: format
        )
        try write(image: image, to: url, format: format, quality: options.quality, source: source)
        return url
    }

    /// Writes the picture to an exact file (the file is replaced).
    public static func write(
        image: CGImage,
        to url: URL,
        format: ExportFormat,
        quality: Double = 0.9,
        source: LoadedImage? = nil
    ) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            format.uniformTypeIdentifier as CFString,
            1,
            nil
        ) else {
            throw ImageExporterError.cannotCreate(url)
        }
        var properties: [CFString: Any] = metadata(from: source, width: image.width, height: image.height)
        if format.supportsQuality {
            properties[kCGImageDestinationLossyCompressionQuality] = min(1, max(0.1, quality))
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageExporterError.cannotWrite(url)
        }
    }

    /// The metadata of the output: the metadata of the source, with the
    /// orientation set to 1 and the read only keys removed.
    public static func metadata(from source: LoadedImage?, width: Int, height: Int) -> [CFString: Any] {
        var properties: [CFString: Any] = [:]
        if let source = source {
            for (key, value) in source.properties {
                properties[key] = value
            }
        }
        // The orientation is applied to the pixels, so it is 1 in the output.
        properties[kCGImagePropertyOrientation] = 1
        // The read only keys of the source are dropped.
        for key in [kCGImagePropertyPixelWidth, kCGImagePropertyPixelHeight] {
            properties.removeValue(forKey: key)
        }
        // The EXIF dictionary: the size of the picture and the orientation.
        var exif = (properties[kCGImagePropertyExifDictionary] as? [CFString: Any]) ?? [:]
        exif[kCGImagePropertyExifPixelXDimension] = width
        exif[kCGImagePropertyExifPixelYDimension] = height
        exif[kCGImagePropertyExifOrientation] = 1
        properties[kCGImagePropertyExifDictionary] = exif
        // The TIFF dictionary: the orientation and the size.
        var tiff = (properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]) ?? [:]
        tiff[kCGImagePropertyTIFFOrientation] = 1
        tiff[kCGImagePropertyTIFFXResolution] = tiff[kCGImagePropertyTIFFXResolution] ?? 72
        tiff[kCGImagePropertyTIFFYResolution] = tiff[kCGImagePropertyTIFFYResolution] ?? 72
        tiff[kCGImagePropertyTIFFResolutionUnit] = tiff[kCGImagePropertyTIFFResolutionUnit] ?? 2
        for key in [
            kCGImagePropertyTIFFImageWidth,
            kCGImagePropertyTIFFImageLength,
            kCGImagePropertyTIFFBitsPerSample,
            kCGImagePropertyTIFFSampleFormat,
            kCGImagePropertyTIFFPhotometricInterpretation,
            kCGImagePropertyTIFFSamplesPerPixel,
            kCGImagePropertyTIFFRowsPerStrip,
            kCGImagePropertyTIFFStripByteCounts,
            kCGImagePropertyTIFFPlanarConfiguration,
            kCGImagePropertyTIFFColorMap,
        ] {
            tiff.removeValue(forKey: key)
        }
        properties[kCGImagePropertyTIFFDictionary] = tiff
        return properties
    }

    /// A file name that does not exist yet: `<name><suffix>.<ext>`, then
    /// `<name><suffix>_2.<ext>`, `<name><suffix>_3.<ext>`, ...
    public static func uniqueURL(in directory: URL, name: String, suffix: String, format: ExportFormat) -> URL {
        let base = name + suffix
        let ext = format.fileExtension
        var candidate = directory.appendingPathComponent(base).appendingPathExtension(ext)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory
                .appendingPathComponent("\(base)_\(counter)")
                .appendingPathExtension(ext)
            counter += 1
        }
        return candidate
    }
}
#endif
