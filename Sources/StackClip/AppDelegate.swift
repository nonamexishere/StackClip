import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let history = ClipboardHistory()
    private let hotKey = HotKeyManager()
    private var pendingIconRevert: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "doc.on.clipboard",
                                           accessibilityDescription: "StackClip")

        menu.delegate = self
        statusItem.menu = menu
        history.onChange = { [weak self] in self?.rebuildMenu() }
        history.startMonitoring()
        rebuildMenu()

        hotKey.register { [weak self] in
            AppendCopy.perform(onSuccess: { self?.showAppendSuccess() },
                               onFailure: { NSSound.beep() })
        }
    }

    // Permission state can change behind our back in System Settings, so the
    // warning item is refreshed every time the menu opens (the check is cheap).
    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        if !AXIsProcessTrusted() {
            let warning = NSMenuItem(title: "⚠️ Append Copy needs Accessibility access…",
                                     action: #selector(openAccessibilitySettings),
                                     keyEquivalent: "")
            warning.target = self
            menu.addItem(warning)
            menu.addItem(.separator())
        }

        let header: NSMenuItem
        if #available(macOS 14, *) {
            header = NSMenuItem.sectionHeader(title: "Clipboard History")
        } else {
            header = NSMenuItem(title: "Clipboard History", action: nil, keyEquivalent: "")
            header.isEnabled = false
        }
        menu.addItem(header)

        if history.items.isEmpty {
            let empty = NSMenuItem(title: "History is empty", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for (index, item) in history.items.enumerated() {
                let menuItem = NSMenuItem(title: menuTitle(for: item),
                                          action: #selector(historyItemClicked(_:)),
                                          keyEquivalent: index < 9 ? String(index + 1) : "")
                menuItem.keyEquivalentModifierMask = [] // bare digit picks the item
                menuItem.target = self
                menuItem.representedObject = item
                menuItem.toolTip = item.count > 300 ? String(item.prefix(300)) + "…" : item
                menu.addItem(menuItem)
            }
        }

        menu.addItem(.separator())
        let hint = NSMenuItem(title: "⌘⇧C  Append copy", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(separatorPreferenceItem())
        menu.addItem(.separator())

        let clear = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
        addLoginItemToggle(to: menu)
        menu.addItem(NSMenuItem(title: "Quit StackClip",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
    }

    private func separatorPreferenceItem() -> NSMenuItem {
        let submenu = NSMenu()
        for choice in AppendCopy.Separator.allCases {
            let item = NSMenuItem(title: choice.menuTitle,
                                  action: #selector(separatorChosen(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = choice.rawValue
            item.state = choice == AppendCopy.Separator.current ? .on : .off
            submenu.addItem(item)
        }
        let item = NSMenuItem(title: "Append Separator", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private func menuTitle(for item: String) -> String {
        let singleLine = item
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ⏎ ")
        return singleLine.count > 50 ? String(singleLine.prefix(50)) + "…" : singleLine
    }

    // Brief visual + audible confirmation that an append landed.
    private func showAppendSuccess() {
        statusItem.button?.image = NSImage(systemSymbolName: "checkmark.circle.fill",
                                           accessibilityDescription: "Appended")
        NSSound(named: "Tink")?.play()
        pendingIconRevert?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.statusItem.button?.image = NSImage(systemSymbolName: "doc.on.clipboard",
                                                     accessibilityDescription: "StackClip")
        }
        pendingIconRevert = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(AppendCopy.accessibilitySettingsURL)
        // Also ask for the system dialog; harmless if it was already shown.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    @objc private func separatorChosen(_ sender: NSMenuItem) {
        guard let token = sender.representedObject as? String,
              let choice = AppendCopy.Separator(rawValue: token) else { return }
        AppendCopy.Separator.current = choice
        rebuildMenu()
    }

    @objc private func historyItemClicked(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? String else { return }
        history.copyToPasteboard(item)
    }

    @objc private func clearHistory() {
        history.clear()
    }

    // Only meaningful when running as the bundled .app (SMAppService needs a
    // bundle identifier); hidden when running the bare SPM binary in dev.
    private func addLoginItemToggle(to menu: NSMenu) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let item = NSMenuItem(title: "Launch at Login",
                              action: #selector(toggleLoginItem), keyEquivalent: "")
        item.target = self
        item.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(item)
    }

    @objc private func toggleLoginItem() {
        LoginItem.toggle()
        rebuildMenu()
    }
}
