import AppKit

final class ClipboardHistory {
    static let maxItems = 50
    private static let defaultsKey = "history"
    // Set by password managers (and others) on copies that must not be recorded.
    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    private(set) var items: [String]
    var onChange: (() -> Void)?

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?

    init() {
        items = UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? []
        lastChangeCount = pasteboard.changeCount
    }

    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.checkPasteboard()
        }
    }

    func copyToPasteboard(_ item: String) {
        pasteboard.clearContents()
        pasteboard.setString(item, forType: .string)
        // Record our own write so the monitor doesn't churn the menu over it,
        // but still move the item to the top of the history.
        lastChangeCount = pasteboard.changeCount
        record(item)
    }

    func clear() {
        items = []
        save()
        onChange?()
    }

    private func checkPasteboard() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        if pasteboard.types?.contains(Self.concealedType) == true { return }
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return }
        record(text)
    }

    private func record(_ text: String) {
        if let existing = items.firstIndex(of: text) {
            items.remove(at: existing)
        }
        items.insert(text, at: 0)
        if items.count > Self.maxItems {
            items.removeLast(items.count - Self.maxItems)
        }
        save()
        onChange?()
    }

    private func save() {
        UserDefaults.standard.set(items, forKey: Self.defaultsKey)
    }
}
