import Foundation

@MainActor final class InboxStore {
    static let initialFeed = URL(string: "https://hyunho-feeds.pages.dev/99cf9e8a101b6d8561a2c2e9aebea93d/feed.xml")!
    let url: URL
    private(set) var state: InboxState
    var write: (Data, URL) throws -> Void = { data, url in try data.write(to: url, options: .atomic) }

    init(url: URL) throws {
        self.url = url
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                state = try JSONDecoder().decode(InboxState.self, from: Data(contentsOf: url))
                try Self.validate(state)
            } catch {
                throw InboxError.invalid("피드 기록을 열 수 없습니다. 원본은 보존되어 있습니다. \(error.localizedDescription)")
            }
        } else { state = InboxState() }
    }
    func transaction(_ edit: (inout InboxState) throws -> Void) throws {
        var next = state
        try edit(&next)
        try Self.validate(next)
        guard next != state else { return }
        let data = try JSONEncoder().encode(next)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try write(data, url)
        state = next
    }
    func seed() throws {
        guard !state.seeded else { return }
        try transaction {
            $0.seeded = true
            $0.subscriptions.append(InboxSubscription(url: Self.initialFeed, title: "통합 브리핑"))
        }
    }
    func removeSubscription(_ id: UUID) throws {
        try transaction {
            $0.subscriptions.removeAll { $0.id == id }
            $0.items.removeAll { $0.subscriptionID == id && !$0.isSaved }
            let ids = Set($0.items.map(\.id))
            $0.positions = $0.positions.filter { ids.contains($0.value) }
        }
    }
    private static func validate(_ state: InboxState) throws {
        guard state.version == 1,
              Set(state.subscriptions.map(\.id)).count == state.subscriptions.count,
              Set(state.items.map(\.id)).count == state.items.count,
              Set(state.pendingReminders.map(\.id)).count == state.pendingReminders.count,
              state.items.allSatisfy({ !$0.id.isEmpty && !$0.title.isEmpty }),
              state.subscriptions.allSatisfy({ $0.url.scheme?.lowercased() == "https" && $0.url.host != nil }) else {
            throw InboxError.invalid("지원하지 않거나 손상된 피드 형식입니다.")
        }
    }
}
