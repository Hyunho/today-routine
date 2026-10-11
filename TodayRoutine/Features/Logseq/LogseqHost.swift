#if os(macOS)
import AppKit
import Combine
import NativeLogseqUI

@MainActor final class LogseqHost: ObservableObject {
    let state: AppState
    let session: EditorSession
    @Published private(set) var isTransitioning = false
    @Published private(set) var ownerID: UUID?
    @Published var commandsActive = false
    weak var ownerWindow: NSWindow?
    private var restored = false
    private var observers: Set<AnyCancellable> = []
    private let initialURL: URL?

    init(preferences: UserDefaults? = nil, initialURL: URL? = nil) {
        let state = AppState(preferences: preferences ?? Self.preferences())
        self.state = state
        self.session = EditorSession(state: state, includesContinue: false, includesPlain: true, synchronizesTaskHierarchy: true)
        self.initialURL = initialURL ?? Self.fixtureURL()
        state.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &observers)
        session.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &observers)
    }
    static func preferences() -> UserDefaults {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--uitest-store"), args.count > i + 1 {
            return UserDefaults(suiteName: "logseq-uitest-" + args[i + 1])!
        }
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return UserDefaults(suiteName: "logseq-unit-host-" + UUID().uuidString)!
        }
        #endif
        return UserDefaults(suiteName: "com.hyunho.TodayRoutineMac.logseq")!
    }
    static func fixtureURL() -> URL? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--uitest-store"), let i = args.firstIndex(of: "--uitest-logseq"), args.count > i + 1 {
            return URL(fileURLWithPath: args[i + 1])
        }
        #endif
        return nil
    }
    var pageStack: [String] {
        if let file = state.markdownFile { return ["Logseq", file.url.lastPathComponent] }
        if state.showsJournals { return ["Logseq", "저널 모아보기"] }
        if let page = state.currentPage { return ["Logseq", page.title] }
        return ["Logseq"]
    }
    func restoreOnce() async {
        guard !restored else { return }
        restored = true
        state.isBusy = true
        defer { state.isBusy = false }
        do {
            if let initialURL { try await state.openMarkdown(at: initialURL) }
            else { try await state.restoreWorkspace() }
        } catch { state.errorMessage = "마지막 노트를 열지 못했습니다. 파일이나 그래프를 다시 선택해 주세요.\n" + error.localizedDescription }
    }
    func prepareToLeave() async -> Bool {
        guard !isTransitioning else { return false }
        isTransitioning = true
        defer { isTransitioning = false }
        do { try await session.prepareToLeave(); return true }
        catch { state.errorMessage = error.localizedDescription; return false }
    }
    func claimWindow(_ window: NSWindow, id: UUID) async {
        guard ownerID != id else { return }
        if ownerID != nil {
            guard await prepareToLeave() else { ownerWindow?.makeKeyAndOrderFront(nil); return }
            session.resignEditorFocus()
        }
        ownerWindow = window
        ownerID = id
    }
    func releaseWindow(id: UUID) {
        guard ownerID == id else { return }
        ownerID = nil; ownerWindow = nil; commandsActive = false
    }
}
#endif
