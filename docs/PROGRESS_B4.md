# PROGRESS B4 - the tests of FrameKit, the bundle, the CI and the README

Task B4 of `docs/DESIGN.md`: the last pieces of the repository.

* `Tests/FrameKitTests/` - the tests of the back end (macOS only).
* `scripts/bundle-app.sh` - the `.app`, the zip and the DMG.
* `.github/workflows/ci.yml` - the continuous integration of GitHub Actions.
* `README.md` - the description of the project.
* `docs/PROGRESS_B4.md` - this file.

`FrameCore`, `FrameKit`, `frame-cli` and `LightSufferFrame` were **not**
changed (they only had to be read).

## 1. `Tests/FrameKitTests/` (macOS only)

`Package.swift` already adds the target inside `#if os(macOS)`, so the tests
only exist on macOS. Three files:

| file | what it holds |
| --- | --- |
| `FrameKitTestSupport.swift` | the helpers: the folder of the samples (`#filePath`), a temporary folder, the drawing of a picture into a top-down RGBA buffer (`rasterize`), the drawing of the source the way the renderer does it (`photoRaster`), the biggest difference of two pictures (`maximumDifference`) and the reading of a string of the metadata (`metadataString`) |
| `FrameKitRenderTests.swift` | the tests of the renderer and of the loader |
| `FrameKitExportTests.swift` | the tests of the exporter |

The tests:

* `testRenderFullHasTheSizeOfTheLayoutAndKeepsThePicture` - the full render of
  `samples/landscape.jpg` with the style `film120` has exactly the outer size
  of `BorderLayout.compute` (1869 x 1318 for the 1800 x 1200 sample) and every
  pixel of the picture is the pixel of the source (the biggest difference of
  the channels is 0, the test allows 2).
* `testRenderWithoutFrameCopiesEveryPixel` - the style `none` has no margin at
  all and the picture is copied exactly (the difference must be 0).
* `testFilm120PaintsTheMarginAndKeepsThePicture` - the black strip of the 120
  film is black (the colour of the style is `#050505`, the test allows 40 for
  the rounding), the scan margin outside of it is white and the picture is
  still the picture of the source.
* `testLoaderReadsTheSampleAndItsMetadata` - the size, the orientation, the
  type and the EXIF block (`Make` `Light Suffer Frame`, `Model`
  `Synthetic Sample Camera`) of the sample.
* `testUniqueURLNeverOverwrites` - the name of the first export is
  `picture_frame.jpg`, the second one is `picture_frame_2.jpg` and the third one
  is `picture_frame_3.jpg`.
* `testExportNeverOverwritesAnExistingFile` - two exports of the same picture
  write two different files.
* `testExportKeepsTheMetadataAndSetsTheOrientationToOne` - the orientation of
  the exported JPEG is `1` (the pixels are already oriented), the orientation of
  the TIFF and of the EXIF dictionaries is `1` too, and the `Make` and the
  `Model` of the source survive the export.

The tests are short and deterministic. They use
`FileManager.default.temporaryDirectory` and they are **skipped** (not failed)
when the samples are missing (`throw XCTSkip`).

## 2. `scripts/bundle-app.sh`

`bash scripts/bundle-app.sh [DEST]` (DEST is `dist` by default). It needs
macOS (`swift`, `iconutil`, `codesign`, `ditto`, `hdiutil`).

1. The two universal release binaries:
   `swift build -c release --arch arm64 --arch x86_64 --product LightSufferFrame`
   and the same for `frame-cli`. When the build did not make a universal
   binary, the two architectures are built apart (`--scratch-path`) and joined
   with `lipo`.
2. `Light Suffer Frame.app` with `Contents/MacOS/LightSufferFrame`,
   `Contents/MacOS/frame-cli` (the helper of the command line),
   `Contents/Resources/AppIcon.icns` and `Contents/Info.plist`
   (`CFBundleName` *Light Suffer Frame*, `CFBundleIdentifier`
   `com.lightsuffer.frame`, `CFBundleShortVersionString` `0.1.0`,
   `CFBundleVersion` `1`, `LSMinimumSystemVersion` `13.0`,
   `NSHighResolutionCapable` true, `CFBundleIconFile` `AppIcon` and the
   `CFBundleDocumentTypes` of the JPEG, the HEIC, the PNG and the TIFF).
3. The icon: `frame-cli icon "$TMP/AppIcon.iconset"` and
   `iconutil -c icns`.
