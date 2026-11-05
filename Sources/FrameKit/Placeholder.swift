import Foundation

// FrameKit - the macOS back end of Light Suffer Frame.
//
// It bridges the portable FrameCore painter to Core Graphics (a `CGCanvas` that
// implements the `Canvas2D` protocol), loads images with ImageIO, respects the
// EXIF orientation and exports through ImageIO.
//
// Everything here needs Apple frameworks, so the whole file is guarded: the
// package must still build on Linux (CI parity runs there).
//
// The plan (docs/DESIGN.md, "FrameKit rendering"):
//
//   * `CGCanvas: Canvas2D` - CGContext + CoreText, y-down.
//   * image loading with CGImageSource (index 0, EXIF orientation applied).
//   * export with ImageIO (same format as the source, JPEG, HEIC, TIFF, PNG).

/// The name and version of the back end, shown in the about box.
public enum FrameKitInfo {
    public static let name = "FrameKit"
    public static let version = "0.1.0"
}
