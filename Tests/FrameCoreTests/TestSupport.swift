import XCTest

@testable import FrameCore

// The helpers of the ported tests: a recording canvas, the device space points
// of a call log and the small accessors of the recorded calls.

/// Paints a style on a recording canvas and returns the layout and the log.
func paint(
    _ style: BorderStyle,
    _ width: Int,
    _ height: Int,
    _ options: PaintOptions = PaintOptions()
) throws -> (layout: Layout, canvas: RecordingCanvas) {
    let layout = try BorderLayout.compute(style: style, photoW: width, photoH: height)
    let canvas = RecordingCanvas()
    BorderPainter.draw(on: canvas, layout: layout, options: options)
    return (layout, canvas)
}

/// The calls of one kind, e.g. "fillRect".
func calls(_ log: [CanvasCall], _ op: String) -> [CanvasCall] {
    log.filter { ($0.first as? String) == op }
}

/// The string argument of a call ("fillText" carries its text at index 1).
func text(_ call: CanvasCall) -> String {
    (call.count > 1 ? call[1] as? String : nil) ?? ""
}

/// The numeric arguments of a call.
func numbers(_ call: CanvasCall) -> [Double] {
    call.dropFirst().compactMap { $0 as? Double }
}

/// The font size of a call, as the JS recorder logs it.
func fontSize(_ call: CanvasCall) -> Double {
    call.count > 1 ? (call[1] as? Double ?? 0) : 0
}

/// A filled shape: its colour and its points in device space.
struct FilledShape {
    let color: String
    let points: [[Double]]
}

/// The filled shapes of a call log (the `fill` calls and their colour).
func filledShapes(_ log: [CanvasCall]) -> [FilledShape] {
    let device = CallLog.devicePoints(log)
    var color = "#000000"
    var shapes: [FilledShape] = []
    for (index, call) in log.enumerated() {
        guard let op = call.first as? String else { continue }
        switch op {
        case "fillStyle":
            color = text(call)
        case "fill":
            shapes.append(FilledShape(color: color, points: device[index]))
        default:
            break
        }
    }
    return shapes
}

/// A printed text: its content, its colour, its anchor point and its font size.
struct PrintedText {
    let text: String
    let color: String
    /// The anchor point in device space.
    let point: [Double]
    /// The font size in picture pixels.
    let fontSize: Double
}

/// The texts of a call log, in order.
func printedTexts(_ log: [CanvasCall]) -> [String] {
    calls(log, "fillText").map { text($0) }
}

/// The texts of a call log with their colour, position and font size.
func printedTextsDetailed(_ log: [CanvasCall]) -> [PrintedText] {
    let device = CallLog.devicePoints(log)
    var color = "#000000"
    var size = 0.0
    var result: [PrintedText] = []
    for (index, call) in log.enumerated() {
        guard let op = call.first as? String else { continue }
        switch op {
        case "fillStyle":
            color = text(call)
        case "font":
            size = fontSize(call)
        case "fillText":
            result.append(
                PrintedText(
                    text: text(call),
                    color: color,
                    point: device[index].first ?? [0, 0],
                    fontSize: size
                )
            )
        default:
            break
        }
    }
    return result
}

/// A call with the style that was active when it was made.
struct StyledCall {
    let op: String
    /// The fill colour (the stroke colour for a `strokeRect`).
    let color: String
    /// The points of the call in device space.
    let points: [[Double]]
    let call: CanvasCall
}

/// Every call of a log with the style that was active when it was made.
func styledCalls(_ log: [CanvasCall]) -> [StyledCall] {
    let device = CallLog.devicePoints(log)
    var fill = "#000000"
    var stroke = "#000000"
    var result: [StyledCall] = []
    for (index, call) in log.enumerated() {
        guard let op = call.first as? String else { continue }
        switch op {
        case "fillStyle":
            fill = text(call)
        case "strokeStyle":
            stroke = text(call)
        default:
            break
        }
        result.append(
            StyledCall(
                op: op,
                color: op == "strokeRect" ? stroke : fill,
                points: device[index],
                call: call
            )
        )
    }
    return result
}

/// The colour of the text of a call log (the last `fillStyle` before it).
func printedTextColors(_ log: [CanvasCall]) -> [String] {
    var color = "#000000"
    var colors: [String] = []
    for call in log {
        guard let op = call.first as? String else { continue }
        if op == "fillStyle" {
            color = text(call)
        } else if op == "fillText" {
            colors.append(color)
        }
    }
    return colors
}

/// Is the point inside the picture? (The picture is never painted.)
func isInsidePhoto(_ layout: Layout, _ point: [Double]) -> Bool {
    point[0] > Double(layout.left) + 0.5 && point[0] < Double(layout.left + layout.photoW) - 0.5 &&
        point[1] > Double(layout.top) + 0.5 && point[1] < Double(layout.top + layout.photoH) - 0.5
}

/// The picture sizes used by the JS tests.
let testAspects: [(width: Int, height: Int)] = [
    (4032, 3024), (3024, 4032), (3000, 2000), (2000, 3000),
    (3000, 3000), (4000, 1200), (1200, 4000), (64, 48),
]
