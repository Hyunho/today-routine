import Foundation
import SwiftData
@MainActor final class StoreSyncAdapter {
    let store: RoutineStore
    init(store: RoutineStore) { self.store = store }
    func configuration() throws -> SyncDeviceState? { try store.context.fetch(FetchDescriptor<SyncDeviceState>()).first }
    func entries() throws -> [SyncJournalEntry] { try store.context.fetch(FetchDescriptor<SyncJournalEntry>()) }
    func events() throws -> [SyncEvent] { try entries().map { try SyncCoding.decode(SyncEvent.self,from:$0.data) } }
    func exportState() throws -> SyncState { try SyncReducer.reduce(events()) }
    func enable(spaceID: UUID, deviceID: UUID) throws {
        if let config = try configuration() {
            guard config.spaceID == spaceID else { throw SyncError.invalid("다른 동기화 공간에 연결할 수 없습니다. 기존 공간을 선택해 주세요.") }
            config.enabled = true; try store.save(); return
        }
        store.syncApplying = true; defer { store.syncApplying = false }
        try store.transaction {
            store.context.insert(SyncDeviceState(spaceID:spaceID,deviceID:deviceID))
            try capture(before:[:])
        }
    }
    func disconnect() throws { if let config = try configuration() { config.enabled = false; try store.save() } }
    func capture(before: [String:SyncObject]) throws {
        guard let config = try configuration() else { return }
        let after = try StoreSyncBridge.objects(store.loadSnapshot())
        var ops: [SyncOperation] = []
        for object in after.values.sorted(by:{$0.key < $1.key}) {
            let old = before[object.key]
            if object.kind == .record, let old, old.fields["updatedAt"] == object.fields["updatedAt"], store.syncDayCommand?.0 != object.id { continue }
            var values = object.fields.filter { old?.fields[$0.key] != $0.value }
            if object.kind == .record {
                if old == nil { values = values.filter { !($0.key.hasPrefix("step/") && $0.value == "false") } }
                if let command = store.syncDayCommand, command.0 == object.id { values["command"] = command.1.rawValue }
                else if values.keys.contains(where:{$0.hasPrefix("step/")}) { values.removeValue(forKey:"status") }
            }
            if !values.isEmpty { ops.append(SyncOperation(kind:object.kind,id:object.id,values:values)) }
        }
        for old in before.values where after[old.key] == nil { ops.append(SyncOperation(kind:old.kind,id:old.id,deleted:true)) }
        guard !ops.isEmpty else { return }
        let counter = (try events().map(\.counter).max() ?? 0)+1
        let event = SyncEvent(spaceID:config.spaceID,id:UUID(),deviceID:config.deviceID,counter:counter,createdAt:Date(),operations:ops)
        try SyncValidation.validate(event)
        store.context.insert(try SyncJournalEntry(event:event))
    }
    func ingest(_ incoming: [SyncEvent]) throws {
        guard let config = try configuration() else { throw SyncError.invalid("동기화 폴더를 먼저 연결해 주세요.") }
        guard incoming.allSatisfy({$0.spaceID == config.spaceID}) else { throw SyncError.invalid("다른 공간의 데이터입니다.") }
        let existing = try events(), state = try SyncReducer.reduce(existing+incoming), known = Set(existing.map(\.id))
        store.syncApplying = true; defer { store.syncApplying = false }
        try store.transaction {
            var inserted = known
            for event in incoming where !inserted.contains(event.id) { store.context.insert(try SyncJournalEntry(event:event,published:true)); inserted.insert(event.id) }
            try StoreSyncBridge.apply(state,store:store)
        }
    }
    func appendLocal(_ event: SyncEvent) throws {
        guard event.spaceID == (try configuration())?.spaceID else { throw SyncError.invalid("CSV의 동기화 공간이 다릅니다.") }
        let existing = try events(); let state = try SyncReducer.reduce(existing+[event])
        if existing.contains(where:{$0.id == event.id}) { return }
        store.syncApplying = true; defer { store.syncApplying = false }
        try store.transaction { store.context.insert(try SyncJournalEntry(event:event)); try StoreSyncBridge.apply(state,store:store) }
    }
    func pendingEvents() throws -> [SyncEvent] { try entries().filter { !$0.published }.map { try SyncCoding.decode(SyncEvent.self,from:$0.data) } }
    func markPublished(ids: [UUID]) throws {
        let set = Set(ids); store.syncApplying = true; defer { store.syncApplying = false }
        try store.transaction { for entry in try entries() where set.contains(entry.id) { entry.published = true } }
    }
}
