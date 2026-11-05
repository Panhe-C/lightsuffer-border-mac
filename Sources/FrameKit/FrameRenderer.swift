import Foundation
import FrameCore

#if canImport(CoreGraphics)
import CoreGraphics
import ImageIO

/// The errors of the renderer.
public enum FrameRendererError: Error, CustomStringConvertible {
    case tooLarge(width: Int, height: Int, limit: Int)
    case contextFailed
    case imageFailed

    public var description: String {
        switch self {
        case .tooLarge(let width, let height, let limit):
            return "the picture is too large: \(width)x\(height) pixels is more than \(limit) megapixels"
        case .contextFailed:
            return "cannot create the drawing context"
        case .imageFailed:
            return "cannot read the rendered picture"
        }
    }
}

/// The options of a render.
public struct FrameRenderOptions {
    /// The style of the frame.
    public var style: BorderStyle
    /// The options of the painter (the edge print, the frame number, ...).
    public var paint: PaintOptions
    /// The long edge of a preview, in pixels.
    public var previewLongEdge: Int

    public init(style: BorderStyle, paint: PaintOptions = PaintOptions(), previewLongEdge: Int = 1200) {
        self.style = style
        self.paint = paint
        self.previewLongEdge = previewLongEdge
    }
}

/// Renders the frame of a picture with Core Graphics.
///
/// The painter works in the pixels of the picture, so the layout is always
/// computed on the real size of the photo; a preview only scales the result.
public final class FrameRenderer {
    /// The largest picture the renderer draws (400 megapixels).
    public static let maximumPixels = 400_000_000

    public init() {}

    // MARK: - Full resolution

    /// The picture with the frame, at the full resolution of the source.
    public func renderFull(_ source: LoadedImage, options: FrameRenderOptions) throws -> CGImage {
        let layout = try BorderLayout.compute(style: options.style, photoW: source.width, photoH: source.height)
        let width = layout.outerW
        let height = layout.outerH
        try FrameRenderer.checkSize(width: width, height: height)
        guard let context = FrameRenderer.makeContext(
            width: width,
            height: height,
            colorSpace: source.colorSpace,
            hasAlpha: source.hasAlpha,
            bitDepth: source.bitDepth
        ) else {
            throw FrameRendererError.contextFailed
        }
        // 1:1 pixels, no smoothing.
        context.interpolationQuality = .none
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        // The context is flipped once: the painter works top down.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        FrameRenderer.drawPhoto(source, in: context, layout: layout)
        let canvas = CGCanvas(context: context)
        BorderPainter.draw(on: canvas, layout: layout, options: FrameRenderer.paintOptions(options.paint))
        guard let image = context.makeImage() else {
            throw FrameRendererError.imageFailed
        }
        return image
    }

    // MARK: - Preview

    /// A small picture with the frame.
    ///
    /// The layout is computed on the real size of the photo, so the preview
    /// shows exactly the frame of the full resolution render.
    public func renderPreview(_ source: LoadedImage, options: FrameRenderOptions) throws -> CGImage {
        let layout = try BorderLayout.compute(style: options.style, photoW: source.width, photoH: source.height)
        let outerWidth = CGFloat(layout.outerW)
        let outerHeight = CGFloat(layout.outerH)
        let longEdge = max(outerWidth, outerHeight)
        guard longEdge > 0 else { throw FrameRendererError.contextFailed }
        let scale = min(1, CGFloat(max(16, options.previewLongEdge)) / longEdge)
        let width = max(1, Int((outerWidth * scale).rounded()))
        let height = max(1, Int((outerHeight * scale).rounded()))
        guard let context = FrameRenderer.makeContext(
            width: width,
            height: height,
            colorSpace: source.colorSpace,
            hasAlpha: source.hasAlpha,
            bitDepth: 8
        ) else {
            throw FrameRendererError.contextFailed
        }
        context.interpolationQuality = .high
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        // The flip and the scale of the preview; the painter still works in
        // the pixels of the full resolution picture.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.scaleBy(x: scale, y: scale)
        // The photo comes from a downsampled thumbnail.
        let thumbnail = try ImageLoader.thumbnail(source.url, maxPixelSize: max(16, options.previewLongEdge))
        FrameRenderer.drawPhoto(
            source.withImage(thumbnail),
            in: context,
            layout: layout,
            destinationSize: CGSize(width: CGFloat(layout.photoW), height: CGFloat(layout.photoH))
        )
        let canvas = CGCanvas(context: context)
        BorderPainter.draw(on: canvas, layout: layout, options: FrameRenderer.paintOptions(options.paint))
        guard let image = context.makeImage() else {
            throw FrameRendererError.imageFailed
        }
        return image
    }

    // MARK: - Style card

