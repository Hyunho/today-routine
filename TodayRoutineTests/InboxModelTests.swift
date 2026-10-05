import XCTest
@testable import RoutineCore
actor InboxFakeFeed: FeedFetching {
    var failure = false
    var suspended = false
    var continuation: CheckedContinuation<Void,Never>?
    var started = false
    func configure(failure: Bool = false, suspended: Bool = false) { self.failure = failure; self.suspended = suspended }
    func release() { suspended = false; continuation?.resume(); continuation = nil }
    func fetch(_ url: URL) async throws -> ParsedFeed {
        started = true
        if suspended { await withCheckedContinuation { continuation = $0 } }
        if failure || url.host == "fail.test" { throw URLError(.cannotConnectToHost) }
        return ParsedFeed(title: "Feed", entries: [ParsedFeedEntry(identity: "one", title: "Entry", body: "Body", link: URL(string:"https://example.com/post"), publishedAt: nil)])
    }
}
@MainActor final class InboxModelTests: XCTestCase {
    func make(_ client: InboxFakeFeed) throws -> InboxModel {
        let store = try InboxStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("inbox.json"))
        return InboxModel(store: store, client: client)
    }
    func testRepeatedMergePreservesDateReadingAndPosition() async throws {
        let model = try make(InboxFakeFeed())
        await model.addSubscription(URL(string: "https://example.com/feed")!)
        let item = try XCTUnwrap(model.state.items.first)
        model.setRead(item.id); model.toggleSaved(item.id); model.savePosition(item.id, key: "all/all")
        await model.refresh(now: item.date.addingTimeInterval(1000), force: true)
        XCTAssertEqual(model.state.items.count, 1)
        XCTAssertEqual(model.state.items[0].date, item.date)
        XCTAssertTrue(model.state.items[0].isSaved); XCTAssertTrue(model.state.items[0].isRead)
        XCTAssertEqual(model.state.positions["all/all"], item.id)
    }
    func testFailureDoesNotEraseOtherFeedsAndCanRetry() async throws {
        let client = InboxFakeFeed(), model = try make(client)
        await model.addSubscription(URL(string:"https://example.com/feed")!)
        await model.addSubscription(URL(string:"https://fail.test/feed")!)
        XCTAssertEqual(model.state.subscriptions.count, 2)
        XCTAssertEqual(model.state.items.count, 1)
        XCTAssertEqual(model.feedErrors.count, 1)
        await client.configure(failure: true)
        await model.refresh(now: Date(), force: true)
        XCTAssertEqual(model.state.items.count, 1)
        XCTAssertEqual(model.feedErrors.count, 2)
    }
    func testDeletionWhileFetchingDoesNotResurrectSubscription() async throws {
        let client = InboxFakeFeed(), model = try make(client)
        await client.configure(suspended: true)
        let task = Task { await model.addSubscription(URL(string: "https://example.com/feed")!) }
        while !(await client.started) { await Task.yield() }
        let id = try XCTUnwrap(model.state.subscriptions.first?.id)
        model.removeSubscription(id)
        await client.release(); await task.value
        XCTAssertTrue(model.state.items.isEmpty); XCTAssertTrue(model.state.subscriptions.isEmpty)
    }
    func testDuplicateURLsAndThrottle() async throws {
        let client = InboxFakeFeed(), model = try make(client)
        await model.addSubscription(URL(string:"https://EXAMPLE.com:443/feed#anchor")!)
        await model.addSubscription(URL(string:"https://example.com/feed")!)
        XCTAssertEqual(model.state.subscriptions.count, 1)
        XCTAssertNotNil(model.error)
        let date = try XCTUnwrap(model.state.subscriptions.first?.lastRefreshAt)
        await client.configure(failure: true)
        await model.refresh(now: date.addingTimeInterval(899), force: false)
        XCTAssertTrue(model.feedErrors.isEmpty)
        await model.refresh(now: date.addingTimeInterval(899), force: true)
        XCTAssertEqual(model.feedErrors.count, 1)
    }
    func testSavedArticleSurvivesUnsubscribeAndFilters() async throws {
        let model = try make(InboxFakeFeed())
        await model.addSubscription(URL(string:"https://example.com/feed")!)
        let id = try XCTUnwrap(model.state.items.first?.id)
        model.toggleSaved(id); model.removeSubscription(model.state.subscriptions[0].id)
        XCTAssertEqual(model.items(filter: .feeds, savedOnly: true).map(\.id), [id])
        XCTAssertTrue(model.items(filter: .reminders, savedOnly: false).isEmpty)
    }
}
