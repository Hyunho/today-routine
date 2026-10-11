import XCTest
@testable import RoutineCore

final class OutlineEditingTests: XCTestCase {
    func testLineParsingAndInvalidInput() throws {
        let edit = try OutlineEdit(line: "DONE 15:30 새 제목", expectsStatus: true)
        XCTAssertEqual(edit.status, .completed)
        XCTAssertEqual(edit.minute, 930)
        XCTAssertEqual(edit.title, "새 제목")
        XCTAssertThrowsError(try OutlineEdit(line: "TODO 25:00 제목", expectsStatus: true))
        XCTAssertThrowsError(try OutlineEdit(line: "TODO 14:00", expectsStatus: true))
        XCTAssertThrowsError(try OutlineEdit(line: "DONE 10:00 제목\n다른 줄", expectsStatus: true))
    }

    @MainActor func testRoutineEditUpdatesSharedDataAndOnlySelectedDayTime() throws {
        let store = RoutineStore(container: try PersistenceFactory.make(inMemory: true))
        var draft = RoutineDraft(); draft.name = "운동"; draft.minute = 840
        try store.upsertRoutine(draft)
        let day = Date()
        try store.editOutlineRoutine(id: draft.id, date: day, original: "TODO 14:00 운동", line: "DONE 15:00 달리기")
        let snapshot = try store.loadSnapshot(), routine = try XCTUnwrap(snapshot.routines.first)
        XCTAssertEqual(routine.name, "달리기")
        XCTAssertEqual(routine.minute, 840)
        XCTAssertEqual(RoutineRules.minute(routine, records: snapshot.records, on: day), 900)
        XCTAssertEqual(snapshot.records.first?.status, .completed)
        XCTAssertThrowsError(try store.editOutlineRoutine(id: draft.id, date: day, original: "TODO 14:00 운동", line: "TODO 16:00 오래된 수정"))
        XCTAssertEqual(routine.name, "달리기")
    }

    @MainActor func testBlockKeepsDurationAndRejectsMidnightOverflow() throws {
        let store = RoutineStore(container: try PersistenceFactory.make(inMemory: true))
        var draft = BlockDraft(); draft.title = "집중"; draft.dayKey = RoutineRules.dayKey(Date()); draft.startMinute = 840; draft.endMinute = 900
        try store.upsertBlock(draft)
        try store.editOutlineBlock(id: draft.id, original: "14:00 집중", line: "15:00 독서")
        let block = try XCTUnwrap(try store.loadSnapshot().blocks.first)
        XCTAssertEqual(block.startMinute, 900); XCTAssertEqual(block.endMinute, 960)
        XCTAssertEqual(block.title, "독서")
        XCTAssertThrowsError(try store.editOutlineBlock(id: draft.id, original: "15:00 독서", line: "23:30 독서"))
        XCTAssertEqual(block.startMinute, 900)
    }

    @MainActor func testFailedSaveRollsBackAllFields() throws {
        let store = RoutineStore(container: try PersistenceFactory.make(inMemory: true))
        var draft = RoutineDraft(); draft.name = "운동"; draft.minute = 840
        try store.upsertRoutine(draft)
        store.saveOperation = { _ in throw StoreError.invalid("저장 실패") }
        XCTAssertThrowsError(try store.editOutlineRoutine(id: draft.id, date: Date(), original: "TODO 14:00 운동", line: "DONE 15:00 달리기"))
        let snapshot = try store.loadSnapshot()
        XCTAssertEqual(snapshot.routines.first?.name, "운동")
        XCTAssertTrue(snapshot.records.isEmpty)
    }

    @MainActor func testEditedRoutineSyncsTitleTimeAndCompletionTogether() throws {
        let a = RoutineStore(container: try PersistenceFactory.make(inMemory: true))
        let b = RoutineStore(container: try PersistenceFactory.make(inMemory: true))
        let x = StoreSyncAdapter(store: a), y = StoreSyncAdapter(store: b), space = UUID()
        try x.enable(spaceID: space, deviceID: UUID()); try y.enable(spaceID: space, deviceID: UUID())
        var draft = RoutineDraft(); draft.name = "운동"; draft.minute = 840
        try a.upsertRoutine(draft)
        try y.ingest(x.pendingEvents())
        try a.editOutlineRoutine(id: draft.id, date: Date(), original: "TODO 14:00 운동", line: "DONE 15:00 달리기")
        try y.ingest(x.pendingEvents())
        let snapshot = try b.loadSnapshot()
        XCTAssertEqual(snapshot.routines.first?.name, "달리기")
        XCTAssertEqual(snapshot.records.first?.minuteOverride, 900)
        XCTAssertEqual(snapshot.records.first?.status, .completed)
    }
}
