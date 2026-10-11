#if os(macOS)
import SwiftUI
import Combine
import NativeLogseqCore
import NativeLogseqUI

@MainActor final class TodayDocumentPersistence: GraphPersistence {
    let store: RoutineStore
    var document: TodayDocument
    var revision: Int
    private var fingerprint: String
    let url: URL
    init(store: RoutineStore, day: String) throws {
        self.store = store
        (document, revision) = try store.openTodayDocument(day: day)
        fingerprint = UUID().uuidString
        url = URL(fileURLWithPath: "/today-documents/\(day).md")
    }
    static func native(_ node: TodayDocumentBlock) -> NativeLogseqCore.Block {
        NativeLogseqCore.Block(id: node.id, text: node.text, children: node.children.map(native))
    }
    static func local(_ node: NativeLogseqCore.Block) -> TodayDocumentBlock {
        TodayDocumentBlock(id: node.id, text: node.text, children: node.children.map(local))
    }
    private var stored: StoredPage {
        StoredPage(page: Page(id: document.id, title: document.dayKey, kind: .journal(day: document.dayKey), blocks: document.blocks.map(Self.native)), url: url, fingerprint: fingerprint)
    }
    func load() async throws -> GraphSnapshot { GraphSnapshot(pages: [stored], issues: []) }
    func save(_ page: Page, expectedFingerprint: String?) async throws -> StoredPage {
        guard page.id == document.id, expectedFingerprint == fingerprint else { throw GraphStoreError.conflict(url) }
        var next = document; next.blocks = page.blocks.map(Self.local)
        revision = try store.saveTodayDocumentDraft(next, expectedRevision: revision)
        document.blocks = next.blocks
        fingerprint = UUID().uuidString
        return stored
    }
    func apply() throws {
        (document, revision) = try store.applyTodayDocument(day: document.dayKey, expectedRevision: revision)
    }
}

@MainActor final class TodayDocumentHost: ObservableObject {
    let id = UUID()
    let state: AppState
    let session: EditorSession
    @Published var error: String?
    @Published var active = false
    @Published private(set) var busy = false
    @Published private(set) var day: String?
    private var persistence: TodayDocumentPersistence?
    private weak var model: AppModel?
    private var observers: Set<AnyCancellable> = []
    var commandsActive: Bool { active }
    var needsApply: Bool { state.hasUnsavedChanges || persistence?.document.needsApply == true }
    init() {
        state = AppState(preferences: UserDefaults(suiteName: "com.hyunho.TodayRoutine.today-document")!)
        session = EditorSession(state: state, includesContinue: false, includesPlain: false, synchronizesTaskHierarchy: true)
        state.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &observers)
        session.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &observers)
    }
    func open(day: String, model: AppModel) async {
        guard !busy, let store = model.store else { return }
        self.model = model; model.todayDocumentHosts[id] = self
        if self.day != nil, !(await flushDraft()) { return }
        // Reopening the same dirty document keeps selection and undo history intact.
        if self.day == day, persistence?.document.needsApply == true { return }
        busy = true; defer { busy = false }
        do {
            let adapter = try TodayDocumentPersistence(store: store, day: day)
            if self.day == day, adapter.document == persistence?.document, adapter.revision == persistence?.revision { return }
            try await state.openEmbedded(store: adapter, root: adapter.url.deletingLastPathComponent())
            persistence = adapter; self.day = day; error = nil
        } catch { self.error = error.localizedDescription }
    }
    func flushDraft() async -> Bool {
        guard persistence != nil else { return true }
        do { try await session.prepareToLeave(); return true }
        catch { self.error = error.localizedDescription; model?.error = error.localizedDescription; return false }
    }
    func apply() async -> Bool {
        guard !busy else { return false }
        busy = true; defer { busy = false }
        guard await flushDraft() else { return false }
        guard let persistence, let model else { return true }
        if !persistence.document.needsApply { error = nil; return true }
        let success = model.perform { _ in try persistence.apply() }
        error = success ? nil : model.error
        if success {
            do {
                try session.reconcileEmbeddedPage(Page(id: persistence.document.id, title: persistence.document.dayKey,
                    kind: .journal(day: persistence.document.dayKey), blocks: persistence.document.blocks.map(TodayDocumentPersistence.native)))
            } catch { self.error = error.localizedDescription; return false }
        }
        objectWillChange.send()
        return success
    }
    func reloadSource() async {
        guard !busy, let persistence, let model, let store = model.store else { return }
        busy = true; defer { busy = false }
        do {
            try store.discardTodayDocumentDraft(day: persistence.document.dayKey, expectedRevision: persistence.revision)
            let next = try TodayDocumentPersistence(store: store, day: persistence.document.dayKey)
            try await state.openEmbedded(store: next, root: next.url.deletingLastPathComponent(), discardingChanges: true)
            self.persistence = next; error = nil
        } catch { self.error = error.localizedDescription }
    }
    func exportCopy() {
        guard session.commitComposition() else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "\(day ?? "오늘")-편집사본.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { do { try await state.exportCurrentPage(to: url) } catch { self.error = error.localizedDescription } }
    }
}

