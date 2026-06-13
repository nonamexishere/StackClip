import AppKit

final class ClipboardHistory {
    static let maxItems = 50
    private static let defaultsKey = "history"
    private static let pinnedKey = "pinned"
    // Set by password managers (and others) on copies that must not be recorded.
    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    private(set) var items: [String]
    // Favorites the user has pinned; persisted separately so they survive a
    // history clear and render in their own menu section.
    private(set) var pinned: [String]
    var onChange: (() -> Void)?

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?

    init() {
        items = UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? []
        pinned = UserDefaults.standard.stringArray(forKey: Self.pinnedKey) ?? []
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

    func isPinned(_ item: String) -> Bool {
        pinned.contains(item)
    }

    // Pin/unpin a value. Pins are de-duplicated and capped at maxItems so the
    // section can't grow without bound; newest pin floats to the top.
    func pin(_ item: String) {
        guard !pinned.contains(item) else { return }
        pinned.insert(item, at: 0)
        if pinned.count > Self.maxItems {
            pinned.removeLast(pinned.count - Self.maxItems)
        }
        savePinned()
        onChange?()
    }

    func unpin(_ item: String) {
        guard let index = pinned.firstIndex(of: item) else { return }
        pinned.remove(at: index)
        savePinned()
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
        items = Self.inserting(text, into: items)
        save()
        onChange?()
    }

    /// Move/insert `text` at the front of `list`, de-duplicated and capped at
    /// `max`. Pure so it can be unit-tested without the pasteboard or defaults.
    static func inserting(_ text: String, into list: [String], max: Int = maxItems) -> [String] {
        var result = list
        if let existing = result.firstIndex(of: text) {
            result.remove(at: existing)
        }
        result.insert(text, at: 0)
        if result.count > max {
            result.removeLast(result.count - max)
        }
        return result
    }

    private func save() {
        UserDefaults.standard.set(items, forKey: Self.defaultsKey)
    }

    private func savePinned() {
        UserDefaults.standard.set(pinned, forKey: Self.pinnedKey)
    }
}
