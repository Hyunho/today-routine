import XCTest
@testable import RoutineCore
@MainActor final class InboxStoreTests: XCTestCase {
    func path() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("inbox.json") }
    func testRoundTripAndSeedOnlyOnce() throws {
        let url = path(), store = try InboxStore(url: url)
        try store.seed()
        XCTAssertEqual(store.state.subscriptions.count, 1)
        let id = store.state.subscriptions[0].id
        try store.removeSubscription(id)
        let reopened = try InboxStore(url: url); try reopened.seed()
        XCTAssertTrue(reopened.state.subscriptions.isEmpty)
        XCTAssertTrue(reopened.state.seeded)
    }
    func testDeletionKeepsSavedAndRetention() throws {
        let store = try InboxStore(url: path()), feed = UUID(), now = Date()
        try store.transaction { s in
            s.subscriptions = [InboxSubscription(id: feed, url: URL(string: "https://example.com/feed")!, title: "Test")]
            s.items = (0..<502).map { i in InboxItem(id: "\(i)", kind: .feed, subscriptionID: feed, title: "Article", sourceTitle: "Test", date: now.addingTimeInterval(Double(i)), isSaved: i == 0) }
            s.prune(now: now)
        }
        XCTAssertEqual(store.state.items.count, 501)
        try store.removeSubscription(feed)
        XCTAssertEqual(store.state.items.map(\.id), ["0"])
        XCTAssertEqual(try InboxStore(url: store.url).state.items.first?.sourceTitle, "Test")
    }
    func testFailedWriteDoesNotPublishChange() throws {
        let store = try InboxStore(url: path()); try store.seed()
        let old = store.state
        store.write = { _,_ in throw CocoaError(.fileWriteOutOfSpace) }
        XCTAssertThrowsError(try store.transaction { $0.subscriptions = [] })
        XCTAssertEqual(store.state, old)
        XCTAssertEqual(try InboxStore(url: store.url).state, old)
    }
    func testCorruptionAndFutureVersionPreserveBytes() throws {
        for data in [Data("not json".utf8), try JSONEncoder().encode(InboxState(version: 99))] {
            let url = path(); try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
            XCTAssertThrowsError(try InboxStore(url: url))
            XCTAssertEqual(try Data(contentsOf: url), data)
        }
    }
    func testOldReminderPruningPreservesSavedAndPositions() throws {
        let store = try InboxStore(url: path()), now = Date()
        try store.transaction { s in
            s.items = [InboxItem(id: "old", kind: .reminder, title: "Old", sourceTitle: "루틴", date: now.addingTimeInterval(-91*86400)), InboxItem(id: "saved", kind: .reminder, title: "Saved", sourceTitle: "루틴", date: now.addingTimeInterval(-91*86400), isSaved: true)]
            s.positions["all/all"] = "saved"; s.prune(now: now)
        }
        let state = try InboxStore(url: store.url).state
        XCTAssertEqual(state.items.map(\.id), ["saved"])
        XCTAssertEqual(state.positions["all/all"], "saved")
    }
}
