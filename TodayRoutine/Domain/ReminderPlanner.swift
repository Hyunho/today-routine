import Foundation
struct ReminderRequest: Identifiable, Equatable { var id: String; var title: String; var fireDate: Date }
enum ReminderPlanner {
    static func requests(snapshot: StoreSnapshot, now: Date, defaults: ReminderDefaults = ReminderDefaults()) -> [ReminderRequest] {
        let calendar = RoutineRules.calendar, start = calendar.startOfDay(for: now)
        var result: [ReminderRequest] = []
        for offset in 0...7 {
            let day = calendar.date(byAdding: .day, value: offset, to: start)!, key = RoutineRules.dayKey(calendar.date(byAdding: .day, value: offset, to: start)!)
            for r in snapshot.routines where RoutineRules.isScheduled(r, on: day) {
                let preference = snapshot.reminders.first { $0.routineID == r.id }
                let minute: Int
                let lead: Int
                if let preference {
                    guard preference.enabled, (0..<1440).contains(preference.minute) else { continue }
                    minute = snapshot.records.first { $0.routineID == r.id && $0.dayKey == key }?.minuteOverride ?? preference.minute
                    lead = 0
                } else {
                    guard defaults.enabled, let scheduled = RoutineRules.minute(r, records: snapshot.records, on: day) else { continue }
                    minute = scheduled; lead = defaults.leadMinutes
                }
                if snapshot.records.contains(where: { $0.routineID == r.id && $0.dayKey == key && $0.status != .pending }) { continue }
                let fireDate = calendar.date(byAdding: .minute, value: minute - lead, to: day)!
                guard fireDate > now, fireDate < calendar.date(byAdding: .day, value: 7, to: start)!, !defaults.suppresses(fireDate) else { continue }
                result.append(ReminderRequest(id: "routine/\(r.id.uuidString)/\(key)", title: r.name, fireDate: fireDate))
            }
        }
        return Array(result.sorted { $0.fireDate == $1.fireDate ? $0.id < $1.id : $0.fireDate < $1.fireDate }.prefix(60))
    }
}
