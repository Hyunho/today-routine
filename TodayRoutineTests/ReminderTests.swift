import XCTest
@testable import RoutineCore
final class ReminderTests: XCTestCase {
    func testNextSevenDaysLimitedToNearest60() {
        let now = ISO8601DateFormatter().date(from: "2026-10-01T00:00:00Z")!
        var s = StoreSnapshot()
        for i in 0..<20 { let r = Routine(name: "루틴\(i)"); s.routines.append(r); s.reminders.append(ReminderPreference(routineID: r.id, enabled: true, minute: 600+i)) }
        let requests = ReminderPlanner.requests(snapshot: s, now: now)
        XCTAssertEqual(requests.count, 60); XCTAssertEqual(Set(requests.map(\.id)).count, 60)
        XCTAssertTrue(requests.allSatisfy { $0.fireDate > now && $0.fireDate < now.addingTimeInterval(7*86400) })
        XCTAssertEqual(requests.first?.fireDate, ISO8601DateFormatter().date(from: "2026-10-01T01:00:00Z"))
    }
    func testExcludesCompletedSkippedPausedWeeklyGoal() {
        let now = ISO8601DateFormatter().date(from: "2026-10-01T00:00:00Z")!
        let r = Routine(name: "매일"), paused = Routine(name: "정지"), goal = Routine(name: "주간")
        paused.status = .paused; goal.repeatKind = .weeklyGoal
        let record = RoutineDayRecord(routineID: r.id, dayKey: "2026-10-01", name: r.name); record.status = .completed
        let next = RoutineDayRecord(routineID: r.id, dayKey: "2026-10-02", name: r.name); next.status = .skipped
        var s = StoreSnapshot(); s.routines = [r,paused,goal]; s.records = [record,next]; s.reminders = s.routines.map { ReminderPreference(routineID: $0.id, enabled: true, minute: 600) }
        let requests = ReminderPlanner.requests(snapshot: s, now: now)
        XCTAssertEqual(requests.count, 5)
        XCTAssertEqual(requests.first?.fireDate, ISO8601DateFormatter().date(from: "2026-10-03T01:00:00Z"))
    }
}