4. The signature: `codesign --force --deep -s -` (ad hoc, no certificate).
5. The zip: `ditto -c -k --keepParent` ->
   `LightSufferFrame-0.1.0-universal.zip`.
6. The DMG: `hdiutil create ... -format UDZO` (the `.app` and a link to
   `/Applications`) -> `LightSufferFrame-0.1.0-universal.dmg`.
7. The check: `lipo -archs` must show `arm64` **and** `x86_64` for the two
   binaries, otherwise the script fails. The paths of the artifacts are printed
   at the end.

## 3. `.github/workflows/ci.yml`

The runner is `macos-15` (`macos-14` is the fallback). The permissions are
`contents: write`, but only the job `release` uses them.

The job `build`:

| step | what it does |
| --- | --- |
| checkout | `actions/checkout@v4` |
| setup node | `actions/setup-node@v4` with node 20 |
| the node tools | `npm ci --prefix tools` (node-canvas is an optional dependency) |
| swift build | the whole package |
| swift test | `FrameCoreTests` and (on macOS) `FrameKitTests` |
| the parity | `node tools/parity-check.mjs` - the job **fails** when a combination does not match (the report is copied to `dist/parity-report.json`) |
| the bundle | `bash scripts/bundle-app.sh dist` |
| the samples | every style x every picture of `samples/` with `frame-cli render` into `dist/samples/`, the round trip of the formats (`sips` makes the PNG, the TIFF and the HEIC, the frames are written as JPEG again) and the metadata (`sips -g all` and `mdls`) in `dist/samples/meta.txt`. The HEIC conversion is not fatal when the runner does not support it |
| the screenshot | `LightSufferFrame --snapshot dist/screenshot.png samples/landscape.jpg samples/portrait.jpg` (best effort: `continue-on-error`, one minute) |
| the artifacts | `actions/upload-artifact@v4` with the name `artifacts` and the path `dist/**` |

The job `release` has the condition `if: startsWith(github.ref,
'refs/tags/v')`: a push on a branch never creates a release. It downloads the
artifacts of the build and runs `gh release create` with the zip and the DMG.

**No tag was pushed and no release was created.**

## 4. `README.md`

The description of the project: what it does, the requirements (macOS 13+,
universal), the installation of the unsigned build (right click **Open**, the
*Privacy & Security* section of the system settings or `xattr -dr
com.apple.quarantine`), the command line (`styles`, `layout`, `calls`, `render`,
`icon`), the build from the sources, the parity with `wx-spektrafilm`
(`tools/border.js`) and the license (GPLv3). There is a short Chinese blurb at
the top. There is **no** claim about the App Store.

## The check on the Linux box

```
$ swift build --build-system native            # Build complete
$ swift test  --build-system native             # Executed 44 tests, 0 failures
$ node tools/parity-check.mjs                   # 280/280 combinations match - PASS
```

The new test target does not exist on Linux (`Package.swift` adds it inside
`#if os(macOS)`), so the 44 tests are the same as before. The three new test
files are parsed with `swiftc -parse` (no error).

## What I am not sure about

* **The tests of `FrameKit` were never compiled.** The Linux box has no Core
  Graphics, so the target does not exist here. The files are parsed and the
  names of the APIs were taken from the sources of `FrameKit`, but the first
  run on macOS may have to fix a typo (the most likely candidates are the
  constants of ImageIO and the `XCTSkip` of a helper).
* **The EXIF of the export.** The test asks that the `Make` and the `Model` of
  the source survive the export of a JPEG. ImageIO writes the TIFF dictionary
  of the source into the EXIF block of the JPEG, but this was not verified
  here; if the runner loses the two fields, the test says so.
* **The universal build.** `swift build --arch arm64 --arch x86_64` should
  give a universal binary, but the place of the products (`.build/apple/
  Products/Release`) depends on the version of SwiftPM. The script looks for
  the products, checks them with `lipo` and falls back to two builds joined
  with `lipo`, so it should work with both.
* **The name of the exported file.** `ImageExporter.export` takes the name of
  the **folder** of the source, not the name of the file: the export of
  `samples/landscape.jpg` is called `samples_frame.jpg` and not
  `landscape_frame.jpg`. It is a bug of `FrameKit`, which was not to be
  changed in this task; the tests and the continuous integration work around it
  (the CLI writes the exact file names).
* **The screenshot** needs a window server; the step is best effort and it
  does not fail the build.
