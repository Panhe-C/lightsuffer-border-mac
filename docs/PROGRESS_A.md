# PROGRESS A - portable core, parity tooling and tests

Task A of `docs/DESIGN.md`: the portable Swift core (the port of the film border
system of wx-spektrafilm), the command line interface, the parity tooling
against the JavaScript original, and the XCTest suite. Everything in this task
runs and is verified on the Linux build box.

## 1. FrameCore (portable, Foundation only)

`Sources/FrameCore` was a draft that did not even compile. It was reviewed line
by line against `utils/border.js` and fixed:

* `BorderConstants` is now `public` (it was used as the default value of a
  public initialiser, which is an error in Swift) and holds every constant of
  the JS (`FILM35_BAND`, `SPROCKET_*`, `FILM120_*`, `PRINT_SQUEEZE`, ...).
* `BorderStyle.edgeSpec` / `EdgeSpec` are public, `BorderStyle.normalized`
  replaces `normalizeStyle`.
* `Layout.swift`: `positive()` now mirrors the JS (round, then reject
  anything below one pixel or not finite); `compute(style:photoW:photoH:)` got
  a `Double` overload so that the JS error cases (`NaN`, `Infinity`) can be
  tested; `film120Blacks`, `film120Edge`, `thumbnailGeometry` and
  `fitLayout` (called `fit(style:photoW:photoH:maxOuterLongEdge:fit:)`) were
  added - they exist in the JS and the export plan of the app needs them.
* `RecordingCanvas` now restores the drawing state on `restore()` (like a real
  canvas) and logs the calls in exactly the vocabulary of the JS twin
  (`tools/recording-context.mjs`).
* `CallLog.swift` (new) replays a recorded log and returns the points of every
  call in device space (the transform stack applied). It is the twin of
  `devicePoints()` in `tools/recording-context.mjs` and is what the tests use
  to prove that no painted point ever falls inside the photo.

The constants, the formulas, the order of the random draws (24 values for the
120 film, 4 levels + 5 values per side for the irregular edges) and the order
and the arguments of the canvas calls are identical to the JS. The parity check
below proves it for every style.

## 2. frame-cli (portable subcommands)

`Sources/frame-cli/main.swift` (plain `CommandLine` parsing, no dependencies):

```
frame-cli styles                                   # the ids and the names, as JSON
frame-cli layout --style S --width W --height H     # the layout, as JSON
frame-cli calls  --style S --width W --height H     # {"layout": ..., "calls": [...]}
                [--text T] [--mono|--no-mono] [--frame-number N] [--squeeze 0.8]
frame-cli render ... / frame-cli icon ...           # macOS only (Core Graphics)
```

The JSON is written with `JSONSerialization` and `.sortedKeys`. `render` and
`icon` sit behind `#if canImport(CoreGraphics)`; on other platforms they print
a clear "this command needs macOS" error. On macOS they are stubs that wait
for the Core Graphics back end (FrameKit).

## 3. Tests (Tests/FrameCoreTests, XCTest, portable)

44 tests, all green on Linux. They are the port of the layout and painter
tests of `harness/test-border.mjs`:

| suite | tests | what |
| --- | --- | --- |
| BorderCatalogueTests | 5 | the catalogue, the names, `normalizeStyle`, the colours |
| LayoutTests | 6 | outer size = photo + margins for every style and aspect, invalid dimensions, symmetry, the Polaroid margins, the 35 mm strip along the long edge (landscape, portrait, panorama), linear scaling, the picker miniatures |
| Film120LayoutTests | 6 | the photo is not cropped, the thin margins, the wide print side, the irregular rebate, determinism, the fixed pattern in units of the photo, the mono stocks |
| EdgeStyleTests | 5 | the band widths stay in their range, the sides differ, determinism, the same shape at any size, four bands + one ring, the contour stays in the band and wobbles, the readable picker card |
| PainterGeometryTests | 4 | nothing is painted outside the frame, nothing inside the photo (transform stack applied), the four margin rectangles tile the frame, the Polaroid hairline |
| Film35PrintTests | 4 | the stock name, the numbers, the sprocket holes and their pitch, the arrows, the portrait strip, a long name is shrunk |
| Film120PrintTests | 8 | the print of the landscape / portrait / square picture, the scan margin, the light bleed, the mono print, the explicit flag, an overlong name |
| SeededRandomTests | 3 | the first values of the seeds 9 and 21 (computed with node from border.js), the determinism |
| ReferenceValueTests | 3 | the picker miniatures and `fitLayout` against the values of the JS |

