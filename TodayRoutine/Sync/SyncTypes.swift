import Foundation
import CryptoKit

enum SyncKind: String, Codable, CaseIterable { case routine, step, group, record, task, block }
struct SyncObject: Codable, Equatable {
    var kind: SyncKind; var id: String; var fields: [String:String]
    var key: String { "\(kind.rawValue)/\(id)" }
}
struct SyncOperation: Codable, Equatable {
    var kind: SyncKind; var id: String; var values: [String:String] = [:]; var deleted = false
    var key: String { "\(kind.rawValue)/\(id)" }
}
struct SyncEvent: Codable, Equatable, Identifiable {
    var version = 1; var spaceID: UUID; var id: UUID; var deviceID: UUID; var counter: Int64; var createdAt: Date
    var operations: [SyncOperation]
    var order: String { String(format: "%020lld", counter) + "/" + deviceID.uuidString + "/" + id.uuidString }
}
struct SyncState: Codable, Equatable {
    var objects: [String:SyncObject] = [:]
    var tombstones: Set<String> = []
    var versions: [String:String] = [:]
    var counter: Int64 = 0
    func version(_ key: String, _ field: String) -> String { versions[key + "/" + field] ?? "" }
}
enum SyncError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { switch self { case .invalid(let message): message } }
}
enum SyncCoding {
    static func encode<T: Encodable>(_ value: T) throws -> Data { let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; e.dateEncodingStrategy = .millisecondsSince1970; return try e.encode(value) }
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T { let d = JSONDecoder(); d.dateDecodingStrategy = .millisecondsSince1970; return try d.decode(type, from: data) }
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func stableID(_ text: String) -> UUID { let h = hash(Data(text.utf8)); return UUID(uuidString: "\(h.prefix(8))-\(h.dropFirst(8).prefix(4))-\(h.dropFirst(12).prefix(4))-\(h.dropFirst(16).prefix(4))-\(h.dropFirst(20).prefix(12))")! }
}
