import Foundation
import SwiftData

@Model final class TodayDocumentRecord {
    @Attribute(.unique) var dayKey: String
    var payload: Data
    var revision: Int
    init(dayKey: String, payload: Data) { self.dayKey = dayKey; self.payload = payload; revision = 0 }
    var hiddenRoutineIDs: Set<UUID> { Set((try? JSONDecoder().decode(TodayDocument.self, from: payload).hiddenRoutineIDs) ?? []) }
}
