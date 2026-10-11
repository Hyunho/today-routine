import Foundation
import SwiftData
@MainActor enum StoreSyncBridge {
    static func objects(_ s: StoreSnapshot) throws -> [String:SyncObject] {
        var result: [String:SyncObject] = [:]
        for r in s.routines {
            var f: [String:String] = [:]
            f["name"] = r.name
            f["note"] = r.note
            f["repeatRaw"] = r.repeatRaw
            f["weekdays"] = r.weekdays.map(String.init).joined(separator:",")
            f["weeklyTarget"] = String(r.weeklyTarget)
            if let link = r.calendarLinkJSON { f["calendarLink"] = link }
            f["durationMinutes"] = r.durationMinutes.map(String.init) ?? ""
            f["minute"] = r.minute.map(String.init) ?? ""
            f["groupID"] = r.groupID?.uuidString ?? ""
            f["sortOrder"] = String(r.sortOrder)
            f["statusRaw"] = r.statusRaw
            f["createdAt"] = String(r.createdAt.timeIntervalSince1970)
            f["updatedAt"] = String(r.updatedAt.timeIntervalSince1970)
            let o = SyncObject(kind:.routine,id:r.id.uuidString,fields:f); result[o.key] = o
        }
        for r in s.steps {
            var f: [String:String] = [:]
            f["routineID"] = r.routineID.uuidString
            f["name"] = r.name
            f["sortOrder"] = String(r.sortOrder)
            f["createdAt"] = String(r.createdAt.timeIntervalSince1970)
            f["updatedAt"] = String(r.updatedAt.timeIntervalSince1970)
            let o = SyncObject(kind:.step,id:r.id.uuidString,fields:f); result[o.key] = o
        }
        for r in s.groups {
            var f: [String:String] = [:]
            f["name"] = r.name
            f["sortOrder"] = String(r.sortOrder)
            f["createdAt"] = String(r.createdAt.timeIntervalSince1970)
            f["updatedAt"] = String(r.updatedAt.timeIntervalSince1970)
            let o = SyncObject(kind:.group,id:r.id.uuidString,fields:f); result[o.key] = o
        }
        for r in s.tasks {
            var f: [String:String] = [:]
            f["title"] = r.title
            f["note"] = r.note
            f["dayKey"] = r.dayKey ?? ""
            f["minute"] = r.minute.map(String.init) ?? ""
            f["completedAt"] = r.completedAt.map { String($0.timeIntervalSince1970) } ?? ""
            f["createdAt"] = String(r.createdAt.timeIntervalSince1970)
            f["updatedAt"] = String(r.updatedAt.timeIntervalSince1970)
            let o = SyncObject(kind:.task,id:r.id.uuidString,fields:f); result[o.key] = o
        }
        for r in s.blocks {
            var f: [String:String] = [:]
            f["title"] = r.title
            f["dayKey"] = r.dayKey
            f["startMinute"] = String(r.startMinute)
            f["endMinute"] = String(r.endMinute)
            f["linkedID"] = r.linkedID?.uuidString ?? ""
            f["linkedKind"] = r.linkedKind ?? ""
            f["createdAt"] = String(r.createdAt.timeIntervalSince1970)
            f["updatedAt"] = String(r.updatedAt.timeIntervalSince1970)
            let o = SyncObject(kind:.block,id:r.id.uuidString,fields:f); result[o.key] = o
        }
        for r in s.records {
            let ids = Set(s.steps.filter { $0.routineID == r.routineID }.map { $0.id.uuidString }).union(r.completedStepIDs.map(\.uuidString))
            let names = Dictionary(uniqueKeysWithValues:s.steps.filter { $0.routineID == r.routineID }.map { ($0.id.uuidString,$0.name) })
            var f = ["routineID":r.routineID.uuidString,"dayKey":r.dayKey,"status":r.statusRaw,"stepIDs":ids.sorted().joined(separator:","),"nameSnapshot":r.nameSnapshot,"completedAt":r.completedAt.map { String($0.timeIntervalSince1970) } ?? "","createdAt":String(r.createdAt.timeIntervalSince1970),"updatedAt":String(r.updatedAt.timeIntervalSince1970),"stepNames":String(data:try SyncCoding.encode(names),encoding:.utf8)!]
            f["minuteOverride"] = r.minuteOverride.map(String.init) ?? ""
            for id in ids { f["step/"+id] = r.completedStepIDs.contains(where:{$0.uuidString == id}) ? "true":"false" }
            let o = SyncObject(kind:.record,id:r.key,fields:f); result[o.key] = o
        }
        return result
    }
    static func apply(_ state: SyncState, store: RoutineStore) throws {
        let s = try store.loadSnapshot()
        func routineDeleted(_ id: UUID) -> Bool { state.tombstones.contains("routine/" + id.uuidString) }

        for r in s.routines where state.tombstones.contains("routine/"+r.id.uuidString) { store.context.delete(r) }
        for reminder in s.reminders where routineDeleted(reminder.routineID) { store.context.delete(reminder) }
        for o in state.objects.values where o.kind == .routine {
            guard let id = UUID(uuidString:o.id) else { continue }; let f = o.fields
            let r = s.routines.first { $0.id == id } ?? Routine(id: id, name: f["name"] ?? "")
            if r.modelContext == nil { r.id = id; store.context.insert(r) }
            if f["name"] != nil { r.name = f["name"] ?? "" }
            if f["note"] != nil { r.note = f["note"] ?? "" }
            if f["repeatRaw"] != nil { r.repeatRaw = f["repeatRaw"] ?? "" }
            if f["weekdays"] != nil { r.weekdays = (f["weekdays"] ?? "").split(separator:",").compactMap { Int($0) } }
            if f["weeklyTarget"] != nil { r.weeklyTarget = Int(f["weeklyTarget"] ?? "") ?? 0 }
            if let link = f["calendarLink"] { r.calendarLinkJSON = link.isEmpty ? nil : link }
            if let duration = f["durationMinutes"] { r.durationMinutes = Int(duration) }
            if f["minute"] != nil { r.minute = Int(f["minute"] ?? "") }
            if f["groupID"] != nil { r.groupID = UUID(uuidString:f["groupID"] ?? "") }
            if f["sortOrder"] != nil { r.sortOrder = Int(f["sortOrder"] ?? "") ?? 0 }
            if f["statusRaw"] != nil { r.statusRaw = f["statusRaw"] ?? "" }
            if f["createdAt"] != nil { r.createdAt = Date(timeIntervalSince1970:Double(f["createdAt"] ?? "") ?? 0) }
            if f["updatedAt"] != nil { r.updatedAt = Date(timeIntervalSince1970:Double(f["updatedAt"] ?? "") ?? 0) }
            if let groupID = r.groupID, state.tombstones.contains("group/"+groupID.uuidString) { r.groupID = nil }
        }
        for r in s.steps where state.tombstones.contains("step/"+r.id.uuidString) || routineDeleted(r.routineID) { store.context.delete(r) }
        for o in state.objects.values where o.kind == .step {
            guard let id = UUID(uuidString:o.id) else { continue }; let f = o.fields
            if let routineID = f["routineID"].flatMap(UUID.init(uuidString:)), routineDeleted(routineID) { continue }
            let r = s.steps.first { $0.id == id } ?? RoutineStep(id: id, routineID: UUID(uuidString: f["routineID"] ?? "") ?? id, name: f["name"] ?? "")
            if r.modelContext == nil { r.id = id; store.context.insert(r) }
            if f["routineID"] != nil { r.routineID = UUID(uuidString:f["routineID"] ?? "") ?? id }
            if f["name"] != nil { r.name = f["name"] ?? "" }
            if f["sortOrder"] != nil { r.sortOrder = Int(f["sortOrder"] ?? "") ?? 0 }
            if f["createdAt"] != nil { r.createdAt = Date(timeIntervalSince1970:Double(f["createdAt"] ?? "") ?? 0) }
            if f["updatedAt"] != nil { r.updatedAt = Date(timeIntervalSince1970:Double(f["updatedAt"] ?? "") ?? 0) }
        }
        for r in s.groups where state.tombstones.contains("group/"+r.id.uuidString) { store.context.delete(r) }
        for o in state.objects.values where o.kind == .group {
            guard let id = UUID(uuidString:o.id) else { continue }; let f = o.fields
            let r = s.groups.first { $0.id == id } ?? RoutineGroup(name: f["name"] ?? "")
            if r.modelContext == nil { r.id = id; store.context.insert(r) }
            if f["name"] != nil { r.name = f["name"] ?? "" }
            if f["sortOrder"] != nil { r.sortOrder = Int(f["sortOrder"] ?? "") ?? 0 }
            if f["createdAt"] != nil { r.createdAt = Date(timeIntervalSince1970:Double(f["createdAt"] ?? "") ?? 0) }
            if f["updatedAt"] != nil { r.updatedAt = Date(timeIntervalSince1970:Double(f["updatedAt"] ?? "") ?? 0) }
        }
        for r in s.tasks where state.tombstones.contains("task/"+r.id.uuidString) { store.context.delete(r) }
        for o in state.objects.values where o.kind == .task {
            guard let id = UUID(uuidString:o.id) else { continue }; let f = o.fields
            let r = s.tasks.first { $0.id == id } ?? TaskItem(id: id, title: f["title"] ?? "")
            if r.modelContext == nil { r.id = id; store.context.insert(r) }
            if f["title"] != nil { r.title = f["title"] ?? "" }
            if f["note"] != nil { r.note = f["note"] ?? "" }
            if f["dayKey"] != nil { r.dayKey = (f["dayKey"] ?? "").isEmpty ? nil : f["dayKey"] }
            if f["minute"] != nil { r.minute = Int(f["minute"] ?? "") }
            if f["completedAt"] != nil { r.completedAt = Double(f["completedAt"] ?? "").map { Date(timeIntervalSince1970:$0) } }
            if f["createdAt"] != nil { r.createdAt = Date(timeIntervalSince1970:Double(f["createdAt"] ?? "") ?? 0) }
            if f["updatedAt"] != nil { r.updatedAt = Date(timeIntervalSince1970:Double(f["updatedAt"] ?? "") ?? 0) }
        }
        for r in s.blocks where state.tombstones.contains("block/"+r.id.uuidString) { store.context.delete(r) }
        for o in state.objects.values where o.kind == .block {
            guard let id = UUID(uuidString:o.id) else { continue }; let f = o.fields
            let r = s.blocks.first { $0.id == id } ?? TimeBlock(id: id, title: f["title"] ?? "", dayKey: f["dayKey"] ?? "", start: Int(f["startMinute"] ?? "") ?? 0, end: Int(f["endMinute"] ?? "") ?? 1)
            if r.modelContext == nil { r.id = id; store.context.insert(r) }
            if f["title"] != nil { r.title = f["title"] ?? "" }
            if f["dayKey"] != nil { r.dayKey = f["dayKey"] ?? "" }
            if f["startMinute"] != nil { r.startMinute = Int(f["startMinute"] ?? "") ?? 0 }
            if f["endMinute"] != nil { r.endMinute = Int(f["endMinute"] ?? "") ?? 0 }
            if f["linkedID"] != nil { r.linkedID = UUID(uuidString:f["linkedID"] ?? "") }
            if f["linkedKind"] != nil { r.linkedKind = (f["linkedKind"] ?? "").isEmpty ? nil : f["linkedKind"] }
            if f["createdAt"] != nil { r.createdAt = Date(timeIntervalSince1970:Double(f["createdAt"] ?? "") ?? 0) }
            if f["updatedAt"] != nil { r.updatedAt = Date(timeIntervalSince1970:Double(f["updatedAt"] ?? "") ?? 0) }
            guard r.endMinute > r.startMinute else { throw SyncError.invalid("동기화된 블록 시간이 올바르지 않습니다.") }
            if let linked = r.linkedID, state.tombstones.contains((r.linkedKind ?? "")+"/"+linked.uuidString) { r.linkedID = nil; r.linkedKind = nil }
        }
        for r in s.records where state.tombstones.contains("record/" + r.key) || routineDeleted(r.routineID) { store.context.delete(r) }
        for o in state.objects.values where o.kind == .record {
            let parts = o.id.split(separator:"/"); guard parts.count == 2, let id = UUID(uuidString:String(parts[0])) else { continue }
            guard !routineDeleted(id) else { continue }
            let f = o.fields, key = String(parts[1])
            let r = s.records.first { $0.key == o.id } ?? RoutineDayRecord(routineID:id,dayKey:key,name:f["nameSnapshot"] ?? "")
            if r.modelContext == nil { store.context.insert(r) }
            if let minute = f["minuteOverride"] { r.minuteOverride = Int(minute) }
            r.statusRaw = f["status"] ?? "pending"; r.nameSnapshot = f["nameSnapshot"] ?? r.nameSnapshot
            r.completedStepIDs = f.filter { $0.key.hasPrefix("step/") && $0.value == "true" }.compactMap { UUID(uuidString:String($0.key.dropFirst(5))) }
            r.completedAt = Double(f["completedAt"] ?? "").map { Date(timeIntervalSince1970:$0) }
            r.createdAt = Date(timeIntervalSince1970:Double(f["createdAt"] ?? "") ?? 0)
            r.updatedAt = Date(timeIntervalSince1970:Double(f["updatedAt"] ?? "") ?? 0)
        }
    }
}
