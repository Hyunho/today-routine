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
extension SyncStoreTests {
    @MainActor func testOldSevenModelStoreMigratesWithoutLosingIDsOrReminders() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".store")
        let rid = UUID(), sid = UUID(), tid = UUID(), bid = UUID()
        do {
            let old = Schema([Routine.self,RoutineStep.self,RoutineGroup.self,RoutineDayRecord.self,TaskItem.self,TimeBlock.self,ReminderPreference.self])
            let container = try ModelContainer(for:old,configurations:[ModelConfiguration(schema:old,url:url,cloudKitDatabase:.none)])
            let context = ModelContext(container)
            context.insert(Routine(id:rid,name:"기존 루틴")); context.insert(RoutineStep(id:sid,routineID:rid,name:"물"))
            context.insert(RoutineGroup(name:"기존 그룹")); context.insert(RoutineDayRecord(routineID:rid,dayKey:"2026-10-01",name:"과거 이름"))
            context.insert(TaskItem(id:tid,title:"일감")); context.insert(TimeBlock(id:bid,title:"시간",dayKey:"2026-10-01",start:60,end:120))
            context.insert(ReminderPreference(routineID:rid)); try context.save()
        }
        let store = RoutineStore(container:try PersistenceFactory.make(url:url)), s = try store.loadSnapshot()
        XCTAssertEqual(s.routines.first?.id,rid); XCTAssertEqual(s.steps.first?.id,sid)
        XCTAssertEqual(s.groups.count,1); XCTAssertEqual(s.records.first?.nameSnapshot,"과거 이름")
        XCTAssertEqual(s.tasks.first?.id,tid); XCTAssertEqual(s.blocks.first?.id,bid); XCTAssertEqual(s.reminders.count,1)
        XCTAssertTrue(try StoreSyncAdapter(store:store).events().isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath:url.appendingPathExtension("pre-sync-v1").appendingPathComponent(url.lastPathComponent).path))
    }
    @MainActor func testRemoteApplyFailureKeepsOutboxAndRecords() throws {
        let a = RoutineStore(container:try PersistenceFactory.make(inMemory:true)), b = RoutineStore(container:try PersistenceFactory.make(inMemory:true))
        let x = StoreSyncAdapter(store:a), y = StoreSyncAdapter(store:b), space = UUID()
        try x.enable(spaceID:space,deviceID:UUID()); try y.enable(spaceID:space,deviceID:UUID())
        var draft = RoutineDraft(); draft.name = "전달"; try a.upsertRoutine(draft)
        b.saveOperation = { _ in throw CocoaError(.fileWriteOutOfSpace) }
        XCTAssertThrowsError(try y.ingest(x.events()))
        XCTAssertTrue(try b.loadSnapshot().routines.isEmpty); XCTAssertTrue(try y.events().isEmpty)
    }
}
extension SyncStoreTests {
    @MainActor func testHistoricCommandKeepsOldStepIdentityAfterRoutineEdit() throws {
        let store = RoutineStore(container:try PersistenceFactory.make(inMemory:true))
        let sync = StoreSyncAdapter(store:store); try sync.enable(spaceID:UUID(),deviceID:UUID())
        var draft = RoutineDraft(); draft.name = "과거"; draft.steps = [StepDraft(name:"옛 단계")]; try store.upsertRoutine(draft)
        let oldID = draft.steps[0].id.uuidString, date = RoutineRules.date(for:"2026-10-01")!
        try store.setStatus(routineID:draft.id,date:date,status:.completed)
        draft.steps = [StepDraft(name:"새 단계")]; try store.upsertRoutine(draft)
        try store.setStatus(routineID:draft.id,date:date,status:.pending)
        let record = try sync.exportState().objects["record/"+draft.id.uuidString+"/2026-10-01"]
        XCTAssertEqual(record?.fields["stepIDs"],oldID)
        XCTAssertTrue(record?.fields["stepNames"]?.contains("옛 단계") == true)
    }
}
