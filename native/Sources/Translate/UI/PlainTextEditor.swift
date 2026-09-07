import AppKit
import SwiftUI

/// A text view with insets we control exactly.
///
/// SwiftUI's `TextEditor` hides its text container inset, so a placeholder
/// drawn as a SwiftUI overlay never quite lines up with the caret, and its
/// scroller parks a permanent track down the side of an empty editor. Drawing
/// the placeholder inside the text view, from the same origin the caret uses,
/// makes the two agree by construction.
struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    var placeholder = ""
    var isEditable = true
    var fontSize: CGFloat = 15
    var inset = NSSize(width: 20, height: 18)
    /// Focus the editor as soon as the window opens.
    var focusOnAppear = false

    func makeNSView(context: Context) -> NSScrollView {
        let textView = PlaceholderTextView()
        textView.placeholder = placeholder
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: fontSize)
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.textContainerInset = inset
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        // Smart quotes turn a typed apostrophe into a curly one, which is fine
        // for prose and wrong for anything the user pasted from code.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.string = text

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .overlay
        scrollView.automaticallyAdjustsContentInsets = false

        if focusOnAppear {
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? PlaceholderTextView else { return }
        textView.placeholder = placeholder
        if textView.string != text {
            let wasAtEnd = isAtEnd(scrollView)
            textView.string = text
            textView.needsDisplay = true
            // Read-only panes are streaming targets: follow the text as it
            // arrives, but only if the reader hasn't scrolled away.
            if !isEditable, wasAtEnd { textView.scrollToEndOfDocument(nil) }
        }
    }

    private func isAtEnd(_ scrollView: NSScrollView) -> Bool {
        let visible = scrollView.contentView.documentVisibleRect
        let height = scrollView.documentView?.bounds.height ?? 0
        return visible.maxY >= height - 4
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? PlaceholderTextView else { return }
            text.wrappedValue = textView.string
            textView.needsDisplay = true
        }
    }
}

/// Draws its own placeholder so it starts exactly where the caret does.
final class PlaceholderTextView: NSTextView {
    var placeholder = "" {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 15),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        let origin = NSPoint(
            x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0),
            y: textContainerInset.height
        )
        placeholder.draw(at: origin, withAttributes: attributes)
    }
}
