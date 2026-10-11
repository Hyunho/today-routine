import SwiftUI
import WebKit

/// Owned by the root so tab changes preserve the page and its history.
@MainActor
final class ValleyBrowserModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let homeURL: URL
    let title: String

    init(homeURL: URL = URL(string: "https://www.valley.town/space?tab=subscribed")!, title: String = "Valley") {
        self.homeURL = homeURL
        self.title = title
        super.init()
    }
    @Published private(set) var pageTitle: String?
    @Published private(set) var canGoBack = false
    @Published private(set) var isLoading = false
    @Published private(set) var currentURL: URL?
    @Published private(set) var errorMessage: String?
    private var observations: [NSKeyValueObservation] = []
    private var hasLoaded = false
    lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = true
        observations = [
            view.observe(\.title, options: [.initial, .new]) { [weak self] view, _ in
                let value = view.title
                DispatchQueue.main.async { self?.pageTitle = value }
            },
            view.observe(\.url, options: [.initial, .new]) { [weak self] view, _ in
                let value = view.url
                DispatchQueue.main.async { self?.currentURL = value }
            },
            view.observe(\.canGoBack, options: [.new]) { [weak self] view, _ in
                let value = view.canGoBack
                DispatchQueue.main.async { self?.canGoBack = value }
            },
            view.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
                let value = view.isLoading
                DispatchQueue.main.async { self?.isLoading = value }
            }
        ]
        return view
    }()

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        webView.load(URLRequest(url: homeURL))
    }

    func reload() {
        errorMessage = nil
        if webView.url == nil { webView.load(URLRequest(url: homeURL)) }
        else { webView.reload() }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        errorMessage = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        report(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        report(error)
    }

    private func report(_ error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        errorMessage = error.localizedDescription
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        errorMessage = "페이지가 중단되었습니다. 새로고침해 주세요."
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if ["http", "https", "about"].contains(url.scheme?.lowercased() ?? "") {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
            guard action.navigationType == .linkActivated else { return }
            #if os(macOS)
            NSWorkspace.shared.open(url)
            #else
            UIApplication.shared.open(url)
            #endif
        }
    }

    // Keep links that request a new window inside this browser tab.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if action.targetFrame == nil,
           let scheme = action.request.url?.scheme?.lowercased(), ["https", "http"].contains(scheme) {
            webView.load(action.request)
        }
        return nil
    }
}

struct ValleyBrowserView: View {
    @ObservedObject var browser: ValleyBrowserModel
    @Environment(\.pageStack) private var parentPageStack

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { browser.webView.goBack() } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!browser.canGoBack)
                .accessibilityLabel("뒤로 가기")
                Spacer()
                Text(browser.title).font(.headline)
                Spacer()
                Button { browser.reload() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("새로고침")
            }
            .buttonStyle(.borderless)
            .padding()
            Divider()
            if browser.isLoading {
                ProgressView().controlSize(.small).padding(4)
            }
            if let error = browser.errorMessage {
                VStack(spacing: 6) {
                    Text("페이지를 불러오지 못했습니다").font(.headline)
                    Text(error).font(.caption).foregroundStyle(.secondary)
                    Button("다시 시도") { browser.reload() }
                }.padding()
            }
            ValleyWebContent(webView: browser.webView)
        }
        .webActionsSidebar(url: browser.currentURL ?? browser.homeURL)
        .pageStack(parentPageStack + [pageHeading])
        .onAppear { browser.loadIfNeeded() }
    }

    private var pageHeading: String {
        let title = browser.pageTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? (browser.currentURL ?? browser.homeURL).host ?? browser.title : title
    }

}

private struct ValleyWebContent {
    let webView: WKWebView
}

#if os(macOS)
extension ValleyWebContent: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#else
extension ValleyWebContent: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif
