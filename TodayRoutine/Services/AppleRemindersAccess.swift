import Foundation
import EventKit

@MainActor protocol AppleRemindersAccess {
    var hasAccess: Bool { get }
    func requestAccess() async throws -> Bool
    func lists() -> [AppleReminderList]
    func fetch(listIDs: Set<String>) async throws -> [AppleReminderItem]
    func save(_ draft: AppleReminderDraft) throws
    func complete(_ item: AppleReminderItem) throws
}

@MainActor final class EventKitRemindersAccess: AppleRemindersAccess {
    private let store = EKEventStore()
    var hasAccess: Bool { EKEventStore.authorizationStatus(for: .reminder) == .fullAccess }
    func requestAccess() async throws -> Bool { try await store.requestFullAccessToReminders() }
    func lists() -> [AppleReminderList] {
        guard hasAccess else { return [] }
        return store.calendars(for: .reminder).map {
            AppleReminderList(id: $0.calendarIdentifier, title: $0.title, source: $0.source.title, writable: $0.allowsContentModifications)
        }.sorted { ($0.source, $0.title, $0.id) < ($1.source, $1.title, $1.id) }
    }
    func fetch(listIDs: Set<String>) async throws -> [AppleReminderItem] {
        guard hasAccess else { throw AppleRemindersError.noAccess }
        let calendars = store.calendars(for: .reminder).filter { listIDs.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return [] } // A nil calendar predicate would read every list.
        let predicate = store.predicateForReminders(in: calendars)
        let reminders: [EKReminder]? = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { continuation.resume(returning: $0) }
        }
        guard hasAccess else { throw AppleRemindersError.noAccess }
        guard let reminders else { throw AppleRemindersError.unavailable }
        return reminders.map(Self.item)
    }
    private static func item(_ r: EKReminder) -> AppleReminderItem {
        AppleReminderItem(id: r.calendarItemIdentifier, listID: r.calendar.calendarIdentifier, listTitle: r.calendar.title,
                          title: r.title ?? "제목 없음", note: r.notes ?? "", due: r.dueDateComponents,
                          completed: r.isCompleted, modified: r.lastModifiedDate, writable: r.calendar.allowsContentModifications)
    }
    private func original(_ item: AppleReminderItem) throws -> EKReminder {
        guard hasAccess else { throw AppleRemindersError.noAccess }
        guard let reminder = store.calendarItem(withIdentifier: item.id) as? EKReminder else { throw AppleRemindersError.unavailable }
        guard reminder.refresh() else { throw AppleRemindersError.unavailable }
        guard reminder.calendar.allowsContentModifications else { throw AppleRemindersError.readOnly }
        guard Self.item(reminder) == item else { throw AppleRemindersError.changed }
        return reminder
    }
    func save(_ draft: AppleReminderDraft) throws {
        guard hasAccess else { throw AppleRemindersError.noAccess }
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw AppleRemindersError.emptyTitle }
        let reminder: EKReminder
        if let baseline = draft.original {
            reminder = try original(baseline)
        } else {
            guard let calendar = store.calendar(withIdentifier: draft.listID), calendar.allowedEntityTypes.contains(.reminder) else { throw AppleRemindersError.unavailable }
            guard calendar.allowsContentModifications else { throw AppleRemindersError.readOnly }
            reminder = EKReminder(eventStore: store); reminder.calendar = calendar
        }
        try Self.apply(draft, to: reminder)
        do { try store.save(reminder, commit: true) }
        catch { _ = reminder.refresh(); throw error }
    }
    static func apply(_ draft: AppleReminderDraft, to reminder: EKReminder) throws {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw AppleRemindersError.emptyTitle }
        // Patch only edited fields; retain recurrence, alarms, priority, URL, and original time zone.
        if draft.original == nil || title != draft.original?.title { reminder.title = title }
        if draft.original == nil || draft.note != draft.original?.note { reminder.notes = draft.note }
        if draft.original == nil || draft.dayKey != draft.original?.dayKey || draft.minute != draft.original?.minute {
            reminder.dueDateComponents = AppleReminderDate.components(dayKey: draft.dayKey, minute: draft.minute)
        }
    }
    func complete(_ item: AppleReminderItem) throws {
        let reminder = try original(item)
        reminder.isCompleted = !item.completed
        do { try store.save(reminder, commit: true) }
        catch { _ = reminder.refresh(); throw error }
    }
}
