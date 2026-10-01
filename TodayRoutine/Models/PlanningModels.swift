import Foundation
import SwiftData
@Model final class TaskItem {
    @Attribute(.unique) var id: UUID
    var title: String; var note: String; var dayKey: String?; var minute: Int?; var completedAt: Date?; var createdAt: Date; var updatedAt: Date
    init(id: UUID = UUID(), title: String, dayKey: String? = nil, minute: Int? = nil) { self.id = id; self.title = title; note = ""; self.dayKey = dayKey; self.minute = minute; createdAt = Date(); updatedAt = Date() }
}
@Model final class TimeBlock {
    @Attribute(.unique) var id: UUID
    var title: String; var dayKey: String; var startMinute: Int; var endMinute: Int; var linkedID: UUID?; var linkedKind: String?
    var createdAt: Date; var updatedAt: Date
    init(id: UUID = UUID(), title: String, dayKey: String, start: Int, end: Int) { self.id = id; self.title = title; self.dayKey = dayKey; startMinute = start; endMinute = end; createdAt = Date(); updatedAt = Date() }
}
@Model final class ReminderPreference {
    @Attribute(.unique) var routineID: UUID
    var id: UUID; var enabled: Bool; var minute: Int; var createdAt: Date; var updatedAt: Date
    init(routineID: UUID, enabled: Bool = false, minute: Int = 540) { id = UUID(); self.routineID = routineID; self.enabled = enabled; self.minute = minute; createdAt = Date(); updatedAt = Date() }
}
