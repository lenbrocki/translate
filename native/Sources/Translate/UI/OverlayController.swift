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
    /// Where the selection came from, so the translation can be pasted back
    /// over it.
    private var replacementTarget: ReplacementTarget?
    /// A replace pressed before the translation finished, waiting for it to.
    private var pendingReplace: Task<Void, Never>?

    private let gap: CGFloat = 16
    private let screenEdge: CGFloat = 12

    var isVisible: Bool { panel?.isVisible ?? false }

    /// Shows the card near `anchor` (defaults to the pointer). `target` is the
    /// selection the card is translating, if the translation can replace it.
    func present(near anchor: NSPoint? = nil, replacing target: ReplacementTarget? = nil) {
        let panel = panel ?? makePanel()
        self.panel = panel
        self.anchor = anchor ?? NSEvent.mouseLocation
        replacementTarget = target

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
        pendingReplace?.cancel()
        pendingReplace = nil
        session.cancel()
    }

    /// Moves the translation into the main window, where there is room to
    /// edit the source text or keep working with it.
    func openInMainWindow() {
        // Before dismissing: that cancels a translation still streaming.
        guard let snapshot = session.snapshot else { return }
        let target = replacementTarget
        dismiss()
        AppCore.shared.openInMainWindow(snapshot, replacing: target)
    }

    /// Pastes the translation over the selection it came from.
    ///
    /// Pressed while the translation is still streaming, it waits for the end
    /// rather than doing nothing: the text often looks finished a moment
    /// before the stream actually closes, and a click that silently misses
    /// reads as a broken button.
    func replaceSelection() {
        guard replacementTarget != nil, !session.trimmedOutput.isEmpty, pendingReplace == nil else { return }
        pendingReplace = Task { [weak self] in
            while self?.session.isStreaming == true {
                try? await Task.sleep(for: .milliseconds(50))
                if Task.isCancelled { return }
            }
            guard let self, !Task.isCancelled else { return }
            self.pendingReplace = nil
            guard self.session.errorMessage == nil else { return }
            await self.pasteTranslation()
        }
    }

    /// The panel has to go first: while it is key, the ⌘V would land in the
    /// card rather than in the app underneath.
    private func pasteTranslation() async {
        guard let target = replacementTarget else { return }
        let translation = session.trimmedOutput
        guard !translation.isEmpty else { return }

        dismiss()
        replacementTarget = nil
        await target.paste(translation)
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
        // The app stays inactive while the card is up, and an inactive app's
        // window gets no mouse-moved events unless it asks — without them
        // SwiftUI's hover never fires on the card's buttons.
        panel.acceptsMouseMovedEvents = true
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
                onReplace: { [weak self] in self?.replaceSelection() },
                onOpenInApp: { [weak self] in self?.openInMainWindow() },
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
            if event.keyCode == 36, // Return
               event.modifierFlags.contains(.command), !self.isPickerOpen {
                self.replaceSelection()
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
