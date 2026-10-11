import XCTest
@testable import RoutineCore

final class TodayDocumentTests: XCTestCase {
    @MainActor func testRefreshPreservesNestedNotesAndStepOrderAndMultilineCompletion() throws {
        let store = RoutineStore(container: try PersistenceFactory.make(inMemory: true))
        var routine = RoutineDraft(); routine.name = "루틴"
        routine.steps = [StepDraft(id: UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!, name: "첫째"), StepDraft(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "둘째")]
        try store.upsertRoutine(routine)
        let day = RoutineRules.dayKey(Date())
        var (doc, rev) = try store.openTodayDocument(day: day)
        XCTAssertEqual(doc.blocks[0].children.map(\.text), ["TODO 첫째", "TODO 둘째"])
        doc.blocks[0].text += "\n보존할 메모"
        doc.blocks[0].children[0].text = "DONE 첫째"
        doc.blocks[0].children[1].text = "DONE 둘째"
        doc.blocks[0].children.append(TodayDocumentBlock(text: "독립 메모"))
        rev = try store.saveTodayDocumentDraft(doc, expectedRevision: rev)
        (doc, rev) = try store.applyTodayDocument(day: day, expectedRevision: rev)
        XCTAssertEqual(doc.blocks[0].text, "DONE 루틴\n보존할 메모")
        routine.status = .archived; try store.upsertRoutine(routine)
        let refreshed = try store.openTodayDocument(day: day).0
        XCTAssertTrue(refreshed.blocks.flatMap(\.flattened).contains { $0.text == "독립 메모" })
        XCTAssertTrue(refreshed.blocks.flatMap(\.flattened).contains { $0.text == "보존할 메모" })
    }

    @MainActor func testMultipleRoutineStatusesSyncInOneAtomicApply() throws {
        let a = RoutineStore(container: try PersistenceFactory.make(inMemory: true)), b = RoutineStore(container: try PersistenceFactory.make(inMemory: true))
        let x = StoreSyncAdapter(store: a), y = StoreSyncAdapter(store: b), space = UUID()
        try x.enable(spaceID: space, deviceID: UUID()); try y.enable(spaceID: space, deviceID: UUID())
        var one = RoutineDraft(); one.name = "하나"; one.steps = [StepDraft(name: "단계")]; try a.upsertRoutine(one)
        var two = RoutineDraft(); two.name = "둘"; two.steps = [StepDraft(name: "단계")]; try a.upsertRoutine(two)
        try y.ingest(x.pendingEvents())
        let day = RoutineRules.dayKey(Date())
        var (doc, rev) = try a.openTodayDocument(day: day)
        for i in doc.blocks.indices { doc.blocks[i].text = doc.blocks[i].id == one.id ? "DONE 하나" : "SKIPPED 둘" }
        rev = try a.saveTodayDocumentDraft(doc, expectedRevision: rev)
        _ = try a.applyTodayDocument(day: day, expectedRevision: rev)
        try y.ingest(x.pendingEvents())
        let snapshot = try b.loadSnapshot()
        XCTAssertEqual(snapshot.records.first { $0.routineID == one.id }?.status, .completed)
        XCTAssertEqual(snapshot.records.first { $0.routineID == two.id }?.status, .skipped)
    }

    @MainActor func testStatusPropagationAndStableReopen() throws {
        let store = RoutineStore(container: try PersistenceFactory.make(inMemory: true))
        var routine = RoutineDraft(); routine.name = "운동"; routine.minute = 840
        routine.steps = [StepDraft(name: "준비"), StepDraft(name: "실행")]
        try store.upsertRoutine(routine)
        let day = RoutineRules.dayKey(Date())
        var (doc, rev) = try store.openTodayDocument(day: day)
        let before = rev
        XCTAssertEqual(try store.openTodayDocument(day: day).1, before)
        doc.blocks[0].text = "DONE 15:00 운동"
        rev = try store.saveTodayDocumentDraft(doc, expectedRevision: rev)
        (doc, rev) = try store.applyTodayDocument(day: day, expectedRevision: rev)
        let record = try XCTUnwrap(try store.loadSnapshot().records.first)
        XCTAssertEqual(record.status, .completed)
        XCTAssertEqual(Set(record.completedStepIDs), Set(routine.steps.map(\.id)))
        XCTAssertTrue(doc.blocks[0].children.allSatisfy { $0.text.hasPrefix("DONE ") })
        XCTAssertEqual(try store.openTodayDocument(day: day).0, doc)
        XCTAssertEqual(try store.openTodayDocument(day: day).1, rev)
        doc.blocks[0].children[0].text = "TODO 준비"
        rev = try store.saveTodayDocumentDraft(doc, expectedRevision: rev)
        (doc, _) = try store.applyTodayDocument(day: day, expectedRevision: rev)
        XCTAssertEqual(record.status, .pending)
        XCTAssertTrue(doc.blocks[0].text.hasPrefix("TODO "))
    }

