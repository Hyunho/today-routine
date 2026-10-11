import XCTest
import SwiftData
@testable import RoutineCore

final class LegacyTaskCleanupTests: XCTestCase {
    @MainActor private func makeStore() throws -> RoutineStore {
        RoutineStore(container: try PersistenceFactory.make(inMemory: true))
    }
    @MainActor private func seed(_ store: RoutineStore) throws -> (UUID, UUID, UUID) {
        let task = TaskItem(title: "미완료"), done = TaskItem(title: "완료")
        done.completedAt = Date()
        let routine = Routine(name: "유지")
        let block = TimeBlock(title: "집중 시간", dayKey: "2026-10-09", start: 540, end: 600)
        block.linkedID = task.id; block.linkedKind = "task"
        let linkedRoutine = TimeBlock(title: "루틴 시간", dayKey: "2026-10-09", start: 600, end: 660)
        linkedRoutine.linkedID = routine.id; linkedRoutine.linkedKind = "routine"
        store.context.insert(task); store.context.insert(done); store.context.insert(routine)
        store.context.insert(block); store.context.insert(linkedRoutine); try store.save()
        return (task.id, block.id, routine.id)
    }
    @MainActor func testCleanupDeletesTasksAndPreservesBlocks() throws {
        let store = try makeStore(), (_, blockID, routineID) = try seed(store)
        try store.removeLegacyTasks()
        let snapshot = try store.loadSnapshot()
        XCTAssertTrue(snapshot.tasks.isEmpty)
        XCTAssertEqual(snapshot.blocks.count, 2)
        let block = try XCTUnwrap(snapshot.blocks.first { $0.id == blockID })
        XCTAssertEqual(block.title, "집중 시간"); XCTAssertEqual(block.dayKey, "2026-10-09")
        XCTAssertEqual(block.startMinute, 540); XCTAssertEqual(block.endMinute, 600)
        XCTAssertNil(block.linkedID); XCTAssertNil(block.linkedKind)
        XCTAssertEqual(snapshot.blocks.first { $0.linkedKind == "routine" }?.linkedID, routineID)
        // No changes means no save attempt, even if persistence is unavailable.
        store.saveOperation = { _ in XCTFail("Idempotent cleanup should not save") }
        try store.removeLegacyTasks()
    }
    @MainActor func testCleanupDeletesJournalOnlyTasks() throws {
        let store = try makeStore(), sync = StoreSyncAdapter(store: store), space = UUID(), id = UUID(), block = UUID()
        try sync.enable(spaceID: space, deviceID: UUID())
        let event = SyncEvent(spaceID: space, id: UUID(), deviceID: UUID(), counter: 1, createdAt: Date(), operations: [
            SyncOperation(kind: .task, id: id.uuidString, values: ["title": "저널에만 존재"]),
            SyncOperation(kind: .block, id: block.uuidString, values: ["title": "시간", "dayKey": "2026-10-09", "startMinute": "540", "endMinute": "600", "linkedKind": "task", "linkedID": id.uuidString])
        ])
        store.context.insert(try SyncJournalEntry(event: event, published: true)); try store.save()
        try store.removeLegacyTasks()
        let state = try sync.exportState()
        XCTAssertTrue(state.tombstones.contains("task/" + id.uuidString))
        XCTAssertEqual(state.objects["block/" + block.uuidString]?.fields["linkedKind"], "")
        XCTAssertFalse(state.tombstones.contains("block/" + block.uuidString))
        let count = try sync.events().count
        try store.removeLegacyTasks()
        XCTAssertEqual(try sync.events().count, count)
    }
    @MainActor func testCleanupRollbackAndRetry() throws {
        let store = try makeStore(), sync = StoreSyncAdapter(store: store)
        try sync.enable(spaceID: UUID(), deviceID: UUID())
        let (id, blockID, _) = try seed(store)
        let events = try sync.events()
        store.saveOperation = { _ in throw CocoaError(.fileWriteOutOfSpace) }
        XCTAssertThrowsError(try store.removeLegacyTasks())
        XCTAssertEqual(try store.loadSnapshot().tasks.count, 2)
        XCTAssertEqual(try store.loadSnapshot().blocks.first { $0.id == blockID }?.linkedID, id)
        XCTAssertEqual(try sync.events(), events)
        store.saveOperation = nil
        try store.removeLegacyTasks()
        XCTAssertTrue(try store.loadSnapshot().tasks.isEmpty)
        XCTAssertTrue(try sync.pendingEvents().contains { $0.operations.contains { $0.kind == .task && $0.id == id.uuidString && $0.deleted } })
    }
    @MainActor func testCleanupIsIdempotentAndKeepsPendingDeletion() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".store")
        var deletedID: UUID!
        do {
            let store = RoutineStore(container: try PersistenceFactory.make(url: url)), sync = StoreSyncAdapter(store: store)
            try sync.enable(spaceID: UUID(), deviceID: UUID())
            deletedID = try seed(store).0
            try sync.disconnect()
            try store.removeLegacyTasks()
            let count = try sync.events().count
            try store.removeLegacyTasks()
            XCTAssertEqual(try sync.events().count, count)
        }
        let reopened = RoutineStore(container: try PersistenceFactory.make(url: url)), sync = StoreSyncAdapter(store: reopened)
        XCTAssertTrue(try reopened.loadSnapshot().tasks.isEmpty)
        XCTAssertTrue(try sync.pendingEvents().contains { $0.operations.contains { $0.id == deletedID.uuidString && $0.deleted } })
    }
}

