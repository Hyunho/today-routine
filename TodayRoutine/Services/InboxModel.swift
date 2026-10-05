import Foundation
import Observation

@MainActor @Observable final class InboxModel {
    private let store: InboxStore
    private let client: any FeedFetching
    private(set) var state: InboxState
    private(set) var isRefreshing = false
    var error: String?
    private(set) var feedErrors: [UUID: String] = [:]
    private var active: Set<UUID> = []
    private var attempts: [UUID: Date] = [:]
    init(store: InboxStore, client: any FeedFetching = FeedClient()) {
        self.store = store; self.client = client; state = store.state
    }
    private func change(_ edit: (inout InboxState) throws -> Void) {
        do { try store.transaction(edit); state = store.state }
        catch { self.error = error.localizedDescription }
    }
    static func normalized(_ url: URL) throws -> URL {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: true), parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil else { throw InboxError.invalid("HTTPS 피드 주소를 입력해 주세요.") }
        parts.scheme = "https"; parts.host = host.lowercased(); parts.fragment = nil
        if parts.port == 443 { parts.port = nil }
        if parts.path.isEmpty { parts.path = "/" }
        guard let result = parts.url else { throw InboxError.invalid("주소를 확인해 주세요.") }
        return result
    }
    func addSubscription(_ url: URL) async {
        do {
            let url = try Self.normalized(url)
            guard !state.subscriptions.contains(where: { (try? Self.normalized($0.url)) == url }) else { throw InboxError.invalid("이미 구독 중인 주소입니다.") }
            let feed = InboxSubscription(url: url, title: url.host ?? "새 구독")
            try store.transaction { $0.subscriptions.append(feed) }; state = store.state
            error = nil
            await refreshFeed(feed, now: Date())
        } catch { self.error = error.localizedDescription }
    }
    func removeSubscription(_ id: UUID) {
        do { try store.removeSubscription(id); state = store.state; feedErrors[id] = nil; attempts[id] = nil }
        catch { self.error = error.localizedDescription }
    }
    func refresh(now: Date = Date(), force: Bool = false) async {
        for feed in state.subscriptions {
            guard !Task.isCancelled else { return }
            let last = attempts[feed.id] ?? feed.lastRefreshAt
            if !force, let last, now.timeIntervalSince(last) < 900 { continue }
            await refreshFeed(feed, now: now)
        }
    }
    private func refreshFeed(_ feed: InboxSubscription, now: Date) async {
        guard state.subscriptions.contains(where: { $0.id == feed.id }), active.insert(feed.id).inserted else { return }
        attempts[feed.id] = now; isRefreshing = true
        defer { active.remove(feed.id); isRefreshing = !active.isEmpty }
        do {
            let parsed = try await client.fetch(feed.url)
            try Task.checkCancellation()
            guard state.subscriptions.contains(where: { $0.id == feed.id }) else { return }
            try store.transaction { s in
                guard let index = s.subscriptions.firstIndex(where: { $0.id == feed.id }) else { return }
                let title = parsed.title.isEmpty ? feed.title : parsed.title
                s.subscriptions[index].title = title; s.subscriptions[index].lastRefreshAt = now
                var map = Dictionary(uniqueKeysWithValues: s.items.map { ($0.id, $0) })
                for entry in parsed.entries {
                    let id = "feed/\(feed.id.uuidString)/\(entry.identity)"
                    let old = map[id]
                    map[id] = InboxItem(id: id, kind: .feed, subscriptionID: feed.id, title: entry.title, sourceTitle: title, body: entry.body, link: entry.link, date: entry.publishedAt ?? old?.date ?? now, isRead: old?.isRead ?? false, isSaved: old?.isSaved ?? false)
                }
                s.items = Array(map.values); s.prune(now: now)
            }
            state = store.state; feedErrors[feed.id] = nil
        } catch is CancellationError { attempts[feed.id] = nil }
        catch {
            guard state.subscriptions.contains(where: { $0.id == feed.id }) else { return }
            feedErrors[feed.id] = error.localizedDescription
        }
    }
    func reconcileReminders(_ requests: [ReminderRequest], now: Date = Date()) {
        change { InboxReminderReducer.reconcile(state: &$0, requests: requests, now: now) }
    }
    func setRead(_ id: String) { change { s in if let i = s.items.firstIndex(where: { $0.id == id }) { s.items[i].isRead = true } } }
    func toggleSaved(_ id: String) { change { s in if let i = s.items.firstIndex(where: { $0.id == id }) { s.items[i].isSaved.toggle() } } }
    func savePosition(_ id: String, key: String) { change { if $0.items.contains(where: { $0.id == id }) { $0.positions[key] = id } } }
    func items(filter: InboxFilter, savedOnly: Bool) -> [InboxItem] {
        state.items.filter { item in
            (!savedOnly || item.isSaved) && (filter == .all || (filter == .feeds && item.kind == .feed) || (filter == .reminders && item.kind == .reminder))
        }.sorted(by: InboxState.newestFirst)
    }
}
