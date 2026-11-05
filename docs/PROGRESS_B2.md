# PROGRESS B2 - the command line (render, icon) and the sample pictures

Task B2 of `docs/DESIGN.md`: the two macOS only subcommands of `frame-cli` and
a new set of sample pictures. `FrameCore` and `FrameKit` were not changed.

## 1. `frame-cli render` (macOS only)

```
frame-cli render --style film35 --text "KODAK PORTRA 400" \
                 [--mono|--no-mono] [--frame-number N] [--squeeze 0.8] \
                 [--format same|jpeg|heic|tiff|png] [--quality 0.9] [--suffix _frame] \
                 <input file|folder> <output file|folder>
```

The input may be a picture or a folder (the folders are searched recursively,
the hidden files are skipped). The output is a folder (the pictures are written
as `<name><suffix>.<ext>`, never overwriting an existing file) or, with a
single picture, the name of a file that is written exactly.

The command uses the back end of `FrameKit`: `FileDiscovery` finds the
pictures, `ImageLoader` reads them, `FrameRenderer.renderFull` draws the frame
at the full resolution and `ImageExporter` writes the result (the format of the
source, or JPEG, HEIC, TIFF or PNG with a quality). The paths of the written
files are printed, one per line.

The edge print of the 35 mm and the 120 film uses the condensed font of the
system when there is one (`FrameRenderer.paintOptions`), so the 120 print needs
no horizontal squeeze.

## 2. `frame-cli icon` (macOS only)

```
frame-cli icon out/LightSufferFrame.iconset
```

Draws the app icon: a dark rounded tile (the macOS icon grid, 22.37 % corner
radius) with a Polaroid of a warm sunset in the middle - the sunset is a
gradient with a sun and a ridge, the Polaroid comes from the painter itself
(the `polaroid` style around a 1000 x 1000 picture). The tile is drawn once at
1024 pixels and scaled down for the smaller sizes.

The command writes the ten files of an iconset (`icon_16x16.png` ...
`icon_512x512@2x.png`), so that `iconutil` can turn the folder into an
`icon.icns`.

## 3. The samples

`samples/` holds four new synthetic pictures (they replace the old ones):

| file | size | picture |
| --- | --- | --- |
| `landscape.jpg` | 1800 x 1200 | a warm sunset over three ridges |
| `portrait.jpg` | 1200 x 1800 | cold hills in the fog |
| `square.jpg` | 1500 x 1500 | a blue hour with a pale sun and a lake |
| `wide.jpg` | 1920 x 1080 | a panoramic sunset |

They are generated with numpy and Pillow (a sky gradient, a sun, fractal value
noise for the ridges, a fog band, a little Gaussian noise), written as
progressive JPEG with the quality 88 and an EXIF block (Make, Model, DateTime,
orientation 1). Every file is between 89 kB and 104 kB.

`samples/README.md` says that the pictures are synthetic and CC0.

## 4. Results on the Linux box

```
$ swift build --build-system native            # Build complete
$ swift test  --build-system native             # Executed 44 tests, 0 failures
$ node tools/parity-check.mjs                   # 280/280 combinations match - PASS
```

`styles`, `layout` and `calls` still work everywhere; `render` and `icon` print
"this command needs macOS (Core Graphics)" on the other platforms.

The macOS code was type checked against a stub of the Apple frameworks (the
same stubs as in PROGRESS_B1): `Sources/frame-cli/main.swift` compiles without
an error and without a warning with the Core Graphics code enabled.

## 5. Notes for the next task

* The SwiftUI app, the tests of `FrameKit`, the bundle script and the CI are
  not part of this task.
* `frame-cli render` writes the file of a single picture exactly where it is
  asked to; a folder never overwrites an existing file (the name gets `_2`,
  `_3`, ...).
* The icon is drawn by the CLI; the bundle script of the app can call
  `frame-cli icon` and `iconutil` (macOS only).
