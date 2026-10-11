import XCTest
@testable import RoutineCore

@MainActor final class AppleCalendarTests: XCTestCase {
    func testMonthQueryUsesWholeMonthWithoutChangingSelectedDay() async {
        let client = CalendarFixture()
        let model = AppleCalendarModel(client: client, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        model.date = Date(timeIntervalSince1970: 1791331200)
        await model.select("work", enabled: true)
        let selected = model.date
        let originalEvents = model.events.map(\.id)
        _ = await model.events(inMonth: selected)
        let range = await client.range
        let expected = Calendar.current.dateInterval(of: .month, for: selected)!
        XCTAssertEqual(range?.0, expected.start)
        XCTAssertEqual(range?.1, expected.end)
        XCTAssertEqual(model.date, selected)
        XCTAssertEqual(model.events.map(\.id), originalEvents)
    }
    func testCompletionPersistsAndDoesNotCompleteAnotherOccurrence() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let model = AppleCalendarModel(client: CalendarFixture(), defaults: defaults)
        await model.select("work", enabled: true)
        let event = model.events[0]
        model.setCompleted(event, completed: true)
        let restored = AppleCalendarModel(client: CalendarFixture(), defaults: defaults)
        XCTAssertTrue(restored.isCompleted(event))
        let next = AppleCalendarEvent(id: event.id + "next-occurrence", calendarID: event.calendarID, calendarTitle: event.calendarTitle, title: event.title, start: event.start.addingTimeInterval(86400), end: event.end.addingTimeInterval(86400), allDay: true, location: "", note: "", url: nil)
        XCTAssertFalse(restored.isCompleted(next))
        restored.setCompleted(event, completed: false)
        let reopened = AppleCalendarModel(client: CalendarFixture(), defaults: defaults)
        XCTAssertFalse(reopened.isCompleted(event))
    }
    func testCalendarTimelineBoundsAndOverlaps() {
        let calendar = RoutineRules.calendar
        let day = calendar.startOfDay(for: Date())
        func event(_ start: Int, _ end: Int, allDay: Bool = false) -> AppleCalendarEvent {
            AppleCalendarEvent(id: "calendar", calendarID: "work", calendarTitle: "업무", title: "회의", start: day.addingTimeInterval(Double(start * 60)), end: day.addingTimeInterval(Double(end * 60)), allDay: allDay, location: "", note: "", url: nil)
        }
        let overnight = event(-60, 600).timelineMinutes(on: day, calendar: calendar)!
        XCTAssertEqual(overnight.start, 0)
        XCTAssertEqual(overnight.end, 600)
        let zero = event(600, 600).timelineMinutes(on: day, calendar: calendar)!
        XCTAssertEqual(zero.end, 625)
        XCTAssertNil(event(0, 1440, allDay: true).timelineMinutes(on: day, calendar: calendar))
        XCTAssertNil(event(-60, 0).timelineMinutes(on: day, calendar: calendar))
        let placements = TimelineLayout.place([TimelineInterval(id: "routine", start: 600, end: 625), TimelineInterval(id: "calendar", start: zero.start, end: zero.end)])
        XCTAssertEqual(placements.count, 2)
        XCTAssertTrue(placements.allSatisfy { $0.columns == 2 })
        XCTAssertNotEqual(placements[0].column, placements[1].column)
    }
    func testSelectionAndDisconnectDoNotReadEveryCalendar() async {
        let client = CalendarFixture()
        let model = AppleCalendarModel(client: client, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await model.refresh()
        XCTAssertTrue(model.events.isEmpty)
        await model.select("work", enabled: true)
        XCTAssertEqual(model.events.map(\.title), ["회의"])
        model.disconnect()
        await model.refresh()
        XCTAssertTrue(model.events.isEmpty)
        XCTAssertTrue(model.selectedIDs.isEmpty)
    }
    func testTodayQueryDoesNotChangeCalendarTabDateOrEvents() async {
        let client = CalendarFixture()
        let model = AppleCalendarModel(client: client, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        model.date = Date(timeIntervalSince1970: 1791331200)
        await model.select("work", enabled: true)
        let originalDate = model.date
        let originalStart = model.events.first?.start
        let today = originalDate.addingTimeInterval(86400 * 3)
        let events = await model.events(on: today, calendar: RoutineRules.calendar)
        XCTAssertEqual(events.first?.start, RoutineRules.calendar.startOfDay(for: today))
        XCTAssertEqual(model.date, originalDate)
        XCTAssertEqual(model.events.first?.start, originalStart)
        model.disconnect()
        let empty = await model.events(on: today, calendar: RoutineRules.calendar)
        XCTAssertTrue(empty.isEmpty)
    }
    func testConnectRefreshesCalendarChoicesAndClearsOldError() async {
        let model = AppleCalendarModel(client: CalendarFixture(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        model.error = "previous permission error"
        await model.connect()
        XCTAssertTrue(model.hasAccess)
        XCTAssertEqual(model.calendars.map(\.id), ["work"])
        XCTAssertNil(model.error)
        XCTAssertFalse(model.isConnecting)
    }
    func testRevokedPermissionClearsData() async {
        let client = CalendarFixture()
        let model = AppleCalendarModel(client: client, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await model.select("work", enabled: true)
        await client.revoke()
        await model.refresh()
        XCTAssertFalse(model.hasAccess)
        XCTAssertTrue(model.events.isEmpty)
        XCTAssertTrue(model.calendars.isEmpty)
    }
    func testDateSelectionQueriesOneDayAndSelectionPersists() async {
        let client = CalendarFixture()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let model = AppleCalendarModel(client: client, defaults: defaults)
        model.date = Date(timeIntervalSince1970: 1791331200)
        await model.select("work", enabled: true)
        let range = await client.range
        XCTAssertEqual(range?.0, Calendar.current.startOfDay(for: model.date))
        XCTAssertEqual(range?.1, Calendar.current.date(byAdding: .day, value: 1, to: range!.0))
        let restored = AppleCalendarModel(client: client, defaults: defaults)
        XCTAssertEqual(restored.selectedIDs, ["work"])
    }
    func testRecurringEventsShowOnlyNextOccurrenceOfEachSelectedSeries() async {
        let now = Date(timeIntervalSince1970: 1791417600)
        func event(_ id: String, series: String?, daysAhead: Int, calendarID: String = "work") -> AppleCalendarEvent {
            let start = now.addingTimeInterval(Double(daysAhead) * 86400)
            return AppleCalendarEvent(id: id, calendarID: calendarID, calendarTitle: "업무", title: id,
                                      start: start, end: start.addingTimeInterval(3600), allDay: false,
                                      location: "", note: "", url: nil, seriesID: series,
                                      recurrence: series == nil ? nil : .weekly(interval: 1))
        }
        let client = CalendarFixture(events: [
            event("late", series: "weekly", daysAhead: 8),
            event("other", series: "monthly", daysAhead: 2),
            event("early", series: "weekly", daysAhead: 1),
            event("one-off", series: nil, daysAhead: 1),
            event("unselected", series: "outside", daysAhead: 1, calendarID: "personal")
        ])
        let model = AppleCalendarModel(client: client, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await model.select("work", enabled: true)

        let events = await model.recurringEvents(from: now)

        XCTAssertEqual(events.map(\.id), ["early", "other"])
        let range = await client.range
        XCTAssertEqual(range?.0, now)
        XCTAssertEqual(range?.1, Calendar.current.date(byAdding: .year, value: 2, to: now))
    }
    func testYearlyClusterIsNotMistakenForWeeklyAndDenseYearlyRuleIsMonthly() async {
        let now = RoutineRules.date(for: "2026-01-01")!
        func event(_ id: String, series: String, day: String) -> AppleCalendarEvent {
            let start = RoutineRules.date(for: day)!
            return AppleCalendarEvent(id: id, calendarID: "work", calendarTitle: "업무", title: series,
                start: start, end: start.addingTimeInterval(3600), allDay: false, location: "", note: "", url: nil,
                seriesID: series, recurrence: .yearly(interval: 1))
        }
        let cluster = ["2026-03-01", "2026-03-02", "2026-03-03", "2027-03-01", "2027-03-02", "2027-03-03"].map { event($0, series: "cluster", day: $0) }
        let monthly = (0..<24).map { offset in
            let date = RoutineRules.calendar.date(byAdding: .month, value: offset, to: now)!
            return event("month-\(offset)", series: "monthly", day: RoutineRules.dayKey(date))
        }
        let model = AppleCalendarModel(client: CalendarFixture(events: cluster + monthly), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await model.select("work", enabled: true)
        let result = await model.recurringEvents(from: now)
        XCTAssertEqual(result.first { $0.seriesID == "cluster" }?.routineFrequency, .yearly)
        XCTAssertEqual(result.first { $0.seriesID == "monthly" }?.routineFrequency, .monthly)
    }
    func testRecurringEventsUseFrequencyGroupsAndPersistDisplaySelection() async {
        let now = Date(timeIntervalSince1970: 1791417600)
        func event(_ id: String, recurrence: AppleCalendarRecurrence) -> AppleCalendarEvent {
            let start = now.addingTimeInterval(86400)
            return AppleCalendarEvent(id: id, calendarID: "work", calendarTitle: "업무", title: id,
                                      start: start, end: start.addingTimeInterval(3600), allDay: false,
                                      location: "", note: "", url: nil, seriesID: id, recurrence: recurrence)
        }
        let client = CalendarFixture(events: [
            event("daily-7", recurrence: .daily(interval: 7)),
            event("daily-8", recurrence: .daily(interval: 8)),
            event("weekly-1", recurrence: .weekly(interval: 1)),
            event("weekly-2", recurrence: .weekly(interval: 2)),
            event("monthly", recurrence: .monthly(interval: 1)),
            event("quarterly", recurrence: .monthly(interval: 3)),
            event("yearly", recurrence: .yearly(interval: 1)),
            event("biennial", recurrence: .yearly(interval: 2))
        ])
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let model = AppleCalendarModel(client: client, defaults: defaults)
        await model.select("work", enabled: true)

        let events = await model.recurringEvents(from: now)

        XCTAssertEqual(events.filter { $0.routineFrequency == .weekly }.map(\.id), ["daily-7", "weekly-1"])
        XCTAssertEqual(events.filter { $0.routineFrequency == .monthly }.map(\.id), ["daily-8", "monthly", "weekly-2"])
        XCTAssertEqual(events.filter { $0.routineFrequency == .yearly }.map(\.id), ["quarterly", "yearly"])
        model.setFrequency(.monthly, visible: false)
        let restored = AppleCalendarModel(client: client, defaults: defaults)
        XCTAssertFalse(restored.visibleFrequencies.contains(.monthly))
        XCTAssertTrue(restored.visibleFrequencies.contains(.weekly))
        XCTAssertTrue(restored.visibleFrequencies.contains(.yearly))
    }
}
private actor CalendarFixture: AppleCalendarAccess {
    var permitted = true
    var range: (Date, Date)?
    let suppliedEvents: [AppleCalendarEvent]?
    init(events: [AppleCalendarEvent]? = nil) { suppliedEvents = events }
    func revoke() { permitted = false }
    func requestAccess() -> Bool { permitted }
    func read(selectedIDs: Set<String>, start: Date, end: Date) -> AppleCalendarSnapshot {
        range = (start, end)
        guard permitted else { return AppleCalendarSnapshot(hasAccess: false) }
        let event = AppleCalendarEvent(id: "event", calendarID: "work", calendarTitle: "업무", title: "회의", start: start, end: end, allDay: true, location: "", note: "", url: nil)
        return AppleCalendarSnapshot(hasAccess: true, calendars: [AppleCalendarList(id: "work", title: "업무", source: "iCloud")], events: suppliedEvents ?? (selectedIDs.contains("work") ? [event] : []))
    }
}
