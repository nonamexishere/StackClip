import AppKit

// A small Preferences window holding the global-shortcut recorder. StackClip runs
// as an .accessory app, so this is the one regular, titled window it shows.
// Created lazily and reused; the owner activates the app before showing it so the
// recorder field can actually receive key events (see AppDelegate.showPreferences).
final class PreferencesWindowController: NSWindowController {
    // Reports a chord chosen via the recorder or the Reset button. The owner
    // persists it and calls HotKeyManager.update.
    var onChange: ((Shortcut) -> Void)?

    private let recorder: ShortcutRecorderView

    init(shortcut: Shortcut) {
        recorder = ShortcutRecorderView(shortcut: shortcut)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 120),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        window.title = "StackClip Preferences"
        window.isReleasedWhenClosed = false

        super.init(window: window)

        let label = NSTextField(labelWithString: "Append-copy shortcut:")
        label.alignment = .right

        recorder.onChange = { [weak self] shortcut in
            self?.onChange?(shortcut)
        }

        let resetButton = NSButton(title: "Reset to Default",
                                   target: self,
                                   action: #selector(resetToDefault))
        resetButton.bezelStyle = .rounded

        let row = NSStackView(views: [label, recorder])
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY

        let stack = NSStackView(views: [row, resetButton])
        stack.orientation = .vertical
        stack.spacing = 14
        stack.alignment = .trailing
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        window.contentView = content

        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // Keep the recorder's display in sync when the shortcut changes from outside.
    func setShortcut(_ shortcut: Shortcut) {
        recorder.setShortcut(shortcut)
    }

    @objc private func resetToDefault() {
        recorder.setShortcut(.appendCopyDefault)
        onChange?(.appendCopyDefault)
    }
}
