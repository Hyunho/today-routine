import Foundation

struct ReminderDefaults: Codable, Equatable {
    var enabled = false
    var leadMinutes = 0
    var quietEnabled = false
    var quietStart = 1320
    var quietEnd = 420

    func suppresses(_ date: Date) -> Bool {
        guard quietEnabled, quietStart != quietEnd else { return false }
        let calendar = RoutineRules.calendar
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        return quietStart < quietEnd ? (quietStart..<quietEnd).contains(minute) : minute >= quietStart || minute < quietEnd
    }
}
