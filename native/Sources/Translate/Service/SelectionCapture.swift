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
            "Could not send the keystroke."
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

    /// Pastes `text` over the frontmost app's selection, leaving the clipboard
    /// as it found it. The caller must hand focus back to that app first.
    static func paste(_ text: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                continuation.resume(with: Result { try pasteSynchronously(text) })
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
        try sendCommandKeystroke(keyC)

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

    private static func pasteSynchronously(_ text: String) throws {
        guard hasAccessibilityPermission else { throw SelectionError.notTrusted }

        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let ours = pasteboard.changeCount

        try sendCommandKeystroke(keyV)

        // Pasting reads the pasteboard asynchronously and there is no signal
        // for when it has, so wait longer than the copy does before restoring.
        // If something else wrote to the pasteboard meanwhile, leave it be.
        Thread.sleep(forTimeInterval: 0.3)
        if let saved, pasteboard.changeCount == ours {
            pasteboard.clearContents()
            pasteboard.setString(saved, forType: .string)
        }
    }

    /// Virtual keycodes for "C" and "V" on a US layout. Keycodes are
    /// positional, so these are the physical keys regardless of the user's
    /// layout.
    private static let keyC: CGKeyCode = 8
    private static let keyV: CGKeyCode = 9

    private static func sendCommandKeystroke(_ key: CGKeyCode) throws {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        else { throw SelectionError.eventFailed }

        // Set the flags explicitly so modifiers the user is still physically
        // holding (the trigger shortcut) don't turn this into ⌘⇧C.
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}

/// The selection a translation can be pasted back over. The request translates
/// the text trimmed, so the whitespace around it is kept here and put back —
/// otherwise replacing a triple-clicked line would swallow its newline.
struct ReplacementTarget {
    let app: NSRunningApplication
    let leading: String
    let trailing: String

    init(app: NSRunningApplication, selection: String) {
        self.app = app
        leading = String(selection.prefix { $0.isWhitespace })
        trailing = selection.allSatisfy(\.isWhitespace)
            ? ""
            : String(String(selection.reversed().prefix { $0.isWhitespace }).reversed())
    }

    /// Brings the app back to the front and pastes `translation` over its
    /// selection. Whatever window of ours had focus must already be gone or
    /// be giving it up, or the ⌘V lands there instead.
    @MainActor
    func paste(_ translation: String) async {
        app.activate()

        // Wait for focus to actually land back in the app, instead of
        // guessing how long that takes.
        for _ in 0..<25 {
            try? await Task.sleep(for: .milliseconds(20))
            if NSApp.keyWindow == nil,
               NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
                break
            }
        }
        try? await Task.sleep(for: .milliseconds(40))

        do {
            try await SelectionCapture.paste(leading + translation + trailing)
        } catch {
            NSLog("Translate: could not replace the selection — \(error.localizedDescription)")
        }
    }
}
