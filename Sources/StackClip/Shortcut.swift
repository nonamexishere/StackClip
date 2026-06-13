import AppKit
import Carbon.HIToolbox

/// A global-hotkey combination: a virtual key code plus a Carbon modifier mask
/// (cmdKey/shiftKey/optionKey/controlKey). Knows how to persist itself in
/// UserDefaults and render a human-readable label like "⌘⇧C".
struct Shortcut: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32 // Carbon mask: cmdKey | shiftKey | optionKey | controlKey

    /// StackClip's factory default: ⌘⇧C.
    static let appendCopyDefault = Shortcut(keyCode: UInt32(kVK_ANSI_C),
                                            modifiers: UInt32(cmdKey | shiftKey))

    // MARK: Persistence

    private static let keyCodeKey = "hotKeyCode"
    private static let modifiersKey = "hotKeyModifiers"

    /// The saved combo, or the factory default when nothing has been stored yet.
    /// Reading the keys as objects (not `integer(forKey:)`) lets us tell "absent"
    /// from a legitimately stored 0, so the default survives a fresh launch.
    static var current: Shortcut {
        get {
            let defaults = UserDefaults.standard
            guard defaults.object(forKey: keyCodeKey) != nil,
                  defaults.object(forKey: modifiersKey) != nil else {
                return appendCopyDefault
            }
            let code = UInt32(defaults.integer(forKey: keyCodeKey))
            let mods = UInt32(defaults.integer(forKey: modifiersKey))
            return Shortcut(keyCode: code, modifiers: mods)
        }
        set {
            let defaults = UserDefaults.standard
            defaults.set(Int(newValue.keyCode), forKey: keyCodeKey)
            defaults.set(Int(newValue.modifiers), forKey: modifiersKey)
        }
    }

    /// Forget any saved combo so `current` falls back to the factory default.
    static func resetToDefault() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: keyCodeKey)
        defaults.removeObject(forKey: modifiersKey)
    }

    // MARK: Display

    /// A label like "⌘⇧C" for this combo, suitable for menu hints and the
    /// recorder field.
    var displayString: String { Self.displayString(keyCode: keyCode, modifiers: modifiers) }

    /// Render a keyCode + Carbon modifier mask to a glyph string (modifier
    /// glyphs ⌃⌥⇧⌘ in the conventional order, then the key). Unknown keys fall
    /// back to "Key (<code>)". Pure, so it can be unit-tested.
    static func displayString(keyCode: UInt32, modifiers: UInt32) -> String {
        var result = ""
        // Conventional Cocoa order: Control, Option, Shift, Command.
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        result += keyName(for: keyCode)
        return result
    }

    /// Human-readable name for a virtual key code. Covers the letters, digits,
    /// Space and the other keys a user is likely to bind; anything else falls
    /// back to "Key (<code>)".
    static func keyName(for keyCode: UInt32) -> String {
        if let name = keyNames[Int(keyCode)] { return name }
        return "Key (\(keyCode))"
    }

    private static let keyNames: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
        kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
        kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
        kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
        kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
        kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_Space: "Space",
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[",
        kVK_ANSI_RightBracket: "]", kVK_ANSI_Backslash: "\\", kVK_ANSI_Semicolon: ";",
        kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".",
        kVK_ANSI_Slash: "/", kVK_ANSI_Grave: "`",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14",
        kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18",
        kVK_F19: "F19", kVK_F20: "F20",
    ]

    /// The function-key codes (F1–F20). They're the one class of key allowed to
    /// be bound without a modifier, since they don't collide with normal typing.
    static let functionKeyCodes: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9,
        kVK_F10, kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17,
        kVK_F18, kVK_F19, kVK_F20,
    ]

    /// Translate Cocoa modifier flags (already masked to
    /// .deviceIndependentFlagsMask) to a Carbon modifier mask.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mask: UInt32 = 0
        if flags.contains(.command) { mask |= UInt32(cmdKey) }
        if flags.contains(.option) { mask |= UInt32(optionKey) }
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        if flags.contains(.shift) { mask |= UInt32(shiftKey) }
        return mask
    }
}
