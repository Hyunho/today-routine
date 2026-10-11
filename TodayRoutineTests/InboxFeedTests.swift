import XCTest
@testable import RoutineCore
final class InboxFeedTests: XCTestCase {
    let base = URL(string: "https://example.com/feeds/index.xml")!
    func parse(_ text: String) throws -> ParsedFeed { try FeedParser.parse(Data(text.utf8), baseURL: base) }
    func testRSSBodyAndRelativeLinks() throws {
        let feed = try parse("""
        <rss xmlns:content="http://purl.org/rss/1.0/modules/content/"><channel><title>News</title><item><guid>one</guid><title>A &amp; B</title><link>/a</link><pubDate>Mon, 05 Oct 2026 14:56:54 +0900</pubDate><description>short</description><content:encoded><![CDATA[<p>Hello &amp; welcome</p><script>bad()</script><img src="https://evil.test/pixel">]]></content:encoded></item></channel></rss>
        """)
        XCTAssertEqual(feed.title, "News"); XCTAssertEqual(feed.entries.count, 1)
        let item = try XCTUnwrap(feed.entries.first)
        XCTAssertEqual(item.identity, "one"); XCTAssertEqual(item.title, "A & B")
        XCTAssertEqual(item.link?.absoluteString, "https://example.com/a")
        XCTAssertEqual(item.body, "Hello & welcome")
        XCTAssertEqual(item.publishedAt, ISO8601DateFormatter().date(from: "2026-10-05T05:56:54Z"))
    }
    func testAtomMissingDatesAndAlternateLink() throws {
        let feed = try parse("""
        <feed xmlns="http://www.w3.org/2005/Atom"><title>Atom</title><entry><id>a</id><title>Post</title><link rel="self" href="/api"/><link rel="alternate" href="../article"/><updated>2026-10-05T05:00:00Z</updated><content type="xhtml"><div xmlns="http://www.w3.org/1999/xhtml"><p>First</p><p>Second</p></div></content></entry><entry><id>b</id><title>Missing</title><link href="javascript:alert(1)"/><published>invalid</published></entry></feed>
        """)
        XCTAssertEqual(feed.entries.count, 2)
        XCTAssertEqual(feed.entries[0].link?.absoluteString, "https://example.com/article")
        XCTAssertNotNil(feed.entries[0].publishedAt)
        XCTAssertTrue(feed.entries[0].body.contains("First")); XCTAssertTrue(feed.entries[0].body.contains("Second"))
        XCTAssertNil(feed.entries[1].publishedAt); XCTAssertNil(feed.entries[1].link)
        XCTAssertEqual(feed.entries[1].body, "")
    }
    func testMalformedHTMLAndEntitiesRejected() throws {
        for xml in ["<rss><channel>", "<html><body>Not feed</body></html>", "<!DOCTYPE rss [<!ENTITY x SYSTEM 'file:///etc/passwd'>]><rss><channel><title>&x;</title></channel></rss>"] {
            XCTAssertThrowsError(try parse(xml), xml)
        }
    }
    func testDuplicateGuidAndStableFallback() throws {
        let xml = "<rss><channel><item><guid>x</guid><title>First</title></item><item><guid>x</guid><title>Duplicate</title></item><item><title>No ID</title></item></channel></rss>"
        let a = try parse(xml), b = try parse(xml)
        XCTAssertEqual(a.entries.count, 2)
        XCTAssertEqual(a.entries[0].title, "First")
        XCTAssertEqual(a.entries[1].identity, b.entries[1].identity)
        XCTAssertNil(a.entries[1].publishedAt)
    }
    func testTextDecoderDoesNotExecuteMarkup() {
        XCTAssertEqual(FeedParser.plainText("<style>secret</style><p>A&nbsp;&#x1F600; &#65;</p><!--hide--><p>B<br>C</p>"), "A 😀 A\nB\nC")
    }
    func testPrefixedAtomAndContentNamespace() throws {
        let feed = try parse("<a:feed xmlns:a='http://www.w3.org/2005/Atom'><a:title>Prefix</a:title><a:entry><a:id>p</a:id><a:title>Post</a:title><a:content>Text</a:content></a:entry></a:feed>")
        XCTAssertEqual(feed.title, "Prefix"); XCTAssertEqual(feed.entries.first?.body, "Text")
        let rss = try parse("<rss xmlns:c='http://purl.org/rss/1.0/modules/content/'><channel><item><title>Post</title><description>Short</description><c:encoded>Full text</c:encoded></item></channel></rss>")
        XCTAssertEqual(rss.entries.first?.body, "Full text")
    }
    func testMissingLinksDoNotCollapseDifferentArticles() throws {
        let feed = try parse("<rss><channel><item><title>First</title></item><item><title>Second</title></item></channel></rss>")
        XCTAssertEqual(feed.entries.count, 2)
        XCTAssertNil(feed.entries.first?.link)
        XCTAssertNotEqual(feed.entries.first?.identity, feed.entries.last?.identity)
    }
    func testRejectsInsecureRedirect() {
        let download = FeedDownload()
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let origin = URL(string: "https://example.com/feed")!
        let task = session.dataTask(with: origin)
        let response = HTTPURLResponse(url: origin, statusCode: 302, httpVersion: nil, headerFields: nil)!
        var result: URLRequest? = URLRequest(url: origin)
        download.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: URLRequest(url: URL(string: "http://example.com/feed")!)) { result = $0 }
        XCTAssertNil(result)
    }
    func testDownloadCancellation() async {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [InboxURLProtocol.self]
        let client = FeedClient(configuration: config)
        let task = Task { try await client.fetch(URL(string: "https://example.com/slow")!) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled download must throw") } catch {}
    }
    func testDownloaderErrorsAndOversize() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [InboxURLProtocol.self]
        let client = FeedClient(configuration: config)
        for route in ["status", "html", "oversize", "timeout"] {
            do { _ = try await client.fetch(URL(string: "https://example.com/\(route)")!); XCTFail("Should reject \(route)") }
            catch { XCTAssertFalse(error.localizedDescription.isEmpty) }
        }
        do { _ = try await client.fetch(URL(string: "http://example.com/rss")!); XCTFail("HTTP must fail") } catch {}
        let good = try await client.fetch(URL(string: "https://example.com/good")!)
        XCTAssertEqual(good.title, "Downloaded")
    }
}
final class InboxURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let route = request.url!.lastPathComponent
        if route == "slow" { return }
        if route == "timeout" { client?.urlProtocol(self, didFailWithError: URLError(.timedOut)); return }
        let response = HTTPURLResponse(url: request.url!, statusCode: route == "status" ? 500 : 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if route == "oversize" {
            for _ in 0..<6 { client?.urlProtocol(self, didLoad: Data(repeating: 32, count: 1024*1024)) }
        } else {
            let body = route == "html" ? "<html/>" : "<rss><channel><title>Downloaded</title></channel></rss>"
            client?.urlProtocol(self, didLoad: Data(body.utf8))
        }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
