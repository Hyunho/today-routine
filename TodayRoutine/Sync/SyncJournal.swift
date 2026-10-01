import Foundation
import SwiftData
@Model final class SyncJournalEntry {
    @Attribute(.unique) var id: UUID
    var data: Data; var published: Bool
    init(event: SyncEvent, published: Bool = false) throws { id = event.id; data = try SyncCoding.encode(event); self.published = published }
}
@Model final class SyncDeviceState {
    @Attribute(.unique) var key: String
    var spaceID: UUID; var deviceID: UUID; var enabled: Bool
    init(spaceID: UUID, deviceID: UUID) { key = "local"; self.spaceID = spaceID; self.deviceID = deviceID; enabled = true }
}
