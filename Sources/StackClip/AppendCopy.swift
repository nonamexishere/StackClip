import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum AppendCopy {
    /// String inserted between the existing clipboard contents and the newly
    /// appended selection. Persisted in UserDefaults as its raw token.
    enum Separator: String, CaseIterable {
        case newline, space, tab

        private static let defaultsKey = "separator"

        var string: String {
            switch self {
            case .newline: return "\n"
            case .space: return " "
            case .tab: return "\t"
            }
        }

        var menuTitle: String {
            switch self {
            case .newline: return "New Line"
            case .space: return "Space"
            case .tab: return "Tab"
            }
        }

        static var current: Separator {
            get {
                UserDefaults.standard.string(forKey: defaultsKey)
                    .flatMap(Separator.init(rawValue:)) ?? .newline
            }
            set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
        }
    }

    /// Deep link to System Settings → Privacy & Security → Accessibility.
    static let accessibilitySettingsURL =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    /// Modifiers that would turn a synthetic Cmd+C into a different chord.
    private static let blockingModifiers: CGEventFlags = [.maskShift, .maskControl, .maskAlternate]

    static func perform(onSuccess: @escaping () -> Void = {},
                        onFailure: @escaping () -> Void = {}) {
        guard AXIsProcessTrusted() else {
            // Send the user straight to the right pane; the system prompt is
            // only auto-shown once per process, so don't rely on it here.
            NSWorkspace.shared.open(accessibilitySettingsURL)
            NSSound.beep()
            return
        }

        let old = NSPasteboard.general.string(forType: .string) ?? ""

        // Primary path: read the focused element's selected text directly via
        // the Accessibility API. No synthetic keystrokes are involved, so this
        // works even while the user is still holding ⌘⇧ from the hotkey — the
        // exact case where a simulated ⌘C silently fails (the held Shift merges
        // in and the app sees ⌘⇧C, not a copy).
        if let selection = focusedSelectedText(), !selection.isEmpty {
            appendToPasteboard(old: old, new: selection)
            onSuccess()
            return
        }

        // Fallback for apps that don't expose selected text over AX (some
        // browsers, Electron apps): simulate ⌘C — but only once the held hotkey
        // modifiers are released, so the synthetic event isn't corrupted.
        let startCount = NSPasteboard.general.changeCount
        whenModifiersClear {
            simulateCmdC()
            waitForChange(from: startCount, deadline: Date(timeIntervalSinceNow: 1.0),
                          onTimeout: onFailure) {
                guard let new = NSPasteboard.general.string(forType: .string), !new.isEmpty else {
                    onFailure() // clipboard changed, but nothing textual to append
                    return
                }
                appendToPasteboard(old: old, new: new)
                onSuccess()
            }
        }
    }

    private static func appendToPasteboard(old: String, new: String) {
        let combined = old.isEmpty ? new : old + Separator.current.string + new
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(combined, forType: .string)
    }

    /// The selected text of the system-wide focused UI element, or nil if the
    /// app doesn't expose it.
    private static func focusedSelectedText() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &value) == .success,
              let text = value as? String else { return nil }
        return text
    }

    /// Defer `body` until the user releases the hotkey's extra modifiers, so a
    /// simulated ⌘C isn't merged with a still-held Shift. Polls the live
    /// keyboard state; after a timeout it force-lifts whatever is stuck.
    private static func whenModifiersClear(deadline: Date = Date(timeIntervalSinceNow: 1.0),
                                           then body: @escaping () -> Void) {
        let held = CGEventSource.flagsState(.combinedSessionState).intersection(blockingModifiers)
        if held.isEmpty {
            body()
            return
        }
        if Date() >= deadline {
            liftModifiers(held)
            body()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            whenModifiersClear(deadline: deadline, then: body)
        }
    }

    private static func liftModifiers(_ held: CGEventFlags) {
        let source = CGEventSource(stateID: .privateState)
        let mapping: [(CGEventFlags, [Int])] = [
            (.maskShift, [kVK_Shift, kVK_RightShift]),
            (.maskControl, [kVK_Control, kVK_RightControl]),
            (.maskAlternate, [kVK_Option, kVK_RightOption]),
        ]
        for (flag, keys) in mapping where held.contains(flag) {
            for key in keys {
                CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: false)?
                    .post(tap: .cghidEventTap)
            }
        }
    }

    private static func simulateCmdC() {
        // A .privateState source keeps the injected event's modifiers isolated
        // from the live keyboard so the explicit .maskCommand below is what the
        // frontmost app sees.
        let source = CGEventSource(stateID: .privateState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private static func waitForChange(from startCount: Int, deadline: Date,
                                      onTimeout: @escaping () -> Void,
                                      then completion: @escaping () -> Void) {
        if NSPasteboard.general.changeCount != startCount {
            completion()
            return
        }
        guard Date() < deadline else {
            onTimeout() // nothing copyable selected; give up
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            waitForChange(from: startCount, deadline: deadline,
                          onTimeout: onTimeout, then: completion)
        }
    }
}
