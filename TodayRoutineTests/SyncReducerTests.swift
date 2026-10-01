import XCTest
@testable import RoutineCore
final class SyncReducerTests: XCTestCase {
    let space = UUID(), device = UUID(), routine = UUID()
    func event(_ count: Int64, _ values: [String:String], kind: SyncKind = .routine, id: String? = nil, deleted: Bool = false) -> SyncEvent {
        SyncEvent(spaceID: space, id: UUID(), deviceID: device, counter: count, createdAt: Date(), operations: [SyncOperation(kind: kind, id: id ?? routine.uuidString, values: values, deleted: deleted)])
    }
    func testOutOfOrderAndDuplicateConverge() throws {
        let a = event(1,["name":"독서"]), b = event(2,["note":"아침"])
        let result = try SyncReducer.reduce([b,a,a])
        XCTAssertEqual(result, try SyncReducer.reduce([a,b]))
        XCTAssertEqual(result.objects["routine/\(routine)"]?.fields["name"], "독서")
        XCTAssertEqual(result.objects["routine/\(routine)"]?.fields["note"], "아침")
    }
    func testClockSkewAndDeletionDoNotResurrect() throws {
        var a = event(1,["name":"처음"]), b = event(2,["name":"마지막"])
        a.createdAt = Date.distantFuture; b.createdAt = Date.distantPast
        XCTAssertEqual(try SyncReducer.reduce([b,a]).objects["routine/\(routine)"]?.fields["name"],"마지막")
        let deleted = event(3,[:],deleted: true), later = event(4,["name":"부활"])
        let result = try SyncReducer.reduce([later,deleted,a]); XCTAssertNil(result.objects["routine/\(routine)"])
        XCTAssertTrue(result.tombstones.contains("routine/\(routine)"))
    }
    func testConcurrentStepPatchesPreserveBothChecks() throws {
        let s1 = UUID().uuidString, s2 = UUID().uuidString, key = routine.uuidString + "/2026-10-02"
        let a = event(1,["routineID":routine.uuidString,"dayKey":"2026-10-02","stepIDs":"\(s1),\(s2)","nameSnapshot":"독서","status":"pending"],kind:.record,id:key)
        let b = event(2,["step/"+s1:"true"],kind:.record,id:key), c = event(3,["step/"+s2:"true"],kind:.record,id:key)
        XCTAssertEqual(try SyncReducer.reduce([c,a,b,b]).objects["record/"+key]?.fields["status"],"completed")
        let undo = event(4,["step/"+s1:"false"],kind:.record,id:key)
        XCTAssertEqual(try SyncReducer.reduce([c,a,undo,b]).objects["record/"+key]?.fields["status"],"pending")
    }
    func testRejectsUnknownVersionAndConflictingID() {
        var a = event(1,["name":"독서"]); a.version = 2
        XCTAssertThrowsError(try SyncReducer.reduce([a]))
        a.version = 1; var b = a; b.operations[0].values["name"] = "다른 값"
        XCTAssertThrowsError(try SyncReducer.reduce([a,b]))
    }
}
