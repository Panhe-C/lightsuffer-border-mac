import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers
import FrameCore
import FrameKit

/// The delegate of the application: it receives the files that the user opens
/// with the finder or with the dock.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The files that were opened (and are not handled yet).
    private(set) var openedURLs: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        openedURLs.append(contentsOf: urls)
        NotificationCenter.default.post(name: AppDelegate.didOpenFiles, object: urls)
    }

    /// Takes the opened files away.
    func takeOpenedURLs() -> [URL] {
        let urls = openedURLs
        openedURLs = []
        return urls
    }

    static let didOpenFiles = Notification.Name("LightSufferFrame.didOpenFiles")
}

/// Light Suffer Frame - the macOS application.
///
/// One window: the list of the pictures on the left, the preview in the middle
/// and the style picker and the export panel on the right.
@main
struct LightSufferFrameApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Light Suffer Frame", id: "main") {
            ContentView(delegate: delegate)
                .environmentObject(model)
                .task { await runSnapshotIfNeeded() }
        }
        .windowResizability(.contentMinSize)
        .commands { menu }
    }

    /// The menus of the application.
    @CommandsBuilder
    private var menu: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("打开…") {
                model.presentOpenPanel()
            }
            .keyboardShortcut("o", modifiers: .command)
        }
        CommandMenu("导出") {
            Button("导出全部") {
                model.exportAll()
            }
            .keyboardShortcut("e", modifiers: EventModifiers([.command, .shift]))
            Button("导出所选") {
                model.exportSelected()
            }
            .keyboardShortcut("e", modifiers: .command)
            Button("在访达中显示") {
                model.revealLastExport()
            }
            .disabled(model.lastExport.isEmpty)
        }
    }

    /// The `--snapshot out.png file...` mode: it draws the window into a PNG
    /// file and quits (the continuous integration takes the picture).
    @MainActor
    private func runSnapshotIfNeeded() async {
        guard let request = model.snapshotRequest else { return }
        model.snapshotRequest = nil
        model.addFiles(request.inputs)
        // The little pictures of the list need a moment.
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        let view = ContentView(delegate: delegate)
            .environmentObject(model)
            .frame(width: 640, height: 400)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        renderer.render { _, context in
            if let image = context.makeImage() {
                writePNG(image, to: request.output)
            }
            NSApp.terminate(nil)
        }
    }
}

/// Writes a PNG file.
func writePNG(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        return
    }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}
