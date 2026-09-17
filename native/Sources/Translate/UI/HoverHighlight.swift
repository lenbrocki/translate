import SwiftUI

extension View {
    /// Tints a control while the pointer is over it. The system button styles
    /// on macOS give no hover feedback of their own, so this lays a faint fill
    /// over the bezel instead of replacing the style — the controls keep their
    /// native look and only gain the response.
    ///
    /// `tint` is what the fill is made of: the text colour darkens a light
    /// bezel and lightens a dark one, while white brightens an accent fill.
    func hoverHighlight(cornerRadius: CGFloat = 6, tint: Color = .primary, opacity: Double = 0.07) -> some View {
        modifier(HoverHighlight(cornerRadius: cornerRadius, tint: tint, opacity: opacity))
    }
}

private struct HoverHighlight: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color
    let opacity: Double

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tint.opacity(isHovering && isEnabled ? opacity : 0))
                    .allowsHitTesting(false)
            )
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}
