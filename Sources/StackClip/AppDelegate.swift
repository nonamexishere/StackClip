import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let history = ClipboardHistory()
    private let hotKey = HotKeyManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "doc.on.clipboard",
                                           accessibilityDescription: "StackClip")

        history.onChange = { [weak self] in self?.rebuildMenu() }
        history.startMonitoring()
        rebuildMenu()

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)

        hotKey.register {
            AppendCopy.perform()
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        if history.items.isEmpty {
            let empty = NSMenuItem(title: "History is empty", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for item in history.items {
                let menuItem = NSMenuItem(title: menuTitle(for: item),
                                          action: #selector(historyItemClicked(_:)),
                                          keyEquivalent: "")
                menuItem.target = self
                menuItem.representedObject = item
                menu.addItem(menuItem)
            }
        }

        menu.addItem(.separator())
        let hint = NSMenuItem(title: "⌘⇧C  Append copy", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())

        let clear = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
        menu.addItem(NSMenuItem(title: "Quit StackClip",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))

        statusItem.menu = menu
    }

    private func menuTitle(for item: String) -> String {
        let singleLine = item
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ⏎ ")
        return singleLine.count > 50 ? String(singleLine.prefix(50)) + "…" : singleLine
    }

    @objc private func historyItemClicked(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? String else { return }
        history.copyToPasteboard(item)
    }

    @objc private func clearHistory() {
        history.clear()
    }
}
