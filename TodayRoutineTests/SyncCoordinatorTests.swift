import XCTest
import Observation
@testable import RoutineCore
final class SyncCoordinatorTests: XCTestCase {
    @MainActor func testTwoStoresCSVUndoAndNoExportLoop() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let a = RoutineStore(container:try PersistenceFactory.make(inMemory:true)), b = RoutineStore(container:try PersistenceFactory.make(inMemory:true))
        var draft = RoutineDraft(); draft.name = "아침"; draft.steps = [StepDraft(name:"물"),StepDraft(name:"독서")]; try a.upsertRoutine(draft)
        let x = SyncCoordinator(store:a,automatic:false), y = SyncCoordinator(store:b,automatic:false)
        await x.connect(url:root,persist:false); await y.connect(url:root,persist:false)
        XCTAssertEqual(try b.loadSnapshot().routines.count,1)
        guard let csv = x.latestCSV.first?.url else { return XCTFail("export missing") }
        var rows = try CSVCodec.decode(Data(contentsOf:csv)); rows[1][1] = "TRUE"
        try CSVCodec.encode(rows).write(to:csv)
        await y.refresh(); await x.refresh()
        XCTAssertEqual(try a.loadSnapshot().records.first?.completedStepIDs.count,1)
        let before = try StoreSyncAdapter(store:a).events().count
        await x.refresh(); await y.refresh()
        XCTAssertEqual(try StoreSyncAdapter(store:a).events().count,before)
        rows[1][1] = "FALSE"; try CSVCodec.encode(rows).write(to:csv)
        await y.refresh(); await x.refresh()
        XCTAssertEqual(try a.loadSnapshot().records.first?.completedStepIDs.count,0)
        try a.toggleStep(routineID:draft.id,stepID:draft.steps[1].id,date:Date())
        await x.refresh(); await y.refresh()
        XCTAssertEqual(try b.loadSnapshot().records.first?.completedStepIDs,[draft.steps[1].id])
        x.disconnect(); y.disconnect()
        XCTAssertEqual(try a.loadSnapshot().routines.count,1)
        XCTAssertTrue(FileManager.default.fileExists(atPath:csv.path))
    }
}
extension SyncCoordinatorTests {
    @MainActor func testConflictingCSVNeedsChoiceAndDamagedFolderKeepsData() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let store = RoutineStore(container:try PersistenceFactory.make(inMemory:true))
        var draft = RoutineDraft(); draft.name = "충돌"; draft.steps = [StepDraft(name:"물")]; try store.upsertRoutine(draft)
        let sync = SyncCoordinator(store:store,automatic:false); await sync.connect(url:root,persist:false)
        let csv = try XCTUnwrap(sync.latestCSV.first?.url)
        try store.toggleStep(routineID:draft.id,stepID:draft.steps[0].id,date:Date())
        try store.toggleStep(routineID:draft.id,stepID:draft.steps[0].id,date:Date())
        var rows = try CSVCodec.decode(Data(contentsOf:csv)); rows[1][1] = "TRUE"; try CSVCodec.encode(rows).write(to:csv)
        await sync.refresh(); XCTAssertEqual(sync.conflicts.count,1)
        await sync.resolve(try XCTUnwrap(sync.conflicts.first),useCSV:false)
        XCTAssertTrue(sync.conflicts.isEmpty); XCTAssertEqual(try store.loadSnapshot().records.first?.status,.pending)
        await sync.refresh(); XCTAssertTrue(sync.conflicts.isEmpty)
        let manifest = root.appendingPathComponent("space.json"), data = try Data(contentsOf:manifest)
        try Data("broken".utf8).write(to:manifest)
        try store.toggleStep(routineID:draft.id,stepID:draft.steps[0].id,date:Date())
        await sync.refresh(); XCTAssertGreaterThan(sync.pendingCount,0)
        XCTAssertEqual(try store.loadSnapshot().records.first?.status,.completed)
        try data.write(to:manifest); await sync.refresh(); XCTAssertEqual(sync.pendingCount,0)
        sync.disconnect()
    }
}

extension SyncCoordinatorTests {
    @MainActor func testAutomaticSyncSettlesWithoutChanges() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = RoutineStore(container: try PersistenceFactory.make(inMemory: true))
        var draft = RoutineDraft(); draft.name = "자동 동기화 안정화"
        try store.upsertRoutine(draft)
        let sync = SyncCoordinator(store: store)
        defer { sync.disconnect(); try? FileManager.default.removeItem(at: root) }
        await sync.connect(url: root, persist: false)
        try await Task.sleep(for: .seconds(3))
        let settled = try XCTUnwrap(sync.lastChecked)
        try await Task.sleep(for: .seconds(2))
        XCTAssertEqual(sync.lastChecked, settled, "변경 없는 CSV를 확인하는 작업이 다시 쓰기 알림을 발생시키면 안 됩니다")
        XCTAssertEqual(try store.loadSnapshot().routines.count, 1)
    }
}

