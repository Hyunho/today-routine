import SwiftUI

extension AppModel {
    @discardableResult func selectTab(_ name: String) async -> Bool {
        guard name != selectedTab else { return true }
        #if os(macOS)
        if selectedTab == "Logseq" {
            for host in todayDocumentHosts.values where host.active {
                guard await host.apply() else { return false }
            }
        }
        guard !logseq.isTransitioning else { return false }
        if selectedTab == "Logseq" {
            guard await logseq.prepareToLeave() else { return false }
            logseq.session.resignEditorFocus()
        }
        logseq.commandsActive = false
        #endif
        selectedTab = name
        return true
    }
    @discardableResult func setFocusSession(_ next: FocusSession?) async -> Bool {
        #if os(macOS)
        if next != nil {
            for host in todayDocumentHosts.values where host.active {
                guard await host.apply() else { return false }
            }
        }
        guard !logseq.isTransitioning else { return false }
        if next != nil, selectedTab == "Logseq" {
            guard await logseq.prepareToLeave() else { return false }
            logseq.session.resignEditorFocus()
        }
        logseq.commandsActive = false
        #endif
        focusSession = next
        return true
    }
    var tabSelection: Binding<String> {
        Binding(get: { self.selectedTab }, set: { name in Task { await self.selectTab(name) } })
    }
}
