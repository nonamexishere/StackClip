import AppKit
import Carbon.HIToolbox

// A focusable field that records the next key chord. Click it (or tab to it) and
// it shows "Recording…"; the next chord with at least one modifier (or a bare
// function key) is reported via onChange. A modifier-less ordinary key is
// rejected so it can't hijack normal typing — recording just continues. Esc
// cancels recording and restores the prior shortcut display.
final class ShortcutRecorderView: NSView {
    // Reports a newly captured chord. Not called when recording is cancelled.
    var onChange: ((Shortcut) -> Void)?

    private var shortcut: Shortcut
    private var isRecording = false
    private let label = NSTextField(labelWithString: "")

    init(shortcut: Shortcut) {
        self.shortcut = shortcut
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor

        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.font = .systemFont(ofSize: 13)
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
        ])
        refreshLabel()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize { NSSize(width: 120, height: 24) }

    // Update the displayed chord from the outside (e.g. after Reset to Default).
    func setShortcut(_ shortcut: Shortcut) {
        self.shortcut = shortcut
        isRecording = false
        refreshLabel()
    }

    // Must accept first responder to capture key events and draw a focus ring.
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() { bounds.fill() }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        startRecording()
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { startRecording() }
        return became
    }

    override func resignFirstResponder() -> Bool {
        if isRecording { cancelRecording() }
        return super.resignFirstResponder()
    }

    private func startRecording() {
        isRecording = true
        label.stringValue = "Recording…"
        label.textColor = .secondaryLabelColor
        needsDisplay = true
    }

    private func cancelRecording() {
        isRecording = false
        refreshLabel()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        // Esc cancels and restores the previous shortcut.
        if Int(event.keyCode) == kVK_Escape {
            cancelRecording()
            window?.makeFirstResponder(nil)
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let carbon = Shortcut.carbonModifiers(from: flags)
        let keyCode = UInt32(event.keyCode)

        // Require a modifier — except for function keys, which are safe to bind
        // bare. A modifier-less ordinary key is rejected: stay in recording mode
        // so the user can try again rather than capturing a hijacking binding.
        guard carbon != 0 || Shortcut.functionKeyCodes.contains(Int(keyCode)) else {
            NSSound.beep()
            return
        }

        shortcut = Shortcut(keyCode: keyCode, modifiers: carbon)
        isRecording = false
        refreshLabel()
        onChange?(shortcut)
        window?.makeFirstResponder(nil)
    }

    private func refreshLabel() {
        label.stringValue = shortcut.displayString
        label.textColor = .labelColor
        needsDisplay = true
    }
}
