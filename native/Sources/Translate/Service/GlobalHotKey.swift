import AppKit
import Carbon.HIToolbox

/// A system-wide hot key, registered through Carbon's `RegisterEventHotKey`.
///
/// This is still the only public API for a global shortcut that works without
/// Accessibility permission, and it does not need an event tap.
@MainActor
final class GlobalHotKey {
    enum RegistrationError: LocalizedError {
        case needsModifier
        case rejected(OSStatus)

        var errorDescription: String? {
            switch self {
            case .needsModifier:
                "Pick a combination that includes ⌘, ⌥, or ⌃."
            case .rejected:
                "Another app is already using that combination."
            }
        }
    }

    private static let signature = OSType(0x54524E53) // 'TRNS'

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var onFire: () -> Void = {}

    /// Carbon hands the callback a raw pointer, so the live instance is parked
    /// here for the trampoline to find.
    private static weak var active: GlobalHotKey?

    func register(_ combo: KeyCombo, onFire: @escaping () -> Void) throws {
        guard combo.isValid else { throw RegistrationError.needsModifier }
        unregister()

        self.onFire = onFire
        Self.active = self
        installHandlerIfNeeded()

        let id = EventHotKeyID(signature: Self.signature, id: 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(combo.keyCode),
            combo.carbonModifiers,
            id,
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else { throw RegistrationError.rejected(status) }
        hotKeyRef = ref
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ -> OSStatus in
            var id = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &id
            )
            guard status == noErr, id.signature == GlobalHotKey.signature else { return status }
            // Carbon delivers this on the main thread; hop through MainActor
            // anyway so the compiler can see it.
            DispatchQueue.main.async { GlobalHotKey.active?.onFire() }
            return noErr
        }, 1, &spec, nil, &eventHandler)
    }
}
