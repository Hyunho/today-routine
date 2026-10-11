#if os(macOS)
import AppKit

@MainActor final class TodayRoutineMacDelegate: NSObject, NSApplicationDelegate {
    var closeCoordinator: LogseqCloseCoordinator?
    private var terminating = false
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let closeCoordinator else { return .terminateNow }
        guard !terminating else { return .terminateCancel }
        terminating = true
        Task {
            let allowed = await closeCoordinator.prepareToClose()
            terminating = false
            sender.reply(toApplicationShouldTerminate: allowed)
        }
        return .terminateLater
    }
}
#endif
