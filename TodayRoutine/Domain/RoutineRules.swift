import Foundation
enum RoutineRules {
    static func refreshedSelection(_ selection: Date, previousToday: Date, now: Date) -> Date {
        dayKey(selection) == dayKey(previousToday) ? now : selection
    }
    static func visible(_ routine: Routine, records: [RoutineDayRecord], on date: Date, now: Date) -> Bool {
        if dayKey(date) < dayKey(now), records.contains(where: { $0.routineID == routine.id && $0.dayKey == dayKey(date) }) { return true }
        return isScheduled(routine, on: date) || (routine.status == .active && routine.repeatKind == .weeklyGoal)
    }
    static var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Seoul")!; c.firstWeekday = 2; return c }
    static func dayKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year,.month,.day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!,c.month!,c.day!)
    }
    static func date(for key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }; guard parts.count == 3 else { return nil }
        guard let d = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])), dayKey(d) == key else { return nil }; return d
    }
    static func weekStart(_ date: Date) -> Date {
        let day = calendar.startOfDay(for: date), offset = (calendar.component(.weekday, from: date) + 5) % 7
        return calendar.date(byAdding: .day, value: -offset, to: day)!
    }
    static func isScheduled(_ routine: Routine, on date: Date) -> Bool {
        guard routine.status == .active else { return false }
        switch routine.repeatKind { case .daily: return true; case .weekdays: return routine.weekdays.contains(calendar.component(.weekday, from: date)); case .weeklyGoal: return false }
    }
    static func timeSorted(_ routines: [Routine]) -> [Routine] {
        routines.sorted {
            let a = $0.minute ?? Int.max, b = $1.minute ?? Int.max
            if a != b { return a < b }; if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }; return $0.id.uuidString < $1.id.uuidString
        }
    }
    static func completedCount(routineID: UUID, records: [RoutineDayRecord], week: Date) -> Int {
        let start = dayKey(weekStart(week)), end = dayKey(calendar.date(byAdding: .day, value: 7, to: weekStart(week))!)
        return Set(records.filter { $0.routineID == routineID && $0.status == .completed && $0.dayKey >= start && $0.dayKey < end }.map(\.dayKey)).count
    }
    static func timeLabel(_ minute: Int?) -> String { guard let minute else { return "시간 미정" }; return String(format: "%02d:%02d", minute / 60, minute % 60) }
}
