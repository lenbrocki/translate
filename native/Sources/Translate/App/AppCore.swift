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
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { !($0 is NSPanel) && $0.title == "Translate" }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openMainWindow?()
        }
    }
}
