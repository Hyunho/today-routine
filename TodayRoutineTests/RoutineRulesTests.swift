import XCTest
@testable import RoutineCore
final class RoutineRulesTests: XCTestCase {
    func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }
    func testGroupedTimeSort() {
        let r = [Routine(name: "요가", minute: 390, sortOrder: 0), Routine(name: "미정", sortOrder: 1), Routine(name: "달리기", minute: 330, sortOrder: 2), Routine(name: "운동", minute: 345, sortOrder: 3)]
        XCTAssertEqual(RoutineRules.timeSorted(r).map(\.name), ["달리기", "운동", "요가", "미정"])
        XCTAssertEqual(r.map(\.sortOrder), [0,1,2,3])
        let a = Routine(name: "동률A", minute: 330, sortOrder: 8), b = Routine(name: "동률B", minute: 330, sortOrder: 2)
        XCTAssertEqual(RoutineRules.timeSorted([a,b]).map(\.name), ["동률B","동률A"])
    }
    func testSeoulMidnightAndMonday() {
        let d = date("2026-10-04T15:00:00Z")
        XCTAssertEqual(RoutineRules.dayKey(d), "2026-10-05")
        XCTAssertEqual(RoutineRules.dayKey(d.addingTimeInterval(-1)), "2026-10-04")
        XCTAssertEqual(RoutineRules.weekStart(date("2026-10-10T12:00:00Z")), d)
    }
    func testWeekdaysAndArchivedRoutine() {
        let r = Routine(name: "월요일"); r.repeatKind = .weekdays; r.weekdays = [2]
        XCTAssertTrue(RoutineRules.isScheduled(r, on: date("2026-10-05T00:00:00Z")))
        XCTAssertFalse(RoutineRules.isScheduled(r, on: date("2026-10-06T00:00:00Z")))
        r.status = .archived; XCTAssertFalse(RoutineRules.isScheduled(r, on: date("2026-10-05T00:00:00Z")))
    }
}
