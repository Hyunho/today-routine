import XCTest
final class SyncWorkflowTests: XCTestCase {
    func testCreateRoutineCompleteAndSyncSettings() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--uitest-store",UUID().uuidString,"--uitest-sync"]; app.launch()
        app.staticTexts["루틴"].click(); app.buttons["루틴 추가"].click()
        let name = app.textFields["루틴 이름"]; XCTAssertTrue(name.waitForExistence(timeout:5)); name.click(); name.typeText("맥 아침 독서")
        app.buttons["저장"].click()
        XCTAssertTrue(app.staticTexts["맥 아침 독서"].waitForExistence(timeout:5))
        app.staticTexts["오늘"].click(); app.buttons["맥 아침 독서 완료"].click()
        XCTAssertTrue(app.staticTexts["완료 1개"].waitForExistence(timeout:5))
        app.buttons["설정"].click(); app.buttons.containing(.staticText,identifier:"iCloud Drive 폴더").firstMatch.click()
        XCTAssertTrue(app.buttons["연결 해제"].waitForExistence(timeout:8))
        XCTAssertTrue(app.buttons["맥 아침 독서"].waitForExistence(timeout:8))
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "Mac 자동 동기화 설정"; shot.lifetime = .keepAlways; add(shot)
    }
}
