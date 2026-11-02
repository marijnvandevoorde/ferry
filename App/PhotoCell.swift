import SwiftUI

struct PhotoCell: View {
    let item: PhotoItem
    let isSelected: Bool
    var isFocused = false
    @State private var hovering = false

    var body: some View {
        Color.clear
            .aspectRatio(3 / 2, contentMode: .fit)
            .overlay {
                if let image = item.thumbnail {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .transition(.opacity)
                } else {
                    ZStack {
                        Rectangle().fill(.quaternary)
                        Image(systemName: item.info.isVideo ? "video" : "photo")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(item.imported && !isSelected ? 0.55 : 1)
            .overlay(alignment: .topTrailing) {
                if isSelected || hovering {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, isSelected ? Color.accentColor : .black.opacity(0.3))
                        .shadow(radius: 2)
                        .padding(7)
                }
            }
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 4) {
                    if item.imported {
                        Label("Imported", systemImage: "checkmark")
                    }
                    if item.info.isVideo {
                        Image(systemName: "video.fill")
                    }
                }
                .labelStyle(.titleAndIcon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.black.opacity(0.45), in: Capsule())
                .padding(6)
                .opacity(item.imported || item.info.isVideo ? 1 : 0)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: isSelected ? 3 : 0)
            }
            .overlay {
                // Keyboard focus, distinct from selection.
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    .padding(-4)
                    .opacity(isFocused ? 1 : 0)
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .help("\(item.info.filename)\n\(item.date.formatted(date: .abbreviated, time: .shortened))")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .animation(.easeOut(duration: 0.15), value: isSelected)
            .animation(.easeOut(duration: 0.2), value: item.thumbnail != nil)
    }

    private var accessibilityText: String {
        var parts = [item.info.isVideo ? "Video" : "Photo", item.info.filename,
                     item.date.formatted(date: .abbreviated, time: .shortened)]
        if item.imported { parts.append("imported") }
        return parts.joined(separator: ", ")
    }
}
