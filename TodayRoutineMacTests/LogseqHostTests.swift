import XCTest
import AppKit
import NativeLogseqUI
@testable import TodayRoutineMac

@MainActor final class LogseqHostTests: XCTestCase {
    func testTodayDocumentAppliesWhenLeavingLogseqTab() async throws {
        let store = RoutineStore(container: try PersistenceFactory.make(inMemory: true))
        var routine = RoutineDraft(); routine.name = "탭 이동 테스트"; routine.minute = 540
        try store.upsertRoutine(routine)
        let day = RoutineRules.dayKey(Date())
        var (document, revision) = try store.openTodayDocument(day: day)
        document.blocks[0].text = "DONE 09:00 탭 이동 테스트"
        _ = try store.saveTodayDocumentDraft(document, expectedRevision: revision)
        let model = AppModel(); model.store = store
        model.selectedTab = "Logseq"
        let host = TodayDocumentHost(); host.active = true
        await host.open(day: day, model: model)
        XCTAssertTrue(host.commandsActive)
        XCTAssertTrue(host.needsApply)
        let changed = await model.selectTab("오늘")
        XCTAssertTrue(changed)
        XCTAssertFalse(host.commandsActive)
        XCTAssertFalse(host.needsApply)
        XCTAssertEqual(try store.loadSnapshot().records.first?.status, .completed)
    }

