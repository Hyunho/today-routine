import SwiftUI
import WebKit

struct FeedBodyView: View {
    let bodyText: String
    let format: String?
    let baseURL: URL?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @ScaledMetric(relativeTo: .body) private var fontSize = 17.0
    @State private var height: CGFloat = 80
    var body: some View {
        FeedWebContent(html: FeedBodyRenderer.document(body: bodyText, format: format, base: baseURL, dark: colorScheme == .dark, fontSize: fontSize), baseURL: baseURL, height: $height) { url in openURL(url) }
            .frame(height: height)
    }
}

private struct FeedWebContent {
    let html: String
    let baseURL: URL?
    @Binding var height: CGFloat
    let openLink: (URL) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeWebView(context: Context) -> ReadingWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = ReadingWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.widthChanged = { [weak coordinator = context.coordinator, weak webView] in
            if let webView { coordinator?.measure(webView) }
        }
        #if os(iOS)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        #else
        webView.setValue(false, forKey: "drawsBackground")
        #endif
        return webView
    }
    func update(_ webView: ReadingWebView, context: Context) {
        context.coordinator.parent = self
        guard context.coordinator.html != html || context.coordinator.baseURL != baseURL else { return }
        context.coordinator.html = html; context.coordinator.baseURL = baseURL
        context.coordinator.loadingDocument = true
        webView.loadHTMLString(html, baseURL: baseURL)
    }
    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: FeedWebContent
        var html: String?
        var baseURL: URL?
        var loadingDocument = false
        init(_ parent: FeedWebContent) { self.parent = parent }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { measure(webView) }
        func measure(_ webView: WKWebView) {
            // Native evaluation measures layout; feed-authored JavaScript remains disabled.
            webView.evaluateJavaScript("Math.ceil(document.body.getBoundingClientRect().height)") { [weak self] value, _ in
                guard let self, let number = value as? NSNumber else { return }
                let height = max(40, CGFloat(truncating: number) + 2)
                if abs(self.parent.height - height) > 1 { self.parent.height = height }
            }
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated {
                if let url = action.request.url, FeedLinkPolicy.allows(url) { parent.openLink(url) }
                decisionHandler(.cancel)
            } else {
                // The initial loadHTMLString navigation may use baseURL rather than about:blank.
                // Allow that one local document load, then block redirects and meta refreshes.
                if loadingDocument && action.navigationType == .other && action.targetFrame?.isMainFrame == true {
                    loadingDocument = false
                    decisionHandler(.allow)
                } else { decisionHandler(.cancel) }
            }
        }
    }
}
#if os(iOS)
extension FeedWebContent: UIViewRepresentable {
    func makeUIView(context: Context) -> ReadingWebView { makeWebView(context: context) }
    func updateUIView(_ webView: ReadingWebView, context: Context) { update(webView, context: context) }
}
#else
extension FeedWebContent: NSViewRepresentable {
    func makeNSView(context: Context) -> ReadingWebView { makeWebView(context: context) }
    func updateNSView(_ webView: ReadingWebView, context: Context) { update(webView, context: context) }
}
#endif
private final class ReadingWebView: WKWebView {
    var widthChanged: (() -> Void)?
    private var previousWidth: CGFloat = 0
    #if os(iOS)
    override func layoutSubviews() { super.layoutSubviews(); measureWidth() }
    #else
    override func layout() { super.layout(); measureWidth() }
    override func scrollWheel(with event: NSEvent) {
        // The web view expands to the full article height. Its enclosing SwiftUI
        // scroll view owns vertical scrolling; WebKit otherwise consumes it.
        if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX),
           let scrollView = enclosingScrollView {
            scrollView.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }
    #endif
    private func measureWidth() {
        guard abs(bounds.width - previousWidth) > 1 else { return }
        previousWidth = bounds.width
        DispatchQueue.main.async { [weak self] in self?.widthChanged?() }
    }
}
