import SwiftUI
import FrameCore
import FrameKit

/// The panel of the export: the format, the quality, the suffix, the folder
/// and the progress.
struct ExportPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("导出")
                .font(.headline)

            Picker(
                "格式",
                selection: Binding(get: { model.formatRaw }, set: { model.setFormat($0) })
            ) {
                ForEach(ExportFormat.allCases, id: \.rawValue) { format in
                    Text(format.displayName).tag(format.rawValue)
                }
            }

            if model.format.supportsQuality {
                HStack(spacing: 8) {
                    Text("质量")
                        .font(.caption)
                    Slider(
                        value: Binding(get: { model.quality }, set: { model.setQuality($0) }),
                        in: 0.5...1.0
                    )
                    Text("\(Int((model.quality * 100).rounded()))%")
                        .font(.caption)
                        .monospacedDigit()
                        .frame(width: 38, alignment: .trailing)
                }
            }

            HStack(spacing: 8) {
                TextField(
                    "后缀",
                    text: Binding(get: { model.suffix }, set: { model.setSuffix($0) })
                )
                .textFieldStyle(.roundedBorder)
                Button("选择文件夹…") {
                    model.presentFolderPanel()
                }
            }

            if !model.outputFolder.isEmpty {
                Text(model.outputFolder)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            } else {
                Text("保存在原图旁边")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button("导出全部") {
                    model.exportAll()
                }
                .disabled(model.items.isEmpty || model.isExporting)
                Button("导出所选") {
                    model.exportSelected()
                }
                .disabled(model.selectedItems.isEmpty || model.isExporting)
            }

            if model.isExporting {
                ProgressView(value: model.exportProgress)
                HStack {
                    Text("\(Int((model.exportProgress * 100).rounded()))%")
                        .font(.caption)
                        .monospacedDigit()
                    Spacer()
                    Button("取消") {
                        model.cancelExport()
                    }
                    .font(.caption)
                }
            }

            if !model.exportStatus.isEmpty {
                HStack(spacing: 8) {
                    Text(model.exportStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("在访达中显示") {
                        model.revealLastExport()
                    }
                    .font(.caption)
                    .disabled(model.lastExport.isEmpty)
                }
            }
        }
    }
}
