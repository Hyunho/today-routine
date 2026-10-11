import XCTest
@testable import RoutineCore

final class ReminderDefaultsTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-01T00:00:00Z")!
    func testDefaultsExceptionsAndUntimedRoutine() {
        let standard = Routine(name: "기본", minute: 600)
        let custom = Routine(name: "별도", minute: 600)
        let off = Routine(name: "끔", minute: 600)
        var snapshot = StoreSnapshot()
        snapshot.routines = [standard, custom, off, Routine(name: "시간 미정")]
        snapshot.reminders = [ReminderPreference(routineID: custom.id, enabled: true, minute: 660), ReminderPreference(routineID: off.id, enabled: false, minute: 600)]
        let requests = ReminderPlanner.requests(snapshot: snapshot, now: now, defaults: ReminderDefaults(enabled: true, leadMinutes: 10))
        XCTAssertEqual(Set(requests.map(\.title)), Set(["기본", "별도"]))
        XCTAssertEqual(requests.first { $0.title == "기본" }?.fireDate, now.addingTimeInterval(50 * 60))
        XCTAssertEqual(requests.first { $0.title == "별도" }?.fireDate, now.addingTimeInterval(120 * 60))
        let disabled = ReminderPlanner.requests(snapshot: snapshot, now: now)
        XCTAssertEqual(Set(disabled.map(\.title)), ["별도"])
    }
    func testDayOverrideAndPreviousDayLead() {
        let r = Routine(name: "자정", minute: 10)
        var snapshot = StoreSnapshot(); snapshot.routines = [r]
        let record = RoutineDayRecord(routineID: r.id, dayKey: "2026-10-02", name: r.name)
        record.minuteOverride = 20; snapshot.records = [record]
        let requests = ReminderPlanner.requests(snapshot: snapshot, now: now, defaults: ReminderDefaults(enabled: true, leadMinutes: 30))
        let request = requests.first { $0.id.hasSuffix("2026-10-02") }
        XCTAssertEqual(request?.fireDate, ISO8601DateFormatter().date(from: "2026-10-01T14:50:00Z"))
    }
    func testOvernightQuietHoursIncludeStartExcludeEnd() {
        let options = ReminderDefaults(quietEnabled: true, quietStart: 1320, quietEnd: 420)
        let formatter = ISO8601DateFormatter()
        XCTAssertTrue(options.suppresses(formatter.date(from: "2026-10-01T13:00:00Z")!))
        XCTAssertTrue(options.suppresses(formatter.date(from: "2026-10-01T21:59:00Z")!))
        XCTAssertFalse(options.suppresses(formatter.date(from: "2026-10-01T22:00:00Z")!))
        let r = Routine(name: "야간", minute: 1380)
        var snapshot = StoreSnapshot(); snapshot.routines = [r]
        snapshot.reminders = [ReminderPreference(routineID: r.id, enabled: true, minute: 1380)]
        XCTAssertTrue(ReminderPlanner.requests(snapshot: snapshot, now: now, defaults: options).isEmpty)
    }
    @MainActor func testApplyDefaultsClearsOnlyRequestedExceptions() throws {
        let store = RoutineStore(container: try PersistenceFactory.make(inMemory: true))
        let a = UUID(), b = UUID()
        try store.saveReminder(routineID: a, enabled: true, minute: 500)
        try store.saveReminder(routineID: b, enabled: false, minute: 600)
        try store.useDefaultReminder(routineID: a)
        XCTAssertEqual(try store.loadSnapshot().reminders.map(\.routineID), [b])
        try store.useDefaultReminder()
        XCTAssertTrue(try store.loadSnapshot().reminders.isEmpty)
    }
}
