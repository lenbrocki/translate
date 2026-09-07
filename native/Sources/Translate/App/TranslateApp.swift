import AppKit
import SwiftUI

@main
struct TranslateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Translate", id: WindowID.main) {
            MainView()
        }
        .defaultSize(width: 940, height: 620)
        // No title bar of its own: the language controls sit in that row, on
        // the window surface, with the content well floating below them.
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .toolbar) {
                Button("Translate Selection") { AppCore.shared.translateSelection() }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
        }

        MenuBarExtra {
            MenuBarContent()
        } label: {
            Image(systemName: "character.bubble")
        }
    }
}

private struct MenuBarContent: View {
    var body: some View {
        Button("Open Translate") { AppCore.shared.showMainWindow() }
        Button("Translate Selection") { AppCore.shared.translateSelection() }
        Divider()
        SettingsLink { Text("Settings…") }
        Divider()
        Button("Quit Translate") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { AppCore.shared.start() }
    }

    /// The app lives in the menu bar: closing the window shouldn't take the
    /// global shortcut down with it.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            MainActor.assumeIsolated { AppCore.shared.showMainWindow() }
        }
        return true
    }
}
