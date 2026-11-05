import SwiftUI
import FrameCore
import FrameKit

/// The grid of the ten styles; the cards are drawn with the real painter.
struct StylePicker: View {
    @EnvironmentObject private var model: AppModel
    private let columns = [GridItem(.adaptive(minimum: 116), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("胶片边框")
                    .font(.headline)
                Spacer()
            }
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(BorderStyle.allCases) { style in
                    Button {
                        model.setStyle(style.rawValue)
                    } label: {
                        VStack(spacing: 4) {
                            card(style)
                            Text(style.displayName)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .padding(4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(model.style == style ? Color.accentColor.opacity(0.32) : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(style.displayName)
                }
            }
        }
    }

    /// The card of one style.
    @ViewBuilder
    private func card(_ style: BorderStyle) -> some View {
        if let image = model.cards[style] {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 74)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        } else {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.secondary.opacity(0.18))
                .frame(height: 74)
                .overlay(
                    ProgressView()
                        .controlSize(.small)
                )
        }
    }
}

/// The text of the edge print and the black and white switch (the 120 film).
struct EdgeOptions: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if model.printsEdgeText {
            VStack(alignment: .leading, spacing: 8) {
                Text("胶片名称")
                    .font(.headline)
                TextField(
                    "KODAK PORTRA 400",
                    text: Binding(get: { model.edgeText }, set: { model.setEdgeText($0) })
                )
                .textFieldStyle(.roundedBorder)
                if model.allowsMonochrome {
                    Toggle("黑白", isOn: Binding(get: { model.mono }, set: { model.setMonochrome($0) }))
                        .help("120 胶片的浅灰色印字")
                }
            }
        }
    }
}
