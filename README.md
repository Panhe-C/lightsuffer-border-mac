# Light Suffer Frame

A native macOS application that adds **film borders** to your photos, and
nothing else: the picture is never cropped and never changed, the frame is
drawn *around* it, at the full resolution of the original file.

Ten styles are available: a thin white edge, a Polaroid, a black edge, a 35 mm
film strip with its sprocket holes and its edge print, a 120 film strip with
its black border and its orange light leak, and four irregular film edges (thin
and thick, black and white).

**中文简介**：Light Suffer Frame 是一款 macOS 原生胶片边框应用，只给照片加边框，
不裁剪、不修改照片像素，导出时保持原始分辨率。支持细白边、拍立得、黑边、
35mm 胶片、120 胶片和四种不规则胶片边。软件免费、开源，许可证为 GPLv3。

## What it is

* A **SwiftUI application** (macOS 13 or newer) with a list of the pictures, a
  live preview, a picker of the ten styles, the text of the edge print
  (`KODAK PORTRA 400`, ...) and an export panel (JPEG, HEIC, TIFF, PNG, the
  quality, the suffix and the output folder).
* A **command line tool** (`frame-cli`) that renders the same frames and draws
  the icon of the application.
* A **port of the border system** of the WeChat Mini Program "light suffer胶片"
  (wx-spektrafilm): the same layout math, the same seeded irregularity, the
  same painter. The Swift port and the JavaScript original are compared call by
  call by the parity check (see below).

The export keeps the metadata of the source (EXIF, GPS, IPTC, the ICC profile)
and writes the orientation as `1`, because the pixels of the export are already
oriented. An existing file is never overwritten: the name gets `_2`, `_3`, ...

## Requirements

* macOS 13 (Ventura) or newer.
* An Intel or an Apple Silicon Mac: the release is a universal binary
  (arm64 + x86_64).

Nothing else: no account, no payment, no telemetry and no network access.

## Install

The releases are published as a **DMG** and as a **zip** of the `.app`. They
are **not signed** with a certificate of Apple (there is no Apple Developer
account behind this project), so Gatekeeper does not trust them at the first
start. This is normal, the app is not notarized:

1. Open the `LightSufferFrame-*.dmg` and drag **Light Suffer Frame** into
   *Applications* (or unzip the zip and move the `.app` into *Applications*).
2. The first time you open it, macOS refuses it. Choose one of these ways:
   * right click on the app in *Applications* (or on the DMG) and choose
     **Open**, then **Open** again in the dialog;
   * or open **System Settings › Privacy & Security**, scroll to the bottom
     (the section *Security* says that the app was blocked) and press
     **Open Anyway**;
   * or remove the quarantine flag from the terminal:
     ```sh
     xattr -dr com.apple.quarantine "/Applications/Light Suffer Frame.app"
     ```
3. The app opens the pictures you drop on it, the ones of the finder (the
   *Open…* button) and the ones of a whole folder.

## The command line

`frame-cli` is the same renderer as the application. It is inside the app
bundle (`Light Suffer Frame.app/Contents/MacOS/frame-cli`) and it can also be
built from the sources.

```
frame-cli styles
frame-cli layout --style S --width W --height H
frame-cli calls  --style S --width W --height H [--text T] [--mono|--no-mono]
                 [--frame-number N] [--squeeze 0.8]
frame-cli render --style S [--text T] [--mono|--no-mono] [--frame-number N]
                 [--format same|jpeg|heic|tiff|png] [--quality 0.9]
                 [--suffix _frame] <input file|folder> <output file|folder>
frame-cli icon   <output.iconset folder>
```

The styles are `none`, `thin-white`, `polaroid`, `black`, `film35`, `film120`,
`edge-black-thin`, `edge-black`, `edge-white-thin` and `edge-white`.

* `styles` prints the catalogue of the styles as JSON.
* `layout` prints the layout of a frame (the margins, the size of the picture,
  the geometry of the film) as JSON. It is the same JSON as the JavaScript
  original.
* `calls` prints the layout **and** the log of the drawing calls of the
  painter. It is the interface of the parity check.
* `render` writes the framed pictures. The input may be a picture or a folder
  (the folders are searched recursively); the output is a folder or, with a
  single picture, the exact name of a file. The format is the format of the
  source, or JPEG, HEIC, TIFF or PNG.
* `icon` writes the ten pictures of an iconset (for `iconutil`).

`styles`, `layout` and `calls` work on every platform (they need nothing but
Foundation); `render` and `icon` need Core Graphics and therefore macOS.

```sh
# the layout of a 120 frame around a 1800 x 1200 picture
frame-cli layout --style film120 --width 1800 --height 1200

# a batch of frames
frame-cli render --style film120 --text "KODAK PORTRA 400" samples/ out/frames/

# the icon of the application
frame-cli icon out/AppIcon.iconset && iconutil -c icns out/AppIcon.iconset
```

## Build from source

You need macOS and a Swift 5.9+ toolchain (Xcode 15 or newer).

```sh
git clone https://github.com/Panhe-C/lightsuffer-border-mac.git
cd lightsuffer-border-mac
swift build          # FrameCore, FrameKit, frame-cli and the application
swift test           # the tests of FrameCore and (on macOS) of FrameKit
bash scripts/bundle-app.sh dist
```

The last command writes the universal `.app`, the zip and the DMG into `dist/`.
It signs the bundle ad hoc (`codesign -s -`), so the result is as good as the
released one.

The layout of the package:

| folder | what it holds |
| --- | --- |
| `Sources/FrameCore` | the portable layout math and the painter (Foundation only) |
| `Sources/FrameKit` | the Core Graphics / ImageIO back end (macOS only) |
| `Sources/frame-cli` | the command line |
| `Sources/LightSufferFrame` | the SwiftUI application (macOS only) |
| `Tests/FrameCoreTests` | the tests of the layout and of the painter (every platform) |
| `Tests/FrameKitTests` | the tests of the renderer and of the export (macOS only) |
| `tools/` | the JavaScript original and the parity check |
| `samples/` | four synthetic pictures (CC0) |

## The parity with wx-spektrafilm

The border system is a port of `utils/border.js` of the WeChat Mini Program
**wx-spektrafilm** ("light suffer胶片", GPLv3). A copy of the original file
lives in `tools/border.js` and the JavaScript twin of the Swift canvas is
`tools/recording-context.mjs`.

`tools/parity-check.mjs` runs both implementations for every style, seven
picture sizes and four sets of options (280 combinations), and compares the
layout and **every drawing call, number by number** (a tolerance of 1e-6). It
also checks that neither implementation paints a single point inside the
picture.

```sh
swift build --product frame-cli
node tools/parity-check.mjs     # the report is written to out/parity-report.json
```

The continuous integration runs this check on every push: a mismatch fails the
build.

## The license

**GPLv3** (the same license as the Mini Program the border system comes from).
The file `LICENSE` is the GNU General Public License, version 3.

The four pictures of `samples/` are generated by a small program and are
**CC0** (public domain): they are not photographs and they have no third party
rights.

## The repository

<https://github.com/Panhe-C/lightsuffer-border-mac>

The issues and the pull requests are welcome. There is no App Store version
and none is planned: the application is free software and the builds are
published on the page of the releases of the repository.
