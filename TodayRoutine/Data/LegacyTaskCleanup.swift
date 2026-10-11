import Foundation

extension RoutineStore {
    /// Upgrade cleanup; also safe to retry after a failed save.
    func removeLegacyTasks() throws {
        let adapter = StoreSyncAdapter(store: self)
        let before = try StoreSyncBridge.objects(loadSnapshot())
        let journal = try adapter.exportState()
        func isLegacy(_ object: SyncObject) -> Bool {
            object.kind == .task || (object.kind == .block && object.fields["linkedKind"] == "task")
        }
        guard before.values.contains(where: isLegacy) || journal.objects.values.contains(where: isLegacy) else { return }
        let wasApplying = syncApplying
        syncApplying = true
        defer { syncApplying = wasApplying }
        try transaction {
            try removeLegacyTaskRecords()
            try adapter.captureLegacyTaskRemoval(before: before)
        }
    }

    /// Caller owns the transaction so incoming events and cleanup commit together.
    func removeLegacyTaskRecords() throws {
        let snapshot = try loadSnapshot()
        for block in snapshot.blocks where block.linkedKind == "task" {
            block.linkedID = nil; block.linkedKind = nil; block.updatedAt = Date()
        }
        for task in snapshot.tasks { context.delete(task) }
    }
}

extension StoreSyncAdapter {
    func captureLegacyTaskRemoval(before: [String: SyncObject]) throws {
        guard let config = try configuration() else { return }
        let journal = try exportState()
        let candidates = before.merging(journal.objects) { _, remote in remote }
        var operations: [SyncOperation] = []
        for object in candidates.values.sorted(by: { $0.key < $1.key }) where !journal.tombstones.contains(object.key) {
            if object.kind == .task {
                operations.append(SyncOperation(kind: .task, id: object.id, deleted: true))
            } else if object.kind == .block && object.fields["linkedKind"] == "task" {
                // Only unlink; a journal-only block must never be deleted by a snapshot diff.
                operations.append(SyncOperation(kind: .block, id: object.id, values: ["linkedID": "", "linkedKind": ""]))
            }
        }
        // SyncValidation bounds each event to 10,000 operations.
        var counter = journal.counter
        for start in stride(from: 0, to: operations.count, by: 10_000) {
            guard counter < Int64.max - 1 else { throw SyncError.invalid("동기화 변경 번호 범위를 초과했습니다.") }
            counter += 1
            let event = SyncEvent(spaceID: config.spaceID, id: UUID(), deviceID: config.deviceID,
                                  counter: counter, createdAt: Date(),
                                  operations: Array(operations[start..<min(start + 10_000, operations.count)]))
            try SyncValidation.validate(event)
            store.context.insert(try SyncJournalEntry(event: event))
        }
    }
}
