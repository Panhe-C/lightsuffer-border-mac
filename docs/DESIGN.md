# Light Suffer Frame: design (v1)

Native macOS app that ONLY adds film-style borders to photos. It ports the border system
of the WeChat Mini Program "light suffer胶片" (wx-spektrafilm, GPLv3, `utils/border.js`,
branch feat/film-border, commit 571f84f; reference copy: `/workspace/wx-spektrafilm/utils/border.js`
and its tests `/workspace/wx-spektrafilm/harness/test-border.mjs` on the build box).

Hard rules
- Display name "Light Suffer Frame" (Chinese UI strings are fine, e.g. 胶片边框). macOS 13+, universal
  (arm64 + x86_64). SwiftUI + Core Graphics + ImageIO + Core Text. GPLv3. No signing identity, no Apple
  Developer account, spend no money. Commit messages in English.
- The border never crops or alters photo pixels: it goes AROUND the image. Full original resolution on export.
- Output must match the mini program: same layout math, same seeded irregularity.
- The build box is Linux. Only the portable `FrameCore` target compiles there (Swift 6.4.2 toolchain).
  Everything that imports CoreGraphics/ImageIO/CoreText/SwiftUI/AppKit can ONLY be built and tested on GitHub
  Actions macOS runners. So that code must be written very carefully (no way to compile locally), guarded with
  `#if canImport(CoreGraphics)` / `#if os(macOS)` so the Linux build of the whole package still works.

Swift on the box:  `export LD_LIBRARY_PATH=$HOME/swift-shim; . ~/.local/share/swiftly/env.sh`
then `swift build --target FrameCore`, `swift test --filter FrameCoreTests`. (This swiftly toolchain is 6.4.2; the
code must also build with Xcode 16/26: tools-version 5.9, Swift 5 language mode, no Swift-6-only APIs.)

## Package layout (Package.swift already exists)
- `Sources/FrameCore` (portable, Foundation only): `BorderStyle`, `Layout` (computeLayout port), `SeededRandom`,
  `Canvas2D` protocol (the Canvas 2D subset border.js uses), `Painter` (line-by-line port of drawBorder and helpers),
  `RecordingCanvas` (logs every call as JSON-friendly arrays). ALREADY WRITTEN as a first draft: review it against
  border.js, fix compile errors, keep call order/arguments identical to the JS.
- `Sources/FrameKit` (macOS only): `CGCanvas: Canvas2D` (CGContext + CoreText, y-down), image loading, rendering,
  export (ImageIO), file discovery.
- `Sources/frame-cli`: CLI. Portable subcommands (`styles`, `layout`, `calls`) work everywhere; `render`, `icon`
  need FrameKit (macOS only, `#if canImport(CoreGraphics)`).
- `Sources/LightSufferFrame`: the SwiftUI app (macOS only; Package.swift only adds it on macOS).
- `Tests/FrameCoreTests` (portable XCTest), `Tests/FrameKitTests` (macOS only).

## Parity design
`Canvas2D` mirrors the JS ctx calls: save, restore, translate, rotate, scale, fillStyle, strokeStyle, lineWidth,
textAlign, font(size), fillRect, strokeRect, beginPath, moveTo, lineTo, arcTo, closePath, fill, fillText.
`RecordingCanvas` (Swift) and `tools/recording-context.mjs` (JS) log these identically (numbers compared with a
1e-6 relative tolerance; font logged as the numeric px size; measureText stub = utf16 length * fontSize * 0.6 in
both). `frame-cli calls --style S --width W --height H [--text T] [--mono|--no-mono]` prints the layout + call log
as JSON; `tools/dump-calls.mjs` does the same with the real `tools/border.js`; `tools/parity-check.mjs` compares
them for every style x sizes (landscape 3000x2000, portrait 2000x3000, square 2000x2000, 16:9 1920x1080, a tiny
64x48, panorama 4000x1200, and 1200x4000) and also with/without text and with mono on/off. `computeLayout` output
(JSON) is compared too. In parity mode the squeeze is the JS 0.8 (`--squeeze 0.8`, default for the recorder).

## FrameKit rendering
- Load with CGImageSource (index 0). Respect EXIF orientation: draw with the orientation transform (pixel exact,
  `interpolationQuality = .none` for 1:1 export), write orientation = 1 in the output metadata.
- Bitmap context in the SOURCE colour space when it is an RGB model (e.g. Display P3), else sRGB. 8 bit, or 16 bit
  when the source is 16 bit. noneSkipLast (white-initialised) when the source has no alpha, premultipliedLast with
  alpha. Colours in the painter are sRGB strings: create CGColors in sRGB so CG converts into the context space.
