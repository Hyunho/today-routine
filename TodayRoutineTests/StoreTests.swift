import XCTest
import SwiftData
@testable import RoutineCore

final class StoreTests: XCTestCase {
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
