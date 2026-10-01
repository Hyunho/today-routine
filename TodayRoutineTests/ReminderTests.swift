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

import UserNotifications
@MainActor private final class FakeNotificationClient: NotificationClient {
    var allowed: UNAuthorizationStatus = .denied
    var ids = ["routine/obsolete", "other-feature/keep"]
    var added: [ReminderRequest] = []
    func requestPermission() async throws -> Bool { allowed == .authorized }
    func authorization() async -> UNAuthorizationStatus { allowed }
    func pendingIDs() async -> [String] { ids }
    func remove(ids removed: [String]) { ids.removeAll { removed.contains($0) } }
    func add(_ request: ReminderRequest) async throws { added.append(request); ids.append(request.id) }
}
extension ReminderTests {
    @MainActor func testDeniedPermissionDoesNotPreventSaving() async throws {
        let client = FakeNotificationClient()
        let service = NotificationService(client: client)
        let allowed = try await service.requestPermission(); XCTAssertFalse(allowed)
        let store = RoutineStore(container: try PersistenceFactory.make(inMemory: true))
        var draft = RoutineDraft(); draft.name = "거부해도 저장"; try store.upsertRoutine(draft)
        let denied = NotificationService(client: client); denied.enqueue(snapshot: try store.loadSnapshot()); await denied.waitUntilIdle()
        XCTAssertEqual(try store.loadSnapshot().routines.count, 1)
        XCTAssertTrue(denied.status.contains("꺼져")); XCTAssertTrue(client.added.isEmpty)
        XCTAssertEqual(client.ids, ["other-feature/keep"])
    }
    @MainActor func testAuthorizedRefreshSchedulesAndCancelsCompletedDay() async throws {
        let client = FakeNotificationClient(); client.allowed = .authorized
        let service = NotificationService(client: client)
        let r = Routine(name: "알림"), pref = ReminderPreference(routineID: UUID(), enabled: true, minute: 1439)
        pref.routineID = r.id
        var snapshot = StoreSnapshot(); snapshot.routines = [r]; snapshot.reminders = [pref]
        service.enqueue(snapshot: snapshot); await service.waitUntilIdle()
        XCTAssertFalse(client.added.isEmpty); XCTAssertTrue(client.ids.contains("other-feature/keep"))
        let record = RoutineDayRecord(routineID: r.id, dayKey: RoutineRules.dayKey(Date()), name: r.name); record.status = .completed; snapshot.records = [record]
        service.enqueue(snapshot: snapshot); await service.waitUntilIdle()
        XCTAssertFalse(client.ids.contains("routine/\(r.id.uuidString)/\(record.dayKey)"))
    }
}
