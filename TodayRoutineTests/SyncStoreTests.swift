import XCTest
import SwiftData
@testable import RoutineCore
final class SyncStoreTests: XCTestCase {
    @MainActor func testBootstrapAndRemoteChecksPreserveBothDevices() throws {
        let a = RoutineStore(container: try PersistenceFactory.make(inMemory:true)), b = RoutineStore(container:try PersistenceFactory.make(inMemory:true))
        var d = RoutineDraft(); d.name = "아침"; d.steps = [StepDraft(name:"물"),StepDraft(name:"독서")]; try a.upsertRoutine(d)
        let x = StoreSyncAdapter(store:a), y = StoreSyncAdapter(store:b), space = UUID()
        try x.enable(spaceID:space,deviceID:UUID()); try y.enable(spaceID:space,deviceID:UUID())
        try y.ingest(x.pendingEvents()); XCTAssertEqual(try b.loadSnapshot().routines.first?.name,"아침")
        let date = Date()
        try a.toggleStep(routineID:d.id,stepID:d.steps[0].id,date:date)
        try b.toggleStep(routineID:d.id,stepID:d.steps[1].id,date:date)
        try x.ingest(y.pendingEvents()); try y.ingest(x.pendingEvents())
        XCTAssertEqual(try a.loadSnapshot().records.first?.status,.completed)
        XCTAssertEqual(try b.loadSnapshot().records.first?.completedStepIDs.count,2)
        XCTAssertEqual(try x.exportState(),try y.exportState())
    }
    @MainActor func testSaveFailureRollsBackDataAndJournal() throws {
        let store = RoutineStore(container:try PersistenceFactory.make(inMemory:true)), space = UUID()
        let sync = StoreSyncAdapter(store:store); try sync.enable(spaceID:space,deviceID:UUID())
        var d = RoutineDraft(); d.name = "보존"
        store.saveOperation = { _ in throw CocoaError(.fileWriteOutOfSpace) }
        XCTAssertThrowsError(try store.upsertRoutine(d))
        XCTAssertTrue(try store.loadSnapshot().routines.isEmpty); XCTAssertTrue(try sync.pendingEvents().isEmpty)
        store.saveOperation = nil; try store.upsertRoutine(d)
        XCTAssertEqual(try sync.pendingEvents().count,1)
    }
    @MainActor func testPendingEventsSurviveReopenAndReceipt() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".store")
        let space = UUID()
        do { let store = RoutineStore(container:try PersistenceFactory.make(url:url)); let sync = StoreSyncAdapter(store:store)
            try sync.enable(spaceID:space,deviceID:UUID()); var d = RoutineDraft(); d.name = "독서"; try store.upsertRoutine(d)
        }
        let store = RoutineStore(container:try PersistenceFactory.make(url:url)), sync = StoreSyncAdapter(store:store)
        let pending = try sync.pendingEvents(); XCTAssertEqual(pending.count,1)
        try sync.markPublished(ids:pending.map(\.id)); XCTAssertTrue(try sync.pendingEvents().isEmpty)
        XCTAssertEqual(try store.loadSnapshot().routines.first?.name,"독서")
    }
}
