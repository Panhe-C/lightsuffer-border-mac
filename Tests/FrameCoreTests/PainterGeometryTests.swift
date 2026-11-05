import XCTest

@testable import FrameCore

/// The geometry of the painter: nothing is painted outside the frame and
/// nothing is painted inside the picture.
final class PainterGeometryTests: XCTestCase {
    func testNoBorderDrawsNothing() throws {
        for (width, height) in [(3000, 2000), (2000, 3000), (2000, 2000), (900, 1600)] {
            let (_, canvas) = try paint(.none, width, height, PaintOptions(stockName: "Kodak Portra 400"))
            XCTAssertEqual(canvas.calls.count, 0, "no border draws nothing")
        }
    }

    func testNothingIsPaintedOutsideTheFrameOrInsideThePhoto() throws {
        for style in BorderStyle.allCases {
            for (width, height) in [(3000, 2000), (2000, 3000), (2000, 2000), (900, 1600)] {
                let (layout, canvas) = try paint(style, width, height, PaintOptions(stockName: "Kodak Portra 400"))
                if style == .none { continue }
                let styled = styledCalls(canvas.calls)
                for call in styled {
                    for point in call.points {
                        XCTAssertGreaterThanOrEqual(point[0], -0.5, "\(style.rawValue) \(width)x\(height)")
                        XCTAssertLessThanOrEqual(point[0], Double(layout.outerW) + 0.5)
                        XCTAssertGreaterThanOrEqual(point[1], -0.5)
                        XCTAssertLessThanOrEqual(point[1], Double(layout.outerH) + 0.5)
                    }
                    if call.op == "fillRect" {
                        // A rectangle may touch the photo only along its edge.
                        let a = call.points[0]
                        let b = call.points[1]
                        let overlapW = min(b[0], Double(layout.left + layout.photoW)) - max(a[0], Double(layout.left))
                        let overlapH = min(b[1], Double(layout.top + layout.photoH)) - max(a[1], Double(layout.top))
                        XCTAssertFalse(
                            overlapW > 0.5 && overlapH > 0.5,
                            "\(style.rawValue) \(width)x\(height): a margin rectangle overlaps the photo"
                        )
                    }
                    if call.op == "fill" {
                        for point in call.points {
                            XCTAssertFalse(
                                isInsidePhoto(layout, point),
                                "\(style.rawValue) \(width)x\(height): a shape reaches into the photo"
                            )
                        }
                    }
                    if call.op == "fillText" {
                        XCTAssertFalse(
                            isInsidePhoto(layout, call.points[0]),
                            "\(style.rawValue): text inside the photo"
                        )
                    }
                }
            }
        }
    }

    func testTheMarginRectanglesTileTheFrame() throws {
        for style in BorderStyle.allCases {
            for (width, height) in [(3000, 2000), (2000, 3000), (2000, 2000), (900, 1600)] {
                let (layout, canvas) = try paint(style, width, height)
                if style == .none { continue }
                let rects = styledCalls(canvas.calls).filter { $0.op == "fillRect" && $0.color == layout.color }
                XCTAssertEqual(rects.count, 4)
                let area = rects.reduce(0.0) { sum, call in
                    let a = call.points[0]
                    let b = call.points[1]
                    return sum + abs((b[0] - a[0]) * (b[1] - a[1]))
                }
                XCTAssertEqual(
                    area,
                    Double(layout.outerW * layout.outerH - layout.photoW * layout.photoH),
                    accuracy: 0.5,
                    "\(style.rawValue): margin area"
                )
            }
        }
    }

    func testThePolaroidHasAHairline() throws {
        let (_, canvas) = try paint(.polaroid, 3000, 2000)
        XCTAssertTrue(styledCalls(canvas.calls).contains { $0.op == "strokeRect" })
    }
}
