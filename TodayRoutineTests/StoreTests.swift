import XCTest
import SwiftData
@testable import RoutineCore

final class StoreTests: XCTestCase {
    @MainActor func testWeeklyGoalCannotBeCreatedButExistingRoutineIsPreserved() throws {
        let store = RoutineStore(container: try PersistenceFactory.make(inMemory: true))
        var draft = RoutineDraft(); draft.name = "새 주간 목표"; draft.repeatKind = .weeklyGoal
        XCTAssertThrowsError(try store.upsertRoutine(draft))
        XCTAssertTrue(try store.loadSnapshot().routines.isEmpty)

        let legacy = Routine(name: "확인할 기존 루틴")
        legacy.repeatKind = .weeklyGoal; legacy.weeklyTarget = 4; legacy.status = .paused
        store.context.insert(legacy); try store.save()
        var edit = RoutineDraft(legacy, steps: [])
        edit.note = "삭제하지 않고 보존"
        try store.upsertRoutine(edit)
        XCTAssertEqual(legacy.repeatKind, .weeklyGoal)
        XCTAssertEqual(legacy.weeklyTarget, 4)
        XCTAssertEqual(legacy.status, .paused)
        XCTAssertEqual(legacy.note, "삭제하지 않고 보존")

        edit.repeatKind = .weekdays; edit.weekdays = [2, 4]
        try store.upsertRoutine(edit)
        edit.repeatKind = .weeklyGoal
        XCTAssertThrowsError(try store.upsertRoutine(edit))
        XCTAssertEqual(legacy.repeatKind, .weekdays)
    }
    @MainActor func testSaveFailureRollsBackWithoutLosingDraft() throws {
        let store = RoutineStore(container: try PersistenceFactory.make(inMemory: true))
        var draft = RoutineDraft(); draft.name = "원래 이름"; try store.upsertRoutine(draft)
        draft.name = "보존할 입력"
        store.saveOperation = { _ in throw CocoaError(.fileWriteOutOfSpace) }
        XCTAssertThrowsError(try store.upsertRoutine(draft))
        XCTAssertEqual(try store.loadSnapshot().routines.first?.name, "원래 이름")
        XCTAssertEqual(draft.name, "보존할 입력")
        store.saveOperation = nil; try store.upsertRoutine(draft)
        XCTAssertEqual(try store.loadSnapshot().routines.first?.name, "보존할 입력")
    }
    @MainActor func testReopenPreservesAllModels() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("routine.store")
        let id = UUID()
        do {
            let store = RoutineStore(container: try PersistenceFactory.make(url: url))
            store.context.insert(Routine(id: id, name: "아침", minute: 330))
            store.context.insert(RoutineStep(routineID: id, name: "물"))
            store.context.insert(RoutineGroup(name: "건강"))
            store.context.insert(RoutineDayRecord(routineID: id, dayKey: "2026-10-01", name: "아침"))
            store.context.insert(TaskItem(title: "책", dayKey: "2026-10-01"))
            store.context.insert(TimeBlock(title: "독서", dayKey: "2026-10-01", start: 540, end: 600))
            store.context.insert(ReminderPreference(routineID: id, enabled: true, minute: 330))
            try store.save()
        }
        let reopened = RoutineStore(container: try PersistenceFactory.make(url: url))
        let s = try reopened.loadSnapshot()
        XCTAssertEqual(s.routines.first?.id, id); XCTAssertEqual(s.routines.first?.name, "아침")
        XCTAssertEqual(s.steps.first?.name, "물"); XCTAssertEqual(s.groups.first?.name, "건강")
        XCTAssertEqual(s.records.first?.dayKey, "2026-10-01"); XCTAssertEqual(s.tasks.first?.title, "책")
        XCTAssertEqual(s.blocks.first?.startMinute, 540); XCTAssertEqual(s.reminders.first?.minute, 330)
    }
    @MainActor func testInvalidStoreReportsErrorWithoutReset() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let data = Data("invalid database".utf8); try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try PersistenceFactory.make(url: url))
        XCTAssertEqual(try Data(contentsOf: url), data)
    }
}

extension StoreTests {
    @MainActor func testDurationSaveEditClearAndInvalidInput() throws {
        let store = RoutineStore(container: try PersistenceFactory.make(inMemory: true))
        var draft = RoutineDraft(); draft.name = "독서"
        try store.upsertRoutine(draft)
        let routine = try XCTUnwrap(store.loadSnapshot().routines.first)
        XCTAssertNil(routine.durationMinutes)
        draft.durationMinutes = 45
        try store.upsertRoutine(draft)
        XCTAssertEqual(routine.durationMinutes, 45)
        var edit = RoutineDraft(routine, steps: [])
        XCTAssertEqual(edit.durationMinutes, 45)
        for invalid in [0, -1, 1441] {
            edit.durationMinutes = invalid
            XCTAssertThrowsError(try store.upsertRoutine(edit))
            XCTAssertEqual(routine.durationMinutes, 45)
        }
        edit.durationMinutes = nil
        try store.upsertRoutine(edit)
        XCTAssertNil(routine.durationMinutes)
    }
}

extension StoreTests {
    @MainActor func testDurationSurvivesStoreReopenAndLegacySyncWithoutField() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("routine.store")
        var draft = RoutineDraft(); draft.name = "독서"; draft.durationMinutes = 75
        do {
            let store = RoutineStore(container: try PersistenceFactory.make(url: url))
            try store.upsertRoutine(draft)
            var unknown = RoutineDraft(); unknown.name = "미정 루틴"
            try store.upsertRoutine(unknown)
        }
        let reopened = RoutineStore(container: try PersistenceFactory.make(url: url))
        let routine = try XCTUnwrap(reopened.loadSnapshot().routines.first { $0.id == draft.id })
        XCTAssertEqual(routine.durationMinutes, 75)
        XCTAssertNil(try reopened.loadSnapshot().routines.first { $0.name == "미정 루틴" }?.durationMinutes)
        var state = SyncState()
        let legacy = SyncObject(kind: .routine, id: draft.id.uuidString, fields: ["note": "이전 기기에서 수정"])
        state.objects[legacy.key] = legacy
        try StoreSyncBridge.apply(state, store: reopened)
        XCTAssertEqual(routine.durationMinutes, 75)
        XCTAssertEqual(routine.note, "이전 기기에서 수정")
    }
}
