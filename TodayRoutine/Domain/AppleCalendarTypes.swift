import Foundation

struct AppleCalendarList: Identifiable, Sendable {
    let id: String
    let title: String
    let source: String
    var writable: Bool = false
}
enum CalendarRoutineFrequency: String, CaseIterable, Codable, Sendable {
    case weekly, monthly, yearly
    var label: String { switch self { case .weekly: "주간"; case .monthly: "월간"; case .yearly: "연간" } }
    var detail: String { switch self { case .weekly: "주 1회 이상"; case .monthly: "주 1회 미만 · 월 1회 이상"; case .yearly: "월 1회 미만 · 연 1회 이상" } }
}
enum AppleCalendarRecurrence: Sendable, Equatable {
    case daily(interval: Int)
    case weekly(interval: Int)
    case monthly(interval: Int)
    case yearly(interval: Int)
    case other

    var frequency: CalendarRoutineFrequency? {
        switch self {
        case .daily(let n): return n < 1 ? nil : n <= 7 ? .weekly : n <= 31 ? .monthly : n <= 366 ? .yearly : nil
        case .weekly(let n): return n < 1 ? nil : n == 1 ? .weekly : n <= 4 ? .monthly : n <= 52 ? .yearly : nil
        case .monthly(let n): return n < 1 ? nil : n == 1 ? .monthly : n <= 12 ? .yearly : nil
        case .yearly(let n): return n == 1 ? .yearly : nil
        case .other: return nil
        }
    }
    var label: String {
        switch self {
        case .daily(let n): return n == 1 ? "매일" : "\(n)일마다"
        case .weekly(let n): return n == 1 ? "매주" : "\(n)주마다"
        case .monthly(let n): return n == 1 ? "매월" : "\(n)개월마다"
        case .yearly(let n): return n == 1 ? "매년" : "\(n)년마다"
        case .other: return "사용자 지정 반복"
        }
    }
}
struct AppleCalendarEvent: Identifiable, Sendable {
    let id: String
    let calendarID: String
    let calendarTitle: String
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
    let location: String
    let note: String
    let url: URL?
    var colorComponents: [Double] = []
    var seriesID: String? = nil
    var recurrence: AppleCalendarRecurrence? = nil
    var recurrenceDescription: String = ""
    var routineFrequency: CalendarRoutineFrequency? = nil
    var occurrenceDate: Date? = nil
    var localItemID: String = ""
    var externalID: String? = nil
    var sourceTitle: String = ""
}
struct AppleCalendarSnapshot: Sendable {
    var hasAccess: Bool
    var calendars: [AppleCalendarList] = []
    var events: [AppleCalendarEvent] = []
}
protocol AppleCalendarAccess: Sendable {
    func requestAccess() async throws -> Bool
    func read(selectedIDs: Set<String>, start: Date, end: Date) async -> AppleCalendarSnapshot
    func createRoutine(_ request: CalendarRoutineCreation) async throws -> CalendarRoutineLink
    func connection(link: CalendarRoutineLink, routineID: UUID) async -> CalendarRoutineConnection
}
extension AppleCalendarAccess {
    func createRoutine(_ request: CalendarRoutineCreation) async throws -> CalendarRoutineLink { throw StoreError.invalid("캘린더 일정 생성이 지원되지 않습니다.") }
    func connection(link: CalendarRoutineLink, routineID: UUID) async -> CalendarRoutineConnection { .missing }
}

extension AppleCalendarEvent {
    func timelineMinutes(on date: Date, calendar: Calendar) -> (start: Int, end: Int)? {
        guard !allDay else { return nil }
        let day = calendar.startOfDay(for: date)
        let next = calendar.date(byAdding: .day, value: 1, to: day)!
        guard start < next, end > day || (start == end && start >= day) else { return nil }
        func minute(_ value: Date) -> Int {
            if value <= day { return 0 }
            if value >= next { return 1440 }
            return calendar.component(.hour, from: value) * 60 + calendar.component(.minute, from: value)
        }
        let from = minute(start)
        return (from, min(1440, max(from + 25 * (start == end ? 1 : 0), minute(end))))
    }
}
