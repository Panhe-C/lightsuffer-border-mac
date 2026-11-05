import XCTest

@testable import FrameCore

/// The seeded generator: the same values as the JavaScript original
/// (mulberry32 in utils/border.js of wx-spektrafilm).
final class SeededRandomTests: XCTestCase {
    /// The first values of `node -e "..."` with the original border.js:
    ///
    ///     seededRandom(9)  -> 0.19872891809791327, 0.8512107962742448, ...
    ///     seededRandom(21) -> 0.4322912215720862, 0.4470290595199913, ...
    func testTheValuesMatchTheJavaScriptOriginal() {
        var nine = SeededRandom(seed: 9)
        XCTAssertEqual(nine.next(), 0.19872891809791327, accuracy: 1e-15)
        XCTAssertEqual(nine.next(), 0.8512107962742448, accuracy: 1e-15)
        XCTAssertEqual(nine.next(), 0.1417661067098379, accuracy: 1e-15)
        XCTAssertEqual(nine.next(), 0.8216717173345387, accuracy: 1e-15)
        XCTAssertEqual(nine.next(), 0.7238044005353004, accuracy: 1e-15)
        XCTAssertEqual(nine.next(), 0.6888616101350635, accuracy: 1e-15)
        XCTAssertEqual(nine.next(), 0.2627184335142374, accuracy: 1e-15)
        XCTAssertEqual(nine.next(), 0.919454253045842, accuracy: 1e-15)

        var twentyOne = SeededRandom(seed: 21)
        XCTAssertEqual(twentyOne.next(), 0.4322912215720862, accuracy: 1e-15)
        XCTAssertEqual(twentyOne.next(), 0.4470290595199913, accuracy: 1e-15)
        XCTAssertEqual(twentyOne.next(), 0.2832840313203633, accuracy: 1e-15)
        XCTAssertEqual(twentyOne.next(), 0.38238615170121193, accuracy: 1e-15)
        XCTAssertEqual(twentyOne.next(), 0.476709007518366, accuracy: 1e-15)
        XCTAssertEqual(twentyOne.next(), 0.8919890881516039, accuracy: 1e-15)
        XCTAssertEqual(twentyOne.next(), 0.8700839278753847, accuracy: 1e-15)
        XCTAssertEqual(twentyOne.next(), 0.3457998954690993, accuracy: 1e-15)
    }

    func testTheValuesAreInTheUnitIntervalAndDeterministic() {
        var first = SeededRandom(seed: 21)
        var second = SeededRandom(seed: 21)
        for _ in 0..<1000 {
            let value = first.next()
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThan(value, 1)
            XCTAssertEqual(value, second.next(), accuracy: 0)
        }
    }

    func testDifferentSeedsGiveDifferentSeries() {
        var nine = SeededRandom(seed: 9)
        var twentyOne = SeededRandom(seed: 21)
        XCTAssertNotEqual(nine.next(), twentyOne.next())
    }
}
