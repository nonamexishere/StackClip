import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSSearchFieldDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let history = ClipboardHistory()
    private let hotKey = HotKeyManager()
    private var pendingIconRevert: DispatchWorkItem?

    // Whether picking an item should auto-paste it into the previously-focused
    // app. Persisted; default OFF.
    private static let pasteOnPickKey = "pasteOnPick"
    private var pasteOnPick: Bool {
        get { UserDefaults.standard.bool(forKey: Self.pasteOnPickKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.pasteOnPickKey) }
    }

    // MARK: Search field (Feature A)
    //
    // The field is created once and reused across rebuilds. Hosting it in the
    // menu via a persistent NSMenuItem.view (rather than recreating it each
    // time) is what lets it reliably keep keyboard focus while the menu tracks:
    // typing toggles isHidden on the existing item rows instead of rebuilding
    // the menu, which would drop first responder on every keystroke.
    private let searchField = NSSearchField()
    private lazy var searchItem: NSMenuItem = {
        searchField.placeholderString = "Search history"
        // Filter on literally every keystroke: controlTextDidChange (via the
        // delegate) is the reliable hook; target/action only covers the search
        // throttle and the clear button.
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        searchField.sendsWholeSearchString = false
        searchField.sendsSearchStringImmediately = true
        (searchField.cell as? NSSearchFieldCell)?.sendsSearchStringImmediately = true
        // Host the field in a small container so it has padding inside the menu.
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 30))
        searchField.frame = NSRect(x: 8, y: 3, width: 224, height: 24)
        container.addSubview(searchField)
        let item = NSMenuItem()
        item.view = container
        return item
    }()
    private var filterText = ""

    // Live references to the rows in each section, kept so applyFilter can flip
    // their visibility and recompute digit shortcuts without a full rebuild.
    // Each entry is a (primary, Option-key alternate) pair that must hide and
    // show together.
    private typealias EntryRow = (row: NSMenuItem, alt: NSMenuItem)
    private var historyMenuItems: [EntryRow] = []
    private var pinnedMenuItems: [EntryRow] = []

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
    // Rebuilding here is fine — it happens before the user starts typing; the
    // search filter only ever runs through applyFilter() so focus survives.
    func menuWillOpen(_ menu: NSMenu) {
        filterText = ""
        searchField.stringValue = ""
        rebuildMenu()
        applyFilter()
        // Hand keyboard focus to the field once the menu's tracking window is
        // up, otherwise the field won't accept typing during menu tracking.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.searchField.window?.makeFirstResponder(self.searchField)
        }
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        historyMenuItems.removeAll()
        pinnedMenuItems.removeAll()

        if !AXIsProcessTrusted() {
            let warning = NSMenuItem(title: "⚠️ Append Copy needs Accessibility access…",
                                     action: #selector(openAccessibilitySettings),
                                     keyEquivalent: "")
            warning.target = self
            menu.addItem(warning)
            menu.addItem(.separator())
        }

        menu.addItem(searchItem)
        menu.addItem(.separator())

        // Pinned section (only when there are pins). Pins survive Clear History.
        if !history.pinned.isEmpty {
            menu.addItem(sectionHeader("Pinned"))
            for item in history.pinned {
                let pair = makeEntryItems(for: item, pinned: true)
                pinnedMenuItems.append(pair)
                menu.addItem(pair.row)
                menu.addItem(pair.alt)
            }
            menu.addItem(.separator())
        }

        menu.addItem(sectionHeader("Clipboard History"))

        if history.items.isEmpty {
            let empty = NSMenuItem(title: "History is empty", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for item in history.items {
                let pair = makeEntryItems(for: item, pinned: false)
                historyMenuItems.append(pair)
                menu.addItem(pair.row)
                menu.addItem(pair.alt)
            }
        }

        menu.addItem(.separator())
        let hint = NSMenuItem(title: "⌘⇧C  Append copy", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(separatorPreferenceItem())
        menu.addItem(pasteOnPickItem())
        menu.addItem(.separator())

        let clear = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
        addLoginItemToggle(to: menu)
        menu.addItem(NSMenuItem(title: "Quit StackClip",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
    }

    private func sectionHeader(_ title: String) -> NSMenuItem {
        if #available(macOS 14, *) {
            return NSMenuItem.sectionHeader(title: title)
        }
        let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        header.isEnabled = false
        return header
    }

    // A history/pinned entry is two stacked rows sharing one menu slot: the
    // visible row copies on click, and an Option-key alternate (hidden until ⌥
    // is held) pins or unpins it. This keeps the common case a single click
    // while avoiding a submenu — a submenu on the row would swallow the click
    // and never fire the copy action. The full value rides in representedObject
    // so filtering and pasting can read it back. The pair must share visibility,
    // so applyFilter toggles the alternate alongside its primary.
    private func makeEntryItems(for item: String, pinned: Bool) -> EntryRow {
        let label = menuTitle(for: item)

        let row = NSMenuItem(title: (pinned ? "📌 " : "") + label,
                             action: #selector(historyItemClicked(_:)),
                             keyEquivalent: "")
        row.keyEquivalentModifierMask = [] // bare digit picks the item
        row.target = self
        row.representedObject = item
        row.toolTip = item.count > 300 ? String(item.prefix(300)) + "…" : item

        let alt = NSMenuItem(title: (pinned ? "📌 Unpin: " : "📌 Pin: ") + label,
                             action: #selector(togglePin(_:)),
                             keyEquivalent: "")
        alt.keyEquivalentModifierMask = .option
        alt.isAlternate = true
        alt.target = self
        alt.representedObject = item
        return (row, alt)
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

    private func pasteOnPickItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Paste after picking",
                              action: #selector(togglePasteOnPick), keyEquivalent: "")
        item.target = self
        item.state = pasteOnPick ? .on : .off
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

    // MARK: Filtering (Feature A)

    // Toggle isHidden on the existing rows to match the case-insensitive filter
    // and recompute the 1–9 digit shortcuts over what's visible. Deliberately
    // does NOT rebuild the menu, so the search field keeps keyboard focus.
    private func applyFilter() {
        let query = filterText.trimmingCharacters(in: .whitespaces)
        let isEmpty = query.isEmpty // empty filter shows the full list as before.

        func matches(_ value: String) -> Bool {
            isEmpty || value.range(of: query, options: .caseInsensitive) != nil
        }

        // Hide/show each primary together with its Option-key alternate.
        // Clear a hidden row's digit so a stale keyEquivalent can't win
        // performKeyEquivalent over a visible row sharing the same digit;
        // visible rows get their digits (re)assigned below.
        func setHidden(_ pair: EntryRow, _ hidden: Bool) {
            pair.row.isHidden = hidden
            pair.alt.isHidden = hidden
            if hidden {
                pair.row.keyEquivalent = ""
                pair.alt.keyEquivalent = ""
            }
        }

        for pair in pinnedMenuItems {
            let value = pair.row.representedObject as? String ?? ""
            setHidden(pair, !matches(value))
        }

        var visibleHistory: [EntryRow] = []
        for pair in historyMenuItems {
            let value = pair.row.representedObject as? String ?? ""
            let show = matches(value)
            setHidden(pair, !show)
            if show { visibleHistory.append(pair) }
        }

        // Digit shortcuts follow the visible history rows (1…9, top to bottom).
        // Keep the alternate's keyEquivalent in lockstep with its primary so
        // AppKit still recognises the two as a single Option-swappable pair (a
        // mismatch there would make both rows show at once).
        for (index, pair) in visibleHistory.enumerated() {
            let digit = index < 9 ? String(index + 1) : ""
            pair.row.keyEquivalent = digit
            pair.alt.keyEquivalent = digit
        }
        // The "History is empty" placeholder (when present) needs no filtering:
        // it only exists when there are genuinely no history items to match.
    }

    @objc private func searchChanged(_ sender: NSSearchField) {
        filterText = sender.stringValue
        applyFilter()
    }

    // Fires on every character typed/deleted in the field — the dependable
    // path for live filtering while the menu is tracking.
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField, field === searchField else { return }
        filterText = field.stringValue
        applyFilter()
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

    @objc private func togglePasteOnPick() {
        pasteOnPick.toggle()
        rebuildMenu()
    }

    @objc private func historyItemClicked(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? String else { return }
        history.copyToPasteboard(item)
        guard pasteOnPick else { return }
        // The menu is dismissing now; paste only once it has fully closed and
        // focus has returned to the target app, otherwise ⌘V lands nowhere.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            AppendCopy.simulatePaste()
        }
    }

    @objc private func togglePin(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? String else { return }
        if history.isPinned(item) {
            history.unpin(item)
        } else {
            history.pin(item)
        }
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
