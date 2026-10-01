import XCTest
final class SyncWorkflowTests: XCTestCase {
    func testLocalModeAndConnectedFolderStatus() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--uitest-store",UUID().uuidString]; app.launch()
        app.buttons["설정"].tap(); app.buttons.containing(.staticText,identifier:"iCloud Drive 폴더").firstMatch.tap()
        XCTAssertTrue(app.buttons["동기화 폴더 선택"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["기기에만 저장"].exists)
        app.terminate(); app.launchArguments += ["--uitest-sync"]; app.launch()
        app.buttons["설정"].tap(); app.buttons.containing(.staticText,identifier:"iCloud Drive 폴더").firstMatch.tap()
        XCTAssertTrue(app.buttons["연결 해제"].waitForExistence(timeout:8))
        XCTAssertTrue(app.staticTexts["폴더 저장 완료 · 상대 기기 확인 대기"].waitForExistence(timeout:8))
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "iPhone 자동 동기화 설정"; shot.lifetime = .keepAlways; add(shot)
    }
}
