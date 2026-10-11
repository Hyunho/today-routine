import Foundation
import Observation

@MainActor @Observable final class AppleRemindersModel {
    private let client: any AppleRemindersAccess
    private let defaults: UserDefaults
    private let key = "appleReminders.selectedLists"
    private var generation = 0
    private(set) var selectedIDs: Set<String>
    private(set) var lists: [AppleReminderList] = []
    private(set) var items: [AppleReminderItem] = []
    private(set) var hasAccess = false
    private(set) var loading = false
    var error: String?
    var writableLists: [AppleReminderList] { lists.filter { selectedIDs.contains($0.id) && $0.writable } }
    var unavailableListCount: Int { selectedIDs.subtracting(Set(lists.map(\.id))).count }
    init(client: any AppleRemindersAccess, defaults: UserDefaults = .standard) {
        self.client = client; self.defaults = defaults
        selectedIDs = Set(defaults.stringArray(forKey: key) ?? [])
    }
    func connect() async {
        do {
            guard try await client.requestAccess() else { error = AppleRemindersError.noAccess.localizedDescription; await refresh(); return }
            error = nil; await refresh()
        } catch { self.error = error.localizedDescription }
    }
    func select(_ id: String, enabled: Bool) async {
        if enabled { selectedIDs.insert(id) } else { selectedIDs.remove(id) }
        defaults.set(Array(selectedIDs).sorted(), forKey: key)
        items.removeAll { !selectedIDs.contains($0.listID) }
        await refresh()
    }
    func disconnect() {
        generation += 1; selectedIDs = []; items = []; loading = false; error = nil
        defaults.removeObject(forKey: key)
    }
    func refresh() async {
        generation += 1
        let current = generation
        hasAccess = client.hasAccess
        guard hasAccess else { items = []; lists = []; loading = false; return }
        lists = client.lists()
        let ids = selectedIDs.intersection(Set(lists.map(\.id)))
        items.removeAll { !ids.contains($0.listID) }
        guard !ids.isEmpty else { items = []; loading = false; return }
        loading = true
        do {
            let result = try await client.fetch(listIDs: ids)
            guard current == generation else { return }
            guard client.hasAccess else { hasAccess = false; items = []; lists = []; loading = false; return }
            items = result.filter { ids.contains($0.listID) }.sorted {
                ($0.completed ? 1 : 0, $0.dayKey ?? "9999", $0.minute ?? Int.max, $0.title, $0.id) <
                ($1.completed ? 1 : 0, $1.dayKey ?? "9999", $1.minute ?? Int.max, $1.title, $1.id)
            }
            loading = false
        } catch {
            guard current == generation else { return }
            loading = false; self.error = error.localizedDescription
            if !client.hasAccess { hasAccess = false; items = []; lists = [] }
        }
    }
    func save(_ draft: AppleReminderDraft) async -> Bool {
        do {
            guard selectedIDs.contains(draft.listID) else { throw AppleRemindersError.unavailable }
            try client.save(draft); error = nil; await refresh(); return true
        } catch { self.error = error.localizedDescription; await refresh(); return false }
    }
    func complete(_ item: AppleReminderItem) async -> Bool {
        do {
            guard selectedIDs.contains(item.listID) else { throw AppleRemindersError.unavailable }
            try client.complete(item); error = nil; await refresh(); return true
        } catch { self.error = error.localizedDescription; await refresh(); return false }
    }
    func due(on date: Date) -> [AppleReminderItem] { items.filter { $0.dayKey == RoutineRules.dayKey(date) } }
}
