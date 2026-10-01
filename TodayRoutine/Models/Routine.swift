import Foundation
import SwiftData

enum RepeatKind: String, Codable, CaseIterable { case daily, weekdays, weeklyGoal
    var label: String { switch self { case .daily: "매일"; case .weekdays: "요일 선택"; case .weeklyGoal: "주간 목표" } }
}
enum RoutineStatus: String, Codable, CaseIterable { case active, paused, archived
    var label: String { switch self { case .active: "활성"; case .paused: "일시정지"; case .archived: "보관됨" } }
}
enum DayStatus: String, Codable { case pending, completed, skipped }

@Model final class Routine {
    @Attribute(.unique) var id: UUID
    var name: String; var note: String; var repeatRaw: String; var weekdays: [Int]; var weeklyTarget: Int
    var minute: Int?; var groupID: UUID?; var sortOrder: Int; var statusRaw: String
    var createdAt: Date; var updatedAt: Date
    var repeatKind: RepeatKind { get { RepeatKind(rawValue: repeatRaw) ?? .daily } set { repeatRaw = newValue.rawValue } }
    var status: RoutineStatus { get { RoutineStatus(rawValue: statusRaw) ?? .active } set { statusRaw = newValue.rawValue } }
    init(id: UUID = UUID(), name: String, minute: Int? = nil, sortOrder: Int = 0) {
        self.id = id; self.name = name; self.note = ""; repeatRaw = "daily"; weekdays = []; weeklyTarget = 3
        self.minute = minute; self.sortOrder = sortOrder; statusRaw = "active"; createdAt = Date(); updatedAt = Date()
    }
}
@Model final class RoutineStep {
    @Attribute(.unique) var id: UUID
    var routineID: UUID; var name: String; var sortOrder: Int; var createdAt: Date; var updatedAt: Date
    init(id: UUID = UUID(), routineID: UUID, name: String, sortOrder: Int = 0) { self.id = id; self.routineID = routineID; self.name = name; self.sortOrder = sortOrder; createdAt = Date(); updatedAt = Date() }
}
@Model final class RoutineGroup {
    @Attribute(.unique) var id: UUID
    var name: String; var sortOrder: Int; var createdAt: Date; var updatedAt: Date
    init(name: String, sortOrder: Int = 0) { id = UUID(); self.name = name; self.sortOrder = sortOrder; createdAt = Date(); updatedAt = Date() }
}
