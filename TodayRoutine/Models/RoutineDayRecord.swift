import Foundation
import SwiftData
@Model final class RoutineDayRecord {
    @Attribute(.unique) var key: String
    var id: UUID; var routineID: UUID; var dayKey: String; var statusRaw: String; var completedStepIDs: [UUID]
    var minuteOverride: Int? = nil
    var nameSnapshot: String; var completedAt: Date?; var createdAt: Date; var updatedAt: Date
    var status: DayStatus { get { DayStatus(rawValue: statusRaw) ?? .pending } set { statusRaw = newValue.rawValue } }
    init(routineID: UUID, dayKey: String, name: String) { id = UUID(); self.routineID = routineID; self.dayKey = dayKey; key = "\(routineID.uuidString)/\(dayKey)"; statusRaw = "pending"; completedStepIDs = []; nameSnapshot = name; createdAt = Date(); updatedAt = Date() }
}
