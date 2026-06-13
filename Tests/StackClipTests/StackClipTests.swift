import XCTest
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
