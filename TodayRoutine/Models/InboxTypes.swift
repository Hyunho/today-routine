import Foundation

enum InboxKind: String, Codable, Sendable { case feed, reminder }
enum InboxFilter: String, CaseIterable, Identifiable, Sendable {
    case all, reminders, feeds
    var id: String { rawValue }
    var title: String { switch self { case .all: "전체"; case .reminders: "루틴 알림"; case .feeds: "구독 글" } }
    func positionKey(savedOnly: Bool) -> String { rawValue + (savedOnly ? "/saved" : "/all") }
}
struct InboxSubscription: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var url: URL
    var title: String
    var lastRefreshAt: Date?
}
struct InboxItem: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var kind: InboxKind
    var subscriptionID: UUID?
    var routineID: UUID?
    var dayKey: String?
    var title: String
    var sourceTitle: String
    var body = ""
    var link: URL?
    var date: Date
    var isRead = false
    var isSaved = false
}
struct InboxPendingReminder: Codable, Equatable, Sendable {
    var id: String
    var routineID: UUID
    var dayKey: String
    var title: String
    var fireDate: Date
}
struct InboxState: Codable, Equatable, Sendable {
    var version = 1
    var seeded = false
    var subscriptions: [InboxSubscription] = []
    var items: [InboxItem] = []
    var pendingReminders: [InboxPendingReminder] = []
    var positions: [String: String] = [:]

    mutating func prune(now: Date) {
        var counts: [UUID: Int] = [:]
        items = items.sorted(by: Self.newestFirst).filter { item in
            if item.isSaved { return true }
            if item.kind == .reminder { return item.date >= now.addingTimeInterval(-90 * 86400) }
            guard let feed = item.subscriptionID else { return false }
            counts[feed, default: 0] += 1
            return counts[feed, default: 0] <= 500
        }
        let ids = Set(items.map(\.id))
        positions = positions.filter { ids.contains($0.value) }
    }
    static func newestFirst(_ a: InboxItem, _ b: InboxItem) -> Bool {
        a.date == b.date ? a.id < b.id : a.date > b.date
    }
}
enum InboxError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { switch self { case .invalid(let message): message } }
}
