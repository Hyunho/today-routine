import Foundation
extension RoutineStore {
    func upsertTask(_ d: TaskDraft) throws {
        let title = d.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw StoreError.invalid("일감 제목을 입력해 주세요.") }
        guard d.dayKey == nil || RoutineRules.date(for: d.dayKey!) != nil, d.minute == nil || (d.dayKey != nil && (0..<1440).contains(d.minute!)) else { throw StoreError.invalid("날짜와 시간을 확인해 주세요.") }
        let s = try loadSnapshot(); try transaction {
            let t = s.tasks.first { $0.id == d.id } ?? TaskItem(id: d.id, title: title)
            if t.modelContext == nil { context.insert(t) }; t.title = title; t.note = d.note; t.dayKey = d.dayKey; t.minute = d.minute; t.updatedAt = Date()
        }
    }
    func setTaskCompleted(id: UUID, completed: Bool) throws {
        let s = try loadSnapshot(); try transaction { guard let t = s.tasks.first(where: { $0.id == id }) else { return }; t.completedAt = completed ? Date() : nil; t.updatedAt = Date() }
    }
    func deleteTask(id: UUID) throws {
        let s = try loadSnapshot(); try transaction {
            for b in s.blocks where b.linkedKind == "task" && b.linkedID == id { b.linkedID = nil; b.linkedKind = nil; b.updatedAt = Date() }
            for t in s.tasks where t.id == id { context.delete(t) }
        }
    }
    func upsertBlock(_ d: BlockDraft) throws {
        let title = d.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw StoreError.invalid("블록 제목을 입력해 주세요.") }
        guard RoutineRules.date(for: d.dayKey) != nil, (0..<1440).contains(d.startMinute), (0..<1440).contains(d.endMinute), d.endMinute > d.startMinute else { throw StoreError.invalid("종료 시간은 같은 날의 시작 시간 이후여야 합니다.") }
        let s = try loadSnapshot()
        if let id = d.linkedID { guard (d.linkedKind == "task" && s.tasks.contains { $0.id == id }) || (d.linkedKind == "routine" && s.routines.contains { $0.id == id }) else { throw StoreError.invalid("연결할 항목을 다시 선택해 주세요.") } }
        try transaction {
            let b = s.blocks.first { $0.id == d.id } ?? TimeBlock(id: d.id, title: title, dayKey: d.dayKey, start: d.startMinute, end: d.endMinute)
            if b.modelContext == nil { context.insert(b) }; b.title = title; b.dayKey = d.dayKey; b.startMinute = d.startMinute; b.endMinute = d.endMinute; b.linkedID = d.linkedID; b.linkedKind = d.linkedID == nil ? nil : d.linkedKind; b.updatedAt = Date()
        }
    }
    func deleteBlock(id: UUID) throws { let s = try loadSnapshot(); try transaction { for b in s.blocks where b.id == id { context.delete(b) } } }
    func overlaps(_ d: BlockDraft) throws -> Bool { try loadSnapshot().blocks.contains { $0.id != d.id && $0.dayKey == d.dayKey && d.startMinute < $0.endMinute && d.endMinute > $0.startMinute } }
}
