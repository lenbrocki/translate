import AppKit
import ApplicationServices

enum SelectionError: LocalizedError {
    case notTrusted
    case noSelection
    case eventFailed

    var errorDescription: String? {
        switch self {
        case .notTrusted:
            "Translate needs Accessibility permission to read the selected text. Grant it in System Settings › Privacy & Security › Accessibility."
        case .noSelection:
            "No text was selected."
        case .eventFailed:
            "Could not send the copy keystroke."
        }
    }
}

/// Reads whatever is selected in the frontmost app.
///
/// Copying is the only way to get another app's selection without an
/// accessibility API most apps don't implement — it's the same trick DeepL and
/// friends use. Blocks for up to ~700ms, so it never runs on the main actor.
enum SelectionCapture {
    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Same check, but asks macOS to show the "open System Settings" prompt.
    /// This is also what registers the app in the Accessibility list.
    @discardableResult
    static func requestAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// Copies the selection and returns it, leaving the clipboard as it found it.
    static func capture() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try captureSynchronously() })
            }
        }
    }

    private static let queue = DispatchQueue(label: "com.lennartbrocki.translate.selection")

    private static func captureSynchronously() throws -> String {
        guard hasAccessibilityPermission else { throw SelectionError.notTrusted }

        let pasteboard = NSPasteboard.general
        let changeCountBefore = pasteboard.changeCount
        let saved = pasteboard.string(forType: .string)

        // Give the user a moment to release the shortcut's modifier keys
        // before we push our own down; some apps get confused otherwise.
        Thread.sleep(forTimeInterval: 0.06)
        try sendCopyKeystroke()

        // Wait for the frontmost app to actually service the copy.
        var captured: String?
        for _ in 0..<60 {
            Thread.sleep(forTimeInterval: 0.01)
            if pasteboard.changeCount != changeCountBefore {
                captured = pasteboard.string(forType: .string)
                break
            }
        }

        defer {
            if let saved {
                // Let the source app finish reading the pasteboard first.
                Thread.sleep(forTimeInterval: 0.08)
                pasteboard.clearContents()
                pasteboard.setString(saved, forType: .string)
            }
        }

        guard let text = captured, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SelectionError.noSelection
        }
        return text
    }

    private static func sendCopyKeystroke() throws {
        /// Virtual keycode for "C" on a US layout. Keycodes are positional, so
        /// this is the physical key regardless of the user's layout.
        let keyC: CGKeyCode = 8

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: false)
        else { throw SelectionError.eventFailed }

        // Set the flags explicitly so modifiers the user is still physically
        // holding (the trigger shortcut) don't turn this into ⌘⇧C.
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
