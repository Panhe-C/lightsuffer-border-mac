import Foundation
import FrameCore

#if canImport(CoreGraphics)
// The macOS only back end (Core Graphics / ImageIO / Core Text).
import FrameKit
#endif

// Light Suffer Frame - command line front end.
//
// The portable subcommands (`styles`, `layout`, `calls`) work on every
// platform; they are the parity interface between the Swift port and the
// JavaScript original (see tools/parity-check.mjs).
//
// `render` and `icon` need Core Graphics and therefore macOS; on other
// platforms they print a clear error.

let toolName = "frame-cli"

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("\(toolName): \(message)\n".utf8))
    exit(code)
}

func usage() -> String {
    """
    \(toolName) - the Light Suffer Frame film border tool

    USAGE:
      \(toolName) styles
      \(toolName) layout --style S --width W --height H
      \(toolName) calls  --style S --width W --height H [--text T] [--mono|--no-mono]
                         [--frame-number N] [--squeeze 0.8]
      \(toolName) render --style S --input FILE --output FILE [--text T] [--mono|--no-mono]
      \(toolName) icon   --output FILE

    STYLES:
      \(BorderStyle.allCases.map(\.rawValue).joined(separator: ", "))

    The portable subcommands print JSON on stdout.
    """
}

// MARK: - arguments

struct Arguments {
    var command = ""
    var style = "none"
    var width: Int?
    var height: Int?
    var text = ""
    var monochrome: Bool?
    var frameNumber: Int?
    var squeeze = BorderConstants.defaultPrintSqueeze
    var input: String?
    var output: String?
    var help = false
}

func parseArguments(_ raw: [String]) throws -> Arguments {
    var args = Arguments()
    guard let first = raw.first else { throw CLIError.usage }
    args.command = first
    var index = 1
    while index < raw.count {
        let flag = raw[index]
        func value(_ name: String) throws -> String {
            guard index + 1 < raw.count else { throw CLIError.missingValue(name) }
            index += 1
            return raw[index]
        }
        switch flag {
        case "--style":
            args.style = try value("--style")
        case "--width":
            let text = try value("--width")
            guard let number = Int(text) else { throw CLIError.badValue("--width", text) }
            args.width = number
        case "--height":
            let text = try value("--height")
            guard let number = Int(text) else { throw CLIError.badValue("--height", text) }
            args.height = number
        case "--text":
            args.text = try value("--text")
        case "--mono":
            args.monochrome = true
        case "--no-mono":
            args.monochrome = false
        case "--frame-number":
            let text = try value("--frame-number")
            guard let number = Int(text) else { throw CLIError.badValue("--frame-number", text) }
            args.frameNumber = number
        case "--squeeze":
            let text = try value("--squeeze")
            guard let number = Double(text) else { throw CLIError.badValue("--squeeze", text) }
            args.squeeze = number
        case "--input":
            args.input = try value("--input")
        case "--output":
            args.output = try value("--output")
        case "-h", "--help":
            args.help = true
        default:
            throw CLIError.unknownArgument(flag)
        }
        index += 1
    }
    return args
}

enum CLIError: Error, CustomStringConvertible {
    case usage
    case unknownArgument(String)
    case missingValue(String)
    case badValue(String, String)
    case missingArgument(String)
    case invalidDimension(String)
    case macOSOnly
    case notImplementedYet(String)

    var description: String {
        switch self {
        case .usage:
            return "no command given"
        case .unknownArgument(let name):
            return "unknown argument \(name)"
        case .missingValue(let name):
            return "\(name) needs a value"
        case .badValue(let name, let value):
            return "\(name) is not a number: \(value)"
        case .missingArgument(let name):
            return "\(name) is required"
        case .invalidDimension(let value):
            return "invalid picture dimension: \(value)"
        case .macOSOnly:
            return "this command needs macOS (Core Graphics); the portable commands are: styles, layout, calls"
        case .notImplementedYet(let name):
            return "'\(name)' needs the Core Graphics back end (FrameKit), which is not implemented yet"
        }
    }
}

// MARK: - JSON output

/// JSON friendly value (JSONSerialization is picky about `Any`).
func jsonValue(_ value: Any) -> Any {
    switch value {
    case let value as String: return value as NSString
    case let value as Double: return value as NSNumber
    case let value as Int: return value as NSNumber
    case let value as Bool: return value as NSNumber
    default: return "\(value)" as NSString
    }
}

func emitJSON(_ object: Any) {
    guard JSONSerialization.isValidJSONObject(object) else {
        fail("the result is not valid JSON")
    }
    do {
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        )
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    } catch {
        fail("cannot serialize the result: \(error)")
    }
}

// MARK: - commands

func layout(for args: Arguments) throws -> Layout {
    guard let width = args.width else { throw CLIError.missingArgument("--width") }
    guard let height = args.height else { throw CLIError.missingArgument("--height") }
    do {
        return try BorderLayout.compute(style: .normalized(args.style), photoW: width, photoH: height)
    } catch {
        throw CLIError.invalidDimension("\(width)x\(height)")
    }
}

func layoutObject(_ layout: Layout) throws -> Any {
    let encoder = JSONEncoder()
    let data = try encoder.encode(layout)
    return try JSONSerialization.jsonObject(with: data)
}

func runStyles() {
    let styles = BorderStyle.allCases.map { ["id": $0.rawValue, "name": $0.displayName] as [String: String] }
    emitJSON(styles)
}

func runLayout(_ args: Arguments) throws {
    let layout = try layout(for: args)
    emitJSON(try layoutObject(layout))
}

func runCalls(_ args: Arguments) throws {
    let layout = try layout(for: args)
    let canvas = RecordingCanvas()
    let options = PaintOptions(
        stockName: args.text,
        frameNumber: args.frameNumber,
        monochrome: args.monochrome,
        printSqueeze: args.squeeze
    )
    BorderPainter.draw(on: canvas, layout: layout, options: options)
    let calls = canvas.calls.map { $0.map { jsonValue($0) } }
    emitJSON(["layout": try layoutObject(layout), "calls": calls])
}

// MARK: - macOS only commands

#if canImport(CoreGraphics)

func runRender(_ args: Arguments) throws {
    // The Core Graphics back end (FrameKit) comes with the macOS app; the
    // portable parity interface (styles / layout / calls) is complete.
    throw CLIError.notImplementedYet("render")
}

func runIcon(_ args: Arguments) throws {
    throw CLIError.notImplementedYet("icon")
}

#else

func runRender(_ args: Arguments) throws {
    throw CLIError.macOSOnly
}

func runIcon(_ args: Arguments) throws {
    throw CLIError.macOSOnly
}

#endif

// MARK: - main

let rawArguments = Array(CommandLine.arguments.dropFirst())

do {
    let args = try parseArguments(rawArguments)
    if args.help || args.command.isEmpty {
        print(usage())
        exit(args.command.isEmpty && !args.help ? 2 : 0)
    }
    switch args.command {
    case "styles":
        runStyles()
    case "layout":
        try runLayout(args)
    case "calls":
        try runCalls(args)
    case "render":
        try runRender(args)
    case "icon":
        try runIcon(args)
    case "-h", "--help", "help":
        print(usage())
    default:
        throw CLIError.unknownArgument(args.command)
    }
} catch let error as CLIError {
    fail("\(error)\n\n\(usage())", code: 2)
} catch {
    fail("\(error)")
}
