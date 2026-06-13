import Carbon.HIToolbox

final class HotKeyManager {
    var handler: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    // The currently-registered combo, so update() can short-circuit a no-op and
    // callers can read back what's live.
    private(set) var keyCode: UInt32 = UInt32(kVK_ANSI_C)
    private(set) var modifiers: UInt32 = UInt32(cmdKey | shiftKey)

    func register(keyCode: UInt32 = UInt32(kVK_ANSI_C),
                  modifiers: UInt32 = UInt32(cmdKey | shiftKey),
                  handler: @escaping () -> Void) {
        self.handler = handler

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(),
                            hotKeyEventHandler,
                            1,
                            &eventType,
                            Unmanaged.passUnretained(self).toOpaque(),
                            &eventHandlerRef)

        _ = registerHotKey(keyCode: keyCode, modifiers: modifiers)
    }

    /// Swap the live hotkey for a new combo, reusing the already-installed event
    /// handler and stored handler closure. Unregisters the previous ref first so
    /// nothing leaks and the old combo can't double-fire. On success the new
    /// combo is persisted in keyCode/modifiers and `true` is returned; if
    /// RegisterEventHotKey fails (e.g. the combo is taken exclusively), the old
    /// hotkey is restored and `false` is returned so the caller can beep.
    @discardableResult
    func update(keyCode: UInt32, modifiers: UInt32) -> Bool {
        guard keyCode != self.keyCode || modifiers != self.modifiers else { return true }

        let previousRef = hotKeyRef
        let previousKeyCode = self.keyCode
        let previousModifiers = self.modifiers

        if let previousRef { UnregisterEventHotKey(previousRef) }
        hotKeyRef = nil

        if registerHotKey(keyCode: keyCode, modifiers: modifiers) {
            return true
        }

        // New combo refused: put the old one back so the feature keeps working.
        _ = registerHotKey(keyCode: previousKeyCode, modifiers: previousModifiers)
        return false
    }

    // Register `keyCode`+`modifiers`, recording them on success. Returns whether
    // RegisterEventHotKey succeeded.
    @discardableResult
    private func registerHotKey(keyCode: UInt32, modifiers: UInt32) -> Bool {
        let hotKeyID = EventHotKeyID(signature: OSType(0x53544B43), id: 1) // 'STKC'
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetEventDispatcherTarget(), 0, &hotKeyRef)
        guard status == noErr else {
            hotKeyRef = nil
            return false
        }
        self.keyCode = keyCode
        self.modifiers = modifiers
        return true
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    }
}

// Carbon takes a C function pointer, which cannot capture context; the manager
// instance travels through the userData pointer instead.
private func hotKeyEventHandler(_ nextHandler: EventHandlerCallRef?,
                                _ event: EventRef?,
                                _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let userData else { return noErr }
    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    manager.handler?()
    return noErr
}
