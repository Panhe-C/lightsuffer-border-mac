import XCTest

@testable import FrameCore

/// The irregular film edges: a thin band right at the outermost edge.
final class EdgeStyleTests: XCTestCase {
    private struct Spec {
        let style: BorderStyle
        let name: String
        let lo: Double
        let hi: Double
    }

    private let specs: [Spec] = [
        Spec(style: .edgeBlackThin, name: "不规则细黑边", lo: 0.006, hi: 0.012),
        Spec(style: .edgeBlack, name: "不规则黑边", lo: 0.015, hi: 0.025),
        Spec(style: .edgeWhiteThin, name: "不规则细白边", lo: 0.006, hi: 0.012),
        Spec(style: .edgeWhite, name: "不规则白边", lo: 0.015, hi: 0.025),
    ]

    private let sizes: [(width: Int, height: Int)] = [
        (3000, 2000), (2000, 3000), (2000, 2000), (1600, 900), (6000, 1000), (1000, 6000),
    ]

    func testNamesAndColors() {
        for spec in specs {
            XCTAssertEqual(spec.style.displayName, spec.name)
            let expected = spec.style.rawValue.contains("black") ? "#050505" : "#fcfbf8"
            XCTAssertEqual(spec.style.color, expected)
        }
    }

    func testTheBandWidthsStayInTheirRange() throws {
        for spec in specs {
            for (width, height) in sizes {
                let layout = try BorderLayout.compute(style: spec.style, photoW: width, photoH: height)
                let short = Double(min(width, height))
                XCTAssertEqual(layout.photoW, width, "the photo is not cropped")
                XCTAssertEqual(layout.photoH, height)
                for side in Side.allCases {
                    let value = Double(layout[side]) / short
                    XCTAssertGreaterThanOrEqual(
                        value, spec.lo - 0.001,
                        "\(spec.style.rawValue) \(width)x\(height): a side is \(value) of the short edge"
                    )
                    XCTAssertLessThanOrEqual(value, spec.hi + 0.001)
                }
                // The sides differ visibly.
                let sides = Side.allCases.map { layout[$0] }
                XCTAssertGreaterThanOrEqual(Set(sides).count, 3, "\(spec.style.rawValue): the sides differ")
                // Deterministic.
                XCTAssertEqual(try BorderLayout.compute(style: spec.style, photoW: width, photoH: height), layout)
            }
        }
    }

    func testThePatternIsTheSameShapeAtAnyPhotoSize() throws {
        for spec in specs {
            let big = try BorderLayout.compute(style: spec.style, photoW: 4000, photoH: 3000)
            let small = try BorderLayout.compute(style: spec.style, photoW: 1000, photoH: 750)
            let bigEdge = try XCTUnwrap(big.edge)
            let smallEdge = try XCTUnwrap(small.edge)
            for side in Side.allCases {
                XCTAssertEqual(bigEdge.widths[side] / 4, smallEdge.widths[side], accuracy: 1e-9)
            }
            XCTAssertEqual(bigEdge.wobble, smallEdge.wobble)
            XCTAssertNotNil(bigEdge.rim)
            XCTAssertNotEqual(bigEdge.rim, big.color)
        }
    }

    func testPaintingFourBandsAndOneRing() throws {
        for spec in specs {
            for (width, height) in [(3000, 2000), (2000, 3000), (1600, 900)] {
                let (layout, canvas) = try paint(spec.style, width, height)
                let styled = styledCalls(canvas.calls)
                let rects = styled.filter { $0.op == "fillRect" }
                XCTAssertEqual(rects.count, 4)
                XCTAssertTrue(rects.allSatisfy { $0.color == layout.color })

                let rings = styled.filter { $0.op == "fill" }
                XCTAssertEqual(rings.count, 1)
                XCTAssertEqual(rings[0].color, spec.style.edgeSpec?.rim)
                XCTAssertFalse(styled.contains { $0.op == "fillText" }, "no print")

                // The contour stays inside the band, between 15 % and 70 % of the
                // band width from the outer edge.
                let contour = Array(rings[0].points.dropFirst(4))
                XCTAssertGreaterThan(contour.count, 200)
                for point in contour {
                    let toLeft = point[0]
                    let toRight = Double(layout.outerW) - point[0]
                    let toTop = point[1]
                    let toBottom = Double(layout.outerH) - point[1]
                    func inside(_ distance: Double, _ band: Int) -> Bool {
                        distance >= 0 && distance <= Double(band) * 0.7 + 0.01
                    }
                    XCTAssertTrue(
                        inside(toLeft, layout.left) || inside(toRight, layout.right) ||
                            inside(toTop, layout.top) || inside(toBottom, layout.bottom),
                        "\(spec.style.rawValue) \(width)x\(height): the contour left the band"
                    )
                    XCTAssertFalse(isInsidePhoto(layout, point))
                }

                // A wobble that is actually there: the top side of the contour
                // is not a straight line.
                let top = contour.filter { $0[1] < Double(layout.outerH) * 0.25 }.map { $0[1] }
                XCTAssertGreaterThan(
                    (top.max() ?? 0) - (top.min() ?? 0),
                    0.02 * Double(layout.top),
                    "\(spec.style.rawValue): the contour wobbles"
                )
            }
        }
    }

    func testThePickerCardShowsAReadableEdge() throws {
        for spec in specs {
            let card = try BorderLayout.thumbnailGeometry(style: spec.style, sampleW: 300, sampleH: 200)
            let photoHeight = 200.0
            let photoWidth = 300.0
            let cardTop = (card.top * photoHeight) / (1 - card.top - card.bottom)
            let cardLeft = (card.left * photoWidth) / (1 - card.left - card.right)
            // The JS test measures both against the short side of the sample.
            let least = 0.035 * photoHeight - 0.01
            XCTAssertGreaterThanOrEqual(cardTop, least)
            XCTAssertGreaterThanOrEqual(cardLeft, least)
        }
    }
}
