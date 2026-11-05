import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers
import FrameCore
import FrameKit

/// The window of the application: the list of the pictures, the preview and the
/// panel of the style and of the export.
struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    let delegate: AppDelegate
    @State private var isDropTargeted = false

    var body: some View {
        HSplitView {
            PhotoListView()
                .frame(minWidth: 190, idealWidth: 230, maxWidth: 320)
            PreviewPane()
                .frame(minWidth: 300, idealWidth: 520)
            SidePanel()
                .frame(minWidth: 250, idealWidth: 300, maxWidth: 380)
        }
        .frame(minWidth: 860, minHeight: 520)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .padding(2)
                .opacity(isDropTargeted ? 1 : 0)
        )
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .onReceive(NotificationCenter.default.publisher(for: AppDelegate.didOpenFiles)) { notification in
            if let urls = notification.object as? [URL] {
                model.addFiles(urls)
            }
        }
        .task {
            let urls = delegate.takeOpenedURLs()
            if !urls.isEmpty {
                model.addFiles(urls)
            }
        }
        .alert("出错了", isPresented: errorBinding) {
            Button("好") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    /// The alert of the errors.
    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }

    /// Takes the files of the drag and the drop.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            handled = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let url = ContentView.url(from: item) else { return }
                DispatchQueue.main.async {
                    model.addFiles([url])
                }
            }
        }
        return handled
    }

    /// The file of a dropped item.
    private static func url(from item: NSSecureCoding?) -> URL? {
        if let value = item as? URL {
            return value
        }
        if let value = item as? NSURL {
            return value as URL
        }
        if let data = item as? Data {
            if let url = URL(dataRepresentation: data, relativeTo: nil) {
                return url
            }
            if let text = String(data: data, encoding: .utf8), let url = URL(string: text) {
                return url
            }
        }
        return nil
    }
}

/// The list of the pictures.
struct PhotoListView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    model.presentOpenPanel()
                } label: {
                    Label("打开", systemImage: "folder")
                }
                Spacer()
                Text("\(model.items.count) 张")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(model.items) { item in
                        row(item)
                    }
                }
                .padding(8)
            }
        }
    }

    /// One picture of the list.
    private func row(_ item: PhotoItem) -> some View {
        let selected = model.selection.contains(item.url)
        return Button {
            let flags = NSEvent.modifierFlags
            model.select(item, extending: flags.contains(.shift), toggling: flags.contains(.command))
        } label: {
            HStack(spacing: 8) {
                thumbnail(item)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .lineLimit(1)
                    if item.pixelSize.width > 0 {
                        Text("\(Int(item.pixelSize.width))×\(Int(item.pixelSize.height))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(4)
            .background(selected ? Color.accentColor.opacity(0.28) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The little picture.
    @ViewBuilder
    private func thumbnail(_ item: PhotoItem) -> some View {
        if let image = item.thumbnail {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 52, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.18))
                .frame(width: 52, height: 40)
        }
    }
}

/// The preview of the selected picture.
struct PreviewPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color(nsColor: .underPageBackgroundColor)
                if let image = model.preview {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(14)
                        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 36))
                        Text("把照片或文件夹拖到这里")
                    }
                    .foregroundStyle(.secondary)
                }
                if model.isRendering {
                    ProgressView()
                }
            }
            Divider()
            HStack {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let item = model.currentItem {
                    Text(item.url.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The name of the style and of the film stock.
    private var caption: String {
        var parts = [model.style.displayName]
        if model.printsEdgeText && !model.edgeText.isEmpty {
            parts.append(model.edgeText.uppercased())
        }
        if model.allowsMonochrome && model.mono {
            parts.append("黑白")
        }
        return parts.joined(separator: " · ")
    }
}

/// The panel on the right: the style, the edge print and the export.
struct SidePanel: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                StylePicker()
                EdgeOptions()
                ExportPanel()
            }
            .padding(12)
        }
    }
}
