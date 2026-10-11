import XCTest
@testable import RoutineCore
final class DayTimeTests: XCTestCase {
    @MainActor func testOverrideIsPerDayPreservesCompletionAndCanReset() throws {
        let store = RoutineStore(container: try PersistenceFactory.make(inMemory: true))
        var d = RoutineDraft(); d.name = "운동"; d.minute = 360; try store.upsertRoutine(d)
        let day = RoutineRules.date(for: "2026-10-02")!, tomorrow = RoutineRules.date(for: "2026-10-03")!
        try store.setStatus(routineID: d.id, date: day, status: .completed)
        try store.setDayMinute(routineID: d.id, date: day, minute: 600)
        var s = try store.loadSnapshot(); let r = s.routines[0]
        XCTAssertEqual(r.minute, 360)
        XCTAssertEqual(RoutineRules.minute(r, records: s.records, on: day), 600)
        XCTAssertEqual(RoutineRules.minute(r, records: s.records, on: tomorrow), 360)
        XCTAssertEqual(s.records[0].status, .completed)
        XCTAssertThrowsError(try store.setDayMinute(routineID: d.id, date: day, minute: 1440))
        try store.setDayMinute(routineID: d.id, date: day, minute: nil)
        s = try store.loadSnapshot()
        XCTAssertEqual(RoutineRules.minute(r, records: s.records, on: day), 360)
    }
    @MainActor func testOverrideAndResetSyncBetweenStores() throws {
        let a = RoutineStore(container: try PersistenceFactory.make(inMemory: true)), b = RoutineStore(container: try PersistenceFactory.make(inMemory: true))
        let x = StoreSyncAdapter(store: a), y = StoreSyncAdapter(store: b), space = UUID()
        try x.enable(spaceID: space, deviceID: UUID()); try y.enable(spaceID: space, deviceID: UUID())
        var d = RoutineDraft(); d.name = "기상"; d.minute = 300; try a.upsertRoutine(d)
        let day = RoutineRules.date(for: "2026-10-02")!
        try a.setDayMinute(routineID: d.id, date: day, minute: 420)
        try y.ingest(x.pendingEvents())
        XCTAssertEqual(try b.loadSnapshot().records[0].minuteOverride, 420)
        try a.setDayMinute(routineID: d.id, date: day, minute: nil)
        try y.ingest(x.pendingEvents())
        XCTAssertNil(try b.loadSnapshot().records[0].minuteOverride)
    }
}

extension DayTimeTests {
    @MainActor func testUntimedRoutineCanBeScheduledForOneDayAndReset() throws {
        let store = RoutineStore(container: try PersistenceFactory.make(inMemory: true))
        var d = RoutineDraft(); d.name = "시간 미정"; try store.upsertRoutine(d)
        let day = RoutineRules.date(for: "2026-10-02")!, next = RoutineRules.date(for: "2026-10-03")!
        try store.setDayMinute(routineID: d.id, date: day, minute: 1080)
        var s = try store.loadSnapshot(); let routine = s.routines[0]
        XCTAssertEqual(RoutineRules.minute(routine, records: s.records, on: day), 1080)
        XCTAssertNil(RoutineRules.minute(routine, records: s.records, on: next))
        XCTAssertNil(routine.minute)
        try store.setDayMinute(routineID: d.id, date: day, minute: nil)
        s = try store.loadSnapshot()
        XCTAssertNil(RoutineRules.minute(routine, records: s.records, on: day))
    }
}
