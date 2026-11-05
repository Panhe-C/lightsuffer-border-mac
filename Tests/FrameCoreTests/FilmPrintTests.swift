import XCTest

@testable import FrameCore

/// The edge print of the 35 mm film: the stock name, the frame numbers and the
/// sprocket holes.
final class Film35PrintTests: XCTestCase {
    func testTheStockNameTheNumbersAndTheHoles() throws {
        let (layout, canvas) = try paint(
            .film35, 3000, 2000,
            PaintOptions(stockName: "Kodak Portra 400", frameNumber: 7)
        )
        let texts = printedTextsDetailed(canvas.calls)
        XCTAssertTrue(texts.contains { $0.text == "KODAK PORTRA 400" }, "the stock name is printed in capitals")
        XCTAssertTrue(texts.contains { $0.text == "7" })
        XCTAssertTrue(texts.contains { $0.text == "7A" })
        XCTAssertTrue(texts.allSatisfy { $0.color == BorderConstants.edgePrintColor }, "orange-yellow edge print")

        // Landscape: the print sits in the bands (above and below the photo).
        for printed in texts {
            XCTAssertTrue(
                printed.point[1] < Double(layout.top) || printed.point[1] > Double(layout.top + layout.photoH)
            )
        }

        let holes = filledShapes(canvas.calls).filter { $0.color == BorderConstants.sprocketColor }
        XCTAssertGreaterThanOrEqual(holes.count, 14)
        XCTAssertEqual(holes.count % 2, 0, "sprocket holes on both edges")
        // Holes are inside the bands and clear of the photo.
        for hole in holes {
            let ys = hole.points.map { $0[1] }
            XCTAssertTrue(
                (ys.max() ?? 0) < Double(layout.top) || (ys.min() ?? 0) > Double(layout.top + layout.photoH)
            )
        }

        // The arrows are filled triangles in the edge print colour, not glyphs.
        let arrows = filledShapes(canvas.calls).filter { $0.color == BorderConstants.edgePrintColor }
        XCTAssertGreaterThanOrEqual(arrows.count, 2)

        // The holes keep the 135 pitch: 8 holes for every 36 mm frame, about.
        let perEdge = Double(holes.count) / 2
        XCTAssertLessThan(abs(perEdge - Double(layout.outerW) / (Double(layout.band) * 0.864)), 2)
    }

    func testAPortraitPictureRotatesTheStrip() throws {
        let (layout, canvas) = try paint(.film35, 2000, 3000, PaintOptions(stockName: "Kodak Portra 400"))
        let texts = printedTextsDetailed(canvas.calls)
        XCTAssertGreaterThanOrEqual(texts.count, 3)
        for printed in texts {
            XCTAssertTrue(
                printed.point[0] < Double(layout.left) || printed.point[0] > Double(layout.left + layout.photoW)
            )
        }
    }

    func testWithoutAStockNameOnlyTheNumbersArePrinted() throws {
        let (_, canvas) = try paint(.film35, 3000, 2000)
        // No three capital letters in a row: the stock name is not printed.
        let capitals = printedTexts(canvas.calls).filter { value in
            value.range(of: "[A-Z]{3}", options: .regularExpression) != nil
        }
        XCTAssertTrue(capitals.isEmpty, "no stock name")
        XCTAssertEqual(printedTexts(canvas.calls), ["12", "12A"])
    }

    func testALongNameIsShrunkToFit() throws {
        let name = "A very long film stock name that cannot fit the band at all, really"
        let (layout, canvas) = try paint(.film35, 3000, 2000, PaintOptions(stockName: name))
        let printed = try XCTUnwrap(printedTextsDetailed(canvas.calls).first { $0.text.count > 20 })
        XCTAssertLessThanOrEqual(
            Double(printed.text.count) * printed.fontSize * 0.6,
            Double(layout.photoW) * 0.62 + 1
        )
    }
}

