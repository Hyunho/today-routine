import XCTest
import SwiftData
@testable import RoutineCore

@MainActor final class CalendarRoutineTests: XCTestCase {
    func testFailedLinkSaveKeepsOriginalScheduleAndJournal() throws {
        let store = RoutineStore(container: try PersistenceFactory.make(inMemory: true))
        var draft = RoutineDraft(); draft.name = "보존할 루틴"
        try store.upsertRoutine(draft)
        let sync = StoreSyncAdapter(store: store)
        try sync.enable(spaceID: UUID(), deviceID: UUID())
        let before = try sync.events()
        store.saveOperation = { _ in throw CocoaError(.fileWriteOutOfSpace) }
        let link = CalendarRoutineLink(localItemID: "local", externalID: "external", calendarID: "work", calendarTitle: "업무", sourceTitle: "iCloud")
        XCTAssertThrowsError(try store.linkCalendarRoutine(id: draft.id, link: link))
        let routine = try XCTUnwrap(store.loadSnapshot().routines.first)
        XCTAssertNil(routine.calendarLink)
        XCTAssertTrue(RoutineRules.isScheduled(routine, on: Date()))
        XCTAssertEqual(try sync.events(), before)
    }
    func testCreatedEventReceiptSurvivesRestartUntilLocalLinkIsSaved() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let routine = Routine(name: "독서")
        let request = try CalendarRoutineCreation(routine: routine, calendarID: "work", startDay: Date(), duration: 30)
        let creator = AppleCalendarModel(client: CalendarCreationFixture(), defaults: defaults)
        let link = try await creator.createRoutine(request)
        let reopened = AppleCalendarModel(client: CalendarReadOnlyFixture(), defaults: defaults)
        let recovered = try await reopened.createRoutine(request)
        XCTAssertEqual(recovered, link)
        reopened.finishConversion(routine.id)
        do { _ = try await reopened.createRoutine(request); XCTFail("The completed receipt must be cleared") }
        catch { XCTAssertTrue(error is StoreError) }
    }
    func testUntimedConversionIsAllDayAndWeekdaysStartOnSelectedDay() throws {
        let routine = Routine(name: "아침 준비")
        routine.repeatKind = .weekdays; routine.weekdays = [2, 4, 6]
        let request = try CalendarRoutineCreation(routine: routine, calendarID: "work", startDay: RoutineRules.date(for: "2026-10-08")!, duration: 30)
        XCTAssertTrue(request.allDay)
        XCTAssertEqual(RoutineRules.dayKey(request.start), "2026-10-09")
        XCTAssertEqual(RoutineRules.dayKey(request.end), "2026-10-10")
        XCTAssertEqual(request.weekdays, [2, 4, 6])
        routine.minute = 600
        let timed = try CalendarRoutineCreation(routine: routine, calendarID: "work", startDay: request.start, duration: 45)
        XCTAssertFalse(timed.allDay)
        XCTAssertEqual(RoutineRules.calendar.component(.hour, from: timed.start), 10)
        XCTAssertEqual(timed.end.timeIntervalSince(timed.start), 45 * 60)
    }
    func testLinkPreservesRoutineStepsAndHistoryAndSyncs() throws {
        let store = RoutineStore(container: try PersistenceFactory.make(inMemory: true))
        var draft = RoutineDraft(); draft.name = "독서"; draft.steps = [StepDraft(name: "열 쪽 읽기")]
        try store.upsertRoutine(draft)
        let day = RoutineRules.date(for: "2026-10-01")!
        try store.setStatus(routineID: draft.id, date: day, status: .completed)
        let sync = StoreSyncAdapter(store: store), space = UUID()
        try sync.enable(spaceID: space, deviceID: UUID())
        let link = CalendarRoutineLink(localItemID: "local", externalID: "external", calendarID: "work", calendarTitle: "업무", sourceTitle: "iCloud")
        try store.linkCalendarRoutine(id: draft.id, link: link)
        let snapshot = try store.loadSnapshot(), routine = try XCTUnwrap(snapshot.routines.first)
        XCTAssertEqual(routine.id, draft.id)
        XCTAssertEqual(snapshot.steps.first?.id, draft.steps.first?.id)
        XCTAssertEqual(snapshot.records.first?.status, .completed)
        XCTAssertFalse(RoutineRules.isScheduled(routine, on: Date()))
        XCTAssertThrowsError(try store.setDayMinute(routineID: routine.id, date: Date(), minute: 600))
        let peer = RoutineStore(container: try PersistenceFactory.make(inMemory: true)), remote = StoreSyncAdapter(store: peer)
        try remote.enable(spaceID: space, deviceID: UUID()); try remote.ingest(sync.events())
        XCTAssertEqual(try peer.loadSnapshot().routines.first?.calendarLink, link)
    }
    func testMatchingUsesMarkerOrScopedExternalIDAndRejectsAmbiguousCopies() {
        let routine = Routine(name: "독서")
        routine.calendarLink = CalendarRoutineLink(localItemID: "old-local", externalID: "external", calendarID: "old-calendar", calendarTitle: "업무", sourceTitle: "iCloud")
        let start = Date()
        var event = AppleCalendarEvent(id: "new", calendarID: "new-calendar", calendarTitle: "업무", title: "독서", start: start, end: start.addingTimeInterval(1800), allDay: false, location: "", note: "", url: nil, seriesID: "external", recurrence: .daily(interval: 1))
        event.externalID = "external"; event.sourceTitle = "iCloud"
        XCTAssertNotNil(CalendarRoutineIdentity.event(for: routine, in: [event]))
        var copy = event; copy = AppleCalendarEvent(id: "copy", calendarID: "other", calendarTitle: "업무", title: "독서", start: start, end: event.end, allDay: false, location: "", note: "", url: nil, seriesID: "external", recurrence: .daily(interval: 1))
        copy.externalID = "external"; copy.sourceTitle = "iCloud"
        XCTAssertNil(CalendarRoutineIdentity.event(for: routine, in: [event, copy]))
        event = AppleCalendarEvent(id: "new", calendarID: "new-calendar", calendarTitle: "업무", title: "독서", start: start, end: event.end, allDay: false, location: "", note: "", url: CalendarRoutineIdentity.marker(routine.id), seriesID: "external", recurrence: .daily(interval: 1))
        XCTAssertEqual(CalendarRoutineIdentity.event(for: routine, in: [event, copy])?.id, "new")
    }
}

private actor CalendarCreationFixture: AppleCalendarAccess {
    func requestAccess() -> Bool { true }
    func read(selectedIDs: Set<String>, start: Date, end: Date) -> AppleCalendarSnapshot { AppleCalendarSnapshot(hasAccess: true) }
    func createRoutine(_ request: CalendarRoutineCreation) -> CalendarRoutineLink {
        CalendarRoutineLink(localItemID: "created", externalID: "server-created", calendarID: request.calendarID, calendarTitle: "업무", sourceTitle: "iCloud")
    }
}
private actor CalendarReadOnlyFixture: AppleCalendarAccess {
    func requestAccess() -> Bool { true }
    func read(selectedIDs: Set<String>, start: Date, end: Date) -> AppleCalendarSnapshot { AppleCalendarSnapshot(hasAccess: true) }
}
