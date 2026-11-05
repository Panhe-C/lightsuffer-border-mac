import Foundation
import FrameCore

#if canImport(CoreGraphics)
// The macOS only back end (Core Graphics / ImageIO / Core Text).
import CoreGraphics
import FrameKit
import ImageIO
import UniformTypeIdentifiers
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
      \(toolName) render --style S [--text T] [--mono|--no-mono] [--frame-number N]
                         [--format same|jpeg|heic|tiff|png] [--quality 0.9]
                         [--suffix _frame] <input file|folder> <output file|folder>
      \(toolName) icon   <output.iconset folder>

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
    var format = "same"
    var quality = 0.9
    var suffix = "_frame"
    /// The arguments without a flag (the input and the output).
    var positional: [String] = []
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
        if !flag.hasPrefix("-") {
            // A file or a folder.
            args.positional.append(flag)
            index += 1
            continue
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
        case "--format":
            args.format = try value("--format")
        case "--quality":
            let text = try value("--quality")
            guard let number = Double(text) else { throw CLIError.badValue("--quality", text) }
            args.quality = number
        case "--suffix":
            args.suffix = try value("--suffix")
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
    case badFormat(String)
    case noPictures(String)
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
        case .badFormat(let name):
            return "unknown image format: \(name) (same, jpeg, heic, tiff, png)"
        case .noPictures(let path):
            return "no picture found in \(path)"
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

/// The format of the `--format` flag.
func exportFormat(_ name: String) throws -> ExportFormat {
    switch name.lowercased() {
    case "same", "sameassource", "source": return .sameAsSource
    case "jpeg", "jpg": return .jpeg
    case "heic": return .heic
    case "tiff", "tif": return .tiff
    case "png": return .png
    default: throw CLIError.badFormat(name)
    }
}

/// The format of a file name (the extension).
func exportFormat(ofFile url: URL) -> ExportFormat? {
    switch url.pathExtension.lowercased() {
    case "jpg", "jpeg", "jpe": return .jpeg
    case "heic", "heif": return .heic
    case "png": return .png
    case "tif", "tiff": return .tiff
    default: return nil
    }
}

/// `render`: the pictures of the input get the frame of the style.
func runRender(_ args: Arguments) throws {
    let inputPath = args.input ?? args.positional.first
    let outputPath = args.output ?? (args.positional.count > 1 ? args.positional[1] : nil)
    guard let inputPath = inputPath else { throw CLIError.missingArgument("<input>") }
    guard let outputPath = outputPath else { throw CLIError.missingArgument("<output>") }

    let style = BorderStyle.normalized(args.style)
    let format = try exportFormat(args.format)
    let inputs = FileDiscovery.discover(URL(fileURLWithPath: inputPath))
    guard !inputs.isEmpty else { throw CLIError.noPictures(inputPath) }

    // A condensed font needs no horizontal squeeze of the 120 print.
    let paint = FrameRenderer.paintOptions(
        PaintOptions(
            stockName: args.text,
            frameNumber: args.frameNumber,
            monochrome: args.monochrome,
            printSqueeze: args.squeeze
        )
    )
    let renderer = FrameRenderer()
    let renderOptions = FrameRenderOptions(style: style, paint: paint)
    let output = URL(fileURLWithPath: outputPath)
    var isDirectory: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: output.path, isDirectory: &isDirectory)
    // One picture and a file name: write exactly that file.
    var toFile = false
    if inputs.count == 1 {
        if exists && !isDirectory.boolValue {
            toFile = true
        } else if !exists && !output.pathExtension.isEmpty {
            toFile = true
        }
    } else if !exists && !output.pathExtension.isEmpty {
        throw CLIError.badValue("<output>", "several pictures need a folder")
    }
    var written: [URL] = []
    for input in inputs {
        let source = try ImageLoader.load(input)
        let image = try renderer.renderFull(source, options: renderOptions)
        if toFile {
            let targetFormat: ExportFormat
            if format != .sameAsSource {
                targetFormat = format
            } else if let byName = exportFormat(ofFile: output) {
                targetFormat = byName
            } else {
                targetFormat = ExportFormat.format(ofSourceType: source.uniformTypeIdentifier)
            }
            try ImageExporter.write(
                image: image,
                to: output,
                format: targetFormat,
                quality: args.quality,
                source: source
            )
            written.append(output)
        } else {
            let exporterOptions = ImageExporter.Options(
                format: format,
                quality: args.quality,
                suffix: args.suffix,
                outputDirectory: output
            )
            written.append(try ImageExporter.export(image: image, source: source, options: exporterOptions))
        }
    }
    for url in written {
        print(url.path)
    }
}