private struct TodayDocumentFocusKey: FocusedValueKey { typealias Value = TodayDocumentHost }
extension FocusedValues {
    var todayDocument: TodayDocumentHost? {
        get { self[TodayDocumentFocusKey.self] }
        set { self[TodayDocumentFocusKey.self] = newValue }
    }
}
struct TodayDocumentCommands: Commands {
    @FocusedValue(\.todayDocument) private var host
    var body: some Commands {
        if let host, host.commandsActive {
            CommandGroup(replacing: .undoRedo) {
                Button("실행 취소") { if host.session.commitComposition() { host.session.undoManager.undo() } }.keyboardShortcut("z").disabled(!host.session.undoManager.canUndo)
                Button("다시 실행") { if host.session.commitComposition() { host.session.undoManager.redo() } }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!host.session.undoManager.canRedo)
            }
            CommandGroup(replacing: .saveItem) {
                Button("오늘 타임라인·시간 블록에 반영") { Task { _ = await host.apply() } }.keyboardShortcut("s").disabled(host.busy)
            }
            CommandGroup(after: .textEditing) {
                Button("블록 접기") { host.session.foldCurrentBlock(collapsed: true) }.keyboardShortcut(.upArrow, modifiers: .command)
                Button("블록 펼치기") { host.session.foldCurrentBlock(collapsed: false) }.keyboardShortcut(.downArrow, modifiers: .command)
                Button("블록 위로 이동") { host.session.moveBullet(up: true) }.keyboardShortcut(.upArrow, modifiers: [.command, .shift])
                Button("블록 아래로 이동") { host.session.moveBullet(up: false) }.keyboardShortcut(.downArrow, modifiers: [.command, .shift])
                Button("할 일 상태 전환") { host.session.toggleTask() }.keyboardShortcut(.return, modifiers: .command)
            }
        }
    }
}

struct TodayDocumentEditorView: View {
    @ObservedObject var host: TodayDocumentHost
    let model: AppModel
    let day: String
    @State private var confirmsReload = false
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(host.needsApply ? "문서 초안 · 반영 대기" : "타임라인·시간 블록 반영됨").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("사본 저장") { host.exportCopy() }
                    Button("원본 다시 읽기") { confirmsReload = true }.disabled(host.busy)
                    Button("오늘에 반영") { Task { _ = await host.apply() } }.disabled(host.busy)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
            if let error = host.error {
                Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled).padding(10)
            }
            if host.state.hasUnsavedChanges { Text("문서 초안을 저장하고 있습니다. 저장 오류 시 사본으로 보관해 주세요.").font(.caption).foregroundStyle(.secondary) }
            EmbeddedPageEditor(state: host.state, session: host.session)
        }
        .focusedValue(\.todayDocument, host)
        .task(id: day) { host.active = true; await host.open(day: day, model: model) }
        .onDisappear { host.active = false }
        .alert("저장된 원본으로 다시 불러올까요?", isPresented: $confirmsReload) {
            Button("취소", role: .cancel) { }
            Button("다시 읽기", role: .destructive) { Task { await host.reloadSource() } }
        } message: { Text("아직 반영하지 않은 문서 편집과 실행 취소 기록이 사라집니다. 필요한 내용은 먼저 사본으로 저장해 주세요.") }
    }
}
#endif
