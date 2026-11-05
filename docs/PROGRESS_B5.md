# PROGRESS B5 - the name of the exported file

A bug of `FrameKit`: `ImageExporter.export` took the name of the **folder** of
the source picture instead of the name of the picture. The export of
`samples/landscape.jpg` was called `samples_frame.jpg`.

## The fix

`Sources/FrameKit/ImageExporter.swift`, in `export(image:source:options:)`:

```swift
name: source?.url.deletingPathExtension().lastPathComponent ?? "picture",
```

The name of the file is now the name of the source picture without its
extension (`landscape`) followed by the suffix (`landscape_frame.jpg`). The
folder of the source is still used for the **directory** of the export when no
output folder is given, and the file is never overwritten (`_2`, `_3`, ...).
The doc comment of `export` says it now.

## The test

`Tests/FrameKitTests/FrameKitExportTests.swift` (macOS only) has a new case:

* `testExportNamesTheFileAfterTheSourcePicture` - it loads
  `samples/landscape.jpg`, renders it, exports it with the suffix `_frame`
  into a temporary folder and checks that the name of the written file starts
  with `landscape_frame` (and that it is neither `samples_frame...` nor the
  name of the temporary folder).

The test is skipped (not failed) when the samples are missing.

## The check on the Linux box

```
$ swift build --build-system native            # Build complete
$ swift test  --build-system native             # Executed 44 tests, 0 failures
```

The target `FrameKitTests` does not exist on Linux (`Package.swift` adds it
inside `#if os(macOS)`), so the 44 tests are the same as before; the changed
files are parsed with `swiftc -parse` (no error).

## What I am not sure about

* **The test was never compiled.** The Linux box has no Core Graphics, so the
  target does not exist here; the files are only parsed.
* The other parts of the application (the CLI, the app) write the exact file
  names they want, so the change only shows in the exports of the app.