extension LegacyTaskCleanupTests {
    private func legacyEvent(space: UUID, task: UUID, block: UUID, counter: Int64 = 1) -> SyncEvent {
        // Use an exactly representable timestamp so JSON round trips preserve event equality.
        SyncEvent(spaceID: space, id: UUID(), deviceID: UUID(), counter: counter, createdAt: Date(timeIntervalSince1970: 1_791_504_000), operations: [
            SyncOperation(kind: .task, id: task.uuidString, values: ["title": "구버전 작업"]),
            SyncOperation(kind: .block, id: block.uuidString, values: ["title": "보존할 블록", "dayKey": "2026-10-09", "startMinute": "540", "endMinute": "600", "linkedKind": "task", "linkedID": task.uuidString])
        ])
    }
    @MainActor func testIngestRetiresNewLegacyTaskAndDetachesBlock() throws {
        let store = try makeStore(), sync = StoreSyncAdapter(store: store), space = UUID(), task = UUID(), block = UUID()
        try sync.enable(spaceID: space, deviceID: UUID())
        let event = legacyEvent(space: space, task: task, block: block)
        try sync.ingest([event])
        XCTAssertTrue(try store.loadSnapshot().tasks.isEmpty)
        let kept = try XCTUnwrap(store.loadSnapshot().blocks.first)
        XCTAssertEqual(kept.title, "보존할 블록"); XCTAssertEqual(kept.startMinute, 540); XCTAssertEqual(kept.endMinute, 600)
        XCTAssertNil(kept.linkedID); XCTAssertNil(kept.linkedKind)
        XCTAssertTrue(try sync.exportState().tombstones.contains("task/" + task.uuidString))
        XCTAssertEqual(try sync.pendingEvents().count, 1)
        let peer = try makeStore(), peerSync = StoreSyncAdapter(store: peer)
        try peerSync.enable(spaceID: space, deviceID: UUID())
        try peerSync.ingest(sync.events())
        XCTAssertTrue(try peer.loadSnapshot().tasks.isEmpty)
        XCTAssertNil(try peer.loadSnapshot().blocks.first?.linkedID)
        XCTAssertTrue(try peerSync.pendingEvents().isEmpty)
    }
    @MainActor func testReplayDoesNotRestoreTasksOrGrowJournal() throws {
        let store = try makeStore(), sync = StoreSyncAdapter(store: store), space = UUID(), task = UUID(), block = UUID()
        try sync.enable(spaceID: space, deviceID: UUID())
        let event = legacyEvent(space: space, task: task, block: block)
        try sync.ingest([event]); let count = try sync.events().count
        try sync.ingest([event])
        XCTAssertTrue(try store.loadSnapshot().tasks.isEmpty)
        XCTAssertEqual(try sync.events().count, count)
        // A late old client can reconnect a block to an already tombstoned task.
        try sync.ingest([legacyEvent(space: space, task: task, block: block, counter: 50)])
        XCTAssertNil(try store.loadSnapshot().blocks.first?.linkedKind)
        XCTAssertEqual(try sync.exportState().objects["block/" + block.uuidString]?.fields["linkedKind"], "")
        let settled = try sync.events().count
        try sync.ingest([])
        XCTAssertEqual(try sync.events().count, settled)
    }
    @MainActor func testAppendLocalAndEnableRetireLegacyTasks() throws {
        let store = try makeStore(), (task, _, _) = try seed(store), sync = StoreSyncAdapter(store: store), space = UUID()
        try sync.enable(spaceID: space, deviceID: UUID())
        XCTAssertTrue(try store.loadSnapshot().tasks.isEmpty)
        XCTAssertTrue(try sync.exportState().tombstones.contains("task/" + task.uuidString))
        let other = UUID()
        try sync.appendLocal(legacyEvent(space: space, task: other, block: UUID(), counter: 50))
        XCTAssertTrue(try store.loadSnapshot().tasks.isEmpty)
        XCTAssertTrue(try sync.exportState().tombstones.contains("task/" + other.uuidString))
    }
    @MainActor func testIngestCleanupFailureRollsBackIncomingEvent() throws {
        let store = try makeStore(), sync = StoreSyncAdapter(store: store), space = UUID()
        try sync.enable(spaceID: space, deviceID: UUID())
        let event = legacyEvent(space: space, task: UUID(), block: UUID())
        store.saveOperation = { _ in throw CocoaError(.fileWriteOutOfSpace) }
        XCTAssertThrowsError(try sync.ingest([event]))
        XCTAssertTrue(try sync.events().isEmpty); XCTAssertTrue(try store.loadSnapshot().blocks.isEmpty)
        store.saveOperation = nil
        try sync.ingest([event])
        XCTAssertTrue(try store.loadSnapshot().tasks.isEmpty)
        XCTAssertEqual(try sync.events().count, 2)
    }
}