- Context is flipped once (translate(0,H), scale(1,-1)) so the painter works top-down like Canvas 2D. Photo is drawn
  un-flipped with its own flip inside save/restore.
- `CGCanvas`: arcTo -> `addArc(tangent1End:tangent2End:radius:)`, fill -> `fillPath()` (non-zero), text via CoreText
  `CTLine` with kCTForegroundColorFromContextAttributeName, baseline for "middle" = y + (ascent - descent)/2, text
  flipped back with scale(1,-1), textAlign right = shift by -width. Bold edge-print font: prefer
  "HelveticaNeue-CondensedBold", then "AvenirNextCondensed-Bold", else "Helvetica-Bold" (bold system font).
  `isCondensed` -> use `printSqueeze = 1` for 120; fallback font keeps the JS squeeze 0.8.
- Preview: render with a scaled CTM (scale = previewLongEdge / outerLongEdge) from a downsampled thumbnail
  (CGImageSourceCreateThumbnailAtIndex, WithTransform) so layout == full-res layout (computed on the real
  dimensions).
- Memory guard: refuse an output over 400 megapixels (clear error); autoreleasepool per image; process serially.

## Export
Formats: same as source, JPEG, HEIC, TIFF (PNG too). Quality slider 0.5-1.0 (JPEG/HEIC, kCGImageDestinationLossyCompressionQuality).
Preserve metadata: copy the source properties dictionary (EXIF, TIFF, GPS, IPTC...), fix orientation to 1 (top level
and TIFF), update EXIF PixelXDimension/PixelYDimension, drop read-only keys (PixelWidth/Height, ColorModel, Depth,
ProfileName, HasAlpha...). ICC: ImageIO embeds the context colour space profile. Filename `<name>_frame.<ext>` (suffix
editable), never overwrite (append `_2`, `_3`...). Output folder: chosen folder, or next to the source when unset.
Batch with progress + cancel (Task cancellation checked between images).

## App (SwiftUI, macOS 13)
Single `Window`; left thumbnail list (ScrollView + LazyVStack, own selection so ImageRenderer can snapshot it; multi
select with Cmd/Shift click), centre live preview (async render, cancel stale renders), right style picker
(grid of cards rendered with the real painter on the selected photo's thumbnail), edge-text TextField
(default "KODAK PORTRA 400", only for 35mm/120) + 黑白 toggle (light-grey print, 120 only), export panel
(format, quality, suffix, folder, 导出全部 / 导出所选, progress bar, cancel, reveal in Finder). Drag and drop files and
folders (recursive; JPEG, HEIC/HEIF, PNG, TIFF), an Open button (NSOpenPanel, files + folders), Dock/Finder open
via NSApplicationDelegate `application(_:open:)`. Settings in `@AppStorage` (style, text, mono, format, quality,
suffix, folder). `--snapshot out.png file...` launch argument: load files, render the main view with ImageRenderer
(scale 2, 1280x800) into a PNG and quit (used on CI for the screenshot; best effort).

## CI (.github/workflows/ci.yml, macos-15 or newest available)
1. checkout, setup-node, Xcode select if needed.  2. `swift build` + `swift test` (both test targets).
3. Parity: build frame-cli, run tools/dump-calls.mjs + `frame-cli calls`, compare (fail on mismatch); optionally
node-canvas render of the JS painter (continue-on-error) uploaded for visual comparison.
4. Universal release build (`swift build -c release --arch arm64 --arch x86_64`), `scripts/bundle-app.sh` makes
`Light Suffer Frame.app` (Info.plist, icon.icns generated by `frame-cli icon` + iconutil, ad-hoc `codesign -s -`
which is not an Apple account), zip it (`ditto -c -k --keepParent`), build a DMG with hdiutil (app +
/Applications symlink), verify `lipo -archs` has arm64 and x86_64.
5. Render samples: every style x `samples/*.jpg` (landscape, portrait, square, 16:9) with the universal CLI, plus
format round trips (sips makes HEIC/TIFF/PNG inputs; check EXIF + ICC survive using `sips -g` / a Swift test).
6. App screenshot (best effort): `--snapshot`, and a `screencapture` attempt.
7. Upload artifacts (app zip, DMG, samples, parity report, screenshot). On tag `v*` create a GitHub Release with
the zip + DMG (`permissions: contents: write`, `gh release create`).
