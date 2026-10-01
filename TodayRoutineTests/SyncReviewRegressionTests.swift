import XCTest
@testable import RoutineCore
final class FinalReviewReproTests: XCTestCase {
    func fixture() throws -> (SyncEvent, RoutineCSVDocument, String, String) {
        let r = UUID(), a = UUID().uuidString, b = UUID().uuidString, space = UUID()
        let e = SyncEvent(spaceID:space,id:UUID(),deviceID:UUID(),counter:1,createdAt:Date(),operations:[
            SyncOperation(kind:.routine,id:r.uuidString,values:["name":"review"]),
            SyncOperation(kind:.step,id:a,values:["routineID":r.uuidString,"name":"A","sortOrder":"0"]),
            SyncOperation(kind:.step,id:b,values:["routineID":r.uuidString,"name":"B","sortOrder":"1"])])
        let s = try SyncReducer.reduce([e])
        return (e, try RoutineCSVDocument.make(routineID:r,spaceID:space,state:s,today:RoutineRules.date(for:"2026-10-02")!),a,b)
    }
    func testSameCSVOnPeersWithDifferentRecordPresence() throws {
        let (initial, doc, a, b) = try fixture()
        let id = doc.routineID.uuidString+"/2026-10-02"
        let appEdit = SyncEvent(spaceID:doc.spaceID,id:UUID(),deviceID:UUID(),counter:2,createdAt:Date(),operations:[SyncOperation(kind:.record,id:id,values:["routineID":doc.routineID.uuidString,"dayKey":"2026-10-02","stepIDs":a+","+b,"step/"+b:"true"])])
        let peerA = try SyncReducer.reduce([initial, appEdit]), peerB = try SyncReducer.reduce([initial])
        let csv = Data("날짜,A,B\n2026-10-02,TRUE,FALSE\n".utf8)
        let deltaA = try CSVImporter.diff(data:csv,baseline:doc,current:peerA)
        let deltaB = try CSVImporter.diff(data:csv,baseline:doc,current:peerB)
        var eventA = try CSVImporter.event(deltaA.operations,document:doc)
        var eventB = try CSVImporter.event(deltaB.operations,document:doc)
        let hash = SyncCoding.hash(try CSVCodec.encode(CSVCodec.decode(csv)))
        let coordinatorID = SyncCoding.stableID(doc.documentID.uuidString+String(doc.state.counter)+hash)
        eventA.id = coordinatorID; eventB.id = coordinatorID
        XCTAssertEqual(eventA,eventB,"Same document and CSV must produce identical event bytes on both peers")
        XCTAssertNoThrow(try SyncReducer.reduce([initial,appEdit,eventA,eventB]))
    }
    func testRemovedHistoricalColumnDoesNotJoinNewDaySchema() throws {
        let (initial, oldDoc, a, b) = try fixture()
        let oldID = oldDoc.routineID.uuidString+"/2026-10-01"
        let oldRecord = SyncEvent(spaceID:oldDoc.spaceID,id:UUID(),deviceID:UUID(),counter:2,createdAt:Date(),operations:[SyncOperation(kind:.record,id:oldID,values:["routineID":oldDoc.routineID.uuidString,"dayKey":"2026-10-01","stepIDs":a+","+b,"step/"+a:"true","step/"+b:"true"])])
        let removeA = SyncEvent(spaceID:oldDoc.spaceID,id:UUID(),deviceID:UUID(),counter:3,createdAt:Date(),operations:[SyncOperation(kind:.step,id:a,deleted:true)])
        let state = try SyncReducer.reduce([initial,oldRecord,removeA])
        let doc = try RoutineCSVDocument.make(routineID:oldDoc.routineID,spaceID:oldDoc.spaceID,state:state,today:RoutineRules.date(for:"2026-10-02")!)
        var rows = try CSVCodec.decode(doc.csv)
        let index = try XCTUnwrap(rows.first?.firstIndex(of:"B"))
        let todayRow = try XCTUnwrap(rows.firstIndex(where:{$0.first == "2026-10-02"}))
        rows[todayRow][index] = "TRUE"
        let delta = try CSVImporter.diff(data:CSVCodec.encode(rows),baseline:doc,current:state)
        let applied = try SyncReducer.reduce([try CSVImporter.event(delta.operations,document:doc)],initial:state)
        let newRecord = applied.objects["record/"+oldDoc.routineID.uuidString+"/2026-10-02"]
        XCTAssertEqual(newRecord?.fields["stepIDs"],b)
        XCTAssertEqual(newRecord?.fields["status"],"completed")
    }
    @MainActor func testConcurrentValidTimeRangesCanStillMerge() throws {
        let a = RoutineStore(container:try PersistenceFactory.make(inMemory:true))
        let b = RoutineStore(container:try PersistenceFactory.make(inMemory:true))
        var draft = BlockDraft(); draft.title = "review"; draft.dayKey = "2026-10-02"; draft.startMinute = 600; draft.endMinute = 720
        try a.upsertBlock(draft)
        let space = UUID(), x = StoreSyncAdapter(store:a), y = StoreSyncAdapter(store:b)
        try x.enable(spaceID:space,deviceID:UUID()); try y.enable(spaceID:space,deviceID:UUID()); try y.ingest(x.events())
        var da = draft, db = draft; da.startMinute = 690; db.endMinute = 630
        try a.upsertBlock(da); try b.upsertBlock(db)
        XCTAssertNoThrow(try x.ingest(y.events()),"Both user edits were valid; merge should choose an intact time range")
    }
}
extension FinalReviewReproTests {
    func testPeersWithDifferentConflictSubsetsShareIdenticalCellEvents() throws {
        let (initial,doc,a,b) = try fixture()
        let id = doc.routineID.uuidString+"/2026-10-02"
        let edit = SyncEvent(spaceID:doc.spaceID,id:UUID(),deviceID:UUID(),counter:3,createdAt:Date(),operations:[SyncOperation(kind:.record,id:id,values:["routineID":doc.routineID.uuidString,"dayKey":"2026-10-02","stepIDs":a+","+b,"step/"+a:"false"])])
        let csv = Data("날짜,A,B\n2026-10-02,TRUE,TRUE\n".utf8), hash = SyncCoding.hash(csv)
        let one = try CSVImporter.diff(data:csv,baseline:doc,current:SyncReducer.reduce([initial,edit]))
        let two = try CSVImporter.diff(data:csv,baseline:doc,current:SyncReducer.reduce([initial]))
        XCTAssertEqual(one.conflicts.count,1)
        let x = try CSVImporter.cellEvents(one.operations,document:doc,hash:hash)
        let y = try CSVImporter.cellEvents(two.operations,document:doc,hash:hash)
        XCTAssertEqual(x.count,1); XCTAssertEqual(y.count,2)
        XCTAssertEqual(x.first,y.first { $0.operations[0].values["step/"+b] != nil })
        XCTAssertNoThrow(try SyncReducer.reduce([initial,edit]+x+y))
    }
    func testAllDeletedStepsUseWholeCompletionForNewDay() throws {
        let (initial,oldDoc,a,b) = try fixture()
        let r = oldDoc.routineID.uuidString, oldID = r+"/2026-10-01"
        let edits = SyncEvent(spaceID:oldDoc.spaceID,id:UUID(),deviceID:UUID(),counter:2,createdAt:Date(),operations:[SyncOperation(kind:.record,id:oldID,values:["routineID":r,"dayKey":"2026-10-01","stepIDs":a+","+b]),SyncOperation(kind:.step,id:a,deleted:true),SyncOperation(kind:.step,id:b,deleted:true)])
        let state = try SyncReducer.reduce([initial,edits]), date = RoutineRules.date(for:"2026-10-02")!
        let doc = try RoutineCSVDocument.make(routineID:oldDoc.routineID,spaceID:oldDoc.spaceID,state:state,today:date)
        var rows = try CSVCodec.decode(doc.csv)
        rows[try XCTUnwrap(rows.firstIndex{$0[0] == "2026-10-02"})][try XCTUnwrap(rows[0].firstIndex(of:"완료"))] = "TRUE"
        let result = try CSVImporter.diff(data:CSVCodec.encode(rows),baseline:doc,current:state)
        let applied = try SyncReducer.reduce([CSVImporter.event(result.operations,document:doc)],initial:state)
        XCTAssertEqual(applied.objects["record/"+r+"/2026-10-02"]?.fields["stepIDs"],"")
        XCTAssertEqual(applied.objects["record/"+r+"/2026-10-02"]?.fields["status"],"completed")
    }
}
