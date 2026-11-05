import XCTest
import CoreGraphics
import ImageIO
import FrameCore
import FrameKit

#if canImport(CoreGraphics)

/// The tests of the renderer (`FrameRenderer`) and of the loader (`ImageLoader`).
final class FrameKitRenderTests: XCTestCase {

    /// The full render has the size of the layout and the picture keeps its
    /// pixels: the painter only paints the margins.
    func testRenderFullHasTheSizeOfTheLayoutAndKeepsThePicture() throws {
        let url = try Fixtures.sample("landscape.jpg")
        let source = try ImageLoader.load(url)
        let style = BorderStyle.film120

        let image = try FrameRenderer().renderFull(source, options: FrameRenderOptions(style: style))
        let layout = try BorderLayout.compute(style: style, photoW: source.width, photoH: source.height)

        // The outer size of the picture is the size of the layout.
        XCTAssertEqual(image.width, layout.outerW)
        XCTAssertEqual(image.height, layout.outerH)

        let rendered = try XCTUnwrap(rasterize(image))
        XCTAssertEqual(rendered.width, layout.outerW)
        XCTAssertEqual(rendered.height, layout.outerH)

        // The picture of the render is the picture of the source, pixel by pixel.
        let photoLayout = try BorderLayout.compute(style: .none, photoW: source.width, photoH: source.height)
        let reference = try XCTUnwrap(photoRaster(source, layout: photoLayout))
        let difference = maximumDifference(rendered, reference, originX: layout.left, originY: layout.top)
        XCTAssertLessThanOrEqual(difference, 2, "the picture was changed by the frame")
    }

    /// The style `none` has no frame at all: the picture is copied as it is.
    func testRenderWithoutFrameCopiesEveryPixel() throws {
        let url = try Fixtures.sample("landscape.jpg")
        let source = try ImageLoader.load(url)

        let image = try FrameRenderer().renderFull(source, options: FrameRenderOptions(style: .none))
        let layout = try BorderLayout.compute(style: .none, photoW: source.width, photoH: source.height)

        XCTAssertEqual(layout.left, 0)
        XCTAssertEqual(layout.top, 0)
        XCTAssertEqual(layout.right, 0)
        XCTAssertEqual(layout.bottom, 0)
        XCTAssertEqual(image.width, source.width)
        XCTAssertEqual(image.height, source.height)

        let rendered = try XCTUnwrap(rasterize(image))
        let reference = try XCTUnwrap(photoRaster(source, layout: layout))
        let difference = maximumDifference(rendered, reference, originX: 0, originY: 0)
        // The picture is copied as it is (one level of rounding is allowed).
        XCTAssertLessThanOrEqual(difference, 1, "the picture was changed")
    }

    /// The 120 frame paints the black strip of the film around the picture and
    /// leaves the picture alone.
    func testFilm120PaintsTheMarginAndKeepsThePicture() throws {
        let url = try Fixtures.sample("landscape.jpg")
        let source = try ImageLoader.load(url)
        let style = BorderStyle.film120

        let image = try FrameRenderer().renderFull(source, options: FrameRenderOptions(style: style))
        let layout = try BorderLayout.compute(style: style, photoW: source.width, photoH: source.height)
        let rendered = try XCTUnwrap(rasterize(image))

        // The black strip of the film is black (the colour of the style).
        let blacks = BorderLayout.film120Blacks(layout)
        XCTAssertGreaterThan(blacks.left, 2, "the sample has no black strip")
        let stripX = Int((Double(layout.left) - blacks.left / 2).rounded())
        let stripY = layout.top + layout.photoH / 2
        let strip = rendered.pixel(x: stripX, y: stripY)
        XCTAssertLessThanOrEqual(strip.r, 40, "the black strip is not black")
        XCTAssertLessThanOrEqual(strip.g, 40, "the black strip is not black")
        XCTAssertLessThanOrEqual(strip.b, 40, "the black strip is not black")

        // The scan margin outside of the strip is white.
        let corner = rendered.pixel(x: 1, y: 1)
        XCTAssertGreaterThan(corner.r, 200, "the scan margin is not white")
        XCTAssertGreaterThan(corner.g, 200, "the scan margin is not white")
        XCTAssertGreaterThan(corner.b, 200, "the scan margin is not white")

        // The picture is still the picture of the source.
        let photoLayout = try BorderLayout.compute(style: .none, photoW: source.width, photoH: source.height)
        let reference = try XCTUnwrap(photoRaster(source, layout: photoLayout))
        let difference = maximumDifference(rendered, reference, originX: layout.left, originY: layout.top)
        XCTAssertLessThanOrEqual(difference, 2, "the picture was changed by the frame")
    }

    /// The loader reads the size of the picture after the orientation and the
    /// metadata of the file.
    func testLoaderReadsTheSampleAndItsMetadata() throws {
        let url = try Fixtures.sample("landscape.jpg")
        let source = try ImageLoader.load(url)

        XCTAssertEqual(source.width, 1800)
        XCTAssertEqual(source.height, 1200)
        XCTAssertEqual(source.orientation, 1)
        XCTAssertEqual(source.uniformTypeIdentifier, "public.jpeg")

        // The samples carry a small EXIF block.
        let make = metadataString(source.properties, kCGImagePropertyTIFFMake)
        let model = metadataString(source.properties, kCGImagePropertyTIFFModel)
        XCTAssertEqual(make, "Light Suffer Frame")
        XCTAssertEqual(model, "Synthetic Sample Camera")
    }
}
#endif
