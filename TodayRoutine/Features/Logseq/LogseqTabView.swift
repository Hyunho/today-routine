#if os(macOS)
import SwiftUI
import NativeLogseqUI

struct LogseqTabView: View {
    @ObservedObject var host: LogseqHost
    let windowID: UUID
    let isActive: Bool
    var body: some View {
        Group {
            if host.ownerID == windowID {
                WorkspaceView(state: host.state, session: host.session, minimumWidth: 0)
            } else {
                ContentUnavailableView {
                    Label("Logseq", systemImage: "doc.text")
                } description: {
                    Text("편집 중인 창에서 노트를 이어 쓸 수 있습니다.")
                } actions: {
                    Button("편집 창으로 이동") { host.ownerWindow?.makeKeyAndOrderFront(nil) }
                }
            }
        }
        .accessibilityIdentifier("logseq-workspace")
        .task(id: isActive) { if isActive { await host.restoreOnce() } }
        .pageStack(host.pageStack)
    }
}
struct LogseqHostCommands: Commands {
    @ObservedObject var host: LogseqHost
    var body: some Commands {
        WorkspaceCommands(state: host.state, session: host.session, isActive: host.commandsActive)
    }
}
#endif
