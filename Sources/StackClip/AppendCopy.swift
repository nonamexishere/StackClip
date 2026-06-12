import AppKit
import Carbon.HIToolbox

enum AppendCopy {
    static let separator = "\n"

    static func perform() {
        guard AXIsProcessTrusted() else {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            AXIsProcessTrustedWithOptions(options as CFDictionary)
            return
        }

        let pasteboard = NSPasteboard.general
        let old = pasteboard.string(forType: .string) ?? ""
        let startCount = pasteboard.changeCount

        simulateCmdC()
        waitForChange(from: startCount, deadline: Date(timeIntervalSinceNow: 1.0)) {
            guard let new = pasteboard.string(forType: .string), !new.isEmpty else { return }
            let combined = old.isEmpty ? new : old + separator + new
            pasteboard.clearContents()
            pasteboard.setString(combined, forType: .string)
        }
    }

    private static func simulateCmdC() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)
        // Plain Cmd, even though the user is physically holding Cmd+Shift for the hotkey.
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private static func waitForChange(from startCount: Int, deadline: Date,
                                      then completion: @escaping () -> Void) {
        if NSPasteboard.general.changeCount != startCount {
            completion()
            return
        }
        guard Date() < deadline else { return } // nothing copyable selected; give up quietly
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            waitForChange(from: startCount, deadline: deadline, then: completion)
        }
    }
}