## 4. Parity tooling (tools/)

* `tools/border.js` - a **verbatim** copy of `utils/border.js` of
  wx-spektrafilm (GPLv3, Panhe-C, commit 571f84f; the film modelling of
  spektrafilm by Andrea Volpato). Only a header comment with the attribution
  was added; the body is byte for byte identical (`diff` against the original
  is empty).
* `tools/recording-context.mjs` - the JS twin of `RecordingCanvas`: the same
  call vocabulary, `font` logged as the numeric px size, `measureText` =
  UTF-16 length x font size x 0.6, `textBaseline` ignored. It also replays a
  log into device space (`devicePoints`).
* `tools/dump-calls.mjs` - runs the original painter and prints the same JSON
  as `frame-cli calls`.
* `tools/parity-check.mjs` - runs both for the 10 styles x 7 sizes
  (3000x2000, 2000x3000, 2000x2000, 1920x1080, 64x48, 4000x1200, 1200x4000) x
  4 option sets (`Kodak Portra 400`, no text, `Ilford HP5 Plus` = automatic
  mono, `KODAK PORTRA 400` + `--mono`), compares the layout and the whole call
  log with a tolerance of 1e-6 (relative and absolute), writes
  `out/parity-report.json` and exits 1 on a mismatch. The path of the
  `frame-cli` binary is the first argument (default `.build/debug/frame-cli`,
  or `swift run frame-cli`).
* `tools/package.json` - `type: module`, `canvas` as an optional dependency.
* `tools/render-js.mjs` - renders every style of every picture of `samples/`
  with node-canvas and the original painter into `out/js/<name>_<style>.png`.
  Without node-canvas it prints what is missing and stops.

## 5. Results

```
$ swift build --build-system native            # Build complete
$ swift test  --build-system native             # Executed 44 tests, 0 failures
$ node tools/parity-check.mjs                   # 280/280 combinations match - PASS
$ node tools/render-js.mjs                      # 40 PNGs in out/js/
```

The parity report (`out/parity-report.json`) lists the 280 combinations, all of
them with `ok: true` and no difference. A deliberate mutation of one
coordinate (0.01) is detected by the checker, a deviation of 1e-9 is not (it is
below the tolerance). With a `frame-cli` that lies (one coordinate shifted by
0.5) the checker reports the differences and exits with 1.

`npm install` works in `tools/` on this box: node-canvas 3.2.3 is installed and
renders the reference frames (the 35 mm sprocket holes, the orange edge print
and the 120 rebate with its light bleed look right in `out/js/`).

## 6. Notes for the next task

* On this build box the default build system (llbuild) does not pass
  `LD_LIBRARY_PATH` to the linker, so `swiftc` cannot find `libncurses.so.6`:
  use `swift build --build-system native` (or `swift build --target FrameCore`,
  which does not link). This is an environment problem, not a package problem.
* `Sources/FrameKit` is still a stub (it must not import Apple frameworks
  unconditionally, otherwise the package does not build on Linux).
* `samples/` now holds four small synthetic pictures (landscape, portrait,
  square, 16:9) so that the render step has something to work with; they can
  be replaced by real photographs.
* `out/` and `tools/node_modules/` are ignored by git.
