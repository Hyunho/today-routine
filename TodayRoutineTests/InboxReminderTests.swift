import XCTest
@testable import RoutineCore
final class InboxReminderTests: XCTestCase {
    let routine = UUID(uuidString:"11111111-1111-1111-1111-111111111111")!
    func request(_ time: Date) -> ReminderRequest { ReminderRequest(id:"routine/\(routine.uuidString)/2026-10-06", title:"공부", fireDate:time) }
    func testDueOnceAndRestoredPending() throws {
        let now = Date(), request = request(Date().addingTimeInterval(60))
        var state = InboxState()
        InboxReminderReducer.reconcile(state: &state, requests: [request], now: now)
        XCTAssertTrue(state.items.isEmpty); XCTAssertEqual(state.pendingReminders.count, 1)
        state = try JSONDecoder().decode(InboxState.self, from: JSONEncoder().encode(state))
        InboxReminderReducer.reconcile(state: &state, requests: [], now: request.fireDate)
        XCTAssertEqual(state.items.count, 1); XCTAssertEqual(state.items[0].routineID, routine)
        XCTAssertEqual(state.items[0].date, request.fireDate)
        state.items[0].isRead = true; state.items[0].isSaved = true
        InboxReminderReducer.reconcile(state: &state, requests: [], now: request.fireDate.addingTimeInterval(10))
        XCTAssertEqual(state.items.count, 1); XCTAssertTrue(state.items[0].isRead); XCTAssertTrue(state.items[0].isSaved)
    }
    func testCancellationAndRescheduleOnlyAffectFuture() {
        let now = Date(); var state = InboxState(); let future = request(now.addingTimeInterval(120))
        InboxReminderReducer.reconcile(state: &state, requests: [future], now: now)
        let changed = request(now.addingTimeInterval(180))
        InboxReminderReducer.reconcile(state: &state, requests: [changed], now: now.addingTimeInterval(10))
        XCTAssertEqual(state.pendingReminders.first?.fireDate, changed.fireDate)
        InboxReminderReducer.reconcile(state: &state, requests: [], now: now.addingTimeInterval(20))
        XCTAssertTrue(state.pendingReminders.isEmpty); XCTAssertTrue(state.items.isEmpty)
        InboxReminderReducer.reconcile(state: &state, requests: [changed], now: now.addingTimeInterval(30))
        InboxReminderReducer.reconcile(state: &state, requests: [], now: now.addingTimeInterval(181))
        XCTAssertEqual(state.items.count, 1)
    }
    func testNoInventedHistoryOrMalformedIDs() {
        var state = InboxState(); let now = Date()
        InboxReminderReducer.reconcile(state: &state, requests: [request(now.addingTimeInterval(-1)), ReminderRequest(id:"bad", title:"bad", fireDate:now.addingTimeInterval(20))], now:now)
        XCTAssertTrue(state.items.isEmpty); XCTAssertTrue(state.pendingReminders.isEmpty)
    }
}
