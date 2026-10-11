import XCTest
import EventKit
@testable import RoutineCore

@MainActor final class AppleRemindersTests: XCTestCase {
    func testDateOnlyAndTimedDueDates() {
        let dateOnly = DateComponents(year: 2026, month: 10, day: 6)
        XCTAssertEqual(AppleReminderDate.dayKey(dateOnly), "2026-10-06")
        XCTAssertNil(AppleReminderDate.minute(dateOnly))
        var utc = DateComponents(year: 2026, month: 10, day: 5, hour: 18, minute: 30)
        utc.timeZone = TimeZone(secondsFromGMT: 0)
        XCTAssertEqual(AppleReminderDate.dayKey(utc), "2026-10-06")
        XCTAssertEqual(AppleReminderDate.minute(utc), 210)
        let rebuilt = AppleReminderDate.components(dayKey: "2026-10-06", minute: nil)
        XCTAssertNil(rebuilt?.hour)
        XCTAssertEqual(AppleReminderDate.dayKey(rebuilt), "2026-10-06")
    }
    func testOnlySelectedListsAreLoadedAndDisconnectDoesNotDelete() async {
        let client = MemoryAppleReminders()
        let model = AppleRemindersModel(client: client, defaults: freshDefaults())
        await model.refresh()
        XCTAssertTrue(model.items.isEmpty)
        await model.select("work", enabled: true)
        XCTAssertEqual(model.items.map(\.id), ["one"])
        await model.select("work", enabled: false)
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertEqual(client.records.count, 2)
    }
    func testPermissionRevocationClearsDisplayedData() async {
        let client = MemoryAppleReminders()
        let model = AppleRemindersModel(client: client, defaults: freshDefaults())
        await model.select("work", enabled: true)
        client.hasAccess = false
        await model.refresh()
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertFalse(model.hasAccess)
    }
    func testCompletionAndSaveFailuresKeepCurrentData() async {
        let client = MemoryAppleReminders()
        let model = AppleRemindersModel(client: client, defaults: freshDefaults())
        await model.select("work", enabled: true)
        let item = model.items[0]
        client.failWrites = true
        let failed = await model.complete(item)
        XCTAssertFalse(failed)
        XCTAssertFalse(model.items[0].completed)
        XCTAssertNotNil(model.error)
        client.failWrites = false
        let saved = await model.complete(item)
        XCTAssertTrue(saved)
        XCTAssertTrue(model.items[0].completed)
    }
    func testDisconnectIgnoresInFlightFetch() async {
        let client = DelayedAppleReminders()
        let model = AppleRemindersModel(client: client, defaults: freshDefaults())
        let pending = Task { await model.select("work", enabled: true) }
        while client.continuation == nil { await Task.yield() }
        model.disconnect()
        client.continuation?.resume(returning: [client.records[0]])
        await pending.value
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertFalse(model.loading)
    }
    func testTodayUsesDueDayAndSelectionSurvivesRelaunch() async {
        let client = MemoryAppleReminders()
        client.records[0].due = DateComponents(year: 2026, month: 10, day: 6)
        let defaults = freshDefaults()
        let model = AppleRemindersModel(client: client, defaults: defaults)
        await model.select("work", enabled: true)
        let reopened = AppleRemindersModel(client: client, defaults: defaults)
        await reopened.refresh()
        XCTAssertEqual(reopened.due(on: RoutineRules.date(for: "2026-10-06")!).map(\.id), ["one"])
        XCTAssertTrue(reopened.due(on: RoutineRules.date(for: "2026-10-07")!).isEmpty)
    }
    func testTitleEditPreservesOriginalTimeZoneAndOtherReminderFields() throws {
        let reminder = EKReminder(eventStore: EKEventStore())
        reminder.title = "원본"; reminder.notes = "메모"; reminder.priority = 3
        var due = DateComponents(year: 2026, month: 10, day: 6, hour: 9, minute: 0)
        due.timeZone = TimeZone(identifier: "America/Los_Angeles")
        reminder.dueDateComponents = due
        reminder.addAlarm(EKAlarm(relativeOffset: -600))
        reminder.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil))
        let item = AppleReminderItem(id: "test", listID: "work", listTitle: "업무", title: "원본", note: "메모", due: reminder.dueDateComponents)
        var draft = AppleReminderDraft(item); draft.title = "수정"
        let originalDue = reminder.dueDateComponents
        try EventKitRemindersAccess.apply(draft, to: reminder)
        XCTAssertEqual(reminder.title, "수정")
        XCTAssertEqual(reminder.notes, "메모")
        XCTAssertEqual(reminder.dueDateComponents, originalDue)
        XCTAssertEqual(reminder.priority, 3)
        XCTAssertEqual(reminder.alarms?.first?.relativeOffset, -600)
        XCTAssertEqual(reminder.recurrenceRules?.first?.frequency, .daily)
        draft.dayKey = nil; draft.minute = nil
        try EventKitRemindersAccess.apply(draft, to: reminder)
        XCTAssertNil(reminder.dueDateComponents)
        draft.title = "  "
        XCTAssertThrowsError(try EventKitRemindersAccess.apply(draft, to: reminder))
    }
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "AppleRemindersTests-\(UUID())")!
    }
}

@MainActor class MemoryAppleReminders: AppleRemindersAccess {
    var hasAccess = true
    var failWrites = false
    var records = [AppleReminderItem(id: "one", listID: "work", listTitle: "업무", title: "마감 확인"), AppleReminderItem(id: "two", listID: "private", listTitle: "개인", title: "독서")]
    func requestAccess() async throws -> Bool { hasAccess }
    func lists() -> [AppleReminderList] { [.init(id: "work", title: "업무", source: "테스트", writable: true), .init(id: "private", title: "개인", source: "테스트", writable: true)] }
    func fetch(listIDs: Set<String>) async throws -> [AppleReminderItem] { records.filter { listIDs.contains($0.listID) } }
    func save(_ draft: AppleReminderDraft) throws {
        if failWrites { throw CocoaError(.fileWriteNoPermission) }
        if let id = draft.original?.id, let i = records.firstIndex(where: { $0.id == id }) { records[i].title = draft.title }
    }
    func complete(_ item: AppleReminderItem) throws {
        if failWrites { throw CocoaError(.fileWriteNoPermission) }
        if let i = records.firstIndex(where: { $0.id == item.id }) { records[i].completed.toggle() }
    }
}

@MainActor final class DelayedAppleReminders: MemoryAppleReminders {
    var continuation: CheckedContinuation<[AppleReminderItem], Never>?
    override func fetch(listIDs: Set<String>) async throws -> [AppleReminderItem] {
        await withCheckedContinuation { continuation = $0 }
    }
}
