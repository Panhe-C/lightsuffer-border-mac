import Foundation
import SwiftUI
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import FrameCore
import FrameKit

/// A picture of the list.
final class PhotoItem: Identifiable, ObservableObject {
    let id = UUID()
    let url: URL
    /// The name of the file (without the extension).
    var name: String { url.deletingPathExtension().lastPathComponent }
    @Published var thumbnail: NSImage?
    @Published var pixelSize: CGSize = .zero
    @Published var isLoaded = false

    init(url: URL) {
        self.url = url
    }
}

/// The request of the `--snapshot` mode of the command line.
struct SnapshotRequest {
    let output: URL
    let inputs: [URL]
}

/// The state of the application.
///
/// The settings live in the user defaults (`@AppStorage`); the setter of every
/// setting sends `objectWillChange`, so that the window follows them.
final class AppModel: ObservableObject {
    // MARK: - settings

    @AppStorage("style") var styleRaw: String = "none"
    @AppStorage("edgeText") var edgeText: String = "KODAK PORTRA 400"
    @AppStorage("mono") var mono: Bool = false
    @AppStorage("format") var formatRaw: String = ExportFormat.sameAsSource.rawValue
    @AppStorage("quality") var quality: Double = 0.9
    @AppStorage("suffix") var suffix: String = "_frame"
    @AppStorage("outputFolder") var outputFolder: String = ""

    /// The style of the frame.
    var style: BorderStyle { BorderStyle.normalized(styleRaw) }
    /// The format of the exported files.
    var format: ExportFormat { ExportFormat(rawValue: formatRaw) ?? .sameAsSource }
    /// The folder of the exported files (empty: next to the picture).
    var outputFolderURL: URL? {
        outputFolder.isEmpty ? nil : URL(fileURLWithPath: outputFolder)
    }
    /// Does the style print the name of the film stock?
    var printsEdgeText: Bool { style.printsEdgeText }
    /// Does the style print the light grey edge of a black and white stock?
    var allowsMonochrome: Bool { style == .film120 }

    // MARK: - state

    /// The pictures of the list.
    @Published var items: [PhotoItem] = []
    /// The selected pictures.
    @Published var selection: Set<URL> = []
    /// The picture of the preview.
    @Published var preview: NSImage?
    @Published var isRendering = false
    /// The cards of the style picker.
    @Published var cards: [BorderStyle: NSImage] = [:]
    /// The export.
    @Published var isExporting = false
    @Published var exportProgress: Double = 0
    @Published var exportStatus: String = ""
    @Published var lastExport: [URL] = []
    @Published var errorMessage: String?

    /// The request of the `--snapshot` mode (nil when there is none).
    var snapshotRequest: SnapshotRequest?

    private var previewTask: Task<Void, Never>?
    private var cardsTask: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?
    private var thumbnailTasks: [URL: Task<Void, Never>] = [:]
    private var renderGeneration = 0
    private var anchor: URL?

    init() {
        snapshotRequest = AppModel.parseSnapshotRequest(CommandLine.arguments)
    }

    /// The `--snapshot out.png file...` mode of the command line.
    static func parseSnapshotRequest(_ arguments: [String]) -> SnapshotRequest? {
        guard let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count else {
            return nil
        }
        let output = URL(fileURLWithPath: arguments[index + 1])
        let inputs = arguments[(index + 2)...].map { URL(fileURLWithPath: $0) }
        return SnapshotRequest(output: output, inputs: inputs)
    }

    // MARK: - the list of pictures

    /// Adds the pictures of the files and of the folders.
    func addFiles(_ urls: [URL]) {
        let found = FileDiscovery.discover(urls: urls)
        let known = Set(items.map { $0.url })
        var added: [PhotoItem] = []
        for url in found where !known.contains(url) {
            let item = PhotoItem(url: url)
            items.append(item)
            added.append(item)
        }
        if selection.isEmpty, let first = added.first {
            selection = [first.url]
            anchor = first.url
        }
        for item in added {
            loadThumbnail(item)
        }
        refreshAll()
    }

