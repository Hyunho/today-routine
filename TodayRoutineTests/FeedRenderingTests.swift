import XCTest
@testable import RoutineCore
final class FeedRenderingTests: XCTestCase {
    func testGrokBotMarkdownLinkRemainsClickable() {
        let url = "grokbot://app/v1/agent?id=a93df8d3-7d51-4003-896c-b0bb383d0b73"
        let html = FeedBodyRenderer.markdown("[🤖 봇 열기](\(url))", base: nil)
        XCTAssertTrue(html.contains("<a href=\"\(url)\">🤖 봇 열기</a>"), html)
    }

    func testFeedLinksAllowWebAndGrokBotButRejectOtherSchemes() throws {
        for value in ["https://example.com/article", "http://example.com/article",
                      "grokbot://app/v1/agent?id=a93df8d3-7d51-4003-896c-b0bb383d0b73",
                      "GROKBOT://app/v1/agent?id=a93df8d3-7d51-4003-896c-b0bb383d0b73"] {
            XCTAssertTrue(FeedLinkPolicy.allows(try XCTUnwrap(URL(string: value))), value)
        }
        for value in ["javascript:alert(1)", "file:///tmp/private.txt", "data:text/html,hello",
                      "unknown://app/action", "grokbot:agent", "grokbot:///agent", "https:///article"] {
            XCTAssertFalse(FeedLinkPolicy.allows(try XCTUnwrap(URL(string: value))), value)
            let html = FeedBodyRenderer.markdown("[link](\(value))", base: nil)
            XCTAssertFalse(html.contains("href="), html)
        }
    }

    func testMarkdownBlocksAndInlineFormatting() throws {
        let html = FeedBodyRenderer.markdown("# 제목\n\n**굵게**와 [링크](/news)\n\n- 하나\n- 둘\n\n> 인용\n\n```swift\nlet x = 1 < 2\n```\n\n| 이름 | 값 |\n| --- | --- |\n| 항목 | 3 |", base: URL(string: "https://example.com")!)
        for fragment in ["<h1>", "<strong>굵게</strong>", "href=\"https://example.com/news\"", "<ul>", "<li>", "<blockquote>", "<pre><code>", "&lt;", "<table>", "<td>"] { XCTAssertTrue(html.contains(fragment), "Missing \(fragment): \(html)") }
    }
    func testRSSPreservesRawMarkdownAndHTML() throws {
        let xml = "<rss><channel><item><title>MD</title><description><![CDATA[# 제목\n\n**강조**]]></description></item><item><title>HTML</title><description><![CDATA[<h2>제목</h2><p><strong>강조</strong></p>]]></description></item></channel></rss>"
        let entries = try FeedParser.parse(Data(xml.utf8), baseURL: URL(string: "https://example.com")!).entries
        XCTAssertEqual(entries[0].richBody, "# 제목\n\n**강조**")
        XCTAssertEqual(entries[0].bodyFormat, "markdown")
        XCTAssertEqual(entries[1].bodyFormat, "html")
        XCTAssertTrue(entries[1].richBody!.contains("<strong>"))
        XCTAssertFalse(entries[1].body.contains("<strong>"))
    }
    func testAtomXHTMLRetainsNestedStructure() throws {
        let xml = "<feed xmlns='http://www.w3.org/2005/Atom'><entry><id>a</id><title>A</title><content type='xhtml'><div xmlns='http://www.w3.org/1999/xhtml'><h2>Heading</h2><p>A &amp; B <a href='/a'>link</a></p></div></content></entry></feed>"
        let item = try FeedParser.parse(Data(xml.utf8), baseURL: URL(string: "https://example.com")!).entries[0]
        XCTAssertEqual(item.bodyFormat, "html")
        XCTAssertTrue(item.richBody!.contains("<h2>Heading</h2>"))
        XCTAssertTrue(item.richBody!.contains("href=\"/a\""))
        XCTAssertTrue(item.richBody!.contains("A &amp; B"))
    }
    func testUnsafeMarkdownLinkAndDocumentPolicy() {
        XCTAssertEqual(FeedBodyRenderer.format("```html\n<div>example</div>\n```"), "markdown")
        let html = FeedBodyRenderer.markdown("[bad](javascript:alert) **ok**", base: nil)
        XCTAssertFalse(html.contains("href="))
        let page = FeedBodyRenderer.document(body: "<script>bad()</script>", format: "html", base: nil, dark: false, fontSize: 17)
        XCTAssertTrue(page.contains("default-src 'none'"))
        XCTAssertTrue(page.contains("script-src 'none'"))
        XCTAssertTrue(page.contains("form-action 'none'"))
    }
    func testLegacyItemStillDecodesWithoutRichBody() throws {
        let item = InboxItem(id: "old", kind: .feed, title: "old", sourceTitle: "old", body: "**bold**", date: Date(), isRead: true, isSaved: true)
        let data = try JSONEncoder().encode(item)
        let restored = try JSONDecoder().decode(InboxItem.self, from: data)
        XCTAssertNil(restored.richBody)
        XCTAssertTrue(restored.isRead && restored.isSaved)
    }
}
