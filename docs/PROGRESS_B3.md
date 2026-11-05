# PROGRESS B3 - the macOS application (SwiftUI)

Task B3 of `docs/DESIGN.md`: the SwiftUI application of Light Suffer Frame
(macOS 13). `FrameCore`, `FrameKit` and `frame-cli` were not changed.

The application is only built on macOS (`Package.swift` adds the target inside
`#if os(macOS)`), so the Linux box only parses the sources.

## The files

| file | what it holds |
| --- | --- |
| `Sources/LightSufferFrame/LightSufferFrameApp.swift` | `@main` the application, the single `Window`, the menus, the `NSApplicationDelegateAdaptor` (the files that the finder opens) and the `--snapshot out.png file...` mode (`ImageRenderer`, scale 2, 640x400 points = 1280x800 pixels) |
| `Sources/LightSufferFrame/AppModel.swift` | the state of the application: the settings (`@AppStorage`), the list of the pictures, the selection, the preview, the cards of the picker, the export |
| `Sources/LightSufferFrame/ContentView.swift` | the window: the list of the pictures (left), the preview (middle), the panel of the style and of the export (right), the drag and the drop, the panel of the finder |
| `Sources/LightSufferFrame/StylePickerView.swift` | the grid of the ten styles (the cards are drawn with the real painter) and the text of the edge print |
| `Sources/LightSufferFrame/ExportPanel.swift` | the format, the quality, the suffix, the folder, 导出全部 / 导出所选, the progress and 取消 |

## What it does

* **The list** (`ScrollView` + `LazyVStack`): the little pictures of the files,
  the name and the size. Click selects, ⌘ adds or removes, ⇧ extends the
  selection from the last click.
* **The preview**: `FrameRenderer.renderPreview` (the layout is computed on the
  real size of the photo, the picture comes from a thumbnail). Every change
  (style, text, 黑白, selection) starts a new render and throws the old one
  away (a counter and the cancellation of the task).
* **The style picker**: the ten styles of `BorderStyle.allCases`, drawn with
  `FrameRenderer.renderStyleCard` (the painter on the little picture of the
  selected file). The name of the film stock and the 黑白 switch only appear
  for the 35 mm and the 120 film (the 黑白 switch only for the 120).
* **The export**: the format (the format of the source, JPEG, HEIC, TIFF, PNG),
  the quality, the suffix and the folder (`NSOpenPanel`); 导出全部 and 导出所选
  write the files with `ImageExporter` (never overwriting), the progress bar
  shows the work and 取消 stops it; 在访达中显示 opens the finder.
* **The files**: the 打开 button (`NSOpenPanel`, files *and* folders), the drag
  and the drop of files and folders (`FileDiscovery` walks the folders
  recursively) and the files that the finder or the dock opens
  (`application(_:open:)`).
* **The settings** are in the user defaults (`@AppStorage`): the style, the
  text of the edge print, 黑白, the format, the quality, the suffix and the
  output folder.

The heavy work (the thumbnails, the preview, the cards, the export) happens in
`Task.detached`; only the interface is touched on the main actor.

## The check on the Linux box

```
$ swift build --build-system native            # Build complete
$ swift test  --build-system native             # Executed 44 tests, 0 failures
$ node tools/parity-check.mjs                   # 280/280 combinations match - PASS
```

The SwiftUI code cannot be compiled here. `AppModel.swift` was type checked
against a small stub of SwiftUI and AppKit (the same trick as in PROGRESS_B1):
it compiles without an error. The views were only parsed (`swiftc -parse`).

## The APIs I am not sure about

The first build on macOS may have to fix these:

* `ImageRenderer.render { size, context in ... }` and `renderer.scale = 2` -
  the completion handler of macOS 13 (the `nsImage` property is the simpler
  alternative).
* `@AppStorage` in an `ObservableObject`: the value is written correctly, but
  the class does not get `objectWillChange` from the wrapper, so every setter
  of the model sends it by hand (`objectWillChange.send()`).
* `EventModifiers([.command, .shift])` - the array literal of an `OptionSet`
  should work, but the explicit initialiser is used to be sure.
* `NotificationCenter.default.publisher(for:)` needs `import Combine` (it is
  there).
* `NSItemProvider.loadItem(forTypeIdentifier:)` returns the file as `Data`
  (the URL data representation), as `URL` or as `NSURL`; all three are tried.
* `Divider()` inside a `CommandMenu` is not a `Command`, so it was removed.
* `NSEvent.modifierFlags` gives the modifiers of the click that is handled
  (the ⌘ and ⇧ of the selection).

## The next task

The tests of `FrameKit` (macOS only), the bundle script (`scripts/bundle-app.sh`
with `frame-cli icon` + `iconutil`), the continuous integration and the README
of the repository.
