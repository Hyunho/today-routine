import Foundation
import EventKit

/// Keep synchronous EventKit queries off the main actor; never expose live EK objects to views.
actor EventKitCalendarAccess: AppleCalendarAccess {
    private let store = EKEventStore()
    func requestAccess() async throws -> Bool { try await store.requestFullAccessToEvents() }
    func read(selectedIDs: Set<String>, start: Date, end: Date) -> AppleCalendarSnapshot {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            return AppleCalendarSnapshot(hasAccess: false)
        }
        let calendars = store.calendars(for: .event)
        let lists = calendars.map { AppleCalendarList(id: $0.calendarIdentifier, title: $0.title, source: $0.source.title, writable: $0.allowsContentModifications) }
            .sorted { ($0.source, $0.title, $0.id) < ($1.source, $1.title, $1.id) }
        let selected = calendars.filter { selectedIDs.contains($0.calendarIdentifier) }
        // An empty selection must not become a nil predicate, which reads all calendars.
        guard !selected.isEmpty else { return AppleCalendarSnapshot(hasAccess: true, calendars: lists) }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: selected)
        let events = store.events(matching: predicate).map(snapshot)
            .sorted { ($0.allDay ? 0 : 1, $0.start, $0.title, $0.id) < ($1.allDay ? 0 : 1, $1.start, $1.title, $1.id) }
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return AppleCalendarSnapshot(hasAccess: false) }
        return AppleCalendarSnapshot(hasAccess: true, calendars: lists, events: events)
    }
    private func snapshot(_ event: EKEvent) -> AppleCalendarEvent {
            let recurrence = event.recurrenceRules?.first.map { rule -> AppleCalendarRecurrence in
                switch rule.frequency {
                case .daily: return .daily(interval: rule.interval)
                case .weekly: return .weekly(interval: rule.interval)
                case .monthly: return .monthly(interval: rule.interval)
                case .yearly: return .yearly(interval: rule.interval)
                default: return .other
                }
            }
            return AppleCalendarEvent(id: event.calendarItemIdentifier + ":" + String(event.startDate.timeIntervalSince1970),
                calendarID: event.calendar.calendarIdentifier, calendarTitle: event.calendar.title,
                title: event.title ?? "제목 없음", start: event.startDate, end: event.endDate,
                allDay: event.isAllDay, location: event.location ?? "", note: event.notes ?? "", url: event.url,
                colorComponents: event.calendar.cgColor?.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)?.components?.map { Double($0) } ?? [],
                seriesID: event.hasRecurrenceRules || event.isDetached ? (event.calendarItemExternalIdentifier ?? event.calendarItemIdentifier) : nil,
                recurrence: recurrence, recurrenceDescription: recurrence.map { pattern in
                    let names = ["", "일", "월", "화", "수", "목", "금", "토"]
                    let days = event.recurrenceRules?.first?.daysOfTheWeek?.map { names[$0.dayOfTheWeek.rawValue] } ?? []
                    return pattern.label + (days.isEmpty ? "" : " · " + days.joined(separator: "·"))
                } ?? "", occurrenceDate: event.occurrenceDate, localItemID: event.calendarItemIdentifier,
                externalID: event.calendarItemExternalIdentifier, sourceTitle: event.calendar.source.title)
    }
    private func link(_ event: EKEvent) -> CalendarRoutineLink {
        CalendarRoutineLink(localItemID: event.calendarItemIdentifier, externalID: event.calendarItemExternalIdentifier,
                            calendarID: event.calendar.calendarIdentifier, calendarTitle: event.calendar.title, sourceTitle: event.calendar.source.title)
    }
    func createRoutine(_ request: CalendarRoutineCreation) throws -> CalendarRoutineLink {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { throw StoreError.invalid("캘린더 접근 권한을 허용해 주세요.") }
        guard let calendar = store.calendar(withIdentifier: request.calendarID), calendar.allowsContentModifications else { throw StoreError.invalid("일정을 추가할 수 있는 캘린더를 선택해 주세요.") }
        let marker = CalendarRoutineIdentity.marker(request.routineID)
        let searchEnd = Calendar.current.date(byAdding: .year, value: 1, to: request.start)!
        let predicate = store.predicateForEvents(withStart: request.start.addingTimeInterval(-86400), end: searchEnd, calendars: [calendar])
        let existing = store.events(matching: predicate).filter { $0.url == marker }
        let ids = Set(existing.map(\.calendarItemIdentifier))
        guard ids.count <= 1 else { throw StoreError.invalid("같은 루틴에 연결된 일정이 여러 개입니다. Apple 캘린더에서 확인해 주세요.") }
        if let event = existing.first { return link(event) }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar; event.title = request.title
        event.startDate = request.start; event.endDate = request.end; event.isAllDay = request.allDay
        event.timeZone = request.allDay ? nil : RoutineRules.calendar.timeZone
        event.url = marker
        if request.weekdays.isEmpty {
            event.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil))
        } else {
            let days = request.weekdays.compactMap { EKWeekday(rawValue: $0).map { EKRecurrenceDayOfWeek($0) } }
            event.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, daysOfTheWeek: days,
                daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: nil))
        }
        try store.save(event, span: .futureEvents, commit: true)
        return link(event)
    }
    func connection(link: CalendarRoutineLink, routineID: UUID) -> CalendarRoutineConnection {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return .noAccess }
        if let event = store.calendarItem(withIdentifier: link.localItemID) as? EKEvent,
           event.calendar.calendarIdentifier == link.calendarID { return .connected(snapshot(event)) }
        var candidates = link.externalID.map { store.calendarItems(withExternalIdentifier: $0).compactMap { $0 as? EKEvent } } ?? []
        if candidates.isEmpty {
            let calendars = store.calendars(for: .event).filter { $0.title == link.calendarTitle && $0.source.title == link.sourceTitle }
            guard !calendars.isEmpty else { return .missing }
            let start = Calendar.current.date(byAdding: .year, value: -1, to: Date())!
            let end = Calendar.current.date(byAdding: .year, value: 2, to: Date())!
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
            candidates = store.events(matching: predicate).filter { $0.url == CalendarRoutineIdentity.marker(routineID) }
        }
        let marked = candidates.filter { $0.url == CalendarRoutineIdentity.marker(routineID) }
        let scoped = marked.isEmpty ? candidates.filter { $0.calendar.title == link.calendarTitle && $0.calendar.source.title == link.sourceTitle } : marked
        let unique = Dictionary(grouping: scoped, by: { $0.calendar.calendarIdentifier + "/" + $0.calendarItemIdentifier })
        guard unique.count <= 1 else { return .ambiguous }
        guard let event = scoped.first else { return .missing }
        return .connected(snapshot(event))
    }
}
