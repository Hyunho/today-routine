import Foundation

/// Shared by Markdown rendering and user-initiated WebView navigation.
enum FeedLinkPolicy {
    static func allows(_ url: URL) -> Bool {
        ["https", "http", "grokbot"].contains(url.scheme?.lowercased() ?? "")
            && !(url.host ?? "").isEmpty
    }
}

/// Converts Foundation's Markdown syntax tree to an offline HTML reading document.
enum FeedBodyRenderer {
    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
    static func format(_ value: String) -> String {
        if value.range(of: "(?m)^ {0,3}(#{1,6}\\s|```|~~~)", options: .regularExpression) != nil { return "markdown" }
        return value.range(of: "(?i)<(?:p|div|h[1-6]|table|ul|ol|li|br|strong|em|a|pre|blockquote|section|article|img)\\b[^>]*>", options: .regularExpression) == nil ? "markdown" : "html"
    }
    static func markdown(_ source: String, base: URL?) -> String {
        guard let parsed = try? AttributedString(markdown: source, options: .init(interpretedSyntax: .full), baseURL: base) else { return "<pre>\(escape(source))</pre>" }
        var result = "", path: [PresentationIntent.IntentType] = []
        for run in parsed.runs {
            let next = Array((run.presentationIntent?.components ?? []).reversed())
            var shared = 0
            while shared < min(path.count, next.count), path[shared].identity == next[shared].identity { shared += 1 }
            for component in path.dropFirst(shared).reversed() { result += close(component.kind) }
            for component in next.dropFirst(shared) { result += open(component.kind) }
            path = next
            var text = escape(String(parsed[run.range].characters))
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.code) { text = "<code>\(text)</code>" }
            if intent.contains(.stronglyEmphasized) { text = "<strong>\(text)</strong>" }
            if intent.contains(.emphasized) { text = "<em>\(text)</em>" }
            if intent.contains(.strikethrough) { text = "<del>\(text)</del>" }
            if intent.contains(.lineBreak) { text = "<br>" }
            if let url = run.link, FeedLinkPolicy.allows(url) {
                text = "<a href=\"\(escape(url.absoluteString))\">\(text)</a>"
            }
            result += text
        }
        for component in path.reversed() { result += close(component.kind) }
        return result
    }
    private static func open(_ kind: PresentationIntent.Kind) -> String {
        switch kind {
        case .paragraph: return "<p>"
        case .header(let level): return "<h\(min(6, max(1, level)))>"
        case .orderedList: return "<ol>"
        case .unorderedList: return "<ul>"
        case .listItem: return "<li>"
        case .codeBlock: return "<pre><code>"
        case .blockQuote: return "<blockquote>"
        case .thematicBreak: return "<hr>"
        case .table: return "<div class=\"table-scroll\"><table>"
        case .tableHeaderRow: return "<thead><tr>"
        case .tableRow: return "<tr>"
        case .tableCell: return "<td>"
        @unknown default: return "<div>"
        }
    }
    private static func close(_ kind: PresentationIntent.Kind) -> String {
        switch kind {
        case .paragraph: return "</p>"
        case .header(let level): return "</h\(min(6, max(1, level)))>"
        case .orderedList: return "</ol>"
        case .unorderedList: return "</ul>"
        case .listItem: return "</li>"
        case .codeBlock: return "</code></pre>"
        case .blockQuote: return "</blockquote>"
        case .thematicBreak: return ""
        case .table: return "</table></div>"
        case .tableHeaderRow: return "</tr></thead>"
        case .tableRow: return "</tr>"
        case .tableCell: return "</td>"
        @unknown default: return "</div>"
        }
    }
    static func document(body: String, format: String?, base: URL?, dark: Bool, fontSize: Double) -> String {
        let html = format == "html" ? body : markdown(body, base: base)
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'none'; style-src 'unsafe-inline'; img-src data:; frame-src 'none'; form-action 'none'; base-uri 'none'">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        :root { color-scheme: \(dark ? "dark" : "light"); }
        html,body { margin:0; padding:0; background:transparent; color:\(dark ? "#efefef" : "#222"); font-family:-apple-system,sans-serif; font-size:\(fontSize)px; line-height:1.65; overflow-wrap:anywhere; }
        body > :first-child { margin-top:0; } body > :last-child { margin-bottom:0; }
        p { margin:0 0 1em; } h1,h2,h3,h4,h5,h6 { line-height:1.3; margin:1.2em 0 .5em; } h1 { font-size:1.7em; } h2 { font-size:1.4em; } h3 { font-size:1.2em; }
        a { color:\(dark ? "#5dd8d1" : "#007f79"); } blockquote { margin:1em 0; border-left:3px solid #888; padding-left:1em; }
        pre { overflow-x:auto; padding:12px; border-radius:8px; background:\(dark ? "#252525" : "#f1f2f3"); white-space:pre; } code { font-family:ui-monospace,monospace; font-size:.9em; }
        .table-scroll { overflow-x:auto; } table { border-collapse:collapse; margin:1em 0; max-width:100%; } td,th { border:1px solid #8888; padding:7px 10px; } thead { font-weight:600; }
        img,video { max-width:100%; height:auto; } iframe,object,embed,form { display:none !important; }
        </style></head><body>\(html)</body></html>
        """
    }
}