extension SyncCoordinatorTests {
    @MainActor func testIdleRefreshKeepsExportsAndStillAppliesLaterLocalAndOldCSVEdits() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = RoutineStore(container: try PersistenceFactory.make(inMemory: true))
        var draft = RoutineDraft(); draft.name = "증분 확인"; draft.steps = [StepDraft(name: "물")]
        try store.upsertRoutine(draft)
        let sync = SyncCoordinator(store: store, automatic: false)
        defer { sync.disconnect(); try? FileManager.default.removeItem(at: root) }
        await sync.connect(url: root, persist: false)
        let oldCSV = try XCTUnwrap(sync.latestCSV.first?.url)
        await sync.refresh(); await sync.refresh()
        let invalidations = ExportInvalidations()
        withObservationTracking { _ = sync.latestCSV } onChange: { invalidations.record() }
        await sync.refresh()
        XCTAssertEqual(invalidations.count, 0, "Idle sync must not regenerate or replace export links")
        draft.name = "이름 변경"
        try store.upsertRoutine(draft)
        await sync.refresh()
        XCTAssertEqual(sync.latestCSV.first?.name, "이름 변경")
        XCTAssertNotEqual(sync.latestCSV.first?.url, oldCSV)
        var rows = try CSVCodec.decode(Data(contentsOf: oldCSV)); rows[1][1] = "TRUE"
        try CSVCodec.encode(rows).write(to: oldCSV)
        await sync.refresh()
        XCTAssertEqual(try store.loadSnapshot().records.first?.completedStepIDs, [draft.steps[0].id])
    }
}

private final class ExportInvalidations: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    func record() { lock.lock(); defer { lock.unlock() }; value += 1 }
}

extension SyncCoordinatorTests {
    @MainActor func testNotificationStormDoesNotStarveRefreshAndInactiveStopsScheduling() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = RoutineStore(container: try PersistenceFactory.make(inMemory: true))
        let sync = SyncCoordinator(store: store)
        defer { sync.disconnect(); try? FileManager.default.removeItem(at: root) }
        await sync.connect(url: root, persist: false)
        try await Task.sleep(for: .seconds(1))
        let before = try XCTUnwrap(sync.lastChecked)
        for _ in 0..<30 {
            sync.localDataDidChange()
            try await Task.sleep(for: .milliseconds(40))
        }
        XCTAssertGreaterThan(try XCTUnwrap(sync.lastChecked), before, "Continuous notifications must not postpone every refresh")
        sync.setActive(false)
        try await Task.sleep(for: .milliseconds(100))
        let stopped = sync.lastChecked
        sync.localDataDidChange()
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertEqual(sync.lastChecked, stopped)
        sync.setActive(true)
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertGreaterThan(try XCTUnwrap(sync.lastChecked), try XCTUnwrap(stopped))
    }

    @MainActor func testIdleRefreshPreservesConflictsAndCSVWarnings() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = RoutineStore(container: try PersistenceFactory.make(inMemory: true))
        var draft = RoutineDraft(); draft.name = "충돌 유지"; draft.steps = [StepDraft(name: "물")]
        try store.upsertRoutine(draft)
        let sync = SyncCoordinator(store: store, automatic: false)
        defer { sync.disconnect(); try? FileManager.default.removeItem(at: root) }
        await sync.connect(url: root, persist: false)
        let csv = try XCTUnwrap(sync.latestCSV.first?.url)
        try store.toggleStep(routineID: draft.id, stepID: draft.steps[0].id, date: Date())
        try store.toggleStep(routineID: draft.id, stepID: draft.steps[0].id, date: Date())
        var rows = try CSVCodec.decode(Data(contentsOf: csv)); rows[1][1] = "TRUE"
        try CSVCodec.encode(rows).write(to: csv)
        await sync.refresh(); await sync.refresh()
        let conflicts = sync.conflicts
        XCTAssertEqual(conflicts.count, 1)
        await sync.refresh()
        XCTAssertEqual(sync.conflicts, conflicts)
        try Data("bad header\nbad row".utf8).write(to: csv)
        await sync.refresh()
        XCTAssertTrue(sync.conflicts.isEmpty, "Malformed replacement must not leave obsolete actionable conflicts")
        try CSVCodec.encode(rows).write(to: csv)
        await sync.refresh()
        XCTAssertEqual(sync.conflicts.count, 1)
        await sync.resolve(try XCTUnwrap(sync.conflicts.first), useCSV: false)
        XCTAssertTrue(sync.conflicts.isEmpty)
        try Data("bad header\nbad row".utf8).write(to: csv)
        await sync.refresh()
        let warning = sync.status
        XCTAssertTrue(warning.hasPrefix("CSV 확인 필요:"))
        await sync.refresh()
        XCTAssertEqual(sync.status, warning)
        try CSVCodec.encode(rows).write(to: csv)
        await sync.refresh()
        XCTAssertFalse(sync.status.hasPrefix("CSV 확인 필요:"))
    }
}

