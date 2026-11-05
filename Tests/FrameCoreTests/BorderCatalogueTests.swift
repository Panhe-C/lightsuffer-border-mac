import XCTest

@testable import FrameCore

/// The catalogue of the styles (the first tests of harness/test-border.mjs).
final class BorderCatalogueTests: XCTestCase {
    func testStyleIdsInPickerOrder() {
        XCTAssertEqual(
            BorderStyle.allCases.map(\.rawValue),
            [
                "none", "thin-white", "polaroid", "black", "film35", "film120",
                "edge-black-thin", "edge-black", "edge-white-thin", "edge-white",
            ]
        )
    }

    func testStyleNames() {
        XCTAssertEqual(BorderStyle.none.displayName, "无边框")
        XCTAssertEqual(BorderStyle.thinWhite.displayName, "细白边")
        XCTAssertEqual(BorderStyle.polaroid.displayName, "拍立得")
        XCTAssertEqual(BorderStyle.black.displayName, "黑边")
        XCTAssertEqual(BorderStyle.film35.displayName, "35mm 胶片")
        XCTAssertEqual(BorderStyle.film120.displayName, "120 胶片")
        XCTAssertEqual(BorderStyle.edgeBlackThin.displayName, "不规则细黑边")
        XCTAssertEqual(BorderStyle.edgeBlack.displayName, "不规则黑边")
        XCTAssertEqual(BorderStyle.edgeWhiteThin.displayName, "不规则细白边")
        XCTAssertEqual(BorderStyle.edgeWhite.displayName, "不规则白边")
    }

    func testNormalizeStyleFallsBackToNone() {
        XCTAssertEqual(BorderStyle.normalized("film35"), .film35)
        XCTAssertEqual(BorderStyle.normalized("bogus"), .none)
        XCTAssertEqual(BorderStyle.normalized(nil), .none)
        XCTAssertEqual(BorderStyle.normalized(""), .none)
    }

    func testColors() {
        XCTAssertEqual(BorderStyle.thinWhite.color, "#ffffff")
        XCTAssertEqual(BorderStyle.polaroid.color, "#f4f1e8")
        XCTAssertEqual(BorderStyle.black.color, "#000000")
        XCTAssertEqual(BorderStyle.film35.color, "#0c0b0a")
        XCTAssertEqual(BorderStyle.film120.color, "#050505")
        XCTAssertEqual(BorderStyle.edgeBlackThin.color, "#050505")
        XCTAssertEqual(BorderStyle.edgeBlack.color, "#050505")
        XCTAssertEqual(BorderStyle.edgeWhiteThin.color, "#fcfbf8")
        XCTAssertEqual(BorderStyle.edgeWhite.color, "#fcfbf8")
        // The rim is a different tone than the band, so the edge is visible.
        for style in [BorderStyle.edgeBlackThin, .edgeBlack, .edgeWhiteThin, .edgeWhite] {
            XCTAssertNotNil(style.edgeSpec?.rim)
            XCTAssertNotEqual(style.edgeSpec?.rim, style.color)
        }
    }

    func testOnlyTheFilmStylesPrintTheStockName() {
        XCTAssertTrue(BorderStyle.film35.printsEdgeText)
        XCTAssertTrue(BorderStyle.film120.printsEdgeText)
        for style in BorderStyle.allCases where style != .film35 && style != .film120 {
            XCTAssertFalse(style.printsEdgeText, "\(style.rawValue) prints no edge text")
        }
    }
}
