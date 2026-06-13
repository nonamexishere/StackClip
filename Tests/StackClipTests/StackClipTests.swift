import XCTest
import Carbon.HIToolbox
@testable import StackClip

final class HistoryInsertTests: XCTestCase {
    func testNewestGoesToFront() {
        let list = ClipboardHistory.inserting("b", into: ["a"])
        XCTAssertEqual(list, ["b", "a"])
    }

    func testDuplicateMovesToFrontWithoutGrowing() {
        let list = ClipboardHistory.inserting("a", into: ["c", "b", "a"])
        XCTAssertEqual(list, ["a", "c", "b"])
    }

    func testCapIsEnforcedDroppingOldest() {
        let list = ClipboardHistory.inserting("new", into: ["x", "y", "z"], max: 3)
        XCTAssertEqual(list, ["new", "x", "y"])
        XCTAssertEqual(list.count, 3)
    }

    func testInsertIntoEmpty() {
        XCTAssertEqual(ClipboardHistory.inserting("only", into: []), ["only"])
    }
}

final class SeparatorTests: XCTestCase {
    func testStrings() {
        XCTAssertEqual(AppendCopy.Separator.newline.string, "\n")
        XCTAssertEqual(AppendCopy.Separator.space.string, " ")
        XCTAssertEqual(AppendCopy.Separator.tab.string, "\t")
    }

    func testRawValueRoundTrip() {
        for sep in AppendCopy.Separator.allCases {
            XCTAssertEqual(AppendCopy.Separator(rawValue: sep.rawValue), sep)
        }
    }

    func testMenuTitlesAreDistinct() {
        let titles = Set(AppendCopy.Separator.allCases.map(\.menuTitle))
        XCTAssertEqual(titles.count, AppendCopy.Separator.allCases.count)
    }
}

final class ShortcutFormatterTests: XCTestCase {
    func testCarbonModifiersFromCocoaFlags() {
        XCTAssertEqual(Shortcut.carbonModifiers(from: [.command, .shift]),
                       UInt32(cmdKey | shiftKey))
        XCTAssertEqual(Shortcut.carbonModifiers(from: [.option]), UInt32(optionKey))
        XCTAssertEqual(Shortcut.carbonModifiers(from: []), 0)
    }

    func testDefaultIsCommandShiftC() {
        XCTAssertEqual(Shortcut.appendCopyDefault.displayString, "⇧⌘C")
    }

    func testModifierGlyphOrdering() {
        let mods = UInt32(cmdKey | controlKey | optionKey | shiftKey)
        XCTAssertEqual(Shortcut.displayString(keyCode: UInt32(kVK_Space), modifiers: mods),
                       "⌃⌥⇧⌘Space")
    }

    func testUnknownKeyFallsBack() {
        XCTAssertEqual(Shortcut.keyName(for: 9999), "Key (9999)")
    }

    func testFunctionKeyMembership() {
        XCTAssertTrue(Shortcut.functionKeyCodes.contains(kVK_F5))
        XCTAssertFalse(Shortcut.functionKeyCodes.contains(kVK_ANSI_A))
    }
}
