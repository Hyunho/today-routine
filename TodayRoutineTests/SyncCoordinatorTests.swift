import XCTest
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
