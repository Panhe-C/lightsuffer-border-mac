import XCTest

@testable import FrameCore

/// The layout math (the second part of harness/test-border.mjs).
final class LayoutTests: XCTestCase {
    func testOuterSizeIsThePhotoPlusTheMargins() throws {
        for style in BorderStyle.allCases {
            for (width, height) in testAspects {
                let layout = try BorderLayout.compute(style: style, photoW: width, photoH: height)
                XCTAssertEqual(layout.outerW, width + layout.left + layout.right, "\(style.rawValue) \(width)x\(height)")
                XCTAssertEqual(layout.outerH, height + layout.top + layout.bottom, "\(style.rawValue) \(width)x\(height)")
                XCTAssertGreaterThanOrEqual(layout.left, 0)
                XCTAssertGreaterThanOrEqual(layout.top, 0)
                XCTAssertGreaterThanOrEqual(layout.right, 0)
                XCTAssertGreaterThanOrEqual(layout.bottom, 0)
                if style == .none {
                    XCTAssertEqual(layout.outerW, width)
                    XCTAssertEqual(layout.outerH, height)
                    XCTAssertEqual(layout.left, 0)
                    XCTAssertEqual(layout.top, 0)
                    XCTAssertEqual(layout.right, 0)
                    XCTAssertEqual(layout.bottom, 0)
                } else {
                    XCTAssertGreaterThan(layout.left, 0, "\(style.rawValue) \(width)x\(height)")
                    XCTAssertGreaterThan(layout.top, 0, "\(style.rawValue) \(width)x\(height)")
                    XCTAssertGreaterThan(layout.right, 0, "\(style.rawValue) \(width)x\(height)")
                    XCTAssertGreaterThan(layout.bottom, 0, "\(style.rawValue) \(width)x\(height)")
                }
            }
        }
    }

    func testInvalidDimensionsAreRejected() {
        XCTAssertThrowsError(try BorderLayout.compute(style: .black, photoW: 0, photoH: 100))
        XCTAssertThrowsError(try BorderLayout.compute(style: .black, photoW: 100, photoH: -3))
        XCTAssertThrowsError(try BorderLayout.compute(style: .black, photoW: 100.0, photoH: Double.nan))
        XCTAssertThrowsError(try BorderLayout.compute(style: .black, photoW: Double.infinity, photoH: 100))
    }

    func testSymmetryAndCharacterOfEachStyle() throws {
        let thin = try BorderLayout.compute(style: .thinWhite, photoW: 4032, photoH: 3024)
        XCTAssertEqual(thin.color, "#ffffff")
        XCTAssertEqual(thin.left, thin.right)
        XCTAssertEqual(thin.top, thin.bottom)
        XCTAssertEqual(thin.left, thin.top)

        let polaroid = try BorderLayout.compute(style: .polaroid, photoW: 4032, photoH: 3024)
        XCTAssertGreaterThan(Double(polaroid.bottom), Double(polaroid.top) * 2.5)
        XCTAssertEqual(polaroid.left, polaroid.right)
        // The Polaroid margin follows the SHORT edge, so portrait and landscape agree.
        let portrait = try BorderLayout.compute(style: .polaroid, photoW: 3024, photoH: 4032)
        XCTAssertEqual(portrait.bottom, polaroid.bottom)
        XCTAssertEqual(portrait.left, polaroid.left)

        let black = try BorderLayout.compute(style: .black, photoW: 3000, photoH: 2000)
        XCTAssertEqual(black.color, "#000000")
        XCTAssertEqual(black.left, black.right)
        XCTAssertEqual(black.top, black.bottom)
    }

    /// The film strip runs along the long edge: a landscape picture gets bands
    /// on top and bottom, a portrait one on the left and right.
    func testFilm35RunsAlongTheLongEdge() throws {
        let landscape = try BorderLayout.compute(style: .film35, photoW: 3000, photoH: 2000)
        XCTAssertEqual(landscape.orientation, .horizontal)
        XCTAssertEqual(landscape.top, landscape.band)
        XCTAssertEqual(landscape.bottom, landscape.band)
        XCTAssertEqual(landscape.left, landscape.side)
        XCTAssertGreaterThan(Double(landscape.band), Double(landscape.side) * 4)
        // A 3:2 picture gets the real 135 proportions: a 5.5 mm band on a 36 mm frame.
        XCTAssertLessThan(
            abs(Double(landscape.band) / Double(landscape.photoW) - 5.5 / 36),
            0.002
        )

        let portrait = try BorderLayout.compute(style: .film35, photoW: 2000, photoH: 3000)
        XCTAssertEqual(portrait.orientation, .vertical)
        XCTAssertEqual(portrait.left, portrait.band)
        XCTAssertEqual(portrait.right, portrait.band)
        XCTAssertEqual(portrait.top, portrait.side)
        XCTAssertEqual(portrait.band, landscape.band, "the band does not depend on the orientation")

        // A panorama does not get an absurdly thick band.
        let panorama = try BorderLayout.compute(style: .film35, photoW: 6000, photoH: 1000)
        XCTAssertLessThanOrEqual(Double(panorama.band), 1000 * 0.153 * 1.5 + 1)
    }

    /// A layout scales linearly with the picture, so the preview layout is the
    /// export layout divided by one constant (up to the rounding of 1 px).
    func testLayoutScalesLinearly() throws {
        for style in BorderStyle.allCases {
            let big = try BorderLayout.compute(style: style, photoW: 4000, photoH: 3000)
            let small = try BorderLayout.compute(style: style, photoW: 1000, photoH: 750)
            for side in Side.allCases {
                XCTAssertLessThanOrEqual(
                    abs(Double(big[side]) / 4 - Double(small[side])),
                    1,
                    "\(style.rawValue) \(side) scales linearly"
                )
            }
        }
    }

    func testPickerMiniatures() throws {
        for style in BorderStyle.allCases {
            let geometry = try BorderLayout.thumbnailGeometry(style: style, sampleW: 300, sampleH: 200)
            XCTAssertGreaterThanOrEqual(geometry.left, 0)
            XCTAssertLessThan(geometry.left + geometry.right, 1)
            XCTAssertGreaterThanOrEqual(geometry.top, 0)
            XCTAssertLessThan(geometry.top + geometry.bottom, 1)
            XCTAssertGreaterThan(geometry.aspect, 0.5)
            XCTAssertLessThan(geometry.aspect, 2)
        }
    }
}