    /// A card of the style picker: the frame of the style around a small
    /// picture (or around a grey rectangle when there is no picture).
    public func renderStyleCard(
        style: BorderStyle,
        photo: CGImage?,
        size: CGSize,
        paint: PaintOptions = PaintOptions()
    ) throws -> CGImage {
        let width = max(1, Int(size.width.rounded()))
        let height = max(1, Int(size.height.rounded()))
        // A picture of the shape of the card; the frame is drawn around it.
        let photoWidth = 1000
        let photoHeight = max(1, Int((1000 * Double(height) / Double(width)).rounded()))
        let layout = try BorderLayout.compute(style: style, photoW: photoWidth, photoH: photoHeight)
        let outerWidth = CGFloat(layout.outerW)
        let outerHeight = CGFloat(layout.outerH)
        let scale = min(
            CGFloat(width) / max(1, outerWidth),
            CGFloat(height) / max(1, outerHeight)
        )
        guard let context = FrameRenderer.makeContext(
            width: width,
            height: height,
            colorSpace: nil,
            hasAlpha: false,
            bitDepth: 8
        ) else {
            throw FrameRendererError.contextFailed
        }
        context.interpolationQuality = .high
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        // The frame is centred in the card.
        let offsetX = (CGFloat(width) - outerWidth * scale) / 2
        let offsetY = (CGFloat(height) - outerHeight * scale) / 2
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: offsetX, y: offsetY)
        context.scaleBy(x: scale, y: scale)
        // The picture area of the card.
        context.setFillColor(gray: 0.91, alpha: 1)
        context.fill(
            CGRect(
                x: CGFloat(layout.left),
                y: CGFloat(layout.top),
                width: CGFloat(layout.photoW),
                height: CGFloat(layout.photoH)
            )
        )
        if let photo = photo {
            context.saveGState()
            context.translateBy(x: CGFloat(layout.left), y: -(CGFloat(layout.top) + CGFloat(layout.photoH)))
            context.scaleBy(x: 1, y: -1)
            context.draw(photo, in: CGRect(x: 0, y: 0, width: CGFloat(layout.photoW), height: CGFloat(layout.photoH)))
            context.restoreGState()
        }
        let canvas = CGCanvas(context: context)
        BorderPainter.draw(on: canvas, layout: layout, options: FrameRenderer.paintOptions(paint))
        guard let image = context.makeImage() else {
            throw FrameRendererError.imageFailed
        }
        return image
    }

    // MARK: - Helpers

    /// The options of the painter.
    ///
    /// A real condensed font needs no horizontal squeeze of the 120 print; the
    /// fallback font keeps the 0.8 squeeze of the Mini Program.
    public static func paintOptions(_ paint: PaintOptions) -> PaintOptions {
        var options = paint
        if options.printSqueeze == BorderConstants.defaultPrintSqueeze {
            let font = CGCanvas.edgeFont(size: 10)
            if font.isCondensed {
                options.printSqueeze = 1
            }
        }
        return options
    }

    /// Refuses a picture that is too large to draw.
    public static func checkSize(width: Int, height: Int) throws {
        guard width > 0, height > 0 else { throw FrameRendererError.contextFailed }
        guard Double(width) * Double(height) <= Double(maximumPixels) else {
            throw FrameRendererError.tooLarge(width: width, height: height, limit: maximumPixels / 1_000_000)
        }
    }

    /// The bitmap context of the render.
    ///
    /// The colour space is the one of the source when it is an RGB model (a
    /// Display P3 picture stays a Display P3 picture), otherwise sRGB. 16 bit
    /// sources keep their depth when they have no alpha.
    public static func makeContext(
        width: Int,
        height: Int,
        colorSpace: CGColorSpace?,
        hasAlpha: Bool,
        bitDepth: Int
    ) -> CGContext? {
        let space = FrameRenderer.renderColorSpace(colorSpace)
        let deep = bitDepth > 8 && !hasAlpha
        let alphaInfo: CGImageAlphaInfo = hasAlpha ? .premultipliedLast : .noneSkipLast
        var info = CGBitmapInfo(rawValue: alphaInfo.rawValue)
        if deep {
            info = CGBitmapInfo(rawValue: alphaInfo.rawValue | CGBitmapInfo.byteOrder16Big.rawValue)
        }
        let bits = deep ? 16 : 8
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: bits,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: info.rawValue
        )
        if let context = context { return context }
        // The deep format is not always available; the simple one always is.
        guard let fallback = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: renderColorSpace(nil),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return nil
        }
        return fallback
    }

    /// The colour space of the render.
    public static func renderColorSpace(_ colorSpace: CGColorSpace?) -> CGColorSpace {
        if let colorSpace = colorSpace, colorSpace.model == .rgb {
            return colorSpace
        }
        return CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    }

    /// Draws the picture into its place of the frame.
    ///
    /// The context is flipped, so the picture needs its own flip; the EXIF
    /// orientation is applied by the transform of the source.
    public static func drawPhoto(
        _ source: LoadedImage,
        in context: CGContext,
        layout: Layout,
        destinationSize: CGSize? = nil
    ) {
        let photoHeight = CGFloat(layout.photoH)
        let width = destinationSize?.width ?? CGFloat(source.storedSize.width)
        let height = destinationSize?.height ?? CGFloat(source.storedSize.height)
        context.saveGState()
        context.translateBy(x: CGFloat(layout.left), y: -(CGFloat(layout.top) + photoHeight))
        context.scaleBy(x: 1, y: -1)
        context.concatenate(source.orientationTransform)
        context.draw(source.image, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.restoreGState()
    }
}

extension LoadedImage {
    /// The same picture with other pixels.
    ///
    /// The pixels are already oriented (a thumbnail of ImageIO is created with
    /// the transform), so the orientation of the source is not applied twice.
    func withImage(_ image: CGImage) -> LoadedImage {
        let size = CGSize(width: CGFloat(image.width), height: CGFloat(image.height))
        return LoadedImage(
            url: url,
            image: image,
            pixelSize: size,
            storedSize: size,
            orientation: 1,
            uniformTypeIdentifier: uniformTypeIdentifier,
            colorSpace: image.colorSpace ?? colorSpace,
            hasAlpha: hasAlpha,
            bitDepth: bitDepth,
            properties: properties
        )
    }
}
#endif