/// The pictures of the app icon: the sizes of an iconset.
let iconVariants: [(name: String, size: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

/// `icon`: the app icon as an iconset folder (for iconutil).
func runIcon(_ args: Arguments) throws {
    let outputPath = args.output ?? args.positional.first
    guard let outputPath = outputPath else { throw CLIError.missingArgument("<output.iconset>") }
    let directory = URL(fileURLWithPath: outputPath, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    guard let master = drawIconTile(size: 1024) else {
        throw CLIError.notImplementedYet("icon")
    }
    for variant in iconVariants {
        guard let image = resize(master, to: variant.size) else { continue }
        let url = directory.appendingPathComponent(variant.name)
        try writePNG(image, to: url)
        print(url.path)
    }
}

/// A picture of the sRGB colour space.
func sRGBColor(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1) -> CGColor {
    CGColor(red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
}

/// The sRGB colour space.
func sRGBSpace() -> CGColorSpace {
    CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
}

/// The app icon: a dark rounded tile with a Polaroid of a warm sunset.
func drawIconTile(size: Int) -> CGImage? {
    let side = CGFloat(size)
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: sRGBSpace(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }
    context.setAllowsAntialiasing(true)
    context.interpolationQuality = .high
    // The tile: a rounded square with a dark gradient.
    let margin = side * 0.055
    let tile = CGRect(x: margin, y: margin, width: side - margin * 2, height: side - margin * 2)
    let radius = tile.width * 0.2237
    context.addPath(CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.clip()
    let gradient = CGGradient(
        colorsSpace: sRGBSpace(),
        colors: [
            sRGBColor(0.13, 0.12, 0.11),
            sRGBColor(0.05, 0.05, 0.05),
        ] as CFArray,
        locations: [0, 1]
    )
    if let gradient = gradient {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: tile.midX, y: tile.maxY),
            end: CGPoint(x: tile.midX, y: tile.minY),
            options: []
        )
    }
    // The Polaroid of the sunset.
    if let photo = drawPolaroidSunset(width: 560) {
        let photoWidth = CGFloat(photo.width)
        let photoHeight = CGFloat(photo.height)
        let frameWidth: CGFloat = side * 0.66
        let frameHeight: CGFloat = photoHeight * frameWidth / photoWidth
        let frameX: CGFloat = (side - frameWidth) / 2
        let frameY: CGFloat = (side - frameHeight) / 2 - side * 0.012
        let frame = CGRect(x: frameX, y: frameY, width: frameWidth, height: frameHeight)
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -side * 0.008),
            blur: side * 0.022,
            color: sRGBColor(0, 0, 0, 0.55)
        )
        context.draw(photo, in: frame)
        context.restoreGState()
    }
    context.resetClip()
    return context.makeImage()
}

/// The Polaroid of the sunset: the photo with the frame of the painter.
func drawPolaroidSunset(width: Int) -> CGImage? {
    guard let layout = try? BorderLayout.compute(style: .polaroid, photoW: 1000, photoH: 1000) else {
        return nil
    }
    let scale = CGFloat(width) / CGFloat(layout.outerW)
    let pixelsWide = max(1, Int((CGFloat(layout.outerW) * scale).rounded()))
    let pixelsHigh = max(1, Int((CGFloat(layout.outerH) * scale).rounded()))
    guard let context = CGContext(
        data: nil,
        width: pixelsWide,
        height: pixelsHigh,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: sRGBSpace(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }
    context.setAllowsAntialiasing(true)
    context.interpolationQuality = .high
    // The paper.
    context.setFillColor(sRGBColor(0.957, 0.945, 0.910))
    context.fill(CGRect(x: 0, y: 0, width: CGFloat(pixelsWide), height: CGFloat(pixelsHigh)))
    // The picture: the photo rectangle of the layout, in the y-up space.
    let photoX: CGFloat = CGFloat(layout.left) * scale
    let photoWidth: CGFloat = CGFloat(layout.photoW) * scale
    let photoHeight: CGFloat = CGFloat(layout.photoH) * scale
    let photoY: CGFloat = CGFloat(pixelsHigh) - (CGFloat(layout.top) * scale) - photoHeight
    let photo = CGRect(x: photoX, y: photoY, width: photoWidth, height: photoHeight)
    drawSunset(context, in: photo)
    // The frame of the painter (the paper border and the hairline).
    context.translateBy(x: 0, y: CGFloat(pixelsHigh))
    context.scaleBy(x: 1, y: -1)
    context.scaleBy(x: scale, y: scale)
    BorderPainter.draw(on: CGCanvas(context: context), layout: layout, options: PaintOptions())
    return context.makeImage()
}

/// A warm sunset: the sky, the sun and the ridge.
func drawSunset(_ context: CGContext, in rect: CGRect) {
    context.saveGState()
    context.clip(to: rect)
    let gradient = CGGradient(
        colorsSpace: sRGBSpace(),
        colors: [
            sRGBColor(0.15, 0.09, 0.26),
            sRGBColor(0.55, 0.20, 0.33),
            sRGBColor(0.90, 0.44, 0.20),
            sRGBColor(0.99, 0.79, 0.44),
        ] as CFArray,
        locations: [0, 0.42, 0.72, 1]
    )
    if let gradient = gradient {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.midX, y: rect.maxY),
            end: CGPoint(x: rect.midX, y: rect.minY),
            options: []
        )
    }
    // The sun.
    let radius = rect.height * 0.15
    let centre = CGPoint(x: rect.midX + rect.width * 0.13, y: rect.minY + rect.height * 0.34)
    context.setFillColor(sRGBColor(1, 0.93, 0.72, 0.96))
    context.fillEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
    // The ridge.
    context.setFillColor(sRGBColor(0.07, 0.05, 0.07))
    context.beginPath()
    context.move(to: CGPoint(x: rect.minX, y: rect.minY))
    context.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.16))
    context.addLine(to: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.minY + rect.height * 0.26))
    context.addLine(to: CGPoint(x: rect.minX + rect.width * 0.46, y: rect.minY + rect.height * 0.13))
    context.addLine(to: CGPoint(x: rect.minX + rect.width * 0.68, y: rect.minY + rect.height * 0.24))
    context.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.11))
    context.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
    context.closePath()
    context.fillPath()
    context.restoreGState()
}

/// A smaller copy of a picture.
func resize(_ image: CGImage, to size: Int) -> CGImage? {
    guard size > 0 else { return nil }
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: sRGBSpace(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(size), height: CGFloat(size)))
    return context.makeImage()
}

/// Writes a PNG file.
func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        throw CLIError.notImplementedYet("icon")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw CLIError.notImplementedYet("icon")
    }
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
    case "-h", "--help":
        print(usage())
    default:
        throw CLIError.unknownArgument(args.command)
    }
} catch let error as CLIError {
    fail("\(error)\n\n\(usage())", code: 2)
} catch {
    fail("\(error)")
}