    /// Loads the little picture of one item.
    private func loadThumbnail(_ item: PhotoItem) {
        thumbnailTasks[item.url]?.cancel()
        let url = item.url
        thumbnailTasks[url] = Task { @MainActor [weak self] in
            let box = await Task.detached(priority: .utility) { () -> SendableImage? in
                guard let image = try? ImageLoader.thumbnail(url, maxPixelSize: 400) else { return nil }
                return SendableImage(image: image)
            }.value
            guard !Task.isCancelled, let box = box else { return }
            let size = CGSize(width: box.image.width, height: box.image.height)
            item.thumbnail = NSImage(cgImage: box.image, size: size)
            item.pixelSize = size
            item.isLoaded = true
            self?.thumbnailTasks[url] = nil
            self?.refreshCards()
        }
    }

    /// The pictures of the selection (in the order of the list).
    var selectedItems: [PhotoItem] {
        items.filter { selection.contains($0.url) }
    }

    /// The picture of the preview (the first of the selection).
    var currentItem: PhotoItem? {
        if let url = selection.first, let item = items.first(where: { $0.url == url }) {
            return item
        }
        return items.first
    }

    // MARK: - the selection

    /// Selects a picture (with the command and the shift key).
    func select(_ item: PhotoItem, extending: Bool, toggling: Bool) {
        if toggling {
            if selection.contains(item.url) {
                selection.remove(item.url)
            } else {
                selection.insert(item.url)
                anchor = item.url
            }
        } else if extending, let anchor = anchor, let start = items.firstIndex(where: { $0.url == anchor }),
                  let end = items.firstIndex(where: { $0.url == item.url }) {
            let range = min(start, end)...max(start, end)
            selection = Set(items[range].map { $0.url })
        } else {
            selection = [item.url]
            anchor = item.url
        }
        refreshAll()
    }

    /// Selects everything.
    func selectAll() {
        selection = Set(items.map { $0.url })
        anchor = items.first?.url
        refreshAll()
    }

    // MARK: - the preview and the cards

    /// Draws the preview and the cards of the style picker again.
    func refreshAll() {
        refreshPreview()
        refreshCards()
    }

    /// Draws the preview of the selected picture.
    func refreshPreview() {
        previewTask?.cancel()
        renderGeneration += 1
        let generation = renderGeneration
        guard let item = currentItem else {
            preview = nil
            isRendering = false
            return
        }
        let url = item.url
        let style = self.style
        let paint = FrameRenderer.paintOptions(
            PaintOptions(stockName: edgeText, monochrome: mono)
        )
        isRendering = true
        previewTask = Task { @MainActor [weak self] in
            let box = await Task.detached(priority: .userInitiated) { () -> SendableImage? in
                guard let source = try? ImageLoader.load(url) else { return nil }
                let options = FrameRenderOptions(style: style, paint: paint, previewLongEdge: 1400)
                guard let image = try? FrameRenderer().renderPreview(source, options: options) else {
                    return nil
                }
                return SendableImage(image: image)
            }.value
            guard !Task.isCancelled, generation == self?.renderGeneration, let box = box else { return }
            let size = CGSize(width: box.image.width, height: box.image.height)
            self?.preview = NSImage(cgImage: box.image, size: size)
            self?.isRendering = false
        }
    }

    /// Draws the cards of the style picker (the real painter on the picture).
    func refreshCards() {
        cardsTask?.cancel()
        let paint = FrameRenderer.paintOptions(
            PaintOptions(stockName: edgeText, monochrome: mono)
        )
        let photo = currentThumbnail()
        cardsTask = Task { @MainActor [weak self] in
            let boxes = await Task.detached(priority: .userInitiated) { () -> [BorderStyle: SendableImage] in
                var result: [BorderStyle: SendableImage] = [:]
                for candidate in BorderStyle.allCases {
                    let image = try? FrameRenderer().renderStyleCard(
                        style: candidate,
                        photo: photo,
                        size: CGSize(width: 128, height: 84),
                        paint: paint
                    )
                    if let image = image {
                        result[candidate] = SendableImage(image: image)
                    }
                }
                return result
            }.value
            guard !Task.isCancelled else { return }
            var pictures: [BorderStyle: NSImage] = [:]
            for (key, box) in boxes {
                let size = CGSize(width: box.image.width, height: box.image.height)
                pictures[key] = NSImage(cgImage: box.image, size: size)
            }
            self?.cards = pictures
        }
    }

