import Foundation

enum InboxReminderReducer {
    static func reconcile(state: inout InboxState, requests: [ReminderRequest], now: Date) {
        var existing = Set(state.items.map(\.id))
        for pending in state.pendingReminders where pending.fireDate <= now {
            guard existing.insert(pending.id).inserted else { continue }
            state.items.append(InboxItem(id: pending.id, kind: .reminder, routineID: pending.routineID, dayKey: pending.dayKey, title: pending.title, sourceTitle: "오늘의 루틴", body: "루틴을 시작할 시간이에요.\n예정 시각 기준 기록", date: pending.fireDate))
        }
        var pendingIDs: Set<String> = []
        state.pendingReminders = requests.compactMap { request in
            let parts = request.id.split(separator: "/")
            guard request.fireDate > now, !existing.contains(request.id), pendingIDs.insert(request.id).inserted,
                  parts.count == 3, parts[0] == "routine", let id = UUID(uuidString: String(parts[1])) else { return nil }
            return InboxPendingReminder(id: request.id, routineID: id, dayKey: String(parts[2]), title: request.title, fireDate: request.fireDate)
        }
        state.prune(now: now)
    }
}
