import Foundation

struct TodayDocumentBlock: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var text: String
    var children: [TodayDocumentBlock] = []
    var flattened: [Self] { [self] + children.flatMap(\.flattened) }
}
struct TodayDocumentSource: Codable, Equatable {
    enum Kind: String, Codable { case routine, step, block }
    var id: UUID
    var kind: Kind
    var parentID: UUID?
    var text: String
    var duration: Int = 30
    var sortOrder: Int = 0
}
struct TodayDocument: Codable, Equatable {
    var id = UUID()
    var dayKey: String
    var blocks: [TodayDocumentBlock] = []
    var appliedBlocks: [TodayDocumentBlock] = []
    var baseline: [TodayDocumentSource] = []
    // Links outlive deleted nodes so undo can restore the original source identity.
    var links: [TodayDocumentSource] = []
    var hiddenRoutineIDs: [UUID] = []
    var needsApply: Bool { blocks != appliedBlocks }
}