    /// The little picture of the selected file (for the cards).
    private func currentThumbnail() -> CGImage? {
        guard let item = currentItem, let thumbnail = item.thumbnail else { return nil }
        let proposed = thumbnail
        guard let cgImage = proposed.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return cgImage
    }

    // MARK: - the settings

    func setStyle(_ value: String) {
        objectWillChange.send()
        styleRaw = value
        refreshAll()
    }

    func setEdgeText(_ value: String) {
        objectWillChange.send()
        edgeText = value
        refreshAll()
    }

    func setMonochrome(_ value: Bool) {
        objectWillChange.send()
        mono = value
        refreshAll()
    }

    func setFormat(_ value: String) {
        objectWillChange.send()
        formatRaw = value
    }

    func setQuality(_ value: Double) {
        objectWillChange.send()
        quality = value
    }

    func setSuffix(_ value: String) {
        objectWillChange.send()
        suffix = value
    }

    func setOutputFolder(_ value: String) {
        objectWillChange.send()
        outputFolder = value
    }

    // MARK: - the files

    /// The panel of the open button.
    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "打开"
        panel.message = "选择照片或文件夹"
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            let urls = panel.urls
            Task { @MainActor in
                self?.addFiles(urls)
            }
        }
    }

    /// The panel of the output folder.
    func presentFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        panel.message = "选择导出的文件夹"
        if let folder = outputFolderURL {
            panel.directoryURL = folder
        }
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self?.setOutputFolder(url.path)
            }
        }
    }

    /// Shows the exported files in the finder.
    func revealLastExport() {
        guard !lastExport.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(lastExport)
    }

    // MARK: - the export

    /// Exports every picture of the list.
    func exportAll() {
        export(items)
    }

    /// Exports the selected pictures.
    func exportSelected() {
        export(selectedItems)
    }

    /// Stops the running export.
    func cancelExport() {
        exportTask?.cancel()
        exportTask = nil
        isExporting = false
        exportStatus = "已取消"
    }

    /// Exports a list of pictures (the heavy work happens in the background).
    private func export(_ list: [PhotoItem]) {
        exportTask?.cancel()
        guard !list.isEmpty else { return }
        let style = self.style
        let paint = FrameRenderer.paintOptions(
            PaintOptions(stockName: edgeText, monochrome: mono)
        )
        let format = self.format
        let quality = self.quality
        let suffix = self.suffix
        let folder = outputFolderURL
        isExporting = true
        exportProgress = 0
        exportStatus = ""
        lastExport = []
        exportTask = Task { @MainActor [weak self] in
            var written: [URL] = []
            for (index, item) in list.enumerated() {
                if Task.isCancelled { break }
                let url = item.url
                let result = await Task.detached(priority: .userInitiated) { () -> Result<URL, Error> in
                    do {
                        let source = try ImageLoader.load(url)
                        let options = FrameRenderOptions(style: style, paint: paint)
                        let image = try FrameRenderer().renderFull(source, options: options)
                        let exporterOptions = ImageExporter.Options(
                            format: format,
                            quality: quality,
                            suffix: suffix,
                            outputDirectory: folder
                        )
                        return .success(try ImageExporter.export(image: image, source: source, options: exporterOptions))
                    } catch {
                        return .failure(error)
                    }
                }.value
                switch result {
                case .success(let url):
                    written.append(url)
                case .failure(let error):
                    self?.errorMessage = "\(error)"
                }
                self?.exportProgress = Double(index + 1) / Double(list.count)
            }
            guard !Task.isCancelled else {
                self?.isExporting = false
                return
            }
            self?.lastExport = written
            self?.isExporting = false
            self?.exportStatus = written.isEmpty ? "没有导出任何文件" : "已导出 \(written.count) 张照片"
        }
    }
}

/// A `CGImage` that may cross a thread.
struct SendableImage: @unchecked Sendable {
    let image: CGImage
}
