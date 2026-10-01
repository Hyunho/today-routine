import Foundation
struct ReminderRequest: Identifiable, Equatable { var id: String; var title: String; var fireDate: Date }
enum ReminderPlanner {
    static func requests(snapshot: StoreSnapshot, now: Date) -> [ReminderRequest] {
        let calendar = RoutineRules.calendar, start = calendar.startOfDay(for: now)
        var result: [ReminderRequest] = []
        for offset in 0..<7 {
            let day = calendar.date(byAdding: .day, value: offset, to: start)!, key = RoutineRules.dayKey(calendar.date(byAdding: .day, value: offset, to: start)!)
            for r in snapshot.routines where RoutineRules.isScheduled(r, on: day) {
                guard let p = snapshot.reminders.first(where: { $0.routineID == r.id && $0.enabled }), (0..<1440).contains(p.minute) else { continue }
                if snapshot.records.contains(where: { $0.routineID == r.id && $0.dayKey == key && $0.status != .pending }) { continue }
                let fireDate = calendar.date(byAdding: .minute, value: p.minute, to: day)!
                guard fireDate > now else { continue }
                result.append(ReminderRequest(id: "routine/\(r.id.uuidString)/\(key)", title: r.name, fireDate: fireDate))
            }
        }
        return Array(result.sorted { $0.fireDate == $1.fireDate ? $0.id < $1.id : $0.fireDate < $1.fireDate }.prefix(60))
    }
}