/// The edge print of the 120 film: the stock name, the frame number and the
/// half frame number, in the wide black band.
final class Film120PrintTests: XCTestCase {
    func testThePrintOfALandscapePicture() throws {
        let (layout, canvas) = try paint(.film120, 3000, 2000, PaintOptions(stockName: "Kodak Portra 400"))
        let shapes = filledShapes(canvas.calls)

        // Medium format has no sprocket holes.
        XCTAssertFalse(shapes.contains { $0.color == BorderConstants.sprocketColor })

        // The white scan margin: the frame rectangle with the black strip cut out.
        let margin = shapes.filter { $0.color == BorderConstants.scanMarginColor }
        XCTAssertEqual(margin.count, 1)
        XCTAssertGreaterThanOrEqual(margin[0].points.count, 8, "the margin path has an outer rectangle and a hole")

        // The rebate is first painted as four rectangles around the photo.
        let black = styledCalls(canvas.calls).filter { $0.op == "fillRect" && $0.color == layout.color }
        XCTAssertEqual(black.count, 4)

        // The edge print: capitals, in the band above a landscape photo, left to right.
        let texts = printedTextsDetailed(canvas.calls)
        XCTAssertEqual(texts.map(\.text), ["KODAK PORTRA 400", "7", "7A"])
        XCTAssertTrue(texts.allSatisfy { $0.color == BorderConstants.edgePrintColor })
        for printed in texts {
            XCTAssertLessThan(printed.point[1], Double(layout.top), "the print sits in the top band")
            XCTAssertGreaterThan(
                printed.point[1],
                Double(layout.top) - layout.film!.black.top,
                "and inside the black"
            )
        }
        XCTAssertLessThan(texts[0].point[0], texts[1].point[0])
        XCTAssertLessThan(texts[1].point[0], texts[2].point[0])

        // The slight orange light bleed is plain filled slivers in the band.
        let fringe = shapes.filter { $0.color == BorderConstants.film120Fringe }
        XCTAssertGreaterThanOrEqual(fringe.count, 3)
    }

    func testABlackAndWhiteStockPrintsLightGrey() throws {
        let (_, canvas) = try paint(.film120, 3000, 2000, PaintOptions(stockName: "Kodak Tri-X 400"))
        let texts = printedTextsDetailed(canvas.calls)
        XCTAssertEqual(texts.count, 3)
        XCTAssertTrue(texts.allSatisfy { $0.color == BorderConstants.monoPrintColor })
        XCTAssertTrue(
            filledShapes(canvas.calls).contains { $0.color == BorderConstants.film120FringeMono }
        )
    }

    func testTheExplicitFlagWinsOverTheGuess() throws {
        let (_, canvas) = try paint(
            .film120, 3000, 2000,
            PaintOptions(stockName: "Kodak Portra 400", monochrome: true)
        )
        XCTAssertTrue(
            printedTextsDetailed(canvas.calls).allSatisfy { $0.color == BorderConstants.monoPrintColor }
        )
        let (_, other) = try paint(
            .film120, 3000, 2000,
            PaintOptions(stockName: "Kodak Tri-X 400", monochrome: false)
        )
        XCTAssertTrue(
            printedTextsDetailed(other.calls).allSatisfy { $0.color == BorderConstants.edgePrintColor }
        )
    }

    func testThePrintOfAPortraitPicture() throws {
        let (layout, canvas) = try paint(.film120, 2000, 3000, PaintOptions(stockName: "Kodak Portra 400"))
        let texts = printedTextsDetailed(canvas.calls)
        XCTAssertEqual(texts.count, 3)
        for printed in texts {
            XCTAssertLessThan(printed.point[0], Double(layout.left))
            XCTAssertGreaterThan(printed.point[0], Double(layout.left) - layout.film!.black.left)
        }
        // It reads bottom to top: the name starts below the numbers.
        XCTAssertGreaterThan(texts[0].point[1], texts[1].point[1])
        XCTAssertGreaterThan(texts[1].point[1], texts[2].point[1])
    }

    func testASquarePicturePrintsOnTheLeft() throws {
        let (layout, canvas) = try paint(.film120, 2000, 2000, PaintOptions(stockName: "Kodak Portra 400"))
        XCTAssertTrue(
            printedTextsDetailed(canvas.calls).allSatisfy { $0.point[0] < Double(layout.left) }
        )
    }

    func testAnOverlongNameIsShrunkNotCut() throws {
        let (layout, canvas) = try paint(
            .film120, 3000, 2000,
            PaintOptions(stockName: "An extremely long film stock name that would never fit the strip")
        )
        let printed = try XCTUnwrap(printedTextsDetailed(canvas.calls).first { $0.text.count > 20 })
        XCTAssertLessThanOrEqual(
            Double(printed.text.count) * printed.fontSize * 0.6 * BorderConstants.defaultPrintSqueeze,
            Double(layout.photoW) * 0.42 + 1
        )
    }

    func testWithoutAStockNameOnlyTheNumbersArePrinted() throws {
        let (_, canvas) = try paint(.film120, 3000, 2000)
        XCTAssertEqual(printedTexts(canvas.calls), ["7", "7A"])
    }

    func testTheFrameNumberCanBeChosen() throws {
        let (_, canvas) = try paint(.film120, 3000, 2000, PaintOptions(frameNumber: 21))
        XCTAssertEqual(printedTexts(canvas.calls), ["21", "21A"])
    }
}
