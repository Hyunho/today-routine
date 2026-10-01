import Foundation
enum SyncReducer {
    static func reduce(_ events: [SyncEvent], initial: SyncState = SyncState()) throws -> SyncState {
        var unique: [UUID:SyncEvent] = [:]
        let space = events.first?.spaceID
        for event in events {
            try SyncValidation.validate(event)
            guard event.spaceID == space else { throw SyncError.invalid("서로 다른 동기화 폴더의 변경입니다.") }
            if let old = unique[event.id], old != event { throw SyncError.invalid("같은 변경 ID의 내용이 다릅니다.") }
            unique[event.id] = event
        }
        var state = initial
        for event in unique.values.sorted(by: { $0.order < $1.order }) {
            state.counter = max(state.counter,event.counter)
            for op in event.operations {
                if op.deleted { state.objects.removeValue(forKey:op.key); state.tombstones.insert(op.key); continue }
                guard !state.tombstones.contains(op.key) else { continue }
                var object = state.objects[op.key] ?? SyncObject(kind:op.kind,id:op.id,fields:[:])
                for (field,value) in op.values where field != "command" { object.fields[field] = value; state.versions[op.key+"/"+field] = event.order }
                if op.kind == .record {
                    let valid = (object.fields["stepIDs"] ?? "").split(separator:",").map(String.init)
                    if let command = op.values["command"] {
                        object.fields["status"] = command
                        for id in valid { object.fields["step/"+id] = command == "completed" ? "true":"false"; state.versions[op.key+"/step/"+id] = event.order }
                        state.versions[op.key+"/status"] = event.order
                    } else if op.values["status"] == nil && (op.values.keys.contains(where:{$0.hasPrefix("step/")}) || op.values["stepIDs"] != nil) {
                        if !valid.isEmpty { object.fields["status"] = valid.allSatisfy { object.fields["step/"+$0] == "true" } ? "completed":"pending" }
                        if op.values.keys.contains(where:{$0.hasPrefix("step/")}) { state.versions[op.key+"/status"] = event.order }
                    }
                    object.fields["completedAt"] = object.fields["status"] == "completed" ? (object.fields["completedAt"].flatMap { $0.isEmpty ? nil:$0 } ?? String(event.createdAt.timeIntervalSince1970)) : ""
                }
                state.objects[op.key] = object
            }
        }
        return state
    }
}
