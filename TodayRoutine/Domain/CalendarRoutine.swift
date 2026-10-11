import Foundation

struct CalendarRoutineLink: Codable, Equatable, Sendable {
    var version = 1
    var localItemID: String
    var externalID: String?
    var calendarID: String
    var calendarTitle: String
    var sourceTitle: String
}

struct CalendarRoutineCreation: Sendable {
    let routineID: UUID
    let title: String
    let calendarID: String
    let start: Date
    let end: Date
    let allDay: Bool
    let weekdays: [Int]

    @MainActor init(routine: Routine, calendarID: String, startDay: Date, duration: Int) throws {
        guard routine.calendarLink == nil, routine.repeatKind != .weeklyGoal,
              !calendarID.isEmpty, (1...1440).contains(duration) else { throw StoreError.invalid("반복 방식과 캘린더, 소요 시간을 확인해 주세요.") }
        routineID = routine.id; title = routine.name; self.calendarID = calendarID
        weekdays = routine.repeatKind == .weekdays ? Array(Set(routine.weekdays)).sorted() : []
        guard routine.repeatKind != .weekdays || (!weekdays.isEmpty && weekdays.allSatisfy { (1...7).contains($0) }) else { throw StoreError.invalid("반복할 요일을 선택해 주세요.") }
        let calendar = RoutineRules.calendar
        var day = calendar.startOfDay(for: startDay)
        if !weekdays.isEmpty {
            for _ in 0..<7 {
                if weekdays.contains(calendar.component(.weekday, from: day)) { break }
                day = calendar.date(byAdding: .day, value: 1, to: day)!
            }
        }
        allDay = routine.minute == nil
        start = calendar.date(byAdding: .minute, value: routine.minute ?? 0, to: day)!
        end = allDay ? calendar.date(byAdding: .day, value: 1, to: day)! : calendar.date(byAdding: .minute, value: duration, to: start)!
    }
}

enum CalendarRoutineIdentity {
    static func marker(_ id: UUID) -> URL { URL(string: "todayroutine://routine/" + id.uuidString)! }
    @MainActor static func event(for routine: Routine, in events: [AppleCalendarEvent]) -> AppleCalendarEvent? {
        guard let link = routine.calendarLink else { return nil }
        let marked = events.filter { $0.url == marker(routine.id) }
        let local = events.filter { $0.localItemID == link.localItemID && $0.calendarID == link.calendarID }
        let external = events.filter {
            guard let expected = link.externalID, !expected.isEmpty else { return false }
            return $0.externalID == expected && $0.calendarTitle == link.calendarTitle && $0.sourceTitle == link.sourceTitle
        }
        let candidates = !marked.isEmpty ? marked : !local.isEmpty ? local : external
        let series = Set(candidates.map { $0.calendarID + "\u{1F}" + ($0.seriesID ?? $0.localItemID) })
        guard series.count == 1 else { return nil }
        return candidates.sorted { ($0.start, $0.id) < ($1.start, $1.id) }.first
    }
}

enum CalendarRoutineConnection: Sendable {
    case connected(AppleCalendarEvent)
    case missing
    case noAccess
    case ambiguous
}
