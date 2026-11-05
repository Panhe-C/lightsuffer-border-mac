import XCTest

@testable import FrameCore

/// The 120 film: a thin, irregular black edge around the UNCROPPED photo.
final class Film120LayoutTests: XCTestCase {
    private let sizes: [(width: Int, height: Int)] = [
        (3000, 2000), (2000, 3000), (2000, 2000), (1600, 900), (900, 1600),
        (6000, 1000), (1000, 6000),
    ]

    func testThePhotoIsNeverCropped() throws {
        XCTAssertEqual(BorderStyle.film120.displayName, "120 胶片")
        for (width, height) in sizes {
            let layout = try BorderLayout.compute(style: .film120, photoW: width, photoH: height)
            let short = Double(min(width, height))
            XCTAssertEqual(layout.photoW, width)
            XCTAssertEqual(layout.photoH, height)
            XCTAssertEqual(layout.outerW, width + layout.left + layout.right)
            XCTAssertEqual(layout.outerH, height + layout.top + layout.bottom)
            // Thin: even the print side plus the white scan margin stays below
            // 7 % of the short side.
            for side in Side.allCases {
                XCTAssertLessThan(Double(layout[side]) / short, 0.07, "\(width)x\(height) \(side) is thin")
                XCTAssertGreaterThanOrEqual(layout[side], 1)
            }
        }
    }

    func testThePrintSideIsTheWideBand() throws {
        for (width, height) in sizes {
            let layout = try BorderLayout.compute(style: .film120, photoW: width, photoH: height)
            let film = try XCTUnwrap(layout.film)
            // The print side is the long side of the strip: top for landscape,
            // left for portrait and square.
            let side: Side = width > height ? .top : .left
            XCTAssertEqual(film.printSide, side == .top ? "top" : "left")
            for other in Side.allCases where other != side {
                XCTAssertGreaterThan(
                    film.black[side],
                    film.black[other] * 1.8,
                    "\(width)x\(height): the \(side) band is the wide one"
                )
            }
        }
    }

    func testTheRebateIsIrregular() throws {
        for (width, height) in sizes {
            let layout = try BorderLayout.compute(style: .film120, photoW: width, photoH: height)
            let film = try XCTUnwrap(layout.film)
            // No two sides share a width and the corners are nudged.
            let widths = Side.allCases.map { film.black[$0] }
            let rounded = Set(widths.map { String(format: "%.3f", $0) })
            XCTAssertEqual(rounded.count, 4, "\(width)x\(height): the four sides differ")
            XCTAssertTrue(film.corners.contains { $0[0] != 0 || $0[1] != 0 })
            // The nudge never eats the thinnest rebate.
            let jitter = film.corners.flatMap { $0 }.map { abs($0) }.max() ?? 0
            XCTAssertLessThan(jitter, widths.min() ?? 0, "\(width)x\(height): the nudge stays inside the rebate")
        }
    }

    func testTheLayoutIsDeterministic() throws {
        for (width, height) in sizes {
            let first = try BorderLayout.compute(style: .film120, photoW: width, photoH: height)
            let second = try BorderLayout.compute(style: .film120, photoW: width, photoH: height)
            XCTAssertEqual(first, second)
        }
    }

    func testTheIrregularityIsAFixedPatternInUnitsOfThePhoto() throws {
        let big = try BorderLayout.compute(style: .film120, photoW: 4000, photoH: 3000)
        let small = try BorderLayout.compute(style: .film120, photoW: 1000, photoH: 750)
        let bigFilm = try XCTUnwrap(big.film)
        let smallFilm = try XCTUnwrap(small.film)
        for side in Side.allCases {
            XCTAssertEqual(bigFilm.black[side] / 4, smallFilm.black[side], accuracy: 1e-9)
            XCTAssertEqual(bigFilm.white[side] / 4, smallFilm.white[side], accuracy: 1e-9)
        }
    }

    func testMonoStocksAreDetected() {
        XCTAssertTrue(BorderLayout.isMonochrome("Ilford HP5 Plus"))
        XCTAssertTrue(BorderLayout.isMonochrome("Kodak Tri-X 400"))
        XCTAssertTrue(BorderLayout.isMonochrome("黑白"))
        XCTAssertTrue(BorderLayout.isMonochrome("ILFORD HP5"))
        XCTAssertFalse(BorderLayout.isMonochrome("Kodak Portra 400"))
        XCTAssertFalse(BorderLayout.isMonochrome(""))
        XCTAssertFalse(BorderLayout.isMonochrome(nil))
    }
}
