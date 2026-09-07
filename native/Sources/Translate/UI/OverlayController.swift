import AppKit
import SwiftUI

/// A borderless, non-activating panel. Non-activating is the whole point: it
/// can take key focus without macOS switching to whichever Space the main
/// window lives on, so the user stays in their full-screen app.
final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the floating translation card: when it appears, where, and what makes
/// it go away.
@MainActor
final class OverlayController {
    let session = TranslationSession()

    private var panel: OverlayPanel?
    /// Screen point the card is anchored to, in AppKit coordinates.
    private var anchor: NSPoint = .zero
    /// When the card was last shown, so a resign-key that arrives while it is
    /// still coming up doesn't immediately dismiss it.
    private var shownAt: Date?
    private var keyMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    /// True while the language list is showing. It is a child window, so the
    /// panel resigns key and would otherwise dismiss itself out from under it.
    private var isPickerOpen = false

    private let gap: CGFloat = 16
    private let screenEdge: CGFloat = 12

    var isVisible: Bool { panel?.isVisible ?? false }

    /// Shows the card near `anchor` (defaults to the pointer).
    func present(near anchor: NSPoint? = nil) {
        let panel = panel ?? makePanel()
        self.panel = panel
        self.anchor = anchor ?? NSEvent.mouseLocation

        place()
        shownAt = Date()
        panel.orderFrontRegardless()
        panel.makeKey()
        startKeyMonitor()
    }

    func dismiss() {
        stopKeyMonitor()
        panel?.orderOut(nil)
        shownAt = nil
        session.cancel()
    }

    // MARK: - Panel

    private func makePanel() -> OverlayPanel {
        let panel = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .utilityWindow
        // Above normal and floating windows, and above another app's
        // full-screen window.
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle,
        ]

        let hosting = NSHostingController(
            rootView: OverlayView(
                session: session,
                onClose: { [weak self] in self?.dismiss() },
                onPickerOpenChange: { [weak self] open in self?.setPickerOpen(open) }
            )
        )
        // Let SwiftUI drive the panel's size as the translation streams in.
        hosting.sizingOptions = [.preferredContentSize]
        panel.contentViewController = hosting

        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismissIfSettled() }
            }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification, object: panel, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.place()
                    self?.panel?.invalidateShadow()
                }
            }
        )
        return panel
    }

    /// The card is transient: it goes away as soon as you click somewhere else.
    ///
    /// Two blurs must not count. The one that can arrive while the card is
    /// still coming up would dismiss it before it is readable. The one the
    /// language list causes is the card's own popover taking key focus, which
    /// `isPickerOpen` covers: the list sets that flag before it presents, so
    /// the flag is already true by the time this resign arrives.
    private func dismissIfSettled() {
        guard !isPickerOpen else { return }
        guard let shownAt, Date().timeIntervalSince(shownAt) > 0.6 else { return }
        dismiss()
    }

    /// The list closing fires no resign-key of its own, so take the dismissal
    /// that was suppressed if focus ended up somewhere else in the meantime.
    private func setPickerOpen(_ open: Bool) {
        isPickerOpen = open
        if open { return }
        // Give the card the full settle window again, so the blur that follows
        // the list closing doesn't take it down with it.
        shownAt = Date()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            guard !isPickerOpen, let panel, panel.isVisible, !panel.isKeyWindow else { return }
            dismiss()
        }
    }

    /// Places the card next to the anchor, flipping it to stay on one screen.
    private func place() {
        guard let panel else { return }
        let size = panel.frame.size
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        var x = anchor.x + gap
        if x + size.width > visible.maxX - screenEdge {
            x = anchor.x - size.width - gap // flip to the left of the pointer
        }
        // AppKit measures from the bottom, but the card should hang below the
        // pointer, so position its top edge and derive the origin.
        var y = anchor.y - gap - size.height
        if y < visible.minY + screenEdge {
            y = anchor.y + gap // flip above the pointer
        }

        x = min(max(x, visible.minX + screenEdge), max(visible.maxX - size.width - screenEdge, visible.minX + screenEdge))
        y = min(max(y, visible.minY + screenEdge), max(visible.maxY - size.height - screenEdge, visible.minY + screenEdge))

        panel.setFrameOrigin(NSPoint(x: round(x), y: round(y)))
    }

    // MARK: - Keyboard

    /// The card has no menu of its own, so wire up the two shortcuts that
    /// matter here.
    private func startKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel?.isKeyWindow == true else { return event }
            // Escape belongs to the language list while it is open.
            if event.keyCode == 53, !self.isPickerOpen { // Escape
                self.dismiss()
                return nil
            }
            if event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "c" {
                Clipboard.write(self.session.trimmedOutput)
                return nil
            }
            return event
        }
    }

    private func stopKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }
}
