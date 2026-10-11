#if DEBUG
import Foundation

// A persistent, isolated source for UI tests. Never reads or writes the user's EventKit store.
@MainActor final class AppleRemindersFixture: AppleRemindersAccess {
    private let url: URL
    var hasAccess: Bool
    private var records: [AppleReminderItem]
    init(id: String, denied: Bool) {
        url = URL.applicationSupportDirectory.appendingPathComponent("UITest-\(id).apple-reminders.json")
        hasAccess = !denied
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode([AppleReminderItem].self, from: data) { records = saved }
        else {
            let today = RoutineRules.dayKey(Date())
            let tomorrow = RoutineRules.dayKey(RoutineRules.calendar.date(byAdding: .day, value: 1, to: Date())!)
            records = [
                AppleReminderItem(id: "today", listID: "work", listTitle: "업무 테스트", title: "오늘 마감 확인", due: AppleReminderDate.components(dayKey: today, minute: nil)),
                AppleReminderItem(id: "tomorrow", listID: "work", listTitle: "업무 테스트", title: "내일 마감 확인", due: AppleReminderDate.components(dayKey: tomorrow, minute: 540)),
                AppleReminderItem(id: "other", listID: "other", listTitle: "개인 테스트", title: "다른 목록 항목"),
                AppleReminderItem(id: "readonly", listID: "readonly", listTitle: "읽기 전용 테스트", title: "공유 참고 항목", writable: false)
            ]
        }
    }
    func requestAccess() async throws -> Bool { hasAccess }
    func lists() -> [AppleReminderList] {
        [.init(id: "work", title: "업무 테스트", source: "테스트 계정", writable: true), .init(id: "other", title: "개인 테스트", source: "테스트 계정", writable: true), .init(id: "readonly", title: "읽기 전용 테스트", source: "테스트 계정", writable: false)]
    }
    func fetch(listIDs: Set<String>) async throws -> [AppleReminderItem] { records.filter { listIDs.contains($0.listID) } }
    func save(_ draft: AppleReminderDraft) throws {
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppleRemindersError.emptyTitle }
        if let original = draft.original, let index = records.firstIndex(where: { $0.id == original.id }) {
            records[index].title = draft.title; records[index].note = draft.note
            records[index].due = AppleReminderDate.components(dayKey: draft.dayKey, minute: draft.minute)
        } else {
            records.append(AppleReminderItem(id: UUID().uuidString, listID: draft.listID, listTitle: lists().first { $0.id == draft.listID }!.title, title: draft.title, note: draft.note, due: AppleReminderDate.components(dayKey: draft.dayKey, minute: draft.minute)))
        }
        try persist()
    }
    func complete(_ item: AppleReminderItem) throws {
        if let index = records.firstIndex(where: { $0.id == item.id }) { records[index].completed.toggle() }
        try persist()
    }
    private func persist() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(records).write(to: url, options: .atomic)
    }
}
#endif