extension SyncCoordinatorTests {
    @MainActor func testPendingHistoricalCSVDoesNotBlockOtherCSVAndResumesAfterDownload() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = RoutineStore(container: try PersistenceFactory.make(inMemory: true))
        var a = RoutineDraft(); a.name = "다운로드 대기"; a.steps = [StepDraft(name: "물")]
        var b = RoutineDraft(); b.name = "먼저 적용"; b.steps = [StepDraft(name: "독서")]
        try store.upsertRoutine(a); try store.upsertRoutine(b)
        let sync = SyncCoordinator(store: store, automatic: false)
        defer { sync.disconnect(); try? FileManager.default.removeItem(at: root) }
        await sync.connect(url: root, persist: false)
        let missingCSV = try XCTUnwrap(sync.latestCSV.first { $0.id == a.id }?.url)
        let readyCSV = try XCTUnwrap(sync.latestCSV.first { $0.id == b.id }?.url)
        let baseline = missingCSV.deletingLastPathComponent().appendingPathComponent("baseline.json")
        let saved = try Data(contentsOf: baseline)
        try FileManager.default.removeItem(at: baseline)
        let placeholder = baseline.deletingLastPathComponent().appendingPathComponent(".baseline.json.icloud")
        try Data().write(to: placeholder)
        var rows = try CSVCodec.decode(Data(contentsOf: readyCSV)); rows[1][1] = "TRUE"
        try CSVCodec.encode(rows).write(to: readyCSV)
        await sync.refresh(manual: true)
        XCTAssertEqual(try store.loadSnapshot().records.first { $0.routineID == b.id }?.completedStepIDs, [b.steps[0].id])
        XCTAssertTrue(sync.status.contains("다운로드 대기"))
        try FileManager.default.removeItem(at: placeholder); try saved.write(to: baseline)
        await sync.refresh(manual: true)
        XCTAssertFalse(sync.status.contains("다운로드 대기"))
        XCTAssertEqual(try store.loadSnapshot().routines.count, 2)
    }
}

extension SyncCoordinatorTests {
    @MainActor func testDownloadBackoffSurvivesReactivationAndNotifications() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = RoutineStore(container: try PersistenceFactory.make(inMemory: true))
        var draft = RoutineDraft(); draft.name = "재시도 제한"
        try store.upsertRoutine(draft)
        let sync = SyncCoordinator(store: store)
        defer { sync.disconnect(); try? FileManager.default.removeItem(at: root) }
        await sync.connect(url: root, persist: false)
        sync.setActive(false)
        try await Task.sleep(for: .milliseconds(100))
        let csv = try XCTUnwrap(sync.latestCSV.first?.url)
        let baseline = csv.deletingLastPathComponent().appendingPathComponent("baseline.json")
        try FileManager.default.removeItem(at: baseline)
        try Data().write(to: baseline.deletingLastPathComponent().appendingPathComponent(".baseline.json.icloud"))
        for _ in 0..<4 { await sync.refresh(manual: true) }
        XCTAssertTrue(sync.status.contains("다운로드 대기"))
        let changes = ExportInvalidations()
        withObservationTracking { _ = sync.status } onChange: { changes.record() }
        sync.setActive(true)
        for _ in 0..<25 {
            sync.localDataDidChange()
            try await Task.sleep(for: .milliseconds(40))
        }
        XCTAssertEqual(changes.count, 0, "Activation and file notifications must not bypass download backoff")
    }
}

