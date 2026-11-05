import XCTest

@testable import FrameCore

/// The values of the JS reference (tools/border.js), computed with node:
///
///     Border.thumbnailGeometry(id, 300, 200)
///     Border.fitLayout(id, w, h, 4096, fit)
final class ReferenceValueTests: XCTestCase {
    /// The picker miniature of a 120 film (node: the JSON of thumbnailGeometry).
    func testTheThumbnailOfThe120Film() throws {
        let geometry = try BorderLayout.thumbnailGeometry(style: .film120, sampleW: 300, sampleH: 200)
        XCTAssertEqual(geometry.aspect, 1.4136363636363636, accuracy: 1e-15)
        XCTAssertEqual(geometry.left, 0.022508038585209004, accuracy: 1e-15)
        XCTAssertEqual(geometry.right, 0.012861736334405145, accuracy: 1e-15)
        XCTAssertEqual(geometry.top, 0.05, accuracy: 1e-15)
        XCTAssertEqual(geometry.bottom, 0.04090909090909091, accuracy: 1e-15)
        XCTAssertEqual(geometry.color, "#050505")
        XCTAssertEqual(geometry.outerColor, "#fcfbf8")
        let ring = try XCTUnwrap(geometry.ring)
        XCTAssertEqual(ring.left, 0.01620267319286368, accuracy: 1e-15)
        XCTAssertEqual(ring.right, 0.005861068702934735, accuracy: 1e-15)
        XCTAssertEqual(ring.top, 0.01983587031161243, accuracy: 1e-15)
        XCTAssertEqual(ring.bottom, 0.02607345959514549, accuracy: 1e-15)
    }

    /// The picker miniature of an irregular edge (node: thumbnailGeometry).
    func testTheThumbnailOfAnIrregularEdge() throws {
        let geometry = try BorderLayout.thumbnailGeometry(style: .edgeBlackThin, sampleW: 300, sampleH: 200)
        XCTAssertEqual(geometry.aspect, 1.4672897196261683, accuracy: 1e-15)
        XCTAssertEqual(geometry.left, 0.02229299363057325, accuracy: 1e-15)
        XCTAssertEqual(geometry.right, 0.02229299363057325, accuracy: 1e-15)
        XCTAssertEqual(geometry.top, 0.03271028037383178, accuracy: 1e-15)
        XCTAssertEqual(geometry.bottom, 0.03271028037383178, accuracy: 1e-15)
        XCTAssertNil(geometry.ring)
        XCTAssertEqual(geometry.outerColor, "")
    }

    /// The export frame fits the budget (node: fitLayout with a fit that scales
    /// the picture down to the target long edge).
    func testTheExportFrameFitsTheBudget() throws {
        let expectations: [(BorderStyle, Int, Int, Int, Int, Int, Int)] = [
            // style, photoW, photoH, fittedW, fittedH, outerW, outerH
            (.none, 4096, 3072, 4096, 3072, 4096, 3072),
            (.none, 6000, 1000, 4096, 683, 4096, 683),
            (.none, 1600, 1067, 1600, 1067, 1600, 1067),
            (.film35, 4096, 3072, 3878, 2909, 4072, 4095),
            (.film35, 6000, 1000, 3900, 650, 4096, 948),
            (.film35, 1600, 1067, 1600, 1067, 1680, 1557),
            (.film120, 4096, 3072, 3925, 2944, 4096, 3233),
            (.film120, 6000, 1000, 4056, 676, 4095, 743),
            (.film120, 1600, 1067, 1600, 1067, 1662, 1171),
            (.polaroid, 4096, 3072, 3758, 2819, 4096, 3608),
            (.polaroid, 6000, 1000, 4015, 669, 4095, 856),
            (.polaroid, 1600, 1067, 1600, 1067, 1728, 1366),
        ]
        for (style, photoW, photoH, fittedW, fittedH, outerW, outerH) in expectations {
            let fitted = try BorderLayout.fit(
                style: style,
                photoW: photoW,
                photoH: photoH,
                maxOuterLongEdge: 4096,
                fit: BorderLayout.scaledFit
            )
            XCTAssertEqual(fitted.photoW, fittedW, "\(style.rawValue) \(photoW)x\(photoH)")
            XCTAssertEqual(fitted.photoH, fittedH, "\(style.rawValue) \(photoW)x\(photoH)")
            XCTAssertEqual(fitted.layout.outerW, outerW, "\(style.rawValue) \(photoW)x\(photoH)")
            XCTAssertEqual(fitted.layout.outerH, outerH, "\(style.rawValue) \(photoW)x\(photoH)")
            XCTAssertLessThanOrEqual(max(fitted.layout.outerW, fitted.layout.outerH), 4096)
        }
    }
}
