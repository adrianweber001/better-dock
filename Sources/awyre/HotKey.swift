import Carbon.HIToolbox

/// Globales Tastenkürzel ⌃⌥⌘D (braucht keine Sonderberechtigung).
enum HotKey {
    private static var ref: EventHotKeyRef?
    private static var action: (() -> Void)?

    static func register(_ handler: @escaping () -> Void) {
        action = handler

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKey.action?() }
            return noErr
        }, 1, &spec, nil, nil)

        let id = EventHotKeyID(signature: OSType(0x41575952) /* "AWYR" */, id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_D),
                            UInt32(controlKey | optionKey | cmdKey),
                            id, GetApplicationEventTarget(), 0, &ref)
    }
}
