import XCTest
@testable import RoutineCore

final class CloudTransferTests: XCTestCase {
    func testLocalFolderDoesNotPretendToUploadOrModifyFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("user.csv")
        let bytes = Data("사용자가 수정한 내용".utf8)
        try bytes.write(to: file)
        let transport = SyncFolderTransport(root: root)
        let report = try await transport.requestCloudTransfer(upload: true, deviceID: UUID())
        XCTAssertFalse(report.isCloud)
        XCTAssertEqual(report.uploadsRequested, 0)
        XCTAssertTrue(report.summary.contains("로컬 폴더"))
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }
    func testReportDistinguishesServerUploadFromPeerApplicationAndUnknownState() {
        var report = CloudTransferReport()
        report.isCloud = true; report.files = 3; report.uploaded = 1
        report.uploadPending = 1; report.uploadUnknown = 1; report.downloadsRequested = 1
        XCTAssertTrue(report.summary.contains("iCloud 업로드 확인 1개"))
        XCTAssertTrue(report.summary.contains("대기 1개"))
        XCTAssertTrue(report.summary.contains("상태 확인 중 1개"))
        XCTAssertTrue(report.summary.contains("직접 업로드 제어 미지원"))
        XCTAssertTrue(report.summary.contains("다른 기기의 적용 여부"))
        XCTAssertFalse(report.summary.contains("동기화 완료"))
    }
}
