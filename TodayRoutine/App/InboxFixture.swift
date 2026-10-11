#if DEBUG
import Foundation
struct InboxFixtureClient: FeedFetching {
    func fetch(_ url: URL) async throws -> ParsedFeed {
        ParsedFeed(title: "테스트 구독", entries: [ParsedFeedEntry(identity: "test", title: "추가한 구독 글", body: "구독 본문", link: URL(string: "https://example.com/article"), publishedAt: nil)])
    }
}
enum InboxFixture {
    @MainActor static func seed(_ store: InboxStore, routineID: UUID? = nil) throws {
        guard !store.state.seeded else { return }
        let now = Date(), feed = UUID()
        try store.transaction { s in
            s.seeded = true
            s.subscriptions = [InboxSubscription(id: feed, url: URL(string: "https://example.com/feed.xml")!, title: "피드 테스트", lastRefreshAt: now)]
            s.items = (0..<35).map { i in InboxItem(id: "fixture-\(i)", kind: .feed, subscriptionID: feed, title: "테스트 글 \(i)", sourceTitle: "피드 테스트", body: "테스트 피드 본문 \(i)", link: URL(string: "https://example.com/article/\(i)"), date: now.addingTimeInterval(Double(-i*60))) }
            s.items[1].richBody = "# 마크다운 제목\n\n**굵은 글씨**와 [본문 링크](https://example.com)\n\n- 첫 항목\n- 둘째 항목\n\n> 인용 문장\n\n```swift\nlet value = 1 < 2\n```\n\n| 항목 | 값 |\n| --- | --- |\n| 표 내용 | 3 |\n\n본문 마지막 문단"
            s.items[1].bodyFormat = "markdown"
            s.items[2].richBody = "<h2>HTML 제목</h2><p><strong>HTML 강조</strong></p><table><tr><th>열</th></tr><tr><td>HTML 표</td></tr></table><script>document.body.textContent='실행됨'</script>"
            s.items[2].bodyFormat = "html"
            s.items[3].richBody = (1...40).map { "<p>스크롤 테스트 문단 \($0). 긴 피드 본문을 끝까지 읽을 수 있어야 합니다.</p>" }.joined() + "<p>긴 피드 마지막 문단</p>"
            s.items[3].bodyFormat = "html"
            s.items.append(InboxItem(id: "fixture-reminder", kind: .reminder, routineID: routineID ?? UUID(), dayKey: routineID == nil ? "2026-10-06" : RoutineRules.dayKey(now), title: "지난 루틴 알림", sourceTitle: "오늘의 루틴", date: now.addingTimeInterval(-3600)))
        }
    }
}
#endif
