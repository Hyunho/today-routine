#if os(macOS)
import AppKit

@MainActor final class LogseqCloseCoordinator {
    enum Recovery { case retry, saveCopy(URL), cancel }
    private let host: LogseqHost
    private let chooseRecovery: @MainActor (String) -> Recovery
    private let confirmCopy: @MainActor () -> Bool
    private let exportCopy: @MainActor (URL) async throws -> Void
    private var closing = false
    private let prepareAdditional: @MainActor () async -> Bool
    init(host: LogseqHost, chooseRecovery: @escaping @MainActor (String) -> Recovery = LogseqCloseCoordinator.recoveryAlert,
         confirmCopy: @escaping @MainActor () -> Bool = LogseqCloseCoordinator.copyConfirmation,
         exportCopy: (@MainActor (URL) async throws -> Void)? = nil,
         prepareAdditional: @escaping @MainActor () async -> Bool = { true }) {
        self.host = host; self.chooseRecovery = chooseRecovery; self.confirmCopy = confirmCopy
        self.exportCopy = exportCopy ?? { try await host.state.exportCurrentPage(to: $0) }
        self.prepareAdditional = prepareAdditional
    }
    func prepareToClose() async -> Bool {
        guard !closing, !host.isTransitioning, !host.state.isBusy else { return false }
        closing = true
        defer { closing = false; host.state.isBusy = false }
        guard await prepareAdditional() else { return false }
        while true {
            if await host.prepareToLeave() { return true }
            let message = host.state.errorMessage ?? "편집 내용을 저장하지 못했습니다."
            // Recovery uses its own dialog instead of stacking the workspace alert.
            host.state.errorMessage = nil
            host.state.isBusy = true
            switch chooseRecovery(message) {
            case .retry: host.state.isBusy = false; continue
            case .cancel: return false
            case .saveCopy(let url):
                guard host.session.commitComposition() else { return false }
                do { try await exportCopy(url); return confirmCopy() }
                catch { host.state.errorMessage = error.localizedDescription; return false }
            }
        }
    }
    static func recoveryAlert(_ message: String) -> Recovery {
        let alert = NSAlert()
        alert.messageText = "편집 내용을 저장하지 못했습니다"
        alert.informativeText = message
        alert.addButton(withTitle: "재시도")
        alert.addButton(withTitle: "사본 저장 후 닫기")
        alert.addButton(withTitle: "취소")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .retry
        case .alertSecondButtonReturn:
            let panel = NSSavePanel(); panel.nameFieldStringValue = "노트 사본.md"
            guard panel.runModal() == .OK, let url = panel.url else { return .cancel }
            return .saveCopy(url)
        default: return .cancel
        }
    }
    static func copyConfirmation() -> Bool {
        let alert = NSAlert(); alert.messageText = "사본을 저장했습니다. 닫을까요?"
        alert.informativeText = "원본에 저장되지 않은 내용이 사본에 보관됩니다."
        alert.addButton(withTitle: "닫기"); alert.addButton(withTitle: "돌아가기")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
#endif