    func fixture() throws -> (URL, LogseqHost) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let name = "logseq-host-test-" + UUID().uuidString
        let prefs = UserDefaults(suiteName: name)!
        addTeardownBlock { prefs.removePersistentDomain(forName: name) }
        let url = root.appendingPathComponent("note.md")
        try "original".write(to: url, atomically: true, encoding: .utf8)
        return (url, LogseqHost(preferences: prefs))
    }
    func testRestoreOnceDoesNotResetEdits() async throws {
        let (url, host) = try fixture()
        try await host.state.openMarkdown(at: url)
        await host.restoreOnce()
        host.state.updateMarkdown("pending")
        await host.restoreOnce()
        XCTAssertEqual(host.state.markdownFile?.text, "pending")
        XCTAssertEqual(try String(contentsOf: url), "original")
    }
    func testFailedSaveKeepsEdits() async throws {
        let (url, host) = try fixture()
        try await host.state.openMarkdown(at: url)
        host.state.updateMarkdown("local")
        try "external".write(to: url, atomically: true, encoding: .utf8)
        let allowed = await host.prepareToLeave()
        XCTAssertFalse(allowed)
        XCTAssertEqual(host.state.markdownFile?.text, "local")
        XCTAssertEqual(try String(contentsOf: url), "external")
        XCTAssertNotNil(host.state.errorMessage)
    }
    func testBusySessionRejectsTransition() async throws {
        let (_, host) = try fixture()
        host.state.isBusy = true
        let allowed = await host.prepareToLeave()
        XCTAssertFalse(allowed)
        XCTAssertFalse(host.isTransitioning)
    }
    func testQuitFromOtherTabFlushesDirtyDocument() async throws {
        let (url, host) = try fixture()
        try await host.state.openMarkdown(at: url)
        host.state.updateMarkdown("saved on quit")
        let coordinator = LogseqCloseCoordinator(host: host)
        let allowed = await coordinator.prepareToClose()
        XCTAssertTrue(allowed)
        XCTAssertEqual(try String(contentsOf: url), "saved on quit")
    }
    func testCancelQuitRetainsEdits() async throws {
        let (url, host) = try fixture()
        try await host.state.openMarkdown(at: url)
        host.state.updateMarkdown("local")
        try "external".write(to: url, atomically: true, encoding: .utf8)
        let coordinator = LogseqCloseCoordinator(host: host, chooseRecovery: { _ in .cancel })
        let allowed = await coordinator.prepareToClose()
        XCTAssertFalse(allowed)
        XCTAssertEqual(host.state.markdownFile?.text, "local")
    }
    func testFailedCopyDoesNotClose() async throws {
        let (url, host) = try fixture()
        try await host.state.openMarkdown(at: url)
        host.state.updateMarkdown("local")
        try "external".write(to: url, atomically: true, encoding: .utf8)
        let coordinator = LogseqCloseCoordinator(host: host, chooseRecovery: { _ in .saveCopy(url) }, confirmCopy: { true })
        let allowed = await coordinator.prepareToClose()
        XCTAssertFalse(allowed)
        XCTAssertEqual(try String(contentsOf: url), "external")
        XCTAssertTrue(host.state.hasUnsavedChanges)
    }
    func testFailedSaveKeepsSelectedTabAndFocusState() async throws {
        let (url, _) = try fixture()
        let model = AppModel()
        try await model.logseq.state.openMarkdown(at: url)
        model.selectedTab = "Logseq"
        model.logseq.state.updateMarkdown("local")
        try "external".write(to: url, atomically: true, encoding: .utf8)
        let changed = await model.selectTab("오늘")
        XCTAssertFalse(changed)
        XCTAssertEqual(model.selectedTab, "Logseq")
        let focused = await model.setFocusSession(FocusSession(target: .routine(UUID()), title: "focus", day: Date()))
        XCTAssertFalse(focused)
        XCTAssertNil(model.focusSession)
        XCTAssertEqual(model.logseq.state.markdownFile?.text, "local")
    }
    func testSuccessfulTabChangeSavesBeforeSelection() async throws {
        let (url, _) = try fixture()
        let model = AppModel()
        try await model.logseq.state.openMarkdown(at: url)
        model.selectedTab = "Logseq"
        model.logseq.state.updateMarkdown("new")
        let changed = await model.selectTab("오늘")
        XCTAssertTrue(changed)
        XCTAssertEqual(model.selectedTab, "오늘")
        XCTAssertEqual(try String(contentsOf: url), "new")
    }

    func testRecoveryKeepsEditingLockedUntilCopyFinishes() async throws {
        let (url, host) = try fixture()
        try await host.state.openMarkdown(at: url)
        host.state.updateMarkdown("local")
        try "external".write(to: url, atomically: true, encoding: .utf8)
        let copy = url.deletingLastPathComponent().appendingPathComponent("copy.md")
        var resume: CheckedContinuation<Void, Never>?
        let coordinator = LogseqCloseCoordinator(host: host, chooseRecovery: { _ in .saveCopy(copy) }, confirmCopy: { true }, exportCopy: { destination in
            await withCheckedContinuation { resume = $0 }
            try await host.state.exportCurrentPage(to: destination)
        })
        let closing = Task { await coordinator.prepareToClose() }
        while resume == nil { await Task.yield() }
        XCTAssertTrue(host.state.isBusy, "Editor must stay disabled while exporting")
        let canLeave = await host.prepareToLeave()
        XCTAssertFalse(canLeave)
        let duplicate = await coordinator.prepareToClose()
        XCTAssertFalse(duplicate)
        resume?.resume()
        let allowed = await closing.value
        XCTAssertTrue(allowed)
        XCTAssertFalse(host.state.isBusy)
        XCTAssertEqual(try String(contentsOf: copy), "local")
    }

}


