import SwiftUI

private struct WebActionsSidebarModifier: ViewModifier {
    let url: URL?
    let enabled: Bool
    @State private var isExpanded = true

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .trailing, spacing: 0) {
                if enabled && isExpanded {
                    WebActionsSidebar(url: url)
                }
            }
            .toolbar {
                if enabled {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            isExpanded.toggle()
                        } label: {
                            Image(systemName: "sidebar.right")
                        }
                        .help(isExpanded ? "사이드바 숨기기" : "사이드바 펼치기")
                        .accessibilityLabel(isExpanded ? "사이드바 숨기기" : "사이드바 펼치기")
                        .accessibilityValue(isExpanded ? "펼쳐짐" : "숨겨짐")
                        .accessibilityIdentifier("toggle-web-sidebar")
                    }
                }
            }
    }
}

/// A compact trailing rail shared by screens with a web destination.
struct WebActionsSidebar: View {
    let url: URL?
    @Environment(\.openURL) private var openURL
    @State private var openFailed = false

    private var webURL: URL? {
        guard let url, ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    var body: some View {
        VStack(spacing: 8) {
            Button {
                guard let webURL else { return }
                openURL(webURL) { accepted in openFailed = !accepted }
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(webURL == nil)
            .help("기본 브라우저로 열기")
            .accessibilityLabel("웹으로 열기")
            .accessibilityHint("기본 브라우저에서 엽니다")
            .accessibilityIdentifier("open-in-browser")
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .frame(width: 52)
        .frame(maxHeight: .infinity)
        .background(.bar)
        .overlay(alignment: .leading) { Divider() }
        .alert("웹페이지를 열지 못했습니다", isPresented: $openFailed) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("링크를 확인한 후 다시 시도해 주세요.")
        }
    }
}

extension View {
    func webActionsSidebar(url: URL?, enabled: Bool = true) -> some View {
        modifier(WebActionsSidebarModifier(url: url, enabled: enabled))
    }

    @ViewBuilder func platformInlineTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
    @ViewBuilder func platformSheetSize() -> some View {
        #if os(macOS)
        self.frame(minWidth:360,idealWidth:420,minHeight:480,idealHeight:660)
        #else
        self
        #endif
    }
}
struct PlatformEditButton: View {
    var body: some View {
        #if os(iOS)
        EditButton()
        #else
        EmptyView()
        #endif
    }
}

/// Uses the system refresh indicator and keeps transfer results visible after a pull.
struct MobileSyncRefresh: ViewModifier {
    let model: AppModel
    var includeFeeds = false
    @State private var didRefresh = false

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .refreshable {
                await model.refreshLists(includeFeeds: includeFeeds)
                didRefresh = true
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if didRefresh, let status = model.sync?.cloudTransferStatus {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                        .padding(8).frame(maxWidth: .infinity)
                        .background(.regularMaterial)
                        .accessibilityIdentifier("동기화 요청 상태")
                }
            }
        #else
        content
        #endif
    }
}

/// Shared completion indicator; feed read status remains independent.
struct CompletionStatusLabel: View {
    let status: DayStatus
    var body: some View {
        Label(status == .completed ? "완료" : status == .skipped ? "건너뜀" : "미완료",
              systemImage: status == .completed ? "checkmark.circle.fill" : status == .skipped ? "minus.circle.fill" : "circle")
            .font(.caption.weight(.medium))
            .foregroundStyle(status == .completed ? Color.teal : status == .skipped ? Color.orange : Color.secondary)
    }
}

struct CompletionCheckButton: View {
    let title: String
    let status: DayStatus
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: status == .skipped ? "minus.circle.fill" : status == .completed ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(status == .skipped ? Color.orange : status == .completed ? Color.teal : Color.secondary)
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(.borderless)
            .accessibilityLabel("\(title) \(status == .skipped ? "건너뛰기 취소" : status == .completed ? "완료 취소" : "완료")")
            .accessibilityValue(status == .skipped ? "건너뜀" : status == .completed ? "완료" : "미완료")
    }
}

private struct PageStackEnvironmentKey: EnvironmentKey {
    static let defaultValue: [String] = []
}

extension EnvironmentValues {
    var pageStack: [String] {
        get { self[PageStackEnvironmentKey.self] }
        set { self[PageStackEnvironmentKey.self] = newValue }
    }
}

struct PageStackPreferenceKey: PreferenceKey {
    static var defaultValue: [String] = []
    static func reduce(value: inout [String], nextValue: () -> [String]) {
        let next = nextValue()
        if next.count >= value.count { value = next }
    }
}

extension View {
    func pageStack(_ path: [String]) -> some View {
        environment(\.pageStack, path)
            .transformPreference(PageStackPreferenceKey.self) { value in
                if path.count > value.count { value = path }
            }
    }
}
