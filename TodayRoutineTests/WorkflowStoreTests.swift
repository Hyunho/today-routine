import XCTest
@testable import RoutineCore
final class WorkflowStoreTests: XCTestCase {
    @MainActor func makeStore() throws -> RoutineStore { RoutineStore(container: try PersistenceFactory.make(inMemory: true)) }
    @MainActor func fixture(_ store: RoutineStore) throws -> UUID { var d = RoutineDraft(); d.name = "아침"; d.steps = [StepDraft(name: "물"),StepDraft(name: "책")]; try store.upsertRoutine(d); return d.id }
    @MainActor func testCompletionIsIdempotentAndReversible() throws {
        let s = try makeStore(), id = try fixture(s), date = Date()
        try s.setStatus(routineID: id, date: date, status: .completed); try s.setStatus(routineID: id, date: date, status: .completed)
        XCTAssertEqual(try s.loadSnapshot().records.count, 1)
        XCTAssertEqual(RoutineRules.completedCount(routineID: id, records: try s.loadSnapshot().records, week: date), 1)
        try s.setStatus(routineID: id, date: date, status: .pending)
        XCTAssertEqual(RoutineRules.completedCount(routineID: id, records: try s.loadSnapshot().records, week: date), 0)
    }
    @MainActor func testLastStepCompletesAndUncheckReopens() throws {
        let s = try makeStore(), id = try fixture(s), date = Date(); let steps = try s.loadSnapshot().steps
        for step in steps { try s.toggleStep(routineID: id, stepID: step.id, date: date) }
        XCTAssertEqual(try s.loadSnapshot().records.first?.status, .completed)
        try s.toggleStep(routineID: id, stepID: steps[0].id, date: date)
        XCTAssertEqual(try s.loadSnapshot().records.first?.status, .pending)
        try s.setStatus(routineID: id, date: date, status: .completed)
        XCTAssertEqual(try s.loadSnapshot().records.first?.completedStepIDs.count, 2)
    }
    @MainActor func testHistorySurvivesRoutineEdits() throws {
        let s = try makeStore(), id = try fixture(s), yesterday = Date().addingTimeInterval(-86400)
        try s.setStatus(routineID: id, date: yesterday, status: .completed)
        let oldIDs = try s.loadSnapshot().records[0].completedStepIDs
        var d = RoutineDraft(try s.loadSnapshot().routines[0], steps: []); d.name = "새 아침"
        try s.upsertRoutine(d)
        XCTAssertEqual(try s.loadSnapshot().records[0].nameSnapshot, "아침")
        XCTAssertEqual(try s.loadSnapshot().records[0].completedStepIDs, oldIDs)
    }
    @MainActor func testDeleteGroupOnlyUnlinksRoutines() throws {
        let s = try makeStore(); let g = RoutineGroup(name: "건강"); s.context.insert(g); try s.save()
        var d = RoutineDraft(); d.name = "걷기"; d.groupID = g.id; try s.upsertRoutine(d)
        try s.deleteGroup(id: g.id)
        XCTAssertEqual(try s.loadSnapshot().routines.count, 1); XCTAssertNil(try s.loadSnapshot().routines[0].groupID)
    }
    @MainActor func testRejectsEmptyRoutineWithoutSaving() throws {
        let s = try makeStore(); var d = RoutineDraft(); d.name = "  "
        XCTAssertThrowsError(try s.upsertRoutine(d)); XCTAssertTrue(try s.loadSnapshot().routines.isEmpty)
    }
}
