import AppKit
import SwiftUI

enum WindowID {
    static let main = "main"
}

/// The parts of the app that outlive any window: the global shortcut, the
/// overlay, and the selection-translation flow that connects them.
@MainActor
final class AppCore {
    static let shared = AppCore()

    let overlay = OverlayController()

    private let hotKey = GlobalHotKey()
    private var openMainWindow: (() -> Void)?

    private init() {}

    func start() {
        watchWindows()
        do {
            try registerShortcut(Preferences.shared.shortcut)
        } catch {
            // Usually means another app already owns the combination. The app
            // is still useful without it, so report and carry on.
            NSLog("Translate: could not register the global shortcut — \(error.localizedDescription)")
        }
    }

    /// Registers `combo` and, only if that worked, makes it the saved shortcut.
    func setShortcut(_ combo: KeyCombo) throws {
        try registerShortcut(combo)
    }

    private func registerShortcut(_ combo: KeyCombo) throws {
        try hotKey.register(combo) { [weak self] in
            self?.translateSelection()
        }
    }

    // MARK: - Selection translation

    /// Reads the selection out of the frontmost app and translates it into the
    /// overlay. The read blocks for a few hundred milliseconds, so it happens
    /// off the main actor.
    func translateSelection() {
        let anchor = NSEvent.mouseLocation

        Task {
            do {
                let text = try await SelectionCapture.capture()
                let preferences = Preferences.shared
                overlay.session.reset()
                overlay.present(near: anchor)
                overlay.session.start(
                    TranslationRequest(
                        text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                        sourceLanguage: preferences.sourceLanguage,
                        targetLanguage: preferences.targetLanguage,
                        formality: preferences.effectiveFormality,
                        addresseeGender: preferences.effectiveAddresseeGender,
                        speakerGender: preferences.effectiveSpeakerGender,
                        effort: preferences.effort,
                        provider: preferences.provider
                    )
                )
            } catch {
                // Surface the failure in the overlay rather than silently
                // doing nothing — the user pressed a key and deserves a reply.
                overlay.session.reset()
                overlay.present(near: anchor)
                overlay.session.fail(error.localizedDescription)
            }
        }
    }

    // MARK: - Main window

    func registerWindowOpener(_ open: @escaping () -> Void) {
        openMainWindow = open
    }

    func showMainWindow() {
        // The Dock icon comes back first. An accessory app cannot take focus
        // the way a regular one does, so activating before the switch leaves
        // the window sitting behind whatever the user was looking at.
        NSApp.setActivationPolicy(.regular)

        // A turn later: AppKit is still installing the menu bar and the Dock
        // tile, and activation asked for during that lands unreliably.
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: { !($0 is NSPanel) && $0.title == "Translate" }) {
                window.makeKeyAndOrderFront(nil)
            } else {
                self.openMainWindow?()
            }
        }
    }

    // MARK: - Dock icon

    /// The Dock icon follows the windows: present while one is open, gone once
    /// the last one closes. The app itself keeps running either way — in
    /// `.accessory` the menu-bar item stays, the global shortcut stays
    /// registered, and the overlay still appears over other apps.
    private func watchWindows() {
        // Close and key cover the ordinary cases. Occlusion catches a window
        // that appears without taking focus — Settings, opened from the menu
        // bar while the app has no Dock icon to activate through.
        let names: [Notification.Name] = [
            NSWindow.willCloseNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didChangeOcclusionStateNotification,
        ]
        for name in names {
            NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                // `willClose` arrives while the window is still listed and
                // still visible, so let the close finish before counting.
                DispatchQueue.main.async { self?.syncActivationPolicy() }
            }
        }
    }

    /// Counts only windows that can become main. The overlay is an `NSPanel`
    /// and the menu-bar extra carries a status window of its own; neither is a
    /// window the user has open, and neither should hold the Dock icon.
    private func syncActivationPolicy() {
        let wanted: NSApplication.ActivationPolicy =
            NSApp.windows.contains { $0.isVisible && $0.canBecomeMain } ? .regular : .accessory
        guard NSApp.activationPolicy() != wanted else { return }
        NSApp.setActivationPolicy(wanted)
    }
}
