import Foundation
struct StepDraft: Identifiable { var id = UUID(); var name = "" }
struct RoutineDraft: Identifiable {
    var id = UUID(); var name = ""; var note = ""; var repeatKind: RepeatKind = .daily; var weekdays: [Int] = [2,3,4,5,6]
    var weeklyTarget = 3; var minute: Int?; var groupID: UUID?; var status: RoutineStatus = .active; var steps: [StepDraft] = []
    init() {}
    init(_ r: Routine, steps: [RoutineStep]) { id = r.id; name = r.name; note = r.note; repeatKind = r.repeatKind; weekdays = r.weekdays; weeklyTarget = r.weeklyTarget; minute = r.minute; groupID = r.groupID; status = r.status; self.steps = steps.filter { $0.routineID == r.id }.sorted { $0.sortOrder < $1.sortOrder }.map { StepDraft(id: $0.id, name: $0.name) } }
}
struct TaskDraft: Identifiable {
    var id = UUID(); var title = ""; var note = ""; var dayKey: String?; var minute: Int?
    init() {}
    init(_ task: TaskItem) { id = task.id; title = task.title; note = task.note; dayKey = task.dayKey; minute = task.minute }
}
struct BlockDraft: Identifiable {
    var id = UUID(); var title = ""; var dayKey: String = ""; var startMinute = 540; var endMinute = 600; var linkedID: UUID?; var linkedKind: String?
    init() {}
    init(_ block: TimeBlock) { id = block.id; title = block.title; dayKey = block.dayKey; startMinute = block.startMinute; endMinute = block.endMinute; linkedID = block.linkedID; linkedKind = block.linkedKind }
}
