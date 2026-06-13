import AppKit
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

    static func perform(onSuccess: @escaping () -> Void = {},
                        onFailure: @escaping () -> Void = {}) {
        guard AXIsProcessTrusted() else {
            // Send the user straight to the right pane; the system prompt is
            // only auto-shown once per process, so don't rely on it here.
            NSWorkspace.shared.open(accessibilitySettingsURL)
            NSSound.beep()
            return
        }

        let pasteboard = NSPasteboard.general
        let old = pasteboard.string(forType: .string) ?? ""
        let startCount = pasteboard.changeCount

        simulateCmdC()
        waitForChange(from: startCount, deadline: Date(timeIntervalSinceNow: 1.0),
                      onTimeout: onFailure) {
            guard let new = pasteboard.string(forType: .string), !new.isEmpty else {
                onFailure() // clipboard changed, but nothing textual to append
                return
            }
            let combined = old.isEmpty ? new : old + Separator.current.string + new
            pasteboard.clearContents()
            pasteboard.setString(combined, forType: .string)
            onSuccess()
        }
    }

    private static func simulateCmdC() {
        // A .privateState source keeps the injected event's modifiers isolated
        // from the live keyboard. This matters because the hotkey is Cmd+Shift+C:
        // the user is usually still holding Shift when this fires, and a
        // .combinedSessionState source would merge that Shift back in, so the
        // frontmost app would see Cmd+Shift+C (not a copy) and nothing would be
        // copied. With .privateState the flags we set below are authoritative.
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
