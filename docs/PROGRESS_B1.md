# PROGRESS B1 - FrameKit (the Core Graphics back end)

Task B1 of `docs/DESIGN.md`: the macOS back end of Light Suffer Frame. It bridges
the portable painter of `FrameCore` to Core Graphics, loads the pictures with
ImageIO, respects the EXIF orientation and writes the result with ImageIO.

Everything in `Sources/FrameKit` is inside `#if canImport(CoreGraphics)`, so the
package still builds on the Linux box (the Apple frameworks do not exist there;
the files compile to nothing). `FrameCore` was not touched.

## 1. `CGCanvas.swift` - the canvas

`CGCanvas: Canvas2D` draws into a `CGContext` whose user space is y-down with
the origin in the top left corner (the renderer flips the context once with
`translate(0, H)` + `scale(1, -1)`).

* `arcTo` -> `context.addArc(tangent1End:tangent2End:radius:)`, `fill` ->
  `fillPath()` (the non-zero winding rule), `fillRect`/`strokeRect` ->
  `fill(rect)`/`stroke(rect)`, the path calls -> `beginPath`/`move`/`addLine`/
  `closePath`.
* The text is drawn with Core Text: a `CTLine` with
  `kCTForegroundColorFromContextAttributeName` (the colour is the fill colour of
  the context). The baseline is the "middle" one (half an em box below the
  middle of the text); the text is flipped back with `scale(1, -1)` inside a
  save/restore, a right aligned text is shifted by its width.
* `measureText` is the typographic width of the line
  (`CTLineGetTypographicBounds`).
* The edge print font: `HelveticaNeue-CondensedBold`, then
  `AvenirNextCondensed-Bold`, else `Helvetica-Bold`. The name of the font that
  Core Text really used is checked, so a missing font is detected.
  `CGCanvas.isCondensed` tells whether a real condensed font was found (then
  the 120 print needs no horizontal squeeze).
* `CGColorParser` reads the colour strings of the painter (`#rrggbb`, `#rgb`,
  `rgb(...)`, `rgba(...)`) into an sRGB `CGColor`.

## 2. `ImageLoader.swift` - the pictures

`CGImageSource` (index 0) reads the picture, its properties (EXIF, TIFF, GPS,
IPTC...), its uniform type identifier, its colour space, its alpha flag and its
bit depth. The size of the picture is the *oriented* size: for the EXIF
orientations 5...8 the width and the height are swapped.

`LoadedImage.orientationTransform` maps the stored rectangle onto the oriented
one (all eight EXIF orientations; the formula of each one was checked with a
small affine geometry program).

`ImageLoader.thumbnail` makes a downsampled picture with
`kCGImageSourceCreateThumbnailWithTransform` (the orientation is baked in).

## 3. `FrameRenderer.swift` - the render

* `renderFull`: the layout is computed on the real size of the photo; the
  bitmap context is in the colour space of the source when it is an RGB model
  (a Display P3 picture stays a Display P3 picture), otherwise sRGB; 8 bit, or
  16 bit for a 16 bit source without alpha; `interpolationQuality = .none`
  (1:1 pixels). The context is flipped once, the picture gets its own flip
  inside a save/restore (with the orientation transform), then the painter
  draws the frame. A picture of more than 400 megapixels is refused.
* `renderPreview`: the same layout on the real size, but drawn with a scaled
  CTM into a small bitmap; the picture comes from a thumbnail.
* `renderStyleCard`: the frame of a style around a small picture (or a grey
  rectangle) for the picker.
* `FrameRenderer.paintOptions` sets `printSqueeze = 1` when the edge print
  font is a real condensed font; the fallback font keeps the 0.8 squeeze of the
  Mini Program.

## 4. `ImageExporter.swift` - the export

`sameAsSource`, `jpeg`, `heic`, `tiff`, `png`; the lossy quality
(`kCGImageDestinationLossyCompressionQuality`) for JPEG and HEIC. The metadata
of the source is kept, the orientation is set to 1 (top level, TIFF and EXIF),
the pixel dimensions of the EXIF are updated and the read only keys are
dropped. The file is named `<name><suffix>.<ext>` and is never overwritten
(`_2`, `_3`, ...). `export` throws and returns the URL of the file it wrote.

## 5. `FileDiscovery.swift` - the files

The pictures of the files and of the folders the user opened (recursive, hidden
files and folders are skipped): jpg, jpeg, jpe, heic, heif, png, tif, tiff.

## 6. Results on the Linux box

```
$ swift build --build-system native            # Build complete
$ swift test  --build-system native             # Executed 44 tests, 0 failures
$ node tools/parity-check.mjs                   # 280/280 combinations match - PASS
```

The macOS code cannot be compiled here, so it was type checked against a small
stub of the Apple frameworks (CoreGraphics, CoreText, ImageIO,
UniformTypeIdentifiers) in /tmp: the sources compile without an error and
without a warning. The colour parser and the eight orientation transforms were
checked with a small program.

## 7. Notes for the next task

* The SwiftUI app, the `render`/`icon` subcommands of the CLI, the CI and the
  samples are not part of this task.
* `CGCanvas` draws into a context that the renderer flips; a caller that uses
  the canvas on its own has to flip the context too.
* The edge print uses a condensed font when the system has one; the parity
  with the JavaScript original (which squeezes a bold sans by 0.8) is therefore
  only exact for the frame, not for the width of the text.
