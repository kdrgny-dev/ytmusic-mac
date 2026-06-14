import AppKit
import Carbon.HIToolbox

/// Register a couple of global hotkeys that work even when YTMusic isn't
/// frontmost. Uses Carbon's RegisterEventHotKey because it doesn't require
/// the Accessibility (TCC) permission that NSEvent global monitors do.
final class GlobalHotkeys {
    static let shared = GlobalHotkeys()

    private var refs: [EventHotKeyRef] = []
    private var handlerInstalled = false
    private var actions: [UInt32: () -> Void] = [:]
    private static let signature: OSType = OSType(0x59544D48) // 'YTMH'

    func install() {
        installHandler()
        // ⌃⌥⌘ K — focus search inside the app (also brings the window forward)
        register(id: 1, keyCode: UInt32(kVK_ANSI_K),
                 mods: UInt32(controlKey | optionKey | cmdKey)) {
            MainWindowController.shared.show()
            WebViewHolder.shared.focusSearch()
        }
        // ⌃⌥⌘ M — toggle mini player
        register(id: 2, keyCode: UInt32(kVK_ANSI_M),
                 mods: UInt32(controlKey | optionKey | cmdKey)) {
            MiniPlayerWindowController.shared.show()
        }
    }

    private func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, eventRef, userData -> OSStatus in
            guard let eventRef = eventRef, let userData = userData else { return noErr }
            var hkID = EventHotKeyID()
            GetEventParameter(eventRef,
                              EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID),
                              nil,
                              MemoryLayout<EventHotKeyID>.size,
                              nil,
                              &hkID)
            let me = Unmanaged<GlobalHotkeys>.fromOpaque(userData).takeUnretainedValue()
            if let action = me.actions[hkID.id] {
                DispatchQueue.main.async { action() }
            }
            return noErr
        }, 1, &spec, selfPtr, nil)
    }

    private func register(id: UInt32, keyCode: UInt32, mods: UInt32, action: @escaping () -> Void) {
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(keyCode, mods, hkID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref = ref {
            refs.append(ref)
            actions[id] = action
        }
    }

    deinit {
        for ref in refs { UnregisterEventHotKey(ref) }
    }
}
