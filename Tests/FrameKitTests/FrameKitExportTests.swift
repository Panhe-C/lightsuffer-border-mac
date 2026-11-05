import XCTest
import CoreGraphics
import ImageIO
import FrameCore
import FrameKit

#if canImport(CoreGraphics)

/// The tests of the exporter (`ImageExporter`).
final class FrameKitExportTests: XCTestCase {

    /// A name that is already used gets the suffix `_2`, then `_3`.
    func testUniqueURLNeverOverwrites() throws {
        let directory = try Fixtures.temporaryDirectory("unique-url")
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = ImageExporter.uniqueURL(in: directory, name: "picture", suffix: "_frame", format: .jpeg)
        XCTAssertEqual(first.lastPathComponent, "picture_frame.jpg")
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))

        // The file exists: the next name must be a different one.
        try Data("first".utf8).write(to: first)
        let second = ImageExporter.uniqueURL(in: directory, name: "picture", suffix: "_frame", format: .jpeg)
        XCTAssertEqual(second.lastPathComponent, "picture_frame_2.jpg")
        XCTAssertNotEqual(first, second)

        try Data("second".utf8).write(to: second)
        let third = ImageExporter.uniqueURL(in: directory, name: "picture", suffix: "_frame", format: .jpeg)
        XCTAssertEqual(third.lastPathComponent, "picture_frame_3.jpg")
        XCTAssertNotEqual(second, third)

        // The other formats have their own extension.
        let png = ImageExporter.uniqueURL(in: directory, name: "picture", suffix: "_frame", format: .png)
        XCTAssertEqual(png.lastPathComponent, "picture_frame.png")
    }

    /// Two exports of the same picture never write the same file.
    func testExportNeverOverwritesAnExistingFile() throws {
        let directory = try Fixtures.temporaryDirectory("export")
        defer { try? FileManager.default.removeItem(at: directory) }

        let image = try XCTUnwrap(makeTestImage())
        let options = ImageExporter.Options(format: .jpeg, quality: 0.9, suffix: "_frame", outputDirectory: directory)

        let first = try ImageExporter.export(image: image, source: nil, options: options)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))

        let second = try ImageExporter.export(image: image, source: nil, options: options)
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(second.lastPathComponent, "picture_frame_2.jpg")

        // The two files are real files with a size.
        let firstAttributes = try FileManager.default.attributesOfItem(atPath: first.path)
        let secondAttributes = try FileManager.default.attributesOfItem(atPath: second.path)
        XCTAssertNotNil(firstAttributes[.size] as? Int)
        XCTAssertNotNil(secondAttributes[.size] as? Int)
    }

    /// The export writes the orientation 1 (the pixels are already oriented) and
    /// keeps the EXIF block of the source.
    func testExportKeepsTheMetadataAndSetsTheOrientationToOne() throws {
        let url = try Fixtures.sample("landscape.jpg")
        let source = try ImageLoader.load(url)
        let directory = try Fixtures.temporaryDirectory("metadata")
        defer { try? FileManager.default.removeItem(at: directory) }

        let image = try FrameRenderer().renderFull(source, options: FrameRenderOptions(style: .black))
        let options = ImageExporter.Options(format: .jpeg, quality: 0.9, suffix: "_frame", outputDirectory: directory)
        let written = try ImageExporter.export(image: image, source: source, options: options)
        XCTAssertTrue(FileManager.default.fileExists(atPath: written.path))

        let properties = try ImageLoader.properties(of: written)

        // The orientation of the output is 1: the pixels are already oriented.
        XCTAssertEqual(ImageLoader.orientation(of: properties), 1)
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        // The orientation of the two dictionaries is 1 too (when they have one).
        if let value = tiff[kCGImagePropertyTIFFOrientation] as? NSNumber {
            XCTAssertEqual(value.intValue, 1)
        }
        if let value = exif[kCGImagePropertyExifOrientation] as? NSNumber {
            XCTAssertEqual(value.intValue, 1)
        }

        // The size of the output is written in the EXIF block (when it is there).
        if let value = exif[kCGImagePropertyExifPixelXDimension] as? NSNumber {
            XCTAssertEqual(value.intValue, image.width)
        }
        if let value = exif[kCGImagePropertyExifPixelYDimension] as? NSNumber {
            XCTAssertEqual(value.intValue, image.height)
        }

        // The camera of the source survives the export.
        let sourceMake = metadataString(source.properties, kCGImagePropertyTIFFMake)
        let sourceModel = metadataString(source.properties, kCGImagePropertyTIFFModel)
        if let sourceMake = sourceMake {
            XCTAssertEqual(metadataString(properties, kCGImagePropertyTIFFMake), sourceMake)
        }
        if let sourceModel = sourceModel {
            XCTAssertEqual(metadataString(properties, kCGImagePropertyTIFFModel), sourceModel)
        }
    }
}
#endif
