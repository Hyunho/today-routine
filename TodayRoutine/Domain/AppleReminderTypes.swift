import Foundation

struct AppleReminderList: Identifiable, Equatable {
    var id: String
    var title: String
    var source: String
    var writable: Bool
}
struct AppleReminderItem: Identifiable, Equatable, Codable {
    var id: String
    var listID: String
    var listTitle: String
    var title: String
    var note = ""
    var due: DateComponents?
    var completed = false
    var modified: Date?
    var writable = true
    var dayKey: String? { AppleReminderDate.dayKey(due) }
    var minute: Int? { AppleReminderDate.minute(due) }
}
struct AppleReminderDraft: Identifiable {
    let id = UUID()
    var original: AppleReminderItem?
    var listID: String
    var title = ""
    var note = ""
    var dayKey: String?
    var minute: Int?
    init(listID: String) { self.listID = listID }
    init(_ item: AppleReminderItem) {
        original = item; listID = item.listID; title = item.title; note = item.note
        dayKey = item.dayKey; minute = item.minute
    }
}
enum AppleReminderDate {
    // Date-only reminders retain their calendar day; timed reminders display in the app's calendar.
    private static func display(_ due: DateComponents?) -> DateComponents? {
        guard var due, due.year != nil, due.month != nil, due.day != nil else { return nil }
        guard due.hour != nil else { return due }
        var calendar = due.calendar ?? RoutineRules.calendar
        calendar.timeZone = due.timeZone ?? RoutineRules.calendar.timeZone
        due.calendar = calendar
        guard let date = calendar.date(from: due) else { return nil }
        return RoutineRules.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }
    static func dayKey(_ due: DateComponents?) -> String? {
        guard let d = display(due), let y = d.year, let m = d.month, let day = d.day else { return nil }
        return String(format: "%04d-%02d-%02d", y, m, day)
    }
    static func minute(_ due: DateComponents?) -> Int? {
        guard let d = display(due), let h = d.hour else { return nil }
        return h * 60 + (d.minute ?? 0)
    }
    static func components(dayKey: String?, minute: Int?) -> DateComponents? {
        guard let dayKey, let date = RoutineRules.date(for: dayKey) else { return nil }
        var d = RoutineRules.calendar.dateComponents([.year, .month, .day], from: date)
        if let minute { d.hour = minute / 60; d.minute = minute % 60; d.timeZone = RoutineRules.calendar.timeZone }
        return d
    }
}
enum AppleRemindersError: LocalizedError {
    case noAccess, unavailable, readOnly, changed, emptyTitle
    var errorDescription: String? {
        switch self {
        case .noAccess: return "시스템 설정에서 오늘의 루틴의 미리 알림 접근을 허용해 주세요."
        case .unavailable: return "원본 항목이나 목록을 찾을 수 없습니다. 목록을 새로고침해 주세요."
        case .readOnly: return "이 미리 알림 목록은 읽기 전용입니다."
        case .changed: return "미리 알림에서 원본이 변경되었습니다. 입력 내용은 보존됩니다. 최신 항목을 확인한 뒤 다시 편집해 주세요."
        case .emptyTitle: return "제목을 입력해 주세요."
        }
    }
}
