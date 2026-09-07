import AppKit
import SwiftUI

/// Click to record, then press the combination. Mirrors the recorder in
/// System Settings: Escape cancels, Delete clears back to the default.
struct ShortcutRecorder: View {
    @Binding var combo: KeyCombo
    var onFailure: (String) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: toggle) {
            Text(isRecording ? "Press a combination…" : combo.displayString)
                .font(.system(size: 13, weight: .medium))
                .monospaced()
                .frame(minWidth: 140)
                .padding(.vertical, 2)
        }
        .buttonStyle(.bordered)
        .tint(isRecording ? .accentColor : nil)
        .onDisappear(perform: stopRecording)
    }

    private func toggle() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        guard monitor == nil else { return }
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }

    private func handle(_ event: NSEvent) {
        defer { stopRecording() }

        switch event.keyCode {
        case 53: return                                     // Escape — cancel
        case 51: apply(.default); return                    // Delete — reset
        default: break
        }

        let candidate = KeyCombo(
            keyCode: event.keyCode,
            modifiers: event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
        )
        apply(candidate)
    }

    private func apply(_ candidate: KeyCombo) {
        do {
            // Register before persisting, so a combination another app owns
            // leaves the working one in place.
            try AppCore.shared.setShortcut(candidate)
            combo = candidate
            onFailure("")
        } catch {
            onFailure(error.localizedDescription)
        }
    }
}
