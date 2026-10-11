import XCTest
@testable import RoutineCore

final class OutlineExpansionTests: XCTestCase {
    private var nodes: [OutlineNode] {
        [OutlineNode(id: "section", children: [OutlineNode(id: "routine", children: [OutlineNode(id: "step")]), OutlineNode(id: "other")])]
    }

    func testCollapsedDescendantsAreExcludedFromNavigation() {
        var expansion = OutlineExpansion()
        expansion.toggle("routine")
        XCTAssertEqual(expansion.visibleIDs(in: nodes), ["section", "routine", "other"])
        expansion.toggle("section")
        XCTAssertEqual(expansion.visibleIDs(in: nodes), ["section"])
        expansion.toggle("section")
        XCTAssertEqual(expansion.visibleIDs(in: nodes), ["section", "routine", "other"])
    }

    func testArrowsCollapseExpandAndMoveBetweenParentAndChild() {
        var expansion = OutlineExpansion()
        var selection = OutlineSelection()
        selection.select("routine")
        expansion.moveHorizontal(expanding: false, selection: &selection, in: nodes)
        XCTAssertEqual(selection.focus, "routine")
        XCTAssertFalse(expansion.visibleIDs(in: nodes).contains("step"))
        expansion.moveHorizontal(expanding: true, selection: &selection, in: nodes)
        XCTAssertEqual(selection.focus, "routine")
        expansion.moveHorizontal(expanding: true, selection: &selection, in: nodes)
        XCTAssertEqual(selection.focus, "step")
        expansion.moveHorizontal(expanding: false, selection: &selection, in: nodes)
        XCTAssertEqual(selection.focus, "routine")
    }
}
