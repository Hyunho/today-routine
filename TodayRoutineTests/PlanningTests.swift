import XCTest
@testable import RoutineCore
final class PlanningTests: XCTestCase {
    @MainActor func store() throws -> RoutineStore { RoutineStore(container: try PersistenceFactory.make(inMemory: true)) }
    @MainActor func testRejectsInvalidBlockRange() throws {
        let s = try store(); var d = BlockDraft(); d.title = "일"; d.dayKey = "2026-10-02"; d.startMinute = 600; d.endMinute = 600
        XCTAssertThrowsError(try s.upsertBlock(d)); d.endMinute = 1441; XCTAssertThrowsError(try s.upsertBlock(d))
        XCTAssertTrue(try s.loadSnapshot().blocks.isEmpty)
    }
    @MainActor func testOverlapWarnsButAllowsSave() throws {
        let s = try store(); var a = BlockDraft(); a.title = "첫째"; a.dayKey = "2026-10-02"; try s.upsertBlock(a)
        var b = BlockDraft(); b.title = "둘째"; b.dayKey = a.dayKey; b.startMinute = 550
        XCTAssertTrue(try s.overlaps(b)); try s.upsertBlock(b); XCTAssertEqual(try s.loadSnapshot().blocks.count, 2)
    }
    @MainActor func testDeletingTaskPreservesBlockTitle() throws {
        let s = try store(); var t = TaskDraft(); t.title = "독서"; try s.upsertTask(t)
        var b = BlockDraft(); b.title = "책 읽는 시간"; b.dayKey = "2026-10-02"; b.linkedID = t.id; b.linkedKind = "task"; try s.upsertBlock(b)
        XCTAssertNil(try s.loadSnapshot().tasks[0].completedAt)
        try s.deleteTask(id: t.id)
        XCTAssertEqual(try s.loadSnapshot().blocks[0].title, "책 읽는 시간"); XCTAssertNil(try s.loadSnapshot().blocks[0].linkedID)
    }
}