@MainActor final class SettingsLiveUpdateTests: XCTestCase {
    func testExternalLayoutEditsApplyWithoutManualReloadAndRecover() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel()
        let store = RoutineStore(container: try PersistenceFactory.make(inMemory: true))
        let sync = SyncCoordinator(store: store, automatic: false)
        await sync.connect(url: root, persist: false)
        model.sync = sync
        defer { sync.disconnect() }
        let url = try XCTUnwrap(sync.listLayoutFileURL)
        let monitor = Task { await model.monitorListLayoutChanges() }
        defer { monitor.cancel() }
        try Data("{\"itemSpacing\":20}".utf8).write(to: url, options: .atomic)
        for _ in 0..<40 {
            if model.listLayout.itemSpacing == 20 { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(model.listLayout.itemSpacing, 20)
        try Data("{unfinished".utf8).write(to: url, options: .atomic)
        try await Task.sleep(for: .seconds(2.2))
        XCTAssertEqual(model.listLayout.itemSpacing, 20)
        try Data("{\"itemSpacing\":32}".utf8).write(to: url, options: .atomic)
        for _ in 0..<40 {
            if model.listLayout.itemSpacing == 32 { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(model.listLayout.itemSpacing, 32)
    }
}


@MainActor final class SettingsWindowSizingTests: XCTestCase {
    func testPanelRestoresUserResizedContentDimensions() async throws {
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 440, height: 600),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        let view = LogseqWindowView()
        let host = LogseqHost()
        let id = UUID()
        let close = LogseqCloseCoordinator(host: host)
        view.configure(host: host, id: id, active: false, close: close)
        window.contentView = view
        try await Task.sleep(for: .milliseconds(100))
        window.setContentSize(NSSize(width: 470, height: 620))
        view.windowDidEndLiveResize(Notification(name: NSWindow.didEndLiveResizeNotification, object: window))
        view.configure(host: host, id: id, active: false, close: close, settingsVisible: true)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).width, 858, accuracy: 1)
        view.configure(host: host, id: id, active: false, close: close, settingsVisible: false)
        try await Task.sleep(for: .milliseconds(100))
        let restored = window.contentRect(forFrameRect: window.frame).size
        XCTAssertEqual(restored.width, 470, accuracy: 1)
        XCTAssertEqual(restored.height, 620, accuracy: 1)
        window.contentView = nil
        window.delegate = nil
    }
}


extension SettingsWindowSizingTests {
    func testChangingPanelWidthPreservesMainContentAndReopensAtNewWidth() async throws {
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 440, height: 600),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        let view = LogseqWindowView()
        let host = LogseqHost()
        let id = UUID()
        let close = LogseqCloseCoordinator(host: host)
        view.configure(host: host, id: id, active: false, close: close)
        window.contentView = view
        defer { window.contentView = nil; window.delegate = nil }
        try await Task.sleep(for: .milliseconds(100))
        view.configure(host: host, id: id, active: false, close: close, settingsVisible: true, panelWidth: 380)
        try await Task.sleep(for: .milliseconds(100))
        if let screen = window.screen ?? NSScreen.main {
            window.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - window.frame.width, y: window.frame.minY))
        }
        let originalRight = window.frame.maxX
        window.contentMaxSize.width = 2000
        window.setContentSize(NSSize(width: 908, height: 600))
        view.configure(host: host, id: id, active: false, close: close, settingsVisible: true, panelWidth: 540, resizeAnchorX: originalRight)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).width, 988, accuracy: 1)
        XCTAssertEqual(window.frame.maxX, originalRight, accuracy: 1)
        view.configure(host: host, id: id, active: false, close: close, settingsVisible: false, panelWidth: 540)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).width, 440, accuracy: 1)
        view.configure(host: host, id: id, active: false, close: close, settingsVisible: true, panelWidth: 540)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).width, 988, accuracy: 1)
    }
}


extension SettingsWindowSizingTests {
    func testAccessibleResizeRespectsScreenLimit() {
        let handle = AuxiliaryPanelResizeView()
        var result: CGFloat = 0
        handle.panelWidth = 540
        handle.maximumWidth = 550
        handle.onChange = { width, _ in result = width }
        XCTAssertTrue(handle.accessibilityPerformIncrement())
        XCTAssertEqual(result, 550)
        XCTAssertTrue(handle.accessibilityPerformDecrement())
        XCTAssertEqual(result, 520)
        handle.panelWidth = 320
        XCTAssertTrue(handle.accessibilityPerformDecrement())
        XCTAssertEqual(result, 320)
    }
}
