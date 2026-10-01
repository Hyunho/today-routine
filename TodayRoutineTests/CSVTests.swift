import XCTest
@testable import RoutineCore
final class CSVTests: XCTestCase {
    func testKoreanQuotesNewlinesAndBOMRoundTrip() throws {
        let rows = [["날짜","물, 마시기","책 \"한 장\"","줄\n바꿈"],["2026-10-02","TRUE","FALSE",""]]
        XCTAssertEqual(try CSVCodec.decode(CSVCodec.encode(rows)),rows)
        XCTAssertEqual(try CSVCodec.decode(Data("\u{feff}날짜,독서\r\n2026-10-02,TRUE\r\n".utf8)),[["날짜","독서"],["2026-10-02","TRUE"]])
        XCTAssertThrowsError(try CSVCodec.decode(Data("날짜,\"닫히지 않음".utf8)))
    }
}
extension CSVTests {
    func fixture() throws -> (RoutineCSVDocument, SyncState, String, String) {
        let r = UUID(), a = UUID().uuidString, b = UUID().uuidString, space = UUID()
        let operations = [SyncOperation(kind:.routine,id:r.uuidString,values:["name":"아침"]),SyncOperation(kind:.step,id:a,values:["routineID":r.uuidString,"name":"물","sortOrder":"0"]),SyncOperation(kind:.step,id:b,values:["routineID":r.uuidString,"name":"독서","sortOrder":"1"])]
        let state = try SyncReducer.reduce([SyncEvent(spaceID:space,id:UUID(),deviceID:UUID(),counter:1,createdAt:Date(),operations:operations)])
        return (try RoutineCSVDocument.make(routineID:r,spaceID:space,state:state,today:RoutineRules.date(for:"2026-10-02")!),state,a,b)
    }
    func testRoutineMatrixAndEditedCells() throws {
        let (doc,state,a,_) = try fixture()
        XCTAssertEqual(try CSVCodec.decode(doc.csv),[["날짜","물","독서"],["2026-10-02","FALSE","FALSE"]])
        let edit = Data("날짜,물,독서\n2026-10-02,TRUE,FALSE\n".utf8)
        let result = try CSVImporter.diff(data:edit,baseline:doc,current:state)
        XCTAssertEqual(result.operations.count,1); XCTAssertEqual(result.operations.first?.values["step/"+a],"true")
        XCTAssertTrue(result.conflicts.isEmpty)
    }
    func testStaleCSVDoesNotOverwriteDifferentStepOrDeleteMissingRows() throws {
        let (doc,varState,a,b) = try fixture(); var current = varState
        let key = doc.routineID.uuidString + "/2026-10-02"
        current.objects["record/"+key] = SyncObject(kind:.record,id:key,fields:["step/"+b:"true","status":"pending"])
        let result = try CSVImporter.diff(data:Data("날짜,물,독서\n2026-10-02,TRUE,FALSE\n".utf8),baseline:doc,current:current)
        XCTAssertEqual(result.operations.first?.values["step/"+a],"true"); XCTAssertNil(result.operations.first?.values["step/"+b])
        XCTAssertThrowsError(try CSVImporter.diff(data:Data("날짜,物\n".utf8),baseline:doc,current:current))
    }
    func testInvalidAndDuplicateRowsRejectWholeFile() throws {
        let (doc,state,_,_) = try fixture()
        XCTAssertThrowsError(try CSVImporter.diff(data:Data("날짜,물\n2026-10-02,TRUE\n2026-10-02,FALSE\n".utf8),baseline:doc,current:state))
        XCTAssertThrowsError(try CSVImporter.diff(data:Data("날짜,물\n2026-10-02,yes\n".utf8),baseline:doc,current:state))
        XCTAssertTrue(try CSVImporter.diff(data:Data("날짜,물\n2026-10-02,\n".utf8),baseline:doc,current:state).operations.isEmpty)
    }
}
extension CSVTests {
    func testSkippedBootstrapAndUnchangedCSVStaySkipped() throws {
        let (doc, state, a, b) = try fixture()
        let id = doc.routineID.uuidString+"/2026-10-02"
        let e = SyncEvent(spaceID:doc.spaceID,id:UUID(),deviceID:UUID(),counter:2,createdAt:Date(),operations:[SyncOperation(kind:.record,id:id,values:["routineID":doc.routineID.uuidString,"dayKey":"2026-10-02","status":"skipped","stepIDs":a+","+b])])
        let changed = try SyncReducer.reduce([e])
        XCTAssertEqual(changed.objects["record/"+id]?.fields["status"],"skipped")
        var combined = state; combined.objects.merge(changed.objects) { _, new in new }
        let table = try RoutineCSVDocument.make(routineID:doc.routineID,spaceID:doc.spaceID,state:combined,today:RoutineRules.date(for:"2026-10-02")!)
        XCTAssertTrue(try CSVImporter.diff(data:table.csv,baseline:table,current:combined).operations.isEmpty)
    }
    func testRemovedAllStepsKeepsHistoricalAndCurrentCompletion() throws {
        let (doc, initial, a, b) = try fixture(); var state = initial
        let id = doc.routineID.uuidString+"/2026-10-01"
        state.objects["record/"+id] = SyncObject(kind:.record,id:id,fields:["routineID":doc.routineID.uuidString,"dayKey":"2026-10-01","stepIDs":a+","+b,"status":"pending"])
        state.objects.removeValue(forKey:"step/"+a); state.objects.removeValue(forKey:"step/"+b)
        let table = try RoutineCSVDocument.make(routineID:doc.routineID,spaceID:doc.spaceID,state:state,today:RoutineRules.date(for:"2026-10-02")!)
        XCTAssertTrue(table.columns.contains { $0.stepID == "_complete" })
        XCTAssertNil(table.value(date:"2026-10-01",stepID:"_complete",state:state))
        XCTAssertEqual(table.value(date:"2026-10-02",stepID:"_complete",state:state),false)
    }
}
