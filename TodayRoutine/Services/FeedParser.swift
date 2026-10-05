import Foundation
import CryptoKit

struct ParsedFeed: Sendable { var title: String; var entries: [ParsedFeedEntry] }
struct ParsedFeedEntry: Sendable {
    var identity: String
    var title: String
    var body: String
    var link: URL?
    var publishedAt: Date?
}
enum FeedParser {
    static func parse(_ data: Data, baseURL: URL) throws -> ParsedFeed {
        guard data.count <= 5 * 1024 * 1024 else { throw InboxError.invalid("피드가 5 MiB를 초과합니다.") }
        // Reject DTD declarations even when XMLParser silently skips external entities.
        let declarationScan = String(decoding: data.filter { $0 != 0 }, as: UTF8.self)
        guard !declarationScan.localizedCaseInsensitiveContains("<!DOCTYPE"), !declarationScan.localizedCaseInsensitiveContains("<!ENTITY") else { throw InboxError.invalid("외부 선언을 포함한 피드는 지원하지 않습니다.") }
        let delegate = FeedXMLDelegate(base: baseURL)
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never
        parser.delegate = delegate
        guard parser.parse(), !delegate.unsafeEntity, ["rss", "feed"].contains(delegate.root), delegate.validContainer else {
            throw InboxError.invalid("RSS 또는 Atom 피드 형식을 확인해 주세요.")
        }
        return ParsedFeed(title: plainText(delegate.feedTitle), entries: delegate.entries)
    }
    static func safeLink(_ value: String, base: URL) -> URL? {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: base)?.absoluteURL,
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
        return url
    }
    static func plainText(_ html: String) -> String {
        var text = html
        for pattern in ["(?is)<(script|style)\\b[^>]*>.*?</\\1\\s*>", "(?s)<!--.*?-->"] {
            text = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        text = text.replacingOccurrences(of: "(?i)<\\s*(?:br\\b[^>]*|/p\\s*|/div\\s*|/li\\s*|/h[1-6]\\s*)>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
        let entities = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00a0}", "mdash": "—", "ndash": "–", "hellip": "…", "ldquo": "“", "rdquo": "”", "lsquo": "‘", "rsquo": "’", "copy": "©"]
        let regex = try! NSRegularExpression(pattern: "&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);")
        let source = text as NSString
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)).reversed() {
            let key = source.substring(with: match.range(at: 1))
            var replacement = entities[key]
            if key.hasPrefix("#x"), let number = UInt32(key.dropFirst(2), radix: 16), let scalar = UnicodeScalar(number) { replacement = String(scalar) }
            else if key.hasPrefix("#"), let number = UInt32(key.dropFirst()), let scalar = UnicodeScalar(number) { replacement = String(scalar) }
            if let replacement, let range = Range(match.range, in: text) { text.replaceSubrange(range, with: replacement) }
        }
        return text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func date(_ value: String) -> Date? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: value) { return date }
        iso.formatOptions.insert(.withFractionalSeconds)
        if let date = iso.date(from: value) { return date }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["EEE, dd MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm Z", "dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm:ss zzz", "yyyy-MM-dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}
private final class FeedXMLDelegate: NSObject, XMLParserDelegate {
    let base: URL
    var root = "", feedTitle = "", validContainer = false, unsafeEntity = false
    var entries: [ParsedFeedEntry] = []
    private var stack: [String] = [], buffers: [String] = []
    private var fields: [String: String] = [:], entryDepth: Int?, alternateLink = ""
    private var seen: Set<String> = []
    init(base: URL) { self.base = base }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        let name = elementName.lowercased()
        if stack.isEmpty { root = name; validContainer = name == "feed" }
        if stack == ["rss"], name == "channel" { validContainer = true }
        if (root == "rss" && stack == ["rss", "channel"] && name == "item") || (root == "feed" && stack == ["feed"] && name == "entry") {
            entryDepth = stack.count + 1; fields = [:]; alternateLink = ""
        }
        if let depth = entryDepth, stack.count == depth, name == "link", let href = attributes["href"], attributes["rel"] == nil || attributes["rel"] == "alternate" { alternateLink = href }
        stack.append(name); buffers.append("")
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if !buffers.isEmpty { buffers[buffers.count-1] += string } }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { self.parser(parser, foundCharacters: String(decoding: CDATABlock, as: UTF8.self)) }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard let name = stack.last, let text = buffers.last else { return }
        if let depth = entryDepth {
            if stack.count == depth + 1 { fields[name] = text }
            if stack.count == depth {
                finishEntry(); entryDepth = nil
            }
        } else if name == "title", stack == ["rss", "channel", "title"] || stack == ["feed", "title"] { feedTitle = text }
        stack.removeLast(); buffers.removeLast()
        if !buffers.isEmpty {
            // Preserve safe XHTML text boundaries, but never append script/style contents.
            if !["script", "style"].contains(name) { buffers[buffers.count-1] += text + (["p", "div", "br", "li"].contains(name) ? "\n" : "") }
        }
    }
    private func finishEntry() {
        let title = FeedParser.plainText(fields["title"] ?? "")
        let link = FeedParser.safeLink(alternateLink.isEmpty ? fields["link"] ?? "" : alternateLink, base: base)
        let dateString = fields["pubdate"] ?? fields["published"] ?? fields["updated"] ?? fields["dc:date"] ?? ""
        let explicit = (fields["guid"] ?? fields["id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = SHA256.hash(data: Data((title + "\n" + dateString).utf8)).map { String(format: "%02x", $0) }.joined()
        let identity = explicit.isEmpty ? link?.absoluteString ?? fallback : explicit
        guard seen.insert(identity).inserted else { return }
        entries.append(ParsedFeedEntry(identity: identity, title: title.isEmpty ? "제목 없는 글" : title, body: FeedParser.plainText(fields["content:encoded"] ?? fields["content"] ?? fields["description"] ?? fields["summary"] ?? ""), link: link, publishedAt: FeedParser.date(dateString)))
    }
    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) { unsafeEntity = true; parser.abortParsing() }
    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) { unsafeEntity = true; parser.abortParsing() }
    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? { unsafeEntity = true; parser.abortParsing(); return nil }
}
