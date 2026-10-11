import XCTest
@testable import RoutineCore

final class OutlineSelectionTests: XCTestCase {
    func testMovementAndRangeContraction() {
        var selection = OutlineSelection()
        let ids = ["a", "b", "c"]
        selection.move(by: 1, extending: false, in: ids)
        XCTAssertEqual(selection.selectedIDs(in: ids), ["a"])
        selection.move(by: 1, extending: true, in: ids)
        selection.move(by: 1, extending: true, in: ids)
        XCTAssertEqual(selection.selectedIDs(in: ids), ids)
        selection.move(by: -1, extending: true, in: ids)
        XCTAssertEqual(selection.selectedIDs(in: ids), ["a", "b"])
        selection.move(by: -1, extending: false, in: ids)
        XCTAssertEqual(selection.selectedIDs(in: ids), ["a"])
    }

    func testEdgesEmptyAndRemovedRows() {
        var selection = OutlineSelection()
        selection.move(by: -1, extending: false, in: ["a", "b"])
        XCTAssertEqual(selection.focus, "b")
        selection.move(by: 1, extending: true, in: ["a", "b"])
        XCTAssertEqual(selection.selectedIDs(in: ["a", "b"]), ["b"])
        selection.reconcile(with: ["a"])
        XCTAssertNil(selection.focus)
        selection.move(by: 1, extending: true, in: [])
        XCTAssertTrue(selection.selectedIDs(in: []).isEmpty)
    }

    func testSelectAllAndPreserveFocusWhenAnchorDisappears() {
        var selection = OutlineSelection()
        selection.selectAll(in: ["a", "b", "c"])
        XCTAssertEqual(selection.selectedIDs(in: ["a", "b", "c"]), ["a", "b", "c"])
        selection.reconcile(with: ["b", "c"])
        XCTAssertEqual(selection.selectedIDs(in: ["b", "c"]), ["c"])
        selection.clear()
        XCTAssertNil(selection.focus)
    }
}
