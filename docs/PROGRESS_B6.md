# PROGRESS B6 - the FrameKit compile errors of the CI (macos-15)

The GitHub Actions run 42008200331 failed on `swift build` with eight compile
errors in `FrameKit` (the back end of Core Graphics / ImageIO / Core Text).
Every error is an API that the SDK of the runner does not have (or has with
another name); the behaviour of the code does not change.

## The fixes

| # | File | Before | After |
|---|------|--------|-------|
| 1 | `Sources/FrameKit/CGCanvas.swift:165` | `context.rotate(CGFloat(angle))` | `context.rotate(by: CGFloat(angle))` |
| 2 | `Sources/FrameKit/CGCanvas.swift:250` | `CTFontCreateUIFontForLanguage(...)` (returns `CTFont?`) | `?? CTFontCreateWithName("Helvetica-Bold" as CFString, pointSize, nil)` |
| 3 | `Sources/FrameKit/FrameRenderer.swift:238` | `let alphaInfo: CGAlphaInfo` | `let alphaInfo: CGImageAlphaInfo` (`.premultipliedLast` / `.noneSkipLast`) |
| 4 | `Sources/FrameKit/ImageExporter.swift:57` | `UTType(identifier: identifier)` | `UTType(identifier)` (the init has no label) |
| 5 | `Sources/FrameKit/ImageExporter.swift` (`metadata`) | `kCGImagePropertyExifOrientation` and nine `kCGImagePropertyTIFF...` constants | the raw names: `"Orientation"`, `"ImageWidth"`, `"ImageLength"`, `"BitsPerSample"`, `"SampleFormat"`, `"PhotometricInterpretation"`, `"SamplesPerPixel"`, `"RowsPerStrip"`, `"StripByteCounts"`, `"PlanarConfiguration"`, `"ColorMap"` (as `CFString`) |
| 6 | `Sources/FrameKit/ImageLoader.swift:161` | `kCGImagePropertyUniformTypeIdentifier` | `"UniformTypeIdentifier" as CFString` |
| 7 | `Sources/FrameKit/ImageLoader.swift:164` | `type.isImage` | `type.conforms(to: .image)` |
| 8 | `Sources/FrameKit/ImageLoader.swift:186` | `kCGImagePropertyTIFFDepth` | `"Depth" as CFString` (in the TIFF dictionary) |

The constants that the SDK does export stay as they are
(`kCGImagePropertyOrientation`, `kCGImagePropertyPixelWidth/Height`,
`kCGImagePropertyHasAlpha`, `kCGImagePropertyDepth`,
`kCGImagePropertyExifDictionary`, `kCGImagePropertyExifPixelX/YDimension`,
`kCGImagePropertyTIFFDictionary`, `kCGImagePropertyTIFFOrientation`,
`kCGImagePropertyTIFFX/YResolution`, `kCGImagePropertyTIFFResolutionUnit`).

The raw names are the values of the constants, so the metadata of the exports
is exactly the same as before (`"Orientation"`, `"ImageWidth"`, ...).

## The test target

`Tests/FrameKitTests/FrameKitExportTests.swift` used
`kCGImagePropertyExifOrientation` too; the test target is only built after
`FrameKit`, so the error only shows up now. It reads the key
`"Orientation" as CFString` now.

## The check on the Linux box

```
$ swift build --build-system native     # Build complete
$ swift test  --build-system native      # Executed 44 tests, 0 failures
$ node tools/parity-check.mjs            # 280/280 combinations match, PASS
```

The Apple code paths cannot be compiled here (no Core Graphics on Linux), so
they were type checked against a small stand-in of the SDK (the same
signatures, the same optionality) with the `canImport(CoreGraphics)` blocks
switched on: `FrameKit`, `frame-cli` and `FrameKitTests` compile without an
error.

## What I am not sure about

* The stand-in of the SDK is written from the documentation, so a difference
  between it and the real SDK of the runner cannot be found here; the CI
  build is the real proof.
* The application (`LightSufferFrame`) was not changed; it only uses
  `ExportFormat.allCases` of `FrameKit`.
