import SwiftUI

/// A segmented control that answers the pointer. The native one only does so
/// inside a real toolbar, and the main window's controls sit in a hidden title
/// bar instead — so this draws the same track-and-thumb shape itself, with a
/// hover fill on the segments that aren't selected.
///
/// Sized like the native regular control (24pt tall, 13pt text), so it lines up
/// with the bordered buttons beside it. Segments share the width equally; set
/// it with `.frame(width:)`.
struct SegmentedPicker<Value: Hashable & Identifiable>: View {
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> String

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var thumb
    @State private var hovered: Value.ID?

    private let height: CGFloat = 24
    private let trackRadius: CGFloat = 6
    private let inset: CGFloat = 2

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                segment(option)
            }
        }
        .padding(inset)
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: trackRadius, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.1 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: trackRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
        .opacity(isEnabled ? 1 : 0.5)
        .animation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.25), value: selection)
        .animation(.easeOut(duration: 0.12), value: hovered)
    }

    private func segment(_ option: Value) -> some View {
        let isSelected = option == selection
        let isHovered = isEnabled && hovered == option.id && !isSelected

        return Button {
            selection = option
        } label: {
            Text(label(option))
                .font(.system(size: 13))
                .lineLimit(1)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: trackRadius - inset, style: .continuous)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.22) : .white)
                            .shadow(color: .black.opacity(0.14), radius: 0.5, y: 0.5)
                            .matchedGeometryEffect(id: "thumb", in: thumb)
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: trackRadius - inset, style: .continuous)
                            .fill(Color.primary.opacity(0.07))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside {
                hovered = option.id
            } else if hovered == option.id {
                hovered = nil
            }
        }
    }
}
