import XCTest

final class LogseqWorkflowTests: XCTestCase {
    func testTodayDocumentLivesInAdjacentLogseqTab() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-store", UUID().uuidString]
        app.launch()
        defer { app.terminate() }
        let today = app.buttons["오늘"].firstMatch
        let logseq = app.buttons["Logseq"].firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: 10))
        XCTAssertTrue(logseq.exists)
        XCTAssertLessThan(today.frame.midX, logseq.frame.midX)
        XCTAssertLessThan(logseq.frame.midX, app.buttons["일감"].firstMatch.frame.midX)
        XCTAssertFalse(app.buttons["오늘에 반영"].exists)
        logseq.click()
        XCTAssertTrue(app.buttons["오늘에 반영"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["원본 다시 읽기"].exists)
        XCTAssertFalse(app.textViews["Markdown 편집"].exists)
        today.click()
        XCTAssertTrue(today.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["오늘에 반영"].exists)
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.buttons["오늘에 반영"].waitForExistence(timeout: 5))
    }
}
