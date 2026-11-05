# PROGRESS B7 - the screenshot of the application (the ImageRenderer of macOS 13)

The GitHub Actions run 42009250435 builds `FrameKit` now; the only error left
was in the application (`LightSufferFrame`), in `runSnapshotIfNeeded()`:

```
renderer.render { _, context in
    if let image = context.makeImage() {
```

```
error: value of type '(CGContext) -> Void' has no member 'makeImage'
```

## Why

The code was written for the **macOS 14** API of SwiftUI:

| API | macOS 13 | macOS 14 |
|-----|----------|----------|
| `ImageRenderer.render` | `render(rasterizationScale:renderer: (CGContext) -> Void)` | the closure gets `(size: CGSize, context: CGContext)` |
| `CGContext.makeImage()` | does not exist | macOS 14+ |

The package asks for macOS 13 (`Package.swift`: `platforms: [.macOS(.v13)]`),
and the runner of the CI has the SDK of macOS 15, where the *overload* of
`render` with the two parameters exists, but the closure is the one of
macOS 13 - so the closure is `(CGContext) -> Void` and there is no
`makeImage()` to call.

## The fix

`Sources/LightSufferFrame/LightSufferFrameApp.swift`: the callback of
`render` is gone; the image that the renderer has already drawn is used:

```swift
let renderer = ImageRenderer(content: view)
renderer.scale = 2
if let image = renderer.cgImage
    ?? renderer.nsImage.flatMap({ $0.cgImage(forProposedRect: nil, context: nil, hints: nil) }) {
    writePNG(image, to: request.output)
}
NSApp.terminate(nil)
```

* `renderer.scale = 2` stays: the picture is written with twice the pixels.
* `renderer.cgImage` is the `CGImage` of the renderer (macOS 13+); it is the
  same picture as the one of the callback.
* `renderer.nsImage` is the fallback for the cases where `cgImage` is `nil`
  (the same call as in `AppModel.thumbnail`).
* `writePNG` is the function that was there before; it is not changed.
* `NSApp.terminate(nil)` is now outside of the callback: the application
  quits after the picture is written (before, the quitting was inside the
  callback).

The behaviour of the `--snapshot out.png file...` mode does not change: the
window is drawn into a PNG file and the application quits.

## The check on the Linux box

```
$ swift build --build-system native     # Build complete
$ swift test  --build-system native      # Executed 44 tests, 0 failures
```

The application is not built on Linux (`#if os(macOS)` in `Package.swift`),
so the changed file is parsed with `swiftc -parse` (no error) and the shape
of the new code (`??` with the two optionals and the `flatMap`) is type
checked against a small stand-in of the API on Linux.

## What I am not sure about

* The picture of the application is only taken in the step h) of the CI,
  which needs a window server; that step is `continue-on-error`, so a
  missing picture does not fail the build.
* `renderer.cgImage` draws the view off screen; if a part of the interface
  needs a real window, the picture can be empty. The CI shows the result.
