import XCTest
@testable import RoutineCore

final class SyncFolderAccessTests: XCTestCase {
    @MainActor func testRestoresOrdinaryBookmarkFromLocalMacBuild() throws {
        let suite = "sync-bookmark-test-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let data = try folder.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(data, forKey: "routine.sync.bookmark")
        let access = SyncFolderAccess(defaults: defaults)
        XCTAssertEqual(try access.restore()?.resolvingSymlinksInPath(), folder.resolvingSymlinksInPath())
    }

    @MainActor func testDamagedBookmarkIsNotReplacedOrSilentlyAccepted() throws {
        let suite = "sync-bookmark-test-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let data = Data("damaged bookmark".utf8)
        defaults.set(data, forKey: "routine.sync.bookmark")
        XCTAssertThrowsError(try SyncFolderAccess(defaults: defaults).restore())
        XCTAssertEqual(defaults.data(forKey: "routine.sync.bookmark"), data)
    }
}
