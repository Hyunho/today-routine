import XCTest
@testable import RoutineCore
final class SyncTransportTests: XCTestCase {
    func testImmutableEventsAndCSVAndInterruptedFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let transport = SyncFolderTransport(root:root)
        let space = try await transport.open()
        let e = SyncEvent(spaceID:space,id:UUID(),deviceID:UUID(),counter:1,createdAt:Date(timeIntervalSince1970:0),operations:[SyncOperation(kind:.routine,id:UUID().uuidString,values:["name":"아침"])])
        try await transport.publish([e]); try await transport.publish([e])
        try Data("partial".utf8).write(to:root.appendingPathComponent("incomplete.tmp"))
        let batch = try await transport.readBatch()
        XCTAssertEqual(batch.events,[e])
        var bad = e; bad.operations[0].values["name"] = "다른 내용"
        do { try await transport.publish([bad]); XCTFail("must reject different contents") } catch {}
        let state = try SyncReducer.reduce([e])
        let doc = try RoutineCSVDocument.make(routineID:UUID(uuidString:e.operations[0].id)!,spaceID:space,state:state,today:Date())
        let url = try await transport.publishCSV(doc,deviceID:e.deviceID)
        try Data("날짜,완료\n2026-10-02,TRUE\n".utf8).write(to:url)
        _ = try await transport.publishCSV(doc,deviceID:e.deviceID)
        XCTAssertTrue(try String(contentsOf:url).contains("TRUE"))
        let after = try await transport.readBatch()
        XCTAssertEqual(after.documents.count,1)
    }
    func testUnknownVersionAndEscapingSymlinkRejected() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        try Data("{\"version\":99,\"spaceID\":\"\(UUID())\"}".utf8).write(to:root.appendingPathComponent("space.json"))
        do { _ = try await SyncFolderTransport(root:root).open(); XCTFail() } catch {}
        try FileManager.default.removeItem(at:root.appendingPathComponent("space.json"))
        let transport = SyncFolderTransport(root:root); let space = try await transport.open()
        try FileManager.default.createSymbolicLink(at:root.appendingPathComponent("changes"),withDestinationURL:FileManager.default.temporaryDirectory)
        let e = SyncEvent(spaceID:space,id:UUID(),deviceID:UUID(),counter:1,createdAt:Date(),operations:[SyncOperation(kind:.routine,id:UUID().uuidString,values:["name":"x"])])
        do { try await transport.publish([e]); XCTFail() } catch {}
    }
}