    @MainActor func testDraftSurvivesStoreReopenAndConcurrentEditorIsRejected() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("test.store")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let day = RoutineRules.dayKey(Date())
        var original: [TodayDocumentBlock] = []
        do {
            let store = RoutineStore(container: try PersistenceFactory.make(url: url))
            var (doc, rev) = try store.openTodayDocument(day: day)
            doc.blocks = [TodayDocumentBlock(text: "저장한 메모", children: [TodayDocumentBlock(text: "14:00 예약")])]
            original = doc.blocks
            _ = try store.saveTodayDocumentDraft(doc, expectedRevision: rev)
            XCTAssertThrowsError(try store.saveTodayDocumentDraft(doc, expectedRevision: rev))
        }
        let reopened = RoutineStore(container: try PersistenceFactory.make(url: url))
        XCTAssertEqual(try reopened.openTodayDocument(day: day).0.blocks, original)
    }

    @MainActor func testWholeDocumentCreatesBlocksAndKeepsNestedNotesAcrossReopen() throws {
        let store = RoutineStore(container: try PersistenceFactory.make(inMemory: true))
        let day = RoutineRules.dayKey(Date())
        var (doc, revision) = try store.openTodayDocument(day: day)
        let note = TodayDocumentBlock(text: "일반 메모", children: [TodayDocumentBlock(text: "하위 메모")])
        doc.blocks = [TodayDocumentBlock(text: "TODO 14:00 집중"), note]
        revision = try store.saveTodayDocumentDraft(doc, expectedRevision: revision)
        _ = try store.applyTodayDocument(day: day, expectedRevision: revision)
        let snapshot = try store.loadSnapshot()
        XCTAssertEqual(snapshot.blocks.count, 1)
        XCTAssertEqual(snapshot.blocks[0].startMinute, 840)
        XCTAssertEqual(snapshot.blocks[0].endMinute, 870)
        XCTAssertEqual(try store.openTodayDocument(day: day).0.blocks.last, note)
    }

    @MainActor func testDeleteAndUndoRestoresIdentityAndDuration() throws {
        let store = RoutineStore(container: try PersistenceFactory.make(inMemory: true))
        let day = RoutineRules.dayKey(Date())
        var block = BlockDraft(); block.dayKey = day; block.title = "집중"; block.startMinute = 840; block.endMinute = 900
        try store.upsertBlock(block)
        var (doc, rev) = try store.openTodayDocument(day: day)
        let original = doc.blocks
        doc.blocks = [TodayDocumentBlock(text: "메모")]
        rev = try store.saveTodayDocumentDraft(doc, expectedRevision: rev)
        (doc, rev) = try store.applyTodayDocument(day: day, expectedRevision: rev)
        XCTAssertTrue(try store.loadSnapshot().blocks.isEmpty)
        doc.blocks = original
        rev = try store.saveTodayDocumentDraft(doc, expectedRevision: rev)
        _ = try store.applyTodayDocument(day: day, expectedRevision: rev)
        let restored = try XCTUnwrap(try store.loadSnapshot().blocks.first)
        XCTAssertEqual(restored.id, block.id); XCTAssertEqual(restored.endMinute - restored.startMinute, 60)
    }

    @MainActor func testInvalidDocumentRetainsDraftAndDoesNotPartiallyApply() throws {
        let store = RoutineStore(container: try PersistenceFactory.make(inMemory: true))
        let day = RoutineRules.dayKey(Date())
        var (doc, rev) = try store.openTodayDocument(day: day)
        doc.blocks = [TodayDocumentBlock(text: "14:00 정상"), TodayDocumentBlock(text: "25:00 오류")]
        rev = try store.saveTodayDocumentDraft(doc, expectedRevision: rev)
        XCTAssertThrowsError(try store.applyTodayDocument(day: day, expectedRevision: rev))
        XCTAssertTrue(try store.loadSnapshot().blocks.isEmpty)
        XCTAssertEqual(try store.openTodayDocument(day: day).0.blocks, doc.blocks)
    }

    @MainActor func testExternalEditConflictsWithDraftAndRoutineDeletionOnlyHidesThatDay() throws {
        let store = RoutineStore(container: try PersistenceFactory.make(inMemory: true))
        var routine = RoutineDraft(); routine.name = "운동"; routine.minute = 840; try store.upsertRoutine(routine)
        let day = RoutineRules.dayKey(Date())
        var (doc, rev) = try store.openTodayDocument(day: day)
        doc.blocks = [TodayDocumentBlock(text: "메모")]
        rev = try store.saveTodayDocumentDraft(doc, expectedRevision: rev)
        _ = try store.applyTodayDocument(day: day, expectedRevision: rev)
        XCTAssertEqual(try store.loadSnapshot().todayDocuments[0].hiddenRoutineIDs, [routine.id])
        XCTAssertEqual(try store.loadSnapshot().routines.count, 1)
        (doc, rev) = try store.openTodayDocument(day: day)
        doc.blocks.append(TodayDocumentBlock(text: "15:00 새 일정"))
        rev = try store.saveTodayDocumentDraft(doc, expectedRevision: rev)
        routine.name = "외부 변경"; try store.upsertRoutine(routine)
        XCTAssertThrowsError(try store.applyTodayDocument(day: day, expectedRevision: rev))
        XCTAssertTrue(try store.loadSnapshot().blocks.isEmpty)
    }
}