extension SyncCoordinatorTests {
    @MainActor func testMissingEventDefersCSVImportUntilJournalDownloadCompletes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = RoutineStore(container: try PersistenceFactory.make(inMemory: true))
        var draft = RoutineDraft(); draft.name = "일관된 저널"; draft.steps = [StepDraft(name: "물")]
        try store.upsertRoutine(draft)
        let sync = SyncCoordinator(store: store, automatic: false)
        defer { sync.disconnect(); try? FileManager.default.removeItem(at: root) }
        await sync.connect(url: root, persist: false)
        let csv = try XCTUnwrap(sync.latestCSV.first?.url)
        var rows = try CSVCodec.decode(Data(contentsOf: csv)); rows[1][1] = "TRUE"
        try CSVCodec.encode(rows).write(to: csv)
        let transport = SyncFolderTransport(root: root)
        let space = try await transport.open(), peer = UUID(), incoming = UUID()
        let ready = SyncEvent(spaceID: space, id: UUID(), deviceID: peer, counter: 100, createdAt: Date(timeIntervalSince1970: 1), operations: [SyncOperation(kind: .routine, id: incoming.uuidString, values: ["name": "받은 루틴"])])
        let waiting = SyncEvent(spaceID: space, id: UUID(), deviceID: peer, counter: 101, createdAt: Date(timeIntervalSince1970: 1), operations: [SyncOperation(kind: .routine, id: incoming.uuidString, values: ["name": "최종 루틴"])])
        try await transport.publish([ready, waiting])
        let file = root.appendingPathComponent("changes/\(peer)/\(waiting.id).json")
        let saved = try Data(contentsOf: file)
        try FileManager.default.removeItem(at: file)
        let placeholder = file.deletingLastPathComponent().appendingPathComponent(".\(file.lastPathComponent).icloud")
        try Data().write(to: placeholder)
        await sync.refresh(manual: true)
        XCTAssertTrue(try store.loadSnapshot().routines.contains { $0.name == "받은 루틴" })
        XCTAssertFalse(try store.loadSnapshot().records.contains { $0.routineID == draft.id && $0.completedStepIDs.contains(draft.steps[0].id) })
        try FileManager.default.removeItem(at: placeholder); try saved.write(to: file)
        await sync.refresh(manual: true)
        XCTAssertTrue(try store.loadSnapshot().routines.contains { $0.name == "최종 루틴" })
        XCTAssertTrue(try store.loadSnapshot().records.contains { $0.routineID == draft.id && $0.completedStepIDs.contains(draft.steps[0].id) })
    }
}

extension SyncCoordinatorTests {
    @MainActor func testListConfigRefreshAndDisconnect() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = RoutineStore(container: try PersistenceFactory.make(inMemory: true))
        let sync = SyncCoordinator(store: store, automatic: false)
        await sync.connect(url: root, persist: false)
        let url = try XCTUnwrap(sync.listLayoutFileURL)
        XCTAssertEqual(url.lastPathComponent, "list-layout.json")
        try Data("{\"itemMinHeight\":70}".utf8).write(to: url)
        await sync.refresh()
        XCTAssertEqual(sync.listLayout.itemMinHeight, 70)
        try Data("{\"itemMinHeight\":80}".utf8).write(to: url)
        await sync.refresh()
        XCTAssertEqual(sync.listLayout.itemMinHeight, 80)
        try Data("broken".utf8).write(to: url)
        await sync.refresh()
        XCTAssertEqual(sync.listLayout.itemMinHeight, 80)
        XCTAssertTrue(sync.listLayoutStatus.contains("유지"))
        sync.disconnect()
        XCTAssertNil(sync.listLayoutFileURL)
        XCTAssertEqual(try String(contentsOf: url), "broken")
    }
}


extension SyncCoordinatorTests {
    @MainActor func testMalformedLayoutKeepsLastAppliedSettingsAndRecovers() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Config/list-layout.json")
        let store = RoutineStore(container: try PersistenceFactory.make(inMemory: true))
        let sync = SyncCoordinator(store: store, automatic: false)
        await sync.connect(url: root, persist: false)
        defer { sync.disconnect() }
        try Data("{\"itemSpacing\":20}".utf8).write(to: url, options: .atomic)
        await sync.reloadListLayout()
        XCTAssertEqual(sync.listLayout.itemSpacing, 20)
        try Data("{unfinished".utf8).write(to: url, options: .atomic)
        await sync.reloadListLayout()
        XCTAssertEqual(sync.listLayout.itemSpacing, 20)
        try Data("{\"itemSpacing\":32}".utf8).write(to: url, options: .atomic)
        await sync.reloadListLayout()
        XCTAssertEqual(sync.listLayout.itemSpacing, 32)
    }
}


extension SyncCoordinatorTests {
    @MainActor func testLayoutControlsPersistAndFailedSaveKeepsAppliedValue() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sync = SyncCoordinator(store: RoutineStore(container: try PersistenceFactory.make(inMemory: true)), automatic: false)
        await sync.connect(url: root, persist: false)
        defer { sync.disconnect() }
        let url = try XCTUnwrap(sync.listLayoutFileURL)
        var value = sync.listLayout
        value.itemSpacing = 24
        try await sync.saveListLayout(value)
        XCTAssertEqual(sync.listLayout.itemSpacing, 24)
        XCTAssertEqual(try ListLayoutConfig.loadOrCreate(at: url).itemSpacing, 24)
        await sync.reloadListLayout()
        XCTAssertEqual(sync.listLayout.itemSpacing, 24)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        value.itemSpacing = 40
        do { try await sync.saveListLayout(value); XCTFail("Writing over a directory must fail") }
        catch { }
        XCTAssertEqual(sync.listLayout.itemSpacing, 24)
    }
}
